import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../core/session.dart';
import '../data/absence.dart';
import '../data/app_data.dart';
import '../data/rail.dart';
import '../models/models.dart';
import '../ui/format/format.dart';
import '../ui/theme/app_text.dart';
import 'absence_widgets.dart';
import 'common.dart';
import 'details.dart';
import 'rail_rows.dart';

/// "Am I in attendance trouble", per course (DESIGN.md 8, Courses).
class CoursesScreen extends StatelessWidget {
  const CoursesScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final data = context.watch<AppData>();
    final t = Theme.of(context);
    final now = DateTime.now();
    final limits = data.prefs.absenceLimits;
    final lessons = data.lessons.data?.value ?? const <Lesson>[];
    final courses = troubleOrder(data.attendance.data?.value ?? const [], limits, lessons);
    final tracked = courses.where((c) => c.classes.isNotEmpty).length;
    final unset = courses.where((c) => c.classes.isNotEmpty && limits[c.course.id] == null).length;
    final at = data.attendance.data?.fetchedAt;
    return RefreshIndicator(
      onRefresh: data.refreshEclass,
      child: ListView(physics: const AlwaysScrollableScrollPhysics(), children: [
        const OfflineRow(),
        if (data.attendance.data == null && data.attendance.error is LoginRequired)
          EmptyNote('Sign in to eClass to see attendance and VOD progress.',
              action: 'Sign in', onAction: () => openSettings(context))
        else if (data.attendance.data == null && data.attendance.error == null)
          const SkeletonRows(timeColumn: false)
        else
          SourceError(data.attendance, 'eClass', onRetry: data.refreshEclass),
        if (unset > 0)
          Padding(
            padding: const EdgeInsets.fromLTRB(gutter, 8, 8, 4),
            child: Row(children: [
              Expanded(
                child: Text(
                  unset == tracked
                      ? "Set each course's allowed absences to see how many are left."
                      : '$unset ${unset == 1 ? 'course has' : 'courses have'} no absence limit set.',
                  style: t.textTheme.bodyMedium,
                ),
              ),
              TextButton(
                onPressed: () =>
                    Navigator.of(context).push(MaterialPageRoute(builder: (_) => const AbsenceLimitsScreen())),
                child: const Text('Set limits'),
              ),
            ]),
          )
        else if (at != null && courses.isNotEmpty)
          Padding(
            padding: const EdgeInsets.fromLTRB(gutter, 16, gutter, 12),
            child: Text('Absences against the limits you set, as of ${updatedAt(at)}.',
                style: t.textTheme.bodyMedium?.tnum.copyWith(color: t.colorScheme.onSurfaceVariant)),
          ),
        for (final c in courses) ...[
          const Rule(),
          _CourseRow(c, AbsenceState.of(c, limits),
              next: nextLesson(lessons, now, (l) => isLessonOf(l, c.course), off: data.classFree), now: now),
        ],
        const SizedBox(height: 24),
      ]),
    );
  }
}

class _CourseRow extends StatelessWidget {
  final CourseAttendance c;
  final AbsenceState absence;
  final ({Lesson lesson, DateTime day})? next;
  final DateTime now;
  const _CourseRow(this.c, this.absence, {required this.next, required this.now});

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context);
    final muted = t.textTheme.bodyMedium!.tnum.copyWith(color: t.colorScheme.onSurfaceVariant);
    final status = absence.status;
    final n = next;
    final when = n == null ? null : classWhen(n.day, n.lesson, now);
    final unwatched = c.vods.where((v) => !v.done).length;
    final vodLine = c.vods.isEmpty
        ? null
        : unwatched == 0
            ? 'VOD all ${c.vods.length} watched'
            : 'VOD ${c.vods.length - unwatched} of ${c.vods.length} watched';
    final String? plain;
    if (c.classes.isEmpty) {
      plain = 'No class attendance in eClass';
    } else {
      plain = [
        if (absence.limit == null) 'Limit not set',
        if (n != null)
          [
            when!.startsWith('to') ? capitalized(when) : 'Next $when', // today, tomorrow
            n.lesson.room,
          ].where((s) => s.isNotEmpty).join(' · '),
      ].join(' · ');
    }
    return InkWell(
      onTap: () => openCourse(context, c.course),
      child: ConstrainedBox(
        constraints: const BoxConstraints(minHeight: 72),
        child: Padding(
          padding: const EdgeInsets.fromLTRB(gutter, 12, gutter, 12),
          child: Row(children: [
            Expanded(
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text(c.course.name, maxLines: 2, overflow: TextOverflow.ellipsis, style: t.textTheme.titleMedium),
                const SizedBox(height: 2),
                if (status != null)
                  StatusLine(
                      status,
                      [
                        switch (absence.left!) { > 0 && final l => '$l left', 0 => 'At the limit', final l => 'Over by ${-l}' },
                        if (when != null) 'next $when',
                      ].join(' · '),
                      padding: EdgeInsets.zero)
                else if (plain.isNotEmpty)
                  Text(plain, style: muted),
                if (vodLine != null) Text(vodLine, style: muted),
              ]),
            ),
            if (c.classes.isNotEmpty) ...[const SizedBox(width: 16), TallyCount(absence)],
          ]),
        ),
      ),
    );
  }
}
