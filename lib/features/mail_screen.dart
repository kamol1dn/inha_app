import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../data/app_data.dart';
import '../models/models.dart';
import '../ui/format/format.dart';
import '../ui/theme/app_text.dart';
import 'common.dart';

class MailScreen extends StatelessWidget {
  const MailScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final data = context.watch<AppData>();
    final t = Theme.of(context);
    final mails = data.inbox.data?.value ?? const <MailHeader>[];
    return Scaffold(
      appBar: AppBar(title: const Text('Mail')),
      body: RefreshIndicator(
        onRefresh: data.refreshMail,
        child: ListView(physics: const AlwaysScrollableScrollPhysics(), children: [
          SourceError(data.inbox, 'Mail', onRetry: data.refreshMail),
          if (data.inbox.data != null && mails.isEmpty)
            const Padding(padding: EdgeInsets.all(16), child: Text('No mail.')),
          for (final (i, m) in mails.indexed) ...[
            if (i > 0) const Divider(indent: 16),
            ListTile(
              minTileHeight: 72,
              title: Row(children: [
                Expanded(child: Text(m.from, maxLines: 1, overflow: TextOverflow.ellipsis, style: t.textTheme.bodyMedium)),
                Text(pastWhen(m.received), style: t.textTheme.bodySmall?.tnum),
              ]),
              subtitle: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text(m.subject,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: m.unread
                        ? t.textTheme.titleMedium
                        : t.textTheme.bodyLarge?.copyWith(color: t.colorScheme.onSurface)),
                if (m.preview.isNotEmpty)
                  Text(m.preview,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: t.textTheme.bodyMedium?.copyWith(color: t.colorScheme.onSurfaceVariant)),
              ]),
            ),
          ],
        ]),
      ),
    );
  }
}
