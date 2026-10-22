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
/// The saved login is read for every call. The password and the
/// Authorization header never go into an exception or a log: SOAP errors
/// become [ParseError]/[EwsError] carrying only Exchange's ResponseCode, and
/// network errors are rethrown as [DioException] with the header removed.
class EwsClient implements MailApi {
  EwsClient(this._dio, this._credentials, {this.endpoint = defaultEndpoint});

  static const defaultEndpoint = 'https://mail.inha.uz/EWS/Exchange.asmx';

  final Dio _dio;
  final CredentialStore _credentials;
  final String endpoint;

  String? _savedUser; // the saved username [_login] was worked out for
  String? _login; // the form of it the server accepted, so later calls try only that
  bool _preview = true; // false once the server turned down item:Preview

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
  Future<List<MailHeader>> inbox({int limit = 30, int offset = 0}) async {
    if (_preview) {
      try {
        return parseFindItem(await _call(findInboxEnvelope(limit: limit, offset: offset)));
      } on EwsError catch (e) {
        if (!previewRejectionCodes.contains(e.code)) rethrow;
      }
    }
    final headers = parseFindItem(
        await _call(findInboxEnvelope(limit: limit, offset: offset, withPreview: false)));
    _preview = false; // worked without item:Preview: stop asking for it
    return headers;
  }

  @override
  Future<MailMessage> message(String id) async => parseMessage(await _call(getItemEnvelope(id)));

  @override
  Future<void> markRead(String id, {bool read = true}) async =>
      parseUpdateItem(await _call(setReadEnvelope(id, read: read)));

  @override
  Future<int> unreadCount() async => parseGetFolder(await _call(getInboxFolderEnvelope()));

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
    final known = _login;
    for (final login in known != null ? [known] : loginCandidates(user)) {
      final res = await _post(envelope, login, saved.password);
      final status = res.statusCode ?? 0;
      if (status == 401) continue;
      final text = utf8.decode(res.data ?? const <int>[], allowMalformed: true);
      if (status == 200) {
        _login = login;
        return text;
      }
      if (status == 500) _login = login; // SOAP faults come after authentication
      throw ewsFault(text) ?? ParseError('mail (HTTP $status)');
    }
    _login = null;
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
