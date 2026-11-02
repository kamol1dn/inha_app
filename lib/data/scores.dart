/// The accumulated score and the what-if calculator, from a course's grades
/// page. Pure: no I/O and no clock.
library;

import 'dart:math' as math;

import '../models/models.dart';

/// How far apart two figures can be and still be the same one: eClass rounds
/// to two places.
const _agree = 0.05;

/// Something that counts toward the course total: an item, or a category with
/// nothing posted in it yet.
class ScoreLine {
  final String id;
  final String name;
  final String category;
  final GradeItem? item; // null: a category with nothing posted yet
  final double worth; // points out of the course's 100

  const ScoreLine({required this.id, required this.name, required this.category, required this.worth, this.item});

  bool get marked => item?.marked ?? false;

  /// What a score is out of. A category with nothing posted is taken as a %.
  double get max => (item?.max ?? 0) > 0 ? item!.max! : 100;

  /// The points this line has earned: its share of what it is worth. eClass's
  /// own figure is used only where it agrees: on some courses that column holds
  /// the raw mark, which is on another scale.
  double get earned {
    final i = item;
    if (i == null || !i.marked) return 0;
    final share = i.grade == null ? null : i.grade! / max * worth;
    final own = i.contribution;
    if (share == null) return own == null ? 0 : math.min(own, worth);
    return own != null && (own - share).abs() <= _agree ? own : share;
  }
}

/// A course's score so far: eClass's own course total where it gives one, else
/// what the lines add up to. Null from [of] when there is neither.
///
/// Only a published weight makes a line. A category weight of "-" can't be read
/// back from its marks: the contribution column treats such a category as the
/// whole course, so 81 of 100 "contributes" 81 whatever the category is worth.
class CourseScore {
  final List<ScoreLine> lines;
  final double accumulated;

  /// What the score is out of: 100, or what the weights add up to where a
  /// course has no total and its weights pass 100.
  final double outOf;

  /// Items with a weight of 0: shown, but they add nothing.
  final List<GradeItem> uncounted;

  /// Items eClass publishes no weight for: they may count, but by how much
  /// isn't known.
  final List<GradeItem> unweighted;

  const CourseScore._(this.lines, this.accumulated, this.outOf, this.uncounted, this.unweighted);

  static CourseScore? of(CourseGrades g) {
    if (g.source != GradeSource.gradebook) return null;

    final lines = <ScoreLine>[];
    final uncounted = <GradeItem>[];
    final unweighted = <GradeItem>[];
    for (final i in g.items) {
      final (weight, categoryWeight) = (i.weight, i.categoryWeight);
      if (weight == 0) {
        uncounted.add(i);
      } else if (weight == null || categoryWeight == null) {
        unweighted.add(i);
      } else {
        lines.add(ScoreLine(id: i.key, name: i.name, category: i.category, worth: weight * categoryWeight / 100, item: i));
      }
    }
    for (final c in g.categories) {
      final weight = c.weight ?? 0;
      if (weight <= 0 || g.items.any((i) => i.category == c.name)) continue;
      lines.add(ScoreLine(id: 'category:${c.name}', name: c.name, category: c.name, worth: weight));
    }
    final percent = g.percent;
    if (percent == null && lines.isEmpty) return null;

    final worth = lines.fold(0.0, (s, l) => s + l.worth);
    return CourseScore._(lines, percent ?? lines.fold(0.0, (s, l) => s + l.earned),
        percent == null && worth > 100 + _agree ? worth : 100, uncounted, unweighted);
  }

  /// Whether the weights account for the whole course, so "still open" and
  /// "best possible" mean something.
  bool get complete => (lines.fold(0.0, (s, l) => s + l.worth) - outOf).abs() <= 0.5;

  /// "28.5 of 100".
  String get line => ofValue(accumulated);

  /// A score with this one's denominator: "48.5 of 100".
  String ofValue(double value) => '${plainNumber(value)} of ${plainNumber(outOf)}';

  /// The points of the course that have been marked so far.
  double get markedWorth => lines.where((l) => l.marked).fold(0.0, (s, l) => s + l.worth);

  /// The points still to come: everything unmarked, whole.
  double get openWorth => lines.where((l) => !l.marked).fold(0.0, (s, l) => s + l.worth);

  /// The score if everything still open went perfectly.
  double get best => accumulated + openWorth;

  /// The score with these what-if scores, by [ScoreLine.id], on lines still
  /// open. A score is capped at what its line is out of.
  double withScores(Map<String, double> scores) {
    var total = accumulated;
    for (final l in lines) {
      final s = scores[l.id];
      if (s == null || l.marked) continue;
      total += s.clamp(0, l.max) / l.max * l.worth;
    }
    return total;
  }
}

/// Attendance marks tick over after every class and the Attendance channel
/// already covers absences, so they are shown but never announced.
bool isAttendanceMark(GradeItem i) {
  final attendance = RegExp(r'attendance|출석', caseSensitive: false);
  return attendance.hasMatch(i.name) || attendance.hasMatch(i.category);
}
