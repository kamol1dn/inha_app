import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:inha_app/data/exams.dart';
import 'package:inha_app/models/models.dart';

/// The bundled Fall 2026 midterm sheet, as the app reads it.
ExamPeriod midterm() => ExamPeriod.fromJson(
    jsonDecode(File('assets/exams/2026-fall-midterm.json').readAsStringSync()) as Map<String, dynamic>);

Lesson lesson(String subject, {String teacher = ''}) =>
    Lesson(weekday: 1, start: '09:00', end: '10:30', subject: subject, teacher: teacher);

/// "Mon 11:30 Deep learning for computer vision B209 B210", for comparing.
String show(MyExam m) {
  const days = ['Mon', 'Tue', 'Wed', 'Thu', 'Fri', 'Sat', 'Sun'];
  final s = m.exam.start;
  final hhmm = '${s.hour.toString().padLeft(2, '0')}:${s.minute.toString().padLeft(2, '0')}';
  return '${days[s.weekday - 1]} $hhmm ${m.exam.cell} ${m.exam.rooms.join(' ')}';
}

List<String> examsOf(List<String> subjects, String group) =>
    matchExams(midterm(), [for (final s in subjects) StudentCourse(s)], classGroup: group).exams.map(show).toList();

void main() {
  group('the bundled sheets', () {
    test('every sheet in examSheets is bundled and parses', () {
      final pubspec = File('pubspec.yaml').readAsStringSync();
      expect(pubspec, contains('- assets/exams/'));
      for (final path in examSheets) {
        final p = ExamPeriod.fromJson(jsonDecode(File(path).readAsStringSync()) as Map<String, dynamic>);
        expect(p.exams, isNotEmpty, reason: path);
        for (final e in p.exams) {
          expect(e.rooms, isNotEmpty, reason: e.cell);
          expect(e.rooms.every(p.seats.containsKey), isTrue, reason: '${e.cell}: a room missing from seats');
          expect(e.end.isAfter(e.start), isTrue, reason: e.cell);
          expect(e.course, isNotEmpty, reason: e.cell);
        }
      }
    });

    test('Fall 2026 midterm: Mon 26 to Fri 30 Oct, 76 sittings in 27 slots', () {
      final p = midterm();
      expect(p.name, 'Midterm');
      expect(p.term, 'Fall 2026');
      expect(p.exams, hasLength(76));
      expect({for (final e in p.exams) e.slot}, hasLength(27));
      expect(p.first, DateTime(2026, 10, 26, 9, 30));
      expect(p.last, DateTime(2026, 10, 30, 16, 30));
      expect(p.seats['B304(A)'], 50);
      expect(p.seats['B102'], isNull); // the sheet gives no seats for it
      // The slot's letter is its weekday.
      const letters = {'M': 1, 'T': 2, 'W': 3, 'Th': 4, 'F': 5};
      for (final e in p.exams) {
        expect(e.start.weekday, letters[e.slot.split('-').first], reason: e.slot);
      }
    });

    test('a sitting keeps the sheet\'s text and every room it fills', () {
      final db = midterm().exams.where((e) => e.course == 'Database').toList();
      expect(db.map((e) => e.cell), ['Database (Dr.Sarvar)', 'Database (Dr.Agostini)']);
      expect(db.first.rooms, ['B304(A)', 'B304(B)', 'B304(C)', 'B305']);
      expect(db.first.start, DateTime(2026, 10, 29, 12, 30));
      expect(db.first.length, const Duration(hours: 1));
      // "Math for IT(26-01/03..." and "Math for IT (26-01/03..." are one sitting.
      final math = midterm().exams.where((e) => e.cell.startsWith('(UK) Math for IT (26-01')).single;
      expect(math.rooms, ['B304(A)', 'B304(B)', 'B304(C)']);
    });

    test('a cell that gives its own length ends after it', () {
      final physics = midterm().exams.firstWhere((e) => e.course == 'Physics 1');
      expect(physics.read.minutes, 90);
      expect(physics.end, DateTime(2026, 10, 26, 11, 0));
    });

    test('the period shows from 3 weeks before its first exam until its last one ends', () {
      final p = midterm();
      expect(p.shownAt(DateTime(2026, 10, 4)), isFalse);
      expect(p.shownAt(DateTime(2026, 10, 24, 8)), isTrue);
      expect(p.shownAt(DateTime(2026, 10, 30, 16, 29)), isTrue);
      expect(p.shownAt(DateTime(2026, 10, 30, 16, 30)), isFalse);
      expect(ExamPeriod.current([p], DateTime(2026, 11, 2)), isNull);
    });

    test('the exam week is class-free, and the days survive the trip through prefs', () {
      final days = classFreeDays([midterm()]);
      expect(days, {for (var d = 26; d <= 30; d++) DateTime(2026, 10, d)});
      expect(encodeDays(days), '["2026-10-26","2026-10-27","2026-10-28","2026-10-29","2026-10-30"]');
      expect(decodeDays(encodeDays(days)), days);
      expect(decodeDays(null), isEmpty);
      expect(decodeDays('not json'), isEmpty);
    });

    test('an unknown format is refused rather than misread', () {
      expect(() => ExamPeriod.fromJson({'format': 2}), throwsFormatException);
    });
  });

  group('reading a cell', () {
    test('course, programme, groups, teacher, school, department, length', () {
      final ds = ExamCell.parse('(UK) Intro to Data Science (AI 25-01)');
      expect((ds.course, ds.uk, ds.note), ('Intro to Data Science', true, 'AI 25-01'));
      expect([for (final g in ds.groups) '$g'], ['AI25-1']);

      final db = ExamCell.parse('Database (Dr.Sarvar)');
      expect((db.course, db.teacher, db.uk), ('Database', 'Sarvar', false));

      final econ = ExamCell.parse('Introduction to Economics- (SBL)');
      expect((econ.course, econ.school), ('Introduction to Economics', 'SBL'));

      expect(ExamCell.parse('Circuit and Lab (ICE)').department, 'ICE');
      expect(ExamCell.parse('(UK) Numeracy and data (90 min)').minutes, 90);
      expect(ExamCell.parse('Digital Logic Circuit (60)').minutes, 60); // the spring sheets' form
      expect(ExamCell.parse('Physics 1 (90min)').note, '');

      final policy = ExamCell.parse('(UK)CS Policy and Governance (CS 25-01)');
      expect((policy.course, policy.uk), ('CS Policy and Governance', true));

      final english = ExamCell.parse('UK English (BM 25-01)');
      expect((english.course, english.uk), ('English', true));

      final plain = ExamCell.parse('Embedded Software & Design');
      expect((plain.course, plain.uk, plain.note), ('Embedded Software & Design', false, ''));
    });

    test('group lists, with the programme and year carried over', () {
      List<String> groups(String q) => ExamCell.parseGroups(q).map((g) => '$g').toList();
      expect(groups('IT 26-1/26-3'), ['IT26-1', 'IT26-3']);
      expect(groups('AI 25-01/DS 25-01'), ['AI25-1', 'DS25-1']);
      expect(groups('AI -DS 25-1'), ['AI25-1', 'DS25-1']);
      expect(groups('BM-26-01'), ['BM26-1']);
      expect(groups('26-01/03, 26-02/04'), ['26-1', '26-3', '26-2', '26-4']);
      expect(groups('25-01'), ['25-1']);
    });

    test('EduPage group names', () {
      expect('${ExamGroup.ofClass('ICE23-1')}', 'ICE23-1');
      expect(ExamGroup.ofClass('SBL(B)25-2')?.program, 'SBL(B)');
      expect(ExamGroup.ofClass('Mental Education'), isNull);
      expect(const ExamGroup('', 26, 5).includes(ExamGroup.ofClass('IT26-5')!), isTrue);
      expect(const ExamGroup('AI', 25, 1).includes(ExamGroup.ofClass('DS25-1')!), isFalse);
    });

    test('names compare loosely', () {
      expect(examName('Object-Oriented Programming 1'), examName('Object Oriented Programming 1'));
      expect(examName('CS Policies and Governance'), examName('CS Policy and Governance'));
      expect(examName('Mathematics II'), examName('Math 2'));
      expect(examName('Embedded Software & Design'), 'embedded software and design');
      expect(examName('Statistics 1') == examName('Statistics 2'), isFalse);
    });
  });

  group('matching the student\'s courses', () {
    // An ICE 23 student's Fall 2026 courses, from the timetable and eClass.
    final lessons = [
      lesson('Artificial Intelligence'),
      lesson('Deep Learning for Computer Vision'),
      lesson('Multimedia Computing'),
      lesson('Embedded Software & Design'),
      lesson('Mental Education'),
    ];
    final attendance = [
      for (final (id, name) in [
        (2601, 'Distinguished Lecture in Social Science and Art'),
        (2615, 'Embedded Software & Design'),
        (2592, 'Multimedia Computing'),
        (2622, 'Artificial Intelligence'),
        (2630, 'Deep learning for computer vision'),
        (2640, 'Blockchain Basics and Platforms'),
      ])
        CourseAttendance(course: Course(id: id, name: name, code: '')),
    ];

    test('each course gets its sitting; the ones the sheet lacks are listed', () {
      final m = matchExams(midterm(), studentCourses(lessons, attendance), classGroup: 'ICE23-1');
      expect(m.exams.map(show), [
        'Mon 11:30 Deep learning for computer vision B209 B210',
        'Tue 14:00 Artificial Intelligence B304(A) B304(B) B304(C) B305 B306 B201',
        'Wed 09:30 Embedded Software & Design B304(A) B304(B) B304(C) B305 B306',
        'Wed 12:30 Multimedia Computing B304(A) B304(B) B304(C) B305 B306 B201',
        'Fri 09:30 Distinguished Lecture in Social Science and Art B304(A) B304(B) B304(C) B305 B306 B201',
      ]);
      // The timetable's name, joined with the eClass course.
      expect(m.exams.first.course.name, 'Deep Learning for Computer Vision');
      expect(m.exams.first.course.eclass?.id, 2630);
      expect(m.exams.last.course.eclass?.id, 2601); // eClass only
      expect(m.exams.every((e) => e.sittings == 1 && e.room == null), isTrue);
      expect(m.unlisted.map((c) => c.name), ['Mental Education', 'Blockchain Basics and Platforms']);
    });

    test('the room the student set comes with the sitting', () {
      final p = midterm();
      final ai = p.exams.firstWhere((e) => e.course == 'Artificial Intelligence');
      final m = matchExams(p, [const StudentCourse('Artificial Intelligence')],
          classGroup: 'ICE23-1', rooms: {ai.keyIn(p): 'B305'});
      expect(m.exams.single.room, 'B305');
    });

    test('a course the timetable and eClass spell differently is one exam, with its eClass course', () {
      final m = matchExams(
          midterm(),
          studentCourses([lesson('Object Oriented Programming 1')], [
            const CourseAttendance(course: Course(id: 7, name: 'Object-Oriented Programming 1', code: '')),
          ]),
          classGroup: 'CSE25-3');
      expect(m.exams.map(show), [startsWith('Fri 14:00 Object-Oriented Programming 1')]);
      expect(m.exams.single.course.eclass?.id, 7);
      expect(m.unlisted, isEmpty);
    });

    test('the UK programme\'s sittings go to UK groups only', () {
      expect(examsOf(['Operating System'], 'ICE24-1'), [startsWith('Wed 14:00 Operating System')]);
      expect(examsOf(['Operating System'], 'IT26-1'), [startsWith('Thu 17:00 (UK) Operating System')]);
      expect(examsOf(['Financial Management'], 'SBL(B)24-1'), [startsWith('Mon 13:00 Financial Management')]);
      expect(examsOf(['Financial Management'], 'BM25-1'), ['Fri 15:30 (UK) Financial Management (25-01) A605']);
      // No class group known: never a UK sitting.
      expect(examsOf(['Operating System'], ''), [startsWith('Wed 14:00')]);
    });

    test('a group, school, department or teacher picks one sitting', () {
      expect(examsOf(['Introduction to Data Science'], 'AI25-1'), ['Mon 16:30 (UK) Intro to Data Science (AI 25-01) B102']);
      expect(examsOf(['Introduction to Data Science'], 'DS25-1'), ['Mon 16:30 (UK) Intro to Data Science (DS 25-01) B103']);
      expect(examsOf(['Introduction to Economics'], 'CIE26-4'), [startsWith('Mon 16:30 Introduction to Economics (SOCIE)')]);
      expect(examsOf(['Introduction to Economics'], 'SBL(L)26-2'), [startsWith('Mon 09:30 Introduction to Economics- (SBL)')]);
      expect(examsOf(['Basic Korean 1-Uzb'], 'CIE26-3'), [startsWith('Tue 09:30 Basic Korean 1 (SOCIE)')]);
      expect(examsOf(['Circuit and Lab'], 'ICE25-2'), ['Thu 14:00 Circuit and Lab (ICE) B202 B209 B210']);
      expect(examsOf(['Circuit and Lab'], 'CSE25-7'), [startsWith('Thu 14:00 Circuit and Lab (CSE)')]);
      expect(examsOf(['Technical English'], 'CS25-1'), ['Thu 15:30 (UK) Tech English 2 (CS 25-1) B103']);
      expect(examsOf(['Mathematics II'], 'DS25-1'), ['Fri 15:30 (UK) Math 2 (DS 25-1) A203']);
      expect(examsOf(['CS Policies and Governance'], 'CS25-1'), [startsWith('Wed 14:00 (UK)CS Policy and Governance')]);
      expect(examsOf(['Programming Concepts and Application Development'], 'IT26-4'),
          ['Mon 14:30 (UK) PCAD (IT 26-2/26-4) A605 A606']);
      expect(examsOf(['Mathematics'], 'IT26-6'), isEmpty); // "Math for IT" is a different name

      final m = matchExams(midterm(), [StudentCourse('Database', teachers: {'A.Agostini'})], classGroup: 'CSE24-1');
      expect(m.exams.map(show), ['Thu 12:30 Database (Dr.Agostini) B201 B202 B209 B210']);
    });

    test('sittings nothing tells apart are all kept, and say so', () {
      final m = matchExams(midterm(), [const StudentCourse('Database', teachers: {'K.Kim'})], classGroup: 'CSE24-1');
      expect(m.exams.map((e) => e.exam.cell), ['Database (Dr.Sarvar)', 'Database (Dr.Agostini)']);
      expect(m.exams.every((e) => e.sittings == 2), isTrue);
    });

    test('a prefix match is used only when it points at one course', () {
      // "Business English" starts three different courses on the sheet.
      expect(examsOf(['Business English'], 'SBL(B)25-1'), isEmpty);
      expect(examsOf(['Introduction to IT (Foundation)'], 'FND26-1'), [startsWith('Thu 11:00 Introduction to IT')]);
      expect(examsOf(['Database Management'], 'SBL(L)24-1'), [startsWith('Thu 11:00 Database Management')]);
    });
  });
}
