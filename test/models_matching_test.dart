import 'package:flutter_test/flutter_test.dart';
import 'package:inha_app/data/absence.dart';
import 'package:inha_app/data/urgency.dart';
import 'package:inha_app/models/models.dart';
import 'package:inha_app/notifications/rules.dart';
import 'package:inha_app/services/edupage/timetable_parser.dart';

CourseAttendance named(int id, String name, {List<VodProgress> vods = const []}) =>
    CourseAttendance(course: Course(id: id, name: name, code: ''), vods: vods);

VodProgress vod(String title, {double percent = 0, int? moduleId}) =>
    VodProgress(week: 1, title: title, length: const Duration(minutes: 10), percent: percent, moduleId: moduleId);

Deadline vodEvent(String title, String course, {int? moduleId, int? courseId, DateTime? end}) => Deadline(
      title: title,
      courseName: course,
      courseId: courseId,
      kind: DeadlineKind.vod,
      moduleId: moduleId,
      end: end ?? DateTime(2026, 10, 25, 23, 59),
    );

void main() {
  group('courseFor', () {
    final database = named(1, 'Database');
    final management = named(2, 'Database Management');
    final systems = named(3, 'Database Systems');

    test('an exact match wins wherever it is in the list', () {
      expect(courseFor('Database Management', [database, management]), same(management));
      expect(courseFor('database', [management, database]), same(database));
    });

    test('a cut-short name finds the one course it starts', () {
      expect(courseFor('Database Man', [management]), same(management));
      expect(courseFor('Database Man', [database, management]), isNull); // it also starts with "Database"
    });

    test('a longer name finds the longest course it starts with', () {
      expect(courseFor('Database Management Lab', [database, management]), same(management));
    });

    test('a name several courses start with is no match', () {
      expect(courseFor('Data', [management, systems]), isNull);
      expect(courseFor('Database', [management, systems]), isNull);
    });

    test('nothing to go on is no match', () {
      expect(courseFor('', [database]), isNull);
      expect(courseFor('Physics', [database]), isNull);
    });

    test('an event goes by its course id before its name', () {
      final d = vodEvent('x', 'Database', courseId: 2);
      expect(courseOfDeadline(d, [database, management]), same(management));
      expect(courseOfDeadline(vodEvent('x', 'Database'), [database, management]), same(database));
      expect(courseOfDeadline(vodEvent('x', 'Database', courseId: 9), [database]), same(database));
    });

    test('a course\'s deadlines are its own, not a similar one\'s', () {
      final d = Deadline(
          title: 'Lab',
          courseName: 'Database Management',
          kind: DeadlineKind.assignment,
          end: DateTime(2026, 10, 25));
      final att = [database, management];
      expect(courseDeadlines(database.course, [d], att, DateTime(2026, 10, 22)), isEmpty);
      expect(courseDeadlines(management.course, [d], att, DateTime(2026, 10, 22)), [d]);
    });
  });

  group('finding a VOD', () {
    final now = DateTime(2026, 10, 22, 9);

    test('by module id first, so a renamed row still counts', () {
      final att = [named(1, 'Multimedia', vods: [vod('Lecture 7 (new)', percent: 100, moduleId: 72441)])];
      final d = vodEvent('Lecture 7', 'Multimedia', moduleId: 72441);
      expect(vodFor(d, att)?.moduleId, 72441);
      expect(isDone(d, att), isTrue);
      expect(planNotifications(now: now, deadlines: [d], attendance: att), isEmpty);
    });

    test('by title for a cached row with no module id', () {
      final att = [named(1, 'Multimedia', vods: [vod('Lecture 7', percent: 100)])];
      final d = vodEvent('Lecture 7', 'Multimedia', moduleId: 72441);
      expect(vodFor(d, att), isNotNull);
      expect(planNotifications(now: now, deadlines: [d], attendance: att), isEmpty);
    });

    test('a cut-short course name: what the screens show as watched gets no reminder', () {
      final att = [named(1, 'Deep learning for computer vision', vods: [vod('Lecture 7', percent: 100)])];
      final d = vodEvent('Lecture 7', 'Deep learning for');
      expect(isDone(d, att), isTrue);
      expect(planNotifications(now: now, deadlines: [d], attendance: att), isEmpty);
    });

    test('a course name that points nowhere still counts as unwatched', () {
      final att = [named(1, 'Multimedia', vods: [vod('Lecture 7', percent: 100)])];
      expect(planNotifications(now: now, deadlines: [vodEvent('Lecture 7', 'Physics')], attendance: att), isNotEmpty);
    });

    test('finished items: handed in, watched or marked done', () {
      final att = [named(1, 'Multimedia', vods: [vod('Watched', percent: 100), vod('Half', percent: 50)])];
      final watched = vodEvent('Watched', 'Multimedia');
      final half = vodEvent('Half', 'Multimedia');
      final dismissed = vodEvent('Half', 'Multimedia', end: DateTime(2026, 11, 1)).withDismissed(true);
      expect(finishedItems([watched, half, dismissed], att), {reminderStem(watched), reminderStem(dismissed)});
    });
  });

  group('marked done by the student', () {
    final now = DateTime(2026, 10, 24, 9);
    final paper = Deadline(
        title: 'Paper lab', courseName: 'Multimedia', kind: DeadlineKind.assignment, end: DateTime(2026, 10, 25));

    test('counts as done everywhere, apart from eClass\'s own word', () {
      final d = paper.withDismissed(true);
      expect(d.done, isFalse);
      expect(isDone(d, const []), isTrue);
      expect(needsAttention([d], const [], now), isEmpty);
      expect(planNotifications(now: now, deadlines: [d]), isEmpty);
      final v = vodEvent('Lecture', 'Multimedia', end: DateTime(2026, 10, 25)).withDismissed(true);
      expect(needsAttention([v], const [], now), isEmpty);
      expect(planNotifications(now: now, deadlines: [v]), isEmpty);
    });

    test('survives a submission check and the cache', () {
      final d = paper.withDismissed(true).withDone(false, null);
      expect(d.dismissed, isTrue);
      expect(Deadline.fromJson(d.toJson()).dismissed, isTrue);
      final old = paper.toJson()..remove('dismissed');
      expect(Deadline.fromJson(old).dismissed, isFalse);
    });
  });

  group('cached times', () {
    test('instants are written with their zone and read back as the same moment, in device time', () {
      final d = Deadline(
        title: 'Lab',
        courseName: 'AI',
        kind: DeadlineKind.assignment,
        start: DateTime(2026, 10, 20, 9),
        end: DateTime(2026, 10, 25, 23, 55),
        done: true,
        doneAt: DateTime(2026, 10, 21, 21, 14),
      );
      final j = d.toJson();
      for (final f in ['start', 'end', 'doneAt']) {
        expect(j[f], endsWith('Z'));
      }
      final back = Deadline.fromJson(j);
      expect(back.end, d.end);
      expect(back.start, d.start);
      expect(back.doneAt, d.doneAt);
      expect(back.end.isUtc, isFalse);
      expect(reminderStem(back), reminderStem(d));

      final m = MailHeader(id: 'a', from: 'x', subject: 's', received: DateTime(2026, 10, 22, 9));
      expect(m.toJson()['received'], endsWith('Z'));
      expect(MailHeader.fromJson(m.toJson()).received, m.received);
    });

    test('an old cache with no zone keeps reading as local', () {
      final d = Deadline.fromJson(const {
        'title': 'Lab',
        'courseName': 'AI',
        'kind': 'assignment',
        'end': '2026-10-25T23:55:00.000',
      });
      expect(d.end, DateTime(2026, 10, 25, 23, 55));
      expect(d.courseId, isNull);
    });

    test('a class date stays a calendar date', () {
      final e = AttendanceEntry(date: DateTime(2026, 10, 21), label: '1Class', mark: AttendanceMark.present);
      expect(e.toJson()['date'], isNot(endsWith('Z')));
      expect(AttendanceEntry.fromJson(e.toJson()).date, DateTime(2026, 10, 21));
    });
  });

  group('classes held so far', () {
    final now = DateTime(2026, 10, 23, 9);
    AttendanceEntry on(int day, AttendanceMark mark) =>
        AttendanceEntry(date: DateTime(2026, 10, day), label: 'x', mark: mark);

    test('today\'s class counts once it is marked, not before', () {
      final c = CourseAttendance(
        course: const Course(id: 1, name: 'AI', code: ''),
        classes: [on(21, AttendanceMark.unmarked), on(23, AttendanceMark.unmarked), on(28, AttendanceMark.unmarked)],
      );
      expect(c.held(now).map((e) => e.date.day), [21]);
      final marked = CourseAttendance(course: c.course, classes: [on(21, AttendanceMark.present), on(23, AttendanceMark.absent)]);
      expect(marked.held(now).map((e) => e.date.day), [21, 23]);
    });
  });

  group('absence wording', () {
    test('"absences" after "N of M", whatever N is', () {
      expect(const AbsenceState(1, 2).line, '1 of 2 absences used');
      expect(const AbsenceState(0, 4).line, '0 of 4 absences used');
      expect(const AbsenceState(3, 4).line, '3 of 4 absences used');
    });

    test('over the limit, the noun follows the count', () {
      expect(const AbsenceState(1, 0).line, '1 absence · limit 0');
      expect(const AbsenceState(5, 4).line, '5 absences · limit 4');
    });

    test('no limit set', () {
      expect(const AbsenceState(1, null).line, '1 absence · limit not set');
      expect(const AbsenceState(2, null).line, '2 absences · limit not set');
    });
  });

  group('class group matching', () {
    final tables = <String, List<Map<String, dynamic>>>{
      'subjects': [],
      'teachers': [],
      'classrooms': [],
      'lessons': [],
      'periods': [],
      'classes': [
        {'id': '1', 'name': 'ICE23-1'},
        {'id': '2', 'name': 'SBL(L)26-6'},
      ],
      'cards': [],
    };

    test('a group typed with other case or spaces still finds its timetable', () {
      expect(lessonsFor(tables, 'ICE23-1'), isEmpty);
      expect(lessonsFor(tables, 'ice23-1'), isEmpty);
      expect(lessonsFor(tables, 'ICE 23-1'), isEmpty);
      expect(lessonsFor(tables, ' sbl(l) 26-6 '), isEmpty);
    });

    test('anything else is unknown, with the list of what there is', () {
      expect(
          () => lessonsFor(tables, 'ICE23-9'),
          throwsA(isA<UnknownClassGroup>()
              .having((e) => e.name, 'name', 'ICE23-9')
              .having((e) => e.available, 'available', ['ICE23-1', 'SBL(L)26-6'])));
    });
  });
}
