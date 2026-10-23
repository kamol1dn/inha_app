import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../core/session.dart';
import '../data/app_data.dart';
import '../models/models.dart';
import '../ui/theme/app_text.dart';
import 'common.dart';

/// INS grades: the GPA as a plain line, then courses by term, newest first.
/// The letter is the answer, so it is the Fraunces part (DESIGN.md 8).
class GradesScreen extends StatelessWidget {
  const GradesScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final data = context.watch<AppData>();
    final t = Theme.of(context);
    final muted = t.textTheme.bodyMedium!.tnum.copyWith(color: t.colorScheme.onSurfaceVariant);
    final report = data.grades.data?.value;
    final byTerm = <int, List<GradeRecord>>{};
    for (final r in report?.records ?? const <GradeRecord>[]) {
      byTerm.putIfAbsent(r.termKey, () => []).add(r);
    }
    final terms = byTerm.keys.toList()..sort((a, b) => b.compareTo(a));
    return Scaffold(
      appBar: AppBar(title: const Text('Grades')),
      body: RefreshIndicator(
        onRefresh: data.refreshGrades,
        child: ListView(physics: const AlwaysScrollableScrollPhysics(), children: [
          SourceError(data.grades, 'INS', onRetry: data.refreshGrades),
          if (report == null && data.grades.error is LoginRequired)
            EmptyNote('Sign in to INS to see grades.', action: 'Sign in', onAction: () => openSettings(context))
          else if (report == null && data.grades.error == null)
            const SkeletonRows(count: 6, timeColumn: false),
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
          for (final term in terms) ...[
            // INS labels the term in progress "Course registration"; nothing in it is graded yet.
            SectionHeader(byTerm[term]!.every((r) => !r.graded) ? 'This semester' : byTerm[term]!.first.term,
                source: data.grades, staleAfter: const Duration(hours: 24)),
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
                        Text('${r.credits.toStringAsFixed(1)} credits', style: muted),
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
}
