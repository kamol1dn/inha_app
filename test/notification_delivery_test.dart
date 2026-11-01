import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:inha_app/data/exams.dart';
import 'package:inha_app/models/models.dart';
import 'package:inha_app/notifications/notifier.dart';
import 'package:inha_app/notifications/routes.dart';
import 'package:inha_app/notifications/rules.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'notification_settings_test.dart' show FakePlugin;

// How the notifier delivers what the rules plan: one notification per item,
// marks across a grades page opening, alarms that must not fire after all, and
// the app and the background task running at once.

const ai = Course(id: 2622, name: 'Artificial Intelligence', code: 'SOC4040');

final now = DateTime(2026, 10, 22, 12);

Deadline assignment(DateTime end, {bool done = false, bool dismissed = false}) => Deadline(
    title: 'Lab 5',
    courseName: 'Multimedia Computing',
    kind: DeadlineKind.assignment,
    end: end,
    done: done,
    dismissed: dismissed);

CourseGrades book(String mark) => CourseGrades(course: ai, source: GradeSource.gradebook, items: [
      GradeItem(key: 'm1', name: 'Quiz 1', mark: mark, grade: double.tryParse(mark), max: 100),
    ]);
CourseGrades lists(String mark) => CourseGrades(course: ai, source: GradeSource.activities, items: [
      GradeItem(key: 'm1', name: 'Quiz 1', mark: mark, grade: 37, max: 100),
    ]);

CourseAttendance absences(List<DateTime> days) => CourseAttendance(course: ai, classes: [
      for (final d in days) AttendanceEntry(date: d, label: '3Class', mark: AttendanceMark.absent),
    ]);

MyExam exam({String? room, List<String> rooms = const ['B209', 'B210'], DateTime? start, int sittings = 1}) {
  final at = start ?? DateTime(2026, 10, 29, 10);
  final e = Exam(
      slot: 'Th-3',
      start: at,
      end: at.add(const Duration(minutes: 90)),
      cell: 'Database',
      rooms: rooms,
      read: ExamCell.parse('Database'));
  return MyExam(const StudentCourse('Database'), e, room: room, sittings: sittings);
}

EclassNotification notice(int id, {bool read = false, DateTime? time}) =>
    EclassNotification(id: id, subject: 'Room changed', text: 'Now in B-305', time: time ?? now, read: read);

void main() {
  late FakePlugin plugin;
  late Notifier notifier;

  setUp(() {
    SharedPreferences.setMockInitialValues({});
    plugin = FakePlugin();
    notifier = Notifier(plugin: plugin, clock: () => now);
  });

  Notifier at(DateTime t) => Notifier(plugin: plugin, clock: () => t);

  group('one notification per item', () {
    final end = DateTime(2026, 10, 25, 23, 55);
    final lab = assignment(end);
    final stem = Notifier.idFor(reminderStem(lab));
    final threeHours = Notifier.idFor('${reminderStem(lab)}|3h');

    test('the next reminder has the item\'s id; the later one its own, so both alarms stand', () async {
      await notifier.sync(deadlines: [lab], now: now);
      expect(plugin.scheduled.keys, unorderedEquals([stem, threeHours]));
    });

    test('once the first has fired, the next pass moves the later one under the item\'s id', () async {
      await notifier.sync(deadlines: [lab], now: now);
      final after = end.subtract(const Duration(hours: 10));
      plugin.scheduled.clear();
      await at(after).sync(deadlines: [lab], now: after);
      expect(plugin.scheduled.keys, [stem]);
      expect(plugin.scheduled[stem]!.toUtc(), end.subtract(const Duration(hours: 3)).toUtc());
      expect(plugin.cancelled, contains(threeHours));
    });

    test('a reminder shown late replaces the one in the tray, and still carries its own key to open', () async {
      final late = end.subtract(const Duration(hours: 2));
      await at(late).sync(deadlines: [lab], now: late);
      final shown = plugin.shown.single;
      expect(shown.id, stem);
      expect(shown.payload, '${reminderStem(lab)}|3h');
    });

    test('a key of another kind keeps its own id', () {
      expect(reminderItem('grade:1|m1|>7'), 'grade:1|m1|>7');
      expect(reminderItem('absent:1|2026-10-22|3class'), 'absent:1|2026-10-22|3class');
      expect(reminderItem('${reminderStem(lab)}|24h'), reminderStem(lab));
    });

    test('handing the work in withdraws the reminder already in the tray, once', () async {
      final tray = end.subtract(const Duration(hours: 10));
      await at(tray).sync(deadlines: [lab], now: tray);
      expect(plugin.shown, hasLength(1));
      plugin.cancelled.clear();

      await at(tray).sync(deadlines: [assignment(end, done: true)], now: tray);
      expect(plugin.cancelled, contains(stem));
      expect(await at(tray).sentKeys(tray), isEmpty);

      plugin.cancelled.clear();
      await at(tray).sync(deadlines: [assignment(end, done: true)], now: tray);
      expect(plugin.cancelled, isEmpty);
    });

    test('marking it done here does the same, and plans nothing more', () async {
      final tray = end.subtract(const Duration(hours: 10));
      await at(tray).sync(deadlines: [lab], now: tray);
      plugin.cancelled.clear();
      final out = await at(tray).sync(deadlines: [assignment(end, dismissed: true)], now: tray);
      expect(out, isEmpty);
      expect(plugin.cancelled, contains(stem));
    });
  });

  group('marks across a grades page opening or closing', () {
    test('opening the page is no news, though the mark now reads differently', () async {
      await notifier.sync(courseGrades: [lists('37.00/100.00')], now: now);
      await notifier.sync(courseGrades: [book('37.00')], now: now);
      await notifier.sync(courseGrades: [book('37.00')], now: now);
      expect(plugin.shown, isEmpty);
    });

    test('nor is closing it again, and the next real change is announced', () async {
      await notifier.sync(courseGrades: [book('0.37')], now: now);
      await notifier.sync(courseGrades: [lists('37.00/100.00')], now: now);
      expect(plugin.shown, isEmpty);
      await notifier.sync(courseGrades: [lists('40.00/100.00')], now: now);
      expect(plugin.shown.map((s) => s.title), ['Grade changed: Quiz 1']);
    });

    test('an item never seen before is still news when the page opens', () async {
      await notifier.sync(courseGrades: [lists('37.00/100.00')], now: now);
      final opened = CourseGrades(course: ai, source: GradeSource.gradebook, items: [
        ...book('37.00').items,
        const GradeItem(key: 'g9', name: 'Project', mark: '20.00', grade: 20, max: 30),
      ]);
      await notifier.sync(courseGrades: [opened], now: now);
      expect(plugin.shown.map((s) => s.title), ['Graded: Project']);
    });

    test('marks seen before the source was recorded compare as they always did', () async {
      SharedPreferences.setMockInitialValues({Notifier.seenGradesKey: '{"${ai.id}":{"m1":"37.00"}}'});
      await notifier.sync(courseGrades: [book('37.00')], now: now);
      expect(plugin.shown, isEmpty);
      await notifier.sync(courseGrades: [book('40.00')], now: now);
      expect(plugin.shown, hasLength(1));
    });
  });

  group('alarms that must not fire after all', () {
    final night = DateTime(2026, 10, 22, 23, 30);
    final absent = absences([DateTime(2026, 10, 21)]);
    final more = absences([DateTime(2026, 10, 21), DateTime(2026, 10, 22)]);
    final keyOf = 'absent:${ai.id}|2026-10-22|3class';

    test('turning Attendance off before the morning cancels the waiting one', () async {
      final n = at(night);
      await n.sync(attendance: [absent], now: night);
      await n.sync(attendance: [more], now: night);
      expect(plugin.scheduled.keys, [Notifier.idFor(keyOf)]);

      await n.saveSettings(const NotifySettings(channels: {NotifyChannel.deadlines}));
      await n.sync(attendance: [more], now: night);
      expect(plugin.cancelled, contains(Notifier.idFor(keyOf)));
    });

    test('a professor correcting the absence overnight cancels it too', () async {
      final n = at(night);
      await n.sync(attendance: [absent], now: night);
      await n.sync(attendance: [more], now: night);
      await n.sync(attendance: [absent], now: night);
      expect(plugin.cancelled, contains(Notifier.idFor(keyOf)));
      expect(await n.sentKeys(night), isNot(contains(keyOf)));
    });

    test('signing out of eClass cancels everything from it, even with notifications blocked', () async {
      final n = at(night);
      await n.sync(attendance: [absent], now: night);
      await n.sync(
        attendance: [more],
        courseGrades: [book('-')],
        deadlines: [assignment(DateTime(2026, 10, 25, 23, 55))],
        now: night,
      );
      plugin.android.enabled = false;
      plugin.cancelled.clear();
      await n.forgetEclass();
      expect(plugin.cancelled, contains(Notifier.idFor(keyOf)));
      expect(plugin.cancelled, contains(Notifier.idFor(reminderStem(assignment(DateTime(2026, 10, 25, 23, 55))))));
      final p = await SharedPreferences.getInstance();
      expect(jsonDecode(p.getString(Notifier.prefsKey)!), isEmpty);
    });

    test('signing out leaves class reminders alone', () async {
      final n = at(now);
      await n.saveSettings(const NotifySettings(channels: {NotifyChannel.classes}));
      final lesson = Lesson(weekday: now.weekday, start: '14:00', end: '15:30', subject: 'AI');
      await n.sync(lessons: [lesson], now: now);
      plugin.cancelled.clear();
      await n.forgetEclass();
      expect(plugin.cancelled, isEmpty);
    });
  });

  group('the app and the background task at once', () {
    test('a save keeps what the other pass wrote', () async {
      final p = await SharedPreferences.getInstance();
      final first = assignment(DateTime(2026, 10, 22, 13));
      final plan = planNotifications(now: now, deadlines: [first]);
      expect(plan, isNotEmpty);

      // The other isolate's pass records a key after this pass has started.
      final slow = _Interleaved(plugin, onShow: () async {
        final others = jsonDecode(p.getString(Notifier.prefsKey) ?? '{}') as Map<String, dynamic>;
        others['grade:1|m1|>7'] = [now.millisecondsSinceEpoch, 0];
        await p.setString(Notifier.prefsKey, jsonEncode(others));
      });
      await Notifier(plugin: slow, clock: () => now).deliver(plan, now: now);

      final saved = jsonDecode(p.getString(Notifier.prefsKey)!) as Map<String, dynamic>;
      expect(saved.keys, containsAll(['grade:1|m1|>7', plan.first.key]));
    });

    test('a pass removing a key does not bring back the rest of an older copy', () async {
      SharedPreferences.setMockInitialValues({
        Notifier.prefsKey: jsonEncode({'class:x': [now.millisecondsSinceEpoch, now.millisecondsSinceEpoch + 60000000]}),
      });
      await notifier.cancel('class:x', forget: true);
      expect(await notifier.sentKeys(now.add(const Duration(days: 2))), isEmpty);
    });

    test('marks: moving on keeps a course the other pass saw meanwhile', () async {
      final p = await SharedPreferences.getInstance();
      await p.setString(Notifier.seenGradesKey, jsonEncode({'${ai.id}': {'m1': '7.00'}}));
      await notifier.sync(courseGrades: [book('7.00')], now: now);
      final seen = jsonDecode(p.getString(Notifier.seenGradesKey)!) as Map<String, dynamic>;
      expect(seen['${ai.id}'], {'m1': '7.00'});
    });
  });

  group('exams', () {
    final before = DateTime(2026, 10, 27, 12);

    test('the evening before and an hour before, with the rooms until the student sets theirs', () {
      final out = planNotifications(now: before, exams: [exam()]);
      expect(out.map((n) => n.when), [DateTime(2026, 10, 28, 20), DateTime(2026, 10, 29, 9)]);
      expect(out.first.title, 'Exam: Database');
      expect(out.last.title, 'Exam at 10:00: Database');
      expect(out.first.body, 'Thu 29 Oct, 10:00 · Room not set: B209 or B210');
      expect(out.first.channel, NotifyChannel.exams);
      expect(out.map((n) => n.key.split('|').last), ['eve', '1h']);
      expect(out.every((n) => n.key.startsWith(examKeyPrefix)), isTrue);
    });

    test('the room is the one set, or the only one', () {
      expect(planNotifications(now: before, exams: [exam(room: 'B305')]).first.body, endsWith('· Room B305'));
      expect(planNotifications(now: before, exams: [exam(rooms: const ['B101'])]).first.body, endsWith('· Room B101'));
    });

    test('the same words and keys as the extension (extension/test/notify.test.ts)', () {
      final halls = planNotifications(now: before, exams: [exam(rooms: const ['B304(A)', 'B304(B)', 'B304(C)', 'B305'])]);
      expect(halls.first.body, 'Thu 29 Oct, 10:00 · Room not set: B304(A–C) or B305');
      expect(planNotifications(now: before, exams: [exam(rooms: const [])]).first.body, 'Thu 29 Oct, 10:00 · Room not set');
      expect(planNotifications(now: before, exams: [exam(rooms: const ['B1'], sittings: 2)]).first.body,
          'Thu 29 Oct, 10:00 · Room B1. The timetable lists 2 sittings; check which is yours.');
      expect(halls.first.key, matches(RegExp(r'^exam:th-3\|database\|\d{8}T\d{4}Z\|eve$')));
    });

    test('found after the evening: sent now; none once it has started', () {
      final morning = DateTime(2026, 10, 29, 7, 45);
      final out = planNotifications(now: morning, exams: [exam()]);
      expect(out.first.when, morning);
      expect(out.first.key, endsWith('|eve'));
      expect(planNotifications(now: DateTime(2026, 10, 29, 10), exams: [exam()]), isEmpty);
    });

    test('an hour before an early exam falls in quiet hours and comes the evening before', () {
      final early = exam(start: DateTime(2026, 10, 29, 8));
      final out = planNotifications(now: before, exams: [early], quietHours: defaultQuietHours);
      expect(out.map((n) => n.when), [DateTime(2026, 10, 28, 20), DateTime(2026, 10, 28, 22)]);
    });

    test('on by default, delivered, and an exam that drops out is cancelled', () async {
      expect(NotifySettings.defaultChannels, contains(NotifyChannel.exams));
      await at(before).sync(exams: [exam()], now: before);
      expect(plugin.scheduled, hasLength(2));
      plugin.cancelled.clear();
      await at(before).sync(exams: const [], now: before);
      expect(plugin.cancelled, isNotEmpty);
    });

    test('no exam data leaves what is scheduled alone', () async {
      await at(before).sync(exams: [exam()], now: before);
      plugin.cancelled.clear();
      await at(before).sync(now: before);
      expect(plugin.cancelled, isEmpty);
    });

    test('a tap opens Exams', () {
      final key = planNotifications(now: before, exams: [exam()]).first.key;
      expect(notificationTarget(key), isA<ExamsTarget>());
    });
  });

  group('the bell menu', () {
    test('what it holds at first is a baseline; what comes later is announced', () async {
      await notifier.sync(notices: [notice(1)], now: now);
      expect(plugin.shown, isEmpty);
      await notifier.sync(notices: [notice(2), notice(1)], now: now);
      expect(plugin.shown.map((s) => s.title), ['Room changed']);
      await notifier.sync(notices: [notice(2), notice(1)], now: now);
      expect(plugin.shown, hasLength(1));
    });

    test('an empty menu is a baseline too', () async {
      await notifier.sync(notices: const [], now: now);
      await notifier.sync(notices: [notice(1)], now: now);
      expect(plugin.shown, hasLength(1));
    });

    test('no data is not a baseline', () async {
      await notifier.sync(now: now);
      await notifier.sync(notices: [notice(1)], now: now);
      expect(plugin.shown, isEmpty);
    });

    test('channel off: recorded, so turning it on is no flood', () async {
      await notifier.sync(notices: const [], now: now);
      await notifier.saveSettings(const NotifySettings(channels: {NotifyChannel.deadlines}));
      await notifier.sync(notices: [notice(1)], now: now);
      await notifier.saveSettings(const NotifySettings(channels: NotifySettings.defaultChannels));
      await notifier.sync(notices: [notice(1)], now: now);
      expect(plugin.shown, isEmpty);
    });

    test('read and old items are not announced', () {
      expect(planNotifications(now: now, notices: [notice(1, read: true)]), isEmpty);
      expect(planNotifications(now: now, notices: [notice(1, time: now.subtract(const Duration(days: 30)))]), isEmpty);
    });

    test('a tap opens the list of them, with their text', () {
      final key = planNotifications(now: now, notices: [notice(1)]).single.key;
      expect(notificationTarget(key), isA<NoticesTarget>());
    });
  });
}

/// Runs [onShow] in the middle of a pass, as the other isolate would.
class _Interleaved extends FakePlugin {
  _Interleaved(this.inner, {required this.onShow});
  final FakePlugin inner;
  final Future<void> Function() onShow;

  @override
  Future<void> show(
      {required int id, String? title, String? body, notificationDetails, String? payload}) async {
    await onShow();
    await super.show(id: id, title: title, body: body, notificationDetails: notificationDetails, payload: payload);
  }
}
