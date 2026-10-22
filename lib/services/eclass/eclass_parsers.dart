/// Pure HTML → model parsers for eClass pages. See docs/ENDPOINTS.md for
/// which page each one reads.
///
/// Every parser throws [ParseError] when the page does not look like the page
/// it expects (the site changed), and returns an empty list when the page is
/// the right one but simply has nothing in it.
library;

import 'package:html/dom.dart';
import 'package:html/parser.dart' as html_parser;

import '../../core/session.dart';
import '../../models/models.dart';

/// Courses on the dashboard (`GET /`).
List<Course> parseCourses(String html) {
  final doc = html_parser.parse(html);
  var links = doc.querySelectorAll('.course_lists a.course_link[href]');
  if (links.isEmpty) {
    // Older or different layout: any course link that carries a course title.
    links = doc
        .querySelectorAll('a[href*="/course/view.php?id="]')
        .where((a) => a.querySelector('.course-title') != null)
        .toList();
  }

  final seen = <int>{};
  final courses = <Course>[];
  for (final a in links) {
    final id = _intParam(a.attributes['href'], 'id');
    if (id == null || !seen.add(id)) continue;
    final title = _text(a.querySelector('.course-title h3') ??
        a.querySelector('.course-title') ??
        a.querySelector('h3') ??
        a);
    if (title.isEmpty) continue;
    final professor = _text(a.querySelector('.prof'));
    courses.add(Course.fromTitle(id, title, professor: professor));
  }

  if (courses.isEmpty &&
      doc.querySelector('.course_lists, .progress_courses') == null) {
    throw ParseError('eClass courses');
  }
  return courses;
}

/// Events on `GET /calendar/view.php?view=upcoming`.
///
/// Times come from the `time=<unix>` parameter of the date links, never from
/// the visible "Today"/"Tomorrow" text. One link is the due time; two are the
/// start and end of a window (VODs). Returned [DateTime]s are local time.
List<Deadline> parseUpcoming(String html) {
  final doc = html_parser.parse(html);
  var events = doc.querySelectorAll('.eventlist .event');
  if (events.isEmpty) events = doc.querySelectorAll('#region-main .event');
  if (events.isEmpty) {
    final isCalendar = doc.body?.id == 'page-calendar-view' ||
        doc.querySelector('.maincalendar') != null;
    if (isCalendar) return const [];
    throw ParseError('eClass upcoming events');
  }

  final out = <Deadline>[];
  for (final e in events) {
    final referer = e.querySelector('.referer');
    final titleEl = referer ?? e.querySelector('h3.name') ?? e.querySelector('h3');
    final title = _text(titleEl);
    if (title.isEmpty) throw ParseError('eClass upcoming event title');

    final href = referer?.querySelector('a[href]')?.attributes['href'];
    final mod = href == null ? null : _modulePattern.firstMatch(href);
    final kind = switch (mod?.group(1)) {
      'vod' => DeadlineKind.vod,
      'assign' => DeadlineKind.assignment,
      'quiz' => DeadlineKind.quiz,
      null when _classPeriodTitle.hasMatch(title) => DeadlineKind.classPeriod,
      _ => DeadlineKind.other,
    };
    final moduleId = mod == null ? null : int.tryParse(mod.group(2)!);

    final dateEl = e.querySelector('.card-header .date') ?? e.querySelector('.date');
    final times = (dateEl?.querySelectorAll('a[href]') ?? const <Element>[])
        .map((a) => _intParam(a.attributes['href'], 'time'))
        .whereType<int>()
        .map((s) => DateTime.fromMillisecondsSinceEpoch(s * 1000))
        .toList();
    if (times.isEmpty) throw ParseError('eClass upcoming event time');

    out.add(Deadline(
      title: title,
      courseName: _text(e.querySelector('.course')),
      kind: kind,
      start: times.length >= 2 ? times.first : null,
      end: times.last,
      moduleId: moduleId,
    ));
  }
  return out;
}

/// Class attendance on `GET /local/ubattendance/my_status.php?id=<course>`.
///
/// The mark is whichever column (Attendance / Absence / Late / Others) holds
/// the `○`. A page without the table (the course does not take attendance)
/// gives an empty list.
List<AttendanceEntry> parseAttendance(String html) {
  final doc = html_parser.parse(html);
  final table = doc.querySelector('table.attendance_my');
  if (table == null) {
    final isAttendancePage = doc.body?.id == 'page-local-ubattendance-my_status' ||
        doc.querySelector('.attendance_book') != null;
    if (isAttendancePage) return const [];
    throw ParseError('eClass attendance');
  }

  final headers = table.querySelectorAll('thead th').map(_text).toList();
  final markOf = _attendanceColumns(headers);

  final out = <AttendanceEntry>[];
  for (final row in _expandRows(table)) {
    if (row.isMessage) continue; // "no data" row spanning the whole table
    final cells = row.cells;
    if (cells.length < 3) throw ParseError('eClass attendance row');

    final m = RegExp(r'(\d{4})-(\d{1,2})-(\d{1,2})').firstMatch(_text(cells[0]));
    if (m == null) throw ParseError('eClass attendance date');
    final date = DateTime(int.parse(m.group(1)!), int.parse(m.group(2)!), int.parse(m.group(3)!));

    var mark = AttendanceMark.unmarked;
    for (final entry in markOf.entries) {
      if (entry.key < cells.length && _text(cells[entry.key]).contains('○')) {
        mark = entry.value;
        break;
      }
    }
    if (mark == AttendanceMark.unmarked) {
      // Some other symbol than ○ (e.g. "O" or "V"): take the first filled mark cell.
      for (final entry in markOf.entries) {
        if (entry.key < cells.length && _text(cells[entry.key]).isNotEmpty) {
          mark = entry.value;
          break;
        }
      }
    }

    out.add(AttendanceEntry(date: date, label: _text(cells[1]), mark: mark));
  }
  return out;
}

/// VOD progress on `GET /report/ubcompletion/user_progress.php?id=<course>`.
///
/// The Week cell spans all of a week's rows, so later rows have one cell
/// fewer. Weeks without VODs show an empty row and are skipped. A course
/// without progress-managed VODs has no table and gives an empty list.
List<VodProgress> parseVodProgress(String html) {
  final doc = html_parser.parse(html);
  final table = doc.querySelector('table.user_progress');
  if (table == null) {
    final isProgressPage = doc.body?.id == 'page-report-ubcompletion-user_progress' ||
        doc.querySelector('.report_ubcompletion, #ubcompletion-progress-wrapper') != null;
    if (isProgressPage) return const [];
    throw ParseError('eClass VOD progress');
  }

  final out = <VodProgress>[];
  for (final row in _expandRows(table)) {
    if (row.isMessage) continue;
    final cells = row.cells;
    // Week, Resources, Contents time, max position, Progress.
    if (cells.length < 4) throw ParseError('eClass VOD progress row');

    final title = _text(cells[1]);
    if (title.isEmpty) continue; // a week with nothing in it

    final weekCell = cells[0];
    final week = int.tryParse(_text(weekCell.querySelector('.sectiontitle'))) ??
        _firstInt(_text(weekCell)) ??
        _firstInt(weekCell.querySelector('[title]')?.attributes['title'] ?? '');
    if (week == null) throw ParseError('eClass VOD progress week');

    out.add(VodProgress(
      week: week,
      title: title,
      length: _parseClock(_text(cells[2])),
      percent: _parsePercent(_text(cells.last)),
    ));
  }
  return out;
}

/// True for eClass's login page, which is also what a logged-out request
/// for any other page ends up on.
bool isLoginPage(String html) {
  final doc = html_parser.parse(html);
  if (doc.body?.id == 'page-login-index') return true;
  return doc.querySelector('form[action*="/login/index.php"] input[name="password"]') != null;
}

/// The `sesskey` from the page's `M.cfg`, needed for AJAX calls and logout.
String? extractSesskey(String html) {
  final cfg = RegExp(r'"sesskey"\s*:\s*"([^"]+)"').firstMatch(html);
  if (cfg != null) return cfg.group(1);
  final input = html_parser.parse(html).querySelector('input[name="sesskey"]');
  final value = input?.attributes['value'];
  if (value != null && value.isNotEmpty) return value;
  return RegExp(r'[?&]sesskey=([A-Za-z0-9]+)').firstMatch(html)?.group(1);
}

// ---------------------------------------------------------------------------

/// Course-level class-period events: "Artificial Intelligence[001]-1교시".
final _classPeriodTitle = RegExp(r'\[\d+\]\s*-\s*\d+\s*교시\s*$');

final _modulePattern = RegExp(r'/mod/([a-z0-9_]+)/view\.php\?(?:[^#]*&)?id=(\d+)');

/// Element text with whitespace (including &nbsp;) collapsed.
String _text(Element? e) =>
    e == null ? '' : e.text.replaceAll(' ', ' ').replaceAll(RegExp(r'\s+'), ' ').trim();

int? _intParam(String? href, String name) {
  if (href == null) return null;
  final uri = Uri.tryParse(href.trim());
  final v = uri?.queryParameters[name];
  return v == null ? null : int.tryParse(v);
}

int? _firstInt(String s) {
  final m = RegExp(r'\d+').firstMatch(s);
  return m == null ? null : int.parse(m.group(0)!);
}

/// "18:09" (m:ss) or "01:00:34" (h:mm:ss); anything else is zero.
Duration _parseClock(String s) {
  final m = RegExp(r'^(?:(\d+):)?(\d+):(\d{2})$').firstMatch(s.trim());
  if (m == null) return Duration.zero;
  return Duration(
    hours: int.parse(m.group(1) ?? '0'),
    minutes: int.parse(m.group(2)!),
    seconds: int.parse(m.group(3)!),
  );
}

/// "98.21%" → 98.21; no number (not started, "-") → 0.
double _parsePercent(String s) {
  final m = RegExp(r'(\d+(?:\.\d+)?)\s*%').firstMatch(s) ??
      RegExp(r'^(\d+(?:\.\d+)?)$').firstMatch(s.trim());
  return m == null ? 0 : double.parse(m.group(1)!);
}

/// Column index → mark for the ubattendance table, from its header labels
/// (English or Korean), falling back to the usual positions.
Map<int, AttendanceMark> _attendanceColumns(List<String> headers) {
  final found = <int, AttendanceMark>{};
  for (var i = 0; i < headers.length; i++) {
    final h = headers[i].toLowerCase();
    final mark = h.contains('absen') || h.contains('결석')
        ? AttendanceMark.absent
        : h.contains('late') || h.contains('지각')
            ? AttendanceMark.late
            : h.contains('other') || h.contains('기타')
                ? AttendanceMark.other
                : h.contains('attend') || h.contains('출석')
                    ? AttendanceMark.present
                    : null;
    if (mark != null && i >= 2 && !found.containsValue(mark)) found[i] = mark;
  }
  if (found.length == 4) return found;
  return const {
    2: AttendanceMark.present,
    3: AttendanceMark.absent,
    4: AttendanceMark.late,
    5: AttendanceMark.other,
  };
}

class _Row {
  final List<Element> cells;

  /// A single cell spanning several columns, e.g. "No data".
  final bool isMessage;
  const _Row(this.cells, this.isMessage);
}

/// The table's body rows with `rowspan` cells copied down into the rows they
/// cover, so every row has the same columns. Header rows (all `th`) are skipped.
List<_Row> _expandRows(Element table) {
  final bodies = table.children.where((c) => c.localName == 'tbody').toList();
  final rows = <Element>[
    for (final b in bodies.isEmpty ? [table] : bodies)
      ...b.children.where((c) => c.localName == 'tr'),
  ];

  final pending = <int, ({Element cell, int left})>{};
  final out = <_Row>[];
  for (final tr in rows) {
    final physical =
        tr.children.where((c) => c.localName == 'td' || c.localName == 'th').toList();
    if (physical.isEmpty || physical.every((c) => c.localName == 'th')) continue;

    final cells = <Element>[];
    var i = 0;
    var col = 0;
    while (i < physical.length || pending.keys.any((k) => k >= col)) {
      final carried = pending[col];
      if (carried != null) {
        cells.add(carried.cell);
        if (carried.left <= 1) {
          pending.remove(col);
        } else {
          pending[col] = (cell: carried.cell, left: carried.left - 1);
        }
        col++;
        continue;
      }
      if (i >= physical.length) {
        col++;
        continue;
      }
      final cell = physical[i++];
      final span = int.tryParse(cell.attributes['colspan'] ?? '') ?? 1;
      final rowspan = int.tryParse(cell.attributes['rowspan'] ?? '') ?? 1;
      for (var s = 0; s < (span < 1 ? 1 : span); s++) {
        cells.add(cell);
        if (rowspan > 1) pending[col] = (cell: cell, left: rowspan - 1);
        col++;
      }
    }

    final colspan = int.tryParse(physical.first.attributes['colspan'] ?? '') ?? 1;
    out.add(_Row(cells, physical.length == 1 && colspan > 1));
  }
  return out;
}
