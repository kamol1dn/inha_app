import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../data/absence.dart';
import '../data/rail.dart';
import '../data/urgency.dart';
import '../models/models.dart';
import '../ui/format/format.dart';
import '../ui/theme/app_text.dart';
import '../ui/theme/status_colors.dart';
import 'common.dart';
import 'deadline_tile.dart';
import 'details.dart';

// The day rail's rows (DESIGN.md 5 and 7): a time column, a node column with
// the rail line through it, and the row's content.

enum RailNodeKind { none, now, ring, current, dot }

class RailNode {
  final RailNodeKind kind;
  final Color? color; // ring and dot; ink by default
  const RailNode(this.kind, [this.color]);
  static const none = RailNode(RailNodeKind.none);
}

/// The time column's width: 16 of gutter plus room for "00:00" at the
/// current text scale, at least 48.
double railTimeWidth(BuildContext context) {
  final painter = TextPainter(
    text: TextSpan(text: '00:00', style: Theme.of(context).textTheme.numeral),
    textScaler: MediaQuery.textScalerOf(context),
    textDirection: TextDirection.ltr,
  )..layout();
  final w = painter.width;
  painter.dispose();
  return 16 + math.max(48.0, w.ceilToDouble() + 2);
}

const _nodeColumn = 28.0;

/// One rail row. [firstLine] is the style of the content's first line; the
/// node and the start time are centred on it. With [line] false (Deadlines,
/// course detail) the row keeps the columns but draws no rail.
class RailRow extends StatelessWidget {
  final String? start;
  final String? end;
  final Color? startColor;
  final RailNode node;
  final TextStyle firstLine;
  final Widget child;
  final VoidCallback? onTap;
  final bool lineAbove;
  final bool lineBelow;
  final bool line;
  final double top;
  final double bottom;

  const RailRow({
    super.key,
    this.start,
    this.end,
    this.startColor,
    this.node = RailNode.none,
    required this.firstLine,
    required this.child,
    this.onTap,
    this.lineAbove = true,
    this.lineBelow = true,
    this.line = true,
    this.top = 8,
    this.bottom = 8,
  });

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context);
    final scaler = MediaQuery.textScalerOf(context);
    final timeWidth = railTimeWidth(context);
    final nodeY = top + scaler.scale(firstLine.fontSize!) * firstLine.height! / 2;
    final numeral = t.textTheme.numeral;
    final timeTop = math.max(0.0, nodeY - scaler.scale(numeral.fontSize!) * numeral.height! / 2);
    final row = ConstrainedBox(
      constraints: const BoxConstraints(minHeight: 48),
      child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
        SizedBox(
          width: timeWidth,
          child: Padding(
            padding: EdgeInsets.only(top: timeTop),
            child: Column(crossAxisAlignment: CrossAxisAlignment.end, children: [
              if (start != null) Text(start!, style: numeral.copyWith(color: startColor)),
              if (end != null)
                Text(end!, style: t.textTheme.numeralSmall.copyWith(color: t.colorScheme.onSurfaceVariant)),
            ]),
          ),
        ),
        const SizedBox(width: _nodeColumn),
        Expanded(child: Padding(padding: EdgeInsets.only(top: top, bottom: bottom), child: child)),
        const SizedBox(width: gutter),
      ]),
    );
    final painted = CustomPaint(
      painter: _RailPainter(
        x: timeWidth + _nodeColumn / 2,
        nodeY: nodeY,
        node: node,
        lineAbove: line && lineAbove,
        lineBelow: line && lineBelow,
        lineColor: t.colorScheme.outlineVariant,
        ink: t.colorScheme.onSurface,
        accent: t.colorScheme.primary,
        paper: t.colorScheme.surface,
      ),
      child: row,
    );
    return onTap == null ? painted : InkWell(onTap: onTap, child: painted);
  }
}

class _RailPainter extends CustomPainter {
  final double x, nodeY;
  final RailNode node;
  final bool lineAbove, lineBelow;
  final Color lineColor, ink, accent, paper;
  _RailPainter({
    required this.x,
    required this.nodeY,
    required this.node,
    required this.lineAbove,
    required this.lineBelow,
    required this.lineColor,
    required this.ink,
    required this.accent,
    required this.paper,
  });

  @override
  void paint(Canvas canvas, Size size) {
    final line = Paint()
      ..color = lineColor
      ..strokeWidth = 2;
    if (lineAbove) canvas.drawLine(Offset(x, 0), Offset(x, nodeY), line);
    if (lineBelow) canvas.drawLine(Offset(x, nodeY), Offset(x, size.height), line);
    final c = Offset(x, nodeY);
    switch (node.kind) {
      case RailNodeKind.none:
        break;
      case RailNodeKind.now:
        canvas.drawCircle(c, 5, Paint()..color = accent);
      case RailNodeKind.current:
        canvas.drawCircle(c, 6, Paint()..color = accent);
      case RailNodeKind.ring:
        canvas.drawCircle(c, 6, Paint()..color = paper);
        canvas.drawCircle(
            c,
            5,
            Paint()
              ..color = node.color ?? ink
              ..style = PaintingStyle.stroke
              ..strokeWidth = 2);
      case RailNodeKind.dot:
        canvas.drawCircle(c, 4, Paint()..color = node.color ?? ink);
    }
  }

  @override
  bool shouldRepaint(_RailPainter old) =>
      old.x != x ||
      old.nodeY != nodeY ||
      old.node.kind != node.kind ||
      old.node.color != node.color ||
      old.lineAbove != lineAbove ||
      old.lineBelow != lineBelow ||
      old.lineColor != lineColor ||
      old.accent != accent;
}

/// "13:20 ● Now ────": the current time on a rail.
class NowRow extends StatelessWidget {
  final DateTime now;
  final bool lineAbove;
  final bool lineBelow;
  const NowRow(this.now, {super.key, this.lineAbove = false, this.lineBelow = true});

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context);
    final accent = t.colorScheme.primary;
    final style = t.textTheme.labelLarge!.copyWith(color: accent);
    return RailRow(
      start: clock(now),
      startColor: accent,
      node: const RailNode(RailNodeKind.now),
      firstLine: style,
      lineAbove: lineAbove,
      lineBelow: lineBelow,
      top: 14,
      bottom: 0,
      child: Row(children: [
        Text('Now', style: style),
        const SizedBox(width: 8),
        Expanded(child: Container(height: 1, color: accent)),
      ]),
    );
  }
}

/// A day header on a rail ("Tomorrow", "Sun 25 Oct"), or Overdue's.
class RailHeader extends StatelessWidget {
  final String text;
  final Status? status;
  final bool lineAbove;
  final bool lineBelow;
  const RailHeader(this.text, {super.key, this.status, this.lineAbove = true, this.lineBelow = true});

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context);
    final fg = status == null ? null : statusColors(context).of(status!).fg;
    final style = t.textTheme.titleMedium!.copyWith(color: fg);
    return RailRow(
      firstLine: style,
      lineAbove: lineAbove,
      lineBelow: lineBelow,
      top: 16,
      bottom: 4,
      child: Row(children: [
        if (status != null) ...[Icon(statusIcons[status], size: 18, color: fg), const SizedBox(width: 6)],
        Expanded(child: Text(text, style: style)),
      ]),
    );
  }
}

/// A muted line on a rail: "Free for the rest of the day", "Break 1 h 10 min".
class RailNoteRow extends StatelessWidget {
  final String text;
  final String? at;
  final bool lineAbove;
  final bool lineBelow;
  const RailNoteRow(this.text, {super.key, this.at, this.lineAbove = true, this.lineBelow = true});

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context);
    final style = t.textTheme.bodyMedium!.copyWith(color: t.colorScheme.onSurfaceVariant);
    return RailRow(
      start: at,
      startColor: t.colorScheme.onSurfaceVariant,
      firstLine: style,
      lineAbove: lineAbove,
      lineBelow: lineBelow,
      top: 12,
      bottom: 12,
      child: Text(text, style: style),
    );
  }
}

/// "6 of 8 absences used · 2 left": a course's attendance warning.
String absenceWarning(AbsenceState a) {
  final left = a.left;
  if (left == null) return a.line;
  if (left > 0) return '${a.line} · $left left';
  if (left == 0) return '${a.line} · none left';
  return '${a.line} · over by ${-left}';
}

/// The hero: the class in progress or the next one today (DESIGN.md 7).
class HeroClass extends StatelessWidget {
  final RailClass entry;
  final DateTime now;
  final VoidCallback? onTap;
  final bool lineAbove;
  final bool lineBelow;
  const HeroClass(this.entry, this.now, {super.key, this.onTap, this.lineAbove = true, this.lineBelow = true});

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context);
    final l = entry.lesson;
    final current = entry.role == ClassRole.current;
    final label = current
        ? 'Now · until ${l.end} · ${duration(entry.end.difference(now))} left'
        : 'Next · ${relative(entry.start, now: now)}';
    final labelStyle = t.textTheme.labelLarge!.tnum.copyWith(color: t.colorScheme.primary);
    final meta = [l.kind, l.teacher].where((s) => s.isNotEmpty).join(' · ');
    final trouble = entry.trouble;
    return RailRow(
      start: l.start,
      end: l.end,
      node: current ? const RailNode(RailNodeKind.current) : const RailNode(RailNodeKind.ring),
      firstLine: labelStyle,
      lineAbove: lineAbove,
      lineBelow: lineBelow,
      top: 12,
      bottom: 16,
      onTap: onTap ?? () => openLesson(context, l),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Text(label, style: labelStyle),
        const SizedBox(height: 4),
        FittedBox(
          fit: BoxFit.scaleDown,
          alignment: Alignment.centerLeft,
          child: Text(l.room.isEmpty ? 'Room not set' : l.room, maxLines: 1, style: t.textTheme.displayMedium),
        ),
        const SizedBox(height: 4),
        Text(l.subject, style: t.textTheme.titleLarge),
        if (meta.isNotEmpty)
          Text(meta, style: t.textTheme.bodyMedium?.copyWith(color: t.colorScheme.onSurfaceVariant)),
        if (trouble != null)
          StatusLine(trouble.status!, absenceWarning(trouble), padding: const EdgeInsets.only(top: 6)),
      ]),
    );
  }
}

/// A class as an ordinary rail row: the course, then room and kind. [past]
/// classes are muted (Schedule).
class ClassRow extends StatelessWidget {
  final Lesson lesson;
  final AbsenceState? trouble;
  final bool past;
  final bool current;
  final DateTime? now; // for the "Now · until" label when [current]
  final bool showTeacher;
  final bool lineAbove;
  final bool lineBelow;
  const ClassRow(this.lesson,
      {super.key,
      this.trouble,
      this.past = false,
      this.current = false,
      this.now,
      this.showTeacher = false,
      this.lineAbove = true,
      this.lineBelow = true});

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context);
    final muted = t.colorScheme.onSurfaceVariant;
    final l = lesson;
    final titleStyle = t.textTheme.titleMedium!.copyWith(color: past ? muted : null);
    final labelStyle = t.textTheme.labelLarge!.tnum.copyWith(color: t.colorScheme.primary);
    final meta = [l.room, l.kind, if (showTeacher) l.teacher].where((s) => s.isNotEmpty).join(' · ');
    return RailRow(
      start: l.start,
      end: l.end,
      startColor: past ? muted : null,
      node: current
          ? const RailNode(RailNodeKind.current)
          : RailNode(RailNodeKind.ring, past ? muted : null),
      firstLine: current ? labelStyle : titleStyle,
      lineAbove: lineAbove,
      lineBelow: lineBelow,
      top: 10,
      bottom: 10,
      onTap: () => openLesson(context, l),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        if (current && now != null) Text('Now · until ${l.end}', style: labelStyle),
        Text(l.subject, maxLines: 2, overflow: TextOverflow.ellipsis, style: titleStyle),
        if (meta.isNotEmpty) Text(meta, style: t.textTheme.bodyMedium?.tnum.copyWith(color: muted)),
        if (trouble case final a?)
          StatusLine(a.status!, absenceWarning(a), padding: const EdgeInsets.only(top: 2)),
      ]),
    );
  }
}

/// A deadline or VOD window at its due time (DESIGN.md 7 and 8): on Today's
/// rail, and with [line] false on Deadlines and course detail. With
/// [showDay] the day goes under the time.
class DueRow extends StatelessWidget {
  final Deadline deadline;
  final List<CourseAttendance> attendance;
  final DateTime now;
  final bool line;
  final bool showDay;
  final bool lineAbove;
  final bool lineBelow;
  const DueRow(this.deadline,
      {super.key,
      required this.attendance,
      required this.now,
      this.line = true,
      this.showDay = false,
      this.lineAbove = true,
      this.lineBelow = true});

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context);
    final d = deadline;
    final done = isDone(d, attendance);
    final status = done ? null : deadlineStatus(d, now);
    final fg = status == null ? null : statusColors(context).of(status).fg;
    final muted = t.textTheme.bodyMedium!.copyWith(color: t.colorScheme.onSurfaceVariant);
    final vod = vodFor(d, attendance);
    final state = dueState(d, vod);
    final course = d.courseName;
    final titleStyle = t.textTheme.titleSmall!;
    return RailRow(
      start: clock(d.end),
      end: showDay ? '${weekdayShort(d.end.weekday)} ${d.end.day}' : null,
      startColor: fg,
      node: RailNode(RailNodeKind.dot, fg),
      firstLine: titleStyle,
      line: line,
      lineAbove: lineAbove,
      lineBelow: lineBelow,
      onTap: () => showDeadlineSheet(context, d),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Text(rowTitle(d.title), maxLines: 2, overflow: TextOverflow.ellipsis, style: titleStyle),
        if (done)
          StatusLine(Status.ok, d.kind == DeadlineKind.vod ? 'Watched' : doneText(d), padding: EdgeInsets.zero)
        else if (status != null)
          StatusLine(status, dueWarning(d, vod, now), padding: EdgeInsets.zero)
        else
          Text([state, course].where((s) => s.isNotEmpty).join(' · '),
              maxLines: 1, overflow: TextOverflow.ellipsis, style: muted),
        if ((done || status != null) && course.isNotEmpty)
          Text(course, maxLines: 1, overflow: TextOverflow.ellipsis, style: muted),
      ]),
    );
  }
}

/// "Not submitted", "Not attempted", "62% watched", "Closes": what is left
/// to do, for a row's second line.
String dueState(Deadline d, VodProgress? vod) => switch (d.kind) {
      DeadlineKind.assignment => 'Not submitted',
      DeadlineKind.quiz => 'Not attempted',
      DeadlineKind.vod => vod == null ? 'Closes' : 'Closes · ${vod.percent.floor()}% watched',
      _ => '',
    };

/// The status line of an urgent item: "Due in 5 h · not submitted",
/// "Overdue 2 h · not attempted", "62% watched, 21 min left".
String dueWarning(Deadline d, VodProgress? vod, DateTime now) {
  if (d.kind == DeadlineKind.vod) {
    if (vod == null) return 'Closes ${relative(d.end, now: now)} · no watch progress yet';
    final left = (vod.length.inMinutes * (100 - vod.percent) / 100).ceil();
    return vod.percent < 1 ? 'Not started, $left min' : '${vod.percent.floor()}% watched, $left min left';
  }
  final rel = relative(d.end, now: now);
  final when = d.end.isBefore(now) ? rel : 'Due $rel';
  final state = switch (d.kind) {
    DeadlineKind.assignment => 'not submitted',
    DeadlineKind.quiz => 'not attempted',
    _ => '',
  };
  return state.isEmpty ? when : '$when · $state';
}

/// "today 14:00", "tomorrow 13:00", "Mon 13:00": when a class is, from [now].
String classWhen(DateTime day, Lesson l, DateTime now) {
  final h = dayHeader(day, now: now);
  if (h == 'Today' || h == 'Tomorrow') return '${h.toLowerCase()} ${l.start}';
  return '${weekdayShort(day.weekday)} ${l.start}';
}

/// "Today 14:00" from "today 14:00".
String capitalized(String s) => s.isEmpty ? s : s[0].toUpperCase() + s.substring(1);
