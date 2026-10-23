import 'dart:async';

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../data/absence.dart';
import '../data/app_data.dart';
import '../data/rail.dart';
import '../data/urgency.dart';
import '../models/models.dart';
import '../ui/format/format.dart';
import '../ui/theme/app_text.dart';
import '../ui/theme/status_colors.dart';
import 'absence_widgets.dart';
import 'common.dart';
import 'details.dart';
import 'mail_screen.dart';
import 'rail_rows.dart';

/// Answers "where do I need to be next, what's due, am I in trouble" as one
/// rail from now into the next days (DESIGN.md 7).
class TodayScreen extends StatefulWidget {
  final void Function(int tab) onOpenTab;
  final void Function(int weekday) onOpenSchedule;
  const TodayScreen({super.key, required this.onOpenTab, required this.onOpenSchedule});
  @override
  State<TodayScreen> createState() => _TodayScreenState();
}

class _TodayScreenState extends State<TodayScreen> {
  Timer? _tick;

  @override
  void initState() {
    super.initState();
    // The countdown and the Now row tick on the minute.
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
    final now = DateTime.now();
    final lessons = data.lessons.data?.value ?? const <Lesson>[];
    final att = data.attendance.data?.value ?? const <CourseAttendance>[];
    final deadlines = data.deadlines.data?.value ?? const <Deadline>[];
    final limits = data.prefs.absenceLimits;
    final firstLoad = data.lessons.data == null && data.lessons.error == null;
    final rail = todayRail(
      lessons: lessons,
      deadlines: deadlines,
      attendance: att,
      limits: limits,
      now: now,
      timetableKnown: data.lessons.data != null,
    );

    return RefreshIndicator(
      onRefresh: data.refreshAll,
      child: ListView(physics: const AlwaysScrollableScrollPhysics(), children: [
        const OfflineRow(),
        SourceError(data.lessons, 'EduPage', onRetry: data.refreshTimetable),
        SourceError(data.deadlines, 'eClass', onRetry: data.refreshEclass),
        _staleLine(data),
        const SizedBox(height: 4),
        if (firstLoad) ...[NowRow(now, lineBelow: false), const SkeletonRows(count: 3)] else ..._rail(rail, att, now),
        if (!firstLoad) _dueSummary(deadlines, att, data, now),
        _attendance(context, data, lessons, now),
        ..._mail(context, data),
        _footer(context, data),
      ]),
    );
  }

  /// The rail has no header to carry a stale marker, so it gets a line.
  Widget _staleLine(AppData data) {
    final markers = [
      if (data.lessons.error == null && isStale(data.lessons, const Duration(hours: 24)))
        StaleMarker(data.lessons.data!.fetchedAt, what: 'Timetable'),
      if (data.deadlines.error == null && isStale(data.deadlines, const Duration(hours: 3)))
        StaleMarker(data.deadlines.data!.fetchedAt, what: 'eClass'),
    ];
    if (markers.isEmpty) return const SizedBox.shrink();
    return Padding(
      padding: const EdgeInsets.fromLTRB(gutter, 8, gutter, 0),
      child: Wrap(spacing: 16, runSpacing: 4, children: markers),
    );
  }

  List<Widget> _rail(List<RailEntry> rail, List<CourseAttendance> att, DateTime now) => [
        for (final (i, e) in rail.indexed)
          switch (e) {
            RailOverdue() => RailHeader('Overdue', status: Status.danger, lineAbove: i > 0, lineBelow: i < rail.length - 1),
            RailNow(:final at) => NowRow(at, lineAbove: i > 0, lineBelow: i < rail.length - 1),
            RailDay(:final day) => RailHeader(dayHeader(day, now: now), lineBelow: i < rail.length - 1),
            // The hero opens Schedule on its day; other classes open their course.
            RailClass(role: ClassRole.current || ClassRole.next) => HeroClass(e, now,
                onTap: () => widget.onOpenSchedule(e.day.weekday), lineAbove: i > 0, lineBelow: i < rail.length - 1),
            RailClass(:final lesson, :final trouble) =>
              ClassRow(lesson, trouble: trouble, lineAbove: i > 0, lineBelow: i < rail.length - 1),
            RailDue(:final deadline) =>
              DueRow(deadline, attendance: att, now: now, lineAbove: i > 0, lineBelow: i < rail.length - 1),
            RailNote(:final kind, :final at) => RailNoteRow(
                switch (kind) {
                  RailNoteKind.freeAfter => 'Free for the rest of the day',
                  RailNoteKind.noMoreClasses => 'No more classes today',
                  RailNoteKind.noClasses => 'No classes today',
                },
                at: at == null ? null : clock(at),
                lineAbove: i > 0,
                lineBelow: i < rail.length - 1),
          },
      ];

  /// With nothing due in the next 3 days the rail shows no deadline, so one
  /// line says so (DESIGN.md 7). Never an all-clear a failed refresh can't back up.
  Widget _dueSummary(List<Deadline> all, List<CourseAttendance> att, AppData data, DateTime now) {
    if (data.deadlines.data == null || data.deadlines.error != null) return const SizedBox.shrink();
    if (needsAttention(all, att, now).isNotEmpty) return const SizedBox.shrink();
    const pad = EdgeInsets.fromLTRB(gutter, 12, gutter, 0);
    if (all.where(isDue).isEmpty) return const StatusLine(Status.ok, 'No deadlines in eClass.', padding: pad);
    final next = ([...all.where((d) => isDue(d) && !isDone(d, att) && d.end.isAfter(now))]
          ..sort((a, b) => a.end.compareTo(b.end)))
        .firstOrNull;
    final tail = next == null ? '' : ' Next: ${next.title}, ${next.courseName}, ${dayDateTime(next.end)}.';
    return StatusLine(Status.ok, 'Nothing due in the next 3 days.$tail', padding: pad);
  }

  /// The answer to "am I in attendance trouble", always on screen: each
  /// course in trouble with its tally, then one line for the rest. A limit is
  /// never guessed (DESIGN.md 7).
  Widget _attendance(BuildContext context, AppData data, List<Lesson> lessons, DateTime now) {
    final att = data.attendance.data?.value;
    final header = SectionHeader('Attendance', source: data.attendance);
    // One error row per failed service: the top of the screen already shows eClass's.
    if (att == null) {
      return data.attendance.error != null || data.deadlines.error != null
          ? const SizedBox.shrink()
          : Column(children: [header, const SkeletonRows(count: 1, timeColumn: false)]);
    }
    final limits = data.prefs.absenceLimits;
    final tracked = att.where((c) => c.classes.isNotEmpty).toList();
    final trouble = troubleOrder(tracked, limits, lessons).where((c) => AbsenceState.of(c, limits).trouble).toList();
    final limited = tracked.where((c) => limits[c.course.id] != null).length;
    final unlimited = [
      for (final c in tracked)
        if (limits[c.course.id] == null && c.count(AttendanceMark.absent) > 0) c,
    ]..sort((a, b) => b.count(AttendanceMark.absent).compareTo(a.count(AttendanceMark.absent)));
    final fine = limited - trouble.length;
    final courses = fine == 1 ? 'course is' : 'courses are';
    final String? okLine;
    if (fine == 0) {
      okLine = null;
    } else if (trouble.isNotEmpty) {
      okLine = 'The other $fine $courses within their limit.';
    } else if (fine == tracked.length) {
      okLine = fine == 1 ? 'The 1 course is within its limit.' : 'All $fine courses are within their limit.';
    } else {
      okLine = '$fine $courses within their limit.';
    }
    final infoLine = unlimited.isEmpty
        ? null
        : 'No limit set: ${unlimited.map((c) => '${c.course.name} ${c.count(AttendanceMark.absent)}').join(' · ')}';
    final t = Theme.of(context);
    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      header,
      for (final c in trouble) _TroubleRow(c, AbsenceState.of(c, limits), lessons: lessons, now: now),
      InkWell(
        onTap: () => widget.onOpenTab(3),
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 4),
          child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
            if (okLine != null) StatusLine(Status.ok, okLine),
            if (infoLine != null) StatusLine(Status.info, infoLine),
            if (okLine == null && infoLine == null && trouble.isEmpty)
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: gutter, vertical: 4),
                child: Text(
                    tracked.isEmpty ? 'No course takes attendance in eClass.' : 'No absences in ${tracked.length} courses.',
                    style: t.textTheme.bodyMedium),
              ),
          ]),
        ),
      ),
    ]);
  }

  List<Widget> _mail(BuildContext context, AppData data) {
    final t = Theme.of(context);
    final unread = (data.inbox.data?.value ?? const <MailHeader>[]).where((m) => m.unread).toList();
    if (unread.isEmpty) return const [];
    final total = data.mailUnread.data?.value ?? unread.length;
    return [
      SectionHeader('$total unread', source: data.inbox, staleAfter: const Duration(minutes: 30)),
      for (final m in unread.take(2))
        InkWell(
          onTap: () => openMail(context, m),
          child: ConstrainedBox(
            constraints: const BoxConstraints(minHeight: 48),
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: gutter, vertical: 8),
              child: Row(crossAxisAlignment: CrossAxisAlignment.baseline, textBaseline: TextBaseline.alphabetic, children: [
                Expanded(
                  child: Text(m.subject.isEmpty ? '(no subject)' : m.subject,
                      maxLines: 1, overflow: TextOverflow.ellipsis, style: t.textTheme.titleSmall),
                ),
                const SizedBox(width: 12),
                Text(pastWhen(m.received),
                    style: t.textTheme.bodySmall?.tnum.copyWith(color: t.colorScheme.onSurfaceVariant)),
              ]),
            ),
          ),
        ),
      if (total > 2)
        Align(
          alignment: Alignment.centerLeft,
          child: Padding(
            padding: const EdgeInsets.only(left: 8),
            child: TextButton(
              onPressed: () => Navigator.of(context).push(MaterialPageRoute(builder: (_) => const MailScreen())),
              child: Text('${total - 2} more'),
            ),
          ),
        ),
    ];
  }

  Widget _footer(BuildContext context, AppData data) {
    final t = Theme.of(context);
    final at = oldestData(data);
    final busy = data.lessons.loading || data.deadlines.loading || data.attendance.loading;
    final text = busy ? 'Updating…' : at == null ? '' : 'Updated ${updatedAt(at)}';
    return Padding(
      padding: const EdgeInsets.fromLTRB(gutter, 16, gutter, 24),
      child: Text(text, style: t.textTheme.bodySmall?.tnum.copyWith(color: t.colorScheme.onSurfaceVariant)),
    );
  }
}

/// A course near or over its absence limit: the name, what is left and when
/// its next class is, and the tally with its count.
class _TroubleRow extends StatelessWidget {
  final CourseAttendance c;
  final AbsenceState absence;
  final List<Lesson> lessons;
  final DateTime now;
  const _TroubleRow(this.c, this.absence, {required this.lessons, required this.now});

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context);
    final left = absence.left!;
    final next = nextLesson(lessons, now, (l) => isLessonOf(l, c.course));
    final words = [
      switch (left) { > 0 => '$left left', 0 => 'At the limit', _ => 'Over the limit by ${-left}' },
      if (next != null) 'next ${classWhen(next.day, next.lesson, now)}',
    ].join(' · ');
    return InkWell(
      onTap: () => openCourse(context, c.course),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(gutter, 8, gutter, 8),
        child: Row(children: [
          Expanded(
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(c.course.name, maxLines: 2, overflow: TextOverflow.ellipsis, style: t.textTheme.titleMedium),
              const SizedBox(height: 2),
              StatusLine(absence.status!, words, padding: EdgeInsets.zero),
            ]),
          ),
          const SizedBox(width: 16),
          TallyCount(absence),
        ]),
      ),
    );
  }
}
