import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../data/app_data.dart';
import '../models/models.dart';
import '../ui/theme/app_text.dart';
import 'common.dart';

/// INS grades: GPA as a plain row, then courses by term, newest first (DESIGN.md 8).
class GradesScreen extends StatelessWidget {
  const GradesScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final data = context.watch<AppData>();
    final t = Theme.of(context);
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
          if (report != null)
            ListTile(
              title: Text('GPA ${report.gpa.toStringAsFixed(2)} of 4.5', style: t.textTheme.titleMedium?.tnum),
              subtitle: Text('${report.creditsEarned.toStringAsFixed(0)} credits earned · year ${report.yearOfStudy}',
                  style: t.textTheme.bodyMedium?.tnum),
            ),
          for (final term in terms) ...[
            // INS labels the term in progress "Course registration"; nothing in it is graded yet.
            SectionHeader(byTerm[term]!.every((r) => !r.graded) ? 'This semester' : byTerm[term]!.first.term,
                source: data.grades, staleAfter: const Duration(hours: 24)),
            for (final r in byTerm[term]!)
              ListTile(
                title: Text(r.name, maxLines: 1, overflow: TextOverflow.ellipsis, style: t.textTheme.titleMedium),
                subtitle: Text('${r.credits.toStringAsFixed(1)} credits',
                    style: t.textTheme.bodyMedium?.tnum.copyWith(color: t.colorScheme.onSurfaceVariant)),
                trailing: Text(r.graded ? r.letter : 'Not graded',
                    style: (r.graded ? t.textTheme.titleMedium : t.textTheme.bodyMedium)?.tnum),
              ),
          ],
          const SizedBox(height: 24),
        ]),
      ),
    );
  }
}
