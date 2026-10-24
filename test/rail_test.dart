import 'package:flutter_test/flutter_test.dart';
import 'package:inha_app/data/exams.dart';
import 'package:inha_app/data/rail.dart';
import 'package:inha_app/models/models.dart';

const ai = Course(id: 2622, name: 'Artificial Intelligence', code: 'SOC4040');
const esd = Course(id: 2615, name: 'Embedded Software & Design', code: 'SOC3050');
const mmc = Course(id: 2592, name: 'Multimedia Computing', code: 'SOC4020');

// Fri 23 Oct 2026 and the week around it.
const lessons = [
  Lesson(weekday: 5, start: '14:00', end: '15:30', subject: 'Embedded Software & Design', room: 'B202'),
  Lesson(weekday: 1, start: '14:30', end: '16:00', subject: 'Deep Learning for Computer Vision', room: 'A305'),
  Lesson(weekday: 1, start: '13:00', end: '14:30', subject: 'Artificial Intelligence', room: 'B101 Conf'),
  Lesson(weekday: 2, start: '09:30', end: '11:00', subject: 'Multimedia Computing', room: 'B206'),
];

CourseAttendance absent(Course c, int n) => CourseAttendance(course: c, classes: [
      for (var i = 0; i < n; i++)
        AttendanceEntry(date: DateTime(2026, 9, 1 + i), label: '1Class', mark: AttendanceMark.absent),
    ]);

Deadline due(String title, DateTime end, {String course = 'Multimedia Computing', DeadlineKind kind = DeadlineKind.assignment}) =>
    Deadline(title: title, courseName: course, kind: kind, end: end);

/// A short readable form of each entry, for comparing whole rails.
String show(RailEntry e) => switch (e) {
      RailOverdue() => 'Overdue',
      RailNow(:final at) => 'Now ${at.hour}:${at.minute}',
      RailDay(:final day) => 'Day ${day.month}/${day.day}',
      RailClass(:final lesson, :final role, :final trouble) =>
        '${role.name} ${lesson.subject}${trouble == null ? '' : ' !${trouble.used}/${trouble.limit}'}',
      RailExam(:final exam, :final role) => '${role.name} exam ${exam.course.name}',
      RailDue(:final deadline) => 'Due ${deadline.title}',
      RailNote(:final kind) => kind.name,
    };

List<String> rail(DateTime now,
        {List<Deadline> deadlines = const [],
        List<CourseAttendance> attendance = const [],
        Map<int, int> limits = const {},
        List<Lesson> timetable = lessons,
        bool timetableKnown = true,
        List<MyExam> exams = const [],
        Set<DateTime> classFree = const {}}) =>
    todayRail(
      lessons: timetable,
      deadlines: deadlines,
      attendance: attendance,
      limits: limits,
      now: now,
      timetableKnown: timetableKnown,
      exams: exams,
      classFree: classFree,
    ).map(show).toList();

/// A sitting of [course] on the Fall 2026 midterm.
MyExam exam(String course, DateTime start, {int minutes = 60}) => MyExam(
    StudentCourse(course),
    Exam(
        slot: 'M-2',
        start: start,
        end: start.add(Duration(minutes: minutes)),
        cell: course,
        rooms: const ['B209', 'B210'],
        read: ExamCell(course: course)));

void main() {
  final sunday = DateTime(2026, 10, 25);
  final deadlines = [
    due('Assignment 1', sunday.add(const Duration(hours: 23, minutes: 55))),
    due('Video 7', sunday.add(const Duration(hours: 23, minutes: 59)),
        course: 'Distinguished Lecture in Social Science and Art', kind: DeadlineKind.vod),
    due('Lab 6', DateTime(2026, 11, 2, 23, 59)), // beyond 72 h
  ];

  test('before a class: Now, the next class, the free afternoon, then the next days', () {
    expect(rail(DateTime(2026, 10, 23, 13, 20), deadlines: deadlines), [
      'Now 13:20',
      'next Embedded Software & Design',
      'freeAfter',
      'Day 10/25',
      'Due Assignment 1',
      'Due Video 7',
      'Day 10/26',
      'row Artificial Intelligence',
    ]);
  });

  test('during a class it leads, with no separate Now row', () {
    expect(rail(DateTime(2026, 10, 23, 14, 30)).take(2), ['current Embedded Software & Design', 'freeAfter']);
  });

  test('after the last class, and on a day without classes', () {
    expect(rail(DateTime(2026, 10, 23, 16)).take(3), ['Now 16:0', 'noMoreClasses', 'Day 10/26']);
    expect(rail(DateTime(2026, 10, 24, 10)).take(3), ['Now 10:0', 'noClasses', 'Day 10/26']);
  });

  test('without a timetable nothing is said about classes', () {
    expect(rail(DateTime(2026, 10, 24, 10), timetable: const [], timetableKnown: false), ['Now 10:0']);
  });

  test('overdue items sit above Now; what is due today sits at its time', () {
    final r = rail(DateTime(2026, 10, 23, 13, 20), deadlines: [
      due('Quiz 1', DateTime(2026, 10, 23, 12), kind: DeadlineKind.quiz),
      due('Lab 5', DateTime(2026, 10, 23, 13, 59)),
      due('Report', DateTime(2026, 10, 23, 18)),
    ]);
    expect(r.take(6), ['Overdue', 'Due Quiz 1', 'Now 13:20', 'Due Lab 5', 'next Embedded Software & Design', 'freeAfter']);
    expect(r[6], 'Due Report');
  });

  test('done and watched items stay off the rail', () {
    final d = due('Assignment 1', DateTime(2026, 10, 24, 23, 55)).withDone(true, DateTime(2026, 10, 22));
    expect(rail(DateTime(2026, 10, 23, 13, 20), deadlines: [d]), isNot(contains('Due Assignment 1')));
  });

  test('a course in trouble brings its next class, which carries the warning once', () {
    final r = rail(DateTime(2026, 10, 23, 13, 20),
        attendance: [absent(ai, 2), absent(mmc, 7), absent(esd, 1)], limits: {ai.id: 8, mmc.id: 8, esd.id: 8});
    expect(r, [
      'Now 13:20',
      'next Embedded Software & Design',
      'freeAfter',
      'Day 10/26',
      'row Artificial Intelligence',
      'Day 10/27',
      'row Multimedia Computing !7/8',
    ]);
  });

  test('the warning goes on the first class of that course, even the hero', () {
    final r = rail(DateTime(2026, 10, 23, 13, 20), attendance: [absent(esd, 8), absent(ai, 7)], limits: {esd.id: 8, ai.id: 8});
    expect(r[1], 'next Embedded Software & Design !8/8');
    expect(r.where((e) => e.contains('!')), hasLength(2));
    expect(r, contains('row Artificial Intelligence !7/8'));
  });

  test('nextLesson looks through the coming week', () {
    final n = nextLesson(lessons, DateTime(2026, 10, 23, 16), (l) => isLessonOf(l, mmc));
    expect(n?.lesson.room, 'B206');
    expect(n?.day, DateTime(2026, 10, 27));
    expect(nextLesson(lessons, DateTime(2026, 10, 23, 14, 30), (l) => isLessonOf(l, esd))?.day, DateTime(2026, 10, 23));
  });

  group('exams', () {
    final midterm = [
      exam('Deep Learning for Computer Vision', DateTime(2026, 10, 26, 11, 30)),
      exam('Artificial Intelligence', DateTime(2026, 10, 27, 14)),
      exam('Embedded Software & Design', DateTime(2026, 10, 28, 9, 30)),
    ];

    test('the next days hold the exams within 72 h, before a class at the same day', () {
      expect(rail(DateTime(2026, 10, 24, 8), exams: midterm), [
        'Now 8:0',
        'noClasses',
        'Day 10/26',
        'row exam Deep Learning for Computer Vision',
        'row Artificial Intelligence',
      ]);
    });

    test('an exam before the first class today is the hero', () {
      expect(rail(DateTime(2026, 10, 26, 9), exams: midterm).take(5), [
        'Now 9:0',
        'next exam Deep Learning for Computer Vision',
        'row Artificial Intelligence',
        'row Deep Learning for Computer Vision',
        'freeAfter',
      ]);
    });

    test('during an exam it leads, with no separate Now row', () {
      expect(rail(DateTime(2026, 10, 26, 12), exams: midterm).take(3), [
        'current exam Deep Learning for Computer Vision',
        'row Artificial Intelligence',
        'row Deep Learning for Computer Vision',
      ]);
    });

    test('a class before the exam stays the hero; the exam follows at its time', () {
      final r = rail(DateTime(2026, 10, 27, 8), exams: midterm);
      expect(r.take(4), ['Now 8:0', 'next Multimedia Computing', 'row exam Artificial Intelligence', 'freeAfter']);
    });

    final examWeek = {for (var d = 26; d <= 30; d++) DateTime(2026, 10, d)};

    test('no classes in an exam week: exams only, then the first class after it', () {
      expect(rail(DateTime(2026, 10, 26, 9), exams: midterm, classFree: examWeek), [
        'Now 9:0',
        'next exam Deep Learning for Computer Vision',
        'freeAfter',
        'Day 10/27',
        'row exam Artificial Intelligence',
        'Day 10/28',
        'row exam Embedded Software & Design',
        'Day 11/2',
        'row Artificial Intelligence',
      ]);
      expect(rail(DateTime(2026, 10, 29, 9), exams: midterm, classFree: examWeek).take(2), ['Now 9:0', 'noClasses']);
    });

    test('lessonsOn and nextLesson skip the class-free days', () {
      expect(lessonsOn(lessons, DateTime(2026, 10, 26), off: examWeek), isEmpty);
      expect(lessonsOn(lessons, DateTime(2026, 11, 2), off: examWeek), hasLength(2));
      final next = nextLesson(lessons, DateTime(2026, 10, 24, 8), (l) => isLessonOf(l, mmc), off: examWeek);
      expect(next, isNull); // Tue 3 Nov is beyond the week it looks through
      expect(nextLesson(lessons, DateTime(2026, 10, 27, 8), (l) => isLessonOf(l, mmc), off: examWeek)?.day,
          DateTime(2026, 11, 3));
    });

    test('a day with only an exam is free after it, then has no more', () {
      expect(rail(DateTime(2026, 10, 28, 8), exams: midterm).take(3),
          ['Now 8:0', 'next exam Embedded Software & Design', 'freeAfter']);
      expect(rail(DateTime(2026, 10, 28, 11), exams: midterm).take(2), ['Now 11:0', 'noMoreClasses']);
    });
  });
}
