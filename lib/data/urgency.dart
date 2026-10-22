import '../models/models.dart';
import '../ui/theme/status_colors.dart';

// When items appear on Today (DESIGN.md section 7). VOD windows use the same
// 72 h as deadlines rather than the guide's 48 h: a missed window is a
// recorded absence, and "closes Sunday" needs to be seen by Friday.
const deadlineTodayWindow = Duration(hours: 72);
const vodTodayWindow = Duration(hours: 72);

String _norm(String s) => s.toLowerCase().replaceAll(RegExp(r'\s+'), ' ').trim();

/// Kinds that are something due. Class periods are only shown on request.
bool isDue(Deadline d) => d.kind != DeadlineKind.classPeriod;

/// The course's attendance record for a calendar event. Calendar course names
/// can be cut short, so match on prefix either way.
CourseAttendance? courseFor(String courseName, List<CourseAttendance> all) {
  final n = _norm(courseName);
  if (n.isEmpty) return null;
  for (final c in all) {
    final m = _norm(c.course.name);
    if (m == n || m.startsWith(n) || n.startsWith(m)) return c;
  }
  return null;
}

/// The progress row for a VOD-window event, or null if unknown.
VodProgress? vodFor(Deadline d, List<CourseAttendance> all) {
  if (d.kind != DeadlineKind.vod) return null;
  final course = courseFor(d.courseName, all);
  if (course == null) return null;
  final t = _norm(d.title);
  for (final v in course.vods) {
    if (_norm(v.title) == t) return v;
  }
  return null;
}

/// Whether a VOD-window event is already fully watched, or null if unknown.
bool? vodWatched(Deadline d, List<CourseAttendance> all) => vodFor(d, all)?.done;

/// null = plain (no colour), otherwise the status the guide assigns.
Status? deadlineStatus(Deadline d, DateTime now) {
  final left = d.end.difference(now);
  if (d.kind == DeadlineKind.vod) {
    if (left.inHours < 12) return Status.danger;
    if (left.inHours < 72) return Status.warning;
    return null;
  }
  if (left.isNegative || left.inHours < 3) return Status.danger;
  if (left.inHours < 24) return Status.warning;
  return null;
}

/// Items for Today's "Needs attention": unwatched VOD windows and other
/// deadlines due within 72 h (overdue ones kept for 24 h). Never class periods.
List<Deadline> needsAttention(List<Deadline> all, List<CourseAttendance> att, DateTime now) {
  final out = all.where((d) {
    if (!isDue(d)) return false;
    final left = d.end.difference(now);
    if (d.kind == DeadlineKind.vod) {
      return !left.isNegative && left <= vodTodayWindow && vodWatched(d, att) != true;
    }
    return left > const Duration(hours: -24) && left <= deadlineTodayWindow;
  }).toList()
    ..sort((a, b) => a.end.compareTo(b.end));
  return out;
}
