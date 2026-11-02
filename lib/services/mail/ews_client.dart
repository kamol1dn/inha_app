import 'dart:async';
import 'dart:convert';

import 'package:dio/dio.dart';

import '../../core/credentials.dart';
import '../../core/session.dart';
import '../../models/models.dart';
import 'ews_soap.dart';
import 'mail_api.dart';

/// [MailApi] over Exchange Web Services with Basic auth over HTTPS
/// (docs/ENDPOINTS.md, Mail). Pass `Sessions.client(Service.mail)` as the Dio.
///
/// The saved login is read for every call. A login Exchange answered 401 to is
/// not sent again ([CredentialStore.isRefused]) and, until a login is known to
/// work, parallel calls wait for the first one's answer, so a wrong password
/// costs one failed logon however many requests a refresh makes.
///
/// The password and the Authorization header never go into an exception or a
/// log: SOAP errors become [ParseError]/[EwsError] carrying only Exchange's
/// ResponseCode, and network errors are rethrown as [DioException] with the
/// header removed.
class EwsClient implements MailApi {
  EwsClient(this._dio, this._credentials, {this.endpoint = defaultEndpoint});

  static const defaultEndpoint = 'https://mail.inha.uz/EWS/Exchange.asmx';

  final Dio _dio;
  final CredentialStore _credentials;
  final String endpoint;

  String? _savedUser; // the saved username [_login] was worked out for
  String? _login; // the form of it the server accepted, so later calls try only that
  bool _preview = true; // false once the server turned down item:Preview
  (String, String)? _trusted; // the saved login Exchange last let in
  Future<void>? _firstCall; // the call trying a login not known to work yet

  /// NetBIOS domain of the IUT mail server, from its NTLM challenge
  /// (INHA / INHA.local). OWA's form login adds it for you; EWS Basic auth does not.
  static const windowsDomain = 'INHA';

  /// The username to send. Students save their bare ID, which becomes
  /// `INHA\<id>`; anything already qualified (`DOMAIN\user`, `user@domain`)
  /// is sent as is. Only one form is ever tried, so a wrong password costs one
  /// failed logon against the domain's lockout counter, not several.
  static List<String> loginCandidates(String saved) {
    final user = saved.trim();
    if (user.isEmpty) return const [];
    if (user.contains(r'\') || user.contains('@')) return [user];
    return ['$windowsDomain\\$user'];
  }

  @override
  Future<List<MailHeader>> folder(MailFolder folder, {int limit = 30, int offset = 0}) =>
      _find(folder, limit: limit, offset: offset);

  @override
  Future<List<MailHeader>> search(MailFolder folder, String query, {int limit = 30, int offset = 0}) async {
    final q = query.trim();
    return q.isEmpty ? const [] : _find(folder, limit: limit, offset: offset, query: q);
  }

  Future<List<MailHeader>> _find(MailFolder folder, {required int limit, required int offset, String? query}) async {
    if (_preview) {
      try {
        return parseFindItem(await _call(findItemsEnvelope(folder: folder, limit: limit, offset: offset, query: query)));
      } on EwsError catch (e) {
        if (!previewRejectionCodes.contains(e.code)) rethrow;
      }
    }
    final headers = parseFindItem(await _call(
        findItemsEnvelope(folder: folder, limit: limit, offset: offset, query: query, withPreview: false)));
    _preview = false; // worked without item:Preview: stop asking for it
    return headers;
  }

  @override
  Future<MailMessage> message(String id) async => parseMessage(await _call(getItemEnvelope(id)));

  @override
  Future<MailFile> attachment(String id) async => parseAttachment(await _call(getAttachmentEnvelope(id)));

  @override
  Future<void> markRead(String id, {bool read = true}) async =>
      parseUpdateItem(await _call(setReadEnvelope(id, read: read)));

  @override
  Future<int> unreadCount() async => parseGetFolder(await _call(getInboxFolderEnvelope()));

  @override
  Future<Map<MailFolder, MailFolderCount>> folderCounts() async =>
      parseFolderCounts(await _call(getFolderCountsEnvelope()));

  @override
  Future<void> send(OutgoingMail m) async {
    if (m.kind != ComposeKind.draft && m.attachments.isEmpty) {
      parseItemId(await _call(createItemEnvelope(m, send: true)), 'CreateItem');
      return;
    }
    // A file goes on a saved message, so a new message with files is saved as a
    // draft first. If a step fails, what was written so far stays in Drafts.
    // Sending needs the draft's current change key, which every write moves on.
    final (id, changeKey) = await _saved(m);
    parseSendItem(await _call(sendItemEnvelope(id, changeKey)));
  }

  @override
  Future<void> saveDraft(OutgoingMail m) async {
    await _saved(m);
  }

  /// Writes [m] to Drafts with its files, and returns the draft's id and change
  /// key. A draft with nothing new keeps both.
  Future<(String, String)> _saved(OutgoingMail m) async {
    var (id, changeKey) = (m.ref?.id ?? '', m.ref?.changeKey ?? '');
    if (m.kind != ComposeKind.draft) {
      final made = parseItemId(await _call(createItemEnvelope(m, send: false)), 'CreateItem');
      if (made == null) throw ParseError('mail (CreateItem)');
      (id, changeKey) = made;
    } else if (draftChanges(m)) {
      (id, changeKey) = parseItemId(await _call(updateDraftEnvelope(m)), 'UpdateItem') ?? (id, changeKey);
    }
    for (final file in m.attachments) {
      changeKey = parseCreateAttachment(await _call(createAttachmentEnvelope(id, changeKey, file))) ?? changeKey;
    }
    return (id, changeKey);
  }

  @override
  Future<String?> move(String id, MailFolder to) async =>
      parseItemId(await _call(moveItemEnvelope(id, to)), 'MoveItem')?.$1;

  @override
  Future<List<MailAddress>> lookup(String query) async => parseResolveNames(await _call(resolveNamesEnvelope(query)));

  /// POSTs [envelope] and returns the SOAP response text.
  Future<String> _call(String envelope) async {
    final saved = await _credentials.read(Service.mail);
    final user = saved?.username.trim() ?? '';
    if (saved == null || user.isEmpty || saved.password.isEmpty) {
      throw LoginRequired(Service.mail);
    }
    if (user != _savedUser) {
      _savedUser = user;
      _login = null;
    }
    if (await _credentials.isRefused(Service.mail, saved)) {
      throw LoginRequired(Service.mail, 'Wrong username or password');
    }
    if (_trusted == (user, saved.password)) return _send(envelope, user, saved);

    // Not known to work yet: one call tries it, the others wait for its answer
    // and then ask again.
    if (_firstCall case final first?) {
      await first;
      return _call(envelope);
    }
    final answered = Completer<void>();
    _firstCall = answered.future;
    try {
      return await _send(envelope, user, saved);
    } finally {
      _firstCall = null;
      answered.complete();
    }
  }

  Future<String> _send(String envelope, String user, Credentials saved) async {
    final known = _login;
    for (final login in known != null ? [known] : loginCandidates(user)) {
      final res = await _post(envelope, login, saved.password);
      final status = res.statusCode ?? 0;
      if (status == 401) continue;
      final text = utf8.decode(res.data ?? const <int>[], allowMalformed: true);
      _trusted = (user, saved.password); // anything but a 401 got past authentication
      if (status == 200) {
        _login = login;
        return text;
      }
      if (status == 500) _login = login; // SOAP faults come after authentication
      throw ewsFault(text) ?? ParseError('mail (HTTP $status)');
    }
    _login = null;
    _trusted = null;
    await _credentials.markRefused(Service.mail, saved);
    throw LoginRequired(Service.mail, 'Wrong username or password');
  }

  Future<Response<List<int>>> _post(String envelope, String login, String password) async {
    try {
      return await _dio.post<List<int>>(
        endpoint,
        data: envelope,
        options: Options(
          contentType: 'text/xml; charset=utf-8',
          responseType: ResponseType.bytes,
          headers: {
            'Accept': 'text/xml',
            'Authorization': 'Basic ${base64Encode(utf8.encode('$login:$password'))}',
          },
          followRedirects: false,
          validateStatus: (_) => true, // 401 and SOAP faults (500) are handled above
        ),
      );
    } on DioException catch (e) {
      _scrub(e.requestOptions);
      final response = e.response;
      if (response != null) _scrub(response.requestOptions);
      rethrow;
    }
  }

  static void _scrub(RequestOptions options) =>
      options.headers.removeWhere((key, _) => key.toLowerCase() == 'authorization');
}
