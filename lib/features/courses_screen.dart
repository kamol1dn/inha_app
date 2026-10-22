import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../data/app_data.dart';
import '../models/models.dart';
import '../ui/theme/app_text.dart';
import '../ui/theme/status_colors.dart';
import 'common.dart';
import 'details.dart';

/// "Am I in attendance trouble", per course (DESIGN.md 8, Courses).
class CoursesScreen extends StatelessWidget {
  const CoursesScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final data = context.watch<AppData>();
    final courses = [...?data.attendance.data?.value]
      ..sort((a, b) => b.count(AttendanceMark.absent).compareTo(a.count(AttendanceMark.absent)));
    return RefreshIndicator(
      onRefresh: data.refreshEclass,
      child: ListView(physics: const AlwaysScrollableScrollPhysics(), children: [
        SourceError(data.attendance, 'eClass', onRetry: data.refreshEclass),
        if (data.attendance.data == null && data.attendance.error != null)
          const Padding(
            padding: EdgeInsets.all(16),
            child: Text('Sign in to eClass in Settings to see attendance and VOD progress.'),
          ),
        for (final c in courses) _CourseTile(c),
        const SizedBox(height: 24),
      ]),
    );
  }
}

class _CourseTile extends StatelessWidget {
  final CourseAttendance c;
  const _CourseTile(this.c);

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context);
    final muted = t.textTheme.bodyMedium?.tnum.copyWith(color: t.colorScheme.onSurfaceVariant);
    final absent = c.count(AttendanceMark.absent);
    final late = c.count(AttendanceMark.late);
    final present = c.count(AttendanceMark.present);
    final attendanceLine = c.classes.isEmpty
        ? 'No class attendance recorded'
        : '$absent ${absent == 1 ? 'absence' : 'absences'} · $present present'
            '${late > 0 ? ' · $late late' : ''} · limit not set';
    final unwatched = c.vods.where((v) => !v.done).toList();
    final vodLine = c.vods.isEmpty
        ? null
        : unwatched.isEmpty
            ? 'VOD: all ${c.vods.length} watched'
            : 'VOD: ${c.vods.length - unwatched.length} of ${c.vods.length} watched';
    return ListTile(
      minTileHeight: 88,
      title: Row(children: [
        Expanded(
            child: Text(c.course.name,
                maxLines: 1, overflow: TextOverflow.ellipsis, style: t.textTheme.titleMedium)),
        if (absent > 0) ...[
          const SizedBox(width: 8),
          StatusTag(Status.info, '$absent absent'),
        ],
      ]),
      subtitle: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        const SizedBox(height: 2),
        Text(attendanceLine, style: muted),
        if (vodLine != null) Text(vodLine, style: muted),
      ]),
      onTap: () => openCourse(context, c.course),
    );
  }
}
