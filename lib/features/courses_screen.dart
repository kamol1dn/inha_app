import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../data/app_data.dart';
import '../models/models.dart';
import '../ui/format/format.dart';
import '../ui/theme/app_text.dart';
import '../ui/theme/status_colors.dart';
import 'common.dart';

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
      onTap: () => Navigator.of(context).push(MaterialPageRoute(builder: (_) => _CourseDetail(c))),
    );
  }
}

class _CourseDetail extends StatelessWidget {
  final CourseAttendance c;
  const _CourseDetail(this.c);

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
    final muted = t.textTheme.bodyMedium?.tnum.copyWith(color: t.colorScheme.onSurfaceVariant);
    final absent = c.count(AttendanceMark.absent);
    return Scaffold(
      appBar: AppBar(title: Text(c.course.name, maxLines: 1, overflow: TextOverflow.ellipsis)),
      body: ListView(children: [
        if (c.classes.isNotEmpty) ...[
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 16, 16, 0),
            child: Text('$absent ${absent == 1 ? 'absence' : 'absences'}', style: t.textTheme.headlineMedium),
          ),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            child: Text('of ${c.classes.length} classes · ${c.course.code}', style: muted),
          ),
          const SectionHeader('Classes'),
          for (final (i, e) in c.classes.indexed) ...[
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
        const SizedBox(height: 24),
      ]),
    );
  }
}
