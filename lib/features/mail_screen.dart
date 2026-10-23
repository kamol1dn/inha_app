import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../core/session.dart';
import '../data/app_data.dart';
import '../models/models.dart';
import '../ui/format/format.dart';
import '../ui/theme/app_text.dart';
import '../ui/theme/status_colors.dart';
import 'common.dart';
import 'link_text.dart';

void openMail(BuildContext context, MailHeader m) =>
    Navigator.of(context).push(MaterialPageRoute(builder: (_) => MailMessageScreen(header: m)));

/// The inbox: a divided list, newest first, with the next page loaded as the
/// end comes into view (DESIGN.md 8, Mail).
class MailScreen extends StatefulWidget {
  const MailScreen({super.key});
  @override
  State<MailScreen> createState() => _MailScreenState();
}

class _MailScreenState extends State<MailScreen> {
  final _scroll = ScrollController();

  @override
  void initState() {
    super.initState();
    _scroll.addListener(() {
      if (_scroll.position.extentAfter < 600) context.read<AppData>().loadMoreMail();
    });
  }

  @override
  void dispose() {
    _scroll.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final data = context.watch<AppData>();
    final t = Theme.of(context);
    final mails = data.inbox.data?.value ?? const <MailHeader>[];
    return Scaffold(
      appBar: AppBar(title: const Text('Mail')),
      body: RefreshIndicator(
        onRefresh: data.refreshMail,
        child: ListView(controller: _scroll, physics: const AlwaysScrollableScrollPhysics(), children: [
          SourceError(data.inbox, 'Mail', onRetry: data.refreshMail),
          if (data.inbox.data == null && data.inbox.error is LoginRequired)
            EmptyNote('Sign in to university mail to read it here.',
                action: 'Sign in', onAction: () => openSettings(context))
          else if (data.inbox.data == null && data.inbox.error == null)
            const SkeletonRows(count: 6, timeColumn: false),
          if (data.inbox.data != null && mails.isEmpty) const EmptyNote('No mail in the inbox.'),
          for (final (i, m) in mails.indexed) ...[
            if (i > 0) const Rule(),
            _MailRow(m),
          ],
          if (data.loadingMoreMail)
            Padding(
              padding: const EdgeInsets.all(gutter),
              child: Text('Loading older mail…',
                  style: t.textTheme.bodySmall?.copyWith(color: t.colorScheme.onSurfaceVariant)),
            )
          else if (data.mailMoreError != null)
            Padding(
              padding: const EdgeInsets.only(right: 8),
              child: Row(children: [
                Expanded(
                    child: StatusLine(Status.danger, describeError(data.mailMoreError!, 'Mail'))),
                TextButton(onPressed: data.loadMoreMail, child: const Text('Retry')),
              ]),
            ),
          const SizedBox(height: 24),
        ]),
      ),
    );
  }
}

class _MailRow extends StatelessWidget {
  final MailHeader m;
  const _MailRow(this.m);

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context);
    final muted = t.colorScheme.onSurfaceVariant;
    return InkWell(
      onTap: () => openMail(context, m),
      child: ConstrainedBox(
        constraints: const BoxConstraints(minHeight: 72),
        child: Padding(
          padding: const EdgeInsets.fromLTRB(gutter, 12, gutter, 12),
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Row(crossAxisAlignment: CrossAxisAlignment.baseline, textBaseline: TextBaseline.alphabetic, children: [
              Expanded(
                child: Text(m.from,
                    maxLines: 1, overflow: TextOverflow.ellipsis, style: t.textTheme.bodyMedium?.copyWith(color: muted)),
              ),
              const SizedBox(width: 12),
              Text(pastWhen(m.received), style: t.textTheme.bodySmall?.tnum.copyWith(color: muted)),
            ]),
            const SizedBox(height: 2),
            // Weight alone says unread: no dot (DESIGN.md 8, Mail).
            Text(m.subject.isEmpty ? '(no subject)' : m.subject,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: m.unread ? t.textTheme.titleSmall : t.textTheme.bodyLarge),
            if (m.preview.isNotEmpty)
              Text(m.preview,
                  maxLines: 1, overflow: TextOverflow.ellipsis, style: t.textTheme.bodyMedium?.copyWith(color: muted)),
          ]),
        ),
      ),
    );
  }
}

/// One message: sender, time, subject, attachments and the plain-text body
/// with tappable links. Opening an unread message marks it read.
class MailMessageScreen extends StatefulWidget {
  final MailHeader header;
  const MailMessageScreen({super.key, required this.header});
  @override
  State<MailMessageScreen> createState() => _MailMessageScreenState();
}

class _MailMessageScreenState extends State<MailMessageScreen> {
  MailMessage? _message;
  Object? _error;
  late bool _unread = widget.header.unread;
  bool _changingRead = false;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() => _error = null);
    try {
      final m = await context.read<AppData>().mail.message(widget.header.id);
      if (!mounted) return;
      setState(() {
        _message = m;
        _unread = m.unread;
      });
      if (m.unread) await _setRead(true);
    } catch (e) {
      if (mounted) setState(() => _error = e);
    }
  }

  Future<void> _setRead(bool read) async {
    final messenger = ScaffoldMessenger.of(context);
    setState(() => _changingRead = true);
    try {
      await context.read<AppData>().setMailRead(widget.header.id, read: read);
      if (mounted) setState(() => _unread = !read);
    } catch (e) {
      messenger.showSnackBar(SnackBar(
          content: Text(read ? "Couldn't mark it read in Mail." : "Couldn't mark it unread in Mail.")));
    }
    if (mounted) setState(() => _changingRead = false);
  }

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context);
    final muted = t.textTheme.bodyMedium?.copyWith(color: t.colorScheme.onSurfaceVariant);
    final h = widget.header;
    final m = _message;
    final subject = (m?.subject ?? h.subject).isEmpty ? '(no subject)' : (m?.subject ?? h.subject);
    final from = m?.from ?? h.from;
    final address = m?.fromAddress ?? '';
    return HeadingScaffold(
      title: subject,
      actions: [
        if (m != null)
          IconButton(
            tooltip: _unread ? 'Mark as read' : 'Mark as unread',
            icon: Icon(_unread ? Icons.mark_email_read_outlined : Icons.mark_email_unread_outlined),
            onPressed: _changingRead ? null : () => _setRead(_unread),
          ),
      ],
      body: (heading) => SelectionArea(
        child: ListView(padding: const EdgeInsets.fromLTRB(gutter, 16, gutter, 24), children: [
          Text(subject, key: heading, style: t.textTheme.headlineSmall),
          const SizedBox(height: 12),
          Text(from, style: t.textTheme.titleSmall),
          if (address.isNotEmpty && address != from) Text(address, style: muted),
          Text(dayDateTime(m?.received ?? h.received), style: muted?.tnum),
          if (m != null && m.attachments.isNotEmpty) ...[
            const SizedBox(height: 16),
            for (final a in m.attachments)
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 4),
                child: Row(children: [
                  Icon(Icons.attach_file, size: 18, color: t.colorScheme.onSurfaceVariant),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(a.name.isEmpty ? 'Attachment' : a.name,
                        maxLines: 1, overflow: TextOverflow.ellipsis, style: t.textTheme.bodyMedium),
                  ),
                  if (a.size > 0) ...[
                    const SizedBox(width: 8),
                    Text(fileSize(a.size), style: muted?.tnum),
                  ],
                ]),
              ),
          ],
          const SizedBox(height: 16),
          const Divider(),
          const SizedBox(height: 16),
          if (m != null)
            m.body.isEmpty
                ? Text('This message has no text.', style: muted)
                : LinkText(m.body, style: t.textTheme.bodyLarge)
          else if (_error != null)
            Row(children: [
              Expanded(
                  child: StatusLine(Status.danger, describeError(_error!, 'Mail'), padding: EdgeInsets.zero)),
              TextButton(onPressed: _load, child: const Text('Retry')),
            ])
          else
            // A static skeleton of the body while it loads (DESIGN.md 8, Loading).
            Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              for (final w in const [1.0, 0.9, 0.95, 0.6]) ...[
                FractionallySizedBox(
                  widthFactor: w,
                  child: Container(
                    height: 16,
                    decoration: BoxDecoration(
                        color: t.colorScheme.surfaceContainerHighest, borderRadius: BorderRadius.circular(4)),
                  ),
                ),
                const SizedBox(height: 8),
              ],
            ]),
        ]),
      ),
    );
  }
}
