import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';

import '../data/absence.dart';
import '../data/app_data.dart';
import '../models/models.dart';
import '../ui/theme/app_text.dart';
import 'common.dart';

/// One 12x6 cell per allowed absence, used ones filled (DESIGN.md 8).
/// Neutral while within the limit, the status colour once in trouble; over
/// the limit every cell is danger. Not drawn for limits too long to read.
class AbsenceBar extends StatelessWidget {
  final AbsenceState state;
  const AbsenceBar(this.state, {super.key});

  static const maxCells = 20;

  @override
  Widget build(BuildContext context) {
    final limit = state.limit;
    if (limit == null || limit < 1 || limit > maxCells) return const SizedBox.shrink();
    final t = Theme.of(context);
    final status = state.status;
    final used = status == null ? t.colorScheme.onSurfaceVariant : statusColors(context).of(status).fg;
    final over = state.used > limit;
    return Semantics(
      label: '${state.used} of $limit allowed absences used',
      excludeSemantics: true,
      child: Row(mainAxisSize: MainAxisSize.min, children: [
        for (var i = 0; i < limit; i++) ...[
          if (i > 0) const SizedBox(width: 2),
          Container(
            width: 12,
            height: 6,
            decoration: BoxDecoration(
              color: over || i < state.used ? used : t.colorScheme.outlineVariant,
              borderRadius: BorderRadius.circular(2),
            ),
          ),
        ],
      ]),
    );
  }
}

/// The bar next to its words: "▮▮▮▯ 3 of 4 absences used".
class AbsenceLine extends StatelessWidget {
  final AbsenceState state;
  final TextStyle? style;
  const AbsenceLine(this.state, {super.key, this.style});

  @override
  Widget build(BuildContext context) {
    final text = Text(state.line, style: style);
    final limit = state.limit;
    if (limit == null || limit < 1 || limit > AbsenceBar.maxCells) return text;
    return Row(children: [
      AbsenceBar(state),
      const SizedBox(width: 8),
      Flexible(child: text),
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
          padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
          child: Text(
            'How many absences each course allows. eClass doesn\'t publish this, so take it from the '
            'syllabus. With a limit set, Today and Courses show how many are left.',
            style: t.textTheme.bodyMedium?.copyWith(color: t.colorScheme.onSurfaceVariant),
          ),
        ),
        if (courses.isEmpty)
          const Padding(
            padding: EdgeInsets.all(16),
            child: Text('No eClass course takes attendance yet. Sign in to eClass in Settings to see them.'),
          ),
        for (final (i, c) in courses.indexed) ...[
          if (i > 0) const Divider(indent: 16),
          ListTile(
            title: Text(c.course.name, maxLines: 1, overflow: TextOverflow.ellipsis),
            subtitle: Text(
              limits[c.course.id] == null
                  ? 'Not set · ${AbsenceState.of(c, limits).used} so far'
                  : AbsenceState.of(c, limits).line,
              style: t.textTheme.bodyMedium?.tnum.copyWith(color: t.colorScheme.onSurfaceVariant),
            ),
            trailing: Text(limits[c.course.id]?.toString() ?? '', style: t.textTheme.titleMedium?.tnum),
            onTap: () => editAbsenceLimit(context, c.course),
          ),
        ],
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
