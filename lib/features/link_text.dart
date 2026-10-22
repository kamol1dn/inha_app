import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';

import 'common.dart';

final _link = RegExp(
    r'''<(?:https?://|mailto:)[^\s<>"]+>|(?:https?://|www\.)[^\s<>"']+|[\w.+-]+@[\w-]+(?:\.[\w-]+)+''',
    caseSensitive: false);

/// A link found in plain text: the characters [start]..[end] of the text are
/// shown as [label] and open [uri].
typedef FoundLink = ({int start, int end, Uri uri, String label});

/// Web and mail addresses in plain text. Punctuation that ends the sentence
/// is left out of a link, and so is a closing bracket with no opening one
/// inside it.
///
/// Exchange writes an HTML link as `label<url>`. Such a bracketed address is
/// shown as its host name only (the label before it already says what it
/// is), so a 300-character tracking URL doesn't bury the message.
List<FoundLink> findLinks(String text) {
  final out = <FoundLink>[];
  for (final m in _link.allMatches(text)) {
    final raw = m[0]!;
    if (raw.startsWith('<')) {
      final inner = raw.substring(1, raw.length - 1);
      final uri = Uri.tryParse(inner);
      if (uri == null) continue;
      final isMail = uri.scheme.toLowerCase() == 'mailto';
      if (!isMail && uri.host.isEmpty) continue;
      final shown = isMail ? uri.path : uri.host;
      final spaced = m.start > 0 && text[m.start - 1].trim().isNotEmpty;
      out.add((start: m.start, end: m.end, uri: uri, label: spaced ? ' $shown' : shown));
      continue;
    }
    var s = raw;
    while (s.isNotEmpty) {
      final last = s[s.length - 1];
      final unbalanced = (last == ')' && '('.allMatches(s).length < ')'.allMatches(s).length) ||
          (last == ']' && '['.allMatches(s).length < ']'.allMatches(s).length);
      if (!'.,;:!?\'"'.contains(last) && !unbalanced) break;
      s = s.substring(0, s.length - 1);
    }
    final lower = s.toLowerCase();
    final web = lower.startsWith('http://') || lower.startsWith('https://') || lower.startsWith('www.');
    final uri = web
        ? Uri.tryParse(lower.startsWith('www.') ? 'https://$s' : s)
        : Uri(scheme: 'mailto', path: s);
    if (uri == null || (web && uri.host.isEmpty)) continue;
    out.add((start: m.start, end: m.start + s.length, uri: uri, label: s));
  }
  return out;
}

/// Plain text with its links tappable (opened outside the app).
class LinkText extends StatefulWidget {
  final String text;
  final TextStyle? style;
  const LinkText(this.text, {super.key, this.style});

  @override
  State<LinkText> createState() => _LinkTextState();
}

class _LinkTextState extends State<LinkText> {
  List<FoundLink> _links = const [];
  final _taps = <TapGestureRecognizer>[];

  @override
  void initState() {
    super.initState();
    _parse();
  }

  @override
  void didUpdateWidget(LinkText old) {
    super.didUpdateWidget(old);
    if (old.text != widget.text) _parse();
  }

  void _parse() {
    _dispose();
    _links = findLinks(widget.text);
    for (final l in _links) {
      _taps.add(TapGestureRecognizer()..onTap = () => openUrl(context, l.uri));
    }
  }

  void _dispose() {
    for (final t in _taps) {
      t.dispose();
    }
    _taps.clear();
  }

  @override
  void dispose() {
    _dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final primary = Theme.of(context).colorScheme.primary;
    final style = TextStyle(color: primary, decoration: TextDecoration.underline, decorationColor: primary);
    final spans = <InlineSpan>[];
    var at = 0;
    for (final (i, l) in _links.indexed) {
      if (l.start > at) spans.add(TextSpan(text: widget.text.substring(at, l.start)));
      final spaced = l.label.startsWith(' '); // only the host is underlined
      if (spaced) spans.add(const TextSpan(text: ' '));
      spans.add(TextSpan(text: spaced ? l.label.substring(1) : l.label, style: style, recognizer: _taps[i]));
      at = l.end;
    }
    if (at < widget.text.length) spans.add(TextSpan(text: widget.text.substring(at)));
    return Text.rich(TextSpan(style: widget.style, children: spans));
  }
}
