import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';

import '../data/app_data.dart';
import '../data/scores.dart';
import '../models/models.dart';
import '../services/eclass/eclass_links.dart';
import '../ui/theme/app_text.dart';
import 'common.dart';

void openScores(BuildContext context, Course course) => Navigator.of(context)
    .push(MaterialPageRoute(builder: (_) => CourseScoresScreen(courseId: course.id, name: course.name)));

/// One line for a course's marks, for the rows that lead here: "2 of 8 marked".
String markedLine(CourseGrades g) {
  final marked = g.items.where((i) => i.marked).length;
  return marked == 0 ? 'Nothing marked yet' : '$marked of ${g.items.length} marked';
}

/// A course's accumulated score and how much is marked, leading to its scores.
class ScoresRow extends StatelessWidget {
  final CourseGrades g;
  final bool showCourse;
  const ScoresRow(this.g, {super.key, this.showCourse = false});

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context);
    final muted = t.textTheme.bodyMedium!.tnum.copyWith(color: t.colorScheme.onSurfaceVariant);
    final score = CourseScore.of(g);
    return InkWell(
      onTap: () => openScores(context, g.course),
      child: ConstrainedBox(
        constraints: const BoxConstraints(minHeight: 56),
        child: Padding(
          padding: const EdgeInsets.fromLTRB(gutter, 8, gutter, 8),
          child: Row(children: [
            Expanded(
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                if (showCourse) Text(g.course.name, maxLines: 2, overflow: TextOverflow.ellipsis, style: t.textTheme.bodyLarge),
                Text(markedLine(g), style: muted),
              ]),
            ),
            const SizedBox(width: 16),
            if (score != null) Text(score.line, style: t.textTheme.titleMedium?.tnum),
            Icon(Icons.chevron_right, color: t.colorScheme.onSurfaceVariant),
          ]),
        ),
      ),
    );
  }
}

/// A course's marks from eClass: the accumulated score, each category with its
/// weight, and what-if scores on whatever is still open (DESIGN.md 8, Scores).
class CourseScoresScreen extends StatefulWidget {
  final int courseId;
  final String name; // shown while the course is looked up
  const CourseScoresScreen({super.key, required this.courseId, required this.name});

  @override
  State<CourseScoresScreen> createState() => _CourseScoresScreenState();
}

class _CourseScoresScreenState extends State<CourseScoresScreen> {
  final Map<String, double> _whatIf = {};

  /// Part of each what-if field's key, so Clear empties them all.
  int _round = 0;

  @override
  Widget build(BuildContext context) {
    final data = context.watch<AppData>();
    final t = Theme.of(context);
    final muted = t.textTheme.bodyMedium!.tnum.copyWith(color: t.colorScheme.onSurfaceVariant);
    final g = data.gradesOf(widget.courseId);
    final score = g == null ? null : CourseScore.of(g);
    return HeadingScaffold(
      title: widget.name,
      body: (heading) => RefreshIndicator(
        onRefresh: data.refreshEclass,
        child: ListView(physics: const AlwaysScrollableScrollPhysics(), children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(gutter, 16, gutter, 0),
            child: Text(widget.name, key: heading, style: t.textTheme.headlineSmall),
          ),
          SourceError(data.courseGrades, 'eClass', onRetry: data.refreshEclass),
          if (g == null)
            data.courseGrades.data == null && data.courseGrades.error == null
                ? const SkeletonRows(timeColumn: false)
                : const EmptyNote('eClass has no marks for this course.')
          else if (score != null) ...[
            _total(context, g, score, muted),
            ..._counted(context, score, muted),
            if (score.uncounted.isNotEmpty) ...[
              const SectionHeader('Not counted in the total'),
              ..._plainRows(context, score.uncounted, muted),
            ],
          ] else
            ..._unweighted(context, g, muted),
          if (g != null)
            Padding(
              padding: const EdgeInsets.only(left: 8, top: 8),
              child: TextButton(
                onPressed: () => openUrl(
                    context,
                    g.source == GradeSource.gradebook
                        ? eclassGradesUrl(widget.courseId)
                        : eclassCourseUrl(widget.courseId)),
                child: const Text('Open in eClass'),
              ),
            ),
          const SizedBox(height: 24),
        ]),
      ),
    );
  }

  Widget _total(BuildContext context, CourseGrades g, CourseScore score, TextStyle muted) {
    final t = Theme.of(context);
    final own = eclassTotalLine(g, score);
    final open = score.lines.where((l) => !l.marked && _whatIf.containsKey(l.id));
    return Padding(
      padding: const EdgeInsets.fromLTRB(gutter, 20, gutter, 0),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Wrap(crossAxisAlignment: WrapCrossAlignment.end, spacing: 8, children: [
          Text(plainNumber(score.accumulated), style: t.textTheme.headlineMedium),
          Padding(
            padding: const EdgeInsets.only(bottom: 6),
            child: Text('of ${plainNumber(score.outOf)} so far', style: muted),
          ),
        ]),
        Text(
            '${plainNumber(score.markedWorth)} points marked · '
            '${plainNumber(score.openWorth)} still open · best possible ${plainNumber(score.best)}',
            style: muted),
        if (own != null) Text(own, style: muted),
        if (open.isNotEmpty)
          Row(crossAxisAlignment: CrossAxisAlignment.center, children: [
            Expanded(
              child: Text('With these scores: ${score.ofValue(score.withScores(_whatIf))}',
                  style: t.textTheme.titleSmall?.tnum),
            ),
            TextButton(
              onPressed: () => setState(() {
                _whatIf.clear();
                _round++;
              }),
              child: const Text('Clear'),
            ),
          ]),
      ]),
    );
  }

  /// The lines by category, in eClass's order, each category with its weight.
  List<Widget> _counted(BuildContext context, CourseScore score, TextStyle muted) {
    final byCategory = <String, List<ScoreLine>>{};
    for (final l in score.lines) {
      byCategory.putIfAbsent(l.category, () => []).add(l);
    }
    return [
      for (final MapEntry(key: category, value: lines) in byCategory.entries) ...[
        SectionHeader(category.isEmpty
            ? 'Other'
            : '$category · ${plainNumber(lines.fold(0.0, (s, l) => s + l.worth))} points'),
        for (final (i, l) in lines.indexed) ...[
          if (i > 0) const Rule(),
          _LineRow(
            line: l,
            fieldKey: ValueKey('${l.id}/$_round'),
            onScore: (v) => setState(() => v == null ? _whatIf.remove(l.id) : _whatIf[l.id] = v),
            muted: muted,
          ),
        ],
      ],
    ];
  }

  /// A course with no weights to add up: the marks as they are.
  List<Widget> _unweighted(BuildContext context, CourseGrades g, TextStyle muted) {
    final byCategory = <String, List<GradeItem>>{};
    for (final i in g.items) {
      byCategory.putIfAbsent(i.category, () => []).add(i);
    }
    return [
      Padding(
        padding: const EdgeInsets.fromLTRB(gutter, 16, gutter, 0),
        child: Text(
          switch (g.source) {
            GradeSource.gradebook => "eClass doesn't show weights for this course yet, so there is no score to add up.",
            GradeSource.activities => 'This course keeps its grades page closed. These marks come from its '
                'assignments and quizzes, without weights to add up.',
            GradeSource.none => 'This course keeps its grades page closed and has no assignments or quizzes in eClass.',
          },
          style: Theme.of(context).textTheme.bodyLarge,
        ),
      ),
      if (eclassTotalLine(g, null) case final own?)
        Padding(
          padding: const EdgeInsets.fromLTRB(gutter, 4, gutter, 0),
          child: Text(own, style: muted),
        ),
      for (final MapEntry(key: category, value: items) in byCategory.entries) ...[
        SectionHeader(category.isEmpty ? 'Other' : category),
        ..._plainRows(context, items, muted),
      ],
    ];
  }

  List<Widget> _plainRows(BuildContext context, List<GradeItem> items, TextStyle muted) => [
        for (final (i, item) in items.indexed) ...[
          if (i > 0) const Rule(),
          _row(context, name: item.name, detail: null, trailing: _mark(context, item, muted)),
        ],
      ];
}

Widget _mark(BuildContext context, GradeItem item, TextStyle muted) => item.marked
    ? Text(item.score, style: Theme.of(context).textTheme.titleMedium?.tnum)
    : Text('Not marked', style: muted);

Widget _row(BuildContext context, {required String name, required String? detail, required Widget trailing}) {
  final t = Theme.of(context);
  return ConstrainedBox(
    constraints: const BoxConstraints(minHeight: 56),
    child: Padding(
      padding: const EdgeInsets.fromLTRB(gutter, 8, gutter, 8),
      child: Row(children: [
        Expanded(
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(name, maxLines: 2, overflow: TextOverflow.ellipsis, style: t.textTheme.bodyLarge),
            if (detail != null)
              Text(detail, style: t.textTheme.bodyMedium!.tnum.copyWith(color: t.colorScheme.onSurfaceVariant)),
          ]),
        ),
        const SizedBox(width: 16),
        trailing,
      ]),
    ),
  );
}

class _LineRow extends StatelessWidget {
  final ScoreLine line;
  final Key fieldKey;
  final ValueChanged<double?> onScore;
  final TextStyle muted;
  const _LineRow({required this.line, required this.fieldKey, required this.onScore, required this.muted});

  @override
  Widget build(BuildContext context) {
    final item = line.item;
    final worth = plainNumber(line.worth);
    if (item != null && item.marked) {
      return _row(context,
          name: line.name, detail: '${plainNumber(line.earned)} of $worth points', trailing: _mark(context, item, muted));
    }
    return _row(
      context,
      name: item == null ? 'Nothing posted yet' : line.name,
      detail: '$worth points',
      trailing: Row(mainAxisSize: MainAxisSize.min, children: [
        SizedBox(
          width: 64,
          child: TextField(
            key: fieldKey,
            textAlign: TextAlign.end,
            style: Theme.of(context).textTheme.bodyLarge?.tnum,
            keyboardType: const TextInputType.numberWithOptions(decimal: true),
            inputFormatters: [FilteringTextInputFormatter.allow(RegExp(r'[0-9.]'))],
            decoration: const InputDecoration(
                isDense: true, hintText: '–', contentPadding: EdgeInsets.symmetric(horizontal: 8, vertical: 10)),
            onChanged: (s) => onScore(double.tryParse(s)),
          ),
        ),
        const SizedBox(width: 6),
        Text(item == null ? '%' : '/ ${plainNumber(line.max)}', style: muted),
      ]),
    );
  }
}
