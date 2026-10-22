/// Pure parsers for INS / ITIS (ins.inha.uz) pages. No I/O here, so every
/// function can be tested against fixtures. See docs/ENDPOINTS.md.
library;

import 'dart:convert';

import 'package:html/dom.dart';
import 'package:html/parser.dart' as html_parser;

import '../../core/session.dart';
import '../../models/models.dart';

// ---------------------------------------------------------------------------
// Bytes -> text
// ---------------------------------------------------------------------------

/// The single place INS response bytes become text (HTML pages and the
/// grades XML alike), so a real EUC-KR decoder can be swapped in later.
///
/// The grades XML declares `encoding="euc-kr"`, which Dart cannot decode
/// natively. Everything the app reads from it (codes, English course names,
/// letters, numbers) is ASCII, and ASCII is identical in EUC-KR, UTF-8 and
/// Latin-1. So: pure ASCII is returned as is; otherwise strict UTF-8 is tried
/// (in case the server actually sends UTF-8); otherwise Latin-1, which never
/// fails and keeps every ASCII byte intact while turning Korean text (if any)
/// into mojibake that the app does not show.
String decodeInsBytes(List<int> bytes) {
  String text;
  if (bytes.every((b) => b < 0x80)) {
    text = latin1.decode(bytes);
  } else {
    try {
      text = utf8.decode(bytes);
    } on FormatException {
      text = latin1.decode(bytes);
    }
  }
  return text.startsWith('\uFEFF') ? text.substring(1) : text;
}

// ---------------------------------------------------------------------------
// Login page (Start.aspx)
// ---------------------------------------------------------------------------

Document _doc(String html) => html_parser.parse(html);

/// `form1`, or the first form, or null.
Element? _form1(Document doc) =>
    doc.querySelector('form#form1') ??
    doc.querySelector('form[name="form1"]') ??
    doc.querySelector('form');

String? _lowerName(Element e) => e.attributes['name']?.toLowerCase();

bool _isHidden(Element e) => (e.attributes['type'] ?? '').trim().toLowerCase() == 'hidden';

/// Every `input[type=hidden]` inside `form1` (name -> value, document order),
/// i.e. `__VIEWSTATE`, `__VIEWSTATEGENERATOR`, `__EVENTVALIDATION`,
/// `errorMessage` and whatever else WebForms put there. All of them go back in
/// the login POST.
///
/// If `form1` exists but the HTML parser left the inputs outside it (a form
/// inside a table does that), falls back to every hidden input in the page.
Map<String, String> hiddenInputs(String html) {
  final doc = _doc(html);
  Map<String, String> collect(Element? scope) {
    final out = <String, String>{};
    if (scope == null) return out;
    for (final input in scope.querySelectorAll('input')) {
      final name = input.attributes['name'];
      if (name == null || name.isEmpty || !_isHidden(input)) continue;
      out[name] = input.attributes['value'] ?? '';
    }
    return out;
  }

  final fromForm = collect(_form1(doc));
  return fromForm.isNotEmpty ? fromForm : collect(doc.documentElement);
}

/// The `action` attribute of `form1` as written (e.g. `./Start.aspx`), or null.
String? formAction(String html) {
  final action = _form1(_doc(html))?.attributes['action']?.trim();
  return (action == null || action.isEmpty) ? null : action;
}

/// True for the ITIS login form: it has the `txtInhaID` / `txtPW` inputs.
bool isInsLoginPage(String html) => _doc(html).querySelectorAll('input').any((e) {
      final name = _lowerName(e) ?? e.id.toLowerCase();
      return name.endsWith('txtpw') || name.endsWith('txtinhaid');
    });

/// The server's reason for a failed login: the hidden `errorMessage` input
/// that Start.aspx fills in. Null when there is none or it is blank.
String? loginError(String html) {
  for (final input in _doc(html).querySelectorAll('input')) {
    final name = _lowerName(input) ?? input.id.toLowerCase();
    if (name != 'errormessage') continue;
    final value = _squash(input.attributes['value'] ?? '');
    return value.isEmpty ? null : value;
  }
  return null;
}

final _loginRedirect = RegExp(
  r'''location(?:\.href)?\s*(?:=\s*|\.(?:replace|assign)\s*\(\s*)['"][^'"]*start\.aspx''',
  caseSensitive: false,
);
final _sessionMessage =
    RegExp(r'session\s+(?:has\s+|is\s+)?(?:expired|timed?\s*out)', caseSensitive: false);

/// True when a page is the login form, or a stub that bounces the browser to
/// Start.aspx, or says the session expired. Pages that legitimately contain a
/// logout script also match, so callers check for the content they expected
/// first and only then ask this.
bool isSessionExpired(String html) =>
    isInsLoginPage(html) || _loginRedirect.hasMatch(html) || _sessionMessage.hasMatch(html);

// ---------------------------------------------------------------------------
// Menu (left.aspx)
// ---------------------------------------------------------------------------

String _squash(String s) => s.replaceAll(RegExp(r'[\s\u00a0]+'), ' ').trim();

final _quotedAspx = RegExp(r'''['"]([^'"\s<>]*\.aspx[^'"\s<>]*)['"]''', caseSensitive: false);

/// The menu target of an `<a>`: its href, or for `href="#"` /
/// `javascript:` links, the first quoted `.aspx` URL in its href/onclick.
String? _anchorTarget(Element a) {
  final href = (a.attributes['href'] ?? '').trim();
  final lower = href.toLowerCase();
  if (href.isNotEmpty && !href.startsWith('#') && !lower.startsWith('javascript:')) return href;
  for (final source in [href, a.attributes['onclick'] ?? '']) {
    final m = _quotedAspx.firstMatch(source);
    if (m != null) return m.group(1);
  }
  return null;
}

/// The menu link whose text (whitespace-collapsed, trimmed) equals [text],
/// resolved against [base] (default `/ITIS/`, where left.aspx lives). Returns
/// e.g. `/ITIS/main.aspx?param=<opaque>&ENGYN=Y` with the opaque param exactly
/// as the page had it, or null. Exact match wins; a case-insensitive match is
/// the fallback; last, the raw source is searched for `href="...">text<`, which
/// catches menus written into the page by script (`document.write`, innerHTML).
String? findMenuLink(String leftHtml, String text, {String base = '/ITIS/'}) {
  final want = _squash(text);
  final anchors = _doc(leftHtml).querySelectorAll('a');
  Element? hit;
  for (final a in anchors) {
    if (_squash(a.text) == want && _anchorTarget(a) != null) {
      hit = a;
      break;
    }
  }
  hit ??= anchors.cast<Element?>().firstWhere(
        (a) => _squash(a!.text).toLowerCase() == want.toLowerCase() && _anchorTarget(a) != null,
        orElse: () => null,
      );
  final target = hit == null ? _scriptedMenuTarget(leftHtml, want) : _anchorTarget(hit);
  return target == null ? null : Uri.parse(base).resolve(target).toString();
}

String? _scriptedMenuTarget(String source, String text) {
  if (text.isEmpty) return null;
  const gap = r'(?:\s|&nbsp;|\\[nrt])';
  final words = text.split(' ').map(RegExp.escape).join('$gap+');
  final m = RegExp(
    r'''href\s*=\s*\\?["']([^"'\\]*\.aspx[^"'\\]*)\\?["'][^>]*>''' '(?:$gap|<[^>]*>)*' '$words' '$gap*<',
    caseSensitive: false,
  ).firstMatch(source);
  return m?.group(1)?.replaceAll('&amp;', '&');
}

final _menuParam = RegExp(r'main\.aspx\?param=', caseSensitive: false);

/// True when the page source has a `main.aspx?param=` menu link anywhere
/// (markup or script), i.e. it is a logged-in left.aspx.
bool hasMenuLinks(String leftHtml) => _menuParam.hasMatch(leftHtml);

// ---------------------------------------------------------------------------
// Grades pages (main.aspx -> MarkView.aspx -> MarkView_rpx.aspx)
// ---------------------------------------------------------------------------

/// URLs on a page that mention [hint] (case-insensitive): `frame`/`iframe`
/// srcs first, then any other quoted URL (script redirects, `src = '...'`
/// assignments, links). Raw, unresolved, in document order, no duplicates.
List<String> pageRefs(String html, String hint) {
  final needle = hint.toLowerCase();
  final out = <String>[];
  void add(String? ref) {
    final r = ref?.trim();
    if (r == null || r.isEmpty || out.contains(r)) return;
    if (r.toLowerCase().startsWith('javascript:')) return;
    if (r.toLowerCase().contains(needle)) out.add(r);
  }

  for (final f in _doc(html).querySelectorAll('frame, iframe')) {
    add(f.attributes['src']);
  }
  final quoted = RegExp('[\'"]([^\'"\\s<>]*${RegExp.escape(hint)}[^\'"\\s<>]*)[\'"]',
      caseSensitive: false);
  for (final m in quoted.allMatches(html)) {
    add(m.group(1));
  }
  return out;
}

/// `ViewerReportInForm("<report>.rpx", "<xml url>", ...)`, any ViewerReportIn* variant.
final _viewerCall = RegExp(
  r'''ViewerReportIn\w*\s*\(\s*["'][^"']*["']\s*,\s*["']([^"']+)["']''',
);

final _fileUrlAssign = RegExp(
  r'''fileurl\s*\.\s*value\s*=\s*(?:'([^']*)'|"([^"]*)")''',
  caseSensitive: false,
);

/// The grades XML URL from MarkView_rpx.aspx, relative to that page.
///
/// The server's raw page calls the Cabsoft viewer:
/// `ViewerReportInForm("HJ_03507_R01.rpx","MarkView_xml.aspx?Value=...",...)`,
/// and the second argument is the URL. The viewer script then builds
/// `window.frm.fileurl` in the browser, which is what a live DOM shows; those
/// forms are kept as fallbacks. Null if absent. Both GET and POST of the URL as
/// written return the XML (checked against the live site 2026-10-23).
String? extractXmlUrl(String rpxHtml) {
  final viewer = _viewerCall.firstMatch(rpxHtml);
  if (viewer != null) return viewer.group(1)!.trim();
  for (final m in _fileUrlAssign.allMatches(rpxHtml)) {
    final raw = (m.group(1) ?? m.group(2) ?? '').trim();
    if (raw.isEmpty) continue;
    return raw.replaceAll(r'\/', '/').replaceAll(r'\\', r'\');
  }
  for (final input in _doc(rpxHtml).querySelectorAll('input')) {
    if (_lowerName(input) != 'fileurl') continue;
    final v = (input.attributes['value'] ?? '').trim();
    if (v.isNotEmpty) return v;
  }
  return null;
}

// ---------------------------------------------------------------------------
// Grades XML (MarkView_xml.aspx)
// ---------------------------------------------------------------------------

/// Elements whose content is skipped unread by the XML reader. `JUMIN` is the
/// national ID number: it is never read, stored or shown.
const _redacted = {'jumin'};

class _XmlElement {
  _XmlElement(this.name);
  final String name; // lowercased
  final List<_XmlElement> children = [];
  final StringBuffer _text = StringBuffer();

  /// Own text (not descendants'), whitespace-collapsed.
  String get text => _squash(_text.toString());

  _XmlElement? child(String name) {
    for (final c in children) {
      if (c.name == name) return c;
    }
    return null;
  }

  String field(String name) => child(name)?.text ?? '';

  Iterable<_XmlElement> descendants(String name) sync* {
    for (final c in children) {
      if (c.name == name) yield c;
      yield* c.descendants(name);
    }
  }
}

final _xmlToken = RegExp(
  r'<!\[CDATA\[([\s\S]*?)\]\]>' // 1: CDATA
  r'|<!--[\s\S]*?-->' // comment
  r'|<\?[\s\S]*?\?>' // <?xml ...?>
  r'|<![^>]*>' // DOCTYPE
  r'|</\s*([^\s>]+)\s*>' // 2: end tag
  r'''|<([A-Za-z_][\w:.\-]*)((?:[^>"']|"[^"]*"|'[^']*')*?)(/?)>''', // 3: name, 4: attrs, 5: '/'
);

final _entity = RegExp(r'&(#x[0-9a-fA-F]+|#\d+|amp|lt|gt|quot|apos);');

String _unescape(String s) => s.replaceAllMapped(_entity, (m) {
      final e = m.group(1)!;
      switch (e) {
        case 'amp':
          return '&';
        case 'lt':
          return '<';
        case 'gt':
          return '>';
        case 'quot':
          return '"';
        case 'apos':
          return "'";
      }
      final code = e.startsWith('#x') ? int.tryParse(e.substring(2), radix: 16) : int.tryParse(e.substring(1));
      return (code == null || code > 0x10FFFF) ? m.group(0)! : String.fromCharCode(code);
    });

/// A small, tolerant XML reader: enough for the flat DataSet-style XML INS
/// serves (elements and text; attributes ignored). Tag names are lowercased.
/// Self-closing tags, comments, CDATA and entities are handled; a stray end
/// tag is ignored and a missing one is implied. `_redacted` elements are
/// skipped without their content ever being extracted.
_XmlElement _readXml(String xml) {
  final root = _XmlElement('#document');
  final stack = <_XmlElement>[root];
  var pos = 0;
  while (pos < xml.length) {
    final it = _xmlToken.allMatches(xml, pos).iterator;
    if (!it.moveNext()) break;
    final m = it.current;
    if (m.start > pos) stack.last._text.write(_unescape(xml.substring(pos, m.start)));
    pos = m.end;

    if (m.group(1) != null) {
      stack.last._text.write(m.group(1));
    } else if (m.group(2) != null) {
      final name = m.group(2)!.toLowerCase();
      final at = stack.lastIndexWhere((e) => e.name == name);
      if (at > 0) stack.removeRange(at, stack.length);
    } else if (m.group(3) != null) {
      final name = m.group(3)!.toLowerCase();
      final selfClosing = m.group(5) == '/';
      if (_redacted.contains(name)) {
        if (!selfClosing) {
          final end = RegExp('</\\s*${RegExp.escape(name)}\\s*>', caseSensitive: false)
              .allMatches(xml, pos);
          pos = end.isEmpty ? xml.length : end.first.end;
        }
        continue;
      }
      final el = _XmlElement(name);
      stack.last.children.add(el);
      if (!selfClosing) stack.add(el);
    }
  }
  return root;
}

double _double(String s) => double.tryParse(s.trim()) ?? 0;

int _yearOfStudy(String s) {
  final digits = int.tryParse(s.replaceAll(RegExp(r'\D'), ''));
  if (digits != null) return digits;
  return const {'freshman': 1, 'sophomore': 2, 'junior': 3, 'senior': 4}[s.trim().toLowerCase()] ?? 0;
}

/// Parses the "View Grades and Standings" XML (`<root><MAIN>... <MARK>...`).
///
/// GPA = `MAIN/COM_PYUNG`, credits earned = `MAIN/COM_CREDIT`, year of study =
/// `MAIN/GRADE` (direct children of MAIN only: each MARK has its own GRADE
/// like "Junior"). One [GradeRecord] per `MARK`, in document order, wherever
/// the MARKs sit (inside MAIN as documented, or beside it). `JUMIN` is never
/// read. Throws [ParseError] if the text is not this XML (e.g. an HTML page).
GradeReport parseGrades(String xml) {
  final doc = _readXml(xml);
  final main = doc.descendants('main').cast<_XmlElement?>().firstWhere(
        (e) => e!.child('com_pyung') != null || e.child('com_credit') != null,
        orElse: () => null,
      );
  final marks = doc.descendants('mark').toList();
  if (main == null) throw ParseError('INS grades');

  final records = <GradeRecord>[];
  for (final m in marks) {
    final code = m.field('haksu_no');
    final kname = m.field('kwamok_kname');
    final name = kname.isNotEmpty ? kname : m.field('kwamok_ename');
    if (code.isEmpty && name.isEmpty) continue;
    final yearTerm = m.field('yearterm');
    final display = m.field('display_yearterm');
    final letter = m.field('marks');
    records.add(GradeRecord(
      term: display.isNotEmpty ? display : yearTerm,
      termKey: int.tryParse(yearTerm.replaceAll(RegExp(r'\D'), '')) ?? 0,
      code: code,
      name: name,
      credits: _double(m.field('credit')),
      letter: letter.isEmpty ? '-' : letter,
      points: _double(m.field('jumsu')),
      category: m.field('jong_akname'),
    ));
  }

  return GradeReport(
    gpa: _double(main.field('com_pyung')),
    creditsEarned: _double(main.field('com_credit')),
    yearOfStudy: _yearOfStudy(main.field('grade')),
    records: records,
  );
}

/// [parseGrades] straight from response bytes, via [decodeInsBytes].
GradeReport parseGradesBytes(List<int> bytes) => parseGrades(decodeInsBytes(bytes));
