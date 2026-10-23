import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';

import '../data/absence.dart';
import '../data/app_data.dart';
import '../models/models.dart';
import '../ui/theme/app_text.dart';
import 'common.dart';

/// Absences as tally marks (DESIGN.md 8, Courses): one stroke per absence
/// in gates of five, the used ones in ink (the status colour in trouble) and
/// the ones still allowed faint. Without a limit only the used strokes are
/// drawn. Always shown next to its words; more than [maxMarks] strokes are
/// left to the words alone.
class Tally extends StatelessWidget {
  final AbsenceState state;
  final double height;
  const Tally(this.state, {super.key, this.height = 16});

  static const maxMarks = 20;

  int get _total => state.limit == null ? state.used : (state.used > state.limit! ? state.used : state.limit!);

  @override
  Widget build(BuildContext context) {
    final total = _total;
    if (total < 1 || total > maxMarks) return const SizedBox.shrink();
    final t = Theme.of(context);
    final status = state.status;
    final used = status == null ? t.colorScheme.onSurface : statusColors(context).of(status).fg;
    final scale = height / 16;
    return Semantics(
      label: state.limit == null
          ? '${state.used} ${state.used == 1 ? 'absence' : 'absences'}'
          : '${state.used} of ${state.limit} allowed absences used',
      excludeSemantics: true,
      child: CustomPaint(
        size: Size(_TallyPainter.widthFor(total) * scale, height),
        painter: _TallyPainter(total, state.used, used, t.colorScheme.outlineVariant, scale),
      ),
    );
  }
}

class _TallyPainter extends CustomPainter {
  final int total, used;
  final Color usedColor, faintColor;
  final double scale;
  _TallyPainter(this.total, this.used, this.usedColor, this.faintColor, this.scale);

  // At 16dp tall: strokes 7 apart, a gate's diagonal 2 past its ends, gates 33 apart.
  static const _step = 7.0, _pitch = 33.0, _left = 3.0;

  static double widthFor(int n) {
    final gates = (n - 1) ~/ 5 + 1, last = n - 5 * (gates - 1);
    final x0 = _left + (gates - 1) * _pitch;
    return (last == 5 ? x0 + 3 * _step + 2 : x0 + (last - 1) * _step) + 3;
  }

  @override
  void paint(Canvas canvas, Size size) {
    canvas.scale(scale);
    final h = size.height / scale;
    Paint pen(int i) => Paint()
      ..color = i < used ? usedColor : faintColor
      ..strokeWidth = 2
      ..strokeCap = StrokeCap.round;
    for (var i = 0; i < total; i++) {
      final x0 = _left + (i ~/ 5) * _pitch;
      if (i % 5 == 4) {
        canvas.drawLine(Offset(x0 - 2, h * 0.72), Offset(x0 + 3 * _step + 2, h * 0.28), pen(i));
      } else {
        final x = x0 + (i % 5) * _step;
        canvas.drawLine(Offset(x, 1), Offset(x, h - 1), pen(i));
      }
    }
  }

  @override
  bool shouldRepaint(_TallyPainter old) =>
      old.total != total || old.used != used || old.usedColor != usedColor || old.faintColor != faintColor;
}

/// The tally over its count, for the right edge of a row: "6 of 8".
class TallyCount extends StatelessWidget {
  final AbsenceState state;
  const TallyCount(this.state, {super.key});

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context);
    final status = state.status;
    final color = status == null ? t.colorScheme.onSurfaceVariant : statusColors(context).of(status).fg;
    final count = state.limit == null ? '${state.used}' : '${state.used} of ${state.limit}';
    return Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.end, children: [
      Tally(state),
      const SizedBox(height: 4),
      Text(count, style: t.textTheme.numeral.copyWith(color: color)),
    ]);
  }
}

/// Settings → Absence limits: every eClass course that takes attendance,
/// with its limit; tapping one asks for the number.
class AbsenceLimitsScreen extends StatelessWidget {
  const AbsenceLimitsScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final data = context.watch<AppData>();
    final t = Theme.of(context);
    final limits = data.prefs.absenceLimits;
    final courses = [...?data.attendance.data?.value.where((c) => c.classes.isNotEmpty)]
      ..sort((a, b) => a.course.name.compareTo(b.course.name));
    return Scaffold(
      appBar: AppBar(title: const Text('Absence limits')),
      body: ListView(children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(gutter, 16, gutter, 12),
          child: Text(
            "How many absences each course allows. eClass doesn't publish this, so take it from the "
            'syllabus. With a limit set, Today and Courses show how many are left.',
            style: t.textTheme.bodyMedium?.copyWith(color: t.colorScheme.onSurfaceVariant),
          ),
        ),
        if (courses.isEmpty)
          EmptyNote('No eClass course takes attendance yet. Sign in to eClass to see them.',
              action: 'Sign in', onAction: () => openSettings(context)),
        for (final c in courses) ...[
          const Rule(),
          InkWell(
            onTap: () => editAbsenceLimit(context, c.course),
            child: Padding(
              padding: const EdgeInsets.fromLTRB(gutter, 12, gutter, 12),
              child: Row(children: [
                Expanded(
                  child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    Text(c.course.name, maxLines: 2, overflow: TextOverflow.ellipsis, style: t.textTheme.titleMedium),
                    const SizedBox(height: 2),
                    Text(
                      limits[c.course.id] == null
                          ? 'Not set · ${AbsenceState.of(c, limits).used} so far'
                          : AbsenceState.of(c, limits).line,
                      style: t.textTheme.bodyMedium?.tnum.copyWith(color: t.colorScheme.onSurfaceVariant),
                    ),
                  ]),
                ),
                const SizedBox(width: 16),
                Text(limits[c.course.id]?.toString() ?? '', style: t.textTheme.titleMedium?.tnum),
              ]),
            ),
          ),
        ],
        const SizedBox(height: 24),
      ]),
    );
  }
}

/// Asks for a course's allowed absences. No IUT source publishes them, so
/// the student types the number from the syllabus; empty clears it.
Future<void> editAbsenceLimit(BuildContext context, Course course) async {
  final data = context.read<AppData>();
  final result = await showDialog<int>(
    context: context,
    builder: (_) => _LimitDialog(course, data.prefs.absenceLimits[course.id]),
  );
  if (result == null) return; // cancelled
  data.setAbsenceLimit(course.id, result < 0 ? null : result);
}

/// Pops the limit, -1 to clear it, or null when cancelled. Owns its text
/// controller, which must outlive the closing animation.
class _LimitDialog extends StatefulWidget {
  final Course course;
  final int? current;
  const _LimitDialog(this.course, this.current);

  @override
  State<_LimitDialog> createState() => _LimitDialogState();
}

class _LimitDialogState extends State<_LimitDialog> {
  late final _field = TextEditingController(text: widget.current?.toString() ?? '');

  @override
  void dispose() {
    _field.dispose();
    super.dispose();
  }

  void _save() => Navigator.pop(context, int.tryParse(_field.text) ?? -1);

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context);
    return AlertDialog(
      title: const Text('Allowed absences'),
      content: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
        Text(widget.course.name, style: t.textTheme.bodyMedium),
        const SizedBox(height: 16),
        TextField(
          controller: _field,
          autofocus: true,
          keyboardType: TextInputType.number,
          inputFormatters: [FilteringTextInputFormatter.digitsOnly, LengthLimitingTextInputFormatter(2)],
          style: t.textTheme.bodyLarge?.tnum,
          decoration: const InputDecoration(
            border: OutlineInputBorder(),
            helperText: 'From the syllabus. Leave empty if it has none.',
            helperMaxLines: 2,
          ),
          onSubmitted: (_) => _save(),
        ),
      ]),
      actions: [
        TextButton(onPressed: () => Navigator.pop(context), child: const Text('Cancel')),
        TextButton(onPressed: _save, child: const Text('Save')),
      ],
    );
  }
}
