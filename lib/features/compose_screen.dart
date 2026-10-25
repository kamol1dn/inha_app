import 'dart:async';

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../core/session.dart';
import '../data/app_data.dart';
import '../data/services.dart';
import '../models/models.dart';
import '../services/mail/ews_soap.dart';
import '../ui/theme/status_colors.dart';
import 'common.dart';

/// Opens the composer for a new message, or a reply or forward of [ref].
void openCompose(BuildContext context, {ComposeKind kind = ComposeKind.fresh, MailMessage? ref}) =>
    Navigator.of(context).push(MaterialPageRoute(builder: (_) => ComposeScreen(kind: kind, ref: ref)));

/// Opens a saved draft in the composer.
void openDraft(BuildContext context, MailHeader draft) =>
    Navigator.of(context).push(MaterialPageRoute(builder: (_) => ComposeScreen(kind: ComposeKind.draft, draft: draft)));

/// Who a reply to all goes to, as Exchange works it out: the sender and the
/// To line, then the Cc line, without the student and without repeats.
({List<MailAddress> to, List<MailAddress> cc}) replyAllRecipients(MailMessage m) {
  final me = m.receivedBy.toLowerCase();
  final seen = <String>{};
  bool keep(MailAddress a) {
    final key = a.address.toLowerCase();
    return key.isNotEmpty && key != me && seen.add(key);
  }

  return (to: [MailAddress(m.from, m.fromAddress), ...m.to].where(keep).toList(), cc: m.cc.where(keep).toList());
}

/// The addresses typed into a recipient line: separated by commas,
/// semicolons or new lines; "Name <address>" keeps the address.
List<String> parseRecipients(String text) => [
      for (final part in text.split(RegExp(r'[,;\n]')))
        if (part.trim() case final p when p.isNotEmpty) RegExp(r'<([^<>]+)>').firstMatch(p)?.group(1)?.trim() ?? p,
    ];

final _address = RegExp(r'^[^@\s<>,;]+@[^@\s<>,;]+\.[^@\s<>,;]+$');

/// What went wrong sending or saving, in one plain sentence (DESIGN.md 10).
String composeError(Object e, {required bool sending}) {
  if (e is LoginRequired) return 'Mail sign-in needed.';
  if (isNetworkError(e)) return "Couldn't reach Mail. Check the connection.";
  if (e is EwsError && e.code.startsWith('ErrorInvalidRecipients')) return "Mail didn't accept one of the addresses.";
  return sending ? "Mail didn't send it. Try again." : "Mail didn't save the draft. Try again.";
}

/// Writing a message: a new one, a reply, a reply to all, a forward, or a
/// saved draft. Plain text. Leaving with something written asks whether to
/// keep it as a draft.
class ComposeScreen extends StatefulWidget {
  final ComposeKind kind;
  final MailMessage? ref; // the original of a reply or forward
  final MailHeader? draft; // the saved draft, loaded on open
  const ComposeScreen({super.key, this.kind = ComposeKind.fresh, this.ref, this.draft});
  @override
  State<ComposeScreen> createState() => _ComposeScreenState();
}

class _ComposeScreenState extends State<ComposeScreen> {
  final _to = TextEditingController();
  final _cc = TextEditingController();
  final _bcc = TextEditingController();
  final _subject = TextEditingController();
  final _body = TextEditingController();
  late bool _showCc = false;

  MailMessage? _draft; // the saved draft as loaded
  Object? _loadError;
  bool _busy = false;
  bool _done = false; // sent, saved or discarded: leave without asking

  ComposeKind get _kind => widget.kind;
  bool get _isReply => _kind == ComposeKind.reply || _kind == ComposeKind.replyAll;

  /// The text each field started from, to tell what the student changed.
  final _start = <TextEditingController, String>{};

  @override
  void initState() {
    super.initState();
    if (_kind == ComposeKind.draft) {
      _loadDraft();
    } else {
      _remember();
    }
  }

  void _remember() {
    for (final c in [_to, _cc, _bcc, _subject, _body]) {
      _start[c] = c.text;
    }
  }

  Future<void> _loadDraft() async {
    setState(() => _loadError = null);
    try {
      final m = await context.read<AppData>().mail.message(widget.draft!.id);
      if (!mounted) return;
      String line(List<MailAddress> l) => l.map((a) => a.address).where((a) => a.isNotEmpty).join(', ');
      _to.text = line(m.to);
      _cc.text = line(m.cc);
      _bcc.text = line(m.bcc);
      _subject.text = m.subject;
      _body.text = m.body;
      _remember();
      setState(() {
        _draft = m;
        _showCc = m.cc.isNotEmpty || m.bcc.isNotEmpty;
      });
    } catch (e) {
      if (mounted) setState(() => _loadError = e);
    }
  }

  @override
  void dispose() {
    for (final c in [_to, _cc, _bcc, _subject, _body]) {
      c.dispose();
    }
    super.dispose();
  }

  bool _changed(TextEditingController c) => c.text != (_start[c] ?? '');

  bool get _dirty => [_to, _cc, _bcc, _subject, _body].any(_changed);

  /// The message as it stands. A saved draft carries only what changed.
  OutgoingMail _outgoing() {
    List<String>? recipients(TextEditingController c) =>
        _kind == ComposeKind.draft && !_changed(c) ? null : parseRecipients(c.text);
    String? text(TextEditingController c) => _kind == ComposeKind.draft && !_changed(c) ? null : c.text;
    return switch (_kind) {
      ComposeKind.reply || ComposeKind.replyAll => OutgoingMail(_kind, ref: widget.ref, body: _body.text),
      ComposeKind.forward => OutgoingMail(_kind,
          ref: widget.ref, to: recipients(_to), cc: recipients(_cc), bcc: recipients(_bcc), body: _body.text),
      ComposeKind.fresh => OutgoingMail(_kind,
          to: recipients(_to), cc: recipients(_cc), bcc: recipients(_bcc), subject: _subject.text, body: _body.text),
      ComposeKind.draft => OutgoingMail(_kind,
          ref: _draft,
          to: recipients(_to),
          cc: recipients(_cc),
          bcc: recipients(_bcc),
          subject: text(_subject),
          body: text(_body)),
    };
  }

  /// The first problem with the recipients, or null when it can go.
  String? _check() {
    if (_isReply) return null;
    final all = [for (final c in [_to, _cc, _bcc]) ...parseRecipients(c.text)];
    if (all.isEmpty) return 'Add someone to send it to.';
    for (final a in all) {
      if (!_address.hasMatch(a)) return '"$a" is not an email address.';
    }
    return null;
  }

  Future<void> _send() async {
    final messenger = ScaffoldMessenger.of(context);
    final problem = _check();
    if (problem != null) {
      messenger.showSnackBar(SnackBar(content: Text(problem)));
      return;
    }
    FocusScope.of(context).unfocus();
    setState(() => _busy = true);
    try {
      await context.read<AppData>().sendMail(_outgoing());
      _done = true;
      if (mounted) Navigator.of(context).pop();
      messenger.showSnackBar(const SnackBar(content: Text('Sent.')));
    } catch (e) {
      messenger.showSnackBar(SnackBar(content: Text(composeError(e, sending: true))));
      if (mounted) setState(() => _busy = false);
    }
  }

  /// Saves to Drafts and leaves. Returns whether it was saved.
  Future<bool> _save() async {
    final messenger = ScaffoldMessenger.of(context);
    setState(() => _busy = true);
    try {
      await context.read<AppData>().saveMailDraft(_outgoing());
      _done = true;
      if (mounted) Navigator.of(context).pop();
      messenger.showSnackBar(const SnackBar(content: Text('Saved to Drafts.')));
      return true;
    } catch (e) {
      messenger.showSnackBar(SnackBar(content: Text(composeError(e, sending: false))));
      if (mounted) setState(() => _busy = false);
      return false;
    }
  }

  Future<void> _deleteDraft() async {
    final messenger = ScaffoldMessenger.of(context);
    final h = widget.draft!;
    setState(() => _busy = true);
    try {
      await context.read<AppData>().moveMail(h, from: MailFolder.drafts, to: MailFolder.deleted);
      _done = true;
      if (mounted) Navigator.of(context).pop();
      messenger.showSnackBar(const SnackBar(content: Text('Draft moved to Deleted.')));
    } catch (e) {
      messenger.showSnackBar(const SnackBar(content: Text("Couldn't delete the draft.")));
      if (mounted) setState(() => _busy = false);
    }
  }

  /// Leaving with unsaved writing: keep it as a draft, or let it go.
  Future<void> _confirmLeave() async {
    final keep = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(_kind == ComposeKind.draft ? 'Save your changes?' : 'Keep this as a draft?'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('Discard')),
          TextButton(onPressed: () => Navigator.pop(context, true), child: const Text('Save draft')),
        ],
      ),
    );
    if (!mounted || keep == null) return;
    if (keep) {
      await _save();
    } else {
      _done = true;
      Navigator.of(context).pop();
    }
  }

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context);
    final muted = t.textTheme.bodyMedium?.copyWith(color: t.colorScheme.onSurfaceVariant);
    final ref = widget.ref;
    final loading = _kind == ComposeKind.draft && _draft == null;
    final title = switch (_kind) {
      ComposeKind.fresh => 'New message',
      ComposeKind.reply || ComposeKind.replyAll => 'Reply',
      ComposeKind.forward => 'Forward',
      ComposeKind.draft => 'Draft',
    };
    final replyTo = switch (_kind) {
      ComposeKind.reply when ref != null => (to: [MailAddress(ref.from, ref.fromAddress)], cc: const <MailAddress>[]),
      ComposeKind.replyAll when ref != null => replyAllRecipients(ref),
      _ => null,
    };
    return PopScope(
      canPop: _done || _busy || loading || !_dirty,
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop) _confirmLeave();
      },
      child: Scaffold(
        appBar: AppBar(
          title: Text(title),
          actions: [
            IconButton(
              tooltip: 'Send',
              icon: const Icon(Icons.send_outlined),
              onPressed: _busy || loading ? null : _send,
            ),
            PopupMenuButton<String>(
              tooltip: 'More',
              enabled: !_busy && !loading,
              onSelected: (v) => v == 'save' ? _save() : _deleteDraft(),
              itemBuilder: (_) => [
                const PopupMenuItem(value: 'save', child: Text('Save draft')),
                if (_kind == ComposeKind.draft) const PopupMenuItem(value: 'delete', child: Text('Delete draft')),
              ],
            ),
          ],
          bottom: _busy
              ? const PreferredSize(preferredSize: Size.fromHeight(2), child: LinearProgressIndicator())
              : null,
        ),
        body: loading
            ? (_loadError == null
                ? const SkeletonRows(count: 3, timeColumn: false)
                : Padding(
                    padding: const EdgeInsets.only(right: 8, top: 8),
                    child: Row(children: [
                      Expanded(child: StatusLine(Status.danger, describeError(_loadError!, 'Mail'))),
                      TextButton(onPressed: _loadDraft, child: const Text('Retry')),
                    ]),
                  ))
            : ListView(children: [
                if (replyTo != null) ...[
                  _FixedLine('To', replyTo.to.map((a) => a.label).join(', ')),
                  if (replyTo.cc.isNotEmpty) ...[
                    const Rule(inset: 0),
                    _FixedLine('Cc', replyTo.cc.map((a) => a.label).join(', ')),
                  ],
                ] else ...[
                  RecipientField(
                    label: 'To',
                    controller: _to,
                    enabled: !_busy,
                    trailing: _showCc
                        ? null
                        : TextButton(onPressed: () => setState(() => _showCc = true), child: const Text('Cc, Bcc')),
                  ),
                  if (_showCc) ...[
                    const Rule(inset: 0),
                    RecipientField(label: 'Cc', controller: _cc, enabled: !_busy),
                    const Rule(inset: 0),
                    RecipientField(label: 'Bcc', controller: _bcc, enabled: !_busy),
                  ],
                ],
                const Rule(inset: 0),
                if (_kind == ComposeKind.fresh || _kind == ComposeKind.draft)
                  _Line(
                    label: 'Subject',
                    child: TextField(
                      controller: _subject,
                      enabled: !_busy,
                      textCapitalization: TextCapitalization.sentences,
                      style: t.textTheme.bodyLarge,
                      decoration: _bare(''),
                      onChanged: (_) => setState(() {}),
                    ),
                  )
                else
                  _FixedLine('Subject', '${_isReply ? 'RE' : 'FW'}: ${ref?.subject ?? ''}'),
                const Rule(inset: 0),
                Padding(
                  padding: const EdgeInsets.fromLTRB(gutter, 16, gutter, 16),
                  child: TextField(
                    controller: _body,
                    enabled: !_busy,
                    autofocus: _kind != ComposeKind.fresh && _kind != ComposeKind.draft,
                    keyboardType: TextInputType.multiline,
                    textCapitalization: TextCapitalization.sentences,
                    minLines: 8,
                    maxLines: null,
                    style: t.textTheme.bodyLarge,
                    decoration: _bare('Write your message'),
                    onChanged: (_) => setState(() {}),
                  ),
                ),
                if (ref != null)
                  Padding(
                    padding: const EdgeInsets.fromLTRB(gutter, 0, gutter, 24),
                    child: Text(
                      _kind == ComposeKind.forward
                          ? 'The original message and its attachments go below what you write.'
                          : 'The message you are replying to is quoted below what you write.',
                      style: muted,
                    ),
                  ),
              ]),
      ),
    );
  }
}

/// A field with no box: the composer's lines are set off by rules instead.
InputDecoration _bare(String hint) => InputDecoration(
      hintText: hint,
      isCollapsed: true,
      border: InputBorder.none,
      enabledBorder: InputBorder.none,
      focusedBorder: InputBorder.none,
      disabledBorder: InputBorder.none,
    );

/// A header line of the composer: a muted label, then the field.
class _Line extends StatelessWidget {
  final String label;
  final Widget child;
  final Widget? trailing;
  const _Line({required this.label, required this.child, this.trailing});

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context);
    return ConstrainedBox(
      constraints: const BoxConstraints(minHeight: 52),
      child: Padding(
        padding: EdgeInsets.only(left: gutter, right: trailing == null ? gutter : 8),
        child: Row(children: [
          SizedBox(
            width: 64,
            child: Text(label, style: t.textTheme.bodyMedium?.copyWith(color: t.colorScheme.onSurfaceVariant)),
          ),
          Expanded(child: child),
          ?trailing,
        ]),
      ),
    );
  }
}

/// A header line Exchange fills in (a reply's recipients, a prefixed subject).
class _FixedLine extends StatelessWidget {
  final String label;
  final String text;
  const _FixedLine(this.label, this.text);

  @override
  Widget build(BuildContext context) => _Line(
        label: label,
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 14),
          child: Text(text, style: Theme.of(context).textTheme.bodyLarge),
        ),
      );
}

/// A recipient line. While a name is being typed, people and lists from the
/// university directory that match it show under the line; tapping one puts
/// in their address.
class RecipientField extends StatefulWidget {
  final String label;
  final TextEditingController controller;
  final bool enabled;
  final Widget? trailing;
  const RecipientField({super.key, required this.label, required this.controller, this.enabled = true, this.trailing});

  @override
  State<RecipientField> createState() => _RecipientFieldState();
}

class _RecipientFieldState extends State<RecipientField> {
  Timer? _wait;
  int _asked = 0;
  List<MailAddress> _matches = const [];

  /// The entry being typed: the text after the last separator.
  String get _typing => widget.controller.text.split(RegExp(r'[,;\n]')).last.trim();

  void _changed(String _) {
    _wait?.cancel();
    final q = _typing;
    // Three letters before asking the directory; a whole address needs no help.
    if (q.length < 3 || _address.hasMatch(q)) {
      if (_matches.isNotEmpty) setState(() => _matches = const []);
      return;
    }
    _wait = Timer(const Duration(milliseconds: 350), () => _lookup(q));
  }

  Future<void> _lookup(String q) async {
    final asked = ++_asked;
    List<MailAddress> found;
    try {
      found = await context.read<AppData>().mail.lookup(q);
    } catch (_) {
      found = const []; // suggestions are a help, not a requirement
    }
    if (mounted && asked == _asked && q == _typing) setState(() => _matches = found.take(6).toList());
  }

  void _pick(MailAddress a) {
    final c = widget.controller;
    final done = parseRecipients(c.text)..removeLast();
    final text = '${[...done, a.address].join(', ')}, ';
    c.value = TextEditingValue(text: text, selection: TextSelection.collapsed(offset: text.length));
    setState(() => _matches = const []);
  }

  @override
  void dispose() {
    _wait?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context);
    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      _Line(
        label: widget.label,
        trailing: widget.trailing,
        child: TextField(
          controller: widget.controller,
          enabled: widget.enabled,
          keyboardType: TextInputType.emailAddress,
          autocorrect: false,
          style: t.textTheme.bodyLarge,
          decoration: _bare('Name or address'),
          onChanged: _changed,
        ),
      ),
      for (final a in _matches)
        InkWell(
          onTap: () => _pick(a),
          child: Padding(
            padding: const EdgeInsets.fromLTRB(gutter + 64, 8, gutter, 8),
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(a.label, maxLines: 1, overflow: TextOverflow.ellipsis, style: t.textTheme.bodyLarge),
              if (a.name.isNotEmpty)
                Text(a.address,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: t.textTheme.bodyMedium?.copyWith(color: t.colorScheme.onSurfaceVariant)),
            ]),
          ),
        ),
    ]);
  }
}
