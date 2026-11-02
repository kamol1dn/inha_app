import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../core/session.dart';
import '../data/app_data.dart';
import '../models/models.dart';
import '../ui/theme/app_text.dart';
import 'common.dart';
import 'course_scores_screen.dart';

/// INS grades: the GPA as a plain line, then this semester's eClass scores,
/// then courses by term, newest first. The letter is the answer, so it is the
/// Fraunces part (DESIGN.md 8).
class GradesScreen extends StatelessWidget {
  const GradesScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final data = context.watch<AppData>();
    final t = Theme.of(context);
    final muted = t.textTheme.bodyMedium!.tnum.copyWith(color: t.colorScheme.onSurfaceVariant);
    final report = data.grades.data?.value;
    final scores = data.courseGrades.data?.value ?? const <CourseGrades>[];
    final byTerm = <int, List<GradeRecord>>{};
    for (final r in report?.records ?? const <GradeRecord>[]) {
      byTerm.putIfAbsent(r.termKey, () => []).add(r);
    }
    final terms = byTerm.keys.toList()..sort((a, b) => b.compareTo(a));
    return Scaffold(
      appBar: AppBar(title: const Text('Grades')),
      body: RefreshIndicator(
        onRefresh: () => Future.wait([data.refreshGrades(), data.refreshEclass()]),
        child: ListView(physics: const AlwaysScrollableScrollPhysics(), children: [
          const SyncStrip(),
          if (report == null && data.grades.error is LoginRequired)
            EmptyNote('Sign in to INS to see grades.', action: 'Sign in', onAction: () => openSettings(context))
          else if (report == null && data.grades.error == null)
            const SkeletonRows(count: 6, timeColumn: false)
          else
            SourceError(data.grades, 'INS', onRetry: data.refreshGrades),
          if (report != null)
            Padding(
              padding: const EdgeInsets.fromLTRB(gutter, 16, gutter, 0),
              child: Wrap(crossAxisAlignment: WrapCrossAlignment.end, spacing: 8, children: [
                Text(report.gpa.toStringAsFixed(2), style: t.textTheme.headlineMedium),
                Padding(
                  padding: const EdgeInsets.only(bottom: 6),
                  child: Text(
                      'GPA of 4.5 · ${report.creditsEarned.toStringAsFixed(0)} credits · year ${report.yearOfStudy}',
                      style: muted),
                ),
              ]),
            ),
          if (report != null && creditsByCategory(report.records).isNotEmpty) ...[
            const SectionHeader('Credits by category'),
            for (final (i, e) in creditsByCategory(report.records).entries.indexed) ...[
              if (i > 0) const Rule(),
              ConstrainedBox(
                constraints: const BoxConstraints(minHeight: 48),
                child: Padding(
                  padding: const EdgeInsets.symmetric(horizontal: gutter, vertical: 12),
                  child: Row(children: [
                    Expanded(child: Text(e.key, style: t.textTheme.bodyLarge)),
                    const SizedBox(width: 16),
                    Text(_credits(e.value), style: muted),
                  ]),
                ),
              ),
            ],
            if (_insTotals(report) case final line?)
              Padding(
                padding: const EdgeInsets.fromLTRB(gutter, 4, gutter, 0),
                child: Text(line, style: muted),
              ),
          ],
          if (scores.isNotEmpty) ...[
            SectionHeader('Scores this semester', source: data.courseGrades),
            for (final (i, g) in scores.indexed) ...[
              if (i > 0) const Rule(),
              ScoresRow(g, showCourse: true),
            ],
          ],
          for (final term in terms) ...[
            // INS labels the term in progress "Course registration"; nothing in it is graded yet.
            SectionHeader(byTerm[term]!.every((r) => !r.graded) ? 'This semester' : byTerm[term]!.first.term,
                source: data.grades, staleAfter: const Duration(hours: 24)),
            Padding(
              padding: const EdgeInsets.fromLTRB(gutter, 0, gutter, 4),
              child: Text(_termLine(byTerm[term]!), style: muted),
            ),
            for (final (i, r) in byTerm[term]!.indexed) ...[
              if (i > 0) const Rule(),
              ConstrainedBox(
                constraints: const BoxConstraints(minHeight: 56),
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(gutter, 8, gutter, 8),
                  child: Row(children: [
                    Expanded(
                      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                        Text(r.name, maxLines: 2, overflow: TextOverflow.ellipsis, style: t.textTheme.bodyLarge),
                        Text(
                            [_credits(r.credits), if (r.category.isNotEmpty) r.category].join(' · '),
                            style: muted),
                      ]),
                    ),
                    const SizedBox(width: 16),
                    Text(r.graded ? r.letter : 'Not graded', style: r.graded ? t.textTheme.titleMedium : muted),
                  ]),
                ),
              ),
            ],
          ],
          const SizedBox(height: 24),
        ]),
      ),
    );
  }

  /// "3 credits", "1 credit", "1.5 credits".
  static String _credits(double c) => '${plainNumber(c)} ${c == 1 ? 'credit' : 'credits'}';

  /// "GPA 3.81 · 18 credits", or the credits alone for a term with no GPA yet.
  static String _termLine(List<GradeRecord> records) {
    final gpa = termGpa(records);
    final credits = _credits(records.fold(0.0, (s, r) => s + r.credits));
    return gpa == null ? credits : 'GPA ${gpa.toStringAsFixed(2)} · $credits';
  }

  /// INS's own required-credit totals, to compare with the rows counted above.
  static String? _insTotals(GradeReport r) {
    final parts = [
      if (r.majorRequired case final v?) '${plainNumber(v)} major-required',
      if (r.generalRequired case final v?) '${plainNumber(v)} general-required',
    ];
    return parts.isEmpty ? null : 'INS counts ${parts.join(' and ')} credits.';
  }
}
