import '../models/models.dart';
import 'urgency.dart';

// Exam timetables (docs/EXAMS.md). No IUT service publishes them, so each
// sheet is curated from the university's PDF by tool/exam_timetable.py into
// assets/exams/ and bundled with the app. Pure: reading the sheet, reading a
// cell, and matching sittings to the student's courses.

/// The bundled timetables. A new sheet (the finals) is one more file here.
const examSheets = ['assets/exams/2026-fall-midterm.json'];

/// How long before its first exam a period shows on Today, Schedule and
/// course detail. It shows until its last exam ends.
const examLead = Duration(days: 21);

/// One exam week: a midterm or a final.
class ExamPeriod {
  final String id; // "2026-fall-midterm"
  final String kind; // "midterm", "final"
  final String term; // "Fall 2026"
  final String source; // the PDF it was read from

  /// Whether the university has said which room each student sits in. Until
  /// then a sitting only has the rooms it uses.
  final bool roomsAssigned;
  final Map<String, int?> seats; // room -> seats, null when the sheet gives none
  final List<Exam> exams; // in time order

  const ExamPeriod({
    required this.id,
    required this.kind,
    required this.term,
    required this.source,
    required this.roomsAssigned,
    required this.seats,
    required this.exams,
  });

  /// "Midterm", "Final"
  String get name => kind == 'final' ? 'Final' : 'Midterm';

  DateTime get first => exams.first.start;
  DateTime get last => exams.map((e) => e.end).reduce((a, b) => a.isAfter(b) ? a : b);

  /// Shown from [examLead] before the first exam until the last one ends.
  bool shownAt(DateTime now) => exams.isNotEmpty && now.isAfter(first.subtract(examLead)) && now.isBefore(last);

  factory ExamPeriod.fromJson(Map<String, dynamic> j) {
    if (j['format'] != 1) throw FormatException('Unknown exam sheet format ${j['format']}');
    return ExamPeriod(
      id: j['id'] as String,
      kind: j['kind'] as String,
      term: j['term'] as String,
      source: j['source'] as String,
      roomsAssigned: j['roomsAssigned'] as bool,
      seats: {for (final e in (j['seats'] as Map<String, dynamic>).entries) e.key: e.value as int?},
      exams: _inTimeOrder([for (final e in j['exams'] as List) Exam.fromJson(e as Map<String, dynamic>)], (e) => e),
    );
  }

  /// Sorted by start, keeping the sheet's order (its columns) within a slot.
  static List<T> _inTimeOrder<T>(List<T> items, Exam Function(T) exam) {
    final order = [...items.indexed]..sort((a, b) {
        final byTime = exam(a.$2).start.compareTo(exam(b.$2).start);
        return byTime != 0 ? byTime : a.$1.compareTo(b.$1);
      });
    return [for (final (_, item) in order) item];
  }

  /// The period on show at [now], the earliest first; null outside every window.
  static ExamPeriod? current(List<ExamPeriod> all, DateTime now) =>
      ([...all.where((p) => p.shownAt(now))]..sort((a, b) => a.first.compareTo(b.first))).firstOrNull;
}

/// One sitting on the sheet: a course in a slot, in one or more rooms.
class Exam {
  final String slot; // "Th-3"
  final DateTime start;
  final DateTime end;
  final String cell; // as printed: "Database (Dr.Sarvar)"
  final List<String> rooms; // in the sheet's column order
  final ExamCell read;

  const Exam({
    required this.slot,
    required this.start,
    required this.end,
    required this.cell,
    required this.rooms,
    required this.read,
  });

  String get course => read.course;
  Duration get length => end.difference(start);

  /// Stable across app versions while the sheet is unchanged: the key of the
  /// room the student picked.
  String keyIn(ExamPeriod p) => '${p.id}|$slot|$cell';

  /// The slot's times, unless the cell gives its own length ("Physics 1
  /// (90min)"): then the exam starts with the slot and lasts that long.
  factory Exam.fromJson(Map<String, dynamic> j) {
    final day = DateTime.parse(j['date'] as String);
    DateTime at(String hhmm) {
      final p = hhmm.split(':');
      return DateTime(day.year, day.month, day.day, int.parse(p[0]), int.parse(p[1]));
    }

    final read = ExamCell.parse(j['cell'] as String);
    final start = at(j['start'] as String);
    final minutes = read.minutes;
    return Exam(
      slot: j['slot'] as String,
      start: start,
      end: minutes == null ? at(j['end'] as String) : start.add(Duration(minutes: minutes)),
      cell: j['cell'] as String,
      rooms: [for (final r in j['rooms'] as List) r as String],
      read: read,
    );
  }
}

/// A class group as the sheet and EduPage write it: "ICE23-1", "IT 26-1",
/// "AI 25-01". [program] is empty when the sheet leaves it out ("26-05").
class ExamGroup {
  final String program;
  final int year;
  final int number;
  const ExamGroup(this.program, this.year, this.number);

  static final _class = RegExp(r'^([A-Z]+(?:\([A-Z]\))?)\s*-?\s*(\d{2})-(\d+)$');

  /// EduPage's group name, e.g. "ICE23-1" or "SBL(B)25-2"; null if it has
  /// another shape.
  static ExamGroup? ofClass(String name) {
    final m = _class.firstMatch(name.trim().toUpperCase());
    return m == null ? null : ExamGroup(m[1]!, int.parse(m[2]!), int.parse(m[3]!));
  }

  bool includes(ExamGroup g) => (program.isEmpty || program == g.program) && year == g.year && number == g.number;

  @override
  String toString() => '$program$year-$number';
}

/// What a cell says: "(UK) Intro to Data Science (AI 25-01)" is the course
/// "Intro to Data Science" for the UK programme's AI 25-01 group.
class ExamCell {
  final String course;
  final bool uk; // "(UK)": the UK programme's sitting
  final List<ExamGroup> groups; // "(AI 25-01/DS 25-01)"
  final String? teacher; // "(Dr.Sarvar)" -> "Sarvar"
  final String? school; // "(SBL)", "(SOCIE)"
  final String? department; // "(CSE)", "(ICE)"
  final int? minutes; // "(90min)", "(60)"

  /// The qualifiers that tell sittings of one course apart, as printed:
  /// "Dr.Sarvar", "AI 25-01". Empty when there are none.
  final String note;

  const ExamCell({
    required this.course,
    this.uk = false,
    this.groups = const [],
    this.teacher,
    this.school,
    this.department,
    this.minutes,
    this.note = '',
  });

  static const schools = {'SBL', 'SOCIE'};
  static final _trailing = RegExp(r'\s*\(([^()]*)\)\s*$');
  static final _minutes = RegExp(r'^(\d{2,3})\s*(min)?$', caseSensitive: false);
  static final _teacher = RegExp(r'^Dr\.?\s*(.+)$');
  static final _department = RegExp(r'^[A-Z]{2,5}$');
  static final _yearNumber = RegExp(r'(\d{2})\s*-\s*(\d{1,2})');

  factory ExamCell.parse(String cell) {
    var s = cell.trim();
    var uk = false;
    final mark = RegExp(r'^(\(UK\)|UK\s)\s*').firstMatch(s);
    if (mark != null) {
      uk = true;
      s = s.substring(mark.end);
    }
    final qualifiers = <String>[];
    for (var m = _trailing.firstMatch(s); m != null && m.start > 0; m = _trailing.firstMatch(s)) {
      qualifiers.insert(0, m[1]!.trim());
      s = s.substring(0, m.start);
    }
    String? teacher, school, department;
    int? minutes;
    final groups = <ExamGroup>[];
    final notes = <String>[];
    for (final q in qualifiers) {
      final mins = _minutes.firstMatch(q);
      final dr = _teacher.firstMatch(q);
      if (mins != null) {
        minutes = int.parse(mins[1]!);
        continue;
      }
      notes.add(q);
      if (dr != null) {
        teacher = dr[1]!.trim();
      } else if (schools.contains(q.toUpperCase())) {
        school = q.toUpperCase();
      } else if (_department.hasMatch(q)) {
        department = q;
      } else if (_yearNumber.hasMatch(q)) {
        groups.addAll(parseGroups(q));
      }
    }
    return ExamCell(
      course: s.replaceAll(RegExp(r'[\s\-–]+$'), '').trim(),
      uk: uk,
      groups: groups,
      teacher: teacher,
      school: school,
      department: department,
      minutes: minutes,
      note: notes.join(' · '),
    );
  }

  /// "IT 26-1/26-3" -> IT26-1, IT26-3; "AI -DS 25-1" -> AI25-1, DS25-1;
  /// "26-01/03, 26-02/04" -> 26-1, 26-3, 26-2, 26-4 (programme not printed).
  static List<ExamGroup> parseGroups(String q) {
    final out = <ExamGroup>[];
    var programs = [''];
    int? year;
    for (final chunk in q.split(RegExp(r'[/,]'))) {
      final named = RegExp(r'[A-Z]{2,}').allMatches(chunk).map((m) => m[0]!).toList();
      if (named.isNotEmpty) programs = named;
      final yn = _yearNumber.firstMatch(chunk);
      final lone = RegExp(r'^\s*(\d{1,2})\s*$').firstMatch(chunk);
      if (yn != null) {
        year = int.parse(yn[1]!);
        out.addAll([for (final p in programs) ExamGroup(p, year, int.parse(yn[2]!))]);
      } else if (lone != null && year != null) {
        out.addAll([for (final p in programs) ExamGroup(p, year, int.parse(lone[1]!))]);
      }
    }
    return out;
  }
}

/// One of the student's courses, from the timetable and eClass together.
class StudentCourse {
  final String name; // the timetable's name, else eClass's
  final Set<String> teachers;
  final Course? eclass;
  const StudentCourse(this.name, {this.teachers = const {}, this.eclass});
}

/// The timetable's subjects, each joined with its eClass course, then the
/// eClass courses the timetable doesn't have.
List<StudentCourse> studentCourses(List<Lesson> lessons, List<CourseAttendance> attendance) {
  final out = <StudentCourse>[];
  final joined = <int>{};
  for (final subject in {for (final l in lessons) l.subject}) {
    final course = courseFor(subject, attendance)?.course;
    if (course != null) joined.add(course.id);
    out.add(StudentCourse(subject,
        teachers: {
          for (final l in lessons)
            if (l.subject == subject && l.teacher.isNotEmpty) l.teacher,
          if (course != null && course.professor.isNotEmpty) course.professor,
        },
        eclass: course));
  }
  for (final c in attendance) {
    if (joined.contains(c.course.id)) continue;
    out.add(StudentCourse(c.course.name,
        teachers: {if (c.course.professor.isNotEmpty) c.course.professor}, eclass: c.course));
  }
  return out;
}

/// A sitting of one of the student's courses.
class MyExam {
  final StudentCourse course;
  final Exam exam;

  /// How many sittings of this course the sheet lists that nothing the app
  /// knows tells apart (two teachers, say). Usually 1.
  final int sittings;

  /// The room the student set, once they know it.
  final String? room;

  const MyExam(this.course, this.exam, {this.sittings = 1, this.room});
}

/// The student's exams in time order, and their courses the sheet has none for.
class ExamMatch {
  final ExamPeriod period;
  final List<MyExam> exams;
  final List<StudentCourse> unlisted;
  const ExamMatch(this.period, this.exams, this.unlisted);
}

/// Matches the sheet to the student's courses. Names are compared loosely,
/// as [courseFor] does: an exact match first, else a prefix either way that
/// points at one course. The UK programme's sittings go only to UK groups,
/// and qualifiers ("(SOCIE)", "(ICE)", "(Dr.Sarvar)", "(AI 25-01)") narrow a
/// course with several sittings to the one that fits [classGroup] and the
/// course's teachers. Sittings nothing tells apart are all kept.
ExamMatch matchExams(ExamPeriod period, List<StudentCourse> courses,
    {String classGroup = '', Map<String, String> rooms = const {}}) {
  final group = ExamGroup.ofClass(classGroup);
  final ukPrograms = {
    for (final e in period.exams)
      if (e.read.uk)
        for (final g in e.read.groups)
          if (g.program.isNotEmpty) g.program,
  };
  final ukStudent = group != null && ukPrograms.contains(group.program);

  List<Exam> forAudience(List<Exam> found) {
    if (!ukStudent) return found.where((e) => !e.read.uk).toList();
    return found.any((e) => e.read.uk) ? found.where((e) => e.read.uk).toList() : found;
  }

  final mine = <Exam, MyExam>{};
  final unlisted = <StudentCourse>[];
  for (final c in courses) {
    var found = forAudience(period.exams.where((e) => _sameCourse(e.course, c.name)).toList());
    if (found.isEmpty) {
      final near = forAudience(period.exams.where((e) => _nearCourse(e.course, c.name)).toList());
      if ({for (final e in near) examName(e.course)}.length == 1) found = near;
    }
    final fits = found.where((e) => _fits(e.read, group, c.teachers) != false).toList();
    final chosen = fits.isEmpty ? found : fits;
    if (chosen.isEmpty) {
      unlisted.add(c);
      continue;
    }
    for (final e in chosen) {
      // A timetable subject and an eClass course the names didn't join meet
      // here, at the same sitting: one exam, with the eClass course.
      final before = mine[e];
      final course = before == null || before.course.eclass != null || c.eclass == null
          ? before?.course ?? c
          : StudentCourse(before.course.name, teachers: {...before.course.teachers, ...c.teachers}, eclass: c.eclass);
      mine[e] = MyExam(course, e, sittings: chosen.length, room: rooms[e.keyIn(period)]);
    }
  }
  final sheetOrder = {for (final (i, e) in period.exams.indexed) e: i};
  final ordered = mine.values.toList()..sort((a, b) => sheetOrder[a.exam]!.compareTo(sheetOrder[b.exam]!));
  return ExamMatch(period, ordered, unlisted);
}

/// null when nothing the app knows says either way.
bool? _fits(ExamCell cell, ExamGroup? group, Set<String> teachers) {
  final votes = <bool>[];
  if (cell.groups.isNotEmpty && group != null) votes.add(cell.groups.any((g) => g.includes(group)));
  if (cell.school != null && group != null) {
    final school = _schoolOf(group.program);
    if (school != null) votes.add(school == cell.school);
  }
  if (cell.department != null && group != null) votes.add(cell.department == group.program);
  if (cell.teacher != null && teachers.isNotEmpty) {
    final name = cell.teacher!.toLowerCase();
    votes.add(teachers.any((t) => t.toLowerCase().contains(name)));
  }
  if (votes.isEmpty) return null;
  return votes.every((v) => v);
}

/// The school a programme belongs to: Computer and Information Engineering
/// (SOCIE) or Business and Logistics (SBL).
String? _schoolOf(String program) => switch (program) {
      'CSE' || 'ICE' || 'CIE' => 'SOCIE',
      'SBL(B)' || 'SBL(L)' => 'SBL',
      _ => null,
    };

const _short = {'intro': 'introduction', 'math': 'mathematics', 'tech': 'technical', 'ii': '2', 'iii': '3', 'iv': '4'};
const _minor = {'and', 'of', 'to', 'the', 'in', 'for', 'with', 'on'};

/// A course name for comparing: lower case, "&" as "and", no punctuation,
/// the sheet's short words spelled out, and plurals dropped, so "CS Policies
/// and Governance" meets "CS Policy and Governance".
String examName(String name) {
  final words = name
      .toLowerCase()
      .replaceAll('&', ' and ')
      .replaceAll(RegExp(r'[^a-z0-9 ]'), ' ')
      .split(' ')
      .where((w) => w.isNotEmpty)
      .map((w) => _short[w] ?? w)
      .map((w) => w.length > 3 && w.endsWith('ies')
          ? '${w.substring(0, w.length - 3)}y'
          : w.length > 3 && w.endsWith('s') && !w.endsWith('ss')
              ? w.substring(0, w.length - 1)
              : w);
  return words.join(' ');
}

/// The same course: equal names, or the sheet's acronym of it ("PCAD" for
/// "Programming Concepts and Application Development").
bool _sameCourse(String sheet, String mine) {
  if (examName(sheet) == examName(mine)) return true;
  if (!RegExp(r'^[A-Z]{3,6}$').hasMatch(sheet)) return false;
  final initials = mine.split(RegExp(r'[\s\-]+')).where((w) => w.isNotEmpty && !_minor.contains(w.toLowerCase()));
  return initials.map((w) => w[0].toUpperCase()).join() == sheet;
}

/// One name starts with the other ("Basic Korean 1" and "Basic Korean 1-Rus").
bool _nearCourse(String sheet, String mine) {
  final a = examName(sheet), b = examName(mine);
  final shorter = a.length < b.length ? a : b;
  return shorter.length >= 5 && (a.startsWith(b) || b.startsWith(a));
}
