import 'package:flutter_test/flutter_test.dart';
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
      RailDue(:final deadline) => 'Due ${deadline.title}',
      RailNote(:final kind) => kind.name,
    };

List<String> rail(DateTime now,
        {List<Deadline> deadlines = const [],
        List<CourseAttendance> attendance = const [],
        Map<int, int> limits = const {},
        List<Lesson> timetable = lessons,
        bool timetableKnown = true}) =>
    todayRail(
      lessons: timetable,
      deadlines: deadlines,
      attendance: attendance,
      limits: limits,
      now: now,
      timetableKnown: timetableKnown,
    ).map(show).toList();

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
}
