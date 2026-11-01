import 'package:flutter/material.dart';

import '../models/models.dart';
import '../ui/format/format.dart';

IconData deadlineIcon(DeadlineKind k) => switch (k) {
      DeadlineKind.assignment => Icons.assignment_outlined,
      DeadlineKind.quiz => Icons.quiz_outlined,
      DeadlineKind.vod => Icons.play_circle_outline,
      DeadlineKind.other => Icons.event_outlined,
      DeadlineKind.classPeriod => Icons.class_outlined,
    };

/// "Submitted Wed 21:14" for an assignment, "Attempted ..." for a quiz, or that
/// the student marked it themselves.
String doneText(Deadline d) {
  if (d.dismissed && !d.done) return 'Marked done by you';
  final verb = d.kind == DeadlineKind.quiz ? 'Attempted' : 'Submitted';
  final at = d.doneAt;
  return at == null ? verb : '$verb ${pastWhen(at)}';
}
