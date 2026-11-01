/// Where a tapped notification leads (DESIGN.md 6: the item's detail, on
/// top of the tab that owns it). Pure: the payload is the notification key.
library;

import 'package:flutter/foundation.dart' show ValueNotifier;

import '../models/models.dart';
import 'rules.dart';

/// The key of the last tapped notification, until HomeShell has opened it. A
/// screen on top of the tabs can send a key here to lead to a tab as well.
class NotificationTaps extends ValueNotifier<String?> {
  NotificationTaps() : super(null);
}

sealed class NotificationTarget {
  const NotificationTarget();
}

/// A deadline or VOD window: its sheet, over the Deadlines tab.
class DeadlineTarget extends NotificationTarget {
  final Deadline deadline;
  const DeadlineTarget(this.deadline);
}

/// An absence: the course, over the Courses tab.
class CourseTarget extends NotificationTarget {
  final Course course;
  const CourseTarget(this.course);
}

/// A new mark: the course's scores, over the Courses tab.
class ScoresTarget extends NotificationTarget {
  final Course course;
  const ScoresTarget(this.course);
}

/// A class reminder: Schedule on that weekday.
class ScheduleTarget extends NotificationTarget {
  final int weekday;
  const ScheduleTarget(this.weekday);
}

/// An exam reminder: the Exams screen.
class ExamsTarget extends NotificationTarget {
  const ExamsTarget();
}

/// The item is gone (submitted, moved, the course dropped): its tab. A
/// home-screen widget opens a tab directly with `tab:<n>`.
class TabTarget extends NotificationTarget {
  final int tab; // 0 Today, 1 Schedule, 2 Deadlines, 3 Courses, 4 Mail
  const TabTarget(this.tab);
}

/// A widget's "open this tab" key (docs/WIDGETS.md).
const tabKeyPrefix = 'tab:';

NotificationTarget? notificationTarget(
  String key, {
  List<Deadline> deadlines = const [],
  List<CourseAttendance> attendance = const [],
  List<CourseGrades> courseGrades = const [],
}) {
  if (gradeCourseId(key) case final courseId?) {
    for (final g in courseGrades) {
      if (g.course.id == courseId) return ScoresTarget(g.course);
    }
    return const TabTarget(3);
  }
  if (key.startsWith(vodKeyPrefix) || key.startsWith(dueKeyPrefix)) {
    for (final d in deadlines) {
      if (key.startsWith('${reminderStem(d)}|')) return DeadlineTarget(d);
    }
    return const TabTarget(2);
  }
  final courseId = absenceCourseId(key);
  if (courseId != null) {
    for (final c in attendance) {
      if (c.course.id == courseId) return CourseTarget(c.course);
    }
    return const TabTarget(3);
  }
  if (key.startsWith(classKeyPrefix)) {
    final day = DateTime.tryParse(key.substring(classKeyPrefix.length).split('|').first);
    return day == null ? const TabTarget(1) : ScheduleTarget(day.weekday);
  }
  if (key.startsWith(examKeyPrefix)) return const ExamsTarget();
  if (key.startsWith(noticeKeyPrefix)) return const TabTarget(0); // Today lists them
  if (key.startsWith(tabKeyPrefix)) {
    final tab = int.tryParse(key.substring(tabKeyPrefix.length));
    return tab != null && tab >= 0 && tab <= 4 ? TabTarget(tab) : null;
  }
  return null;
}
