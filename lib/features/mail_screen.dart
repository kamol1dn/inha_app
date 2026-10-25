import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../core/session.dart';
import '../data/app_data.dart';
import '../models/models.dart';
import '../ui/format/format.dart';
import '../ui/theme/app_text.dart';
import '../ui/theme/status_colors.dart';
import 'common.dart';
import 'compose_screen.dart';
import 'link_text.dart';

void openMail(BuildContext context, MailHeader m, {MailFolder folder = MailFolder.inbox}) =>
    Navigator.of(context).push(MaterialPageRoute(builder: (_) => MailMessageScreen(header: m, folder: folder)));

/// What a folder says when it is empty.
String _emptyText(MailFolder f) => switch (f) {
      MailFolder.inbox => 'No mail in the inbox.',
      MailFolder.drafts => 'No drafts.',
      MailFolder.sent => 'Nothing sent yet.',
      MailFolder.deleted => 'Nothing in Deleted.',
      MailFolder.junk => 'No junk mail.',
      MailFolder.notes => 'No notes.',
    };

/// The Mail tab: one folder as a divided list, newest first, with the next
/// page loaded as the end comes into view (DESIGN.md 8, Mail). The folder is
/// picked in [MailDrawer].
class MailScreen extends StatefulWidget {
  final MailFolder folder;
  const MailScreen({super.key, this.folder = MailFolder.inbox});
  @override
  State<MailScreen> createState() => _MailScreenState();
}

class _MailScreenState extends State<MailScreen> {
  final _scroll = ScrollController();

  @override
  void initState() {
    super.initState();
    _scroll.addListener(() {
      if (_scroll.position.extentAfter < 600) context.read<AppData>().loadMoreMail(widget.folder);
    });
    WidgetsBinding.instance.addPostFrameCallback((_) => _refreshIfOld());
  }

  @override
  void didUpdateWidget(MailScreen old) {
    super.didUpdateWidget(old);
    if (old.folder == widget.folder) return;
    if (_scroll.hasClients) _scroll.jumpTo(0);
    // Not during this build: the refresh notifies the screens at once.
    WidgetsBinding.instance.addPostFrameCallback((_) => _refreshIfOld());
  }

  /// The inbox refreshes with everything else; another folder is fetched
  /// when it is opened and has not been for a while.
  void _refreshIfOld() {
    if (!mounted || widget.folder == MailFolder.inbox) return;
    final data = context.read<AppData>();
    final list = data.mailbox(widget.folder).list;
    if (list.loading) return;
    final at = list.data?.fetchedAt;
    if (at == null || DateTime.now().difference(at) > const Duration(minutes: 5)) {
      data.refreshMail(folder: widget.folder);
    }
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
    final folder = widget.folder;
    final box = data.mailbox(folder);
    final list = box.list;
    final mails = list.data?.value ?? const <MailHeader>[];
    Future<void> refresh() => data.refreshMail(folder: folder);
    return RefreshIndicator(
      onRefresh: refresh,
      child: ListView(controller: _scroll, physics: const AlwaysScrollableScrollPhysics(), children: [
        if (list.data == null && list.error is LoginRequired)
          EmptyNote('Sign in to university mail to read it here.',
              action: 'Sign in', onAction: () => openSettings(context))
        else if (list.data == null && list.error == null)
          const SkeletonRows(count: 6, timeColumn: false)
        else
          SourceError(list, 'Mail', onRetry: refresh),
        if (list.data != null && mails.isEmpty) EmptyNote(_emptyText(folder)),
        for (final (i, m) in mails.indexed) ...[
          if (i > 0) const Rule(),
          _MailRow(m, folder),
        ],
        if (box.loadingMore)
          Padding(
            padding: const EdgeInsets.all(gutter),
            child: Text('Loading older mail…',
                style: t.textTheme.bodySmall?.copyWith(color: t.colorScheme.onSurfaceVariant)),
          )
        else if (box.moreError != null)
          Padding(
            padding: const EdgeInsets.only(right: 8),
            child: Row(children: [
              Expanded(child: StatusLine(Status.danger, describeError(box.moreError!, 'Mail'))),
              TextButton(onPressed: () => data.loadMoreMail(folder), child: const Text('Retry')),
            ]),
          ),
        // Room for the last row above the New button.
        const SizedBox(height: 96),
      ]),
    );
  }
}

/// The folders, behind the menu button on the Mail tab. The selected one is
/// marked the way the selected tab is: `primary`, filled icon, 600.
class MailDrawer extends StatelessWidget {
  final MailFolder selected;
  final ValueChanged<MailFolder> onSelect;
  const MailDrawer({super.key, required this.selected, required this.onSelect});

  static const _icons = {
    MailFolder.inbox: (Icons.inbox_outlined, Icons.inbox),
    MailFolder.drafts: (Icons.drafts_outlined, Icons.drafts),
    MailFolder.sent: (Icons.send_outlined, Icons.send),
    MailFolder.deleted: (Icons.delete_outline, Icons.delete),
    MailFolder.junk: (Icons.report_outlined, Icons.report),
    MailFolder.notes: (Icons.sticky_note_2_outlined, Icons.sticky_note_2),
  };

  @override
  Widget build(BuildContext context) {
    final data = context.watch<AppData>();
    final t = Theme.of(context);
    return Drawer(
      child: SafeArea(
        child: ListView(padding: const EdgeInsets.symmetric(vertical: 8), children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(gutter, 12, gutter, 16),
            child: Text('Mail', style: t.textTheme.headlineSmall),
          ),
          const Rule(inset: 0),
          const SizedBox(height: 8),
          for (final f in MailFolder.values) _folderRow(context, data, f),
        ]),
      ),
    );
  }

  Widget _folderRow(BuildContext context, AppData data, MailFolder f) {
    final t = Theme.of(context);
    final on = f == selected;
    final fg = on ? t.colorScheme.primary : t.colorScheme.onSurfaceVariant;
    final counts = data.mailCounts[f];
    // Drafts count what is waiting to go; the other folders what is unread.
    final n = f == MailFolder.drafts
        ? counts?.total ?? 0
        : f == MailFolder.inbox
            ? data.mailUnread.data?.value ?? counts?.unread ?? 0
            : counts?.unread ?? 0;
    return InkWell(
      onTap: () => onSelect(f),
      child: ConstrainedBox(
        constraints: const BoxConstraints(minHeight: 52),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: gutter),
          child: Row(children: [
            Icon(on ? _icons[f]!.$2 : _icons[f]!.$1, color: fg),
            const SizedBox(width: 16),
            Expanded(
              child: Text(f.label,
                  style: t.textTheme.bodyLarge?.copyWith(
                      color: on ? t.colorScheme.primary : null, fontWeight: on ? FontWeight.w600 : null)),
            ),
            if (n > 0)
              Text('$n',
                  style: t.textTheme.bodyMedium?.tnum.copyWith(
                      color: on ? t.colorScheme.primary : t.colorScheme.onSurfaceVariant,
                      fontWeight: f == MailFolder.drafts ? null : FontWeight.w600)),
          ]),
        ),
      ),
    );
  }
}

class _MailRow extends StatelessWidget {
  final MailHeader m;
  final MailFolder folder;
  const _MailRow(this.m, this.folder);

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context);
    final muted = t.colorScheme.onSurfaceVariant;
    // Sent mail and drafts are about who they go to.
    final who = folder.outgoing ? (m.to.isEmpty ? 'No recipients' : 'To ${m.to}') : m.from;
    return InkWell(
      onTap: () =>
          folder == MailFolder.drafts ? openDraft(context, m) : openMail(context, m, folder: folder),
      child: ConstrainedBox(
        constraints: const BoxConstraints(minHeight: 72),
        child: Padding(
          padding: const EdgeInsets.fromLTRB(gutter, 12, gutter, 12),
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Row(crossAxisAlignment: CrossAxisAlignment.baseline, textBaseline: TextBaseline.alphabetic, children: [
              Expanded(
                child: Text(who,
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

/// One message: sender, recipients, time, subject, attachments and the
/// plain-text body with tappable links, with Reply, Reply all and Forward
/// under it. Opening an unread message marks it read.
class MailMessageScreen extends StatefulWidget {
  final MailHeader header;
  final MailFolder folder;
  const MailMessageScreen({super.key, required this.header, this.folder = MailFolder.inbox});
  @override
  State<MailMessageScreen> createState() => _MailMessageScreenState();
}

class _MailMessageScreenState extends State<MailMessageScreen> {
  MailMessage? _message;
  Object? _error;
  late bool _unread = widget.header.unread;
  bool _busy = false;

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
    setState(() => _busy = true);
    try {
      await context.read<AppData>().setMailRead(widget.header.id, read: read, folder: widget.folder);
      if (mounted) setState(() => _unread = !read);
    } catch (e) {
      messenger.showSnackBar(SnackBar(
          content: Text(read ? "Couldn't mark it read in Mail." : "Couldn't mark it unread in Mail.")));
    }
    if (mounted) setState(() => _busy = false);
  }

  /// Moves the message, closes it and offers to move it back.
  Future<void> _move(MailFolder to) async {
    final data = context.read<AppData>();
    final messenger = ScaffoldMessenger.of(context);
    final navigator = Navigator.of(context);
    final from = widget.folder;
    final header = widget.header.withUnread(_unread);
    setState(() => _busy = true);
    try {
      final moved = await data.moveMail(header, from: from, to: to);
      navigator.pop();
      messenger.showSnackBar(SnackBar(
        content: Text('Moved to ${to.label}.'),
        action: moved == null
            ? null
            : SnackBarAction(
                label: 'Undo',
                onPressed: () => data.moveMail(moved, from: to, to: from).catchError((_) {
                  messenger.showSnackBar(SnackBar(content: Text("Couldn't move it back to ${from.label}.")));
                  return null;
                }),
              ),
      ));
    } catch (e) {
      messenger.showSnackBar(SnackBar(content: Text("Couldn't move it to ${to.label}.")));
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context);
    final muted = t.textTheme.bodyMedium?.copyWith(color: t.colorScheme.onSurfaceVariant);
    final h = widget.header;
    final m = _message;
    final folder = widget.folder;
    final subject = (m?.subject ?? h.subject).isEmpty ? '(no subject)' : (m?.subject ?? h.subject);
    final from = m?.from ?? h.from;
    final address = m?.fromAddress ?? '';
    // Sent mail can be forwarded; a reply would go back to the student.
    final canReply = folder != MailFolder.sent && folder != MailFolder.notes;
    final canForward = folder != MailFolder.notes;
    return HeadingScaffold(
      title: subject,
      actions: [
        if (m != null && folder != MailFolder.notes && folder != MailFolder.sent)
          IconButton(
            tooltip: _unread ? 'Mark as read' : 'Mark as unread',
            icon: Icon(_unread ? Icons.mark_email_read_outlined : Icons.mark_email_unread_outlined),
            onPressed: _busy ? null : () => _setRead(_unread),
          ),
        if (folder == MailFolder.deleted)
          IconButton(
            tooltip: 'Move to Inbox',
            icon: const Icon(Icons.restore_from_trash_outlined),
            onPressed: _busy ? null : () => _move(MailFolder.inbox),
          )
        else
          IconButton(
            tooltip: 'Delete',
            icon: const Icon(Icons.delete_outline),
            onPressed: _busy ? null : () => _move(MailFolder.deleted),
          ),
        if (folder == MailFolder.inbox || folder == MailFolder.junk)
          PopupMenuButton<MailFolder>(
            tooltip: 'More',
            enabled: !_busy,
            onSelected: _move,
            itemBuilder: (_) => [
              folder == MailFolder.inbox
                  ? const PopupMenuItem(value: MailFolder.junk, child: Text('Move to Junk'))
                  : const PopupMenuItem(value: MailFolder.inbox, child: Text('Not junk')),
            ],
          ),
      ],
      bottom: canForward
          ? _ReplyBar(
              reply: canReply,
              replyAll: canReply && m != null && replyAllRecipients(m).to.length + replyAllRecipients(m).cc.length > 1,
              onCompose: m == null ? null : (kind) => openCompose(context, kind: kind, ref: m),
            )
          : null,
      body: (heading) => SelectionArea(
        child: ListView(padding: const EdgeInsets.fromLTRB(gutter, 16, gutter, 24), children: [
          Text(subject, key: heading, style: t.textTheme.headlineSmall),
          const SizedBox(height: 12),
          if (from.isNotEmpty) Text(from, style: t.textTheme.titleSmall),
          if (address.isNotEmpty && address != from) Text(address, style: muted),
          if (m != null && m.to.isNotEmpty) Text('To ${m.to.map((a) => a.label).join(', ')}', style: muted),
          if (m != null && m.cc.isNotEmpty) Text('Cc ${m.cc.map((a) => a.label).join(', ')}', style: muted),
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

/// Reply, Reply all and Forward, under a rule at the foot of a message.
/// Disabled until the message has loaded: a reply needs its change key.
class _ReplyBar extends StatelessWidget {
  final bool reply;
  final bool replyAll;
  final void Function(ComposeKind kind)? onCompose;
  const _ReplyBar({required this.reply, required this.replyAll, required this.onCompose});

  @override
  Widget build(BuildContext context) {
    VoidCallback? go(ComposeKind kind) => onCompose == null ? null : () => onCompose!(kind);
    return DecoratedBox(
      decoration: BoxDecoration(border: Border(top: BorderSide(color: Theme.of(context).colorScheme.outlineVariant))),
      child: SafeArea(
        top: false,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
          child: Wrap(spacing: 4, children: [
            if (reply)
              TextButton.icon(
                  onPressed: go(ComposeKind.reply), icon: const Icon(Icons.reply), label: const Text('Reply')),
            if (replyAll)
              TextButton.icon(
                  onPressed: go(ComposeKind.replyAll),
                  icon: const Icon(Icons.reply_all),
                  label: const Text('Reply all')),
            TextButton.icon(
                onPressed: go(ComposeKind.forward),
                icon: const Icon(Icons.forward_outlined),
                label: const Text('Forward')),
          ]),
        ),
      ),
    );
  }
}
