import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../core/session.dart';
import '../data/absence.dart';
import '../data/app_data.dart';
import '../data/exams.dart';
import '../data/rail.dart';
import '../data/urgency.dart';
import '../models/models.dart';
import '../notifications/routes.dart';
import '../notifications/rules.dart' show classKeyPrefix;
import '../services/eclass/eclass_links.dart';
import '../ui/format/format.dart';
import '../ui/theme/app_text.dart';
import '../ui/theme/status_colors.dart';
import 'absence_widgets.dart';
import 'common.dart';
import 'course_scores_screen.dart';
import 'exam_rows.dart';
import 'rail_rows.dart';
import 'vod_player_screen.dart';

/// One VOD: how much is watched, where the student left it on this phone, and the
/// way in, which depends on its watch window and on whether eClass named its module
/// (DESIGN.md 8, VOD player).
class _VodRow extends StatelessWidget {
  final VodProgress v;
  final Course course;
  final DateTime now;
  const _VodRow(this.v, {required this.course, required this.now});

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context);
    final muted = t.textTheme.bodyMedium!.tnum.copyWith(color: t.colorScheme.onSurfaceVariant);
    final id = v.moduleId;
    final offer = vodOffer(moduleId: id, opens: v.opens, closes: v.closes, done: v.done, now: now);
    final place = offer == VodOffer.watch ? context.read<AppData>().prefs.vodPosition(id!) : null;
    final note = switch (offer) {
      VodOffer.closed when !v.done => 'Closed ${dayDateTime(v.closes!, now: now)}',
      VodOffer.notOpen => 'Opens ${dayDateTime(v.opens!, now: now)}',
      _ when place != null => 'Continue from ${playPosition(place)}',
      _ => null,
    };
    Widget watch(String label) => TextButton(
          onPressed: () => watchVod(context,
              moduleId: id!, title: v.title, courseId: course.id, resume: offer == VodOffer.watch),
          child: Text(label),
        );
    Widget browser(Uri url) => TextButton(onPressed: () => openUrl(context, url), child: const Text('Open in eClass'));
    final action = switch (offer) {
      VodOffer.watch => watch('Watch'),
      VodOffer.watchAgain => watch('Watch again'),
      VodOffer.browser => browser(eclassCourseUrl(course.id)),
      VodOffer.closed when id != null => browser(eclassVodUrl(id)),
      _ => null,
    };
    return Padding(
      padding: const EdgeInsets.only(top: 8, bottom: 8),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Padding(
          padding: const EdgeInsets.only(left: gutter, right: 8),
          child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Expanded(
              child: Padding(
                padding: const EdgeInsets.only(right: 12),
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Text(v.title, style: t.textTheme.titleSmall),
                  Text(
                      'Week ${v.week} · ${(v.length.inMinutes * v.percent / 100).floor()} / ${v.length.inMinutes} min'
                      '${v.done ? ' · watched' : ''}',
                      style: muted),
                  if (note != null) Text(note, style: muted),
                ]),
              ),
            ),
            ?action,
          ]),
        ),
        Padding(
          padding: const EdgeInsets.fromLTRB(gutter, 6, gutter, 0),
          child: LinearProgressIndicator(
            value: (v.percent / 100).clamp(0, 1),
            minHeight: 4,
            color: t.colorScheme.onSurface,
            backgroundColor: t.colorScheme.outlineVariant,
          ),
        ),
      ]),
    );
  }
}

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
      return HeadingScaffold(
        title: name,
        body: (heading) => ListView(children: [
          _heading(context, name, '', heading),
          if (data.attendance.data == null && data.attendance.error == null)
            const SkeletonRows(timeColumn: false)
          else
            SourceError(data.attendance, 'eClass', onRetry: data.refreshEclass),
          if (data.attendance.data != null) const EmptyNote('This course is no longer on your eClass dashboard.'),
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

    return HeadingScaffold(
      title: c.course.name,
      body: (heading) => RefreshIndicator(
        onRefresh: data.refreshEclass,
        child: ListView(physics: const AlwaysScrollableScrollPhysics(), children: [
          _heading(context, c.course.name, [c.course.code, c.course.professor].where((s) => s.isNotEmpty).join(' · '),
              heading),
          SourceError(data.attendance, 'eClass', onRetry: data.refreshEclass),
          if (c.classes.isEmpty)
            Padding(
              padding: const EdgeInsets.fromLTRB(gutter, 16, gutter, 0),
              child: Text('No class attendance in eClass for this course.', style: t.textTheme.bodyLarge),
            )
          else ...[
            Padding(
              padding: const EdgeInsets.fromLTRB(gutter, 20, gutter, 0),
              child: Wrap(crossAxisAlignment: WrapCrossAlignment.center, spacing: 16, runSpacing: 8, children: [
                Text(limit == null ? '$absent' : '$absent of $limit',
                    style: t.textTheme.headlineMedium?.tnum.copyWith(color: countColor)),
                Tally(absence, height: 28),
                if (isStale(data.attendance, const Duration(hours: 3))) StaleMarker(data.attendance.data!.fetchedAt),
              ]),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(gutter, 4, gutter, 0),
              child: Text(
                [
                  limit == null ? '${absent == 1 ? 'absence' : 'absences'} · limit not set' : 'allowed absences used',
                  if (held.isNotEmpty) '${held.length} ${held.length == 1 ? 'class' : 'classes'} held so far',
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
          ..._exam(context, data.exams(now), c.course, now),
          if (data.gradesOf(c.course.id) case final g?) ...[
            SectionHeader('Scores', source: data.courseGrades),
            ScoresRow(g),
          ],
          SectionHeader('Grade', source: data.grades, staleAfter: const Duration(hours: 24)),
          if (grade == null && data.grades.data == null)
            if (data.grades.error is LoginRequired)
              EmptyNote('Sign in to INS to see grades.', action: 'Sign in', onAction: () => openSettings(context))
            else if (data.grades.error == null)
              const SkeletonRows(count: 1, timeColumn: false)
            else
              SourceError(data.grades, 'INS', onRetry: data.refreshGrades)
          else
            Padding(
              padding: const EdgeInsets.fromLTRB(gutter, 8, gutter, 8),
              child: Row(crossAxisAlignment: CrossAxisAlignment.baseline, textBaseline: TextBaseline.alphabetic, children: [
                Expanded(
                  child: Text(
                    grade == null
                        ? 'INS has no record of this course.'
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
          ..._timetable(context, data, c.course, now),
          if (c.vods.isNotEmpty) ...[
            SectionHeader('VOD lectures', source: data.attendance),
            for (final v in c.vods) _VodRow(v, course: c.course, now: now),
          ],
          if (held.isNotEmpty) ...[
            SectionHeader('Classes so far', source: data.attendance),
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

  /// When and where the course meets each week. Short, so before the long lists.
  /// A row opens Schedule on its day.
  static List<Widget> _timetable(BuildContext context, AppData data, Course course, DateTime now) {
    final weekly = [...?data.lessons.data?.value.where((l) => isLessonOf(l, course))]..sort((a, b) {
        final byDay = a.weekday.compareTo(b.weekday);
        return byDay != 0 ? byDay : a.start.compareTo(b.start);
      });
    if (weekly.isEmpty) return const [];
    final t = Theme.of(context);
    return [
      SectionHeader('In the timetable', source: data.lessons, staleAfter: const Duration(hours: 24)),
      for (final (i, l) in weekly.indexed) ...[
        if (i > 0) const Rule(),
        InkWell(
          onTap: () {
            final inDays = (l.weekday - now.weekday) % 7;
            final day = DateTime(now.year, now.month, now.day + inDays);
            context.read<NotificationTaps>().value = '$classKeyPrefix${day.toIso8601String()}';
          },
          child: ConstrainedBox(
            constraints: const BoxConstraints(minHeight: 48),
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: gutter, vertical: 12),
              child: Row(crossAxisAlignment: CrossAxisAlignment.baseline, textBaseline: TextBaseline.alphabetic, children: [
                Text('${weekdayShort(l.weekday)} ${l.start}', style: t.textTheme.numeral),
                const SizedBox(width: 16),
                Expanded(
                  child: Text([l.room, l.kind, l.teacher].where((s) => s.isNotEmpty).join(' · '),
                      style: t.textTheme.bodyMedium?.tnum.copyWith(color: t.colorScheme.onSurfaceVariant)),
                ),
              ]),
            ),
          ),
        ),
      ],
    ];
  }

  /// The course's sitting in the exam period on show, or that the timetable
  /// lists none. Nothing outside an exam period.
  static List<Widget> _exam(BuildContext context, ExamMatch? match, Course course, DateTime now) {
    if (match == null) return const [];
    final p = match.period;
    final mine = match.exams.where((m) => m.course.eclass?.id == course.id).toList();
    final unlisted = match.unlisted.any((s) => s.eclass?.id == course.id);
    if (mine.isEmpty && !unlisted) return const [];
    final t = Theme.of(context);
    return [
      SectionHeader(p.name),
      for (final m in mine) ExamRow(m, p, now: now, line: false, showDay: true, past: !m.exam.end.isAfter(now)),
      if (mine.isEmpty)
        Padding(
          padding: const EdgeInsets.fromLTRB(gutter, 4, gutter, 4),
          child: Text('No ${p.name.toLowerCase()} on the timetable for this course.',
              style: t.textTheme.bodyMedium?.copyWith(color: t.colorScheme.onSurfaceVariant)),
        ),
    ];
  }

  /// The course name as the screen's heading, with its code and professor.
  /// Once the name scrolls away it shows in the app bar ([HeadingScaffold]).
  static Widget _heading(BuildContext context, String name, String facts, Key nameKey) {
    final t = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.fromLTRB(gutter, 16, gutter, 0),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Text(name, key: nameKey, style: t.textTheme.headlineSmall),
        if (facts.isNotEmpty)
          Padding(
            padding: const EdgeInsets.only(top: 2),
            child: Text(facts, style: t.textTheme.bodyMedium?.copyWith(color: t.colorScheme.onSurfaceVariant)),
          ),
      ]),
    );
  }
}
