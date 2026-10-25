import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:inha_app/app.dart';
import 'package:inha_app/core/session.dart';
import 'package:inha_app/data/app_data.dart';
import 'package:inha_app/features/absence_widgets.dart';
import 'package:inha_app/features/course_detail_screen.dart';
import 'package:inha_app/features/courses_screen.dart';
import 'package:inha_app/features/deadlines_screen.dart';
import 'package:inha_app/features/grades_screen.dart';
import 'package:inha_app/features/mail_screen.dart';
import 'package:inha_app/features/timetable_screen.dart';
import 'package:inha_app/features/today_screen.dart';
import 'package:inha_app/models/models.dart';
import 'package:provider/provider.dart';

import 'fakes.dart';

// The states DESIGN.md 13 asks for, on every screen that shows data: first
// run with no cache, signed out, offline, and the full screen at text scale
// 2.0 in light and dark without an overflow.

const ai = Course(id: 2622, name: 'Artificial Intelligence', code: 'SOC4040', professor: 'J. Kim');
const esd = Course(id: 2615, name: 'Embedded Software & Design', code: 'SOC3050');

Future<void> show(WidgetTester tester, AppData data, Widget screen,
    {double scale = 1, ThemeData? theme, bool scaffold = true}) async {
  tester.view.physicalSize = const Size(412 * 3, 915 * 3);
  tester.view.devicePixelRatio = 3;
  addTearDown(tester.view.reset);
  await tester.pumpWidget(ChangeNotifierProvider.value(
    value: data,
    child: MaterialApp(
      theme: theme ?? InhaApp.light,
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

/// Data for a whole week: a class every day that runs all day long (so the
/// rail always has a hero, whenever the test runs), deadlines, attendance in
/// trouble, VODs, grades and mail.
Future<AppData> seeded() async {
  final (data, eclass, timetable, _, mail) = await makeAppData(prefs: {
    'absenceLimits.v1': '{"${ai.id}": 8}',
  });
  timetable.lessonList = [
    for (var d = 1; d <= 7; d++) ...[
      Lesson(weekday: d, start: '00:00', end: '23:59', subject: 'Embedded Software & Design', room: 'B101 Conference', teacher: 'J. Hong', kind: 'Lecture'),
      Lesson(weekday: d, start: '23:58', end: '23:59', subject: 'Artificial Intelligence', room: 'B202', kind: 'Lab'),
    ],
  ];
  final now = DateTime.now();
  eclass.courseList = [ai, esd];
  eclass.deadlines = [
    Deadline(title: 'Assignment 1: a long title about JPEG quantization tables', courseName: 'Embedded Software & Design',
        kind: DeadlineKind.assignment, end: now.add(const Duration(hours: 5))),
    Deadline(title: 'Video 7', courseName: 'Artificial Intelligence', kind: DeadlineKind.vod,
        start: now.subtract(const Duration(days: 6)), end: now.add(const Duration(days: 2))),
  ];
  eclass.attendanceById = {
    ai.id: CourseAttendance(course: ai, classes: [
      for (var i = 0; i < 7; i++)
        AttendanceEntry(date: now.subtract(Duration(days: 7 * i + 1)), label: '1Class', mark: AttendanceMark.absent),
      AttendanceEntry(date: now.subtract(const Duration(days: 60)), label: '1Class', mark: AttendanceMark.present),
    ], vods: const [
      VodProgress(week: 7, title: 'Video 7', length: Duration(minutes: 55), percent: 62),
    ]),
  };
  mail.all = [for (var i = 0; i < 4; i++) mailHeader(i, unread: i < 3)];
  mail.unread = 3;
  await Future.wait([data.refreshTimetable(), data.refreshEclass(), data.refreshMail()]);
  return data;
}

DioException offline() => DioException(
    requestOptions: RequestOptions(path: 'https://iut.edupage.org/'), type: DioExceptionType.connectionError);

void main() {
  testWidgets('first run: the rail shows Now and a skeleton, and claims nothing about classes', (tester) async {
    final (data, _, _, _, _) = await makeAppData();
    await show(tester, data, TodayScreen(onOpenTab: (_) {}, onOpenSchedule: (_) {}));
    expect(find.text('Now'), findsOneWidget);
    expect(find.bySemanticsLabel('Loading'), findsWidgets);
    expect(find.text('No classes today'), findsNothing);
    expect(find.textContaining('Nothing due'), findsNothing);
  });

  testWidgets('signed out of eClass: one note with one Sign in, no error row as well', (tester) async {
    final (data, eclass, _, _, _) = await makeAppData();
    eclass.error = LoginRequired(Service.eclass, 'no saved login');
    await data.refreshEclass();
    await show(tester, data, const DeadlinesScreen());
    expect(find.text('Sign in to eClass to see deadlines and attendance.'), findsOneWidget);
    expect(find.text('Sign in'), findsOneWidget);
    await show(tester, data, const CoursesScreen());
    expect(find.text('Sign in to eClass to see attendance and VOD progress.'), findsOneWidget);
    expect(find.text('Sign in'), findsOneWidget);
    // Today has no note of its own, so the error row carries the way in.
    await show(tester, data, TodayScreen(onOpenTab: (_) {}, onOpenSchedule: (_) {}));
    expect(find.text('eClass sign-in needed.'), findsOneWidget);
  });

  testWidgets('offline: one offline row replaces the network error rows', (tester) async {
    // Both hosts fail on the network.
    final failing = await makeAppData();
    failing.$2.error = offline();
    failing.$3.error = offline();
    await Future.wait([failing.$1.refreshTimetable(), failing.$1.refreshEclass()]);
    await show(tester, failing.$1, TodayScreen(onOpenTab: (_) {}, onOpenSchedule: (_) {}));
    expect(find.textContaining('Offline'), findsOneWidget);
    expect(find.textContaining("Couldn't reach"), findsNothing);
    expect(find.text('Retry'), findsOneWidget);
    // With only one host down it is that service's error, not offline.
    failing.$3.error = null;
    await failing.$1.refreshTimetable();
    await show(tester, failing.$1, TodayScreen(onOpenTab: (_) {}, onOpenSchedule: (_) {}));
    expect(find.textContaining('Offline'), findsNothing);
    expect(find.textContaining("Couldn't reach eClass"), findsOneWidget);
  });

  for (final (name, theme) in [('light', InhaApp.light), ('dark', InhaApp.dark)]) {
    testWidgets('every screen lays out at text scale 2.0, $name', (tester) async {
      final data = await seeded();
      final screens = <(String, Widget, bool)>[
        ('Today', TodayScreen(onOpenTab: (_) {}, onOpenSchedule: (_) {}), true),
        ('Schedule', const TimetableScreen(), true),
        ('Deadlines', const DeadlinesScreen(), true),
        ('Courses', const CoursesScreen(), true),
        ('Course detail', const CourseDetailScreen(courseId: 2622, name: 'Artificial Intelligence'), false),
        ('Mail', const MailScreen(), true),
        ('Grades', const GradesScreen(), false),
        ('Absence limits', const AbsenceLimitsScreen(), false),
      ];
      for (final (label, screen, wrap) in screens) {
        await show(tester, data, screen, scale: 2, theme: theme, scaffold: wrap);
        expect(tester.takeException(), isNull, reason: label);
      }
      // The rail's hero and the attendance warning made it on screen.
      await show(tester, data, TodayScreen(onOpenTab: (_) {}, onOpenSchedule: (_) {}), scale: 2, theme: theme);
      expect(find.text('B101 Conference'), findsOneWidget);
      await tester.scrollUntilVisible(find.text('7 of 8'), 300);
      expect(find.text('7 of 8'), findsOneWidget);
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox()); // stops the minute timer
    });
  }
}
