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

/// "Submitted Wed 21:14" for an assignment, "Attempted ..." for a quiz.
String doneText(Deadline d) {
  final verb = d.kind == DeadlineKind.quiz ? 'Attempted' : 'Submitted';
  final at = d.doneAt;
  return at == null ? verb : '$verb ${pastWhen(at)}';
}
