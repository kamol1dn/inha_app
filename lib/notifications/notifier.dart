/// Shows and schedules [PlannedNotification]s with flutter_local_notifications
/// and remembers which keys it already sent, so nothing goes out twice.
///
/// Works the same in the app and in the WorkManager background isolate.
/// Android only: on other platforms every call is a no-op.
library;

import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart' show PlatformException;
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:shared_preferences/shared_preferences.dart';
// zonedSchedule takes a TZDateTime; scheduling uses tz.UTC with absolute instants.
import 'package:timezone/timezone.dart' as tz;

import '../models/models.dart';
import 'rules.dart';

class Notifier {
  Notifier({
    FlutterLocalNotificationsPlugin? plugin,
    Future<SharedPreferences> Function()? prefs,
    this.icon = '@mipmap/ic_launcher',
    this.scheduleMode = AndroidScheduleMode.inexactAllowWhileIdle,
  })  : _plugin = plugin ?? FlutterLocalNotificationsPlugin(),
        _prefs = prefs ?? SharedPreferences.getInstance;

  final FlutterLocalNotificationsPlugin _plugin;
  final Future<SharedPreferences> Function() _prefs;

  /// Small icon resource. The launcher icon works but shows as a blob in the
  /// status bar; a white-on-transparent drawable is better (see
  /// docs/NOTIFICATIONS.md).
  final String icon;

  /// Inexact by default, so no exact-alarm permission is needed. Android may
  /// deliver an inexact alarm late: up to an hour on Android 12+, usually a
  /// few minutes. Re-scheduling on every [sync] narrows that window.
  final AndroidScheduleMode scheduleMode;

  /// shared_preferences key holding `{key: [recordedAtMs, fireAtMs]}`, where
  /// fireAtMs is 0 for notifications shown right away.
  static const prefsKey = 'notify.records.v1';

  /// shared_preferences key listing the eClass course ids whose attendance
  /// has been seen. A course's absences from before it was first seen are
  /// recorded without being announced.
  static const seenCoursesKey = 'notify.seenCourses.v1';

  /// shared_preferences key holding the absence limits the student set,
  /// `{"<course id>": <allowed absences>}`. Written by Settings (Prefs).
  static const absenceLimitsKey = 'absenceLimits.v1';

  static Map<int, int> readAbsenceLimits(SharedPreferences p) {
    final raw = p.getString(absenceLimitsKey);
    if (raw == null) return {};
    try {
      return {
        for (final e in (jsonDecode(raw) as Map<String, dynamic>).entries)
          if (int.tryParse(e.key) case final id?)
            if (e.value case final int limit) id: limit,
      };
    } catch (_) {
      return {};
    }
  }

  /// Items due within this long are shown now instead of scheduled; the
  /// plugin rejects schedule times that have passed by the time it runs.
  static const _showNowSlack = Duration(minutes: 1);

  static final channels = <NotifyChannel, AndroidNotificationChannel>{
    NotifyChannel.deadlines: AndroidNotificationChannel(
      'deadlines',
      'Deadlines',
      description: 'Assignments and quizzes, '
          '${_leads(deadlineReminderLeads)} before they are due',
      importance: Importance.high,
    ),
    NotifyChannel.vod: AndroidNotificationChannel(
      'vod',
      'VOD windows',
      description: 'Lecture videos still to watch, ${_leads(vodReminderLeads)} before the window closes',
      importance: Importance.high,
    ),
    NotifyChannel.attendance: AndroidNotificationChannel(
      'attendance',
      'Attendance',
      description: 'A new absence in eClass',
      importance: Importance.high,
    ),
    NotifyChannel.classes: AndroidNotificationChannel(
      'classes',
      'Classes',
      description: 'Your next class, ${_leads(const [classReminderLead])} before it starts',
      importance: Importance.defaultImportance,
    ),
  };

  /// Stable notification id for a key: 31-bit FNV-1a of its UTF-8 bytes.
  static int idFor(String key) {
    var h = 0x811c9dc5;
    for (final b in utf8.encode(key)) {
      h = ((h ^ b) * 0x01000193) & 0xffffffff;
    }
    return h & 0x7fffffff;
  }

  // -------------------------------------------------------------------------
  // Setup
  // -------------------------------------------------------------------------

  static bool get _supported => !kIsWeb && defaultTargetPlatform == TargetPlatform.android;

  bool _ready = false;

  AndroidFlutterLocalNotificationsPlugin? get _android =>
      _plugin.resolvePlatformSpecificImplementation<AndroidFlutterLocalNotificationsPlugin>();

  /// Initialises the plugin and creates the channels. Safe to call more than
  /// once and from a background isolate. Returns false where notifications
  /// are not supported. [onTap] gets the tapped notification; its payload
  /// is the [PlannedNotification.key].
  Future<bool> init({DidReceiveNotificationResponseCallback? onTap}) async {
    if (!_supported) return false;
    if (_ready && onTap == null) return true;
    await _plugin.initialize(
      settings: InitializationSettings(android: AndroidInitializationSettings(icon)),
      onDidReceiveNotificationResponse: onTap,
    );
    final android = _android;
    for (final c in channels.values) {
      await android?.createNotificationChannel(c);
    }
    _ready = true;
    return true;
  }

  /// Asks for POST_NOTIFICATIONS on Android 13+ (a system prompt); on older
  /// versions just reports whether notifications are on. Needs a foreground
  /// activity, so call it from the UI (e.g. after onboarding), never from
  /// the background task.
  Future<bool> requestPermission() async {
    if (!await init()) return false;
    try {
      return await _android?.requestNotificationsPermission() ?? false;
    } on PlatformException catch (e) {
      debugPrint('notifications: permission request failed: ${e.code}');
      return false;
    }
  }

  /// Whether the app may post notifications at all.
  Future<bool> enabled() async {
    if (!await init()) return false;
    try {
      return await _android?.areNotificationsEnabled() ?? false;
    } on PlatformException {
      return false;
    }
  }

  /// The key of the notification whose tap launched the app, if one did.
  Future<String?> launchPayload() async {
    if (!await init()) return null;
    try {
      final details = await _plugin.getNotificationAppLaunchDetails();
      return details?.didNotificationLaunchApp == true ? details?.notificationResponse?.payload : null;
    } on PlatformException {
      return null;
    }
  }

  /// The student's choices in Settings. Read from shared_preferences on every
  /// pass, so the background isolate follows them too.
  Future<NotifySettings> settings() async => NotifySettings.read(await _load());

  Future<void> saveSettings(NotifySettings s) async => s.write(await _prefs());

  // -------------------------------------------------------------------------
  // Single notifications
  // -------------------------------------------------------------------------

  /// Shows [n] immediately. Does not record it; [deliver] does that.
  Future<void> show(PlannedNotification n) async {
    if (!await init()) return;
    await _plugin.show(
      id: idFor(n.key),
      title: n.title,
      body: n.body,
      notificationDetails: _details(n),
      payload: n.key,
    );
  }

  /// Schedules [n] for [PlannedNotification.when] (replacing any earlier
  /// schedule with the same key). Does not record it; [deliver] does that.
  Future<void> schedule(PlannedNotification n) async {
    if (!await init()) return;
    await _plugin.zonedSchedule(
      id: idFor(n.key),
      // An absolute instant, so UTC is exact whatever the device zone is,
      // and the time zone database never needs loading.
      scheduledDate: tz.TZDateTime.from(n.when, tz.UTC),
      notificationDetails: _details(n),
      androidScheduleMode: scheduleMode,
      title: n.title,
      body: n.body,
      payload: n.key,
    );
  }

  /// Removes the notification for [key], whether it is showing or still
  /// scheduled. With [forget], the key is also dropped from the sent list
  /// so the rules may plan it again.
  Future<void> cancel(String key, {bool forget = false}) async {
    if (!await init()) return;
    await _plugin.cancel(id: idFor(key));
    if (forget) {
      await _serial(() async {
        final prefs = await _load();
        final recs = _decode(prefs);
        if (recs.remove(key) != null) await _save(prefs, recs);
      });
    }
  }

  /// Removes every notification and forgets every sent key, e.g. on logout.
  Future<void> cancelAll() async {
    if (await init()) await _plugin.cancelAll();
    await _serial(() async {
      final prefs = await _load();
      await prefs.remove(prefsKey);
    });
  }

  // -------------------------------------------------------------------------
  // Batches
  // -------------------------------------------------------------------------

  /// Keys already sent: shown, or scheduled for a time that has passed.
  /// Keys scheduled for later are left out on purpose, so the rules plan
  /// them again and [deliver] refreshes (or cancels) them each time.
  Future<Set<String>> sentKeys([DateTime? now]) async {
    final at = (now ?? DateTime.now()).millisecondsSinceEpoch;
    final recs = _decode(await _load());
    return {
      for (final e in recs.entries)
        if (e.value.sentBy(at)) e.key,
    };
  }

  /// Runs the rules on fresh data and delivers the result. Pass null for a
  /// source with no data at all (fetch failed and nothing cached): its
  /// pending reminders are then left alone instead of cancelled. Returns
  /// what was delivered.
  ///
  /// Channels the student turned off are not delivered, and their pending
  /// reminders are cancelled. Absences are recorded without a notification
  /// when the Attendance channel is off, and for a course seen for the first
  /// time (a first install, a new semester): those are not news.
  Future<List<PlannedNotification>> sync({
    List<Deadline>? deadlines,
    List<CourseAttendance>? attendance,
    List<Lesson>? lessons,
    DateTime? now,
  }) async {
    final at = now ?? DateTime.now();
    final prefs = await _load();
    final settings = NotifySettings.read(prefs);
    final plan = planNotifications(
      now: at,
      deadlines: deadlines ?? const [],
      attendance: attendance ?? const [],
      lessons: lessons ?? const [],
      sentKeys: await sentKeys(at),
      quietHours: settings.quietHours ? defaultQuietHours : null,
      absenceLimits: readAbsenceLimits(prefs),
    );

    final seen = {...?prefs.getStringList(seenCoursesKey)?.map(int.tryParse).whereType<int>()};
    final firstSeen = {
      for (final c in attendance ?? const <CourseAttendance>[])
        if (c.classes.isNotEmpty && !seen.contains(c.course.id)) c.course.id,
    };
    final attendanceOn = settings.channels.contains(NotifyChannel.attendance);
    bool silent(PlannedNotification n) {
      final course = absenceCourseId(n.key);
      return course != null && (!attendanceOn || firstSeen.contains(course));
    }

    final shown = [
      for (final n in plan)
        if (settings.channels.contains(n.channel) && !silent(n)) n,
    ];
    await deliver(
      shown,
      now: at,
      record: {for (final n in plan) if (silent(n)) n.key},
      cancelMissing: {
        if (deadlines != null) ...[vodKeyPrefix, dueKeyPrefix],
        if (lessons != null) classKeyPrefix,
      },
    );
    if (firstSeen.isNotEmpty) {
      await prefs.setStringList(seenCoursesKey, [for (final id in {...seen, ...firstSeen}) '$id']);
    }
    return shown;
  }

  /// Shows the items due now, schedules the rest and records every key.
  ///
  /// Reminders scheduled earlier that are still in the future but no longer
  /// in [plan] (VOD watched, deadline moved or removed) are cancelled, but
  /// only for keys starting with one of [cancelMissing], i.e. sources the
  /// plan was built from real data for.
  ///
  /// Does nothing while notifications are off, so nothing is marked sent
  /// that the user never saw; once allowed, the rules catch up. The keys in
  /// [record] are the exception: they are marked sent without being shown,
  /// whether or not notifications are allowed.
  Future<void> deliver(
    List<PlannedNotification> plan, {
    DateTime? now,
    Set<String> cancelMissing = const {},
    Set<String> record = const {},
  }) {
    return _serial(() async {
      final at = now ?? DateTime.now();
      final atMs = at.millisecondsSinceEpoch;
      final prefs = await _load();
      final recs = _decode(prefs);
      final unrecorded = record.where((k) => !(recs[k]?.sentBy(atMs) ?? false)).toList();
      for (final k in unrecorded) {
        recs[k] = _Record(atMs, 0);
      }
      if (unrecorded.isNotEmpty) await _save(prefs, recs);
      if (!await enabled()) return;

      final wanted = {for (final n in plan) n.key};
      final stale = [
        for (final e in recs.entries)
          if (!e.value.sentBy(atMs) &&
              !wanted.contains(e.key) &&
              cancelMissing.any(e.key.startsWith))
            e.key,
      ];
      for (final key in stale) {
        try {
          await _plugin.cancel(id: idFor(key));
          recs.remove(key);
        } catch (e) {
          debugPrint('notifications: cancel $key failed: $e');
        }
      }
      if (stale.isNotEmpty) await _save(prefs, recs);

      for (final n in plan) {
        // Re-checked here: another isolate may have sent it meanwhile.
        if (recs[n.key]?.sentBy(atMs) ?? false) continue;
        final clock = DateTime.now();
        final ref = at.isAfter(clock) ? at : clock;
        try {
          if (n.when.isAfter(ref.add(_showNowSlack))) {
            await schedule(n);
            recs[n.key] = _Record(recs[n.key]?.recordedAt ?? atMs, n.when.millisecondsSinceEpoch);
          } else {
            await show(n);
            recs[n.key] = _Record(atMs, 0);
          }
        } catch (e) {
          // Not recorded, so the next pass tries again.
          debugPrint('notifications: could not deliver ${n.key}: $e');
          continue;
        }
        await _save(prefs, recs); // after each, in case the isolate is killed
      }

      final cutoff = at.subtract(sentKeyRetention).millisecondsSinceEpoch;
      final before = recs.length;
      recs.removeWhere((_, r) => r.sentBy(atMs) && r.recordedAt < cutoff);
      if (recs.length != before) await _save(prefs, recs);
    });
  }

  // -------------------------------------------------------------------------
  // Internals
  // -------------------------------------------------------------------------

  NotificationDetails _details(PlannedNotification n) {
    final c = channels[n.channel]!;
    final urgent = c.importance.value >= Importance.high.value;
    return NotificationDetails(
      android: AndroidNotificationDetails(
        c.id,
        c.name,
        channelDescription: c.description,
        importance: c.importance,
        priority: urgent ? Priority.high : Priority.defaultPriority,
        category: n.channel == NotifyChannel.classes
            ? AndroidNotificationCategory.event
            : AndroidNotificationCategory.reminder,
        styleInformation: BigTextStyleInformation(n.body),
        silent: n.quiet,
      ),
    );
  }

  /// One pass at a time per isolate; the isolates themselves are kept apart
  /// by re-reading the store (prefs.reload) inside each pass.
  static Future<void> _queue = Future.value();
  static Future<T> _serial<T>(Future<T> Function() task) {
    final next = _queue.then((_) => task());
    _queue = next.then((_) {}, onError: (_) {});
    return next;
  }

  Future<SharedPreferences> _load() async {
    final prefs = await _prefs();
    await prefs.reload(); // the other isolate may have written since
    return prefs;
  }

  static Map<String, _Record> _decode(SharedPreferences prefs) {
    final raw = prefs.getString(prefsKey);
    if (raw == null) return {};
    try {
      final j = jsonDecode(raw) as Map<String, dynamic>;
      return {
        for (final e in j.entries)
          e.key: _Record((e.value as List)[0] as int, (e.value as List)[1] as int),
      };
    } catch (_) {
      return {}; // unreadable: start over rather than crash the pass
    }
  }

  static Future<void> _save(SharedPreferences prefs, Map<String, _Record> recs) =>
      prefs.setString(
        prefsKey,
        jsonEncode({for (final e in recs.entries) e.key: [e.value.recordedAt, e.value.fireAt]}),
      );

  static String _leads(List<Duration> leads) {
    String one(Duration d) => d.inMinutes % 60 == 0
        ? '${d.inHours} hour${d.inHours == 1 ? '' : 's'}'
        : '${d.inMinutes} minutes';
    final parts = leads.map(one).toList();
    return parts.length < 2
        ? parts.join()
        : '${parts.sublist(0, parts.length - 1).join(', ')} and ${parts.last}';
  }
}

/// Which channels the student wants and whether quiet hours apply, as set
/// in Settings. Defaults follow DESIGN.md 11: everything on except Classes.
class NotifySettings {
  final Set<NotifyChannel> channels;
  final bool quietHours;
  const NotifySettings({required this.channels, this.quietHours = true});

  static const defaultChannels = {NotifyChannel.deadlines, NotifyChannel.vod, NotifyChannel.attendance};

  static String _key(NotifyChannel c) => 'notify.on.${c.name}';
  static const _quietKey = 'notify.quietHours';

  factory NotifySettings.read(SharedPreferences p) => NotifySettings(
        channels: {
          for (final c in NotifyChannel.values)
            if (p.getBool(_key(c)) ?? defaultChannels.contains(c)) c,
        },
        quietHours: p.getBool(_quietKey) ?? true,
      );

  Future<void> write(SharedPreferences p) async {
    for (final c in NotifyChannel.values) {
      await p.setBool(_key(c), channels.contains(c));
    }
    await p.setBool(_quietKey, quietHours);
  }

  NotifySettings copyWith({Set<NotifyChannel>? channels, bool? quietHours}) =>
      NotifySettings(channels: channels ?? this.channels, quietHours: quietHours ?? this.quietHours);
}

class _Record {
  final int recordedAt; // ms since epoch
  final int fireAt; // ms since epoch; 0 = shown at once

  const _Record(this.recordedAt, this.fireAt);

  /// Shown, or scheduled for a time that has come.
  bool sentBy(int nowMs) => fireAt == 0 || fireAt <= nowMs;
}
