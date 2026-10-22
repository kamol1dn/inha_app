import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:inha_app/models/models.dart';
import 'package:inha_app/notifications/notifier.dart';
import 'package:inha_app/notifications/routes.dart';
import 'package:inha_app/notifications/rules.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:timezone/timezone.dart';

const mmc = Course(id: 2615, name: 'Multimedia Computing', code: 'SOC4020');
const ai = Course(id: 2622, name: 'Artificial Intelligence', code: 'SOC4040');

AttendanceEntry absent(DateTime day, [String label = '3Class']) =>
    AttendanceEntry(date: day, label: label, mark: AttendanceMark.absent);
AttendanceEntry present(DateTime day) => AttendanceEntry(date: day, label: '1Class', mark: AttendanceMark.present);

Deadline assignment(DateTime end, {String title = 'Lab 5'}) =>
    Deadline(title: title, courseName: 'Multimedia Computing', kind: DeadlineKind.assignment, end: end);

Deadline vod(DateTime end, {DateTime? start}) => Deadline(
    title: 'Video 7', courseName: 'Multimedia Computing', kind: DeadlineKind.vod, start: start, end: end);

void main() {
  group('quiet hours', () {
    const q = defaultQuietHours;

    test('23:00 to 07:30, across midnight', () {
      expect(q.contains(DateTime(2026, 10, 23, 22, 59)), isFalse);
      expect(q.contains(DateTime(2026, 10, 23, 23, 0)), isTrue);
      expect(q.contains(DateTime(2026, 10, 24, 3, 0)), isTrue);
      expect(q.contains(DateTime(2026, 10, 24, 7, 29)), isTrue);
      expect(q.contains(DateTime(2026, 10, 24, 7, 30)), isFalse);
      expect(q.endOf(DateTime(2026, 10, 23, 23, 30)), DateTime(2026, 10, 24, 7, 30));
      expect(q.endOf(DateTime(2026, 10, 24, 2)), DateTime(2026, 10, 24, 7, 30));
      expect(q.startOf(DateTime(2026, 10, 24, 2)), DateTime(2026, 10, 23, 23));
      expect(q.startOf(DateTime(2026, 10, 23, 23, 30)), DateTime(2026, 10, 23, 23));
    });

    final now = DateTime(2026, 10, 22, 9); // Thursday morning

    test('a reminder due at night waits for 07:30 when the item is still open then', () {
      // A VOD window closing Sun 23:59: its 48 h reminder (Fri 23:59) waits until Sat 07:30.
      final out = planNotifications(now: now, deadlines: [vod(DateTime(2026, 10, 25, 23, 59))], quietHours: q);
      expect(out.map((n) => n.when), [DateTime(2026, 10, 24, 7, 30), DateTime(2026, 10, 25, 17, 59)]);
      expect(out.any((n) => n.quiet), isFalse);
    });

    test('a deadline before the morning gets its last reminder at 22:00 the evening before', () {
      // Due Sat 06:00: 24 h reminder Fri 06:00 -> Fri 07:30; 3 h reminder Sat 03:00 -> Fri 22:00.
      final out = planNotifications(now: now, deadlines: [assignment(DateTime(2026, 10, 24, 6))], quietHours: q);
      expect(out.map((n) => (n.when, n.key.split('|').last)), [
        (DateTime(2026, 10, 23, 7, 30), '24h'),
        (DateTime(2026, 10, 23, 22), '3h'),
      ]);
    });

    test('reminders landing on the same morning collapse into the most urgent one', () {
      // Due Fri 10:00, found Fri 02:00: the missed 24 h reminder (now) and the
      // 3 h one (07:00) both wait for 07:30, where only the 3 h one is kept.
      final out = planNotifications(
          now: DateTime(2026, 10, 23, 2), deadlines: [assignment(DateTime(2026, 10, 23, 10))], quietHours: q);
      expect(out.map((n) => (n.when, n.key.split('|').last)), [(DateTime(2026, 10, 23, 7, 30), '3h')]);
    });

    test('found in the night, closing before morning: sent now without sound', () {
      final out = planNotifications(
          now: DateTime(2026, 10, 23, 1), deadlines: [assignment(DateTime(2026, 10, 23, 3))], quietHours: q);
      expect(out.single.when, DateTime(2026, 10, 23, 1));
      expect(out.single.quiet, isTrue);
    });

    test('a new absence found at night is announced at 07:30', () {
      final night = DateTime(2026, 10, 23, 2);
      final out = planNotifications(
          now: night,
          attendance: [CourseAttendance(course: mmc, classes: [absent(DateTime(2026, 10, 22))])],
          quietHours: q);
      expect(out.single.when, DateTime(2026, 10, 23, 7, 30));
      expect(out.single.channel, NotifyChannel.attendance);
    });

    test('without quiet hours nothing moves', () {
      final out = planNotifications(now: now, deadlines: [vod(DateTime(2026, 10, 25, 23, 59))]);
      expect(out.first.when, DateTime(2026, 10, 23, 23, 59));
    });
  });

  group('keys and tap targets', () {
    final lab = assignment(DateTime(2026, 10, 25, 23, 55));
    final week7 = vod(DateTime(2026, 10, 25, 23, 59));
    final now = DateTime(2026, 10, 22, 9);

    test('every reminder key starts with its item stem', () {
      final out = planNotifications(now: now, deadlines: [lab, week7]);
      for (final n in out) {
        expect(n.key.startsWith('${reminderStem(lab)}|') || n.key.startsWith('${reminderStem(week7)}|'), isTrue);
      }
      expect(reminderStem(week7), startsWith(vodKeyPrefix));
      expect(reminderStem(lab), startsWith('${dueKeyPrefix}assignment:'));
    });

    test('a deadline reminder opens that deadline; a gone one opens Deadlines', () {
      final key = planNotifications(now: now, deadlines: [lab]).first.key;
      expect((notificationTarget(key, deadlines: [week7, lab]) as DeadlineTarget).deadline, same(lab));
      expect((notificationTarget(key, deadlines: [week7]) as TabTarget).tab, 2);
    });

    test('an absence opens its course; a class reminder opens Schedule on its day', () {
      final att = [CourseAttendance(course: mmc, classes: [absent(DateTime(2026, 10, 21))])];
      final key = planNotifications(now: now, attendance: att).single.key;
      expect(absenceCourseId(key), 2615);
      expect((notificationTarget(key, attendance: att) as CourseTarget).course.id, 2615);
      expect((notificationTarget(key) as TabTarget).tab, 3);

      final lesson = Lesson(weekday: DateTime.thursday, start: '14:00', end: '15:30', subject: 'AI', room: 'B101');
      final classKey = planNotifications(now: now, lessons: [lesson]).single.key;
      expect((notificationTarget(classKey) as ScheduleTarget).weekday, DateTime.thursday);
      expect(notificationTarget('something:else'), isNull);
    });
  });

  group('Notifier.sync', () {
    late FakePlugin plugin;
    late Notifier notifier;
    final now = DateTime(2026, 10, 22, 12);

    setUp(() {
      TestWidgetsFlutterBinding.ensureInitialized();
      SharedPreferences.setMockInitialValues({});
      plugin = FakePlugin();
      notifier = Notifier(plugin: plugin);
    });

    final semester = [
      CourseAttendance(course: mmc, classes: [
        present(DateTime(2026, 10, 7)),
        absent(DateTime(2026, 10, 14)),
        absent(DateTime(2026, 10, 16)),
        absent(DateTime(2026, 10, 21)),
      ]),
      CourseAttendance(course: ai, classes: [absent(DateTime(2026, 10, 19))]),
    ];

    test('first sync: existing absences are recorded, not announced; a later one is', () async {
      await notifier.sync(attendance: semester, now: now);
      expect(plugin.shown, isEmpty);
      expect(await notifier.sentKeys(now), hasLength(4));

      final later = [
        CourseAttendance(course: mmc, classes: [...semester[0].classes, absent(DateTime(2026, 10, 22))]),
        semester[1],
      ];
      await notifier.sync(attendance: later, now: now.add(const Duration(hours: 3)));
      expect(plugin.shown.map((s) => s.title), ['Marked absent: Multimedia Computing, 22 Oct']);
    });

    test('a course seen for the first time later (new semester) is not announced either', () async {
      await notifier.sync(attendance: [semester[0]], now: now);
      await notifier.sync(attendance: semester, now: now);
      expect(plugin.shown, isEmpty);
    });

    test('a course with no sessions yet is not "seen": its first absence is news', () async {
      await notifier.sync(attendance: [const CourseAttendance(course: ai)], now: now);
      await notifier.sync(attendance: [semester[1]], now: now);
      expect(plugin.shown, isEmpty); // the first sessions to appear are the baseline
      await notifier.sync(attendance: [
        CourseAttendance(course: ai, classes: [...semester[1].classes, absent(DateTime(2026, 10, 22))])
      ], now: now);
      expect(plugin.shown, hasLength(1));
    });

    test('before the permission is granted the baseline is still recorded', () async {
      plugin.android.enabled = false;
      await notifier.sync(attendance: semester, now: now);
      plugin.android.enabled = true;
      await notifier.sync(attendance: semester, now: now);
      expect(plugin.shown, isEmpty);
    });

    test('a channel turned off is not delivered and its scheduled reminders are cancelled', () async {
      final lab = assignment(DateTime(2026, 10, 25, 23, 55));
      await notifier.sync(deadlines: [lab], now: now);
      expect(plugin.scheduled, hasLength(2));

      final off = (await notifier.settings()).copyWith(
          channels: {...NotifySettings.defaultChannels}..remove(NotifyChannel.deadlines));
      await notifier.saveSettings(off);
      await notifier.sync(deadlines: [lab], now: now);
      expect(plugin.cancelled, unorderedEquals(plugin.scheduled.keys));
      expect(plugin.shown, isEmpty);
    });

    test('Attendance off: new absences are recorded, so turning it on later is no flood', () async {
      await notifier.sync(attendance: [semester[0]], now: now); // baseline
      await notifier.saveSettings(const NotifySettings(channels: {NotifyChannel.deadlines}));
      final later = [
        CourseAttendance(course: mmc, classes: [...semester[0].classes, absent(DateTime(2026, 10, 22))])
      ];
      await notifier.sync(attendance: later, now: now);
      await notifier.saveSettings(const NotifySettings(channels: NotifySettings.defaultChannels));
      await notifier.sync(attendance: later, now: now);
      expect(plugin.shown, isEmpty);
    });

    test('defaults follow DESIGN.md 11: everything but Classes, quiet hours on', () async {
      final s = await notifier.settings();
      expect(s.channels, {NotifyChannel.deadlines, NotifyChannel.vod, NotifyChannel.attendance});
      expect(s.quietHours, isTrue);
      final lesson = Lesson(weekday: now.weekday, start: '14:00', end: '15:30', subject: 'AI');
      await notifier.sync(lessons: [lesson], now: now);
      expect(plugin.scheduled, isEmpty);
    });

    test('a reminder due in quiet hours that cannot wait is posted silently', () async {
      final night = DateTime(2026, 10, 23, 1);
      await notifier.sync(deadlines: [assignment(DateTime(2026, 10, 23, 3))], now: night);
      final details = plugin.shown.single.details!.android!;
      expect(details.silent, isTrue);
      expect(details.channelId, 'deadlines');
    });
  });
}

typedef Shown = ({int id, String? title, NotificationDetails? details, String? payload});

/// flutter_local_notifications without the platform: records what the
/// notifier shows, schedules and cancels.
class FakePlugin implements FlutterLocalNotificationsPlugin {
  final android = FakeAndroid();
  final shown = <Shown>[];
  final scheduled = <int, TZDateTime>{};
  final cancelled = <int>[];

  @override
  T? resolvePlatformSpecificImplementation<T extends FlutterLocalNotificationsPlatform>() =>
      android is T ? android as T : null;

  @override
  Future<bool?> initialize({
    required InitializationSettings settings,
    DidReceiveNotificationResponseCallback? onDidReceiveNotificationResponse,
    DidReceiveBackgroundNotificationResponseCallback? onDidReceiveBackgroundNotificationResponse,
  }) async =>
      true;

  @override
  Future<void> show(
      {required int id, String? title, String? body, NotificationDetails? notificationDetails, String? payload}) async {
    shown.add((id: id, title: title, details: notificationDetails, payload: payload));
  }

  @override
  Future<void> zonedSchedule({
    required int id,
    required TZDateTime scheduledDate,
    required NotificationDetails notificationDetails,
    required AndroidScheduleMode androidScheduleMode,
    String? title,
    String? body,
    String? payload,
    DateTimeComponents? matchDateTimeComponents,
  }) async {
    scheduled[id] = scheduledDate;
  }

  @override
  Future<void> cancel({required int id, String? tag}) async => cancelled.add(id);

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class FakeAndroid implements AndroidFlutterLocalNotificationsPlugin {
  bool enabled = true;

  @override
  Future<bool?> areNotificationsEnabled() async => enabled;

  @override
  Future<void> createNotificationChannel(AndroidNotificationChannel notificationChannel) async {}

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}
