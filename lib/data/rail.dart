import '../models/models.dart';
import 'absence.dart';
import 'exams.dart';
import 'urgency.dart';

// Today's day rail (DESIGN.md 7): one timeline from now through today's
// classes into the next days. Pure: data and a clock in, entries out.

/// One line on the rail, top to bottom.
sealed class RailEntry {
  const RailEntry();
}

/// The "Overdue" header; overdue items follow it, above Now.
class RailOverdue extends RailEntry {
  const RailOverdue();
}

/// The current time. Left out while a class is in progress.
class RailNow extends RailEntry {
  final DateTime at;
  const RailNow(this.at);
}

/// A day header for the days after today.
class RailDay extends RailEntry {
  final DateTime day;
  const RailDay(this.day);
}

enum ClassRole {
  /// In progress now: the hero, with no Now row above it.
  current,

  /// The next class today: the hero.
  next,

  /// Any other class: an ordinary row.
  row,
}

/// A class on [day]. [trouble] is set on the first class of a course that is
/// in attendance trouble, which is where its warning goes.
class RailClass extends RailEntry {
  final Lesson lesson;
  final DateTime day;
  final ClassRole role;
  final AbsenceState? trouble;
  const RailClass(this.lesson, this.day, this.role, {this.trouble});

  DateTime get start => lessonStart(lesson, day);
  DateTime get end => lessonEnd(lesson, day);
}

/// One of the student's exams at its time. [role] as for a class: an exam in
/// progress, or the next thing today, is the hero.
class RailExam extends RailEntry {
  final MyExam exam;
  final ClassRole role;
  const RailExam(this.exam, this.role);
}

/// How far ahead exams go on the rail, as deadlines do.
const examTodayWindow = Duration(hours: 72);

/// A deadline or VOD window at its due time.
class RailDue extends RailEntry {
  final Deadline deadline;
  const RailDue(this.deadline);
}

enum RailNoteKind { freeAfter, noMoreClasses, noClasses }

/// "Free for the rest of the day" (at [at]), "No more classes today",
/// "No classes today".
class RailNote extends RailEntry {
  final RailNoteKind kind;
  final DateTime? at;
  const RailNote(this.kind, [this.at]);
}

int _minutes(String hhmm) {
  final p = hhmm.split(':');
  return (int.tryParse(p.first) ?? 0) * 60 + (p.length > 1 ? int.tryParse(p[1]) ?? 0 : 0);
}

DateTime _midnight(DateTime t) => DateTime(t.year, t.month, t.day);

DateTime lessonStart(Lesson l, DateTime day) => _midnight(day).add(Duration(minutes: _minutes(l.start)));
DateTime lessonEnd(Lesson l, DateTime day) => _midnight(day).add(Duration(minutes: _minutes(l.end)));

List<Lesson> lessonsOn(List<Lesson> lessons, DateTime day) =>
    lessons.where((l) => l.weekday == day.weekday).toList()..sort((a, b) => _minutes(a.start).compareTo(_minutes(b.start)));

/// The next class [test] accepts: one in progress or still to come today,
/// then the next 7 days. Null when there is none in that week.
({Lesson lesson, DateTime day})? nextLesson(List<Lesson> lessons, DateTime now, bool Function(Lesson) test) {
  for (var i = 0; i <= 7; i++) {
    final day = _midnight(now).add(Duration(days: i));
    for (final l in lessonsOn(lessons, day)) {
      if (test(l) && lessonEnd(l, day).isAfter(now)) return (lesson: l, day: day);
    }
  }
  return null;
}

/// Whether a timetable subject is this eClass course (names can be cut short
/// on either side).
bool isLessonOf(Lesson l, Course course) => courseFor(l.subject, [CourseAttendance(course: course)]) != null;

/// Builds Today's rail. [timetableKnown] is false while there is no
/// timetable at all (first run, EduPage failing), so "No classes today" is
/// never claimed without data. [exams] are the student's, from the period on
/// show; they sit on the rail like classes.
List<RailEntry> todayRail({
  required List<Lesson> lessons,
  required List<Deadline> deadlines,
  required List<CourseAttendance> attendance,
  required Map<int, int> limits,
  required DateTime now,
  bool timetableKnown = true,
  List<MyExam> exams = const [],
}) {
  final today = _midnight(now);
  final tomorrow = today.add(const Duration(days: 1));
  final due = needsAttention(deadlines, attendance, now);
  final out = <RailEntry>[];

  final overdue = due.where((d) => d.end.isBefore(now)).toList();
  if (overdue.isNotEmpty) out.addAll([const RailOverdue(), for (final d in overdue) RailDue(d)]);

  // Today: the hero, the classes and exams after it, and what is due today, in time order.
  final todays = lessonsOn(lessons, today);
  final examsToday = exams.where((e) => !e.exam.start.isBefore(today) && e.exam.start.isBefore(tomorrow)).toList();
  final classNow = todays.where((l) => !lessonStart(l, today).isAfter(now) && lessonEnd(l, today).isAfter(now)).firstOrNull;
  // An exam in progress is the hero even if the timetable has a class then.
  final examNow = examsToday.where((e) => !e.exam.start.isAfter(now) && e.exam.end.isAfter(now)).firstOrNull;
  final current = examNow == null ? classNow : null;
  final upcoming = todays.where((l) => lessonStart(l, today).isAfter(now)).toList();
  final upcomingExams = examsToday.where((e) => e.exam.start.isAfter(now)).toList();
  final nextIsExam = examNow == null &&
      current == null &&
      upcomingExams.isNotEmpty &&
      (upcoming.isEmpty || !lessonStart(upcoming.first, today).isBefore(upcomingExams.first.exam.start));
  // Time, then a tie-break: the end-of-day note, exams, classes, what is due.
  final timed = <(DateTime, int, RailEntry)>[];
  if (examNow != null) {
    out.add(RailExam(examNow, ClassRole.current));
    if (classNow != null) timed.add((now, 2, RailClass(classNow, today, ClassRole.row)));
  } else if (current != null) {
    out.add(RailClass(current, today, ClassRole.current));
  } else {
    out.add(RailNow(now));
  }
  final heroTaken = examNow != null || current != null || nextIsExam;
  for (final (i, l) in upcoming.indexed) {
    timed.add((lessonStart(l, today), 2, RailClass(l, today, !heroTaken && i == 0 ? ClassRole.next : ClassRole.row)));
  }
  for (final (i, e) in upcomingExams.indexed) {
    timed.add((e.exam.start, 1, RailExam(e, nextIsExam && i == 0 ? ClassRole.next : ClassRole.row)));
  }
  for (final d in due.where((d) => !d.end.isBefore(now) && d.end.isBefore(tomorrow))) {
    timed.add((d.end, 3, RailDue(d)));
  }
  if (timetableKnown) {
    if (todays.isEmpty && examsToday.isEmpty) {
      out.add(const RailNote(RailNoteKind.noClasses));
    } else if (examNow == null && current == null && upcoming.isEmpty && upcomingExams.isEmpty) {
      out.add(const RailNote(RailNoteKind.noMoreClasses));
    } else {
      final lastEnd = [
        for (final l in todays) lessonEnd(l, today),
        for (final e in examsToday) e.exam.end,
      ].reduce((a, b) => a.isAfter(b) ? a : b);
      timed.add((lastEnd, 0, RailNote(RailNoteKind.freeAfter, lastEnd)));
    }
  }
  timed.sort((a, b) {
    final byTime = a.$1.compareTo(b.$1);
    return byTime != 0 ? byTime : a.$2.compareTo(b.$2);
  });
  out.addAll(timed.map((e) => e.$3));

  // The next days: what is due, the first class of the next day with
  // classes, and the next class of every course in attendance trouble.
  final later = <DateTime, List<(DateTime, int, RailEntry)>>{};
  void put(DateTime at, int order, RailEntry e) => later.putIfAbsent(_midnight(at), () => []).add((at, order, e));
  for (final d in due.where((d) => !d.end.isBefore(tomorrow))) {
    put(d.end, 3, RailDue(d));
  }
  for (final e in exams.where((e) => !e.exam.start.isBefore(tomorrow) && !e.exam.start.isAfter(now.add(examTodayWindow)))) {
    put(e.exam.start, 1, RailExam(e, ClassRole.row));
  }
  final placed = <(Lesson, DateTime)>{};
  void putClass(Lesson l, DateTime day) {
    if (!placed.add((l, day))) return;
    put(lessonStart(l, day), 2, RailClass(l, day, ClassRole.row));
  }

  final first = nextLesson(lessons, tomorrow, (_) => true);
  if (first != null) putClass(first.lesson, first.day);
  final classesToday = {classNow, ...upcoming}.whereType<Lesson>().toSet();
  for (final c in attendance) {
    if (!AbsenceState.of(c, limits).trouble) continue;
    if (classesToday.any((l) => isLessonOf(l, c.course))) continue;
    final next = nextLesson(lessons, tomorrow, (l) => isLessonOf(l, c.course));
    if (next != null) putClass(next.lesson, next.day);
  }
  for (final day in later.keys.toList()..sort()) {
    final items = later[day]!
      ..sort((a, b) {
        final byTime = a.$1.compareTo(b.$1);
        return byTime != 0 ? byTime : a.$2.compareTo(b.$2);
      });
    out.add(RailDay(day));
    out.addAll(items.map((e) => e.$3));
  }

  // Each course's attendance warning goes on its first class on the rail.
  final warned = <int>{};
  return [
    for (final e in out)
      if (e is RailClass) _warned(e, attendance, limits, warned) else e,
  ];
}

RailClass _warned(RailClass e, List<CourseAttendance> attendance, Map<int, int> limits, Set<int> warned) {
  final c = attendance.where((c) => isLessonOf(e.lesson, c.course)).firstOrNull;
  if (c == null) return e;
  final state = AbsenceState.of(c, limits);
  if (!state.trouble || !warned.add(c.course.id)) return e;
  return RailClass(e.lesson, e.day, e.role, trouble: state);
}
