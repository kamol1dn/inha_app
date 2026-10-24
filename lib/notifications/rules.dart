/// Which notifications the current data calls for.
///
/// Pure logic: no plugins, no I/O and no clock. Everything comes in as
/// arguments, so it can be tested with a fixed `now`. The notifier shows the
/// items whose [PlannedNotification.when] is now and schedules the rest.
///
/// Late reminders: when a reminder's time has already passed but the thing
/// it is about has not (the app was off, or the item just appeared), the
/// most urgent of the missed reminders is sent now. Older missed reminders
/// are dropped, so a VOD found 5 hours before it closes gets one "6 h"
/// reminder, not a "48 h" one as well.
library;

import 'package:intl/intl.dart';

import '../models/models.dart';

// ---------------------------------------------------------------------------
// Thresholds
// ---------------------------------------------------------------------------

/// Reminders before a VOD watch window closes. Watching it in the window is
/// what counts for attendance, so this is the one that must not be missed.
const vodReminderLeads = [Duration(hours: 48), Duration(hours: 6)];

/// Reminders before an assignment or quiz deadline.
const deadlineReminderLeads = [Duration(hours: 24), Duration(hours: 3)];

/// Deadline kinds, other than VOD, that get [deadlineReminderLeads].
const remindedDeadlineKinds = {
  DeadlineKind.assignment,
  DeadlineKind.quiz,
  DeadlineKind.other,
};

/// How long before a class starts its reminder fires.
const classReminderLead = Duration(minutes: 15);

/// A late reminder is skipped when the next reminder for the same item is
/// due within this long anyway, so the two do not arrive back to back.
const lateReminderSkipWithin = Duration(hours: 1);

/// Absences dated longer ago than this are not announced. This keeps a first
/// run from announcing a whole semester of old marks. It has to cover the
/// time eClass takes to mark a VOD week absent: the ~9-day watch window plus
/// some delay.
const absenceLookback = Duration(days: 21);

/// How long the notifier keeps a sent key. Must be longer than
/// [absenceLookback], or an old absence could be announced twice.
const sentKeyRetention = Duration(days: 60);

/// Quiet hours (DESIGN.md 11): 23:00 to 07:30, device time.
const defaultQuietHours = QuietHours(startMinute: 23 * 60, endMinute: 7 * 60 + 30);

/// A reminder that falls in quiet hours waits for the morning only if the
/// item is still open at least this long after the quiet hours end.
const quietMorningMargin = Duration(hours: 1);

/// Otherwise it goes out this long before the quiet hours start (22:00).
const quietEveningLead = Duration(hours: 1);

// ---------------------------------------------------------------------------
// Keys
// ---------------------------------------------------------------------------

/// Keys start with one of these, so callers can tell which data a key came
/// from (the notifier only cancels pending reminders whose source it has
/// fresh data for).
const vodKeyPrefix = 'vod:';
const dueKeyPrefix = 'due:';
const absenceKeyPrefix = 'absent:';
const classKeyPrefix = 'class:';
const allKeyPrefixes = {vodKeyPrefix, dueKeyPrefix, absenceKeyPrefix, classKeyPrefix};

// ---------------------------------------------------------------------------
// Types
// ---------------------------------------------------------------------------

/// The Android notification channel a notification goes to, each with its
/// own switch in Settings. Off by default: [classes] (DESIGN.md 11).
enum NotifyChannel { deadlines, vod, attendance, classes }

/// The nightly quiet hours, as minutes after midnight in device time. The
/// window may cross midnight (start after end).
class QuietHours {
  final int startMinute;
  final int endMinute;
  const QuietHours({required this.startMinute, required this.endMinute});

  int _minute(DateTime t) => t.hour * 60 + t.minute;

  bool contains(DateTime t) {
    final m = _minute(t.toLocal());
    return startMinute <= endMinute
        ? m >= startMinute && m < endMinute
        : m >= startMinute || m < endMinute;
  }

  /// When the quiet hours containing [t] end.
  DateTime endOf(DateTime t) {
    final l = t.toLocal();
    var end = DateTime(l.year, l.month, l.day, endMinute ~/ 60, endMinute % 60);
    if (!end.isAfter(l)) end = DateTime(l.year, l.month, l.day + 1, endMinute ~/ 60, endMinute % 60);
    return end;
  }

  /// When the quiet hours containing [t] began.
  DateTime startOf(DateTime t) {
    final l = t.toLocal();
    var start = DateTime(l.year, l.month, l.day, startMinute ~/ 60, startMinute % 60);
    if (start.isAfter(l)) start = DateTime(l.year, l.month, l.day - 1, startMinute ~/ 60, startMinute % 60);
    return start;
  }
}

/// One notification to show now or schedule for later.
class PlannedNotification {
  /// Stable and unique: the same reminder always gets the same key, so the
  /// notifier can tell what it already sent.
  final String key;
  final String title;
  final String body;

  /// When to show it. Equal to `now` for notifications that are due already.
  final DateTime when;
  final NotifyChannel channel;

  /// Post without sound or vibration: it is due during quiet hours and could
  /// neither wait for the morning nor go out before them.
  final bool quiet;

  const PlannedNotification({
    required this.key,
    required this.title,
    required this.body,
    required this.when,
    required this.channel,
    this.quiet = false,
  });

  @override
  bool operator ==(Object other) =>
      other is PlannedNotification &&
      other.key == key &&
      other.title == title &&
      other.body == body &&
      other.when == when &&
      other.channel == channel &&
      other.quiet == quiet;

  @override
  int get hashCode => Object.hash(key, title, body, when, channel, quiet);

  @override
  String toString() =>
      'PlannedNotification($key at $when, ${channel.name}${quiet ? ', quiet' : ''}: "$title" / "$body")';
}

// ---------------------------------------------------------------------------
// Rules
// ---------------------------------------------------------------------------

/// Everything that should be shown or scheduled given the data, minus the
/// keys in [sentKeys]. Sorted by [PlannedNotification.when], then key.
///
/// Nothing is ever placed before [now]: reminders that are due get `when ==
/// now`. Deadlines that have passed and lessons that have started are
/// dropped.
///
/// With [quietHours], a reminder that would go out inside them waits for
/// their end if the item is still open an hour after that, else goes out an
/// hour before they start (22:00), else (that time has passed) goes out
/// [PlannedNotification.quiet]. Every channel is planned whether or not the
/// student turned it off; the notifier filters.
List<PlannedNotification> planNotifications({
  required DateTime now,
  List<Deadline> deadlines = const [],
  List<CourseAttendance> attendance = const [],
  List<Lesson> lessons = const [],
  Set<String> sentKeys = const {},
  QuietHours? quietHours,
  Map<int, int> absenceLimits = const {},
  Set<DateTime> classFree = const {},
}) {
  final out = <String, PlannedNotification>{};
  void add(PlannedNotification n) => out.putIfAbsent(n.key, () => n);

  for (final d in deadlines) {
    if (d.kind == DeadlineKind.vod) {
      _quiet(_vodReminders(now, d, attendance), d.end, now, quietHours).forEach(add);
    } else if (remindedDeadlineKinds.contains(d.kind)) {
      _quiet(_deadlineReminders(now, d), d.end, now, quietHours).forEach(add);
    }
  }
  for (final course in attendance) {
    for (final n in _absences(now, course, absenceLimits[course.course.id])) {
      // Nothing closes: an absence can always wait for the morning.
      _quiet([n], DateTime(9999), now, quietHours).forEach(add);
    }
  }
  // No classes in an exam week, whatever the timetable says.
  final today = now.toLocal();
  final classesToday = !classFree.contains(DateTime(today.year, today.month, today.day));
  for (final lesson in classesToday ? lessons : const <Lesson>[]) {
    final n = _classReminder(now, lesson);
    if (n == null) continue;
    _quiet([n], n.when.add(classReminderLead), now, quietHours).forEach(add);
  }

  final list = out.values.where((n) => !sentKeys.contains(n.key)).toList()
    ..sort((a, b) {
      final byTime = a.when.compareTo(b.when);
      return byTime != 0 ? byTime : a.key.compareTo(b.key);
    });
  return list;
}

Iterable<PlannedNotification> _vodReminders(
  DateTime now,
  Deadline d,
  List<CourseAttendance> attendance,
) sync* {
  final progress = _findVod(d, attendance);
  if (progress.isNotEmpty && progress.every((p) => p.done)) return;

  final course = _courseName(d.courseName);
  final closes = _dayTime.format(d.end.toLocal());
  final status = _vodStatus(progress);
  for (final (lead, at) in _reminderTimes(
    now: now,
    end: d.end,
    leads: vodReminderLeads,
    notBefore: d.start, // nothing to watch before the window opens
  )) {
    yield PlannedNotification(
      key: '${reminderStem(d)}|${_leadTag(lead)}',
      title: '$course: ${_clean(d.title)}',
      body: '$status, closes $closes.',
      when: at,
      channel: NotifyChannel.vod,
    );
  }
}

/// The progress rows for a VOD deadline, matched on course name and title
/// with whitespace and case ignored. Empty when there is no progress data,
/// which counts as unwatched. More than one row only if titles repeat in a
/// course; then it counts as watched only if all of them are.
List<VodProgress> _findVod(Deadline d, List<CourseAttendance> attendance) {
  final course = _norm(_courseName(d.courseName));
  final title = _norm(d.title);
  return [
    for (final a in attendance)
      if (_norm(a.course.name) == course)
        for (final v in a.vods)
          if (_norm(v.title) == title) v,
  ];
}

String _vodStatus(List<VodProgress> progress) {
  if (progress.isEmpty) return 'Not watched yet';
  // Least-watched match, so a repeated title never hides an unwatched one.
  final p = progress.reduce((a, b) => a.percent <= b.percent ? a : b);
  final pct = p.percent.clamp(0, 100).floor();
  if (pct == 0) {
    return p.length > Duration.zero
        ? 'Not watched yet (${_length(p.length)})'
        : 'Not watched yet';
  }
  final left = p.length * ((100 - p.percent.clamp(0, 100)) / 100);
  return left >= const Duration(minutes: 1)
      ? '$pct% watched (${_length(left)} left)'
      : '$pct% watched';
}

Iterable<PlannedNotification> _deadlineReminders(DateTime now, Deadline d) sync* {
  if (d.done) return; // handed in: nothing to remind about (pending ones are cancelled)
  final course = _courseName(d.courseName);
  final due = _dayTime.format(d.end.toLocal());
  final body = switch (d.kind) {
    DeadlineKind.assignment => 'Assignment due $due.',
    DeadlineKind.quiz => 'Quiz closes $due.',
    _ => 'Due $due.',
  };
  for (final (lead, at) in _reminderTimes(now: now, end: d.end, leads: deadlineReminderLeads)) {
    yield PlannedNotification(
      key: '${reminderStem(d)}|${_leadTag(lead)}',
      title: '$course: ${_clean(d.title)}',
      body: body,
      when: at,
      channel: NotifyChannel.deadlines,
    );
  }
}

Iterable<PlannedNotification> _absences(DateTime now, CourseAttendance a, int? limit) sync* {
  final since = now.subtract(absenceLookback);
  final total = a.count(AttendanceMark.absent);
  final course = _clean(a.course.name);
  final tally = switch (limit) {
    null => '${total == 1 ? '1 absence' : '$total absences'} in this course so far.',
    final l when total > l => '$total absences, over the limit of $l.',
    final l when total == l => '$total of $l allowed absences used, none left.',
    final l => '$total of $l allowed absences used, ${l - total} left.',
  };
  for (final e in a.classes) {
    if (e.mark != AttendanceMark.absent || e.date.isBefore(since)) continue;
    final date = e.date.toLocal();
    final label = _clean(e.label);
    final what = label.isEmpty ? 'the class' : label;
    yield PlannedNotification(
      key: '$absenceKeyPrefix${a.course.id}|${_day(date)}|${_norm(label)}',
      title: 'Marked absent: $course, ${_dayMonth.format(date)}',
      body: 'eClass recorded an absence for $what on ${_weekdayDayMonth.format(date)}. $tally',
      when: now,
      channel: NotifyChannel.attendance,
    );
  }
}

PlannedNotification? _classReminder(DateTime now, Lesson l) {
  final today = now.toLocal();
  if (l.weekday != today.weekday) return null;
  final hm = _parseHm(l.start);
  if (hm == null) return null;
  final start = DateTime(today.year, today.month, today.day, hm.$1, hm.$2);
  final times = _reminderTimes(now: now, end: start, leads: const [classReminderLead]);
  if (times.isEmpty) return null; // already started
  final subject = _clean(l.subject);
  final room = _clean(l.room);
  final startText = _hm.format(start);
  return PlannedNotification(
    key: '$classKeyPrefix${_day(start)}|$startText|${_norm(subject)}',
    title: subject,
    body: room.isEmpty
        ? 'Starts at $startText'
        : '${room.toLowerCase().startsWith('room') ? room : 'Room $room'} at $startText',
    when: times.single.$2,
    channel: NotifyChannel.classes,
  );
}

/// The part of a deadline's reminder keys that names the item, without the
/// lead: every reminder for [d] has the key `<stem>|<lead>`. Used to find the
/// item again when its notification is tapped.
String reminderStem(Deadline d) {
  final item = '${_norm(_courseName(d.courseName))}|${_norm(d.title)}|${_stamp(d.end)}';
  return d.kind == DeadlineKind.vod ? '$vodKeyPrefix$item' : '$dueKeyPrefix${d.kind.name}:$item';
}

/// The eClass course id in an absence key, or null for another key.
int? absenceCourseId(String key) => key.startsWith(absenceKeyPrefix)
    ? int.tryParse(key.substring(absenceKeyPrefix.length).split('|').first)
    : null;

/// Moves an item's reminders out of [quiet] hours (see [planNotifications]).
/// [end] is when the item closes. Reminders that end up at the same instant
/// collapse into the last one given, which is the most urgent.
Iterable<PlannedNotification> _quiet(
    Iterable<PlannedNotification> reminders, DateTime end, DateTime now, QuietHours? quiet) {
  if (quiet == null) return reminders;
  final byTime = <DateTime, PlannedNotification>{};
  for (final n in reminders) {
    var when = n.when;
    var silent = false;
    if (quiet.contains(when)) {
      final morning = quiet.endOf(when);
      final evening = quiet.startOf(when).subtract(quietEveningLead);
      if (end.isAfter(morning.add(quietMorningMargin))) {
        when = morning;
      } else if (evening.isAfter(now)) {
        when = evening;
      } else {
        silent = true;
      }
    }
    byTime[when] = PlannedNotification(
        key: n.key, title: n.title, body: n.body, when: when, channel: n.channel, quiet: silent);
  }
  return byTime.values;
}

/// When to send each reminder for something happening at [end], as
/// (lead, when) pairs. Empty once [end] has passed.
///
/// A reminder normally goes out at `end - lead`, moved to [notBefore] if
/// that is earlier. Reminders whose time has passed are late: only the most
/// urgent late one is kept, it goes out now, and it is skipped if the next
/// reminder is less than [lateReminderSkipWithin] away. Reminders landing on
/// the same instant collapse into the most urgent one.
List<(Duration, DateTime)> _reminderTimes({
  required DateTime now,
  required DateTime end,
  required List<Duration> leads,
  DateTime? notBefore,
}) {
  if (!end.isAfter(now)) return const [];
  final sorted = [...leads]..sort((a, b) => b.compareTo(a)); // earliest reminder first
  Duration? late;
  final upcoming = <(Duration, DateTime)>[];
  for (final lead in sorted) {
    var at = end.subtract(lead);
    if (notBefore != null && at.isBefore(notBefore)) at = notBefore;
    if (!at.isAfter(now)) {
      late = lead; // a later, shorter lead supersedes an earlier late one
    } else if (upcoming.isNotEmpty && upcoming.last.$2 == at) {
      upcoming[upcoming.length - 1] = (lead, at);
    } else {
      upcoming.add((lead, at));
    }
  }
  final skipLate = upcoming.isNotEmpty &&
      upcoming.first.$2.difference(now) < lateReminderSkipWithin;
  return [
    if (late != null && !skipLate) (late, now),
    ...upcoming,
  ];
}

// ---------------------------------------------------------------------------
// Formatting
// ---------------------------------------------------------------------------

final _dayTime = DateFormat('EEE d MMM, HH:mm', 'en_US'); // Sun 25 Oct, 23:59
final _weekdayDayMonth = DateFormat('EEE d MMM', 'en_US'); // Wed 21 Oct
final _dayMonth = DateFormat('d MMM', 'en_US'); // 21 Oct
final _hm = DateFormat('HH:mm', 'en_US'); // 10:30

final _spaces = RegExp(r'\s+');
String _clean(String s) => s.replaceAll(_spaces, ' ').trim();
String _norm(String s) => _clean(s).toLowerCase();

/// Course name without an eClass "[202602-SOC4020-001]" suffix, if one
/// slipped through.
String _courseName(String s) => _clean(Course.fromTitle(0, _clean(s)).name);

String _two(int n) => n.toString().padLeft(2, '0');

/// Minute-precision UTC stamp, so keys do not depend on the device zone.
String _stamp(DateTime d) {
  final u = d.toUtc();
  return '${u.year}${_two(u.month)}${_two(u.day)}T${_two(u.hour)}${_two(u.minute)}Z';
}

String _day(DateTime d) => '${d.year}-${_two(d.month)}-${_two(d.day)}';

String _leadTag(Duration d) => d.inMinutes % 60 == 0 ? '${d.inHours}h' : '${d.inMinutes}m';

String _length(Duration d) {
  final mins = (d.inSeconds / 60).round();
  final h = mins ~/ 60, m = mins % 60;
  if (h == 0) return '$m min';
  return m == 0 ? '$h h' : '$h h $m min';
}

(int, int)? _parseHm(String s) {
  final m = RegExp(r'^\s*(\d{1,2}):(\d{2})').firstMatch(s);
  if (m == null) return null;
  final h = int.parse(m.group(1)!), min = int.parse(m.group(2)!);
  if (h > 23 || min > 59) return null;
  return (h, min);
}
