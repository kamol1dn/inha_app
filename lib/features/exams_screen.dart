import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../data/app_data.dart';
import '../data/exams.dart';
import '../ui/format/format.dart';
import '../ui/theme/app_text.dart';
import '../ui/theme/status_colors.dart';
import 'common.dart';
import 'exam_rows.dart';
import 'rail_rows.dart';

/// The exam week: the student's exams by day, the courses the timetable has
/// none for, and on request every sitting on the sheet (docs/EXAMS.md).
class ExamsScreen extends StatefulWidget {
  const ExamsScreen({super.key});
  @override
  State<ExamsScreen> createState() => _ExamsScreenState();
}

class _ExamsScreenState extends State<ExamsScreen> {
  bool _every = false;

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context);
    final data = context.watch<AppData>();
    final now = DateTime.now();
    final match = data.exams(now);
    final muted = t.textTheme.bodyMedium?.tnum.copyWith(color: t.colorScheme.onSurfaceVariant);
    if (match == null) {
      return Scaffold(
        appBar: AppBar(title: const Text('Exams')),
        body: ListView(children: const [
          EmptyNote('No exam timetable for now. The next one comes with an app update.'),
        ]),
      );
    }
    final p = match.period;
    final what = p.name.toLowerCase();
    final known = data.lessons.data != null || data.attendance.data != null;
    return Scaffold(
      appBar: AppBar(title: Text('${p.name} exams')),
      body: ListView(children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(gutter, 16, gutter, 4),
          child: Text('${p.term} $what, ${dayRange(p.first, p.last, now: now)}, from the university\'s exam timetable.',
              style: muted),
        ),
        if (!p.roomsAssigned) const StatusLine(Status.info, 'Rooms not assigned yet: each exam shows the rooms it uses.'),
        if (!known)
          const EmptyNote('Your courses come from the timetable and eClass, and neither has loaded yet.')
        else if (match.exams.isEmpty)
          EmptyNote('None of your courses is on the $what timetable.')
        else
          ..._byDay(match.exams, (m) => ExamRow(m, p, now: now, line: false, past: !m.exam.end.isAfter(now)), now),
        if (known && match.unlisted.isNotEmpty) ...[
          const SectionHeader('Not on the timetable'),
          Padding(
            padding: const EdgeInsets.fromLTRB(gutter, 4, gutter, 4),
            child: Text('No $what listed for ${match.unlisted.map((c) => c.name).join(', ')}.',
                style: t.textTheme.bodyMedium),
          ),
        ],
        Padding(
          padding: const EdgeInsets.only(left: 8, top: 16),
          child: Align(
            alignment: Alignment.centerLeft,
            child: TextButton(
              onPressed: () => setState(() => _every = !_every),
              child: Text(_every ? 'Hide other exams' : 'Show every exam'),
            ),
          ),
        ),
        if (_every)
          ..._byDay(
              [for (final e in p.exams) MyExam(StudentCourse(e.course), e)], (m) => _SittingRow(m, p, now: now), now),
        Padding(
          padding: const EdgeInsets.fromLTRB(gutter, 16, gutter, 24),
          child: Text('From “${p.source}”.',
              style: t.textTheme.bodySmall?.copyWith(color: t.colorScheme.onSurfaceVariant)),
        ),
      ]),
    );
  }

  static List<Widget> _byDay(List<MyExam> exams, Widget Function(MyExam) row, DateTime now) {
    final days = <DateTime, List<MyExam>>{};
    for (final m in exams) {
      days.putIfAbsent(DateTime(m.exam.start.year, m.exam.start.month, m.exam.start.day), () => []).add(m);
    }
    return [
      for (final e in days.entries) ...[
        SectionHeader(dayHeader(e.key, now: now)),
        for (final m in e.value) row(m),
      ],
    ];
  }
}

/// A sitting on the sheet, whoever it is for: the course, then who it is
/// for and the rooms it uses.
class _SittingRow extends StatelessWidget {
  final MyExam exam;
  final ExamPeriod period;
  final DateTime now;
  const _SittingRow(this.exam, this.period, {required this.now});

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context);
    final e = exam.exam;
    final past = !e.end.isAfter(now);
    final muted = t.colorScheme.onSurfaceVariant;
    final title = t.textTheme.titleSmall!.copyWith(color: past ? muted : null);
    return RailRow(
      start: clock(e.start),
      end: clock(e.end),
      startColor: past ? muted : null,
      firstLine: title,
      line: false,
      onTap: () => showExamSheet(context, exam, period),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Text(e.course, style: title),
        Text(
            [
              if (e.read.uk) 'UK programme',
              if (e.read.note.isNotEmpty) e.read.note,
              roomChoice(e.rooms),
            ].join(' · '),
            style: t.textTheme.bodyMedium?.tnum.copyWith(color: muted)),
      ]),
    );
  }
}
