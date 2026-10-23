import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../data/absence.dart';
import '../data/app_data.dart';
import '../data/urgency.dart';
import '../models/models.dart';
import '../services/eclass/eclass_links.dart';
import '../ui/format/format.dart';
import '../ui/theme/app_text.dart';
import '../ui/theme/status_colors.dart';
import 'absence_widgets.dart';
import 'common.dart';
import 'rail_rows.dart';

/// One course: absences, what is due, the INS grade, VOD progress and every
/// attendance session (DESIGN.md 8, Courses). Reads live data, so it updates
/// when a refresh lands while it is open.
class CourseDetailScreen extends StatelessWidget {
  final int courseId;
  final String name; // shown while the course is looked up
  const CourseDetailScreen({super.key, required this.courseId, required this.name});

  static const _markText = {
    AttendanceMark.present: (Icons.check_circle_outline, 'Present', Status.ok),
    AttendanceMark.absent: (Icons.error_outline, 'Absent', Status.danger),
    AttendanceMark.late: (Icons.warning_amber_rounded, 'Late', Status.warning),
    AttendanceMark.other: (Icons.info_outline, 'Other', Status.info),
    AttendanceMark.unmarked: (Icons.remove, 'Not marked', Status.info),
  };

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context);
    final data = context.watch<AppData>();
    final now = DateTime.now();
    final att = data.attendance.data?.value ?? const <CourseAttendance>[];
    final c = att.where((a) => a.course.id == courseId).firstOrNull;
    final muted = t.textTheme.bodyMedium!.tnum.copyWith(color: t.colorScheme.onSurfaceVariant);
    if (c == null) {
      return Scaffold(
        appBar: AppBar(),
        body: ListView(children: [
          _heading(context, name, ''),
          const EmptyNote('This course is no longer on your eClass dashboard.'),
        ]),
      );
    }
    final absence = AbsenceState.of(c, data.prefs.absenceLimits);
    final absent = absence.used;
    final limit = absence.limit;
    final held = c.held(now);
    final due = courseDeadlines(c.course, data.deadlines.data?.value ?? const [], att, now);
    final grade = gradeFor(c.course, data.grades.data?.value);
    final status = absence.status;
    final countColor = status == null ? null : statusColors(context).of(status).fg;

    return Scaffold(
      appBar: AppBar(),
      body: RefreshIndicator(
        onRefresh: data.refreshEclass,
        child: ListView(physics: const AlwaysScrollableScrollPhysics(), children: [
          _heading(context, c.course.name, [c.course.code, c.course.professor].where((s) => s.isNotEmpty).join(' · ')),
          if (c.classes.isEmpty)
            Padding(
              padding: const EdgeInsets.fromLTRB(gutter, 16, gutter, 0),
              child: Text('No class attendance in eClass for this course.', style: t.textTheme.bodyLarge),
            )
          else ...[
            Padding(
              padding: const EdgeInsets.fromLTRB(gutter, 20, gutter, 0),
              child: Wrap(crossAxisAlignment: WrapCrossAlignment.center, spacing: 16, runSpacing: 8, children: [
                Text(limit == null || absent > limit ? '$absent' : '$absent of $limit',
                    style: t.textTheme.headlineMedium?.copyWith(color: countColor)),
                Tally(absence, height: 28),
              ]),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(gutter, 4, gutter, 0),
              child: Text(
                [
                  limit == null
                      ? '${absent == 1 ? 'absence' : 'absences'} · limit not set'
                      : absent > limit
                          ? 'absences · limit $limit'
                          : 'allowed absences used',
                  if (held.isNotEmpty) 'of ${held.length} ${held.length == 1 ? 'class' : 'classes'} so far',
                ].join(' · '),
                style: muted,
              ),
            ),
            if (status != null)
              StatusLine(
                  status,
                  switch (absence.left!) {
                    < 0 => 'Over the limit by ${-absence.left!}',
                    0 => 'At the limit: one more absence is over it',
                    1 => '1 absence left',
                    final l => '$l absences left',
                  },
                  padding: const EdgeInsets.fromLTRB(gutter, 4, gutter, 0)),
          ],
          Padding(
            padding: const EdgeInsets.only(left: 8, top: 8),
            child: Wrap(spacing: 8, children: [
              TextButton(
                onPressed: () => openUrl(context, eclassCourseUrl(c.course.id)),
                child: const Text('Open in eClass'),
              ),
              if (c.classes.isNotEmpty)
                TextButton(
                  onPressed: () => editAbsenceLimit(context, c.course),
                  child: Text(limit == null ? 'Set absence limit' : 'Change limit'),
                ),
            ]),
          ),
          if (due.isNotEmpty) ...[
            SectionHeader('Due', source: data.deadlines),
            for (final d in due) DueRow(d, attendance: att, now: now, line: false, showDay: true),
          ],
          SectionHeader('Grade', source: data.grades, staleAfter: const Duration(hours: 24)),
          Padding(
            padding: const EdgeInsets.fromLTRB(gutter, 8, gutter, 8),
            child: Row(crossAxisAlignment: CrossAxisAlignment.baseline, textBaseline: TextBaseline.alphabetic, children: [
              Expanded(
                child: Text(
                  grade == null
                      ? (data.grades.data == null ? 'Sign in to INS to see grades.' : 'INS has no record of this course.')
                      // INS labels the term in progress "Course registration".
                      : '${grade.graded ? grade.term : 'This semester'} · ${grade.credits.toStringAsFixed(1)} credits',
                  style: muted,
                ),
              ),
              if (grade != null)
                Text(grade.graded ? grade.letter : 'Not graded yet',
                    style: grade.graded ? t.textTheme.titleMedium : muted),
            ]),
          ),
          if (c.vods.isNotEmpty) ...[
            const SectionHeader('VOD lectures'),
            for (final v in c.vods)
              Padding(
                padding: const EdgeInsets.fromLTRB(gutter, 8, gutter, 8),
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Text(v.title, style: t.textTheme.titleSmall),
                  Text(
                      'Week ${v.week} · ${(v.length.inMinutes * v.percent / 100).floor()} / ${v.length.inMinutes} min'
                      '${v.done ? ' · watched' : ''}',
                      style: muted),
                  const SizedBox(height: 6),
                  LinearProgressIndicator(
                    value: (v.percent / 100).clamp(0, 1),
                    minHeight: 4,
                    color: t.colorScheme.onSurface,
                    backgroundColor: t.colorScheme.outlineVariant,
                  ),
                ]),
              ),
          ],
          if (held.isNotEmpty) ...[
            const SectionHeader('Classes so far'),
            for (final (i, e) in held.reversed.indexed) ...[
              if (i > 0) const Rule(),
              ConstrainedBox(
                constraints: const BoxConstraints(minHeight: 48),
                child: Padding(
                  padding: const EdgeInsets.symmetric(horizontal: gutter, vertical: 12),
                  child: Row(children: [
                    Expanded(child: Text(dayDate(e.date), style: t.textTheme.bodyLarge?.tnum)),
                    Icon(_markText[e.mark]!.$1, size: 16, color: statusColors(context).of(_markText[e.mark]!.$3).fg),
                    const SizedBox(width: 6),
                    Text(_markText[e.mark]!.$2, style: t.textTheme.bodyMedium),
                  ]),
                ),
              ),
            ],
          ],
          const SizedBox(height: 24),
        ]),
      ),
    );
  }

  /// The course name as the screen's heading, with its code and professor.
  static Widget _heading(BuildContext context, String name, String facts) {
    final t = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.fromLTRB(gutter, 16, gutter, 0),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Text(name, style: t.textTheme.headlineSmall),
        if (facts.isNotEmpty)
          Padding(
            padding: const EdgeInsets.only(top: 2),
            child: Text(facts, style: t.textTheme.bodyMedium?.copyWith(color: t.colorScheme.onSurfaceVariant)),
          ),
      ]),
    );
  }
}
