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

/// A course's score so far. Null from [of] when eClass publishes no weights.
class CourseScore {
  final List<ScoreLine> lines;
  final double accumulated;

  /// What the score is out of: 100, or what the weights really add up to where
  /// a course's add up to more.
  final double outOf;

  /// Items with no known weight or a weight of 0: shown, but they add nothing.
  final List<GradeItem> uncounted;

  const CourseScore._(this.lines, this.accumulated, this.outOf, this.uncounted);

  static CourseScore? of(CourseGrades g) {
    if (g.source != GradeSource.gradebook) return null;

    // A category weight of "-" can still be read back from a marked item:
    // contribution = mark / max × item weight × category weight.
    final inferred = <String, double>{};
    for (final i in g.items) {
      final (grade, max, weight, points) = (i.grade, i.max, i.weight, i.contribution);
      if (i.categoryWeight != null || grade == null || max == null || weight == null || points == null) continue;
      if (grade <= 0 || max <= 0 || weight <= 0 || points <= 0) continue;
      final read = points / (grade / max * weight / 100);
      if (read <= 100 + _agree) inferred[i.category] ??= read; // over 100: a raw mark, not points
    }

    final lines = <ScoreLine>[];
    final uncounted = <GradeItem>[];
    for (final i in g.items) {
      final categoryWeight = i.categoryWeight ?? inferred[i.category];
      final worth = i.weight == null || categoryWeight == null ? 0.0 : i.weight! * categoryWeight / 100;
      if (worth > 0) {
        lines.add(ScoreLine(id: i.key, name: i.name, category: i.category, worth: worth, item: i));
      } else {
        uncounted.add(i);
      }
    }
    for (final c in g.categories) {
      final weight = c.weight ?? 0;
      if (weight <= 0 || g.items.any((i) => i.category == c.name)) continue;
      lines.add(ScoreLine(id: 'category:${c.name}', name: c.name, category: c.name, worth: weight));
    }
    if (lines.isEmpty) return null;

    // The sum of what is shown, not the total row: on some courses that row adds up the raw marks.
    final sum = lines.fold(0.0, (s, l) => s + l.earned);
    final worth = lines.fold(0.0, (s, l) => s + l.worth);
    final total = g.total;
    return CourseScore._(lines, total != null && (total - sum).abs() <= _agree ? total : sum,
        worth > 100 + _agree ? worth : 100, uncounted);
  }

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

/// eClass's own course total, in its own range: "Course total on eClass: 157.25
/// of 300". Null where there is none, or where it says the same as the score
/// already shown.
String? eclassTotalLine(CourseGrades g, CourseScore? score) {
  final total = g.gradeTotal;
  if (total == null || (score != null && (total - score.accumulated).abs() <= _agree)) return null;
  final max = g.gradeTotalMax;
  return 'Course total on eClass: ${plainNumber(total)}${max == null ? '' : ' of ${plainNumber(max)}'}';
}

/// Attendance marks tick over after every class and the Attendance channel
/// already covers absences, so they are shown but never announced.
bool isAttendanceMark(GradeItem i) {
  final attendance = RegExp(r'attendance|출석', caseSensitive: false);
  return attendance.hasMatch(i.name) || attendance.hasMatch(i.category);
}
