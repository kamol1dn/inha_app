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
import 'deadline_tile.dart';

/// One course: absences, what is due, the INS grade, VOD progress and every
/// attendance session (DESIGN.md 8, Courses). Reads live data, so it updates
/// when a refresh lands while it is open.
class CourseDetailScreen extends StatelessWidget {
  final int courseId;
  final String name; // for the app bar while the course is looked up
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
    final muted = t.textTheme.bodyMedium?.tnum.copyWith(color: t.colorScheme.onSurfaceVariant);
    if (c == null) {
      return Scaffold(
        appBar: AppBar(title: Text(name, maxLines: 1, overflow: TextOverflow.ellipsis)),
        body: const Padding(
          padding: EdgeInsets.all(16),
          child: Text('This course is no longer on your eClass dashboard.'),
        ),
      );
    }
    final absence = AbsenceState.of(c, data.prefs.absenceLimits);
    final absent = absence.used;
    final limit = absence.limit;
    final held = c.held(now);
    final due = courseDeadlines(c.course, data.deadlines.data?.value ?? const [], att, now);
    final grade = gradeFor(c.course, data.grades.data?.value);
    final facts = [
      if (held.isNotEmpty) '${limit == null ? 'of ' : ''}${held.length} ${held.length == 1 ? 'class' : 'classes'} so far',
      c.course.code,
      c.course.professor,
    ].where((s) => s.isNotEmpty).join(' · ');

    return Scaffold(
      appBar: AppBar(title: Text(c.course.name, maxLines: 1, overflow: TextOverflow.ellipsis)),
      body: RefreshIndicator(
        onRefresh: data.refreshEclass,
        child: ListView(physics: const AlwaysScrollableScrollPhysics(), children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 16, 16, 0),
            child: Text(
                c.classes.isEmpty
                    ? 'No class attendance'
                    : limit == null || absent > limit
                        ? '$absent ${absent == 1 ? 'absence' : 'absences'}'
                        : '$absent of $limit',
                style: c.classes.isEmpty ? t.textTheme.titleMedium : t.textTheme.headlineMedium),
          ),
          if (c.classes.isNotEmpty && limit != null) ...[
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 4, 16, 4),
              child: Row(children: [
                AbsenceBar(absence),
                const SizedBox(width: 8),
                Text(absent > limit ? 'limit $limit' : 'allowed absences used', style: muted),
              ]),
            ),
            if (absence.status case final s?)
              StatusLine(
                  s,
                  switch (absence.left!) {
                    < 0 => 'Over the limit by ${-absence.left!}',
                    0 => 'At the limit: one more absence is over it',
                    1 => '1 absence left',
                    final l => '$l absences left',
                  }),
          ],
          if (facts.isNotEmpty)
            Padding(padding: const EdgeInsets.symmetric(horizontal: 16), child: Text(facts, style: muted)),
          Padding(
            padding: const EdgeInsets.only(left: 8, top: 4),
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
            for (final d in due) DeadlineTile(d, attendance: att, now: now, showDay: true),
          ],
          SectionHeader('Grade', source: data.grades, staleAfter: const Duration(hours: 24)),
          ListTile(
            title: Text(
              grade == null
                  ? 'Not in INS'
                  : grade.graded
                      ? grade.letter
                      : 'Not graded yet',
              style: t.textTheme.titleMedium?.tnum,
            ),
            subtitle: grade == null
                ? Text(data.grades.data == null ? 'Sign in to INS to see grades.' : 'INS has no record of this course.',
                    style: muted)
                // INS labels the term in progress "Course registration".
                : Text('${grade.graded ? grade.term : 'This semester'} · ${grade.credits.toStringAsFixed(1)} credits',
                    style: muted),
          ),
          if (c.vods.isNotEmpty) ...[
            const SectionHeader('VOD lectures'),
            for (final v in c.vods)
              ListTile(
                title: Text(v.title, style: t.textTheme.titleMedium),
                subtitle: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Text('Week ${v.week} · ${duration(v.length)} · ${v.percent.round()}% watched', style: muted),
                  const SizedBox(height: 6),
                  LinearProgressIndicator(
                    value: (v.percent / 100).clamp(0, 1),
                    minHeight: 4,
                    backgroundColor: t.colorScheme.outlineVariant,
                  ),
                ]),
              ),
          ],
          if (held.isNotEmpty) ...[
            const SectionHeader('Classes so far'),
            for (final (i, e) in held.reversed.indexed) ...[
              if (i > 0) const Divider(indent: 16),
              ListTile(
                title: Text(dayDate(e.date), style: t.textTheme.bodyLarge?.tnum),
                trailing: Row(mainAxisSize: MainAxisSize.min, children: [
                  Icon(_markText[e.mark]!.$1, size: 18, color: statusColors(context).of(_markText[e.mark]!.$3).fg),
                  const SizedBox(width: 8),
                  Text(_markText[e.mark]!.$2, style: t.textTheme.bodyMedium),
                ]),
              ),
            ],
          ],
          const SizedBox(height: 24),
        ]),
      ),
    );
  }
}
