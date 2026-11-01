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
import 'package:inha_app/services/eclass/eclass_links.dart';
import 'package:inha_app/services/eclass/eclass_parsers.dart';
import 'package:provider/provider.dart';

import 'fakes.dart';

String fixture(String name) => File('test/fixtures/$name').readAsStringSync();

const ai = Course(id: 2626, name: 'Artificial Intelligence', code: 'SOC4040');

final book = parseGradeBook(fixture('eclass_grades.html'), ai)!;

GradeItem item(String name) => book.items.singleWhere((i) => i.name == name);

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
      expect(book.percent, 28.5);
      expect(book.source, GradeSource.gradebook);
    });

    test('where a course hides the Percentage column, the total is its Grade over its Range', () {
      final hidden = fixture('eclass_grades.html')
          .replaceFirst('column-percentage">28.50 %</td>', 'column-percentage"></td>')
          .replaceFirst('column-grade">35.63</td>', 'column-grade">0.11</td>')
          .replaceFirst('column-range">0–125</td>', 'column-range">0–200</td>');
      expect(parseGradeBook(hidden, ai)!.percent, closeTo(0.055, 1e-9));
    });

    test('a page with no table is a closed page; any other page has changed', () {
      expect(parseGradeBook('<body id="page-grade-report-user-index">Can not view grades.</body>', ai), isNull);
      expect(() => parseGradeBook(fixture('eclass_dashboard.html'), ai), throwsA(isA<ParseError>()));
    });

    test('survives the cache', () {
      final back = CourseGrades.fromJson(book.toJson());
      expect(back.items.map((i) => i.toJson()), book.items.map((i) => i.toJson()));
      expect(back.categories.map((c) => c.toJson()), book.categories.map((c) => c.toJson()));
      expect((back.percent, back.source, back.course.id), (28.5, GradeSource.gradebook, ai.id));
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

    test('items with a weight of 0 add nothing; those with none are shown apart', () {
      expect(score.uncounted.map((i) => i.name), ['[QUIZ] Week 6']);
      expect(score.unweighted.map((i) => i.name), ['Attendance book']);
    });

    // Live pages. The contribution column adds up 81 + 70 + 6.25 = 157.25 here; eClass's own total is 26 of 100.
    const hiddenCategories = CourseGrades(course: ai, source: GradeSource.gradebook, percent: 26, categories: [
      GradeCategory('Midterm', null),
      GradeCategory('Attendance', null),
      GradeCategory('Assign', null),
    ], items: [
      GradeItem(key: 'm1', name: 'Midterm', category: 'Midterm', mark: '81.00', grade: 81, max: 100, weight: 100, contribution: 81),
      GradeItem(key: 'm2', name: 'Attendance', category: 'Attendance', mark: '14.00', grade: 14, max: 20, weight: 100, contribution: 70),
      GradeItem(key: 'm3', name: 'Lab 1', category: 'Assign', mark: '10.00', grade: 10, max: 10, weight: 6.25, contribution: 6.25),
    ]);

    test("the course total is eClass's, not what its contribution column adds up to", () {
      final s = CourseScore.of(hiddenCategories)!;
      expect(s.line, '26 of 100');
      expect((s.accumulated, s.outOf), (26, 100));
    });

    test('marks under a hidden category weight are shown, and make no invented points', () {
      final s = CourseScore.of(hiddenCategories)!;
      expect(s.lines, isEmpty);
      expect(s.unweighted.map((i) => i.name), ['Midterm', 'Attendance', 'Lab 1']);
      expect(s.complete, isFalse);
    });

    test('a column that holds a raw mark does not count for more than its share', () {
      final s = CourseScore.of(const CourseGrades(course: ai, source: GradeSource.gradebook, items: [
        GradeItem(key: 'm1', name: 'Project', mark: '75.25', grade: 75.25, max: 100, weight: 30, categoryWeight: 100, contribution: 75.25),
        GradeItem(key: 'm2', name: 'Final', mark: '-', max: 100, weight: 70, categoryWeight: 100, contribution: 0),
      ]))!;
      expect(s.lines[0].earned, 22.575);
      expect(s.line, '22.57 of 100');
      expect(s.complete, isTrue);
    });

    test('with no total and weights past 100, the score says what it is out of', () {
      final s = CourseScore.of(const CourseGrades(course: ai, source: GradeSource.gradebook, items: [
        GradeItem(key: 'm1', name: 'A', mark: '50.00', grade: 50, max: 100, weight: 100, categoryWeight: 100),
        GradeItem(key: 'm2', name: 'B', mark: '-', max: 100, weight: 100, categoryWeight: 100),
      ]))!;
      expect((s.accumulated, s.outOf, s.line, s.ofValue(75)), (50, 200, '50 of 200', '75 of 200'));
    });

    test("a mark that is not a number takes eClass's figure, no more than the line is worth", () {
      CourseGrades letter(double c) => CourseGrades(course: ai, source: GradeSource.gradebook, items: [
            GradeItem(key: 'm1', name: 'A', mark: 'A', weight: 20, categoryWeight: 100, contribution: c),
          ]);
      expect(CourseScore.of(letter(15))!.accumulated, 15);
      expect(CourseScore.of(letter(95))!.accumulated, 20);
    });

    test('a category holding categories is counted through them, not again', () {
      const page = '''<body id="page-grade-report-user-index"><table class="user-grade"><tbody>
        <tr><th class="level1 column-itemname">Course</th></tr>
        <tr><th class="level2 column-itemname">Exams</th></tr>
        <tr><th class="level3 column-itemname">Midterm</th></tr>
        <tr><th class="level3 baggt column-itemname">Midterm total</th><td class="column-weight">50.00 %</td></tr>
        <tr><th class="level3 column-itemname">Final</th></tr>
        <tr><th class="level3 baggt column-itemname">Final total</th><td class="column-weight">50.00 %</td></tr>
        <tr><th class="level2 baggt column-itemname">Exams total</th><td class="column-weight">40.00 %</td></tr>
        <tr><th class="level2 column-itemname">Assign</th></tr>
        <tr><th class="level2 baggt column-itemname">Assign total</th><td class="column-weight">60.00 %</td></tr>
        <tr><th class="level1 baggt column-itemname">Course total</th><td class="column-grade">-</td><td class="column-range">0–100</td></tr>
      </tbody></table></body>''';
      final g = parseGradeBook(page, ai)!;
      expect([for (final c in g.categories) (c.name, c.weight)], [('Midterm', 20), ('Final', 20), ('Assign', 60)]);
      expect([for (final l in CourseScore.of(g)!.lines) (l.name, l.worth)], [('Midterm', 20), ('Final', 20), ('Assign', 60)]);
    });

    test('no weights at all, or marks from the activity lists: no score', () {
      const noWeights = CourseGrades(course: ai, source: GradeSource.gradebook, items: [
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
      expect(data.gradesOf(ai.id)?.percent, 28.5);
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
      await tester.enterText(find.byKey(const ValueKey('category:Final exam')), '80');
      await tester.pump();
      expect(find.text('With these scores: 48.5 of 100'), findsOneWidget);
      expect(find.text('28.5'), findsOneWidget); // the real score does not move

      await tester.tap(find.text('Clear'));
      await tester.pump();
      expect(find.textContaining('With these scores'), findsNothing);
      expect(find.widgetWithText(TextField, '80'), findsNothing);
    });

    group('what-if fields', () {
      // More open rows than a screen holds, each worth 2 points of 40.
      final long = CourseGrades(course: ai, source: GradeSource.gradebook, percent: 10, categories: const [
        GradeCategory('Assign', 40),
      ], items: [
        for (var i = 0; i < 20; i++)
          GradeItem(key: 'g$i', name: 'Homework-$i', category: 'Assign', max: 10, weight: 5, categoryWeight: 40),
      ]);

      Future<void> onPhone(WidgetTester tester, AppData data) async {
        await show(tester, data, CourseScoresScreen(courseId: ai.id, name: ai.name));
        tester.view.physicalSize = const Size(412 * 3, 640 * 3);
        await tester.pump();
      }

      testWidgets('a score stays in its field when the row scrolls away and comes back', (tester) async {
        await onPhone(tester, await withMarks({ai.id: long}));
        await tester.enterText(find.byKey(const ValueKey('g0')), '8');
        await tester.pump();
        // The focus moves on, so nothing keeps the first row alive off screen.
        await tester.enterText(find.byKey(const ValueKey('g1')), '5');
        await tester.pump();
        expect(find.text('With these scores: 12.6 of 100'), findsOneWidget);

        final list = find.byType(Scrollable).first;
        await tester.drag(list, const Offset(0, -2000));
        await tester.pumpAndSettle();
        expect(find.byKey(const ValueKey('g0')), findsNothing);
        await tester.drag(list, const Offset(0, 4000));
        await tester.pumpAndSettle();

        expect(find.widgetWithText(TextField, '8'), findsOneWidget);
        expect(find.text('With these scores: 12.6 of 100'), findsOneWidget);
      });

      testWidgets('the result stays in sight while the list scrolls, and typing keeps the field', (tester) async {
        await onPhone(tester, await withMarks({ai.id: long}));
        await tester.scrollUntilVisible(find.byKey(const ValueKey('g10')), 200, scrollable: find.byType(Scrollable).first);
        await tester.pumpAndSettle();
        expect(find.text('of 100 so far'), findsNothing); // the total has scrolled away
        await tester.tap(find.byKey(const ValueKey('g10')));
        await tester.pump();
        await tester.enterText(find.byKey(const ValueKey('g10')), '10');
        await tester.pump();
        final result = find.text('With these scores: 12 of 100');
        expect(result, findsOneWidget);
        expect(tester.getTopLeft(result).dy, greaterThan(0));
        expect(find.byKey(const ValueKey('g10')), findsOneWidget);
        expect(tester.testTextInput.isVisible, isTrue);
      });

      testWidgets('a comma is a decimal point, and what is not a number is refused', (tester) async {
        expect(parseWhatIf('8,5'), 8.5);
        expect(parseWhatIf('8.5'), 8.5);
        expect(parseWhatIf(','), isNull);

        await show(tester, await withMarks({ai.id: long}), CourseScoresScreen(courseId: ai.id, name: ai.name));
        final field = find.byKey(const ValueKey('g0'));
        await tester.enterText(field, '8,5');
        await tester.pump();
        expect(find.text('With these scores: 11.7 of 100'), findsOneWidget); // 8.5 of 10, not capped from 85

        await tester.enterText(field, '8,5,1');
        await tester.pump();
        expect(tester.widget<TextField>(field).controller!.text, '8,5');
        await tester.enterText(field, 'abc');
        await tester.pump();
        expect(tester.widget<TextField>(field).controller!.text, '8,5');
      });

      testWidgets('a field says what it is for, is 48 tall, and fits 100 at any text scale', (tester) async {
        final handle = tester.ensureSemantics();
        for (final scale in [1.0, 2.0]) {
          await show(tester, await withMarks({ai.id: long}), CourseScoresScreen(courseId: ai.id, name: ai.name), scale: scale);
          final field = find.byKey(const ValueKey('g0'));
          expect(tester.getSize(field).height, greaterThanOrEqualTo(48));
          final painter = TextPainter(
            text: TextSpan(text: '100', style: InhaApp.light.textTheme.bodyLarge),
            textScaler: TextScaler.linear(scale),
            textDirection: TextDirection.ltr,
          )..layout();
          expect(tester.getSize(field).width - 16, greaterThanOrEqualTo(painter.width));
          painter.dispose();
          expect(find.bySemanticsLabel(RegExp('What-if score for Homework-0')), findsOneWidget);
        }
        handle.dispose();
      });
    });

    testWidgets('rows read as on Deadlines, without the kind tag', (tester) async {
      await show(tester, await withMarks({ai.id: book}), CourseScoresScreen(courseId: ai.id, name: ai.name));
      expect(find.text('Week 6'), findsOneWidget);
      expect(find.textContaining('[QUIZ]'), findsNothing);
    });

    test('an item with a module opens its activity; one without has no link', () {
      const assign = GradeItem(key: 'm1', name: 'Lab 1', moduleId: 7001, moduleType: 'assign');
      expect(eclassGradeItemUrl(assign).toString(), 'https://eclass.inha.ac.kr/mod/assign/view.php?id=7001');
      expect(eclassGradeItemUrl(const GradeItem(key: 'g1', name: 'Attendance book')), isNull);
    });

    testWidgets('a marked row with a module is one tap target; a manual one is not', (tester) async {
      final marks = CourseGrades(course: ai, source: GradeSource.activities, items: const [
        GradeItem(key: 'm1', name: 'Lab 1', mark: '8', grade: 8, max: 10, moduleId: 7001, moduleType: 'assign'),
        GradeItem(key: 'g2', name: 'Attendance book', mark: '14', grade: 14, max: 20),
      ]);
      await show(tester, await withMarks({ai.id: marks}), CourseScoresScreen(courseId: ai.id, name: ai.name));
      expect(find.ancestor(of: find.text('Lab 1'), matching: find.byType(InkWell)), findsOneWidget);
      expect(find.ancestor(of: find.text('Attendance book'), matching: find.byType(InkWell)), findsNothing);
    });

    testWidgets('with no answer from eClass it says so, and not that the course has no marks', (tester) async {
      final (data, eclass, _, _, _) = await makeAppData();
      eclass.error = LoginRequired(Service.eclass, 'no saved login');
      await data.refreshEclass();
      await show(tester, data, CourseScoresScreen(courseId: ai.id, name: ai.name));
      expect(find.text('eClass sign-in needed.'), findsOneWidget);
      expect(find.text('Sign in'), findsOneWidget);
      expect(find.textContaining('has no marks'), findsNothing);
      expect(find.bySemanticsLabel('Loading'), findsNothing);
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
