/// Pure parsing of the two public EduPage timetable replies. No I/O, so it is
/// tested against saved fixtures.
///
/// A port of `scripts/pull_timetable.py` from the study repo; keep the two in
/// step. See docs/ENDPOINTS.md for the requests.
library;

import 'dart:convert';

import '../../core/session.dart' show ParseError;
import '../../models/models.dart';

/// `r.dbiAccessorRes.tables` of a `regularttGetData` reply, as
/// table id ("cards", "lessons", ...) -> its `data_rows`.
typedef EdupageTables = Map<String, List<Map<String, dynamic>>>;

/// The class group asked for is not in this timetable (renamed, or a new year).
class UnknownClassGroup implements Exception {
  final String name;

  /// Every class group the timetable does have, sorted.
  final List<String> available;

  UnknownClassGroup(this.name, this.available);

  @override
  String toString() => 'Class group "$name" is not on the EduPage timetable';
}

/// EduPage only has names for Monday..Friday; cards flagged for a later day
/// are dropped, as in the Python script.
const _weekdays = 5;

/// Picks the `tt_num` to load from a `getTTViewerData` reply (the whole body
/// `{"r": ...}`, or just `r`).
///
/// EduPage fills in `default_num` only when the request named the right school
/// year. When it is blank or names a hidden timetable, take the newest visible
/// one: highest `year`, then highest numeric `tt_num`; the first wins a tie.
String chooseTtNum(Object? ttViewerJson) {
  const what = 'EduPage timetable list';
  final regular = _asMap(_unwrap(ttViewerJson, what)['regular']);
  if (regular == null) throw ParseError(what);

  final available = _rows(regular['timetables']).where((t) => !_truthy(t['hidden'])).toList();
  if (available.isEmpty) throw ParseError('$what (no visible timetables)');

  final num = _pyStr(regular['default_num']);
  if (available.any((t) => _str(t['tt_num']) == num)) return num;

  Map<String, dynamic>? newest;
  var best = (-1, -1);
  for (final t in available) {
    final ttNum = _str(t['tt_num']);
    final key = (_int(t['year']) ?? 0, _digits.hasMatch(ttNum) ? int.parse(ttNum) : 0);
    if (newest == null || key.$1 > best.$1 || (key.$1 == best.$1 && key.$2 > best.$2)) {
      newest = t;
      best = key;
    }
  }
  return _str(newest!['tt_num']);
}

/// The tables of a `regularttGetData` reply (the whole body, or just `r`).
EdupageTables parseTables(Object? regularttJson) {
  const what = 'EduPage timetable data';
  final res = _asMap(_unwrap(regularttJson, what)['dbiAccessorRes']);
  final tables = _rows(res?['tables']);
  if (tables.isEmpty) throw ParseError('$what (no tables)');
  return {for (final t in tables) _str(t['id']): _rows(t['data_rows'])};
}

/// Every class group name in the timetable, sorted, e.g. "AI25-1" .. "SBL(L)26-6".
List<String> classGroupsIn(EdupageTables tables) {
  final names = {
    for (final c in _table(tables, 'classes'))
      if (_str(c['name']).isNotEmpty) _str(c['name']),
  };
  return names.toList()..sort();
}

/// [parseTables] then [lessonsFor].
List<Lesson> parseLessons(
  Object? regularttJson,
  String classGroup, {
  Set<String> excludeSubjects = const {},
}) =>
    lessonsFor(parseTables(regularttJson), classGroup, excludeSubjects: excludeSubjects);

/// One [Lesson] per scheduled block of [classGroup], sorted by weekday, then
/// start (period order, which is time order).
///
/// A subject is left out when its full name contains an entry of
/// [excludeSubjects], or its short code equals one ("BDA"); both ignore case,
/// and blank entries are ignored.
///
/// Throws [UnknownClassGroup] if [classGroup] is not in the timetable.
List<Lesson> lessonsFor(
  EdupageTables tables,
  String classGroup, {
  Set<String> excludeSubjects = const {},
}) {
  final subjects = _byId(_table(tables, 'subjects'));
  final teachers = _byId(_table(tables, 'teachers'));
  final rooms = _byId(_table(tables, 'classrooms'));
  final lessons = _byId(_table(tables, 'lessons'));
  final periods = {for (final p in _table(tables, 'periods')) _str(p['period']): p};
  final classes = _table(tables, 'classes');
  final cards = _table(tables, 'cards');

  final klass = classes.where((c) => _str(c['name']) == classGroup).firstOrNull;
  if (klass == null) throw UnknownClassGroup(classGroup, classGroupsIn(tables));
  final classId = _str(klass['id']);

  final mine = {
    for (final e in lessons.entries)
      if (_list(e.value['classids']).map(_str).contains(classId)) e.key,
  };

  final exclude = [
    for (final x in excludeSubjects)
      if (x.trim().isNotEmpty) x.trim().toLowerCase(),
  ];

  final rows = <_Row>[];
  for (final card in cards) {
    final lessonId = _str(card['lessonid']);
    final lesson = lessons[lessonId];
    if (lesson == null || !mine.contains(lessonId)) continue;

    // Unplaced cards carry an empty period/days: EduPage keeps one per lesson
    // for slots the scheduler has not assigned. Skip them.
    final periodRaw = _pyStr(card['period']).trim();
    final days = _pyStr(card['days']);
    if (!_digits.hasMatch(periodRaw) || !days.contains('1')) continue;

    // A lesson spans `durationperiods` consecutive 30-minute periods.
    final startNo = int.parse(periodRaw);
    var span = _truthy(lesson['durationperiods']) ? (_int(lesson['durationperiods']) ?? 1) : 1;
    if (span < 1) span = 1;
    final endNo = startNo + span - 1;
    final start = periods['$startNo'];
    final end = periods['$endNo'];
    if (start == null || end == null) continue;

    final subject = subjects[_str(lesson['subjectid'])] ?? const <String, dynamic>{};
    if (_excluded(subject, exclude)) continue;

    Lesson on(int weekday) => Lesson(
          weekday: weekday,
          start: _hhmm(_str(start['starttime'])),
          end: _hhmm(_str(end['endtime'])),
          subject: subject.containsKey('name') ? _str(subject['name']) : '?',
          room: _list(card['classroomids']).map((r) => _short(rooms, _str(r))).join(', '),
          teacher: _list(lesson['teacherids']).map((t) => _short(teachers, _str(t))).join(', '),
        );

    // `days` is a bitmask string, one char per weekday from Monday: "00100".
    // A card flagged for several days is one block on each.
    for (var idx = 0; idx < days.length && idx < _weekdays; idx++) {
      if (days[idx] != '1') continue;
      rows.add(_Row(idx, startNo, rows.length, on(DateTime.monday + idx)));
    }
  }

  rows.sort((a, b) {
    var c = a.dayIndex.compareTo(b.dayIndex);
    if (c == 0) c = a.periodStart.compareTo(b.periodStart);
    return c != 0 ? c : a.order.compareTo(b.order); // List.sort is not stable
  });

  // Two cards that come out identical in every field (same slot, room and
  // teacher) are one block on screen.
  final seen = <String>{};
  return [
    for (final r in rows)
      if (seen.add(jsonEncode(r.lesson.toJson()))) r.lesson,
  ];
}

class _Row {
  final int dayIndex;
  final int periodStart;
  final int order;
  final Lesson lesson;
  const _Row(this.dayIndex, this.periodStart, this.order, this.lesson);
}

final _digits = RegExp(r'^\d+$');

bool _excluded(Map<String, dynamic> subject, List<String> exclude) {
  if (exclude.isEmpty) return false;
  final name = _str(subject['name']).toLowerCase();
  final short = _str(subject['short']).toLowerCase();
  return exclude.any((x) => name.contains(x) || short == x);
}

/// A room's or teacher's short name, or the raw id if the row has none.
String _short(Map<String, Map<String, dynamic>> byId, String id) {
  final row = byId[id];
  return row != null && row.containsKey('short') ? _str(row['short']) : id;
}

/// "8:00" -> "08:00"; anything that is not H:MM / HH:MM is left alone.
String _hhmm(String t) {
  final m = RegExp(r'^(\d{1,2}):(\d{2})$').firstMatch(t.trim());
  return m == null ? t : '${m.group(1)!.padLeft(2, '0')}:${m.group(2)}';
}

List<Map<String, dynamic>> _table(EdupageTables tables, String id) =>
    tables[id] ?? (throw ParseError('EduPage "$id" table'));

Map<String, Map<String, dynamic>> _byId(List<Map<String, dynamic>> rows) =>
    {for (final r in rows) _str(r['id']): r};

/// An RPC reply's `r` payload. Accepts the raw JSON text, the decoded body, or
/// the payload itself.
Map<String, dynamic> _unwrap(Object? json, String what) {
  Object? j = json;
  if (j is String) {
    try {
      j = jsonDecode(j);
    } on FormatException {
      throw ParseError(what);
    }
  }
  if (j is Map && j.containsKey('r')) j = j['r'];
  return _asMap(j) ?? (throw ParseError(what));
}

Map<String, dynamic>? _asMap(Object? v) => v is Map ? v.cast<String, dynamic>() : null;

List<Object?> _list(Object? v) => v is List ? v : const [];

List<Map<String, dynamic>> _rows(Object? v) =>
    [for (final e in _list(v)) ?_asMap(e)];

String _str(Object? v) => v == null ? '' : '$v';

/// Python truthiness, which the reference script leans on (`x or default`).
bool _truthy(Object? v) =>
    !(v == null || v == false || v == 0 || v == '' || (v is List && v.isEmpty) || (v is Map && v.isEmpty));

/// Python's `str(x or "")`.
String _pyStr(Object? v) => _truthy(v) ? '$v' : '';

int? _int(Object? v) => switch (v) {
      int() => v,
      num() when v.isFinite && v == v.roundToDouble() => v.toInt(),
      String() => int.tryParse(v.trim()),
      _ => null,
    };
