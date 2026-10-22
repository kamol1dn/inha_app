import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../data/app_data.dart';
import '../models/models.dart';
import '../ui/format/format.dart';
import '../ui/theme/app_text.dart';
import 'common.dart';
import 'details.dart';

/// One day at a time, as an agenda list (DESIGN.md 8, Schedule).
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
    final lessons = data.lessons.data?.value ?? const <Lesson>[];
    final now = DateTime.now();
    final monday = DateTime(now.year, now.month, now.day).subtract(Duration(days: now.weekday - 1));
    // On the weekend, show next week.
    final weekStart = now.weekday > 5 ? monday.add(const Duration(days: 7)) : monday;
    return Column(
      children: [
        TabBar(
          controller: _days,
          dividerColor: Theme.of(context).colorScheme.outlineVariant,
          tabs: [
            for (var i = 0; i < 5; i++)
              Tab(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(weekdayShort(i + 1)),
                    Text(
                      '${weekStart.add(Duration(days: i)).day}',
                      style: Theme.of(context).textTheme.labelMedium?.tnum,
                    ),
                  ],
                ),
              ),
          ],
        ),
        SourceError(data.lessons, 'EduPage', onRetry: data.refreshTimetable),
        Expanded(
          child: TabBarView(
            controller: _days,
            children: [
              for (var i = 0; i < 5; i++)
                RefreshIndicator(
                  onRefresh: data.refreshTimetable,
                  child: _DayList(
                    lessons.where((l) => l.weekday == i + 1).toList()
                      ..sort((a, b) => minutesOf(a.start).compareTo(minutesOf(b.start))),
                    isToday: weekStart.add(Duration(days: i)) == DateTime(now.year, now.month, now.day),
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

class _DayList extends StatelessWidget {
  final List<Lesson> lessons;
  final bool isToday;
  final bool loaded;
  const _DayList(this.lessons, {required this.isToday, required this.loaded});

  @override
  Widget build(BuildContext context) {
    if (!loaded) return ListView(physics: const AlwaysScrollableScrollPhysics());
    if (lessons.isEmpty) {
      return ListView(
        physics: const AlwaysScrollableScrollPhysics(),
        children: const [Padding(padding: EdgeInsets.all(16), child: Text('No classes.'))],
      );
    }
    final now = DateTime.now();
    final nowMin = now.hour * 60 + now.minute;
    final rows = <Widget>[];
    for (var i = 0; i < lessons.length; i++) {
      final l = lessons[i];
      if (i > 0) {
        final gap = minutesOf(l.start) - minutesOf(lessons[i - 1].end);
        if (gap >= 30) rows.add(_BreakRow(Duration(minutes: gap)));
      }
      final past = isToday && minutesOf(l.end) <= nowMin;
      final current = isToday && minutesOf(l.start) <= nowMin && minutesOf(l.end) > nowMin;
      rows.add(LessonTile(l, past: past, current: current));
    }
    return ListView(physics: const AlwaysScrollableScrollPhysics(), children: [...rows, const SizedBox(height: 24)]);
  }
}

class _BreakRow extends StatelessWidget {
  final Duration gap;
  const _BreakRow(this.gap);
  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.fromLTRB(88, 4, 16, 4),
      child: Text(
        'Break ${duration(gap)}',
        style: t.textTheme.bodySmall?.copyWith(color: t.colorScheme.onSurfaceVariant),
      ),
    );
  }
}

class LessonTile extends StatelessWidget {
  final Lesson lesson;
  final bool past;
  final bool current;
  const LessonTile(this.lesson, {super.key, this.past = false, this.current = false});

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context);
    final muted = t.colorScheme.onSurfaceVariant;
    final timeColor = current ? t.colorScheme.primary : (past ? muted : t.colorScheme.onSurface);
    return ListTile(
      minTileHeight: 72,
      leading: SizedBox(
        width: 56,
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(current ? 'Now' : lesson.start, style: t.textTheme.titleSmall?.tnum.copyWith(color: timeColor)),
            Text(lesson.end, style: t.textTheme.bodySmall?.tnum.copyWith(color: muted)),
          ],
        ),
      ),
      title: Text(
        lesson.subject,
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
        style: t.textTheme.titleMedium?.copyWith(color: past ? muted : null),
      ),
      subtitle: Text(
        [lesson.room, lesson.kind, lesson.teacher].where((s) => s.isNotEmpty).join(' · '),
        style: t.textTheme.bodyMedium?.tnum.copyWith(color: muted),
      ),
      onTap: () => openLesson(context, lesson),
    );
  }
}
