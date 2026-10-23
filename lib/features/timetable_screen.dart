import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../data/app_data.dart';
import '../data/rail.dart';
import '../models/models.dart';
import '../ui/format/format.dart';
import '../ui/theme/app_text.dart';
import 'common.dart';
import 'rail_rows.dart';

/// One day at a time, as a rail (DESIGN.md 8, Schedule).
class TimetableScreen extends StatefulWidget {
  const TimetableScreen({super.key});
  @override
  State<TimetableScreen> createState() => TimetableScreenState();
}

class TimetableScreenState extends State<TimetableScreen> with SingleTickerProviderStateMixin {
  late final TabController _days = TabController(
    length: 5,
    vsync: this,
    initialIndex: DateTime.now().weekday <= 5 ? DateTime.now().weekday - 1 : 0,
  );

  /// Shows [weekday]'s classes (Monday to Friday; other days are ignored).
  void showWeekday(int weekday) {
    if (weekday >= DateTime.monday && weekday <= DateTime.friday) _days.animateTo(weekday - 1);
  }

  @override
  void dispose() {
    _days.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final data = context.watch<AppData>();
    final t = Theme.of(context);
    final lessons = data.lessons.data?.value ?? const <Lesson>[];
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    final monday = today.subtract(Duration(days: now.weekday - 1));
    // On the weekend, show next week.
    final weekStart = now.weekday > 5 ? monday.add(const Duration(days: 7)) : monday;
    return Column(
      children: [
        TabBar(
          controller: _days,
          tabs: [
            for (var i = 0; i < 5; i++)
              Tab(
                height: 64,
                child: Column(mainAxisSize: MainAxisSize.min, children: [
                  Text(weekdayShort(i + 1), style: t.textTheme.labelMedium),
                  Text(
                    '${weekStart.add(Duration(days: i)).day}',
                    style: t.textTheme.titleMedium?.tnum.copyWith(
                        color: weekStart.add(Duration(days: i)) == today ? t.colorScheme.primary : null),
                  ),
                ]),
              ),
          ],
        ),
        const OfflineRow(),
        SourceError(data.lessons, 'EduPage', onRetry: data.refreshTimetable),
        Expanded(
          child: TabBarView(
            controller: _days,
            children: [
              for (var i = 0; i < 5; i++)
                RefreshIndicator(
                  onRefresh: data.refreshTimetable,
                  child: _DayRail(
                    lessonsOn(lessons, weekStart.add(Duration(days: i))),
                    day: weekStart.add(Duration(days: i)),
                    now: now,
                    loaded: data.lessons.data != null,
                  ),
                ),
            ],
          ),
        ),
      ],
    );
  }
}

class _DayRail extends StatelessWidget {
  final List<Lesson> lessons;
  final DateTime day;
  final DateTime now;
  final bool loaded;
  const _DayRail(this.lessons, {required this.day, required this.now, required this.loaded});

  @override
  Widget build(BuildContext context) {
    if (!loaded) {
      return ListView(physics: const AlwaysScrollableScrollPhysics(), children: const [SkeletonRows()]);
    }
    if (lessons.isEmpty) {
      return ListView(
        physics: const AlwaysScrollableScrollPhysics(),
        children: [EmptyNote('No classes on ${dayDate(day, now: now)}.')],
      );
    }
    final isToday = DateTime(now.year, now.month, now.day) == day;
    // Rows first, then the rail flags (first, last) once their order is known.
    final rows = <Widget Function(bool above, bool below)>[];
    var nowPlaced = !isToday;
    for (var i = 0; i < lessons.length; i++) {
      final l = lessons[i];
      final start = lessonStart(l, day), end = lessonEnd(l, day);
      if (i > 0) {
        final gap = start.difference(lessonEnd(lessons[i - 1], day));
        if (gap.inMinutes >= 30) rows.add((a, b) => RailNoteRow('Break ${duration(gap)}', lineAbove: a, lineBelow: b));
      }
      if (!nowPlaced && start.isAfter(now)) {
        rows.add((a, b) => NowRow(now, lineAbove: a, lineBelow: b));
        nowPlaced = true;
      }
      final current = isToday && !start.isAfter(now) && end.isAfter(now);
      if (current) nowPlaced = true; // the class itself says "Now"
      final past = isToday && !end.isAfter(now);
      rows.add((a, b) => ClassRow(l,
          past: past, current: current, now: now, showTeacher: true, lineAbove: a, lineBelow: b));
    }
    if (!nowPlaced) rows.add((a, b) => NowRow(now, lineAbove: a, lineBelow: b));
    return ListView(physics: const AlwaysScrollableScrollPhysics(), children: [
      const SizedBox(height: 8),
      for (final (i, row) in rows.indexed) row(i > 0, i < rows.length - 1),
      const SizedBox(height: 24),
    ]);
  }
}
