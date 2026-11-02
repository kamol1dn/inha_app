import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../data/app_data.dart';
import '../data/exams.dart';
import '../data/rail.dart';
import '../models/models.dart';
import '../ui/format/format.dart';
import '../ui/theme/app_text.dart';
import 'common.dart';
import 'exam_rows.dart';
import 'rail_rows.dart';

/// One day at a time, as a rail (DESIGN.md 8, Schedule).
class TimetableScreen extends StatefulWidget {
  final DateTime Function() clock;
  const TimetableScreen({super.key, this.clock = DateTime.now});
  @override
  State<TimetableScreen> createState() => TimetableScreenState();
}

class TimetableScreenState extends State<TimetableScreen> with SingleTickerProviderStateMixin, WidgetsBindingObserver {
  late final TabController _days = TabController(length: 5, vsync: this, initialIndex: _todayIndex());

  /// The date the selected day was last set for. The app stays in memory for
  /// days: once this isn't today, what is selected is old, not the student's pick.
  late DateTime _settledOn = _today();

  DateTime _today() {
    final now = widget.clock();
    return DateTime(now.year, now.month, now.day);
  }

  /// Today's tab; on the weekend the strip shows next week, from its Monday.
  int _todayIndex() {
    final weekday = widget.clock().weekday;
    return weekday <= DateTime.friday ? weekday - 1 : 0;
  }

  /// Moves to today's tab if the day has changed since the selection was made.
  void _followToday() {
    if (_settledOn == _today()) return;
    _settledOn = _today();
    _days.index = _todayIndex();
  }

  /// Shows [weekday]'s classes (Monday to Friday; other days are ignored).
  void showWeekday(int weekday) {
    _settledOn = _today();
    if (weekday >= DateTime.monday && weekday <= DateTime.friday) _days.animateTo(weekday - 1);
  }

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state != AppLifecycleState.resumed) return;
    _followToday();
    setState(() {}); // the week strip follows the date too
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _days.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final data = context.watch<AppData>();
    final t = Theme.of(context);
    final lessons = data.lessons.data?.value ?? const <Lesson>[];
    final now = widget.clock();
    // Past midnight with no resume, say on a tab switch. Not during this build:
    // moving the tab drives the page view below.
    if (_settledOn != _today()) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) _followToday();
      });
    }
    final exams = data.exams(now);
    final today = DateTime(now.year, now.month, now.day);
    final monday = today.subtract(Duration(days: now.weekday - 1));
    // On the weekend, show next week.
    final weekStart = now.weekday > 5 ? monday.add(const Duration(days: 7)) : monday;
    // Tall enough for both lines at any text scale; a narrow tab shrinks its text to fit.
    final scaler = MediaQuery.textScalerOf(context);
    final tabHeight = 24 + scaler.scale(12) * 16 / 12 + scaler.scale(19) * 24 / 19;
    return Column(
      children: [
        TabBar(
          controller: _days,
          tabs: [
            for (var i = 0; i < 5; i++)
              Tab(
                height: tabHeight,
                child: FittedBox(
                  fit: BoxFit.scaleDown,
                  child: Column(mainAxisSize: MainAxisSize.min, children: [
                  Text(weekdayShort(i + 1), style: t.textTheme.labelMedium),
                  Text(
                    '${weekStart.add(Duration(days: i)).day}',
                    style: t.textTheme.titleMedium?.tnum.copyWith(
                        color: weekStart.add(Duration(days: i)) == today ? t.colorScheme.primary : null),
                  ),
                  ]),
                ),
              ),
          ],
        ),
        const OfflineRow(),
        SourceError(data.lessons, 'EduPage', onRetry: data.refreshTimetable, coveredByOfflineRow: true),
        Expanded(
          child: TabBarView(
            controller: _days,
            children: [
              for (var i = 0; i < 5; i++)
                RefreshIndicator(
                  onRefresh: data.refreshTimetable,
                  child: _DayRail(
                    lessonsOn(lessons, weekStart.add(Duration(days: i)), off: data.classFree),
                    day: weekStart.add(Duration(days: i)),
                    now: now,
                    all: lessons,
                    off: data.classFree,
                    loaded: data.lessons.data != null,
                    failed: data.lessons.error != null,
                    exams: exams,
                    classFree: data.classFree.contains(weekStart.add(Duration(days: i))),
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
  final List<Lesson> all; // the whole week, for what comes next
  final Set<DateTime> off;
  final bool loaded;
  final bool failed;
  final ExamMatch? exams;
  final bool classFree; // an exam-week day
  const _DayRail(this.lessons,
      {required this.day,
      required this.now,
      required this.all,
      required this.off,
      required this.loaded,
      required this.failed,
      this.exams,
      this.classFree = false});

  /// "No classes on Thu 5 Nov. Next: Mon 9 Nov, 09:00 Multimedia Computing, B-305."
  String _noClasses() {
    final endOfDay = DateTime(day.year, day.month, day.day, 23, 59, 59);
    final next = nextLesson(all, endOfDay.isBefore(now) ? now : endOfDay, (_) => true, off: off);
    final none = 'No classes on ${dayDate(day, now: now)}.';
    if (next == null) return none;
    final l = next.lesson;
    return '$none Next: ${dayDate(next.day, now: now)}, ${l.start} ${l.subject}${l.room.isEmpty ? '' : ', ${l.room}'}.';
  }

  @override
  Widget build(BuildContext context) {
    final examsToday = [
      for (final m in exams?.exams ?? const <MyExam>[])
        if (DateTime(m.exam.start.year, m.exam.start.month, m.exam.start.day) == day) m,
    ];
    if (!loaded && examsToday.isEmpty) {
      // After a failure the row above the days says so: nothing is loading, and
      // with no timetable nothing can be said about this day.
      return ListView(physics: const AlwaysScrollableScrollPhysics(), children: [if (!failed) const SkeletonRows()]);
    }
    if (lessons.isEmpty && examsToday.isEmpty) {
      final what = exams?.period.name.toLowerCase() ?? 'exam';
      return ListView(
        physics: const AlwaysScrollableScrollPhysics(),
        children: [
          EmptyNote(classFree
              ? 'No classes in $what week, and no exam of yours on ${dayDate(day, now: now)}.'
              : _noClasses()),
        ],
      );
    }
    final isToday = DateTime(now.year, now.month, now.day) == day;
    // Classes and exams in time order (an exam first when they start together).
    final sittings = <(DateTime, DateTime, Widget Function(bool past, bool current, bool above, bool below))>[
      for (final m in examsToday)
        (m.exam.start, m.exam.end, (p, c, a, b) => ExamRow(m, exams!.period, now: now, past: p, current: c, lineAbove: a, lineBelow: b)),
      for (final l in lessons)
        (lessonStart(l, day), lessonEnd(l, day), (p, c, a, b) => ClassRow(l,
            past: p, current: c, now: now, showTeacher: true, lineAbove: a, lineBelow: b)),
    ];
    final order = [...sittings.indexed]..sort((x, y) {
        final byTime = x.$2.$1.compareTo(y.$2.$1);
        return byTime != 0 ? byTime : x.$1.compareTo(y.$1);
      });
    // Rows first, then the rail flags (first, last) once their order is known.
    final rows = <Widget Function(bool above, bool below)>[];
    var nowPlaced = !isToday;
    DateTime? lastEnd;
    for (final (_, (start, end, row)) in order) {
      if (lastEnd != null) {
        final gap = start.difference(lastEnd);
        if (gap.inMinutes >= 30) rows.add((a, b) => RailNoteRow('Break ${duration(gap)}', lineAbove: a, lineBelow: b));
      }
      if (!nowPlaced && start.isAfter(now)) {
        rows.add((a, b) => NowRow(now, lineAbove: a, lineBelow: b));
        nowPlaced = true;
      }
      final current = isToday && !start.isAfter(now) && end.isAfter(now);
      if (current) nowPlaced = true; // the class or exam itself says "Now"
      final past = isToday && !end.isAfter(now);
      rows.add((a, b) => row(past, current, a, b));
      lastEnd = lastEnd == null || end.isAfter(lastEnd) ? end : lastEnd;
    }
    if (!nowPlaced) rows.add((a, b) => NowRow(now, lineAbove: a, lineBelow: b));
    return ListView(physics: const AlwaysScrollableScrollPhysics(), children: [
      const SizedBox(height: 8),
      for (final (i, row) in rows.indexed) row(i > 0, i < rows.length - 1),
      const SizedBox(height: 24),
    ]);
  }
}
