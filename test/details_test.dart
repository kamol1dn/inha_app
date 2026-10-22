import 'package:flutter_test/flutter_test.dart';
import 'package:inha_app/data/urgency.dart';
import 'package:inha_app/models/models.dart';
import 'package:inha_app/services/eclass/eclass_links.dart';

const mmc = Course(id: 2615, name: 'Multimedia Computing', code: 'SOC4020');
const ai = Course(id: 2622, name: 'Artificial Intelligence', code: 'SOC4040');
final att = [CourseAttendance(course: mmc), CourseAttendance(course: ai)];

Deadline due(String title, String course, DateTime end,
        {DeadlineKind kind = DeadlineKind.assignment, int? moduleId, String? moduleType}) =>
    Deadline(title: title, courseName: course, kind: kind, end: end, moduleId: moduleId, moduleType: moduleType);

GradeRecord grade(int termKey, String code, String name, String letter) => GradeRecord(
    term: '$termKey', termKey: termKey, code: code, name: name, credits: 3, letter: letter, points: 0);

void main() {
  final now = DateTime(2026, 10, 23, 9);

  group('eClass links', () {
    test('an activity opens /mod/<type>/view.php?id=<module>', () {
      expect(eclassItemUrl(due('Assignment 1', 'Multimedia Computing', now, moduleId: 72061, moduleType: 'assign'))
          .toString(), 'https://eclass.inha.ac.kr/mod/assign/view.php?id=72061');
      expect(eclassItemUrl(due('Notice', 'Artificial Intelligence', now, moduleId: 9, moduleType: 'ubboard'))
          .toString(), 'https://eclass.inha.ac.kr/mod/ubboard/view.php?id=9');
    });

    test('cached events without a type fall back on their kind; course events have no link', () {
      expect(eclassItemUrl(due('Quiz 2', 'AI', now, kind: DeadlineKind.quiz, moduleId: 72454)).toString(),
          'https://eclass.inha.ac.kr/mod/quiz/view.php?id=72454');
      expect(eclassItemUrl(due('Event', 'AI', now, kind: DeadlineKind.other, moduleId: 5)), isNull);
      expect(eclassItemUrl(due('AI[001]-3교시', 'AI', now, kind: DeadlineKind.classPeriod)), isNull);
    });

    test('a course page', () {
      expect(eclassCourseUrl(2615).toString(), 'https://eclass.inha.ac.kr/course/view.php?id=2615');
    });
  });

  test('Deadline keeps its module type through the cache', () {
    final d = Deadline.fromJson(
        due('Lab 5', 'Multimedia Computing', now, moduleId: 1, moduleType: 'assign').toJson());
    expect(d.moduleType, 'assign');
    final old = Deadline.fromJson({...due('Lab 5', 'MMC', now).toJson()}..remove('moduleType'));
    expect(old.moduleType, isNull);
  });

  test('courseDeadlines: this course, due kinds, at most a day overdue, soonest first', () {
    final all = [
      due('Lab 6', 'Multimedia Computing', now.add(const Duration(days: 3))),
      due('Lab 5', 'Multimedia', now.add(const Duration(hours: 5))), // calendar name cut short
      due('Lab 4', 'Multimedia Computing', now.subtract(const Duration(hours: 30))), // long overdue
      due('Lab 3', 'Multimedia Computing', now.subtract(const Duration(hours: 2))),
      due('Multimedia Computing[001]-3교시', 'Multimedia Computing', now, kind: DeadlineKind.classPeriod),
      due('Homework 2', 'Artificial Intelligence', now.add(const Duration(hours: 1))),
    ];
    expect(courseDeadlines(mmc, all, att, now).map((d) => d.title), ['Lab 3', 'Lab 5', 'Lab 6']);
  });

  test('gradeFor: latest term by course code, else by name', () {
    final report = GradeReport(gpa: 4, creditsEarned: 90, yearOfStudy: 3, records: [
      grade(20251, 'SOC4020', 'Multimedia Computing', 'C+'), // retaken
      grade(20262, 'SOC4020', 'Multimedia Computing', '-'),
      grade(20262, 'XYZ1', 'artificial  intelligence', 'A0'),
    ]);
    expect(gradeFor(mmc, report)!.termKey, 20262);
    expect(gradeFor(mmc, report)!.graded, isFalse);
    expect(gradeFor(const Course(id: 1, name: 'Artificial Intelligence', code: ''), report)!.letter, 'A0');
    expect(gradeFor(const Course(id: 1, name: 'Blockchain', code: 'SOC4190'), report), isNull);
    expect(gradeFor(mmc, null), isNull);
  });

  test('held: sessions up to and including today, not the rest of the semester', () {
    final c = CourseAttendance(course: ai, classes: [
      AttendanceEntry(date: DateTime(2026, 10, 21), label: '1Class', mark: AttendanceMark.present),
      AttendanceEntry(date: DateTime(2026, 10, 23), label: '2Class', mark: AttendanceMark.unmarked),
      AttendanceEntry(date: DateTime(2026, 10, 28), label: '1Class', mark: AttendanceMark.unmarked),
    ]);
    expect(c.held(now).map((e) => e.date.day), [21, 23]);
  });
}
