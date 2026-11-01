import 'dart:async';
import 'dart:io';

import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:inha_app/core/cache.dart';
import 'package:inha_app/core/session.dart';
import 'package:inha_app/data/app_data.dart';
import 'package:inha_app/models/models.dart';
import 'package:inha_app/notifications/notifier.dart';
import 'package:inha_app/services/edupage/timetable_parser.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'fakes.dart';

const ai = Course(id: 2626, name: 'Artificial Intelligence', code: 'SOC4040');
const os = Course(id: 2627, name: 'Operating Systems', code: 'SOC3030');

Lesson lesson(String subject) => Lesson(weekday: DateTime.monday, start: '09:00', end: '10:30', subject: subject);

Deadline due(String title, {Course? course, DateTime? end, int? moduleId}) => Deadline(
      title: title,
      courseName: course?.name ?? 'Artificial Intelligence',
      courseId: course?.id,
      kind: DeadlineKind.other,
      end: end ?? DateTime.now().add(const Duration(days: 5)),
      moduleId: moduleId,
    );

/// eClass with its deadlines hanging until [release].
class SlowDeadlines extends FakeEclass {
  final _gate = Completer<void>();
  void release() => _gate.complete();

  @override
  Future<List<Deadline>> upcoming() async {
    await _gate.future;
    return super.upcoming();
  }
}

Future<(AppData, SlowDeadlines)> slowEclass() async {
  final (base, _, timetable, ins, mail) = await makeAppData();
  final eclass = SlowDeadlines();
  return (AppData(eclass: eclass, timetable: timetable, ins: ins, mail: mail, cache: base.cache, prefs: base.prefs), eclass);
}

void main() {
  final dropped = DioException.connectionError(requestOptions: RequestOptions(path: '/'), reason: 'gone');

  group('class group', () {
    test('a fresh install has none, fetches nothing and asks for one', () async {
      final (data, _, timetable, _, _) = await makeAppData(classGroupChosen: false);
      expect(data.prefs.classGroup, '');
      expect(data.prefs.excludedSubjects, isEmpty);
      expect(data.lessons.error, isA<SetupNeeded>());
      expect(data.lessons.loading, isFalse);

      await data.refreshTimetable();
      expect(timetable.asked, isEmpty);
      expect(data.lessons.data, isNull);
      expect(describeError(data.lessons.error!, 'Timetable'), 'Choose your class group in Settings.');
    });

    test('choosing one fetches it', () async {
      final (data, _, timetable, _, _) = await makeAppData(classGroupChosen: false);
      timetable.lessonList = [lesson('AI')];
      data.prefs.classGroup = 'CSE24-2';
      await data.refreshTimetable();
      expect(timetable.asked, ['CSE24-2']);
      expect(data.lessons.error, isNull);
      expect(data.lessons.data?.value.single.subject, 'AI');
    });

    group('an install from before it had to be chosen keeps what it ran on', () {
      Future<Prefs> open(Map<String, Object> saved) async {
        SharedPreferences.setMockInitialValues(saved);
        return Prefs(await SharedPreferences.getInstance());
      }

      test('it left a cache behind: the old defaults become its choice', () async {
        final p = await open({'cache.lessons': '{}'});
        expect(p.classGroup, 'ICE23-1');
        expect(p.excludedSubjects, {'Big Data'});
      });

      test('its own choices stay', () async {
        final p = await open({'notify.asked': true, 'classGroup': 'CSE24-2', 'excludedSubjects': <String>[]});
        expect(p.classGroup, 'CSE24-2');
        expect(p.excludedSubjects, isEmpty);
      });

      test('a fresh install gets no defaults, then or on the next start', () async {
        final p = await open({});
        expect(p.classGroup, '');
        p.notificationsAsked = true;
        expect(Prefs(await SharedPreferences.getInstance()).classGroup, '');
      });
    });

    test('a group the timetable lacks says so, and drops lessons it cannot vouch for', () async {
      final (data, _, timetable, _, _) = await makeAppData();
      timetable.lessonList = [lesson('AI')];
      await data.refreshTimetable();
      timetable.error = UnknownClassGroup('ICE23-1', const ['ICE23-2']);
      await data.refreshTimetable();
      expect(data.lessons.data, isNull);
      expect(data.cache.read('lessons', (j) => j), isNull);
      expect(describeError(data.lessons.error!, 'EduPage'),
          "ICE23-1 isn't on the timetable. Choose your class group in Settings.");
    });

    test('changing the group during a fetch drops that fetch and asks again', () async {
      final (data, _, timetable, _, _) = await makeAppData();
      final gate = Completer<void>();
      timetable
        ..gate = gate.future
        ..lessonList = [lesson('Old group')];
      final first = data.refreshTimetable();
      await pumpEventQueue();

      data.prefs.classGroup = 'ICE23-2';
      timetable
        ..gate = null
        ..lessonList = [lesson('New group')];
      await data.refreshTimetable();
      expect(data.lessons.data?.value.single.subject, 'New group');

      gate.complete();
      await first;
      expect(timetable.asked, ['ICE23-1', 'ICE23-2']);
      expect(data.lessons.data?.value.single.subject, 'New group');
      expect(data.lessons.loading, isFalse);
    });

    test('a new group that cannot load leaves no lessons of the old one', () async {
      final (data, _, timetable, _, _) = await makeAppData();
      timetable.lessonList = [lesson('Old group')];
      await data.refreshTimetable();
      data.prefs.classGroup = 'ICE23-2';
      timetable.error = dropped;
      await data.refreshTimetable();
      expect(data.lessons.data, isNull);
      expect(data.lessons.error, dropped);
    });

    test('hiding a subject during a fetch is applied, keeping the lessons shown until then', () async {
      final (data, _, timetable, _, _) = await makeAppData();
      timetable.lessonList = [lesson('AI')];
      await data.refreshTimetable();
      final gate = Completer<void>();
      timetable.gate = gate.future;
      final first = data.refreshTimetable();
      await pumpEventQueue();

      data.prefs.excludedSubjects = {'Physics'};
      final second = data.refreshTimetable();
      await pumpEventQueue();
      expect(data.lessons.data?.value.single.subject, 'AI');
      expect(timetable.asked, hasLength(3));
      gate.complete();
      await Future.wait([first, second]);
      expect(data.lessons.loading, isFalse);
    });
  });

  group('signing out during a refresh', () {
    test('what the refresh brings back is dropped, on screen and on disk', () async {
      final (data, eclass) = await slowEclass();
      eclass.deadlines = [due('Lab 5')];
      var replans = 0;
      data.onReminderDataChanged = () async => replans++;
      final refresh = data.refreshEclass();
      await pumpEventQueue();

      await data.forget(Service.eclass);
      expect(data.deadlines.loading, isFalse);
      eclass.release();
      await refresh;

      expect(data.deadlines.data, isNull);
      expect(data.cache.read('deadlines', (j) => j), isNull);
      expect(data.prefs.accountCheck(Service.eclass), isNull);
      expect(replans, 1); // planned from nothing, which is harmless
    });

    test('a failure arriving after the sign-out is not shown either', () async {
      final (data, eclass) = await slowEclass();
      eclass.error = dropped;
      final refresh = data.refreshEclass();
      await pumpEventQueue();
      await data.forget(Service.eclass);
      eclass.release();
      await refresh;
      expect(data.deadlines.error, isNull);
    });

    test('with no login saved any more (signed out in the other isolate) nothing is written', () async {
      final (data, eclass, _, _, _) = await makeAppData();
      eclass.deadlines = [due('Lab 5')];
      data.hasLogin = (_) async => false;
      await data.refreshEclass();
      expect(data.deadlines.data, isNull);
      expect(data.deadlines.loading, isFalse);
      expect(data.cache.read('deadlines', (j) => j), isNull);
    });

    test('a resume clears what the other isolate wrote after a sign-out', () async {
      final (data, _, _, _, _) = await makeAppData();
      await data.cache.write('deadlines', <Object?>[], (v) => v);
      data.hasLogin = (s) async => s != Service.eclass;
      await data.reloadFromCache();
      expect(data.cache.read('deadlines', (j) => j), isNull);
      expect(data.deadlines.data, isNull);
    });

    test('a sign-out tells the hook, and forgets what was seen of the account', () async {
      final (data, _, _, _, _) = await makeAppData(prefs: {
        Notifier.seenCoursesKey: <String>['2626'],
        Notifier.seenGradesKey: '{}',
        Notifier.noticesSeenKey: true,
      });
      final told = <Service>[];
      data.onSignedOut = (s) async => told.add(s);
      data.prefs.dismissedDeadlines = {'due:x'};
      await data.forget(Service.eclass);
      expect(told, [Service.eclass]);
      final p = await SharedPreferences.getInstance();
      expect(p.getStringList(Notifier.seenCoursesKey), isNull);
      expect(p.getString(Notifier.seenGradesKey), isNull);
      expect(p.getBool(Notifier.noticesSeenKey), isNull);
      expect(data.prefs.dismissedDeadlines, isEmpty);
    });

    test('a new login cancels what the old one was fetching', () async {
      final (data, eclass) = await slowEclass();
      eclass.deadlines = [due('From the old login')];
      final refresh = data.refreshEclass();
      await pumpEventQueue();
      expect(await data.testLogin(Service.eclass), isNull);
      eclass.release();
      await refresh;
      await pumpEventQueue();
      expect(data.prefs.accountCheck(Service.eclass)?.ok, isTrue);
    });
  });

  group('one course failing', () {
    final fresh = CourseAttendance(course: ai, classes: [
      AttendanceEntry(date: DateTime(2026, 10, 21), label: '1Class', mark: AttendanceMark.present),
    ]);
    final old = CourseAttendance(course: os, classes: [
      AttendanceEntry(date: DateTime(2026, 10, 14), label: '1Class', mark: AttendanceMark.absent),
    ]);
    final serverError = DioException.badResponse(
        statusCode: 503,
        requestOptions: RequestOptions(path: '/'),
        response: Response(requestOptions: RequestOptions(path: '/'), statusCode: 503));

    test('the others update, it keeps its cached entry, and the screen can say which', () async {
      final (data, eclass, _, _, _) = await makeAppData();
      eclass
        ..courseList = const [ai, os]
        ..attendanceById = {ai.id: fresh, os.id: old};
      await data.refreshEclass();

      eclass
        ..attendanceById = {ai.id: fresh}
        ..failingCourses = {os.id: serverError};
      await data.refreshEclass();

      final att = data.attendance.data!.value;
      expect(att.map((a) => a.course.id), [ai.id, os.id]);
      expect(att[1].classes.single.mark, AttendanceMark.absent);
      expect(data.attendance.error, isA<PartialRefresh>());
      expect(describeError(data.attendance.error!, 'eClass'), "Couldn't update Operating Systems from eClass.");
      expect(isWorthRetrying(data.attendance.error), isTrue);
      expect(data.courseGrades.error, isA<PartialRefresh>());
      expect(data.courseGrades.data?.value, hasLength(2));
    });

    test('with nothing cached it reads as empty', () async {
      final (data, eclass, _, _, _) = await makeAppData();
      eclass
        ..courseList = const [ai, os]
        ..attendanceById = {ai.id: fresh}
        ..failingCourses = {os.id: serverError};
      await data.refreshEclass();
      expect(data.attendance.data!.value[1].classes, isEmpty);
    });

    test('every course failing fails the list, and a refused login always does', () async {
      final (data, eclass, _, _, _) = await makeAppData();
      eclass
        ..courseList = const [ai, os]
        ..failingCourses = {ai.id: serverError, os.id: serverError};
      await data.refreshEclass();
      expect(data.attendance.data, isNull);
      expect(data.attendance.error, serverError);

      eclass.failingCourses = {ai.id: LoginRequired(Service.eclass)};
      await data.refreshEclass();
      expect(data.attendance.error, isA<LoginRequired>());
    });
  });

  group('upcoming events beyond the calendar page', () {
    final soon = DateTime.now().add(const Duration(days: 2));
    final later = DateTime.now().add(const Duration(days: 9));

    test('course pages are merged in, without repeats, by time', () async {
      final (data, eclass, _, _, _) = await makeAppData();
      final both = due('Quiz 1', course: ai, end: later, moduleId: 7);
      eclass
        ..courseList = const [ai, os]
        ..deadlines = [both]
        ..upcomingById = {
          ai.id: [both, due('Past the cut', course: ai, end: soon)],
          os.id: [due('OS lab', course: os, end: later.add(const Duration(days: 1)))],
        };
      await data.refreshEclass();
      expect(data.deadlines.data?.value.map((d) => d.title), ['Past the cut', 'Quiz 1', 'OS lab']);
      expect(data.deadlines.error, isNull);
    });

    test('a course page failing keeps that course\'s cached events and loses nothing else', () async {
      final (data, eclass, _, _, _) = await makeAppData();
      eclass
        ..courseList = const [ai, os]
        ..upcomingById = {
          ai.id: [due('AI lab', course: ai, end: soon)],
          os.id: [due('OS lab', course: os, end: later)],
        };
      await data.refreshEclass();

      eclass
        ..failingUpcoming = {os.id}
        ..upcomingById = {ai.id: []};
      await data.refreshEclass();
      expect(data.deadlines.data?.value.map((d) => d.title), ['OS lab']);
      expect(data.deadlines.error, isNull);
    });

    test('the all-courses page failing is forgiven while the course pages answer', () async {
      final (base, _, timetable, ins, mail) = await makeAppData();
      final eclass = _NoCalendar()
        ..courseList = const [ai]
        ..upcomingById = {
          ai.id: [due('AI lab', course: ai, end: soon)],
        };
      final data = AppData(eclass: eclass, timetable: timetable, ins: ins, mail: mail, cache: base.cache, prefs: base.prefs);
      await data.refreshEclass();
      expect(data.deadlines.data?.value.single.title, 'AI lab');
    });

    test('nothing answering fails the list', () async {
      final (data, eclass, _, _, _) = await makeAppData();
      eclass.error = dropped;
      await data.refreshEclass();
      expect(data.deadlines.data, isNull);
      expect(data.deadlines.error, dropped);
    });
  });

  group('marking a deadline done', () {
    test('it reads as dismissed, stays so through a refresh, and can be taken back', () async {
      final (data, eclass, _, _, _) = await makeAppData();
      final lab = due('Paper lab', end: DateTime(2030, 1, 1));
      eclass.deadlines = [lab];
      await data.refreshEclass();
      var replans = 0;
      data.onReminderDataChanged = () async => replans++;

      await data.markDeadlineDone(data.deadlines.data!.value.single);
      expect(data.deadlines.data!.value.single.dismissed, isTrue);
      expect(data.deadlines.data!.value.single.done, isFalse);
      expect(replans, 1);

      await data.refreshEclass();
      expect(data.deadlines.data!.value.single.dismissed, isTrue);

      await data.markDeadlineDone(lab, done: false);
      expect(data.deadlines.data!.value.single.dismissed, isFalse);
    });
  });

  group('bell menu', () {
    test('refreshes with eClass, is cached, and goes with the account', () async {
      final (data, eclass, _, _, _) = await makeAppData();
      eclass.notices = [EclassNotification(id: 1, subject: 'Room changed', text: 'B-305', time: DateTime(2026, 10, 22))];
      await data.refreshEclass();
      expect(data.eclassNotifications.data?.value.single.subject, 'Room changed');
      expect(data.cache.read('notifications', (j) => j), isNotNull);
      await data.forget(Service.eclass);
      expect(data.eclassNotifications.data, isNull);
      expect(data.cache.read('notifications', (j) => j), isNull);
    });
  });

  group('mail list', () {
    Future<(AppData, FakeMail)> loaded() async {
      final (data, _, _, _, mail) = await makeAppData();
      mail.all = [for (var i = 0; i < 70; i++) mailHeader(i)];
      await data.refreshMailFolder(MailFolder.inbox);
      await data.loadMoreMail();
      return (data, mail);
    }

    test('a resume keeps the older pages loaded', () async {
      final (data, _) = await loaded();
      expect(data.inbox.data?.value, hasLength(60));
      await data.reloadFromCache();
      expect(data.inbox.data?.value, hasLength(60));
      expect(data.mailbox(MailFolder.inbox).hasMore, isTrue);
    });

    test('a folder refreshed elsewhere is replaced, and can be scrolled again', () async {
      final (data, mail) = await loaded();
      data.mailbox(MailFolder.inbox).hasMore = false;
      await data.cache.write<List<MailHeader>>(
          'inbox', [mailHeader(0)], (v) => v.map((m) => m.toJson()).toList(), at: DateTime(2030));
      await data.reloadFromCache();
      expect(data.inbox.data?.value, hasLength(1));
      expect(data.mailbox(MailFolder.inbox).hasMore, isTrue);
      expect(mail.pages, isNotEmpty);
    });

    test('a page arriving after a refresh started is dropped', () async {
      final (base, _, timetable, ins, _) = await makeAppData();
      final mail = _SlowPages()..all = [for (var i = 0; i < 70; i++) mailHeader(i)];
      final data = AppData(
          eclass: FakeEclass(), timetable: timetable, ins: ins, mail: mail, cache: base.cache, prefs: base.prefs);
      await data.refreshMailFolder(MailFolder.inbox);

      mail.gate = Completer<void>();
      final more = data.loadMoreMail();
      await pumpEventQueue();
      final gate = mail.gate!;
      mail.gate = null;
      mail.all = [mailHeader(100), ...mail.all];
      await data.refreshMailFolder(MailFolder.inbox);
      final refreshed = data.inbox.data!.value;
      expect(refreshed.first.id, 'id100');

      gate.complete();
      await more;
      expect(data.inbox.data!.value, same(refreshed));
      expect(data.mailbox(MailFolder.inbox).loadingMore, isFalse);
    });

    test('an edit while a page loads is kept', () async {
      final (base, _, timetable, ins, _) = await makeAppData();
      final mail = _SlowPages()..all = [for (var i = 0; i < 70; i++) mailHeader(i, unread: true)];
      final data = AppData(
          eclass: FakeEclass(), timetable: timetable, ins: ins, mail: mail, cache: base.cache, prefs: base.prefs);
      await data.refreshMailFolder(MailFolder.inbox);

      mail.gate = Completer<void>();
      final more = data.loadMoreMail();
      await pumpEventQueue();
      final gate = mail.gate!;
      mail.gate = null;
      await data.setMailRead('id0');
      gate.complete();
      await more;
      expect(data.inbox.data!.value, hasLength(60));
      expect(data.inbox.data!.value.first.unread, isFalse);
    });

    test('search goes to the folder asked for and stays out of the cache', () async {
      final (data, _, _, _, mail) = await makeAppData();
      mail.folders[MailFolder.sent] = [mailHeader(1)];
      expect((await data.searchMail('Notice', folder: MailFolder.sent)).single.id, 'id1');
      expect(mail.searches.single, (MailFolder.sent, 'Notice'));
      expect(data.mailbox(MailFolder.sent).list.data, isNull);
    });

    test('a moved message keeps its attachment flag', () async {
      final (data, _, _, _, _) = await makeAppData();
      final m = MailHeader(id: 'a', from: 'x', subject: 's', received: DateTime(2026), hasAttachments: true);
      expect((await data.moveMail(m, from: MailFolder.inbox, to: MailFolder.junk))?.hasAttachments, isTrue);
    });
  });

  group('what counts as a network failure', () {
    DioException unknown(Object cause) =>
        DioException(requestOptions: RequestOptions(path: '/'), type: DioExceptionType.unknown, error: cause);
    final server = DioException.badResponse(
        statusCode: 502,
        requestOptions: RequestOptions(path: '/'),
        response: Response(requestOptions: RequestOptions(path: '/'), statusCode: 502));

    test('a connection reset mid-response is the network, retried and described as such', () {
      for (final cause in [const HttpException('Connection closed'), const SocketException('reset')]) {
        final reset = unknown(cause);
        expect(isNetworkError(reset), isTrue);
        expect(isWorthRetrying(reset), isTrue);
        expect(describeError(reset, 'eClass'), "Couldn't reach eClass. Check the connection.");
      }
      expect(isNetworkError(unknown(StateError('a bug'))), isFalse);
    });

    test('a 5xx is retried, and is not "offline" or the device\'s connection', () {
      expect(isNetworkError(server), isFalse);
      expect(isWorthRetrying(server), isTrue);
      expect(describeError(server, 'INS'), "Couldn't reach INS.");
    });

    test('a login or a changed page is not retried', () {
      expect(isWorthRetrying(LoginRequired(Service.ins)), isFalse);
      expect(isWorthRetrying(ParseError('x')), isFalse);
    });
  });

  test('a cached time zone change: the fetch time stays the same moment', () async {
    SharedPreferences.setMockInitialValues({});
    final cache = JsonCache(await SharedPreferences.getInstance());
    final at = DateTime(2026, 10, 22, 9, 30);
    await cache.write('x', 1, (v) => v, at: at);
    expect(cache.read('x', (j) => j)!.fetchedAt, at);
    expect((await SharedPreferences.getInstance()).getString('cache.x'), contains('Z'));
  });
}

class _NoCalendar extends FakeEclass {
  @override
  Future<List<Deadline>> upcoming() async => throw Exception('eClass did not answer');
}

class _SlowPages extends FakeMail {
  Completer<void>? gate;

  @override
  Future<List<MailHeader>> folder(MailFolder folder, {int limit = 30, int offset = 0}) async {
    final waiting = gate;
    final page = await super.folder(folder, limit: limit, offset: offset);
    await waiting?.future;
    return page;
  }
}

