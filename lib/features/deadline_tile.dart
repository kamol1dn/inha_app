import 'package:flutter/material.dart';

import '../data/urgency.dart';
import '../models/models.dart';
import '../ui/format/format.dart';
import '../ui/theme/app_text.dart';
import 'common.dart';
import 'details.dart';

IconData deadlineIcon(DeadlineKind k) => switch (k) {
      DeadlineKind.assignment => Icons.assignment_outlined,
      DeadlineKind.quiz => Icons.quiz_outlined,
      DeadlineKind.vod => Icons.play_circle_outline,
      DeadlineKind.other => Icons.event_outlined,
      DeadlineKind.classPeriod => Icons.class_outlined,
    };

/// Two-line deadline row: type icon, item, course; trailing due time and,
/// under 48 h, the relative time in its status colour. With [showDay] (rows
/// not under a day header) a later due time carries its weekday. Tapping it
/// opens the item's details.
class DeadlineTile extends StatelessWidget {
  final Deadline deadline;
  final List<CourseAttendance> attendance;
  final DateTime now;
  final bool showDay;
  const DeadlineTile(this.deadline,
      {super.key, required this.attendance, required this.now, this.showDay = false});

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context);
    final d = deadline;
    final status = deadlineStatus(d, now);
    final relColor = status == null ? t.colorScheme.onSurfaceVariant : statusColors(context).of(status).fg;
    // For a VOD the watch state leads: it is the fact that matters, and a long
    // course name would otherwise push it out of the line.
    final vod = vodFor(d, attendance);
    final sub = [
      if (vod != null) vod.done ? 'Watched' : '${vod.percent.floor()}% watched',
      d.courseName,
    ].join(' · ');
    final showRel = d.end.difference(now).inHours < 48;
    return ListTile(
      minTileHeight: 72,
      leading: Icon(deadlineIcon(d.kind), color: t.colorScheme.onSurfaceVariant),
      title: Text(d.title, maxLines: 1, overflow: TextOverflow.ellipsis, style: t.textTheme.titleMedium),
      subtitle: Text(sub,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: t.textTheme.bodyMedium?.copyWith(color: t.colorScheme.onSurfaceVariant)),
      trailing: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        crossAxisAlignment: CrossAxisAlignment.end,
        children: [
          if (showRel)
            Text(relative(d.end, now: now), style: t.textTheme.bodyMedium?.tnum.copyWith(color: relColor)),
          Text(
              '${d.kind == DeadlineKind.vod ? 'closes ' : ''}'
              '${showDay && !showRel ? relative(d.end, now: now) : clock(d.end)}',
              style: t.textTheme.bodySmall?.tnum.copyWith(color: t.colorScheme.onSurfaceVariant)),
        ],
      ),
      onTap: () => showDeadlineSheet(context, d),
    );
  }
}
