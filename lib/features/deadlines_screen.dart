import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../data/app_data.dart';
import '../data/urgency.dart';
import '../models/models.dart';
import '../ui/format/format.dart';
import '../ui/theme/status_colors.dart';
import 'common.dart';
import 'deadline_tile.dart';

const _kindLabels = {
  DeadlineKind.assignment: 'Assignments',
  DeadlineKind.quiz: 'Quizzes',
  DeadlineKind.vod: 'VOD windows',
  DeadlineKind.other: 'Other',
  DeadlineKind.classPeriod: 'Class periods',
};

/// Everything due, grouped by day, with type / course / watched filters.
class DeadlinesScreen extends StatefulWidget {
  const DeadlinesScreen({super.key});
  @override
  State<DeadlinesScreen> createState() => _DeadlinesScreenState();
}

class _DeadlinesScreenState extends State<DeadlinesScreen> {
  @override
  Widget build(BuildContext context) {
    final data = context.watch<AppData>();
    final prefs = data.prefs;
    final now = DateTime.now();
    final all = [...?data.deadlines.data?.value]..sort((a, b) => a.end.compareTo(b.end));
    final att = data.attendance.data?.value ?? const <CourseAttendance>[];

    final kinds = prefs.deadlineKinds;
    final course = prefs.deadlineCourse;
    final showWatched = prefs.showWatchedVods;
    final shown = all.where((d) {
      if (!kinds.contains(d.kind)) return false;
      if (course != null && courseFor(d.courseName, att)?.course.name != course && d.courseName != course) {
        return false;
      }
      if (!showWatched && vodWatched(d, att) == true) return false;
      return true;
    }).toList();
    final filtered = kinds != Prefs.defaultDeadlineKinds || course != null || showWatched;

    final overdue = shown.where((d) => d.end.isBefore(now)).toList();
    final groups = <String, List<Deadline>>{};
    for (final d in shown.where((d) => !d.end.isBefore(now))) {
      groups.putIfAbsent(dayHeader(d.end, now: now), () => []).add(d);
    }

    return RefreshIndicator(
      onRefresh: data.refreshEclass,
      child: ListView(physics: const AlwaysScrollableScrollPhysics(), children: [
        _FilterBar(
          kinds: kinds,
          course: course,
          showWatched: showWatched,
          courses: _courseNames(all, att),
          onKinds: (v) => setState(() => prefs.deadlineKinds = v),
          onCourse: (v) => setState(() => prefs.deadlineCourse = v),
          onShowWatched: (v) => setState(() => prefs.showWatchedVods = v),
        ),
        SourceError(data.deadlines, 'eClass', onRetry: data.refreshEclass),
        if (data.deadlines.data != null && all.where(isDue).isEmpty && !filtered)
          const Padding(padding: EdgeInsets.all(16), child: Text('No upcoming deadlines in eClass.')),
        if (data.deadlines.data != null && shown.isEmpty && filtered)
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 16, 8, 0),
            child: Row(children: [
              const Expanded(child: Text('Nothing matches these filters.')),
              TextButton(
                onPressed: () => setState(prefs.resetDeadlineFilters),
                child: const Text('Clear filters'),
              ),
            ]),
          ),
        if (overdue.isNotEmpty) ...[
          const _DangerHeader('Overdue'),
          for (final d in overdue) DeadlineTile(d, attendance: att, now: now),
        ],
        for (final e in groups.entries) ...[
          SectionHeader(e.key, first: e.key == groups.keys.first && overdue.isEmpty),
          for (final d in e.value) DeadlineTile(d, attendance: att, now: now),
        ],
        const SizedBox(height: 24),
      ]),
    );
  }

  /// Course names to offer, preferring the full names from attendance over the
  /// calendar's sometimes-shortened ones.
  static List<String> _courseNames(List<Deadline> all, List<CourseAttendance> att) {
    final names = <String>{
      for (final c in att) c.course.name,
      for (final d in all)
        if (courseFor(d.courseName, att) == null && d.courseName.isNotEmpty) d.courseName,
    };
    return names.toList()..sort();
  }
}

class _FilterBar extends StatelessWidget {
  final Set<DeadlineKind> kinds;
  final String? course;
  final bool showWatched;
  final List<String> courses;
  final ValueChanged<Set<DeadlineKind>> onKinds;
  final ValueChanged<String?> onCourse;
  final ValueChanged<bool> onShowWatched;

  const _FilterBar({
    required this.kinds,
    required this.course,
    required this.showWatched,
    required this.courses,
    required this.onKinds,
    required this.onCourse,
    required this.onShowWatched,
  });

  @override
  Widget build(BuildContext context) {
    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 0),
      child: Row(children: [
        _CourseChip(course: course, courses: courses, onChanged: onCourse),
        const SizedBox(width: 8),
        for (final k in DeadlineKind.values) ...[
          FilterChip(
            label: Text(_kindLabels[k]!),
            selected: kinds.contains(k),
            onSelected: (on) => onKinds(on ? {...kinds, k} : ({...kinds}..remove(k))),
          ),
          const SizedBox(width: 8),
        ],
        FilterChip(
          label: const Text('Watched VODs'),
          selected: showWatched,
          onSelected: onShowWatched,
        ),
      ]),
    );
  }
}

class _CourseChip extends StatelessWidget {
  final String? course;
  final List<String> courses;
  final ValueChanged<String?> onChanged;
  const _CourseChip({required this.course, required this.courses, required this.onChanged});

  @override
  Widget build(BuildContext context) {
    final label = course ?? 'All courses';
    return InputChip(
      label: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 180),
        child: Text(label, overflow: TextOverflow.ellipsis),
      ),
      selected: course != null,
      showCheckmark: false,
      avatar: const Icon(Icons.school_outlined, size: 18),
      deleteIcon: const Icon(Icons.arrow_drop_down),
      onDeleted: () => _pick(context),
      onPressed: () => _pick(context),
    );
  }

  Future<void> _pick(BuildContext context) async {
    final picked = await showModalBottomSheet<String>(
      context: context,
      showDragHandle: true,
      builder: (ctx) => SafeArea(
        child: ListView(shrinkWrap: true, children: [
          ListTile(
            title: const Text('All courses'),
            trailing: course == null ? const Icon(Icons.check) : null,
            onTap: () => Navigator.pop(ctx, ''),
          ),
          for (final c in courses)
            ListTile(
              title: Text(c),
              trailing: c == course ? const Icon(Icons.check) : null,
              onTap: () => Navigator.pop(ctx, c),
            ),
        ]),
      ),
    );
    if (picked != null) onChanged(picked.isEmpty ? null : picked);
  }
}

class _DangerHeader extends StatelessWidget {
  final String text;
  const _DangerHeader(this.text);
  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
        child: Text(text,
            style: Theme.of(context)
                .textTheme
                .titleSmall
                ?.copyWith(color: statusColors(context).of(Status.danger).fg)),
      );
}
