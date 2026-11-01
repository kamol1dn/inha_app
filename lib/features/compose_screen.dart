import 'dart:async';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../core/session.dart';
import '../data/app_data.dart';
import '../models/models.dart';
import '../services/mail/ews_soap.dart';
import '../ui/format/format.dart';
import '../ui/theme/app_text.dart';
import '../ui/theme/status_colors.dart';
import 'common.dart';
import 'settings_screen.dart';

/// Opens the composer for a new message, or a reply or forward of [ref].
void openCompose(BuildContext context, {ComposeKind kind = ComposeKind.fresh, MailMessage? ref}) =>
    Navigator.of(context).push(MaterialPageRoute(builder: (_) => ComposeScreen(kind: kind, ref: ref)));

/// Opens a saved draft in the composer. Finishes when the composer closes.
Future<void> openDraft(BuildContext context, MailHeader draft) =>
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

const _tooBigCodes = {'ErrorMessageSizeExceeded', 'ErrorAttachmentSizeLimitExceeded', 'ErrorRequestEntityTooLarge'};

/// What went wrong sending or saving, in one plain sentence (DESIGN.md 10).
/// Files go on a saved message, so with [withFiles] part of it may be in Drafts.
String composeError(Object e, {required bool sending, bool withFiles = false}) {
  if (e is LoginRequired) return 'Mail sign-in needed.';
  final tooBig = e is EwsError ? _tooBigCodes.contains(e.code) : e is ParseError && e.what == 'mail (HTTP 413)';
  final what = isNetworkError(e)
      ? "Couldn't reach Mail. Check the connection."
      : tooBig
          ? 'Mail refused the attachment: it is too big.'
          : e is EwsError && e.code.startsWith('ErrorInvalidRecipients')
              ? "Mail didn't accept one of the addresses."
              : sending
                  ? "Mail didn't send it. Try again."
                  : "Mail didn't save the draft. Try again.";
  return withFiles ? '$what A copy may be in Drafts.' : what;
}

/// "Sign in" on a snack bar, for a mail action the login stopped.
SnackBarAction signInAction(NavigatorState navigator) => SnackBarAction(
      label: 'Sign in',
      onPressed: () => navigator.push(MaterialPageRoute(builder: (_) => const SettingsScreen())),
    );

/// A file the student chose: its name and size, and its content only once
/// read, so that a file too big to send never comes into memory.
class PickedFile {
  final String name;
  final int? size; // null when Android didn't say
  final Future<List<int>> Function() read;
  const PickedFile(this.name, this.size, this.read);
}

/// Asks Android for files. Empty when the student backs out.
Future<List<PickedFile>> pickMailFiles() async => [
      for (final f in await FilePicker.pickFiles()) PickedFile(f.name, await f.length(), f.readAsBytes),
    ];

/// Android's picker hands over a copy in the app's cache: gone once it is read.
Future<void> _clearPickedCopies() async {
  try {
    await FilePicker.clearTemporaryFiles();
  } catch (_) {
    // Only a tidy-up: the system clears the cache in the end.
  }
}

/// Writing a message: a new one, a reply, a reply to all, a forward, or a
/// saved draft. Plain text, with files attached if wanted. Leaving with
/// something written asks whether to keep it as a draft.
class ComposeScreen extends StatefulWidget {
  final ComposeKind kind;
  final MailMessage? ref; // the original of a reply or forward
  final MailHeader? draft; // the saved draft, loaded on open
  final Future<List<PickedFile>> Function() pickFiles;
  const ComposeScreen(
      {super.key, this.kind = ComposeKind.fresh, this.ref, this.draft, this.pickFiles = pickMailFiles});
  @override
  State<ComposeScreen> createState() => _ComposeScreenState();
}

class _ComposeScreenState extends State<ComposeScreen> {
  final _to = TextEditingController();
  final _cc = TextEditingController();
  final _bcc = TextEditingController();
  final _subject = TextEditingController();
  final _body = TextEditingController();
  final _files = <MailFile>[]; // new files; a saved draft keeps the ones it has
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

  bool get _dirty => _files.isNotEmpty || [_to, _cc, _bcc, _subject, _body].any(_changed);

  /// The message as it stands. A saved draft carries only what changed.
  OutgoingMail _outgoing() {
    List<String>? recipients(TextEditingController c) =>
        _kind == ComposeKind.draft && !_changed(c) ? null : parseRecipients(c.text);
    String? text(TextEditingController c) => _kind == ComposeKind.draft && !_changed(c) ? null : c.text;
    return switch (_kind) {
      ComposeKind.reply || ComposeKind.replyAll =>
        OutgoingMail(_kind, ref: widget.ref, body: _body.text, attachments: _files),
      ComposeKind.forward => OutgoingMail(_kind,
          ref: widget.ref,
          to: recipients(_to),
          cc: recipients(_cc),
          bcc: recipients(_bcc),
          body: _body.text,
          attachments: _files),
      ComposeKind.fresh => OutgoingMail(_kind,
          to: recipients(_to),
          cc: recipients(_cc),
          bcc: recipients(_bcc),
          subject: _subject.text,
          body: _body.text,
          attachments: _files),
      ComposeKind.draft => OutgoingMail(_kind,
          ref: _draft,
          to: recipients(_to),
          cc: recipients(_cc),
          bcc: recipients(_bcc),
          subject: text(_subject),
          body: text(_body),
          attachments: _files),
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

  /// Adds what the student picks, up to what a message can carry.
  Future<void> _attach() async {
    final messenger = ScaffoldMessenger.of(context);
    final List<PickedFile> picked;
    try {
      picked = await widget.pickFiles();
    } catch (_) {
      messenger.showSnackBar(const SnackBar(content: Text("Couldn't open the file picker.")));
      return;
    }
    if (picked.isEmpty || !mounted) return;
    setState(() => _busy = true);
    for (final f in picked) {
      final room = maxMailAttachmentBytes - _files.fold<int>(0, (n, x) => n + x.bytes.length);
      String? problem;
      try {
        final bytes = (f.size ?? 0) > room ? null : await f.read();
        if (bytes == null || bytes.length > room) {
          problem = '${f.name} is too big to add. A message can carry ${fileSize(maxMailAttachmentBytes)} of new files.';
        } else if (mounted) {
          setState(() => _files.add(MailFile(name: f.name, bytes: bytes)));
        }
      } catch (_) {
        problem = "Couldn't read ${f.name}.";
      }
      if (problem != null) messenger.showSnackBar(SnackBar(content: Text(problem)));
    }
    unawaited(_clearPickedCopies());
    if (mounted) setState(() => _busy = false);
  }

  /// Says why a send or save failed. The composer stays open with the writing.
  void _failed(ScaffoldMessengerState messenger, NavigatorState navigator, Object e, {required bool sending}) {
    messenger.showSnackBar(SnackBar(
      content: Text(composeError(e, sending: sending, withFiles: _files.isNotEmpty)),
      action: e is LoginRequired ? signInAction(navigator) : null,
    ));
    if (mounted) setState(() => _busy = false);
  }

  Future<void> _send() async {
    final messenger = ScaffoldMessenger.of(context);
    final navigator = Navigator.of(context);
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
      _failed(messenger, navigator, e, sending: true);
    }
  }

  /// Saves to Drafts and leaves. Returns whether it was saved.
  Future<bool> _save() async {
    final messenger = ScaffoldMessenger.of(context);
    final navigator = Navigator.of(context);
    setState(() => _busy = true);
    try {
      await context.read<AppData>().saveMailDraft(_outgoing());
      _done = true;
      if (mounted) Navigator.of(context).pop();
      messenger.showSnackBar(const SnackBar(content: Text('Saved to Drafts.')));
      return true;
    } catch (e) {
      _failed(messenger, navigator, e, sending: false);
      return false;
    }
  }

  Future<void> _deleteDraft() async {
    final data = context.read<AppData>();
    final messenger = ScaffoldMessenger.of(context);
    final h = widget.draft!;
    setState(() => _busy = true);
    try {
      final moved = await data.moveMail(h, from: MailFolder.drafts, to: MailFolder.deleted);
      _done = true;
      if (mounted) Navigator.of(context).pop();
      messenger.showSnackBar(SnackBar(
        content: const Text('Draft moved to Deleted.'),
        action: moved == null
            ? null
            : SnackBarAction(
                label: 'Undo',
                onPressed: () => data.moveMail(moved, from: MailFolder.deleted, to: MailFolder.drafts).catchError((_) {
                  messenger.showSnackBar(const SnackBar(content: Text("Couldn't move it back to Drafts.")));
                  return null;
                }),
              ),
      ));
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
      // Decided when Back is pressed, from what the fields hold then. While a
      // send or save is running Back waits, so a failure can't lose the writing.
      canPop: false,
      onPopInvokedWithResult: (didPop, _) {
        if (didPop || _busy) return;
        if (_done || loading || !_dirty) {
          Navigator.of(context).pop();
        } else {
          _confirmLeave();
        }
      },
      child: Scaffold(
        appBar: AppBar(
          title: Text(title),
          actions: [
            IconButton(
              tooltip: 'Attach file',
              icon: const Icon(Icons.attach_file),
              onPressed: _busy || loading ? null : _attach,
            ),
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
                    child: MailLoadError(_loadError!, onRetry: _loadDraft),
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
                      decoration: bareField('', padding: _linePadding),
                    ),
                  )
                else
                  _FixedLine('Subject', '${_isReply ? 'RE' : 'FW'}: ${ref?.subject ?? ''}'),
                const Rule(inset: 0),
                // What a saved draft already carries stays with it.
                for (final a in _draft?.attachments ?? const <MailAttachment>[]) ...[
                  AttachmentRow(name: a.name, size: a.size),
                  const Rule(inset: 0),
                ],
                for (final f in _files) ...[
                  AttachmentRow(
                    name: f.name,
                    size: f.bytes.length,
                    trailing: IconButton(
                      tooltip: 'Remove ${f.name}',
                      icon: const Icon(Icons.close),
                      onPressed: _busy ? null : () => setState(() => _files.remove(f)),
                    ),
                  ),
                  const Rule(inset: 0),
                ],
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
                    decoration: bareField('Write your message'),
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
InputDecoration bareField(String hint, {EdgeInsetsGeometry padding = EdgeInsets.zero}) => InputDecoration(
      hintText: hint,
      isCollapsed: true,
      contentPadding: padding,
      border: InputBorder.none,
      enabledBorder: InputBorder.none,
      focusedBorder: InputBorder.none,
      disabledBorder: InputBorder.none,
    );

/// Makes a header field as tall as its line, so a tap anywhere on it lands.
const _linePadding = EdgeInsets.symmetric(vertical: 14);

/// The label column of a header line, which grows with the text.
double _labelWidth(BuildContext context) => MediaQuery.textScalerOf(context).scale(64);

/// Mail's error row: Sign in when the login is what stopped it, and then it
/// tries again by itself; otherwise Retry (DESIGN.md 8, Errors).
class MailLoadError extends StatelessWidget {
  final Object error;
  final VoidCallback onRetry;
  final EdgeInsetsGeometry padding;
  const MailLoadError(this.error,
      {super.key, required this.onRetry, this.padding = const EdgeInsets.symmetric(horizontal: gutter, vertical: 4)});

  Future<void> _signIn(BuildContext context) async {
    await Navigator.of(context).push(MaterialPageRoute(builder: (_) => const SettingsScreen()));
    if (context.mounted) onRetry();
  }

  @override
  Widget build(BuildContext context) => Row(children: [
        Expanded(child: StatusLine(Status.danger, describeError(error, 'Mail'), padding: padding)),
        if (error is LoginRequired)
          TextButton(onPressed: () => _signIn(context), child: const Text('Sign in'))
        else
          TextButton(onPressed: onRetry, child: const Text('Retry')),
      ]);
}

/// A file on a message or in the composer: its name and size, at least 48dp
/// tall. With [onTap] the whole row is the target.
class AttachmentRow extends StatelessWidget {
  final String name;
  final int size; // bytes; 0 when unknown
  final Widget? trailing;
  final VoidCallback? onTap;
  const AttachmentRow({super.key, required this.name, this.size = 0, this.trailing, this.onTap});

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context);
    final muted = t.colorScheme.onSurfaceVariant;
    final row = ConstrainedBox(
      constraints: const BoxConstraints(minHeight: 48),
      child: Padding(
        padding: EdgeInsets.only(left: gutter, right: trailing is IconButton ? 4 : gutter),
        child: Row(children: [
          Icon(Icons.attach_file, size: 18, color: muted),
          const SizedBox(width: 8),
          Expanded(
            child: Text(name.isEmpty ? 'Attachment' : name,
                maxLines: 1, overflow: TextOverflow.ellipsis, style: t.textTheme.bodyMedium),
          ),
          if (size > 0) ...[
            const SizedBox(width: 8),
            Text(fileSize(size), style: t.textTheme.bodyMedium?.tnum.copyWith(color: muted)),
          ],
          if (trailing != null) ...[const SizedBox(width: 8), trailing!],
        ]),
      ),
    );
    return onTap == null ? row : Semantics(button: true, child: InkWell(onTap: onTap, child: row));
  }
}

/// A header line of the composer: a muted label, then the field. The two read
/// as one to a screen reader; the label is a sibling of the field otherwise.
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
          Expanded(
            child: MergeSemantics(
              child: Row(children: [
                SizedBox(
                  width: _labelWidth(context),
                  child: Text(label,
                      softWrap: false, style: t.textTheme.bodyMedium?.copyWith(color: t.colorScheme.onSurfaceVariant)),
                ),
                Expanded(child: child),
              ]),
            ),
          ),
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
          decoration: bareField('Name or address', padding: _linePadding),
          onChanged: _changed,
        ),
      ),
      for (final a in _matches)
        InkWell(
          onTap: () => _pick(a),
          child: Padding(
            padding: EdgeInsets.fromLTRB(gutter + _labelWidth(context), 12, gutter, 12),
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
