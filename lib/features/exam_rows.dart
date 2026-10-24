import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../data/app_data.dart';
import '../data/exams.dart';
import '../data/rail.dart';
import '../ui/format/format.dart';
import '../ui/theme/app_text.dart';
import '../ui/theme/status_colors.dart';
import 'common.dart';
import 'details.dart';
import 'rail_rows.dart';

// An exam on the rails, Schedule and course detail, and its sheet
// (docs/EXAMS.md). Until the university says which room each student sits
// in, a sitting has only the rooms it uses: "B209 or B210".

/// The room the student sits in, once known: the one they set, or the only
/// room the exam uses.
String? examRoom(MyExam m) => m.room ?? (m.exam.rooms.length == 1 ? m.exam.rooms.single : null);

/// "Midterm · B209 or B210", "Midterm · Dr.Sarvar · B305": a sitting's
/// second line. The sheet's note only where it tells sittings apart.
String examLine(MyExam m, ExamPeriod p) => [
      p.name,
      if (m.sittings > 1 && m.exam.read.note.isNotEmpty) m.exam.read.note,
      examRoom(m) ?? roomChoice(m.exam.rooms),
    ].join(' · ');

/// "The timetable lists 2 sittings; check which is yours."
String sittingsLine(MyExam m) => 'The timetable lists ${m.sittings} sittings; check which is yours.';

/// The hero for an exam: in progress, or the next thing today (DESIGN.md 7).
/// The room is the big line; until it is known, that it isn't.
class ExamHero extends StatelessWidget {
  final RailExam entry;
  final ExamPeriod period;
  final DateTime now;
  final bool lineAbove;
  final bool lineBelow;
  const ExamHero(this.entry, this.period, this.now, {super.key, this.lineAbove = true, this.lineBelow = true});

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context);
    final m = entry.exam;
    final e = m.exam;
    final current = entry.role == ClassRole.current;
    final label = current
        ? 'Now · until ${clock(e.end)} · ${duration(e.end.difference(now))} left'
        : 'Next · ${relative(e.start, now: now)}';
    final labelStyle = t.textTheme.labelLarge!.tnum.copyWith(color: t.colorScheme.primary);
    final muted = t.textTheme.bodyMedium?.tnum.copyWith(color: t.colorScheme.onSurfaceVariant);
    final room = examRoom(m);
    return RailRow(
      start: clock(e.start),
      end: clock(e.end),
      node: current ? const RailNode(RailNodeKind.current) : const RailNode(RailNodeKind.ring),
      firstLine: labelStyle,
      lineAbove: lineAbove,
      lineBelow: lineBelow,
      top: 12,
      bottom: 16,
      onTap: () => showExamSheet(context, m, period),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Text(label, style: labelStyle),
        const SizedBox(height: 4),
        FittedBox(
          fit: BoxFit.scaleDown,
          alignment: Alignment.centerLeft,
          child: Text(room ?? (period.roomsAssigned ? 'Room not set' : 'Room not assigned yet'),
              maxLines: 1, style: t.textTheme.displayMedium),
        ),
        const SizedBox(height: 4),
        Text(m.course.name, style: t.textTheme.titleLarge),
        Text([period.name, duration(e.length), if (room == null) roomChoice(e.rooms)].join(' · '), style: muted),
        if (m.sittings > 1) StatusLine(Status.info, sittingsLine(m), padding: const EdgeInsets.only(top: 6)),
      ]),
    );
  }
}

/// An exam as a row: the course, then "Midterm · B209 or B210". On a rail
/// the time column holds its start and end; with [showDay] (course detail,
/// Today's exam list) its start and day. [past] exams are muted (Schedule).
class ExamRow extends StatelessWidget {
  final MyExam exam;
  final ExamPeriod period;
  final DateTime now;
  final bool past;
  final bool current;
  final bool line;
  final bool showDay;
  final bool lineAbove;
  final bool lineBelow;
  const ExamRow(this.exam, this.period,
      {super.key,
      required this.now,
      this.past = false,
      this.current = false,
      this.line = true,
      this.showDay = false,
      this.lineAbove = true,
      this.lineBelow = true});

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context);
    final muted = t.colorScheme.onSurfaceVariant;
    final e = exam.exam;
    final titleStyle = t.textTheme.titleMedium!.copyWith(color: past ? muted : null);
    final labelStyle = t.textTheme.labelLarge!.tnum.copyWith(color: t.colorScheme.primary);
    return RailRow(
      start: clock(e.start),
      end: showDay ? '${weekdayShort(e.start.weekday)} ${e.start.day}' : clock(e.end),
      startColor: past ? muted : null,
      node: current ? const RailNode(RailNodeKind.current) : RailNode(RailNodeKind.ring, past ? muted : null),
      firstLine: current ? labelStyle : titleStyle,
      line: line,
      lineAbove: lineAbove,
      lineBelow: lineBelow,
      top: 10,
      bottom: 10,
      onTap: () => showExamSheet(context, exam, period),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        if (current) Text('Now · until ${clock(e.end)}', style: labelStyle),
        Text(exam.course.name, maxLines: 2, overflow: TextOverflow.ellipsis, style: titleStyle),
        Text(examLine(exam, period), style: t.textTheme.bodyMedium?.tnum.copyWith(color: muted)),
        if (exam.sittings > 1 && !past)
          StatusLine(Status.info, sittingsLine(exam), padding: const EdgeInsets.only(top: 2)),
      ]),
    );
  }
}

/// An exam's details: when, the room or the rooms it uses, what the sheet
/// printed, and the way to set the room once it is known.
Future<void> showExamSheet(BuildContext context, MyExam exam, ExamPeriod period) => showModalBottomSheet<void>(
      context: context,
      showDragHandle: true,
      isScrollControlled: true,
      builder: (_) => _ExamSheet(exam, period),
    );

class _ExamSheet extends StatelessWidget {
  final MyExam exam;
  final ExamPeriod period;
  const _ExamSheet(this.exam, this.period);

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context);
    final data = context.watch<AppData>();
    final now = DateTime.now();
    final e = exam.exam;
    // Read live, so setting the room shows here at once.
    final set = data.prefs.examRooms[e.keyIn(period)];
    final room = set ?? (e.rooms.length == 1 ? e.rooms.single : null);
    final muted = t.textTheme.bodyMedium?.copyWith(color: t.colorScheme.onSurfaceVariant);
    final soon = e.end.isAfter(now) && e.start.difference(now) < const Duration(hours: 48);
    final course = exam.course.eclass;
    String seated(String r) => period.seats[r] == null ? r : '$r (${period.seats[r]} seats)';

    return SafeArea(
      child: SingleChildScrollView(
        padding: const EdgeInsets.fromLTRB(gutter, 0, gutter, 16),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text('${period.name} · ${period.term}', style: muted),
          const SizedBox(height: 8),
          Text(exam.course.name, style: t.textTheme.headlineSmall),
          const SizedBox(height: 16),
          const Divider(),
          const SizedBox(height: 16),
          Text('${dayDate(e.start, now: now)}, ${clock(e.start)}–${clock(e.end)} · ${duration(e.length)}',
              style: t.textTheme.bodyLarge?.tnum),
          if (soon)
            Text(e.start.isAfter(now) ? 'Starts ${relative(e.start, now: now)}' : 'Until ${clock(e.end)}',
                style: muted?.tnum),
          const SizedBox(height: 16),
          if (room != null) ...[
            Text('Room $room', style: t.textTheme.titleMedium?.tnum),
            Text(set != null ? 'You set this room.' : 'The only room this exam uses.', style: muted),
          ] else ...[
            StatusLine(Status.info, period.roomsAssigned ? 'Room not set' : 'Room not assigned yet',
                padding: EdgeInsets.zero),
            const SizedBox(height: 4),
            Text(
                period.roomsAssigned
                    ? 'The university has said which room each student sits in. Set yours once you know it.'
                    : 'The university says later which room each student sits in.',
                style: muted),
          ],
          if (e.rooms.length > 1) ...[
            const SizedBox(height: 8),
            Text('This exam uses ${e.rooms.length} rooms: ${e.rooms.map(seated).join(', ')}.', style: muted?.tnum),
          ],
          if (exam.sittings > 1) StatusLine(Status.info, sittingsLine(exam), padding: const EdgeInsets.only(top: 8)),
          const SizedBox(height: 12),
          Text('On the timetable as “${e.cell}”, slot ${e.slot}.',
              style: t.textTheme.bodySmall?.copyWith(color: t.colorScheme.onSurfaceVariant)),
          const SizedBox(height: 16),
          if (e.rooms.length > 1)
            SizedBox(
              width: double.infinity,
              child: TextButton(
                onPressed: () => _pickRoom(context, set),
                child: Text(set == null ? 'Set my room' : 'Change my room'),
              ),
            ),
          if (course != null)
            SizedBox(
              width: double.infinity,
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

  /// One of the exam's rooms, or none. Nothing is guessed: the student picks
  /// the room the university's list gives them.
  Future<void> _pickRoom(BuildContext context, String? current) async {
    final data = context.read<AppData>();
    const clear = '';
    final picked = await showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Your room'),
        contentPadding: const EdgeInsets.only(top: 16, bottom: 8),
        content: SingleChildScrollView(
          child: RadioGroup<String>(
            groupValue: current,
            onChanged: (r) => Navigator.pop(ctx, r),
            child: Column(mainAxisSize: MainAxisSize.min, children: [
              for (final r in exam.exam.rooms)
                RadioListTile<String>(
                  value: r,
                  title: Text(r, style: Theme.of(ctx).textTheme.bodyLarge?.tnum),
                  subtitle: period.seats[r] == null ? null : Text('${period.seats[r]} seats'),
                  contentPadding: const EdgeInsets.symmetric(horizontal: 16),
                ),
            ]),
          ),
        ),
        actions: [
          if (current != null) TextButton(onPressed: () => Navigator.pop(ctx, clear), child: const Text('Clear')),
          TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Cancel')),
        ],
      ),
    );
    if (picked == null) return;
    data.setExamRoom(exam.exam, period, picked == clear ? null : picked);
  }
}
