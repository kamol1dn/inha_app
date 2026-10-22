import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:inha_app/models/models.dart';
import 'package:inha_app/notifications/notifier.dart';
import 'package:inha_app/notifications/rules.dart';
import 'package:shared_preferences/shared_preferences.dart';

// Thursday 22 Oct 2026, 09:00 local time.
final now = DateTime(2026, 10, 22, 9, 0);

// Sunday 25 Oct 2026, 23:59: the VOD window closes.
final vodClose = DateTime(2026, 10, 25, 23, 59);

const mmc = Course(id: 2592, name: 'Multimedia Computing', code: 'SOC4020');
const ai = Course(id: 2635, name: 'Artificial Intelligence', code: 'ICE4012');

Deadline vod({
  String title = 'Week 8 Image compression',
  String course = 'Multimedia Computing',
  DateTime? start,
  DateTime? end,
}) =>
    Deadline(
      title: title,
      courseName: course,
      kind: DeadlineKind.vod,
      start: start ?? DateTime(2026, 10, 16),
      end: end ?? vodClose,
    );

Deadline due(DeadlineKind kind, DateTime end, {String title = 'Assignment 3', String course = 'Artificial Intelligence'}) =>
    Deadline(title: title, courseName: course, kind: kind, end: end);

CourseAttendance progress(Course c, List<VodProgress> vods, {List<AttendanceEntry> classes = const []}) =>
    CourseAttendance(course: c, vods: vods, classes: classes);

VodProgress watched(String title, double percent, {int week = 8, Duration length = const Duration(minutes: 60)}) =>
    VodProgress(week: week, title: title, length: length, percent: percent);

List<PlannedNotification> plan({
  DateTime? at,
  List<Deadline> deadlines = const [],
  List<CourseAttendance> attendance = const [],
  List<Lesson> lessons = const [],
  Set<String> sent = const {},
}) =>
    planNotifications(
      now: at ?? now,
      deadlines: deadlines,
      attendance: attendance,
      lessons: lessons,
      sentKeys: sent,
    );

void expectPlainCopy(Iterable<PlannedNotification> ns) {
  for (final n in ns) {
    for (final text in [n.title, n.body]) {
      expect(text, isNot(contains('!')), reason: 'no exclamation marks: $text');
      expect(text.runes.every((r) => r < 0x80), isTrue, reason: 'no emoji: $text');
      expect(text, isNot(contains('SOC4020')), reason: 'names, not codes: $text');
    }
  }
}

void main() {
  test('eClass class-period events ("...[001]-3교시") never produce a reminder', () {
    final period = due(DeadlineKind.classPeriod, now.add(const Duration(hours: 5)),
        title: 'Artificial Intelligence[001]-1교시');
    expect(plan(deadlines: [period]), isEmpty);
  });

  group('VOD window', () {
    test('unwatched VOD with no progress data: 48 h and 6 h before it closes', () {
      final out = plan(deadlines: [vod()]);

      expect(out.map((n) => n.when), [
        DateTime(2026, 10, 23, 23, 59),
        DateTime(2026, 10, 25, 17, 59),
      ]);
      for (final n in out) {
        expect(n.title, 'Multimedia Computing: Week 8 Image compression');
        expect(n.body, 'Not watched yet, closes Sun 25 Oct, 23:59.');
        expect(n.channel, NotifyChannel.attendance);
        expect(n.key, startsWith(vodKeyPrefix));
      }
      expect(out.map((n) => n.key).toSet(), hasLength(2));
      expectPlainCopy(out);
    });

    test('watched VOD produces nothing, matching ignores case and whitespace', () {
      final out = plan(
        deadlines: [vod(title: 'Week 8  Image\ncompression ', course: ' multimedia  computing')],
        attendance: [
          progress(mmc, [watched('week 8 image COMPRESSION', 100)]),
        ],
      );
      expect(out, isEmpty);
    });

    test('progress for another video does not count', () {
      final out = plan(
        deadlines: [vod()],
        attendance: [
          progress(mmc, [watched('Week 7 Huffman coding', 100, week: 7)]),
          progress(ai, [watched('Week 8 Image compression', 100)]), // other course
        ],
      );
      expect(out, hasLength(2));
      expect(out.first.body, startsWith('Not watched yet'));
    });

    test('partly watched VOD says how much is left', () {
      final out = plan(
        deadlines: [vod()],
        attendance: [progress(mmc, [watched('Week 8 Image compression', 45)])],
      );
      expect(out, hasLength(2));
      expect(out.first.body, '45% watched (33 min left), closes Sun 25 Oct, 23:59.');
    });

    test('a started-but-0% VOD gives its length', () {
      final out = plan(
        deadlines: [vod()],
        attendance: [
          progress(mmc, [watched('Week 8 Image compression', 0, length: const Duration(minutes: 72))]),
        ],
      );
      expect(out.first.body, 'Not watched yet (1 h 12 min), closes Sun 25 Oct, 23:59.');
    });

    test('a repeated title counts as watched only if every copy is', () {
      final out = plan(
        deadlines: [vod(title: 'Lecture')],
        attendance: [
          progress(mmc, [watched('Lecture', 100, week: 7), watched('Lecture', 10, week: 8)]),
        ],
      );
      expect(out, hasLength(2));
      expect(out.first.body, startsWith('10% watched'));
    });

    test('found 30 h before closing: the missed 48 h reminder goes now, 6 h one is scheduled', () {
      final at = vodClose.subtract(const Duration(hours: 30));
      final out = plan(at: at, deadlines: [vod()]);
      expect(out.map((n) => n.when), [at, DateTime(2026, 10, 25, 17, 59)]);
      expect(out.first.key, endsWith('|48h'));
      expect(out.last.key, endsWith('|6h'));
    });

    test('found 5 h before closing: only the 6 h reminder, sent now', () {
      final at = vodClose.subtract(const Duration(hours: 5));
      final out = plan(at: at, deadlines: [vod()]);
      expect(out, hasLength(1));
      expect(out.single.when, at);
      expect(out.single.key, endsWith('|6h'));
    });

    test('a missed reminder is skipped when the next one is under an hour away', () {
      final at = vodClose.subtract(const Duration(hours: 6, minutes: 30));
      final out = plan(at: at, deadlines: [vod()]);
      expect(out, hasLength(1));
      expect(out.single.key, endsWith('|6h'));
      expect(out.single.when, DateTime(2026, 10, 25, 17, 59));
    });

    test('nothing before the window opens; reminders that land on the opening collapse', () {
      final opens = vodClose.subtract(const Duration(hours: 5));
      final out = plan(deadlines: [vod(start: opens)]);
      expect(out, hasLength(1));
      expect(out.single.when, opens);
      expect(out.single.key, endsWith('|6h'));
    });

    test('a closed window produces nothing', () {
      expect(plan(at: vodClose, deadlines: [vod()]), isEmpty);
      expect(plan(at: vodClose.add(const Duration(minutes: 1)), deadlines: [vod()]), isEmpty);
    });

    test('an eClass code suffix on the course name is not shown', () {
      final out = plan(deadlines: [vod(course: 'Multimedia Computing[202602-SOC4020-001]')]);
      expect(out.first.title, 'Multimedia Computing: Week 8 Image compression');
      expectPlainCopy(out);
      // Same key as the plain name, so a later fix in the parser re-sends nothing.
      expect(out.map((n) => n.key), plan(deadlines: [vod()]).map((n) => n.key));
    });
  });

  group('assignments and quizzes', () {
    final saturday = DateTime(2026, 10, 24, 23, 59);

    test('24 h and 3 h before the deadline', () {
      final out = plan(deadlines: [due(DeadlineKind.assignment, saturday)]);
      expect(out.map((n) => n.when), [
        DateTime(2026, 10, 23, 23, 59),
        DateTime(2026, 10, 24, 20, 59),
      ]);
      for (final n in out) {
        expect(n.title, 'Artificial Intelligence: Assignment 3');
        expect(n.body, 'Assignment due Sat 24 Oct, 23:59.');
        expect(n.channel, NotifyChannel.deadlines);
      }
      expectPlainCopy(out);
    });

    test('quiz copy', () {
      final out = plan(deadlines: [due(DeadlineKind.quiz, saturday, title: 'Quiz 2')]);
      expect(out.first.title, 'Artificial Intelligence: Quiz 2');
      expect(out.first.body, 'Quiz closes Sat 24 Oct, 23:59.');
    });

    test('a passed deadline is dropped', () {
      expect(plan(deadlines: [due(DeadlineKind.assignment, now.subtract(const Duration(minutes: 1)))]), isEmpty);
      expect(plan(deadlines: [due(DeadlineKind.quiz, now)]), isEmpty);
    });

    test('due in 2 h: the 3 h reminder goes out now, the 24 h one is never sent', () {
      final out = plan(deadlines: [due(DeadlineKind.assignment, now.add(const Duration(hours: 2)))]);
      expect(out, hasLength(1));
      expect(out.single.when, now);
      expect(out.single.key, endsWith('|3h'));
    });

    test('nothing is ever placed before now', () {
      final out = plan(
        at: DateTime(2026, 10, 24, 22, 0),
        deadlines: [due(DeadlineKind.assignment, saturday), vod()],
        lessons: const [Lesson(weekday: DateTime.saturday, start: '22:10', end: '23:00', subject: 'Late lab')],
      );
      expect(out, isNotEmpty);
      for (final n in out) {
        expect(n.when.isBefore(DateTime(2026, 10, 24, 22, 0)), isFalse, reason: n.key);
      }
    });
  });

  group('dedupe by key', () {
    final input = (
      deadlines: [vod(), due(DeadlineKind.assignment, DateTime(2026, 10, 24, 23, 59))],
      attendance: [
        progress(mmc, const [], classes: [
          AttendanceEntry(date: DateTime(2026, 10, 21), label: '3Class', mark: AttendanceMark.absent),
        ]),
      ],
      lessons: const [Lesson(weekday: DateTime.thursday, start: '10:30', end: '12:00', subject: 'Multimedia Computing', room: 'B-203')],
    );

    List<PlannedNotification> run({DateTime? at, Set<String> sent = const {}}) => plan(
          at: at,
          deadlines: input.deadlines,
          attendance: input.attendance,
          lessons: input.lessons,
          sent: sent,
        );

    test('keys are unique', () {
      final out = run();
      expect(out, hasLength(2 + 2 + 1 + 1));
      expect(out.map((n) => n.key).toSet(), hasLength(out.length));
    });

    test('sent keys are never planned again', () {
      final first = run();
      expect(run(sent: {for (final n in first) n.key}), isEmpty);
    });

    test('keys are stable across runs', () {
      final a = run().where((n) => n.when.isAfter(now)).map((n) => n.key).toSet();
      final b = run(at: now.add(const Duration(minutes: 40))).map((n) => n.key).toSet();
      expect(b.containsAll(a.where((k) => !k.startsWith(classKeyPrefix))), isTrue);
      expect(run(), run()); // same input, same output
    });

    test('once the most urgent missed reminder is sent, older missed ones stay unsent', () {
      final at = vodClose.subtract(const Duration(hours: 5));
      final first = plan(at: at, deadlines: [vod()]);
      expect(first.single.key, endsWith('|6h'));
      expect(plan(at: at.add(const Duration(hours: 1)), deadlines: [vod()], sent: {first.single.key}), isEmpty);
    });

    test('the same deadline listed twice gives one set of reminders', () {
      expect(plan(deadlines: [vod(), vod()]), hasLength(2));
    });

    test('a moved deadline gets new keys', () {
      final before = plan(deadlines: [vod()]).map((n) => n.key).toSet();
      final after = plan(deadlines: [vod(end: vodClose.add(const Duration(days: 2)))]).map((n) => n.key).toSet();
      expect(before.intersection(after), isEmpty);
    });

    test('output is sorted by time', () {
      final out = run();
      for (var i = 1; i < out.length; i++) {
        expect(out[i - 1].when.isAfter(out[i].when), isFalse);
      }
    });
  });

  group('new absence', () {
    AttendanceEntry absent(DateTime d, [String label = '3Class']) =>
        AttendanceEntry(date: d, label: label, mark: AttendanceMark.absent);

    test('one notification, sent now', () {
      final out = plan(attendance: [
        progress(mmc, const [], classes: [
          AttendanceEntry(date: DateTime(2026, 10, 14), label: '2Class', mark: AttendanceMark.present),
          absent(DateTime(2026, 10, 21)),
        ]),
      ]);
      expect(out, hasLength(1));
      final n = out.single;
      expect(n.title, 'Marked absent: Multimedia Computing, 21 Oct');
      expect(n.body, 'eClass recorded an absence for 3Class on Wed 21 Oct. 1 absence in this course so far.');
      expect(n.when, now);
      expect(n.channel, NotifyChannel.attendance);
      expect(n.key, startsWith(absenceKeyPrefix));
      expectPlainCopy(out);
    });

    test('announced once', () {
      final input = [progress(mmc, const [], classes: [absent(DateTime(2026, 10, 21))])];
      final first = plan(attendance: input);
      expect(first, hasLength(1));
      expect(plan(at: now.add(const Duration(hours: 3)), attendance: input, sent: {first.single.key}), isEmpty);
    });

    test('each absence is its own notification, with the running count', () {
      final out = plan(attendance: [
        progress(mmc, const [], classes: [absent(DateTime(2026, 10, 14), '2Class'), absent(DateTime(2026, 10, 21))]),
      ]);
      expect(out, hasLength(2));
      expect(out.map((n) => n.key).toSet(), hasLength(2));
      expect(out.every((n) => n.body.endsWith('2 absences in this course so far.')), isTrue);
    });

    test('present, late, other and unmarked are not announced', () {
      final out = plan(attendance: [
        progress(mmc, const [], classes: [
          for (final m in [AttendanceMark.present, AttendanceMark.late, AttendanceMark.other, AttendanceMark.unmarked])
            AttendanceEntry(date: DateTime(2026, 10, 21), label: m.name, mark: m),
        ]),
      ]);
      expect(out, isEmpty);
    });

    test('absences older than the lookback are not announced', () {
      final old = now.subtract(absenceLookback).subtract(const Duration(days: 1));
      expect(plan(attendance: [progress(mmc, const [], classes: [absent(old)])]), isEmpty);
    });

    test('same date and label in two courses are two notifications', () {
      final out = plan(attendance: [
        progress(mmc, const [], classes: [absent(DateTime(2026, 10, 21))]),
        progress(ai, const [], classes: [absent(DateTime(2026, 10, 21))]),
      ]);
      expect(out.map((n) => n.key).toSet(), hasLength(2));
    });
  });

  group('next class', () {
    Lesson lesson(int weekday, String start, {String room = 'B-203', String subject = 'Multimedia Computing'}) =>
        Lesson(weekday: weekday, start: start, end: '23:00', subject: subject, room: room);

    test('15 min before a lesson today', () {
      final out = plan(lessons: [lesson(DateTime.thursday, '10:30')]);
      expect(out, hasLength(1));
      final n = out.single;
      expect(n.title, 'Multimedia Computing');
      expect(n.body, 'Room B-203 at 10:30');
      expect(n.when, DateTime(2026, 10, 22, 10, 15));
      expect(n.channel, NotifyChannel.classes);
      expect(n.key, startsWith(classKeyPrefix));
      expectPlainCopy(out);
    });

    test('only today', () {
      expect(
        plan(lessons: [
          lesson(DateTime.wednesday, '10:30'),
          lesson(DateTime.friday, '10:30'),
          lesson(DateTime.monday, '13:00'),
        ]),
        isEmpty,
      );
    });

    test('only lessons that have not started', () {
      expect(plan(lessons: [lesson(DateTime.thursday, '08:00')]), isEmpty);
      expect(plan(lessons: [lesson(DateTime.thursday, '09:00')]), isEmpty);
    });

    test('inside the 15 minutes but not started: sent now', () {
      final out = plan(lessons: [lesson(DateTime.thursday, '09:10')]);
      expect(out.single.when, now);
      expect(out.single.body, 'Room B-203 at 09:10');
    });

    test('several lessons today each get a reminder', () {
      final out = plan(lessons: [
        lesson(DateTime.thursday, '10:30'),
        lesson(DateTime.thursday, '13:00', subject: 'Artificial Intelligence', room: 'A-101'),
      ]);
      expect(out.map((n) => n.title), ['Multimedia Computing', 'Artificial Intelligence']);
    });

    test('the same lesson tomorrow gets a different key', () {
      final thu = plan(lessons: [lesson(DateTime.thursday, '10:30')]).single.key;
      final fri = plan(
        at: DateTime(2026, 10, 23, 9, 0),
        lessons: [lesson(DateTime.friday, '10:30')],
      ).single.key;
      expect(thu, isNot(fri));
    });

    test('no room, a room already called "Room", and a bad time', () {
      expect(plan(lessons: [lesson(DateTime.thursday, '13:00', room: '')]).single.body, 'Starts at 13:00');
      expect(plan(lessons: [lesson(DateTime.thursday, '13:00', room: 'Room A-101')]).single.body, 'Room A-101 at 13:00');
      expect(plan(lessons: [lesson(DateTime.thursday, 'TBA')]), isEmpty);
    });
  });

  group('notifier helpers', () {
    test('ids are stable 31-bit FNV-1a values', () {
      expect(Notifier.idFor(''), 0x011c9dc5);
      expect(Notifier.idFor('a'), 0x640c292c); // FNV-1a("a") = 0xe40c292c
      final keys = plan(deadlines: [vod(), due(DeadlineKind.quiz, DateTime(2026, 10, 24, 23, 59))]).map((n) => n.key);
      final ids = keys.map(Notifier.idFor).toList();
      expect(ids.toSet(), hasLength(ids.length));
      expect(ids.every((id) => id >= 0 && id <= 0x7fffffff), isTrue);
      expect(keys.map(Notifier.idFor).toList(), ids);
    });

    test('sentKeys: shown, or scheduled for a time that has come', () async {
      TestWidgetsFlutterBinding.ensureInitialized();
      final t = now.millisecondsSinceEpoch;
      const hour = 3600 * 1000;
      SharedPreferences.setMockInitialValues({
        Notifier.prefsKey: jsonEncode({
          'shown': [t - hour, 0],
          'fired': [t - 5 * hour, t - hour],
          'pending': [t - hour, t + hour],
        }),
      });
      expect(await Notifier().sentKeys(now), {'shown', 'fired'});
    });

    test('sentKeys survives an unreadable store', () async {
      TestWidgetsFlutterBinding.ensureInitialized();
      SharedPreferences.setMockInitialValues({Notifier.prefsKey: 'not json'});
      expect(await Notifier().sentKeys(now), isEmpty);
    });
  });
}
