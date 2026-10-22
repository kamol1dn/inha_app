import 'dart:math' as math;

import '../models/models.dart';
import '../ui/theme/status_colors.dart';

/// A course's absences against the limit the student set for it. No source
/// publishes the limits, so [limit] is null until the student enters one
/// (DESIGN.md 7: never guess it).
class AbsenceState {
  final int used;
  final int? limit;
  const AbsenceState(this.used, this.limit);

  factory AbsenceState.of(CourseAttendance c, Map<int, int> limits) =>
      AbsenceState(c.count(AttendanceMark.absent), limits[c.course.id]);

  int? get left => limit == null ? null : limit! - used;

  /// DESIGN.md 7: warning once the absences left are at most max(1, 25% of
  /// the allowance); danger at 0 left or over the limit; null otherwise.
  Status? get status {
    final l = left;
    if (l == null) return null;
    if (l <= 0) return Status.danger;
    if (l <= math.max(1, limit! * 0.25)) return Status.warning;
    return null;
  }

  bool get trouble => status != null;

  /// "1 left", "At limit", "Over limit"; null when not in trouble.
  String? get tag {
    final l = left;
    if (l == null || status == null) return null;
    if (l < 0) return 'Over limit';
    if (l == 0) return 'At limit';
    return '$l left';
  }

  /// "3 of 4 absences used", "5 absences · limit 4", or the raw count.
  String get line {
    final lim = limit;
    final noun = used == 1 ? 'absence' : 'absences';
    if (lim == null) return '$used $noun · limit not set';
    if (used > lim) return '$used absences · limit $lim';
    return '$used of $lim $noun used';
  }
}

/// Courses ordered for "am I in trouble" (DESIGN.md 8, Courses): danger,
/// then warning, then the rest in timetable order (first class of the week),
/// courses not in the timetable last.
List<CourseAttendance> troubleOrder(List<CourseAttendance> courses, Map<int, int> limits, List<Lesson> lessons) {
  int rank(CourseAttendance c) => switch (AbsenceState.of(c, limits).status) {
        Status.danger => 0,
        Status.warning => 1,
        _ => 2,
      };
  String norm(String s) => s.toLowerCase().replaceAll(RegExp(r'\s+'), ' ').trim();
  int firstClass(CourseAttendance c) {
    final name = norm(c.course.name);
    var best = 1 << 30;
    for (final l in lessons) {
      final subject = norm(l.subject);
      if (subject.isEmpty || !(subject == name || subject.startsWith(name) || name.startsWith(subject))) continue;
      final p = l.start.split(':');
      final at = l.weekday * 24 * 60 + (int.tryParse(p.first) ?? 0) * 60 + (p.length > 1 ? int.tryParse(p[1]) ?? 0 : 0);
      best = math.min(best, at);
    }
    return best;
  }

  return [...courses]..sort((a, b) {
      final byRank = rank(a).compareTo(rank(b));
      if (byRank != 0) return byRank;
      final byTime = firstClass(a).compareTo(firstClass(b));
      return byTime != 0 ? byTime : a.course.name.compareTo(b.course.name);
    });
}
