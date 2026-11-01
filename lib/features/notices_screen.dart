import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../data/app_data.dart';
import '../models/models.dart';
import '../services/eclass/eclass_links.dart';
import '../ui/format/format.dart';
import '../ui/theme/app_text.dart';
import 'common.dart';

void openNotices(BuildContext context) =>
    Navigator.of(context).push(MaterialPageRoute(builder: (_) => const NoticesScreen()));

/// One item of eClass's bell menu: its subject, and with [full] its text. It
/// opens its link when that stays on eClass, else does [onTap].
class NoticeRow extends StatelessWidget {
  final EclassNotification notice;
  final bool full;
  final VoidCallback? onTap;
  const NoticeRow(this.notice, {super.key, this.full = false, this.onTap});

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context);
    final n = notice;
    final muted = t.colorScheme.onSurfaceVariant;
    final row = ConstrainedBox(
      constraints: const BoxConstraints(minHeight: 48),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: gutter, vertical: 8),
        child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Expanded(
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(n.subject, style: n.read ? t.textTheme.bodyLarge : t.textTheme.titleSmall),
              if (full && n.text.isNotEmpty && n.text != n.subject) ...[
                const SizedBox(height: 2),
                Text(n.text, style: t.textTheme.bodyMedium?.copyWith(color: muted)),
              ],
            ]),
          ),
          const SizedBox(width: 12),
          Text(pastWhen(n.time), style: t.textTheme.bodySmall?.tnum.copyWith(color: muted)),
        ]),
      ),
    );
    final link = eclassNoticeUrl(n);
    final tap = link != null ? () => openUrl(context, link) : onTap;
    return tap == null ? row : InkWell(onTap: tap, child: row);
  }
}

/// Everything eClass's bell menu lists, with its text, newest first (DESIGN.md
/// 8, From eClass). Today shows only the newest unread ones.
class NoticesScreen extends StatelessWidget {
  const NoticesScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final data = context.watch<AppData>();
    final source = data.eclassNotifications;
    final notices = source.data?.value;
    return Scaffold(
      appBar: AppBar(title: const Text('From eClass')),
      body: Column(children: [
        const SyncStrip(),
        Expanded(
          child: RefreshIndicator(
            onRefresh: data.refreshEclass,
            child: ListView(physics: const AlwaysScrollableScrollPhysics(), children: [
              SourceError(source, 'eClass', onRetry: data.refreshEclass),
              if (notices == null && source.error == null)
                const SkeletonRows(count: 3, timeColumn: false)
              else if (notices != null && notices.isEmpty)
                const EmptyNote('No notifications from eClass.'),
              for (final (i, n) in (notices ?? const <EclassNotification>[]).indexed) ...[
                if (i > 0) const Rule(),
                NoticeRow(n, full: true),
              ],
            ]),
          ),
        ),
      ]),
    );
  }
}
