import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../data/app_data.dart';
import '../data/urgency.dart';
import '../models/models.dart';
import '../services/eclass/eclass_links.dart';
import '../ui/format/format.dart';
import '../ui/theme/app_text.dart';
import 'common.dart';
import 'course_detail_screen.dart';
import 'deadline_tile.dart';

const _kindNames = {
  DeadlineKind.assignment: 'Assignment',
  DeadlineKind.quiz: 'Quiz',
  DeadlineKind.vod: 'VOD lecture',
  DeadlineKind.other: 'eClass event',
  DeadlineKind.classPeriod: 'Class period',
};

void openCourse(BuildContext context, Course course) => Navigator.of(context)
    .push(MaterialPageRoute(builder: (_) => CourseDetailScreen(courseId: course.id, name: course.name)));

/// A deadline's details: what and for which course, the due time or watch
/// window, watch progress, and the way into eClass (DESIGN.md 8, Deadlines).
Future<void> showDeadlineSheet(BuildContext context, Deadline d) => showModalBottomSheet<void>(
      context: context,
      showDragHandle: true,
      isScrollControlled: true,
      builder: (_) => _DeadlineSheet(d),
    );

class _DeadlineSheet extends StatelessWidget {
  final Deadline d;
  const _DeadlineSheet(this.d);

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context);
    final data = context.watch<AppData>();
    final now = DateTime.now();
    final att = data.attendance.data?.value ?? const <CourseAttendance>[];
    final course = courseFor(d.courseName, att)?.course;
    final vod = vodFor(d, att);
    final status = deadlineStatus(d, now);
    final muted = t.textTheme.bodyMedium?.copyWith(color: t.colorScheme.onSurfaceVariant);
    final item = eclassItemUrl(d);
    final link = item ?? (course == null ? null : eclassCourseUrl(course.id));
    final start = d.start;

    final when = d.kind == DeadlineKind.vod && start != null
        ? 'Watch from ${dayDateTime(start)} to ${dayDateTime(d.end)}'
        : d.kind == DeadlineKind.vod
            ? 'Closes ${dayDateTime(d.end)}'
            : 'Due ${dayDateTime(d.end)}';
    // Within 48 h the time left matters more than the date (DESIGN.md 8).
    final soon = d.end.difference(now) < const Duration(hours: 48);
    final rel = relative(d.end, now: now);
    final left = d.end.isBefore(now) ? rel : '${d.kind == DeadlineKind.vod ? 'Closes' : 'Due'} $rel';

    return SafeArea(
      child: SingleChildScrollView(
        padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Row(children: [
            Icon(deadlineIcon(d.kind), size: 18, color: t.colorScheme.onSurfaceVariant),
            const SizedBox(width: 8),
            Text(_kindNames[d.kind]!, style: muted),
          ]),
          const SizedBox(height: 8),
          Text(d.title, style: t.textTheme.titleMedium),
          if ((course?.name ?? d.courseName).isNotEmpty)
            Text(course?.name ?? d.courseName, style: muted),
          const SizedBox(height: 16),
          Text(when, style: t.textTheme.bodyMedium?.tnum),
          if (soon && status != null)
            StatusLine(status, left, padding: const EdgeInsets.only(top: 4))
          else if (soon)
            Text(left, style: muted?.tnum),
          if (vod != null) ...[
            const SizedBox(height: 16),
            Text(
                vod.done
                    ? 'Watched'
                    : '${vod.percent.floor()}% watched · '
                        '${(vod.length.inMinutes * vod.percent / 100).floor()} of ${vod.length.inMinutes} min',
                style: t.textTheme.bodyMedium?.tnum),
            const SizedBox(height: 6),
            LinearProgressIndicator(
              value: (vod.percent / 100).clamp(0, 1),
              minHeight: 4,
              backgroundColor: t.colorScheme.outlineVariant,
            ),
          ] else if (d.kind == DeadlineKind.vod) ...[
            const SizedBox(height: 16),
            Text('No watch progress in eClass for this video yet.', style: muted),
          ],
          const SizedBox(height: 24),
          if (link != null)
            SizedBox(
              width: double.infinity,
              child: FilledButton(
                onPressed: () => openUrl(context, link),
                child: Text(item != null ? 'Open in eClass' : 'Open the course in eClass'),
              ),
            ),
          if (course != null)
            Padding(
              padding: const EdgeInsets.only(top: 8),
              child: TextButton(
                onPressed: () {
                  Navigator.of(context).pop();
                  openCourse(context, course);
                },
                child: const Text('Course attendance and grade'),
              ),
            ),
        ]),
      ),
    );
  }
}

/// A timetable lesson opens its eClass course when there is one; otherwise
/// (a course eClass doesn't have, like Mental Education) a sheet with what
/// EduPage knows about it.
void openLesson(BuildContext context, Lesson lesson) {
  final att = context.read<AppData>().attendance.data?.value ?? const <CourseAttendance>[];
  final course = courseFor(lesson.subject, att)?.course;
  if (course != null) return openCourse(context, course);
  showModalBottomSheet<void>(
    context: context,
    showDragHandle: true,
    builder: (ctx) {
      final t = Theme.of(ctx);
      final muted = t.textTheme.bodyMedium?.copyWith(color: t.colorScheme.onSurfaceVariant);
      return SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(16, 0, 16, 24),
          child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(lesson.subject, style: t.textTheme.titleMedium),
            const SizedBox(height: 8),
            Text('${weekdayShort(lesson.weekday)} ${lesson.start}–${lesson.end}', style: t.textTheme.bodyMedium?.tnum),
            Text([lesson.room, lesson.kind, lesson.teacher].where((s) => s.isNotEmpty).join(' · '),
                style: muted?.tnum),
            const SizedBox(height: 16),
            Text('This class has no course in eClass, so there is no attendance or VOD record for it.',
                style: muted),
          ]),
        ),
      );
    },
  );
}
