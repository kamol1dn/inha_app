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
      moduleType: mod?.group(1),
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

/// Whether an assignment is handed in, from `GET /mod/assign/view.php?id=`.
///
/// Moodle puts a `submissionstatus<state>` class on the "Submission status"
/// cell once there is a submission: `submitted` (done), `draft` (not handed
/// in), `reopened`, `new`. A graded assignment (`submissiongraded`) is done
/// too. With no class there is no attempt. [at] is the "Last modified" time.
({bool done, DateTime? at}) parseAssignSubmission(String html) {
  final doc = html_parser.parse(html);
  final table = doc.querySelector('.submissionstatustable table') ??
      (doc.body?.id == 'page-mod-assign-view' ? doc.querySelector('#region-main table.generaltable') : null);
  if (table == null) {
    if (doc.body?.id == 'page-mod-assign-view') return (done: false, at: null);
    throw ParseError('eClass assignment');
  }
  String? state;
  for (final cell in table.querySelectorAll('td')) {
    for (final c in cell.classes) {
      if (c.startsWith('submissionstatus') && c.length > 'submissionstatus'.length) {
        state ??= c.substring('submissionstatus'.length);
      }
    }
  }
  final graded = table.querySelector('td.submissiongraded') != null;
  final done = state == 'submitted' || state == 'marked' || graded;
  DateTime? at;
  for (final row in table.querySelectorAll('tr')) {
    final cells = row.querySelectorAll('td, th');
    if (cells.length < 2) continue;
    final label = _text(cells.first).toLowerCase();
    if (label.contains('last modified') || label.contains('최종 수정')) at = _parseDateTime(_text(cells[1]));
  }
  return (done: done, at: done ? at : null);
}

/// Whether a quiz is done, from `GET /mod/quiz/view.php?id=`: any attempt
/// in `table.quizattemptsummary` whose state is "Finished" (종료됨). [at] is
/// the newest "Submitted ..." time in the state details.
({bool done, DateTime? at}) parseQuizSubmission(String html) {
  final doc = html_parser.parse(html);
  if (doc.body?.id != 'page-mod-quiz-view' && doc.querySelector('.quizinfo') == null) {
    throw ParseError('eClass quiz');
  }
  var done = false;
  DateTime? at;
  for (final row in doc.querySelectorAll('table.quizattemptsummary tbody tr')) {
    final cell = row.querySelector('td');
    if (cell == null) continue;
    final text = _text(cell);
    if (!RegExp(r'^(Finished|종료)', caseSensitive: false).hasMatch(text)) continue;
    done = true;
    final when = _parseDateTime(text);
    if (when != null && (at == null || when.isAfter(at))) at = when;
  }
  return (done: done, at: at);
}

/// A course's grades page, `GET /grade/report/user/index.php?id=<course>`, or
/// null when the page has no table.
///
/// The column classes hold whatever language the page is in. A row is a
/// category heading, an item (`th.item`) or a category's total (`th.baggt`),
/// which comes after the category's items and is the row carrying its weight;
/// the course's own total is that row at level 1. Nested categories multiply.
CourseGrades? parseGradeBook(String html, Course course) {
  final doc = html_parser.parse(html);
  final table = doc.querySelector('table.user-grade');
  if (table == null) {
    if (doc.body?.id == 'page-grade-report-user-index') return null;
    throw ParseError('eClass grades');
  }

  final open = <int, _GradeCategoryRows>{}; // the category being read at each level
  final rows = <(Element, _GradeCategoryRows?)>[];
  final categories = <_GradeCategoryRows>[];
  double? total;
  double? gradeTotal;
  double? gradeTotalMax;
  for (final tr in table.querySelectorAll('tbody tr')) {
    final th = tr.querySelector('th.column-itemname');
    if (th == null) continue;
    final level = int.tryParse(RegExp(r'\blevel(\d+)\b').firstMatch(th.className)?.group(1) ?? '');
    if (level == null) throw ParseError('eClass grades row');

    if (th.classes.contains('item')) {
      rows.add((tr, open[level - 1]));
    } else if (th.classes.contains('baggt') || th.classes.contains('baggb')) {
      if (level == 1) {
        total = _gradeNumber(_gradeCell(tr, 'contributiontocoursetotal'));
        gradeTotal = _gradeNumber(_gradeCell(tr, 'grade'));
        gradeTotalMax = _rangeMax(_gradeCell(tr, 'range'));
      } else {
        open[level]?.weight = _gradeNumber(_gradeCell(tr, 'weight'));
      }
    } else {
      final c = _GradeCategoryRows(_text(th), open[level - 1]);
      open[level] = c;
      if (level > 1) categories.add(c);
    }
  }

  return CourseGrades(
    course: course,
    source: GradeSource.gradebook,
    total: total,
    gradeTotal: gradeTotal,
    gradeTotalMax: gradeTotalMax,
    categories: [for (final c in categories) GradeCategory(c.name, c.courseWeight)],
    items: [
      for (final (tr, category) in rows) _gradeItem(tr, category),
    ],
  );
}

GradeItem _gradeItem(Element tr, _GradeCategoryRows? category) {
  final th = tr.querySelector('th.column-itemname')!;
  final id = RegExp(r'^row_(\d+)').firstMatch(th.id)?.group(1);
  final link = th.querySelector('a.gradeitemheader[href]')?.attributes['href'];
  final mod = link == null ? null : _modulePattern.firstMatch(link);
  final moduleId = mod == null ? null : int.tryParse(mod.group(2)!);
  if (id == null && moduleId == null) throw ParseError('eClass grades item');
  final mark = _gradeCell(tr, 'grade');
  return GradeItem(
    key: moduleId != null ? 'm$moduleId' : 'g$id',
    name: _text(th.querySelector('.gradeitemheader') ?? th),
    category: category == null || category.parent == null ? '' : category.name,
    mark: mark,
    grade: _gradeNumber(mark),
    max: _rangeMax(_gradeCell(tr, 'range')),
    weight: _gradeNumber(_gradeCell(tr, 'weight')),
    categoryWeight: category?.parent == null ? 100 : category!.courseWeight,
    contribution: _gradeNumber(_gradeCell(tr, 'contributiontocoursetotal')),
    moduleId: moduleId,
    moduleType: mod?.group(1),
  );
}

/// "0–100" → 100; a scale has no number.
double? _rangeMax(String s) {
  final m = RegExp(r'[–-]\s*(\d+(?:\.\d+)?)\s*$').firstMatch(s);
  return m == null ? null : double.parse(m.group(1)!);
}

String _gradeCell(Element tr, String column) => _text(tr.querySelector('td.column-$column'));

/// "100.00 %" → 100, "8.50" → 8.5; "-", a letter or a word → null.
double? _gradeNumber(String s) {
  final m = RegExp(r'^(-?\d+(?:\.\d+)?)\s*%?$').firstMatch(s.trim());
  return m == null ? null : double.parse(m.group(1)!);
}

/// A category while its rows are read. The course itself is the root, with no
/// parent. Its weight comes from its total row, after its items.
class _GradeCategoryRows {
  final String name;
  final _GradeCategoryRows? parent;
  double? weight;
  _GradeCategoryRows(this.name, this.parent);

  /// % of the course total; null when eClass shows "-" here or above.
  double? get courseWeight {
    final up = parent;
    if (up == null) return 100;
    final w = weight, above = up.courseWeight;
    return w == null || above == null ? null : w * above / 100;
  }
}

/// A course's assignment or quiz list, `GET /mod/<type>/index.php?id=<course>`,
/// the marks of a course with its grades page closed. Quizzes read
/// `37.00/100.00`; assignments give the mark alone, or `-`. A course with none
/// has no table. [type] is `assign` or `quiz`.
List<GradeItem> parseActivityGrades(String html, String type) {
  final doc = html_parser.parse(html);
  final table = doc.querySelector('#region-main table.generaltable');
  if (table == null) {
    if (doc.body?.id == 'page-mod-$type-index') return const [];
    throw ParseError('eClass $type list');
  }
  final headers = table.querySelectorAll('thead th').map(_text).toList();
  final found = headers.indexWhere((h) => h == 'Grade' || h == '성적');
  final gradeColumn = found >= 0 ? found : headers.length - 1;

  final out = <GradeItem>[];
  for (final tr in table.querySelectorAll('tbody tr')) {
    final cells = tr.querySelectorAll('td');
    final link = tr.querySelector('a[href*="view.php"]');
    if (link == null || gradeColumn < 0 || cells.length <= gradeColumn) continue; // the spacer between weeks
    final id = _intParam(link.attributes['href'], 'id');
    if (id == null) throw ParseError('eClass $type list row');
    final text = _text(cells[gradeColumn]);
    final outOf = RegExp(r'^(\d+(?:\.\d+)?)\s*/\s*(\d+(?:\.\d+)?)$').firstMatch(text);
    out.add(GradeItem(
      key: 'm$id',
      name: _text(link),
      category: type == 'assign' ? 'Assignments' : 'Quizzes',
      mark: text,
      grade: outOf != null ? double.parse(outOf.group(1)!) : _gradeNumber(text),
      max: outOf == null ? null : double.parse(outOf.group(2)!),
      moduleId: id,
      moduleType: type,
    ));
  }
  return out;
}

/// The maximum in the Feedback box of `GET /mod/assign/view.php?id=`, whose
/// Grade row reads `85.00 / 100.00`. Null before there is a mark, or on a
/// grading scale.
double? parseAssignMax(String html) {
  final doc = html_parser.parse(html);
  if (doc.body?.id != 'page-mod-assign-view') throw ParseError('eClass assignment');
  for (final row in doc.querySelectorAll('.feedback tr')) {
    final cells = row.querySelectorAll('td, th');
    if (cells.length < 2 || !RegExp(r'^(Grade|성적)$').hasMatch(_text(cells.first))) continue;
    final m = RegExp(r'/\s*(\d+(?:\.\d+)?)\s*$').firstMatch(_text(cells[1]));
    return m == null ? null : double.parse(m.group(1)!);
  }
  return null;
}

/// The first "2026-10-21 21:14" in [s], in device time (eClass shows times in
/// the zone of the student's profile, the same as the device).
DateTime? _parseDateTime(String s) {
  final m = RegExp(r'(\d{4})-(\d{2})-(\d{2})\s+(\d{1,2}):(\d{2})').firstMatch(s);
  if (m == null) return null;
  return DateTime(int.parse(m[1]!), int.parse(m[2]!), int.parse(m[3]!), int.parse(m[4]!), int.parse(m[5]!));
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
