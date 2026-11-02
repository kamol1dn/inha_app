import 'dart:io';

import 'package:cookie_jar/cookie_jar.dart';
import 'package:dio/dio.dart';
import 'package:dio_cookie_manager/dio_cookie_manager.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:inha_app/core/credentials.dart';
import 'package:inha_app/core/session.dart';
import 'package:inha_app/models/models.dart';
import 'package:inha_app/services/eclass/eclass_client.dart';
import 'package:inha_app/services/eclass/eclass_parsers.dart';

import 'eclass_client_test.dart' show FakeCredentials, FakeEclass, FakeSessions;

String fixture(String name) => File('test/fixtures/$name').readAsStringSync();

String calendar(String events) => '<html><body id="page-calendar-view"><div class="maincalendar">'
    '<div class="eventlist">$events</div></div><a href="/login/logout.php">out</a></body></html>';

String event(String title, {String module = 'quiz', int id = 7, int course = 2635, int time = 1792954740}) =>
    '<div class="event"><div class="card-header">'
    '<h3 class="referer"><a href="https://eclass.inha.ac.kr/mod/$module/view.php?id=$id">$title</a></h3>'
    '<span class="date"><a href="https://eclass.inha.ac.kr/calendar/view.php?view=day&amp;time=$time">Sunday</a></span>'
    '<div class="course"><a href="https://eclass.inha.ac.kr/course/view.php?id=$course">Blockchain Basics</a></div>'
    '</div></div>';

String quizPage(String rows, {String head = '<th>State</th><th>Grade</th>'}) =>
    '<html><body id="page-mod-quiz-view"><table class="generaltable quizattemptsummary">'
    '<thead><tr>$head</tr></thead><tbody>$rows</tbody></table></body></html>';

void main() {
  group('calendar events', () {
    test('an opening is not a deadline; its closing is', () {
      final out = parseUpcoming(calendar(event('[QUIZ] 2 Week 6 - 2% (Quiz opens)') +
          event('[QUIZ] 2 Week 6 - 2% (Quiz closes)', time: 1793000000)));
      expect(out.single.title, '[QUIZ] 2 Week 6 - 2% (Quiz closes)');
      expect(out.single.kind, DeadlineKind.quiz);
    });

    test('other activities opening too, whatever the case', () {
      expect(parseUpcoming(calendar(event('Essay (Assignment Opens)', module: 'assign'))), isEmpty);
      expect(parseUpcoming(calendar(event('Essay (opens)', module: 'assign'))), isEmpty);
      expect(parseUpcoming(calendar(event('Who opens the door', module: 'assign'))), hasLength(1));
    });

    test('each event knows its course', () {
      final out = parseUpcoming(fixture('eclass_upcoming.html'));
      expect(out.first.courseId, 2592);
      expect(out.where((d) => d.courseName == 'Multimedia Computing').single.courseId, 2622);
    });

    test('an event with no course link has no course id', () {
      final html = calendar('<div class="event"><h3 class="name">Holiday</h3>'
          '<span class="date"><a href="/calendar/view.php?time=1792954740">Sunday</a></span></div>');
      expect(parseUpcoming(html).single.courseId, isNull);
    });
  });

  group('a finished quiz', () {
    test('with an Attempt column before the state', () {
      final s = parseQuizSubmission(quizPage(
        '<tr><td>1</td><td>Finished<br/><span class="statedetails">Submitted 2026-10-20 14:03</span></td><td>8</td></tr>',
        head: '<th>Attempt</th><th>State</th><th>Grade</th>',
      ));
      expect(s.done, isTrue);
      expect(s.at, DateTime(2026, 10, 20, 14, 3));
    });

    test('the newest of several attempts gives the time', () {
      final s = parseQuizSubmission(quizPage(
        '<tr><td>1</td><td>Finished Submitted 2026-10-20 14:03</td></tr>'
        '<tr><td>2</td><td>종료됨 Submitted 2026-10-21 09:00</td></tr>',
      ));
      expect(s.at, DateTime(2026, 10, 21, 9));
    });

    test('an attempt still in progress is not done', () {
      expect(parseQuizSubmission(quizPage('<tr><td>1</td><td>In progress</td></tr>')).done, isFalse);
    });
  });

  group('VOD rows', () {
    final rows = parseVodProgress(fixture('eclass_progress_2592.html'));

    test('carry the watch window, in device time', () {
      final first = rows.first;
      expect(first.title, 'Class intro');
      expect(first.opens, DateTime.fromMillisecondsSinceEpoch(1788548400 * 1000));
      expect(first.closes, DateTime.fromMillisecondsSinceEpoch(1789325999 * 1000));
      expect(first.closedAt(first.closes!.add(const Duration(minutes: 1))), isTrue);
      expect(first.closedAt(first.closes!.subtract(const Duration(minutes: 1))), isFalse);
    });

    test('have no module id from this page: data-modid is the instance', () {
      expect(rows.every((v) => v.moduleId == null), isTrue);
    });

    test('a row with no Details button simply has no window', () {
      final html = '<html><body><table class="user_progress"><tbody><tr>'
          '<td><div class="sectiontitle">1</div></td><td>Intro</td><td>10:00</td><td>-</td><td>0%</td>'
          '</tr></tbody></table></body></html>';
      final v = parseVodProgress(html).single;
      expect(v.closes, isNull);
      expect(v.closedAt(DateTime(2030)), isFalse);
    });

    test('round-trip with the window, and an old cache reads without it', () {
      final back = VodProgress.fromJson(rows.first.withModuleId(72443).toJson());
      expect(back.moduleId, 72443);
      expect(back.closes, rows.first.closes);
      final old = VodProgress.fromJson({'week': 1, 'title': 'x', 'lengthSec': 60, 'percent': 10});
      expect((old.moduleId, old.closes, old.opens), (null, null, null));
    });
  });

  group('the VOD list', () {
    const page = '<html><body id="page-mod-vod-index">'
        '<a href="https://eclass.inha.ac.kr/course/view.php?id=2592">Course</a>'
        '<div id="region-main"><a href="https://eclass.inha.ac.kr/course/view.php?id=2592">Course again</a>'
        '<table class="generaltable"><tbody>'
        '<tr><td>1</td><td><a href="view.php?id=72001">Class  intro</a></td></tr>'
        '<tr><td>2</td><td><a href="https://eclass.inha.ac.kr/mod/vod/view.php?id=72002">Lecture 2</a></td></tr>'
        '<tr><td>3</td><td><a href="view.php?id=72003">Lecture 2</a></td></tr>'
        '</tbody></table></div></body></html>';

    test('gives names and module ids, not other links', () {
      expect(parseVodModules(page), [('Class intro', 72001), ('Lecture 2', 72002), ('Lecture 2', 72003)]);
    });

    test('a page that is something else gives nothing', () {
      expect(parseVodModules('<html><body>Not a list</body></html>'), isEmpty);
    });

    test('matches rows by name; a repeated name takes the links in order; the rest stay unset', () {
      VodProgress row(String title) => VodProgress(week: 1, title: title, length: Duration.zero, percent: 0);
      final out = withVodModules(
          [row('class intro'), row('Lecture 2'), row('Lecture 2'), row('Lecture 2'), row('Gone')],
          parseVodModules(page));
      expect(out.map((v) => v.moduleId), [72001, 72002, 72003, null, null]);
    });
  });

  group('the bell menu', () {
    test('reads a reply', () {
      final out = parseNotifications('[{"error":false,"data":{"notifications":['
          '{"id":5,"subject":"Room <b>changed</b>","smallmessage":"Now &amp; later","contexturl":"https://x/y",'
          '"timecreated":1792954740,"read":false},'
          '{"id":4,"subject":"Old","smallmessage":"","fullmessage":"Full text","contexturl":"","timecreated":1792000000,"read":true}'
          ']}}]');
      expect(out.map((n) => n.id), [5, 4]);
      expect(out[0].subject, 'Room changed');
      expect(out[0].text, 'Now & later');
      expect(out[0].url, 'https://x/y');
      expect(out[0].time, DateTime.fromMillisecondsSinceEpoch(1792954740000));
      expect(out[1].text, 'Full text');
      expect(out[1].url, isNull);
      expect(out[1].read, isTrue);
    });

    test('a Moodle error or something unreadable is a ParseError', () {
      expect(() => parseNotifications('[{"error":true,"exception":{}}]'), throwsA(isA<ParseError>()));
      expect(() => parseNotifications('<html>'), throwsA(isA<ParseError>()));
      expect(() => parseNotifications('[]'), throwsA(isA<ParseError>()));
    });

    test('the user id comes from the profile link', () {
      expect(parseUserId('<a href="https://eclass.inha.ac.kr/user/edit.php?id=123&amp;course=1">Edit</a>'), 123);
      expect(parseUserId('<script>"/user/edit.php?lang=en&amp;id=45"</script>'), 45);
      expect(parseUserId('<p>none</p>'), isNull);
    });
  });

  group('client', () {
    late FakeEclass server;
    late FakeCredentials creds;
    late EclassClient client;
    const course = Course(id: 2592, name: 'Distinguished Lecture', code: 'NTS4070');

    setUp(() {
      server = FakeEclass({
        '/': fixture('eclass_dashboard.html'),
        '/calendar/view.php?view=upcoming&course=2592': fixture('eclass_upcoming.html'),
        '/report/ubcompletion/user_progress.php?id=2592': fixture('eclass_progress_2592.html'),
      });
      final dio = Dio(BaseOptions(followRedirects: true, validateStatus: (code) => code != null && code < 500))
        ..httpClientAdapter = server
        ..interceptors.add(CookieManager(CookieJar()));
      creds = FakeCredentials(const Credentials('student', 'secret'));
      client = EclassClient(FakeSessions(dio), creds);
    });

    test('a course\'s calendar page; a course without one is empty', () async {
      expect(await client.upcomingIn(course), isNotEmpty);
      expect(await client.upcomingIn(const Course(id: 1, name: 'x', code: '')), isEmpty);
    });

    test('attendance gets module ids from the course\'s VOD list', () async {
      server.pages['/mod/vod/index.php?id=2592'] =
          '<html><body><div id="region-main"><a href="view.php?id=72441">Video 7</a></div>'
          '<a href="/login/logout.php">out</a></body></html>';
      final a = await client.attendance(course);
      expect(a.vods.firstWhere((v) => v.title == 'Video 7').moduleId, 72441);
      expect(a.vods.firstWhere((v) => v.title == 'Lecture 2').moduleId, isNull);
    });

    test('attendance does not need the VOD list', () async {
      final a = await client.attendance(course);
      expect(a.vods, isNotEmpty);
      expect(a.vods.every((v) => v.moduleId == null), isTrue);
    });

    test('the bell menu goes through the AJAX call with the page\'s keys', () async {
      server.pages['/lib/ajax/service.php?sesskey=TESTSESSKY'] =
          '[{"error":false,"data":{"notifications":[{"id":5,"subject":"Room changed","smallmessage":"B-305","timecreated":1792954740}]}}]';
      expect((await client.notifications()).single.subject, 'Room changed');
      expect(server.log.last, 'POST /lib/ajax/service.php?sesskey=TESTSESSKY');
    });

    test('a stale key is read again once; after that it is a failure', () async {
      server.pages['/lib/ajax/service.php?sesskey=TESTSESSKY'] = '[{"error":true}]';
      await expectLater(client.notifications(), throwsA(isA<ParseError>()));
      expect(server.log.where((l) => l.startsWith('POST /lib/ajax')), hasLength(2));
    });

    test('a refused login is posted once, however many fetches follow, until a new one is saved', () async {
      server.password = 'changed';
      await expectLater(client.courses(), throwsA(isA<LoginRequired>()));
      expect(server.loginCount, 1);
      await expectLater(client.courses(), throwsA(isA<LoginRequired>()));
      await expectLater(client.ensureLoggedIn(), throwsA(isA<LoginRequired>()));
      expect(server.loginCount, 1);

      await creds.write(Service.eclass, const Credentials('student', 'changed'));
      expect(await client.courses(), isNotEmpty);
      expect(server.loginCount, 2);
    });
  });

  group('credential store', () {
    test('a refusal is about exactly that login', () async {
      final store = FakeCredentials(const Credentials('a', 'b'));
      await store.markRefused(Service.mail, const Credentials('a', 'b'));
      expect(await store.isRefused(Service.mail, const Credentials('a', 'b')), isTrue);
      expect(await store.isRefused(Service.mail, const Credentials('a', 'c')), isFalse);
      expect(CredentialStore.refusalLasts, const Duration(hours: 24));
    });
  });
}
