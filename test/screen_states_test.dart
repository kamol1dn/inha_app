import 'package:flutter/material.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:inha_app/app.dart';
import 'package:inha_app/core/cache.dart';
import 'package:inha_app/core/credentials.dart';
import 'package:inha_app/core/session.dart';
import 'package:inha_app/data/app_data.dart';
import 'package:inha_app/features/absence_widgets.dart';
import 'package:inha_app/features/common.dart';
import 'package:inha_app/features/course_detail_screen.dart';
import 'package:inha_app/features/courses_screen.dart';
import 'package:inha_app/features/deadlines_screen.dart';
import 'package:inha_app/features/details.dart';
import 'package:inha_app/features/grades_screen.dart';
import 'package:inha_app/features/mail_screen.dart';
import 'package:inha_app/features/notices_screen.dart';
import 'package:inha_app/features/rail_rows.dart';
import 'package:inha_app/features/settings_screen.dart';
import 'package:inha_app/features/timetable_screen.dart';
import 'package:inha_app/features/today_screen.dart';
import 'package:inha_app/models/models.dart';
import 'package:inha_app/notifications/notifier.dart';
import 'package:inha_app/notifications/routes.dart';
import 'package:inha_app/notifications/rules.dart' show PlannedNotification;
import 'package:inha_app/ui/theme/status_colors.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:provider/provider.dart';

import 'fakes.dart';
import 'screens_test.dart' show ai, esd, offline;

// The states of DESIGN.md 13 that aren't the happy path, screen by screen: what
// each says when a service failed, had nothing, or is older than it looks.

/// Pumps [screen] at a size the test can see all of, unless told otherwise.
Future<void> pump(WidgetTester tester, AppData data, Widget screen,
    {Size size = const Size(412, 2400), double scale = 1, bool scaffold = true, NotificationTaps? taps}) async {
  tester.view.physicalSize = size * 3;
  tester.view.devicePixelRatio = 3;
  addTearDown(tester.view.reset);
  await tester.pumpWidget(MultiProvider(
    providers: [
      ChangeNotifierProvider.value(value: data),
      ChangeNotifierProvider.value(value: taps ?? NotificationTaps()),
    ],
    child: MaterialApp(
      theme: InhaApp.light,
      home: Builder(
        builder: (context) => MediaQuery(
          data: MediaQuery.of(context).copyWith(textScaler: TextScaler.linear(scale)),
          child: scaffold ? Scaffold(body: screen) : screen,
        ),
      ),
    ),
  ));
  await tester.pump();
}

Finder statusLine(Status s) => find.byWidgetPredicate((w) => w is StatusLine && w.status == s);

AttendanceEntry absent(DateTime day) => AttendanceEntry(date: day, label: '1Class', mark: AttendanceMark.absent);
AttendanceEntry present(DateTime day) => AttendanceEntry(date: day, label: '1Class', mark: AttendanceMark.present);

/// A course with [absences] absences and one class attended, all in the past.
CourseAttendance taking(Course c, int absences, DateTime now) => CourseAttendance(course: c, classes: [
      for (var i = 0; i < absences; i++) absent(now.subtract(Duration(days: 7 * i + 1))),
      present(now.subtract(const Duration(days: 90))),
    ]);

const noCourse = Lesson(weekday: 1, start: '09:00', end: '10:30', subject: 'Mental Education', room: 'B-305', teacher: 'J. Hong', kind: 'Lecture');

/// A Notifier that only answers what Settings asks, and counts nothing it isn't told.
class QuietNotifier extends Notifier {
  bool allowed;
  bool grants;
  QuietNotifier({this.allowed = true, this.grants = true});

  @override
  Future<NotifySettings> settings() async => const NotifySettings(channels: NotifySettings.defaultChannels);
  @override
  Future<bool> enabled() async => allowed;
  @override
  Future<bool> requestPermission() async {
    allowed = grants;
    return grants;
  }

  @override
  Future<void> saveSettings(NotifySettings s) async {}
  @override
  Future<void> deliver(List<PlannedNotification> plan,
      {DateTime? now, Set<String> cancelMissing = const {}, Set<String> record = const {}, Set<String> withdraw = const {}}) async {}
}

class QuietSessions extends Sessions {
  @override
  Future<void> reset(Service s) async {}
}

Future<void> pumpSettings(WidgetTester tester, AppData data, {QuietNotifier? notifier}) async {
  tester.view.physicalSize = const Size(412, 2400) * 3;
  tester.view.devicePixelRatio = 3;
  addTearDown(tester.view.reset);
  await tester.pumpWidget(MultiProvider(
    providers: [
      ChangeNotifierProvider.value(value: data),
      Provider<CredentialStore>.value(value: CredentialStore()),
      Provider<Sessions>.value(value: QuietSessions()),
      Provider<Notifier>.value(value: notifier ?? QuietNotifier()),
    ],
    child: MaterialApp(theme: InhaApp.light, home: const SettingsScreen()),
  ));
  await tester.pumpAndSettle();
}

void main() {
  group('offline', () {
    Future<(AppData, FakeMail, FakeIns)> allDown() async {
      final (data, eclass, timetable, ins, mail) = await makeAppData();
      eclass.error = offline();
      timetable.error = offline();
      mail.error = offline();
      ins.error = offline();
      await Future.wait([data.refreshTimetable(), data.refreshEclass(), data.refreshMail(), data.refreshGrades()]);
      expect(isOffline(data), isTrue);
      return (data, mail, ins);
    }

    testWidgets('Mail and Grades have no offline row, so they keep their own error', (tester) async {
      final (data, _, _) = await allDown();
      await pump(tester, data, const MailScreen());
      expect(find.text("Couldn't reach Mail. Check the connection."), findsOneWidget);
      await pump(tester, data, const GradesScreen(), scaffold: false);
      expect(find.text("Couldn't reach INS. Check the connection."), findsOneWidget);
    });

    testWidgets('the four tabs with one leave a network failure to it', (tester) async {
      final (data, _, _) = await allDown();
      for (final screen in [
        const TimetableScreen(),
        const DeadlinesScreen(),
        const CoursesScreen(),
      ]) {
        await pump(tester, data, screen);
        expect(find.textContaining('Offline'), findsOneWidget);
        expect(find.textContaining("Couldn't reach"), findsNothing);
      }
    });

    testWidgets('course detail, with no offline row of its own, keeps its error too', (tester) async {
      final (data, _, _) = await allDown();
      await pump(tester, data, const CourseDetailScreen(courseId: 2622, name: 'Artificial Intelligence'), scaffold: false);
      expect(find.text("Couldn't reach eClass. Check the connection."), findsOneWidget);
    });
  });

  group('Mail list', () {
    testWidgets('past 30 min it carries its age; a fresh list does not', (tester) async {
      final (data, _, _, _, _) = await makeAppData();
      final box = data.mailbox(MailFolder.inbox);
      box.list = Snapshot(data: Cached([mailHeader(0)], DateTime.now().subtract(const Duration(minutes: 31))));
      await pump(tester, data, const MailScreen());
      expect(find.textContaining('Inbox as of'), findsOneWidget);

      box.list = Snapshot(data: Cached([mailHeader(0)], DateTime.now().subtract(const Duration(minutes: 29))));
      await pump(tester, data, const MailScreen());
      expect(find.textContaining('as of'), findsNothing);
    });
  });

  group('From eClass', () {
    final at = DateTime.now().subtract(const Duration(hours: 2));
    EclassNotification item(int id, {bool read = false, String? url}) =>
        EclassNotification(id: id, subject: 'Subject $id', text: 'Text $id', url: url, time: at, read: read);

    Future<AppData> withNotices(List<EclassNotification> notices) async {
      final (data, eclass, _, _, _) = await makeAppData();
      eclass.notices = notices;
      await data.refreshEclass();
      return data;
    }

    testWidgets('Today lists the newest unread ones, and leads to all of them with their text', (tester) async {
      final data = await withNotices([for (var i = 1; i <= 6; i++) item(i), item(7, read: true)]);
      await pump(tester, data, TodayScreen(onOpenTab: (_) {}, onOpenSchedule: (_) {}));
      expect(find.text('From eClass'), findsOneWidget);
      for (var i = 1; i <= 4; i++) {
        expect(find.text('Subject $i'), findsOneWidget);
      }
      expect(find.text('Subject 5'), findsNothing);
      expect(find.text('Text 1'), findsNothing);

      await tester.tap(find.text('All 7 notifications'));
      await tester.pumpAndSettle();
      expect(find.byType(NoticesScreen), findsOneWidget);
      expect(find.text('Text 1'), findsOneWidget);
      expect(find.text('Subject 7'), findsOneWidget);
    });

    testWidgets('a read list leaves the way to it; nothing at all leaves no section', (tester) async {
      final data = await withNotices([item(1, read: true)]);
      await pump(tester, data, TodayScreen(onOpenTab: (_) {}, onOpenSchedule: (_) {}));
      expect(find.text('Subject 1'), findsNothing);
      expect(find.text('All 1 notification'), findsOneWidget);

      await pump(tester, await withNotices(const []), TodayScreen(onOpenTab: (_) {}, onOpenSchedule: (_) {}));
      expect(find.text('From eClass'), findsNothing);
    });

    testWidgets('a row is a link only when it stays on eClass', (tester) async {
      final data = await withNotices([
        item(1, url: 'https://eclass.inha.ac.kr/mod/assign/view.php?id=4'),
        item(2, url: 'https://eclass.inha.ac.kr.example.org/x'),
        item(3),
      ]);
      await pump(tester, data, const NoticesScreen(), scaffold: false);
      expect(find.widgetWithText(InkWell, 'Subject 1'), findsOneWidget);
      expect(find.widgetWithText(InkWell, 'Subject 2'), findsNothing);
      expect(find.widgetWithText(InkWell, 'Subject 3'), findsNothing);
    });

    testWidgets('tapping a bell-menu notification opens them, with its text, over Today', (tester) async {
      final data = await withNotices([item(1)]);
      data.prefs.notificationsAsked = true;
      final taps = NotificationTaps();
      tester.view.physicalSize = const Size(412, 900) * 3;
      tester.view.devicePixelRatio = 3;
      addTearDown(tester.view.reset);
      await tester.pumpWidget(MultiProvider(
        providers: [
          ChangeNotifierProvider.value(value: data),
          ChangeNotifierProvider.value(value: taps),
          Provider<Notifier>.value(value: QuietNotifier()),
        ],
        child: MaterialApp(theme: InhaApp.light, home: const HomeShell()),
      ));
      await tester.pump();
      taps.value = 'notice:1';
      await tester.pumpAndSettle();
      expect(find.byType(NoticesScreen), findsOneWidget);
      expect(find.text('Text 1'), findsOneWidget);
      await tester.pageBack();
      await tester.pumpAndSettle();
      expect(find.text('From eClass'), findsOneWidget, reason: 'Today, with its own section');
    });

    testWidgets('empty, it says so', (tester) async {
      await pump(tester, await withNotices(const []), const NoticesScreen(), scaffold: false);
      expect(find.text('No notifications from eClass.'), findsOneWidget);
    });
  });

  group('Settings', () {
    setUp(() {
      FlutterSecureStorage.setMockInitialValues({
        'eclass.username': 'test-user',
        'eclass.password': 'test-password',
        'mail.username': 'test-user',
        'mail.password': 'test-password',
      });
      PackageInfo.setMockInitialValues(
          appName: 'IUT', packageName: 'uz.inha.test', version: '1.3.0', buildNumber: '4', buildSignature: '');
    });

    Future<void> signOutOf(WidgetTester tester, String row) async {
      await tester.tap(find.text(row));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Sign out'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Sign out').last);
      await tester.pumpAndSettle();
    }

    testWidgets('after signing out of eClass the tabs say Sign in, not a loading skeleton', (tester) async {
      final (data, eclass, _, _, _) = await makeAppData();
      await data.refreshEclass();
      await pumpSettings(tester, data);
      eclass.error = LoginRequired(Service.eclass, 'no saved login'); // the login is gone
      await signOutOf(tester, 'eClass');

      expect(data.deadlines.error, isA<LoginRequired>());
      expect(data.attendance.error, isA<LoginRequired>());
      expect(data.prefs.accountCheck(Service.eclass), isNull, reason: 'that refusal was no login of theirs');
      await pump(tester, data, const DeadlinesScreen());
      expect(find.bySemanticsLabel('Loading'), findsNothing);
      expect(find.text('Sign in to eClass to see deadlines and attendance.'), findsOneWidget);
      await pump(tester, data, const CoursesScreen());
      expect(find.bySemanticsLabel('Loading'), findsNothing);
      expect(find.text('Sign in'), findsOneWidget);
    });

    testWidgets('after signing out of mail every folder says Sign in', (tester) async {
      final (data, _, _, _, mail) = await makeAppData();
      await data.refreshMail();
      await pumpSettings(tester, data);
      mail.error = LoginRequired(Service.mail, 'no saved login');
      await signOutOf(tester, 'University mail');

      for (final f in MailFolder.values) {
        expect(data.mailbox(f).list.error, isA<LoginRequired>(), reason: f.label);
      }
      await pump(tester, data, const MailScreen(folder: MailFolder.sent));
      expect(find.bySemanticsLabel('Loading'), findsNothing);
      expect(find.text('Sign in'), findsOneWidget);
    });

    group('another account in the sheet', () {
      Future<(AppData, List<Service>)> saved(WidgetTester tester, {required String id, String? password}) async {
        final (data, _, _, _, _) = await makeAppData();
        final told = <Service>[];
        data.onSignedOut = (s) async => told.add(s);
        data.prefs.dismissedDeadlines = {'due:assignment:ai|lab|20261025T1859Z'};
        await pumpSettings(tester, data);
        await tester.tap(find.text('eClass'));
        await tester.pumpAndSettle();
        await tester.enterText(find.widgetWithText(TextField, 'Student ID'), id);
        if (password != null) await tester.enterText(find.widgetWithText(TextField, 'Password'), password);
        await tester.tap(find.text('Save and test'));
        await tester.pumpAndSettle();
        return (data, told);
      }

      testWidgets('the last one\'s memory goes, as on signing out', (tester) async {
        final (data, told) = await saved(tester, id: 'another-user', password: 'another-password');
        expect(told, [Service.eclass]);
        expect(data.prefs.dismissedDeadlines, isEmpty);
        expect(find.text('Signed in'), findsOneWidget);
      });

      testWidgets('the same ID with a new password keeps it', (tester) async {
        final (data, told) = await saved(tester, id: ' test-user ', password: 'new-password');
        expect(told, isEmpty);
        expect(data.prefs.dismissedDeadlines, isNotEmpty);
      });

      testWidgets('the saved password does not go with another ID, and nothing is forgotten for trying', (tester) async {
        final (data, told) = await saved(tester, id: 'another-user');
        expect(find.text('Enter the password.'), findsOneWidget);
        expect(told, isEmpty);
        expect(data.prefs.dismissedDeadlines, isNotEmpty);
      });

      testWidgets('going back to the first ID in the same sheet counts as another account too', (tester) async {
        final (_, told) = await saved(tester, id: 'another-user', password: 'another-password');
        await tester.enterText(find.widgetWithText(TextField, 'Student ID'), 'test-user');
        await tester.enterText(find.widgetWithText(TextField, 'Password'), 'test-password');
        await tester.tap(find.text('Save and test'));
        await tester.pumpAndSettle();
        expect(told, [Service.eclass, Service.eclass]);
      });
    });

    testWidgets('an edit after a good test goes back to Save and test, so Done cannot lose it', (tester) async {
      final (data, _, _, _, _) = await makeAppData();
      await pumpSettings(tester, data);
      await tester.tap(find.text('eClass'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Save and test'));
      await tester.pumpAndSettle();
      expect(find.text('Signed in'), findsOneWidget);
      expect(find.text('Done'), findsOneWidget);

      await tester.enterText(find.widgetWithText(TextField, 'Password'), 'another-password');
      await tester.pump();
      expect(find.text('Done'), findsNothing);
      expect(find.text('Save and test'), findsOneWidget);
      expect(find.text('Signed in'), findsNothing);
    });

    testWidgets('moving the cursor is no edit', (tester) async {
      final (data, _, _, _, _) = await makeAppData();
      await pumpSettings(tester, data);
      await tester.tap(find.text('eClass'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Save and test'));
      await tester.pumpAndSettle();
      await tester.tap(find.widgetWithText(TextField, 'Student ID'));
      await tester.pump();
      expect(find.text('Done'), findsOneWidget);
    });

    testWidgets('allowing notifications plans the reminders at once', (tester) async {
      final (data, _, _, _, _) = await makeAppData();
      var plans = 0;
      data.onReminderDataChanged = () async => plans++;
      await pumpSettings(tester, data, notifier: QuietNotifier(allowed: false));
      await tester.tap(find.text('Allow'));
      await tester.pumpAndSettle();
      expect(plans, 1);
      expect(find.text('Allow'), findsNothing);
    });

    testWidgets('refusing plans nothing, and the row stays', (tester) async {
      final (data, _, _, _, _) = await makeAppData();
      var plans = 0;
      data.onReminderDataChanged = () async => plans++;
      await pumpSettings(tester, data, notifier: QuietNotifier(allowed: false, grants: false));
      await tester.tap(find.text('Allow'));
      await tester.pumpAndSettle();
      expect(plans, 0);
      expect(find.text('Allow'), findsOneWidget);
    });

    testWidgets('About says which version this is', (tester) async {
      final (data, _, _, _, _) = await makeAppData();
      await pumpSettings(tester, data);
      expect(find.text('Version 1.3.0 (4)'), findsOneWidget);
    });
  });

  group('course detail', () {
    final now = DateTime.now();
    Future<(AppData, FakeEclass, FakeIns, FakeTimetable)> withCourse(CourseAttendance c, {int? limit}) async {
      final (data, eclass, timetable, ins, _) = await makeAppData(prefs: {if (limit != null) 'absenceLimits.v1': '{"${ai.id}": $limit}'});
      eclass.courseList = [c.course];
      eclass.attendanceById = {c.course.id: c};
      await data.refreshEclass();
      return (data, eclass, ins, timetable);
    }

    const screen = CourseDetailScreen(courseId: 2622, name: 'Artificial Intelligence');

    testWidgets('over the limit the count reads 10 of 8, and the caption has no stray word', (tester) async {
      final (data, _, _, _) = await withCourse(taking(ai, 10, now), limit: 8);
      await pump(tester, data, screen, scaffold: false);
      expect(find.text('10 of 8'), findsOneWidget);
      expect(find.text('allowed absences used · 11 classes held so far'), findsOneWidget);
      expect(find.text('Over the limit by 2'), findsOneWidget);
    });

    testWidgets('with no limit it reads the raw count and says the limit is not set', (tester) async {
      final (data, _, _, _) = await withCourse(taking(ai, 1, now));
      await pump(tester, data, screen, scaffold: false);
      expect(find.text('1'), findsOneWidget);
      expect(find.text('absence · limit not set · 2 classes held so far'), findsOneWidget);
    });

    testWidgets('a failed refresh shows on the count and on every section it feeds', (tester) async {
      final vods = CourseAttendance(
          course: ai,
          classes: taking(ai, 2, now).classes,
          vods: const [VodProgress(week: 7, title: 'Video 7', length: Duration(minutes: 55), percent: 62)]);
      final (data, eclass, _, _) = await withCourse(vods, limit: 8);
      eclass.error = offline();
      await data.refreshEclass();
      await pump(tester, data, screen, scaffold: false);
      expect(find.textContaining("Couldn't reach eClass. Check the connection. Showing data from"), findsOneWidget);
      expect(find.byType(StaleMarker), findsNWidgets(4), reason: 'the count, Scores, VOD lectures and Classes so far');
    });

    testWidgets('the grade row says what is true: loading, signed out, failed, or no record', (tester) async {
      final (data, _, ins, _) = await withCourse(taking(ai, 0, now));
      await pump(tester, data, screen, scaffold: false);
      expect(find.textContaining('Sign in to INS'), findsNothing); // nothing asked yet
      expect(find.bySemanticsLabel('Loading'), findsOneWidget);

      ins.error = offline();
      await data.refreshGrades();
      await tester.pump();
      expect(find.text("Couldn't reach INS. Check the connection."), findsOneWidget);
      expect(find.textContaining('Sign in to INS'), findsNothing);

      ins.error = LoginRequired(Service.ins, 'no saved login');
      await data.refreshGrades();
      await tester.pump();
      expect(find.text('Sign in to INS to see grades.'), findsOneWidget);
      expect(find.text('Sign in'), findsOneWidget);

      ins.error = null;
      await data.refreshGrades();
      await tester.pump();
      expect(find.text('INS has no record of this course.'), findsOneWidget);
    });

    testWidgets("lists the course's weekly classes, and a row opens Schedule on that day", (tester) async {
      final (data, _, _, timetable) = await withCourse(taking(ai, 0, now));
      timetable.lessonList = const [
        Lesson(weekday: 3, start: '13:00', end: '14:30', subject: 'Artificial Intelligence', room: 'B202', kind: 'Lab'),
        Lesson(weekday: 1, start: '09:00', end: '10:30', subject: 'Artificial Intelligence', room: 'B101', kind: 'Lecture', teacher: 'J. Kim'),
        Lesson(weekday: 1, start: '11:00', end: '12:30', subject: 'Embedded Software & Design', room: 'B305'),
      ];
      await data.refreshTimetable();
      final taps = NotificationTaps();
      await pump(tester, data, screen, scaffold: false, taps: taps);
      expect(find.text('In the timetable'), findsOneWidget);
      expect(find.text('Mon 09:00'), findsOneWidget);
      expect(find.text('Wed 13:00'), findsOneWidget);
      expect(find.text('B101 · Lecture · J. Kim'), findsOneWidget);
      expect(find.text('B305'), findsNothing);
      // Earliest in the week first.
      expect(tester.getTopLeft(find.text('Mon 09:00')).dy, lessThan(tester.getTopLeft(find.text('Wed 13:00')).dy));

      await tester.tap(find.text('Wed 13:00'));
      expect(notificationTarget(taps.value!), isA<ScheduleTarget>().having((t) => t.weekday, 'weekday', 3));
    });

    testWidgets('a course with no class on the timetable has no such section', (tester) async {
      final (data, _, _, _) = await withCourse(taking(ai, 0, now));
      await pump(tester, data, screen, scaffold: false);
      expect(find.text('In the timetable'), findsNothing);
    });
  });

  group('Schedule', () {
    testWidgets('after a failure with no cache: the error, no skeleton and no claim about classes', (tester) async {
      final (data, _, timetable, _, _) = await makeAppData();
      timetable.error = Exception('EduPage did not answer');
      await data.refreshTimetable();
      await pump(tester, data, const TimetableScreen());
      expect(find.textContaining("Couldn't"), findsOneWidget);
      expect(find.text('Retry'), findsOneWidget);
      expect(find.bySemanticsLabel('Loading'), findsNothing);
      expect(find.textContaining('No classes'), findsNothing);
    });

    testWidgets('while the first load runs there is a skeleton', (tester) async {
      final (data, _, _, _, _) = await makeAppData();
      await pump(tester, data, const TimetableScreen());
      expect(find.bySemanticsLabel('Loading'), findsOneWidget);
    });

    testWidgets('with no class group it offers Settings, not Retry', (tester) async {
      final (data, _, _, _, _) = await makeAppData(classGroupChosen: false);
      await data.refreshTimetable();
      await pump(tester, data, const TimetableScreen());
      expect(find.text('Choose your class group in Settings.'), findsOneWidget);
      expect(find.text('Settings'), findsOneWidget);
      expect(find.text('Retry'), findsNothing);
      expect(find.textContaining('No classes'), findsNothing);
    });

    testWidgets('an empty day names the next class', (tester) async {
      final (data, _, timetable, _, _) = await makeAppData();
      timetable.lessonList = const [
        Lesson(weekday: 1, start: '09:00', end: '10:30', subject: 'Multimedia Computing', room: 'B-305'),
      ];
      await data.refreshTimetable();
      await pump(tester, data, TimetableScreen(clock: () => DateTime(2026, 11, 5, 10))); // a Thursday
      expect(find.text('No classes on Thu 5 Nov. Next: Mon 9 Nov, 09:00 Multimedia Computing, B-305.'), findsOneWidget);
    });

    testWidgets('with nothing on the timetable an empty day says only that', (tester) async {
      final (data, _, _, _, _) = await makeAppData();
      await data.refreshTimetable();
      await pump(tester, data, TimetableScreen(clock: () => DateTime(2026, 11, 5, 10)));
      expect(find.text('No classes on Thu 5 Nov.'), findsOneWidget);
    });

    group('the selected day', () {
      TabController days(WidgetTester tester) => tester.widget<TabBar>(find.byType(TabBar)).controller!;
      Future<void> resume(WidgetTester tester) async {
        tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.paused);
        tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
        await tester.pumpAndSettle();
      }

      testWidgets('follows the date when the app comes back on another day', (tester) async {
        final (data, _, _, _, _) = await makeAppData();
        var at = DateTime(2026, 11, 3, 10); // Tuesday
        await pump(tester, data, TimetableScreen(clock: () => at));
        expect(days(tester).index, 1);
        at = DateTime(2026, 11, 4, 8);
        await resume(tester);
        expect(days(tester).index, 2);
        // After a weekend, Monday of the new week, not last Friday's tab.
        at = DateTime(2026, 11, 9, 8);
        await resume(tester);
        expect(days(tester).index, 0);
      });

      testWidgets("keeps the student's pick on the same date", (tester) async {
        final (data, _, _, _, _) = await makeAppData();
        var at = DateTime(2026, 11, 3, 10);
        await pump(tester, data, TimetableScreen(clock: () => at));
        tester.state<TimetableScreenState>(find.byType(TimetableScreen)).showWeekday(5);
        await tester.pumpAndSettle();
        expect(days(tester).index, 4);
        at = DateTime(2026, 11, 3, 18);
        await resume(tester);
        expect(days(tester).index, 4);
      });
    });
  });

  group('Deadlines', () {
    testWidgets('Overdue is only what is still owed; done work and class periods stay under their day', (tester) async {
      final now = DateTime.now();
      final (data, eclass, _, _, _) = await makeAppData();
      data.prefs.deadlineKinds = {...Prefs.defaultDeadlineKinds, DeadlineKind.classPeriod};
      final past = now.subtract(const Duration(hours: 2));
      eclass.deadlines = [
        Deadline(title: 'Lab 4', courseName: 'Multimedia Computing', kind: DeadlineKind.assignment, end: past),
        Deadline(title: 'Lab 3', courseName: 'Multimedia Computing', kind: DeadlineKind.assignment, end: past, moduleId: 31),
        Deadline(title: 'Week 3 class', courseName: 'Multimedia Computing', kind: DeadlineKind.classPeriod, end: past),
        Deadline(title: 'Week 4 class', courseName: 'Multimedia Computing', kind: DeadlineKind.classPeriod, end: now.add(const Duration(hours: 2))),
        Deadline(title: 'Lab 1', courseName: 'Multimedia Computing', kind: DeadlineKind.assignment, end: now.subtract(const Duration(hours: 25))),
      ];
      eclass.submissions = {31: (done: true, at: past)};
      await data.refreshEclass();
      await pump(tester, data, const DeadlinesScreen());

      expect(find.text('Overdue'), findsOneWidget);
      final overdueAt = tester.getTopLeft(find.text('Overdue')).dy;
      final dayHeaders = find.byWidgetPredicate((w) => w is SectionHeader && w.text != 'Overdue');
      final firstDay = tester.getTopLeft(dayHeaders.first).dy;
      expect(overdueAt, lessThan(firstDay));
      // Lab 4 is the only row between the Overdue header and the first day.
      expect(tester.getTopLeft(find.text('Lab 4')).dy, lessThan(firstDay));
      expect(tester.getTopLeft(find.text('Lab 3')).dy, greaterThan(firstDay));
      expect(tester.getTopLeft(find.text('Week 3 class')).dy, greaterThan(firstDay));
      // A class period has no due wording; more than a day past is left out.
      expect(find.textContaining('Due in'), findsNothing);
      expect(find.text('Lab 1'), findsNothing);
    });

    testWidgets('a chip turned off and on again is no filter', (tester) async {
      final (data, _, _, _, _) = await makeAppData();
      await data.refreshEclass();
      data.prefs.deadlineKinds = {...Prefs.defaultDeadlineKinds}; // equal, not identical
      await pump(tester, data, const DeadlinesScreen());
      expect(find.text('No upcoming deadlines in eClass.'), findsOneWidget);
      expect(find.text('Nothing matches these filters.'), findsNothing);
    });

    testWidgets("the course chip's arrow says what it does", (tester) async {
      final (data, _, _, _, _) = await makeAppData();
      await pump(tester, data, const DeadlinesScreen());
      expect(tester.widget<InputChip>(find.byType(InputChip)).deleteButtonTooltipMessage, 'Choose course');
    });

    testWidgets('an old list with only overdue items still carries its age', (tester) async {
      final now = DateTime.now();
      final (data, _, _, _, _) = await makeAppData();
      data.deadlines = Snapshot(
          data: Cached([
        Deadline(title: 'Lab 4', courseName: 'Multimedia Computing', kind: DeadlineKind.assignment, end: now.subtract(const Duration(hours: 2))),
      ], now.subtract(const Duration(hours: 4))));
      await pump(tester, data, const DeadlinesScreen());
      expect(find.byType(StaleMarker), findsOneWidget);
    });
  });

  group('deadline sheet', () {
    testWidgets('a watched VOD closing soon has no red countdown', (tester) async {
      final now = DateTime.now();
      final (data, eclass, _, _, _) = await makeAppData();
      eclass.courseList = [ai];
      eclass.attendanceById = {
        ai.id: const CourseAttendance(course: ai, vods: [
          VodProgress(week: 7, title: 'Video 7', length: Duration(minutes: 55), percent: 100),
        ]),
      };
      eclass.deadlines = [
        Deadline(title: 'Video 7', courseName: 'Artificial Intelligence', kind: DeadlineKind.vod, end: now.add(const Duration(hours: 5))),
      ];
      await data.refreshEclass();
      await pump(tester, data, const DeadlinesScreen());
      await tester.tap(find.text('Video 7'));
      await tester.pumpAndSettle();
      expect(statusLine(Status.danger), findsNothing);
      expect(find.textContaining('Closes in'), findsOneWidget);
      expect(find.text('Mark as done'), findsNothing);
    });

    testWidgets('marking work done says who did, and can be undone', (tester) async {
      final now = DateTime.now();
      final (data, eclass, _, _, _) = await makeAppData();
      eclass.deadlines = [
        Deadline(title: 'Paper essay', courseName: 'Artificial Intelligence', kind: DeadlineKind.assignment, end: now.add(const Duration(hours: 5)), moduleId: 9, moduleType: 'assign'),
      ];
      await data.refreshEclass();
      await pump(tester, data, const DeadlinesScreen());
      await tester.tap(find.text('Paper essay'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Mark as done'));
      await tester.pumpAndSettle();
      expect(find.text('Marked done by you'), findsOneWidget);

      await tester.tap(find.text('Paper essay'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Mark as not done'));
      await tester.pumpAndSettle();
      expect(find.text('Marked done by you'), findsNothing);
    });
  });

  group('at text scale 2.0 on a small phone', () {
    const small = Size(360, 640);

    testWidgets('the sheet of a class with no eClass course scrolls to its last line', (tester) async {
      final (data, _, _, _, _) = await makeAppData();
      await pump(tester, data, Builder(builder: (context) => TextButton(onPressed: () => openLesson(context, noCourse), child: const Text('Open'))),
          size: small, scale: 2);
      await tester.tap(find.text('Open'));
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
      final last = find.textContaining('no attendance or VOD record');
      await tester.ensureVisible(last);
      await tester.pumpAndSettle();
      expect(tester.getBottomLeft(last).dy, lessThanOrEqualTo(640));
    });

    testWidgets('the limit dialog fits above the keyboard', (tester) async {
      final (data, _, _, _, _) = await makeAppData();
      await pump(tester, data, Builder(builder: (context) => TextButton(onPressed: () => editAbsenceLimit(context, ai), child: const Text('Open'))),
          size: small, scale: 2);
      addTearDown(tester.view.resetViewInsets);
      tester.view.viewInsets = const FakeViewPadding(bottom: 300 * 3);
      await tester.tap(find.text('Open'));
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
      expect(find.text('Allowed absences'), findsOneWidget);
    });
  });

  group('rows', () {
    final now = DateTime(2026, 11, 3, 12); // a Tuesday
    Deadline vod(DateTime end) => Deadline(title: 'Video 7', courseName: 'Artificial Intelligence', kind: DeadlineKind.vod, end: end);
    const watching = VodProgress(week: 7, title: 'Video 7', length: Duration(minutes: 55), percent: 62);

    test('a VOD window that has closed says so', () {
      final closed = vod(now.subtract(const Duration(hours: 2)));
      expect(dueWarning(closed, null, now), 'Closed 2 h ago · no watch progress');
      expect(dueWarning(closed, watching, now), 'Closed 2 h ago · 62% watched');
    });

    test('a VOD window still open says what is left', () {
      final open = vod(now.add(const Duration(hours: 5)));
      expect(dueWarning(open, watching, now), '62% watched, 21 min left');
      expect(dueWarning(open, null, now), startsWith('Closes in'));
    });

    test('a class after other words: no "next today"', () {
      const l = Lesson(weekday: 2, start: '14:00', end: '15:30', subject: 'Artificial Intelligence');
      expect(nextClassWhen(DateTime(2026, 11, 3), l, now), 'today 14:00');
      expect(nextClassWhen(DateTime(2026, 11, 4), l, now), 'tomorrow 14:00');
      expect(nextClassWhen(DateTime(2026, 11, 9), l, now), 'next Mon 14:00');
    });
  });

  group('Today', () {
    final now = DateTime.now();
    Future<AppData> attending(Map<Course, int> absences, {Map<int, int> limits = const {}}) async {
      final (data, eclass, _, _, _) = await makeAppData(prefs: {
        if (limits.isNotEmpty) 'absenceLimits.v1': '{${limits.entries.map((e) => '"${e.key}": ${e.value}').join(', ')}}',
      });
      eclass.courseList = absences.keys.toList();
      eclass.attendanceById = {for (final e in absences.entries) e.key.id: taking(e.key, e.value, now)};
      await data.refreshEclass();
      return data;
    }

    Future<void> today(WidgetTester tester, AppData data) async {
      await pump(tester, data, TodayScreen(onOpenTab: (_) {}, onOpenSchedule: (_) {}));
      addTearDown(() => tester.pumpWidget(const SizedBox())); // stops the minute timer
    }

    testWidgets('one other course is within its limit', (tester) async {
      await today(tester, await attending({ai: 8, esd: 0}, limits: {ai.id: 8, esd.id: 8}));
      expect(find.text('The other course is within its limit.'), findsOneWidget);
    });

    testWidgets('one of two is within its limit, the other has none', (tester) async {
      await today(tester, await attending({ai: 1, esd: 0}, limits: {ai.id: 8}));
      expect(find.text('1 course is within its limit.'), findsOneWidget);
    });

    testWidgets('one course and no absences, no limit', (tester) async {
      await today(tester, await attending({ai: 0}));
      expect(find.text('No absences in 1 course.'), findsOneWidget);
    });

    Future<AppData> withMail(List<MailHeader> rows, int unread) async {
      final (data, _, _, _, mail) = await makeAppData();
      mail.all = rows;
      mail.unread = unread;
      await data.refreshMail();
      return data;
    }

    testWidgets('unread mail older than the loaded page still shows, and leads to Mail', (tester) async {
      await today(tester, await withMail([mailHeader(0)], 3));
      expect(find.text('3 unread'), findsOneWidget);
      expect(find.text('Open Mail'), findsOneWidget);
    });

    testWidgets('"N more" counts what the rows on show leave out', (tester) async {
      await today(tester, await withMail([mailHeader(0, unread: true)], 3));
      expect(find.text('3 unread'), findsOneWidget);
      expect(find.text('2 more'), findsOneWidget);
    });

    testWidgets('a count lagging behind the rows never reads lower than they do', (tester) async {
      await today(tester, await withMail([mailHeader(0, unread: true)], 0));
      expect(find.text('1 unread'), findsOneWidget);
      expect(find.text('0 unread'), findsNothing);
    });

    testWidgets('nothing unread, no section', (tester) async {
      await today(tester, await withMail([mailHeader(0)], 0));
      expect(find.textContaining('unread'), findsNothing);
    });
  });

  group('Courses', () {
    testWidgets('eClass listing no courses says so', (tester) async {
      final (data, _, _, _, _) = await makeAppData();
      await data.refreshEclass();
      await pump(tester, data, const CoursesScreen());
      expect(find.text('eClass lists no courses for you.'), findsOneWidget);
      expect(find.textContaining('Checked'), findsOneWidget);
    });
  });

  group('Absence limits', () {
    const screen = AbsenceLimitsScreen();

    testWidgets('loading is a skeleton; no course that takes attendance is a plain sentence', (tester) async {
      final (data, _, _, _, _) = await makeAppData();
      await pump(tester, data, screen, scaffold: false);
      expect(find.bySemanticsLabel('Loading'), findsOneWidget);
      expect(find.text('Sign in'), findsNothing);

      await data.refreshEclass();
      await tester.pump();
      expect(find.text('No eClass course takes attendance.'), findsOneWidget);
      expect(find.text('Sign in'), findsNothing);
    });

    testWidgets('a failure names it and offers Retry, not Sign in', (tester) async {
      final (data, eclass, _, _, _) = await makeAppData();
      eclass.error = offline();
      await data.refreshEclass();
      await pump(tester, data, screen, scaffold: false);
      expect(find.text("Couldn't reach eClass. Check the connection."), findsOneWidget);
      expect(find.text('Retry'), findsOneWidget);
      expect(find.text('Sign in'), findsNothing);
    });

    testWidgets('from Settings, Sign in goes back to it instead of stacking another', (tester) async {
      final (data, eclass, _, _, _) = await makeAppData();
      eclass.error = LoginRequired(Service.eclass, 'no saved login');
      await data.refreshEclass();
      await pump(tester, data, Builder(builder: (context) => TextButton(
          onPressed: () => Navigator.of(context).push(MaterialPageRoute(builder: (_) => const AbsenceLimitsScreen(fromSettings: true))),
          child: const Text('Open'))));
      await tester.tap(find.text('Open'));
      await tester.pumpAndSettle();
      expect(find.text('Sign in to eClass to see your courses.'), findsOneWidget);
      await tester.tap(find.text('Sign in'));
      await tester.pumpAndSettle();
      expect(find.byType(AbsenceLimitsScreen), findsNothing);
      expect(find.byType(SettingsScreen), findsNothing);
      expect(find.text('Open'), findsOneWidget);
    });

    testWidgets('it can be pulled to refresh', (tester) async {
      final (data, _, _, _, _) = await makeAppData();
      await data.refreshEclass();
      await pump(tester, data, screen, scaffold: false);
      expect(find.byType(RefreshIndicator), findsOneWidget);
    });
  });

  group('Grades', () {
    GradeRecord record(String code, double credits, String letter, double points,
            {int termKey = 20261, String term = '2026 Spring Semester', String category = 'MR-M'}) =>
        GradeRecord(term: term, termKey: termKey, code: code, name: 'Course $code', credits: credits, letter: letter, points: points, category: category);

    group('termGpa', () {
      test('weighs each letter by its credits', () {
        expect(termGpa([record('A', 3, 'A+', 4.5), record('B', 1, 'B0', 3)]), closeTo(4.125, 1e-9));
      });

      test('a fail counts; a pass, a withdrawal and a course not graded do not', () {
        expect(termGpa([record('A', 3, 'A0', 4), record('B', 3, 'F', 0)]), 2);
        expect(termGpa([record('A', 3, 'A0', 4), record('B', 1, 'P', 0), record('C', 3, 'W', 0), record('D', 3, '-', 0)]), 4);
      });

      test('nothing that counts is no GPA, not a zero', () {
        expect(termGpa([record('A', 3, '-', 0)]), isNull);
        expect(termGpa([record('A', 1, 'P', 0)]), isNull);
        expect(termGpa(const []), isNull);
      });

      test('a points figure off the 4.5 scale is no GPA, rather than a wrong one', () {
        expect(termGpa([record('A', 3, 'A0', 95)]), isNull);
        expect(termGpa([record('A', 3, 'A0', 0)]), isNull);
      });
    });

    group('creditsByCategory', () {
      test('sums earned credits, most first, and leaves out what earned none', () {
        expect(
            creditsByCategory([
              record('A', 3, 'A0', 4),
              record('B', 3, 'B0', 3, category: 'GR'),
              record('C', 3, 'A0', 4),
              record('D', 3, 'F', 0),
              record('E', 3, '-', 0),
              record('F', 1, 'P', 0, category: ''),
            ]),
            {'MR-M': 6, 'GR': 3, 'Other': 1});
      });

      test('a course retaken counts once, by its latest result', () {
        expect(
            creditsByCategory([
              record('A', 3, 'F', 0, termKey: 20251),
              record('A', 3, 'B0', 3, termKey: 20261),
            ]),
            {'MR-M': 3});
        expect(
            creditsByCategory([
              record('A', 3, 'B0', 3, termKey: 20251),
              record('A', 3, 'F', 0, termKey: 20261),
            ]),
            isEmpty);
      });
    });

    testWidgets('each term has its GPA and credits, and the categories sit under the GPA', (tester) async {
      final (data, _, _, ins, _) = await makeAppData();
      ins.report = GradeReport(gpa: 3.87, creditsEarned: 98, yearOfStudy: 3, majorRequired: 30, generalRequired: 12, records: [
        record('A', 3, 'A+', 4.5),
        record('B', 3, 'B0', 3, category: 'GR'),
        record('C', 3, '-', 0, termKey: 20262, term: 'Course registration', category: 'GE'),
      ]);
      await data.refreshGrades();
      await pump(tester, data, const GradesScreen(), scaffold: false);
      expect(find.text('GPA 3.75 · 6 credits'), findsOneWidget);
      expect(find.text('3 credits'), findsWidgets); // the term with nothing graded has no GPA line
      expect(find.text('This semester'), findsOneWidget);
      expect(find.text('Credits by category'), findsOneWidget);
      expect(find.text('INS counts 30 major-required and 12 general-required credits.'), findsOneWidget);
      expect(find.text('3 credits · MR-M'), findsOneWidget);
    });

    testWidgets('with nothing graded there is no category section', (tester) async {
      final (data, _, _, _, _) = await makeAppData();
      await data.refreshGrades();
      await pump(tester, data, const GradesScreen(), scaffold: false);
      expect(find.text('Credits by category'), findsNothing);
    });
  });
}
