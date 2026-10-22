import 'dart:async';

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../data/app_data.dart';
import '../data/urgency.dart';
import '../models/models.dart';
import '../ui/format/format.dart';
import '../ui/theme/app_text.dart';
import '../ui/theme/status_colors.dart';
import 'common.dart';
import 'deadline_tile.dart';
import 'mail_screen.dart';

/// Answers "where do I need to be next, what's due, am I in trouble" (DESIGN.md 7).
class TodayScreen extends StatefulWidget {
  final void Function(int tab) onOpenTab;
  const TodayScreen({super.key, required this.onOpenTab});
  @override
  State<TodayScreen> createState() => _TodayScreenState();
}

class _TodayScreenState extends State<TodayScreen> {
  Timer? _tick;

  @override
  void initState() {
    super.initState();
    // The countdown ticks on the minute.
    _tick = Timer.periodic(const Duration(seconds: 30), (_) => setState(() {}));
  }

  @override
  void dispose() {
    _tick?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final data = context.watch<AppData>();
    final t = Theme.of(context);
    final now = DateTime.now();
    final nowMin = now.hour * 60 + now.minute;
    final lessons = data.lessons.data?.value ?? const <Lesson>[];
    final today = lessons.where((l) => l.weekday == now.weekday).toList();
    final current = today.where((l) => minutesOf(l.start) <= nowMin && minutesOf(l.end) > nowMin).firstOrNull;
    final upcoming = today.where((l) => minutesOf(l.start) > nowMin).toList();
    final cardLesson = current ?? upcoming.firstOrNull;
    final later = upcoming.where((l) => !identical(l, cardLesson)).toList();

    final att = data.attendance.data?.value ?? const <CourseAttendance>[];
    final deadlines = data.deadlines.data?.value ?? const <Deadline>[];
    final attention = needsAttention(deadlines, att, now);
    final unread = (data.inbox.data?.value ?? const <MailHeader>[]).where((m) => m.unread).toList();

    return RefreshIndicator(
      onRefresh: data.refreshAll,
      child: ListView(physics: const AlwaysScrollableScrollPhysics(), children: [
        const SizedBox(height: 8),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16),
          child: _NextClassCard(
            lesson: cardLesson,
            isNow: current != null,
            now: now,
            nextDay: cardLesson == null ? _nextClassDay(lessons, now) : null,
            loaded: data.lessons.data != null,
          ),
        ),
        SourceError(data.lessons, 'EduPage', onRetry: data.refreshTimetable),
        if (later.isNotEmpty) ...[
          SectionHeader('Later today', source: data.lessons, staleAfter: const Duration(hours: 24)),
          for (final l in later)
            ListTile(
              dense: true,
              minTileHeight: 48,
              leading: SizedBox(
                width: 48,
                child: Text(l.start, style: t.textTheme.bodyMedium?.tnum),
              ),
              title: Text(l.subject, maxLines: 1, overflow: TextOverflow.ellipsis, style: t.textTheme.titleMedium),
              trailing: Text(l.room, style: t.textTheme.bodyMedium?.tnum),
            ),
        ],
        SectionHeader('Needs attention', source: data.deadlines),
        SourceError(data.deadlines, 'eClass', onRetry: data.refreshEclass),
        for (final d in attention.take(5)) DeadlineTile(d, attendance: att, now: now),
        if (attention.length > 5)
          Align(
            alignment: Alignment.centerLeft,
            child: Padding(
              padding: const EdgeInsets.only(left: 8),
              child: TextButton(
                onPressed: () => widget.onOpenTab(2),
                child: Text('All ${deadlines.where((d) => d.end.isAfter(now)).length} deadlines'),
              ),
            ),
          ),
        // Never show an all-clear that a failed refresh can't back up.
        if (attention.isEmpty && data.deadlines.data != null && data.deadlines.error == null)
          _nothingDue(deadlines, now),
        _attendanceLine(context, data),
        if (unread.isNotEmpty) ...[
          const SectionHeader('Unread mail'),
          for (final m in unread.take(2))
            ListTile(
              minTileHeight: 72,
              title: Text(m.subject, maxLines: 1, overflow: TextOverflow.ellipsis, style: t.textTheme.titleMedium),
              subtitle: Text(m.from, maxLines: 1, overflow: TextOverflow.ellipsis),
              trailing: Text(pastWhen(m.received), style: t.textTheme.bodySmall?.tnum),
              onTap: () => Navigator.of(context).push(MaterialPageRoute(builder: (_) => const MailScreen())),
            ),
          if (unread.length > 2)
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16),
              child: Text('${unread.length - 2} more', style: t.textTheme.bodyMedium),
            ),
        ],
        _footer(context, data),
      ]),
    );
  }

  Widget _nothingDue(List<Deadline> all, DateTime now) {
    if (all.isEmpty) return const StatusLine(Status.ok, 'No deadlines in eClass.');
    final next = ([...all.where((d) => d.end.isAfter(now))]..sort((a, b) => a.end.compareTo(b.end))).firstOrNull;
    final tail = next == null ? '' : ' Next: ${next.title}, ${next.courseName}, ${dayDate(next.end)} ${clock(next.end)}.';
    return StatusLine(Status.ok, 'Nothing due in the next 3 days.$tail');
  }

  /// Absence limits aren't published anywhere we can read, so the guide's rule
  /// applies: show the real counts and never invent a limit.
  Widget _attendanceLine(BuildContext context, AppData data) {
    final att = data.attendance.data?.value;
    // One error row per failed service: the deadlines section already shows eClass's.
    if (data.attendance.error != null && data.deadlines.error != null) return const SizedBox.shrink();
    if (att == null) return SourceError(data.attendance, 'eClass', onRetry: data.refreshEclass);
    if (data.attendance.error != null) return SourceError(data.attendance, 'eClass', onRetry: data.refreshEclass);
    final withAbs = att.where((c) => c.count(AttendanceMark.absent) > 0).toList()
      ..sort((a, b) => b.count(AttendanceMark.absent).compareTo(a.count(AttendanceMark.absent)));
    final text = withAbs.isEmpty
        ? 'No absences recorded in ${att.length} courses.'
        : withAbs
            .map((c) => '${c.course.name}: ${c.count(AttendanceMark.absent)} '
                '${c.count(AttendanceMark.absent) == 1 ? 'absence' : 'absences'}')
            .join(' · ');
    return InkWell(
      onTap: () => widget.onOpenTab(3),
      child: Padding(
        padding: const EdgeInsets.only(top: 8),
        child: StatusLine(withAbs.isEmpty ? Status.ok : Status.info, text),
      ),
    );
  }

  Widget _footer(BuildContext context, AppData data) {
    final t = Theme.of(context);
    final times = [data.lessons, data.deadlines, data.attendance]
        .map((s) => s.data?.fetchedAt)
        .whereType<DateTime>()
        .toList()
      ..sort();
    final busy = data.lessons.loading || data.deadlines.loading || data.attendance.loading;
    final text = busy ? 'Updating…' : times.isEmpty ? '' : 'Updated ${updatedAt(times.first)}';
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 24, 16, 24),
      child: Text(text, style: t.textTheme.bodySmall?.tnum.copyWith(color: t.colorScheme.onSurfaceVariant)),
    );
  }

  static (DateTime, Lesson)? _nextClassDay(List<Lesson> lessons, DateTime now) {
    for (var i = 1; i <= 7; i++) {
      final day = DateTime(now.year, now.month, now.day).add(Duration(days: i));
      final first = (lessons.where((l) => l.weekday == day.weekday).toList()
            ..sort((a, b) => minutesOf(a.start).compareTo(minutesOf(b.start))))
          .firstOrNull;
      if (first != null) return (day, first);
    }
    return null;
  }
}

class _NextClassCard extends StatelessWidget {
  final Lesson? lesson;
  final bool isNow;
  final DateTime now;
  final (DateTime, Lesson)? nextDay;
  final bool loaded;
  const _NextClassCard(
      {required this.lesson, required this.isNow, required this.now, required this.nextDay, required this.loaded});

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context);
    final muted = t.textTheme.bodyMedium?.copyWith(color: t.colorScheme.onSurfaceVariant);
    final l = lesson;
    final List<Widget> children;
    if (!loaded) {
      children = [
        Container(height: 16, width: 120, color: t.colorScheme.surfaceContainerHighest),
        const SizedBox(height: 12),
        Container(height: 28, width: 200, color: t.colorScheme.surfaceContainerHighest),
      ];
    } else if (l == null) {
      final nd = nextDay;
      children = [
        Text(now.weekday > 5 ? 'No classes today' : 'No more classes today', style: t.textTheme.titleMedium),
        if (nd != null) ...[
          const SizedBox(height: 4),
          Text('${_dayWord(nd.$1)} ${nd.$2.start} · ${nd.$2.subject} · ${nd.$2.room}', style: muted?.tnum),
        ],
      ];
    } else {
      final start = _at(l.start), end = _at(l.end);
      final label = isNow ? 'Now · until ${l.end}' : 'Next  ${l.start}–${l.end}';
      final big = isNow ? '${duration(end.difference(now))} left' : relative(start, now: now);
      children = [
        Text(label, style: t.textTheme.labelLarge?.tnum.copyWith(color: t.colorScheme.primary)),
        const SizedBox(height: 4),
        Row(crossAxisAlignment: CrossAxisAlignment.baseline, textBaseline: TextBaseline.alphabetic, children: [
          Expanded(child: Text(l.room.isEmpty ? 'Room not set' : l.room, style: t.textTheme.headlineMedium)),
          Text(big, style: t.textTheme.headlineMedium),
        ]),
        const SizedBox(height: 4),
        Text(l.subject, style: t.textTheme.titleMedium),
        if (l.teacher.isNotEmpty) Text(l.teacher, style: muted),
      ];
    }
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: children),
      ),
    );
  }

  DateTime _at(String hhmm) {
    final m = minutesOf(hhmm);
    return DateTime(now.year, now.month, now.day, m ~/ 60, m % 60);
  }

  String _dayWord(DateTime d) => dayHeader(d, now: now) == 'Tomorrow' ? 'Tomorrow' : weekdayShort(d.weekday);
}
