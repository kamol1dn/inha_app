import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:inha_app/app.dart';
import 'package:inha_app/core/session.dart';
import 'package:inha_app/data/app_data.dart';
import 'package:inha_app/data/scores.dart';
import 'package:inha_app/features/course_scores_screen.dart';
import 'package:inha_app/features/grades_screen.dart';
import 'package:inha_app/models/models.dart';
import 'package:inha_app/notifications/notifier.dart';
import 'package:inha_app/notifications/routes.dart';
import 'package:inha_app/notifications/rules.dart';
import 'package:inha_app/services/eclass/eclass_parsers.dart';
import 'package:provider/provider.dart';

import 'fakes.dart';

String fixture(String name) => File('test/fixtures/$name').readAsStringSync();

const ai = Course(id: 2626, name: 'Artificial Intelligence', code: 'SOC4040');

final book = parseGradeBook(fixture('eclass_grades.html'), ai)!;

GradeItem item(String name) => book.items.singleWhere((i) => i.name == name);

/// The live page of a course whose category weights all show "-", read back
/// from its one mark: Lab 1 is 10 of 10 and contributes 6.25.
const hiddenWeights = CourseGrades(
  course: ai,
  source: GradeSource.gradebook,
  total: 6.25,
  categories: [GradeCategory('Assign', null), GradeCategory('Etc.', null)],
  items: [
    GradeItem(key: 'g1', name: 'Lab 1', category: 'Assign', mark: '10.00', grade: 10, max: 10, weight: 6.25, contribution: 6.25),
    GradeItem(key: 'g2', name: 'Lab 7', category: 'Assign', mark: '-', max: 100, weight: 62.5, contribution: 0),
    GradeItem(key: 'g3', name: 'ETC', category: 'Etc.', mark: '-', max: 100),
  ],
);

void main() {
  group('parseGradeBook', () {
    test('reads items with their category, weight, range and contribution', () {
      final hw = item('Homework-1');
      expect(hw.key, 'm7001');
      expect((hw.moduleType, hw.moduleId), ('assign', 7001));
      expect(hw.category, 'Assign');
      expect((hw.weight, hw.categoryWeight), (50, 20));
      expect((hw.mark, hw.grade, hw.max, hw.contribution), ('8.50', 8.5, 10, 8.5));
      expect(hw.score, '8.5 / 10');
      expect(hw.marked, isTrue);
    });

    test('an unmarked item, and a manual one with no link, keeps its grade item id', () {
      final hw2 = item('Homework-2');
      expect(hw2.key, 'g204');
      expect((hw2.marked, hw2.grade, hw2.contribution), (false, null, 0));
    });

    test('an item directly under the course has the whole course as its category', () {
      final quiz = item('[QUIZ] Week 6');
      expect((quiz.category, quiz.categoryWeight, quiz.weight), ('', 100, 0));
      expect(item('Attendance book').weight, isNull);
    });

    test('category names and weights come from the headings and total rows, totals are not items', () {
      expect([for (final c in book.categories) (c.name, c.weight)],
          [('Midterm exam', 25), ('Final exam', 25), ('Assign', 20), ('Etc.', 30)]);
      expect(book.items.map((i) => i.name), isNot(contains('Assign SUM')));
      expect(book.items.map((i) => i.name), isNot(contains('Course total')));
      expect(book.total, 28.5);
      expect((book.gradeTotal, book.gradeTotalMax), (28.5, 125));
      expect(book.source, GradeSource.gradebook);
    });

    test('a page with no table is a closed page; any other page has changed', () {
      expect(parseGradeBook('<body id="page-grade-report-user-index">Can not view grades.</body>', ai), isNull);
      expect(() => parseGradeBook(fixture('eclass_dashboard.html'), ai), throwsA(isA<ParseError>()));
    });

    test('survives the cache', () {
      final back = CourseGrades.fromJson(book.toJson());
      expect(back.items.map((i) => i.toJson()), book.items.map((i) => i.toJson()));
      expect(back.categories.map((c) => c.toJson()), book.categories.map((c) => c.toJson()));
      expect((back.total, back.source, back.course.id), (28.5, GradeSource.gradebook, ai.id));
      expect((back.gradeTotal, back.gradeTotalMax), (28.5, 125));
    });
  });

  group('parseActivityGrades', () {
    test('a quiz list has the mark and its maximum', () {
      final quizzes = parseActivityGrades(fixture('eclass_quiz_index.html'), 'quiz');
      expect(quizzes.map((q) => (q.key, q.name, q.category)),
          [('m8001', 'Quiz 1', 'Quizzes'), ('m8002', 'Quiz 2', 'Quizzes')]);
      expect((quizzes[0].grade, quizzes[0].max, quizzes[0].score), (37, 100, '37 / 100'));
      expect(quizzes[1].marked, isFalse);
    });

    test('an assignment list has the mark alone, and skips the spacer rows', () {
      final list = parseActivityGrades(fixture('eclass_assign_index.html'), 'assign');
      expect(list.map((a) => a.name), ['Assignment 1', 'Assignment 2']);
      expect((list[0].grade, list[0].max, list[0].score), (85, null, '85'));
      expect(list[1].marked, isFalse);
    });

    test('a course with none has no table; any other page has changed', () {
      expect(parseActivityGrades('<body id="page-mod-quiz-index">There are no Quizzes</body>', 'quiz'), isEmpty);
      expect(() => parseActivityGrades(fixture('eclass_dashboard.html'), 'quiz'), throwsA(isA<ParseError>()));
    });

    test('parseAssignMax reads the Feedback box', () {
      String page(String grade) => '<body id="page-mod-assign-view"><div class="feedback"><table>'
          '<tr><td>Grade</td><td>$grade</td></tr><tr><td>Graded on</td><td>2026-10-30 12:00</td></tr></table></div></body>';
      expect(parseAssignMax(page('85.00 / 100.00')), 100);
      expect(parseAssignMax(page('A')), isNull);
      expect(parseAssignMax('<body id="page-mod-assign-view">Not graded</body>'), isNull);
      expect(() => parseAssignMax(fixture('eclass_dashboard.html')), throwsA(isA<ParseError>()));
    });
  });

  group('CourseScore', () {
    final score = CourseScore.of(book)!;

    test("the accumulated score is eClass's course total", () {
      expect(score.accumulated, 28.5);
    });

    test('worth is item weight × category weight, empty categories count whole', () {
      expect({for (final l in score.lines) l.name: l.worth}, {
        'Mid-term exam result': 25,
        'Homework-1': 10,
        'Homework-2': 10,
        'Final exam': 25,
        'Etc.': 30,
      });
      expect(score.lines.fold(0.0, (s, l) => s + l.worth), 100);
    });

    test('what is marked, what is open and the best still possible', () {
      expect(score.markedWorth, 35);
      expect(score.openWorth, 65);
      expect(score.best, 93.5);
    });

    test('what-if scores add to the total, as far as each line goes', () {
      expect(score.withScores({}), 28.5);
      expect(score.withScores({'category:Final exam': 80}), 48.5); // 80% of 25
      expect(score.withScores({'g204': 5}), 33.5); // 5 of 10 on a 10-point item
      expect(score.withScores({'g204': 500}), 38.5); // capped at 10 of 10
      expect(score.withScores({'m7001': 0}), 28.5); // already marked: not what-if
    });

    test('items with a weight of 0 or none are shown but not counted', () {
      expect(score.uncounted.map((i) => i.name), ['[QUIZ] Week 6', 'Attendance book']);
    });

    test('a category weight of "-" is read back from a marked item', () {
      final s = CourseScore.of(hiddenWeights)!;
      expect({for (final l in s.lines) l.name: l.worth}, {'Lab 1': 6.25, 'Lab 7': 62.5});
      expect(s.accumulated, 6.25);
      expect(s.uncounted.single.name, 'ETC');
    });

    // The course total's row, and sometimes the items' column, hold raw marks: 157.25 "of 100".
    const rawMarks = CourseGrades(course: ai, source: GradeSource.gradebook, total: 157.25, gradeTotal: 157.25, gradeTotalMax: 300, items: [
      GradeItem(key: 'm1', name: 'Midterm', mark: '82.00', grade: 82, max: 100, weight: 40, categoryWeight: 100, contribution: 32.8),
      GradeItem(key: 'm2', name: 'Project', mark: '75.25', grade: 75.25, max: 100, weight: 30, categoryWeight: 100, contribution: 75.25),
      GradeItem(key: 'm3', name: 'Final', mark: '-', max: 100, weight: 30, categoryWeight: 100, contribution: 0),
    ]);

    test('a course total on another scale is not the score: the lines add up, and it never passes 100', () {
      final s = CourseScore.of(rawMarks)!;
      expect(s.lines[1].earned, 22.575); // 75.25% of 30, not the raw 75.25
      expect(plainNumber(s.accumulated), '55.38');
      expect(s.outOf, 100);
      expect(s.line, '55.38 of 100');
      expect(eclassTotalLine(rawMarks, s), 'Course total on eClass: 157.25 of 300');
    });

    test("eClass's own total is kept where it agrees", () {
      expect(score.accumulated, 28.5);
      expect(eclassTotalLine(book, score), isNull);
    });

    test('weights that add up to more than 100 say so', () {
      const over = CourseGrades(course: ai, source: GradeSource.gradebook, items: [
        GradeItem(key: 'm1', name: 'A', mark: '50.00', grade: 50, max: 100, weight: 100, categoryWeight: 100),
        GradeItem(key: 'm2', name: 'B', mark: '-', max: 100, weight: 100, categoryWeight: 100),
      ]);
      final s = CourseScore.of(over)!;
      expect((s.accumulated, s.outOf, s.line, s.ofValue(75)), (50, 200, '50 of 200', '75 of 200'));
    });

    test('a raw mark does not pass as a category weight', () {
      const raw = CourseGrades(course: ai, source: GradeSource.gradebook, total: 50, gradeTotal: 50, gradeTotalMax: 100, items: [
        GradeItem(key: 'm1', name: 'Lab', category: 'Assign', mark: '50.00', grade: 50, max: 100, weight: 50, contribution: 50),
      ], categories: [GradeCategory('Assign', null)]);
      expect(CourseScore.of(raw), isNull);
      expect(eclassTotalLine(raw, null), 'Course total on eClass: 50 of 100');
    });

    test("a mark that is not a number takes eClass's figure, no more than the line is worth", () {
      CourseGrades letter(double c) => CourseGrades(course: ai, source: GradeSource.gradebook, items: [
            GradeItem(key: 'm1', name: 'A', mark: 'A', weight: 20, categoryWeight: 100, contribution: c),
          ]);
      expect(CourseScore.of(letter(15))!.accumulated, 15);
      expect(CourseScore.of(letter(95))!.accumulated, 20);
    });

    test('no weights at all, or marks from the activity lists: no score', () {
      const noWeights = CourseGrades(course: ai, source: GradeSource.gradebook, total: 0, items: [
        GradeItem(key: 'g1', name: 'Lab 1', category: 'Assign', mark: '-', max: 10),
      ], categories: [GradeCategory('Assign', null)]);
      expect(CourseScore.of(noWeights), isNull);
      const activities = CourseGrades(course: ai, source: GradeSource.activities, items: [
        GradeItem(key: 'm1', name: 'Quiz 1', category: 'Quizzes', mark: '37.00/100.00', grade: 37, max: 100),
      ]);
      expect(CourseScore.of(activities), isNull);
    });
  });

  group('planNotifications, grades', () {
    final now = DateTime(2026, 10, 22, 12);
    List<PlannedNotification> plan(Map<String, String> seen, {QuietHours? quiet, DateTime? at}) => planNotifications(
        now: at ?? now, courseGrades: [book], seenGrades: {ai.id: seen}, quietHours: quiet);

    final allSeen = {'m7000': '20.00', 'm7001': '8.50', 'm7002': '99.25'};

    test('a new mark goes out once, with the score so far', () {
      final n = plan({'m7000': '20.00', 'm7002': '99.25'}).single;
      expect(n.title, 'Graded: Homework-1');
      expect(n.body, 'Artificial Intelligence · 8.5 / 10 · 28.5 of 100 so far');
      expect(n.channel, NotifyChannel.grades);
      expect(n.when, now);
      expect(gradeCourseId(n.key), ai.id);
    });

    test('a changed mark says so and says what it was', () {
      final n = plan({...allSeen, 'm7001': '7.00'}).single;
      expect(n.title, 'Grade changed: Homework-1');
      expect(n.body, contains('was 7'));
      expect(n.key, isNot(plan({...allSeen}..remove('m7001')).single.key));
    });

    test('nothing new, unmarked items and the attendance book stay quiet', () {
      expect(plan(allSeen), isEmpty);
      expect(isAttendanceMark(item('Attendance book')), isTrue);
    });

    test('a mark found at night waits for the morning', () {
      final n = plan({'m7000': '20.00', 'm7002': '99.25'}, quiet: defaultQuietHours, at: DateTime(2026, 10, 22, 23, 30))
          .single;
      expect(n.when, DateTime(2026, 10, 23, 7, 30));
      expect(n.quiet, isFalse);
    });

    test('tapping one opens the course scores, or Courses when it is gone', () {
      final key = plan({'m7000': '20.00', 'm7002': '99.25'}).single.key;
      expect((notificationTarget(key, courseGrades: [book]) as ScoresTarget).course.id, ai.id);
      expect((notificationTarget(key) as TabTarget).tab, 3);
    });
  });

  group('AppData', () {
    test('refreshing eClass loads the marks, asks for the courses once and caches them', () async {
      final (data, eclass, _, _, _) = await makeAppData();
      eclass.courseList = const [ai];
      eclass.gradesById = {ai.id: book};
      await data.refreshEclass();
      expect(data.gradesOf(ai.id)?.total, 28.5);
      expect(data.gradesOf(1), isNull);
      expect(eclass.courseCalls, 1);
      await data.reloadFromCache();
      expect(data.gradesOf(ai.id)?.items, hasLength(book.items.length));
    });

    test('signing out of eClass forgets the marks and what the notifier saw', () async {
      final (data, eclass, _, _, _) = await makeAppData(prefs: {Notifier.seenGradesKey: '{"2626":{"m7001":"8.50"}}'});
      eclass.courseList = const [ai];
      eclass.gradesById = {ai.id: book};
      await data.refreshEclass();
      await data.forget(Service.eclass);
      expect(data.courseGrades.data, isNull);
      expect(data.cache.read('courseGrades', (j) => j), isNull);
    });
  });

  group('screens', () {
    Future<AppData> withMarks(Map<int, CourseGrades> marks) async {
      final (data, eclass, _, _, _) = await makeAppData();
      eclass.courseList = [for (final g in marks.values) g.course];
      eclass.gradesById = marks;
      await data.refreshEclass();
      return data;
    }

    Future<void> show(WidgetTester tester, AppData data, Widget screen, {double scale = 1}) async {
      tester.view.physicalSize = const Size(412 * 3, 2400 * 3);
      tester.view.devicePixelRatio = 3;
      addTearDown(tester.view.reset);
      await tester.pumpWidget(ChangeNotifierProvider.value(
        value: data,
        child: MaterialApp(
          theme: InhaApp.light,
          home: Builder(
            builder: (context) => MediaQuery(
              data: MediaQuery.of(context).copyWith(textScaler: TextScaler.linear(scale)),
              child: screen,
            ),
          ),
        ),
      ));
      await tester.pump();
    }

    testWidgets('the score, what is marked and each category', (tester) async {
      await show(tester, await withMarks({ai.id: book}), CourseScoresScreen(courseId: ai.id, name: ai.name));
      expect(find.text('28.5'), findsOneWidget);
      expect(find.text('of 100 so far'), findsOneWidget);
      expect(find.text('35 points marked · 65 still open · best possible 93.5'), findsOneWidget);
      expect(find.text('Assign · 20 points'), findsOneWidget);
      expect(find.text('8.5 / 10'), findsOneWidget);
      expect(find.text('8.5 of 10 points'), findsOneWidget);
      expect(find.text('Not counted in the total'), findsOneWidget);
      expect(find.text('14 / 20'), findsOneWidget);
    });

    testWidgets('typing a what-if score moves the projection, and Clear takes it back', (tester) async {
      await show(tester, await withMarks({ai.id: book}), CourseScoresScreen(courseId: ai.id, name: ai.name));
      expect(find.textContaining('With these scores'), findsNothing);
      await tester.enterText(find.byKey(const ValueKey('category:Final exam/0')), '80');
      await tester.pump();
      expect(find.text('With these scores: 48.5 of 100'), findsOneWidget);
      expect(find.text('28.5'), findsOneWidget); // the real score does not move

      await tester.tap(find.text('Clear'));
      await tester.pump();
      expect(find.textContaining('With these scores'), findsNothing);
      expect(find.widgetWithText(TextField, '80'), findsNothing);
    });

    testWidgets('a closed grades page: the marks, and why there is no score', (tester) async {
      final activities = CourseGrades(
          course: ai,
          source: GradeSource.activities,
          items: parseActivityGrades(fixture('eclass_quiz_index.html'), 'quiz'));
      await show(tester, await withMarks({ai.id: activities}), CourseScoresScreen(courseId: ai.id, name: ai.name));
      expect(find.textContaining('keeps its grades page closed'), findsOneWidget);
      expect(find.text('Quizzes'), findsOneWidget);
      expect(find.text('37 / 100'), findsOneWidget);
      expect(find.text('Not marked'), findsOneWidget);
      expect(find.text('of 100 so far'), findsNothing);
    });

    testWidgets('Grades lists every course with its score and opens it', (tester) async {
      await show(tester, await withMarks({ai.id: book}), const GradesScreen());
      expect(find.text('Scores this semester'), findsOneWidget);
      expect(find.text('28.5 of 100'), findsOneWidget);
      expect(find.text('4 of 5 marked'), findsOneWidget); // the attendance book and week 6 quiz are marks too
      await tester.tap(find.text('28.5 of 100'));
      await tester.pumpAndSettle();
      expect(find.text('of 100 so far'), findsOneWidget);
    });

    testWidgets('lays out at text scale 2.0', (tester) async {
      await show(tester, await withMarks({ai.id: book}), CourseScoresScreen(courseId: ai.id, name: ai.name), scale: 2);
      expect(tester.takeException(), isNull);
    });
  });
}
