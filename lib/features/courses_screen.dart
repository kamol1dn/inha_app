import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../data/absence.dart';
import '../data/app_data.dart';
import '../models/models.dart';
import '../ui/theme/app_text.dart';
import 'absence_widgets.dart';
import 'common.dart';
import 'details.dart';

/// "Am I in attendance trouble", per course (DESIGN.md 8, Courses).
class CoursesScreen extends StatelessWidget {
  const CoursesScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final data = context.watch<AppData>();
    final limits = data.prefs.absenceLimits;
    final courses = troubleOrder(data.attendance.data?.value ?? const [], limits, data.lessons.data?.value ?? const []);
    final unset = courses.where((c) => c.classes.isNotEmpty && limits[c.course.id] == null).length;
    return RefreshIndicator(
      onRefresh: data.refreshEclass,
      child: ListView(physics: const AlwaysScrollableScrollPhysics(), children: [
        SourceError(data.attendance, 'eClass', onRetry: data.refreshEclass),
        if (data.attendance.data == null && data.attendance.error != null)
          const Padding(
            padding: EdgeInsets.all(16),
            child: Text('Sign in to eClass in Settings to see attendance and VOD progress.'),
          ),
        if (unset > 0)
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 8, 8, 0),
            child: Row(children: [
              Expanded(
                child: Text(
                  unset == courses.where((c) => c.classes.isNotEmpty).length
                      ? 'Set each course\'s allowed absences to see how many are left.'
                      : '$unset ${unset == 1 ? 'course has' : 'courses have'} no absence limit set.',
                  style: Theme.of(context).textTheme.bodyMedium,
                ),
              ),
              TextButton(
                onPressed: () =>
                    Navigator.of(context).push(MaterialPageRoute(builder: (_) => const AbsenceLimitsScreen())),
                child: const Text('Set limits'),
              ),
            ]),
          ),
        for (final c in courses) _CourseTile(c, AbsenceState.of(c, limits)),
        const SizedBox(height: 24),
      ]),
    );
  }
}

class _CourseTile extends StatelessWidget {
  final CourseAttendance c;
  final AbsenceState absence;
  const _CourseTile(this.c, this.absence);

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context);
    final muted = t.textTheme.bodyMedium?.tnum.copyWith(color: t.colorScheme.onSurfaceVariant);
    final late = c.count(AttendanceMark.late);
    final present = c.count(AttendanceMark.present);
    final unwatched = c.vods.where((v) => !v.done).toList();
    final vodLine = c.vods.isEmpty
        ? null
        : unwatched.isEmpty
            ? 'VOD: all ${c.vods.length} watched'
            : 'VOD: ${c.vods.length - unwatched.length} of ${c.vods.length} watched';
    final status = absence.status;
    return ListTile(
      minTileHeight: 88,
      title: Row(children: [
        Expanded(
            child: Text(c.course.name,
                maxLines: 1, overflow: TextOverflow.ellipsis, style: t.textTheme.titleMedium)),
        if (status != null) ...[
          const SizedBox(width: 8),
          StatusTag(status, absence.tag!),
        ],
      ]),
      subtitle: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        const SizedBox(height: 4),
        if (c.classes.isEmpty)
          Text('No class attendance recorded', style: muted)
        else if (absence.limit == null)
          Text('${absence.used} ${absence.used == 1 ? 'absence' : 'absences'} · $present present'
              '${late > 0 ? ' · $late late' : ''} · limit not set', style: muted)
        else
          AbsenceLine(absence,
              style: status == null ? muted : muted?.copyWith(color: statusColors(context).of(status).fg)),
        if (vodLine != null) Text(vodLine, style: muted),
      ]),
      onTap: () => openCourse(context, c.course),
    );
  }
}
