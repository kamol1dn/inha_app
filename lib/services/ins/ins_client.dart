import 'dart:async';

import 'package:dio/dio.dart';

import '../../core/credentials.dart';
import '../../core/session.dart';
import '../../models/models.dart';
import 'ins_api.dart';
import 'ins_parsers.dart';

/// INS / ITIS over plain HTTP, the way a browser does it: WebForms login
/// post, then the frameset menu down to the grades XML. See docs/ENDPOINTS.md.
///
/// Redirects are followed by hand (never by the HTTP client) so the cookie
/// manager sees every hop's `Set-Cookie`, and so a bounce to Start.aspx is
/// visible. Every request stays on [base]'s origin.
class InsClient implements InsApi {
  /// Production: the INS Dio from [Sessions] (persistent cookies).
  InsClient(Sessions sessions, CredentialStore credentials, {Uri? base})
      : this._(() => sessions.client(Service.ins), credentials, base);

  /// Tests or custom setups: a Dio that already has a cookie manager.
  InsClient.withDio(Dio dio, CredentialStore credentials, {Uri? base})
      : this._(() => dio, credentials, base);

  InsClient._(this._dio, this._credentials, Uri? base) : base = base ?? defaultBase;

  static final Uri defaultBase = Uri.parse('https://ins.inha.uz/ITIS/');

  /// Menu text in left.aspx.
  static const gradesMenu = 'View Grades and Standings';

  /// Known location of the report frame, tried directly once main.aspx has
  /// been visited if the page chain did not lead there.
  static const rpxPath = 'STD/SJ/SJ_51001/MarkView_rpx.aspx?gubun=inform';

  static const _maxRedirects = 6;
  static const _maxFrameHops = 4;

  /// The ITIS root, e.g. `https://ins.inha.uz/ITIS/` (trailing slash matters).
  final Uri base;
  final Dio Function() _dio;
  final CredentialStore _credentials;
  Future<void>? _loginInFlight;

  Uri get _startUri => base.resolve('Start.aspx');
  Uri get _framesetUri => base.resolve('FRAMESET.htm');
  Uri get _leftUri => base.resolve('left.aspx');

  // -------------------------------------------------------------------------
  // InsApi
  // -------------------------------------------------------------------------

  @override
  Future<void> ensureLoggedIn() async {
    final left = await _get(_leftUri, referer: _framesetUri);
    if (hasMenuLinks(left.body) && !isInsLoginPage(left.body)) return;
    await _login();
  }

  @override
  Future<GradeReport> grades() async {
    try {
      return await _gradesOnce(afterLogin: false);
    } on _SessionExpired {
      await _login();
    }
    try {
      return await _gradesOnce(afterLogin: true);
    } on _SessionExpired {
      throw LoginRequired(Service.ins, 'INS ended the session right after login');
    }
  }

  // -------------------------------------------------------------------------
  // Login
  // -------------------------------------------------------------------------

  /// One login at a time; concurrent callers share it.
  Future<void> _login() =>
      _loginInFlight ??= _doLogin().whenComplete(() => _loginInFlight = null);

  Future<void> _doLogin() async {
    final creds = await _credentials.read(Service.ins);
    if (creds == null || creds.username.trim().isEmpty || creds.password.isEmpty) {
      throw LoginRequired(Service.ins, 'No INS login saved');
    }

    final start = await _get(_startUri);
    if (!isInsLoginPage(start.body)) {
      if (_isFrameset(start)) return; // INS still considers us logged in
      throw ParseError('INS login page${start.statusSuffix}');
    }

    final fields = hiddenInputs(start.body)
      ..['txtInhaID'] = creds.username.trim().toUpperCase()
      ..['txtPW'] = creds.password
      ..['btnLogin'] = ''; // the clicked submit's name must be present
    final actionRef = formAction(start.body);
    final action = _sameOrigin(actionRef == null ? start.uri : start.uri.resolve(actionRef));

    final r = await _dio().postUri<List<int>>(
      action,
      data: fields,
      options: _options(referer: start.uri, contentType: Headers.formUrlEncodedContentType),
    );
    final next = _redirectTarget(action, r);
    final page = next == null ? _Page.of(action, r) : await _get(next, referer: action);

    if (_loginSucceeded(page)) return;
    if (page.status >= 400 && !isInsLoginPage(page.body)) {
      throw ParseError('INS login response${page.statusSuffix}');
    }
    throw LoginRequired(Service.ins, loginError(page.body) ?? 'INS did not accept the ID or password');
  }

  /// Success = INS sends us to FRAMESET.htm (redirect, frameset, or script),
  /// or at least not back to the login form.
  bool _loginSucceeded(_Page page) {
    if (page.status >= 400) return false;
    if (isInsLoginPage(page.body)) return false;
    if (_isFrameset(page) || page.body.toLowerCase().contains('frameset.htm')) return true;
    return !isSessionExpired(page.body);
  }

  bool _isFrameset(_Page page) =>
      page.uri.path.toLowerCase().endsWith('/frameset.htm') ||
      page.body.toLowerCase().contains('<frameset');

  // -------------------------------------------------------------------------
  // Grades chain
  // -------------------------------------------------------------------------

  Future<GradeReport> _gradesOnce({required bool afterLogin}) async {
    // 1. Menu.
    final left = await _get(_leftUri, referer: _framesetUri);
    final link = findMenuLink(left.body, gradesMenu, base: base.path);
    if (link == null) {
      // A missing menu before any login most likely means "logged out" in a
      // shape we do not recognise; after a fresh login it means the page changed.
      if (isSessionExpired(left.body) || (!afterLogin && !hasMenuLinks(left.body))) {
        throw const _SessionExpired();
      }
      throw ParseError('INS menu ($gradesMenu)${left.statusSuffix}');
    }

    // 2. main.aspx?param=... -> MarkView.aspx -> MarkView_rpx.aspx -> fileurl.
    final (xmlUri, rpxUri) = await _findXmlUrl(_sameOrigin(base.resolve(link)), left.uri);

    // 3. The XML itself.
    final r = await _dio().postUri<List<int>>(
      xmlUri,
      data: '', // empty body, explicit Content-Length: 0
      options: _options(referer: rpxUri, contentType: Headers.formUrlEncodedContentType),
    );
    final redirect = _redirectTarget(xmlUri, r);
    if (redirect != null) {
      final page = await _get(redirect, referer: rpxUri);
      if (isSessionExpired(page.body)) throw const _SessionExpired();
      throw ParseError('INS grades (redirected)');
    }
    final page = _Page.of(xmlUri, r);
    try {
      return parseGrades(page.body);
    } on ParseError {
      if (isSessionExpired(page.body)) throw const _SessionExpired();
      if (page.status != 200) throw ParseError('INS grades${page.statusSuffix}');
      rethrow;
    }
  }

  /// Walks from the menu target down the frames until a page assigns
  /// `fileurl`. main.aspx may redirect, be a frameset, or bounce by script;
  /// MarkView.aspx iframes the rpx page. If that leads nowhere, the known rpx
  /// URL is tried directly (the server likely only needs the menu visit).
  /// Returns (xml url, rpx page url).
  Future<(Uri, Uri)> _findXmlUrl(Uri menuTarget, Uri referer) async {
    final visited = <String>{menuTarget.toString()};
    var page = await _get(menuTarget, referer: referer);
    visited.add(page.uri.toString());

    for (var hop = 0;; hop++) {
      final xml = extractXmlUrl(page.body);
      if (xml != null) return (_sameOrigin(page.uri.resolve(xml)), page.uri);
      final next = hop < _maxFrameHops ? _nextFrame(page, visited) : null;
      if (next == null) break;
      final parent = page.uri;
      visited.add(next.toString());
      page = await _get(next, referer: parent);
      visited.add(page.uri.toString());
    }

    final direct = base.resolve(rpxPath);
    if (!visited.contains(direct.toString())) {
      final rpx = await _get(direct, referer: base.resolve('STD/SJ/SJ_51001/MarkView.aspx'));
      final xml = extractXmlUrl(rpx.body);
      if (xml != null) return (_sameOrigin(rpx.uri.resolve(xml)), rpx.uri);
      page = rpx;
    }
    if (isSessionExpired(page.body)) throw const _SessionExpired();
    throw ParseError('INS grades page${page.statusSuffix}');
  }

  /// The next page toward the report: a MarkView_rpx reference first, then
  /// any MarkView reference, skipping pages already loaded.
  Uri? _nextFrame(_Page page, Set<String> visited) {
    for (final hint in const ['markview_rpx', 'markview']) {
      for (final ref in pageRefs(page.body, hint)) {
        final uri = _sameOrigin(page.uri.resolve(ref));
        if (!visited.contains(uri.toString())) return uri;
      }
    }
    return null;
  }

  // -------------------------------------------------------------------------
  // HTTP
  // -------------------------------------------------------------------------

  Options _options({Uri? referer, String? contentType}) => Options(
        responseType: ResponseType.bytes,
        followRedirects: false,
        validateStatus: (_) => true,
        contentType: contentType,
        headers: {if (referer != null) 'Referer': referer.toString()},
      );

  /// GET, following redirects by hand. The result carries the final URL.
  Future<_Page> _get(Uri uri, {Uri? referer}) async {
    var current = uri;
    for (var hop = 0; hop <= _maxRedirects; hop++) {
      final r = await _dio().getUri<List<int>>(current, options: _options(referer: referer));
      final next = _redirectTarget(current, r);
      if (next == null) return _Page.of(current, r);
      current = next;
    }
    throw ParseError('INS (too many redirects)');
  }

  /// Redirects are pinned to INS too: the server sometimes answers with its
  /// internal name (http://ins.iutdev.ac.kr/...), which doesn't resolve outside
  /// IUT's network. Browsers never see it because the frameset links are relative.
  Uri? _redirectTarget(Uri from, Response<dynamic> r) {
    final status = r.statusCode ?? 0;
    if (status < 300 || status >= 400) return null;
    final location = r.headers['location']?.first.trim();
    if (location == null || location.isEmpty) return null;
    return _sameOrigin(from.resolve(location));
  }

  /// Pins [uri] to [base]'s scheme/host/port: links and the XML url come from
  /// page content, and the app only ever talks to INS.
  Uri _sameOrigin(Uri uri) {
    if (uri.scheme == base.scheme && uri.host == base.host && uri.port == base.port) return uri;
    return uri.replace(scheme: base.scheme, host: base.host, port: base.port);
  }
}

class _Page {
  final Uri uri; // final URL after redirects
  final int status;
  final String body;
  const _Page(this.uri, this.status, this.body);

  factory _Page.of(Uri uri, Response<List<int>> r) =>
      _Page(uri, r.statusCode ?? 0, decodeInsBytes(r.data ?? const <int>[]));

  String get statusSuffix => status == 200 ? '' : ' (HTTP $status)';
}

/// Internal signal: INS showed the login page mid-chain.
class _SessionExpired implements Exception {
  const _SessionExpired();
}
