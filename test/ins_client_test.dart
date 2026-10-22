import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:cookie_jar/cookie_jar.dart';
import 'package:dio/dio.dart';
import 'package:dio_cookie_manager/dio_cookie_manager.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:inha_app/core/credentials.dart';
import 'package:inha_app/core/session.dart';
import 'package:inha_app/models/models.dart';
import 'package:inha_app/services/ins/ins_client.dart';

String fixture(String name) => File('test/fixtures/$name').readAsStringSync();
List<int> fixtureBytes(String name) => File('test/fixtures/$name').readAsBytesSync();

const studentId = 'U2510001'; // fake
const password = 'p@ss w+rd&=1'; // fake, with characters that need form-encoding
const fakeJumin = 'FAKE-JUMIN-000000-0000000';
const gradesParam = 'param=FAKEgRaD3s+St4nd/1ngs==&ENGYN=Y';
const xmlQuery = 'Value=FAKE0T0KEN0abc%3d'; // as the raw rpx page writes it

class FakeCredentials implements CredentialStore {
  Credentials? creds;
  FakeCredentials(this.creds);
  @override
  Future<Credentials?> read(Service s) async => s == Service.ins ? creds : null;
  @override
  Future<void> write(Service s, Credentials c) async => creds = c;
  @override
  Future<void> clear(Service s) async => creds = null;
}

/// How `main.aspx?param=<grades>` answers.
enum MainMode { redirect, frameset, script, opaque }

/// How left.aspx answers without a valid session.
enum LoggedOutMode { redirect, script }

class Req {
  final String method;
  final Uri uri;
  final Map<String, dynamic> headers;
  final String body;
  Req(this.method, this.uri, this.headers, this.body);
  String get path => uri.path.toLowerCase();
  @override
  String toString() => '$method ${uri.path}${uri.hasQuery ? '?${uri.query}' : ''}';
}

class _Sess {
  bool authed = false;
  bool gradesMenuVisited = false;
}

/// A tiny ITIS: Start.aspx login, FRAMESET.htm, left.aspx, main.aspx,
/// MarkView.aspx, MarkView_rpx.aspx, MarkView_xml.aspx. Sessions are keyed by
/// an ASP.NET_SessionId cookie, as on the real server.
class FakeIns implements HttpClientAdapter {
  MainMode mainMode = MainMode.redirect;
  LoggedOutMode loggedOutMode = LoggedOutMode.redirect;
  bool loginRedirects = true; // 302 to FRAMESET.htm, else a 200 script page
  /// When set, the login redirect names this host absolutely, like the real
  /// server's http://ins.iutdev.ac.kr/... answers.
  String? loginRedirectHost;
  bool forgetLoginImmediately = false; // login "succeeds" but the session is never authed

  final sessions = <String, _Sess>{};
  final requests = <Req>[];
  int _next = 0;

  void expireAllSessions() => sessions.clear();
  List<Req> get logins =>
      requests.where((r) => r.method == 'POST' && r.path == '/itis/start.aspx').toList();
  Req get xmlRequest => requests.singleWhere((r) => r.path.endsWith('markview_xml.aspx'));

  @override
  void close({bool force = false}) {}

  @override
  Future<ResponseBody> fetch(
      RequestOptions options, Stream<Uint8List>? requestStream, Future<void>? cancelFuture) async {
    final body = requestStream == null
        ? ''
        : utf8.decode(await requestStream.expand((chunk) => chunk).toList());
    final req = Req(options.method, options.uri,
        {for (final e in options.headers.entries) e.key.toLowerCase(): e.value}, body);
    requests.add(req);
    expect(options.uri.host, 'ins.inha.uz', reason: 'never leaves INS');

    // Session cookie.
    final cookie = (req.headers['cookie'] ?? '') as String;
    final sid = RegExp(r'ASP\.NET_SessionId=(\w+)').firstMatch(cookie)?.group(1);
    final headers = <String, List<String>>{};
    var sess = sid == null ? null : sessions[sid];
    if (sess == null) {
      final id = 'fakesession${_next++}';
      sess = sessions[id] = _Sess();
      headers['set-cookie'] = ['ASP.NET_SessionId=$id; path=/; HttpOnly'];
    }

    ResponseBody html(String text, [int status = 200]) => ResponseBody.fromBytes(
        utf8.encode(text), status,
        headers: {...headers, 'content-type': ['text/html; charset=utf-8']});
    ResponseBody redirect(String location) => ResponseBody.fromBytes(
        utf8.encode('<html><body>Object moved to <a href="$location">here</a>.</body></html>'), 302,
        headers: {...headers, 'location': [location], 'content-type': ['text/html; charset=utf-8']});
    ResponseBody loggedOut() => loggedOutMode == LoggedOutMode.redirect
        ? redirect('/ITIS/Start.aspx')
        : html("<script>alert('Session expired.');top.location.href='/ITIS/Start.aspx';</script>");

    switch ((options.method, req.path)) {
      case ('GET', '/itis/start.aspx'):
        return html(fixture('ins_start.html'));

      case ('POST', '/itis/start.aspx'):
        final form = Uri.splitQueryString(body);
        final ok = form['txtInhaID'] == studentId &&
            form['txtPW'] == password &&
            form.containsKey('btnLogin') &&
            form['__VIEWSTATE'] ==
                '/wEPDwUKLTFBS0VWSUVXU1RBVEUPZBYCAgMPZBYCZg8PFgIeBFRleHQFBEZBS0VkZGQ+v1ewFAKE/9z+Q==' &&
            form['__EVENTVALIDATION'] == '/wEdAAXFAKEeventVALIDATIONxx+yy/zz==';
        if (!ok) return html(fixture('ins_start_error.html'));
        if (!forgetLoginImmediately) sess.authed = true;
        return loginRedirects
            ? redirect(loginRedirectHost == null
                ? '/ITIS/FRAMESET.htm'
                : 'http://$loginRedirectHost/ITIS/FRAMESET.htm')
            : html("<script>top.location.href='FRAMESET.htm';</script>");

      case ('GET', '/itis/frameset.htm'):
        return html('<html><frameset cols="200,*"><frame name="left" src="left.aspx">'
            '<frame name="main" src="main.aspx"></frameset></html>');

      case ('GET', '/itis/left.aspx'):
        return sess.authed ? html(fixture('ins_left.html')) : loggedOut();

      case ('GET', '/itis/main.aspx'):
        if (!sess.authed) return loggedOut();
        if (req.uri.query != gradesParam) return html('<p>Other menu</p>');
        sess.gradesMenuVisited = true;
        return switch (mainMode) {
          MainMode.redirect => redirect('/ITIS/STD/SJ/SJ_51001/MarkView.aspx'),
          MainMode.frameset => html('<frameset rows="0,*"><frame src="blank.htm">'
              '<frame name="body" src="STD/SJ/SJ_51001/MarkView.aspx"></frameset>'),
          MainMode.script =>
            html("<script>location.href = 'STD/SJ/SJ_51001/MarkView.aspx';</script>"),
          MainMode.opaque => html('<html><body onload="go()"></body></html>'),
        };

      case ('GET', '/itis/std/sj/sj_51001/markview.aspx'):
        if (!sess.authed) return loggedOut();
        if (!sess.gradesMenuVisited) return html('<p>Invalid access</p>');
        return html('<form id="form1" action="./MarkView.aspx"></form>'
            '<iframe id="ifrReport" src="MarkView_rpx.aspx?gubun=inform"></iframe>');

      case ('GET', '/itis/std/sj/sj_51001/markview_rpx.aspx'):
        if (!sess.authed) return loggedOut();
        if (!sess.gradesMenuVisited || req.uri.query != 'gubun=inform') {
          return html('<p>Invalid access</p>');
        }
        return html(fixture('ins_rpx.html'));

      case ('POST', '/itis/std/sj/sj_51001/markview_xml.aspx'):
        if (!sess.authed) return loggedOut();
        if (Uri.decodeQueryComponent(req.uri.query) != Uri.decodeQueryComponent(xmlQuery)) {
          return html('<p>Bad token</p>', 500); // compared decoded: %3d and %3D are the same
        }
        return ResponseBody.fromBytes(fixtureBytes('ins_grades.xml'), 200,
            headers: {...headers, 'content-type': ['text/xml; charset=euc-kr']});
    }
    return html('<h1>404</h1>', 404);
  }
}

void main() {
  late FakeIns server;
  late FakeCredentials creds;
  late InsClient client;

  setUp(() {
    server = FakeIns();
    creds = FakeCredentials(const Credentials('u2510001 ', password));
    final dio = Dio(BaseOptions(
      // Same shape as Sessions.client(): redirects on by default; the client
      // must override that per request.
      followRedirects: true,
      validateStatus: (code) => code != null && code < 500,
    ))
      ..httpClientAdapter = server
      ..interceptors.add(CookieManager(CookieJar()));
    client = InsClient.withDio(dio, creds);
  });

  Future<GradeReport> expectGrades() async {
    final report = await client.grades();
    expect(report.records, hasLength(8));
    expect(report.gpa, closeTo(3.558824, 1e-9));
    expect(report.creditsEarned, 17);
    expect(report.yearOfStudy, 2);
    return report;
  }

  test('fresh start: logs in and walks the whole grades chain', () async {
    final report = await expectGrades();
    expect(report.records.where((r) => !r.graded), hasLength(2));

    expect(server.requests.map((r) => r.toString()).toList(), [
      'GET /ITIS/left.aspx', // no session yet
      'GET /ITIS/Start.aspx', // ...bounced to the login page
      'GET /ITIS/Start.aspx', // login: fresh hidden fields
      'POST /ITIS/Start.aspx',
      'GET /ITIS/FRAMESET.htm',
      'GET /ITIS/left.aspx',
      'GET /ITIS/main.aspx?$gradesParam',
      'GET /ITIS/STD/SJ/SJ_51001/MarkView.aspx',
      'GET /ITIS/STD/SJ/SJ_51001/MarkView_rpx.aspx?gubun=inform',
      'POST /ITIS/STD/SJ/SJ_51001/MarkView_xml.aspx?Value=FAKE0T0KEN0abc%3D', // Dart writes %3D
    ]);

    // The login post: every hidden input of form1, uppercased ID, btnLogin present.
    final login = server.logins.single;
    expect(login.headers['content-type'], startsWith('application/x-www-form-urlencoded'));
    final form = Uri.splitQueryString(login.body);
    expect(form, {
      '__EVENTTARGET': '',
      '__EVENTARGUMENT': '',
      '__VIEWSTATE':
          '/wEPDwUKLTFBS0VWSUVXU1RBVEUPZBYCAgMPZBYCZg8PFgIeBFRleHQFBEZBS0VkZGQ+v1ewFAKE/9z+Q==',
      '__VIEWSTATEGENERATOR': 'FA4E0001',
      '__EVENTVALIDATION': '/wEdAAXFAKEeventVALIDATIONxx+yy/zz==',
      'errorMessage': '',
      'hdnPublicKey': 'FAKE00PUBLIC00KEY',
      'txtInhaID': studentId,
      'txtPW': password,
      'btnLogin': '',
    });
    expect(login.body, contains('btnLogin='));

    // The XML is fetched with an empty POST, from the rpx page.
    final xml = server.xmlRequest;
    expect(xml.body, isEmpty);
    expect(xml.headers['content-length'], '0');
    expect(xml.headers['referer'], contains('MarkView_rpx.aspx'));
  });

  test('the report never carries JUMIN', () async {
    final report = await expectGrades();
    final json = jsonEncode(report.toJson());
    expect(json, isNot(contains(fakeJumin)));
    expect(json, isNot(contains('000000-0000000')));
  });

  test('second call reuses the session (no new login)', () async {
    await expectGrades();
    server.requests.clear();
    await expectGrades();
    expect(server.logins, isEmpty);
    expect(server.requests.first.toString(), 'GET /ITIS/left.aspx');
  });

  for (final mode in MainMode.values) {
    test('main.aspx as $mode still reaches the XML', () async {
      server.mainMode = mode;
      await expectGrades();
      if (mode == MainMode.opaque) {
        // Fell back to the known rpx URL after visiting main.aspx.
        final paths = server.requests.map((r) => r.toString()).toList();
        expect(paths.indexOf('GET /ITIS/STD/SJ/SJ_51001/MarkView_rpx.aspx?gubun=inform'),
            greaterThan(paths.indexOf('GET /ITIS/main.aspx?$gradesParam')));
      }
    });
  }

  test('a redirect naming the internal host is followed on ins.inha.uz', () async {
    server.loginRedirectHost = 'ins.iutdev.ac.kr';
    await expectGrades();
    expect(server.requests.map((r) => '${r.uri.scheme}://${r.uri.host}').toSet(),
        {'https://ins.inha.uz'});
  });

  test('login answered with a script redirect counts as success', () async {
    server.loginRedirects = false;
    await expectGrades();
    expect(server.logins, hasLength(1));
  });

  test('bad password: LoginRequired with the server message, one attempt', () async {
    creds.creds = const Credentials('u2510001', 'wrong');
    await expectLater(
      client.grades(),
      throwsA(isA<LoginRequired>()
          .having((e) => e.service, 'service', Service.ins)
          .having((e) => e.message, 'message', 'The ID or password is incorrect. (fake message)')),
    );
    expect(server.logins, hasLength(1));
    expect(server.requests.where((r) => r.path.contains('markview')), isEmpty);
  });

  test('ensureLoggedIn: bad password throws, good password passes', () async {
    creds.creds = const Credentials('u2510001', 'wrong');
    await expectLater(client.ensureLoggedIn(), throwsA(isA<LoginRequired>()));
    creds.creds = const Credentials('u2510001', password);
    await client.ensureLoggedIn();
    server.requests.clear();
    await client.ensureLoggedIn(); // already in: just the menu check
    expect(server.requests.map((r) => r.toString()), ['GET /ITIS/left.aspx']);
  });

  test('no saved login: LoginRequired without posting anything', () async {
    creds.creds = null;
    await expectLater(client.grades(), throwsA(isA<LoginRequired>()));
    expect(server.logins, isEmpty);
  });

  for (final mode in LoggedOutMode.values) {
    test('expired session ($mode): logs in again once and retries', () async {
      server.loggedOutMode = mode;
      await expectGrades();
      expect(server.logins, hasLength(1));

      server.expireAllSessions();
      server.requests.clear();
      await expectGrades();
      expect(server.logins, hasLength(1)); // exactly one re-login
      expect(server.requests.first.toString(), 'GET /ITIS/left.aspx');
    });
  }

  test('session that never sticks: one re-login, then LoginRequired', () async {
    server.forgetLoginImmediately = true;
    await expectLater(
      client.grades(),
      throwsA(isA<LoginRequired>().having((e) => e.service, 'service', Service.ins)),
    );
    expect(server.logins, hasLength(1));
  });

  test('concurrent calls share one login', () async {
    final results = await Future.wait([client.grades(), client.grades()]);
    expect(results, everyElement(isA<GradeReport>()));
    expect(server.logins, hasLength(1));
  });
}
