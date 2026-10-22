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
import 'package:inha_app/services/eclass/eclass_client.dart';

String fixture(String name) => File('test/fixtures/$name').readAsStringSync();

final eclass = Uri.parse('https://eclass.inha.ac.kr/');

class FakeSessions implements Sessions {
  FakeSessions(this.dio);
  final Dio dio;

  @override
  Dio client(Service s) => dio;
  @override
  Future<void> init() async {}
  @override
  Future<void> reset(Service s) async {}
}

class FakeCredentials implements CredentialStore {
  FakeCredentials(this.saved);
  Credentials? saved;

  @override
  Future<Credentials?> read(Service s) async => saved;
  @override
  Future<void> write(Service s, Credentials c) async => saved = c;
  @override
  Future<void> clear(Service s) async => saved = null;
}

/// A tiny eClass behind Dio: one live session cookie at a time, the login
/// form (Moodle's 303 → testsession → 303 dance), and fixture pages.
class FakeEclass implements HttpClientAdapter {
  FakeEclass(this.pages);

  /// "path?query" → HTML served to a logged-in client.
  final Map<String, String> pages;

  /// "path?query" → HTML served to a logged-out client instead of the login
  /// redirect, like eClass's calendar, which renders (empty) for guests.
  final Map<String, String> guestPages = {};
  String username = 'student';
  String password = 'secret';
  String? liveSession;
  int _issued = 0;

  /// Every request as "METHOD path?query".
  final log = <String>[];
  final loginForms = <Map<String, String>>[];
  final loginContentTypes = <String?>[];
  final loginFollowRedirects = <bool>[];

  int get loginCount => loginForms.length;

  @override
  Future<ResponseBody> fetch(
    RequestOptions o,
    Stream<Uint8List>? requestStream,
    Future<void>? cancelFuture,
  ) async {
    final uri = o.uri;
    final target = uri.hasQuery ? '${uri.path}?${uri.query}' : uri.path;
    log.add('${o.method} $target');
    final cookies = (o.headers['cookie'] as String?) ?? '';
    final loggedIn = liveSession != null && cookies.contains('MoodleSession=$liveSession');

    if (o.method == 'POST' && uri.path == '/login/index.php') {
      final raw = requestStream == null
          ? ''
          : utf8.decode(await requestStream.expand((b) => b).toList());
      final form = Uri.splitQueryString(raw);
      loginForms.add(form);
      loginContentTypes.add(o.contentType);
      loginFollowRedirects.add(o.followRedirects);
      if (form['username'] == username && form['password'] == password) {
        liveSession = 'sess${++_issued}';
        return _redirect('/login/index.php?testsession=1',
            setCookie: 'MoodleSession=$liveSession; path=/; HttpOnly');
      }
      return _html(fixture('eclass_login.html')); // login form again, with an error
    }

    if (uri.path == '/login/index.php' && uri.queryParameters.containsKey('testsession')) {
      return loggedIn ? _redirect('https://eclass.inha.ac.kr/') : _html(fixture('eclass_login.html'));
    }

    if (!loggedIn && guestPages.containsKey(target)) return _html(guestPages[target]!);

    if (!loggedIn) {
      // What dart:io hands back after following eClass's redirect to login.
      return _html(fixture('eclass_login.html'))
        ..redirects = [RedirectRecord(303, 'GET', eclass.resolve('/login/index.php'))];
    }

    final page = pages[target];
    return page == null ? _html('<h1>Not found</h1>', status: 404) : _html(page);
  }

  ResponseBody _html(String html, {int status = 200}) => ResponseBody.fromString(
        html,
        status,
        headers: {
          'content-type': ['text/html; charset=utf-8'],
        },
      );

  ResponseBody _redirect(String location, {String? setCookie}) => ResponseBody.fromString(
        '',
        303,
        isRedirect: true,
        headers: {
          'location': [location],
          if (setCookie != null) 'set-cookie': [setCookie],
        },
      );

  @override
  void close({bool force = false}) {}
}

void main() {
  late FakeEclass server;
  late CookieJar jar;
  late FakeCredentials creds;
  late EclassClient client;

  const multimedia = Course(id: 2622, name: 'Multimedia Computing', code: 'SOC4020');
  const lecture = Course(id: 2592, name: 'Distinguished Lecture in Social Science and Art', code: 'NTS4070');

  setUp(() {
    server = FakeEclass({
      '/': fixture('eclass_dashboard.html'),
      '/calendar/view.php?view=upcoming': fixture('eclass_upcoming.html'),
      '/local/ubattendance/my_status.php?id=2622': fixture('eclass_attendance_2622.html'),
      '/report/ubcompletion/user_progress.php?id=2592': fixture('eclass_progress_2592.html'),
      '/report/ubcompletion/user_progress.php?id=2635': fixture('eclass_progress_2635.html'),
    });
    jar = CookieJar();
    final dio = Dio(BaseOptions(
      followRedirects: true,
      validateStatus: (code) => code != null && code < 500,
    ))
      ..httpClientAdapter = server
      ..interceptors.add(CookieManager(jar));
    creds = FakeCredentials(const Credentials('student', 'secret'));
    client = EclassClient(FakeSessions(dio), creds);
  });

  /// Pretend an earlier run left a valid session cookie in the jar.
  Future<void> alreadyLoggedIn() async {
    server.liveSession = 'sess0';
    await jar.saveFromResponse(eclass, [Cookie('MoodleSession', 'sess0')]);
  }

  group('logged in', () {
    setUp(alreadyLoggedIn);

    test('courses() fetches the dashboard without logging in', () async {
      final courses = await client.courses();
      expect(courses, hasLength(6));
      expect(courses.singleWhere((c) => c.id == 2622).name, 'Multimedia Computing');
      expect(server.loginCount, 0);
      expect(server.log, ['GET /']);
    });

    test('upcoming() parses the calendar', () async {
      final events = await client.upcoming();
      expect(events, hasLength(10));
      expect(server.log, ['GET /calendar/view.php?view=upcoming']);
    });

    test('ensureLoggedIn() does nothing when the session is alive', () async {
      await client.ensureLoggedIn();
      expect(server.loginCount, 0);
    });

    test('attendance() combines both pages; a 404 part is just empty', () async {
      final mm = await client.attendance(multimedia);
      expect(mm.course.id, 2622);
      expect(mm.classes, hasLength(13));
      expect(mm.count(AttendanceMark.present), 11);
      expect(mm.count(AttendanceMark.absent), 2);
      expect(mm.vods, isEmpty); // progress page 404s in the fake

      final dl = await client.attendance(lecture);
      expect(dl.classes, isEmpty); // attendance page 404s in the fake
      expect(dl.vods, hasLength(12));

      expect(server.log, containsAll([
        'GET /local/ubattendance/my_status.php?id=2622',
        'GET /report/ubcompletion/user_progress.php?id=2622',
        'GET /local/ubattendance/my_status.php?id=2592',
        'GET /report/ubcompletion/user_progress.php?id=2592',
      ]));
    });

    test('attendance() with VODs that are not progress-managed gives no VODs', () async {
      const blockchain = Course(id: 2635, name: 'Blockchain Basics and Platforms', code: 'SOC4190');
      final bc = await client.attendance(blockchain);
      expect(bc.vods, isEmpty);
      expect(bc.classes, isEmpty);
    });

    test('a non-optional page that 404s is an error, not an empty list', () async {
      server.pages.remove('/calendar/view.php?view=upcoming');
      await expectLater(client.upcoming(), throwsA(isA<DioException>()));
    });
  });

  group('guest page', () {
    test('a page that renders for guests, without the logout link, still logs in first', () async {
      server.guestPages['/calendar/view.php?view=upcoming'] =
          '<html><body id="page-calendar-view"><div class="calendar_event_upcoming"></div>'
          '<a href="https://eclass.inha.ac.kr/login/index.php">Log in</a></body></html>';
      final events = await client.upcoming();
      expect(events, hasLength(10));
      expect(server.loginCount, 1);
    });

    test('with no saved login it is LoginRequired, not an empty list', () async {
      server.guestPages['/calendar/view.php?view=upcoming'] = '<html><body></body></html>';
      creds.saved = null;
      await expectLater(client.upcoming(), throwsA(isA<LoginRequired>()));
    });
  });

  group('session expired', () {
    setUp(() async {
      await alreadyLoggedIn();
      server.liveSession = 'sess-the-server-forgot';
    });

    test('logs in once with the form and retries the fetch', () async {
      final events = await client.upcoming();

      expect(events, hasLength(10));
      expect(server.loginCount, 1);
      expect(server.loginForms.single, {'username': 'student', 'password': 'secret'});
      expect(server.loginContentTypes.single, startsWith(Headers.formUrlEncodedContentType));
      expect(server.loginFollowRedirects.single, isFalse);
      expect(server.log, [
        'GET /calendar/view.php?view=upcoming', // → login page
        'POST /login/index.php', // → 303 + Set-Cookie
        'GET /login/index.php?testsession=1', // → 303
        'GET /',
        'GET /calendar/view.php?view=upcoming', // retry
      ]);
    });

    test('keeps the new session cookie for later requests', () async {
      await client.courses();
      server.log.clear();
      await client.upcoming();
      expect(server.loginCount, 1);
      expect(server.log, ['GET /calendar/view.php?view=upcoming']);
    });

    test('attendance() fetches both pages in parallel but logs in only once', () async {
      final mm = await client.attendance(multimedia);
      expect(mm.classes, hasLength(13));
      expect(server.loginCount, 1);
    });

    test('ensureLoggedIn() logs in', () async {
      await client.ensureLoggedIn();
      expect(server.loginCount, 1);
      expect(server.liveSession, 'sess1');
    });
  });

  group('bad or missing credentials', () {
    test('a rejected password throws LoginRequired after one attempt', () async {
      creds.saved = const Credentials('student', 'wrong');
      await expectLater(
        client.courses(),
        throwsA(isA<LoginRequired>().having((e) => e.service, 'service', Service.eclass)),
      );
      expect(server.loginCount, 1);
      expect(server.log.where((l) => l == 'GET /'), hasLength(1)); // no retry
    });

    test('ensureLoggedIn() with a rejected password throws LoginRequired', () async {
      creds.saved = const Credentials('student', 'wrong');
      await expectLater(client.ensureLoggedIn(), throwsA(isA<LoginRequired>()));
    });

    test('no saved login throws LoginRequired without posting anything', () async {
      creds.saved = null;
      await expectLater(client.upcoming(), throwsA(isA<LoginRequired>()));
      expect(server.loginCount, 0);
    });
  });
}
