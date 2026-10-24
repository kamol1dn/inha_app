// Every user-visible time and date string comes from here (DESIGN.md section 9).
library;

const _wd = ['Mon', 'Tue', 'Wed', 'Thu', 'Fri', 'Sat', 'Sun'];
const _mon = ['Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun', 'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec'];

String _pad(int n) => n.toString().padLeft(2, '0');

/// 09:00
String clock(DateTime t) => '${_pad(t.hour)}:${_pad(t.minute)}';

/// Thu 23 Oct (year only when it isn't this year)
String dayDate(DateTime t, {DateTime? now}) {
  final n = now ?? DateTime.now();
  final y = t.year == n.year ? '' : ' ${t.year}';
  return '${_wd[t.weekday - 1]} ${t.day} ${_mon[t.month - 1]}$y';
}

String weekdayShort(int weekday) => _wd[weekday - 1];

DateTime _midnight(DateTime t) => DateTime(t.year, t.month, t.day);

/// Today / Tomorrow / Sat 25 Oct, for day group headers.
String dayHeader(DateTime t, {DateTime? now}) {
  final n = now ?? DateTime.now();
  final days = _midnight(t).difference(_midnight(n)).inDays;
  if (days == 0) return 'Today';
  if (days == 1) return 'Tomorrow';
  return dayDate(t, now: n);
}

/// 1 h 10 min / 40 min
String duration(Duration d) {
  final h = d.inHours, m = d.inMinutes % 60;
  if (h == 0) return '$m min';
  if (m == 0) return '$h h';
  return '$h h $m min';
}

/// now / in 25 min / in 2 h 15 min / in 6 h / Sat 23:59 / 3 Nov 23:59 / Overdue 2 h
String relative(DateTime t, {DateTime? now}) {
  final n = now ?? DateTime.now();
  final d = t.difference(n);
  if (d.isNegative) {
    final p = n.difference(t);
    if (p.inHours < 24) return p.inMinutes < 60 ? 'Overdue ${p.inMinutes} min' : 'Overdue ${p.inHours} h';
    return 'Overdue ${p.inDays} d';
  }
  if (d.inMinutes < 1) return 'now';
  if (d.inMinutes < 60) return 'in ${d.inMinutes} min';
  if (d.inHours < 3) return 'in ${duration(d)}';
  if (d.inHours < 24) return 'in ${d.inHours} h';
  if (d.inDays < 7) return '${_wd[t.weekday - 1]} ${clock(t)}';
  return '${t.day} ${_mon[t.month - 1]} ${clock(t)}';
}

/// For lists of past items (mail): 14:07 today, Wed 14:07 within the week,
/// otherwise 17 Oct (with the year if it isn't this one).
String pastWhen(DateTime t, {DateTime? now}) {
  final n = now ?? DateTime.now();
  final days = _midnight(n).difference(_midnight(t)).inDays;
  if (days <= 0) return clock(t);
  if (days < 7) return '${_wd[t.weekday - 1]} ${clock(t)}';
  return '${t.day} ${_mon[t.month - 1]}${t.year == n.year ? '' : ' ${t.year}'}';
}

/// Thu 23 Oct 14:07 (year only when it isn't this year)
String dayDateTime(DateTime t, {DateTime? now}) => '${dayDate(t, now: now)} ${clock(t)}';

final _kindTag = RegExp(r'^\[([A-Za-z]{2,12})\]\s*');
final _eventSuffix =
    RegExp(r'\s*(\((\w+\s+)?(opens|closes|is due|due|starts|ends)\)|\s+is due)\s*$', caseSensitive: false);

/// An eClass item's title as a row shows it (DESIGN.md 7): Moodle's event
/// suffix ("(Quiz closes)", "is due") is dropped, and so is a leading kind
/// tag, except that before a number it becomes a word, so
/// "[QUIZ] 2 Week 6 - 2% (Quiz closes)" reads "Quiz 2 Week 6 - 2%". The
/// detail sheet keeps eClass's own title.
String rowTitle(String title) {
  var t = title.trim().replaceFirst(_eventSuffix, '');
  final tag = _kindTag.firstMatch(t);
  if (tag != null) {
    final rest = t.substring(tag.end);
    final word = tag[1]!;
    t = RegExp(r'^\d').hasMatch(rest) ? '${word[0].toUpperCase()}${word.substring(1).toLowerCase()} $rest' : rest;
  }
  t = t.replaceAll(RegExp(r'\s+'), ' ').trim();
  return t.isEmpty ? title.trim() : t;
}

/// Mon 26 – Fri 30 Oct / Mon 30 Nov – Fri 4 Dec: a run of days.
String dayRange(DateTime a, DateTime b, {DateTime? now}) {
  if (a.year == b.year && a.month == b.month) {
    return '${_wd[a.weekday - 1]} ${a.day} – ${dayDate(b, now: now)}';
  }
  return '${dayDate(a, now: now)} – ${dayDate(b, now: now)}';
}

final _section = RegExp(r'^(.+)\(([A-Z])\)$');

/// "B209", "B209 or B210", "B304(A–C), B305 or B201": the rooms an exam
/// uses, a hall's sections run together when three or more follow in order.
String roomChoice(List<String> rooms) {
  final parts = <String>[];
  for (var i = 0; i < rooms.length;) {
    final m = _section.firstMatch(rooms[i]);
    var j = i + 1;
    if (m == null) {
      parts.add(rooms[i]);
    } else {
      final letters = [m[2]!];
      for (; j < rooms.length; j++) {
        final n = _section.firstMatch(rooms[j]);
        if (n == null || n[1] != m[1]) break;
        letters.add(n[2]!);
      }
      final run = letters.length >= 3 &&
          [for (var k = 1; k < letters.length; k++) letters[k].codeUnitAt(0) - letters[k - 1].codeUnitAt(0)]
              .every((d) => d == 1);
      parts.addAll(run ? ['${m[1]}(${letters.first}–${letters.last})'] : [for (final l in letters) '${m[1]}($l)']);
    }
    i = j;
  }
  if (parts.length < 2) return parts.join();
  return '${parts.sublist(0, parts.length - 1).join(', ')} or ${parts.last}';
}

/// 812 B / 14 KB / 2.3 MB / 18 MB
String fileSize(int bytes) {
  if (bytes < 1024) return '$bytes B';
  final kb = bytes / 1024;
  if (kb < 1024) return '${kb.round()} KB';
  final mb = kb / 1024;
  return mb < 10 ? '${mb.toStringAsFixed(1)} MB' : '${mb.round()} MB';
}

/// Updated 08:41 (today) / Updated Tue 18:04
String updatedAt(DateTime t, {DateTime? now}) {
  final n = now ?? DateTime.now();
  final sameDay = _midnight(t) == _midnight(n);
  return sameDay ? clock(t) : '${_wd[t.weekday - 1]} ${clock(t)}';
}
