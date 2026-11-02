/// Plain data types shared by every service and screen.
///
/// Every type round-trips through JSON so the last good fetch can be cached
/// and shown offline, except an opened [MailMessage], which is fetched each time.
library;

/// An instant for the cache: UTC, so it means the same moment after a time
/// zone change. Read back with [_readInstant].
String _writeInstant(DateTime t) => t.toUtc().toIso8601String();

/// Device time. A value cached before instants carried a zone reads as local.
DateTime _readInstant(String s) => DateTime.parse(s).toLocal();

enum Service { eclass, edupage, ins, mail }

extension ServiceLabel on Service {
  String get label => switch (this) {
        Service.eclass => 'eClass',
        Service.edupage => 'Timetable',
        Service.ins => 'INS',
        Service.mail => 'Mail',
      };

  /// Services that need a username and password in Settings.
  bool get needsLogin => this != Service.edupage;
}

/// An eClass course, e.g. "Multimedia Computing[202602-SOC4020-001]".
class Course {
  final int id;
  final String name; // "Multimedia Computing"
  final String code; // "SOC4020"
  final String professor;

  const Course({
    required this.id,
    required this.name,
    required this.code,
    this.professor = '',
  });

  /// Splits eClass's "Name[202602-SOC4020-001]" title. Anything after the
  /// bracket is dropped too: the dashboard appends a "NEW" badge to some.
  factory Course.fromTitle(int id, String title, {String professor = ''}) {
    final m = RegExp(r'^(.*?)\s*\[\d+-([A-Z]+\d+)-\d+\][\s\S]*$').firstMatch(title.trim());
    return Course(
      id: id,
      name: (m?.group(1) ?? title).trim(),
      code: m?.group(2) ?? '',
      professor: professor,
    );
  }

  Map<String, dynamic> toJson() =>
      {'id': id, 'name': name, 'code': code, 'professor': professor};
  factory Course.fromJson(Map<String, dynamic> j) => Course(
        id: j['id'] as int,
        name: j['name'] as String,
        code: j['code'] as String,
        professor: (j['professor'] as String?) ?? '',
      );
}

/// One timetable slot from EduPage.
class Lesson {
  final int weekday; // DateTime.monday .. DateTime.friday
  final String start; // "09:00"
  final String end; // "10:30"
  final String subject; // full subject name
  final String room;
  final String teacher;
  final String kind; // "Lecture", "Lab", ... or ''

  const Lesson({
    required this.weekday,
    required this.start,
    required this.end,
    required this.subject,
    this.room = '',
    this.teacher = '',
    this.kind = '',
  });

  Map<String, dynamic> toJson() => {
        'weekday': weekday,
        'start': start,
        'end': end,
        'subject': subject,
        'room': room,
        'teacher': teacher,
        'kind': kind,
      };
  factory Lesson.fromJson(Map<String, dynamic> j) => Lesson(
        weekday: j['weekday'] as int,
        start: j['start'] as String,
        end: j['end'] as String,
        subject: j['subject'] as String,
        room: (j['room'] as String?) ?? '',
        teacher: (j['teacher'] as String?) ?? '',
        kind: (j['kind'] as String?) ?? '',
      );
}

/// [classPeriod] is eClass's course-level "Course[001]-3교시" event: a scheduled
/// class period (교시), not something due. It is kept so it can be shown on
/// request, but never counts as a deadline or triggers a reminder.
enum DeadlineKind { assignment, quiz, vod, other, classPeriod }

/// An item from eClass's upcoming-events calendar. A VOD event is a watch
/// window (start..end); everything else usually has only [end].
class Deadline {
  final String title;
  final String courseName;
  final DeadlineKind kind;
  final DateTime? start;
  final DateTime end;
  final int? courseId; // the eClass course the event links to; null in an old cache
  final int? moduleId; // eClass module id, for opening it
  final String? moduleType; // "assign", "quiz", "vod", "ubboard", ...

  /// Handed in (an assignment) or attempted (a quiz), read from the item's
  /// own eClass page, and when. False when unknown.
  final bool done;
  final DateTime? doneAt;

  /// The student marked it done here: eClass can't track it (handed in on
  /// paper, a plain calendar event). Kept apart from [done], eClass's own word.
  final bool dismissed;

  const Deadline({
    required this.title,
    required this.courseName,
    required this.kind,
    required this.end,
    this.start,
    this.courseId,
    this.moduleId,
    this.moduleType,
    this.done = false,
    this.doneAt,
    this.dismissed = false,
  });

  Deadline withDone(bool done, DateTime? at) => Deadline(
      title: title,
      courseName: courseName,
      kind: kind,
      end: end,
      start: start,
      courseId: courseId,
      moduleId: moduleId,
      moduleType: moduleType,
      done: done,
      doneAt: done ? at : null,
      dismissed: dismissed);

  Deadline withDismissed(bool dismissed) => Deadline(
      title: title,
      courseName: courseName,
      kind: kind,
      end: end,
      start: start,
      courseId: courseId,
      moduleId: moduleId,
      moduleType: moduleType,
      done: done,
      doneAt: doneAt,
      dismissed: dismissed);

  Map<String, dynamic> toJson() => {
        'title': title,
        'courseName': courseName,
        'kind': kind.name,
        'start': start == null ? null : _writeInstant(start!),
        'end': _writeInstant(end),
        'courseId': courseId,
        'moduleId': moduleId,
        'moduleType': moduleType,
        'done': done,
        'doneAt': doneAt == null ? null : _writeInstant(doneAt!),
        'dismissed': dismissed,
      };
  factory Deadline.fromJson(Map<String, dynamic> j) => Deadline(
        title: j['title'] as String,
        courseName: j['courseName'] as String,
        kind: DeadlineKind.values.byName(j['kind'] as String),
        start: j['start'] == null ? null : _readInstant(j['start'] as String),
        end: _readInstant(j['end'] as String),
        courseId: j['courseId'] as int?,
        moduleId: j['moduleId'] as int?,
        moduleType: j['moduleType'] as String?,
        done: (j['done'] as bool?) ?? false,
        doneAt: j['doneAt'] == null ? null : _readInstant(j['doneAt'] as String),
        dismissed: (j['dismissed'] as bool?) ?? false,
      );
}

enum AttendanceMark { present, absent, late, other, unmarked }

class AttendanceEntry {
  final DateTime date;
  final String label; // "3Class"
  final AttendanceMark mark;

  const AttendanceEntry({required this.date, required this.label, required this.mark});

  Map<String, dynamic> toJson() =>
      {'date': date.toIso8601String(), 'label': label, 'mark': mark.name};
  factory AttendanceEntry.fromJson(Map<String, dynamic> j) => AttendanceEntry(
        date: DateTime.parse(j['date'] as String),
        label: j['label'] as String,
        mark: AttendanceMark.values.byName(j['mark'] as String),
      );
}

/// One watchable VOD and how much of it has been watched.
class VodProgress {
  final int week;
  final String title;
  final Duration length;
  final double percent; // 0..100

  /// The course module, for `/mod/vod/view.php?id=<this>`. Null when the course's
  /// VOD list didn't name it, and in an old cache.
  final int? moduleId;

  /// The watch window. Null when the page gives none, and in an old cache.
  final DateTime? opens;
  final DateTime? closes;

  const VodProgress({
    required this.week,
    required this.title,
    required this.length,
    required this.percent,
    this.moduleId,
    this.opens,
    this.closes,
  });

  bool get done => percent >= 100;

  /// The watch window has ended. Unknown counts as still open.
  bool closedAt(DateTime now) => closes != null && now.isAfter(closes!);

  VodProgress withModuleId(int? id) => VodProgress(
      week: week, title: title, length: length, percent: percent, moduleId: id, opens: opens, closes: closes);

  Map<String, dynamic> toJson() => {
        'week': week,
        'title': title,
        'lengthSec': length.inSeconds,
        'percent': percent,
        'moduleId': moduleId,
        'opens': opens == null ? null : _writeInstant(opens!),
        'closes': closes == null ? null : _writeInstant(closes!),
      };
  factory VodProgress.fromJson(Map<String, dynamic> j) => VodProgress(
        week: j['week'] as int,
        title: j['title'] as String,
        length: Duration(seconds: j['lengthSec'] as int),
        percent: (j['percent'] as num).toDouble(),
        moduleId: j['moduleId'] as int?,
        opens: j['opens'] == null ? null : _readInstant(j['opens'] as String),
        closes: j['closes'] == null ? null : _readInstant(j['closes'] as String),
      );
}

/// One item of eClass's bell menu: an announcement, feedback, a graded item.
class EclassNotification {
  final int id;
  final String subject;
  final String text; // the short message, plain text
  final String? url; // what it is about, when Moodle gives a link
  final DateTime time;
  final bool read;

  const EclassNotification({
    required this.id,
    required this.subject,
    required this.text,
    required this.time,
    this.url,
    this.read = false,
  });

  Map<String, dynamic> toJson() =>
      {'id': id, 'subject': subject, 'text': text, 'url': url, 'time': _writeInstant(time), 'read': read};
  factory EclassNotification.fromJson(Map<String, dynamic> j) => EclassNotification(
        id: j['id'] as int,
        subject: j['subject'] as String,
        text: j['text'] as String,
        url: j['url'] as String?,
        time: _readInstant(j['time'] as String),
        read: (j['read'] as bool?) ?? false,
      );
}

/// Everything attendance-related for one course.
class CourseAttendance {
  final Course course;
  final List<AttendanceEntry> classes; // from ubattendance; empty if the course has none
  final List<VodProgress> vods; // empty if VODs are not progress-tracked

  const CourseAttendance({required this.course, this.classes = const [], this.vods = const []});

  int count(AttendanceMark m) => classes.where((e) => e.mark == m).length;

  /// Sessions held so far: those before [now]'s day, and today's once marked.
  /// eClass lists the whole semester, the weeks still to come as unmarked rows,
  /// and an unmarked class today may not have happened yet.
  List<AttendanceEntry> held(DateTime now) {
    final today = DateTime(now.year, now.month, now.day);
    return classes
        .where((e) => e.date.isBefore(today) || (!e.date.isAfter(today) && e.mark != AttendanceMark.unmarked))
        .toList();
  }

  Map<String, dynamic> toJson() => {
        'course': course.toJson(),
        'classes': classes.map((e) => e.toJson()).toList(),
        'vods': vods.map((e) => e.toJson()).toList(),
      };
  factory CourseAttendance.fromJson(Map<String, dynamic> j) => CourseAttendance(
        course: Course.fromJson(j['course'] as Map<String, dynamic>),
        classes: (j['classes'] as List)
            .map((e) => AttendanceEntry.fromJson(e as Map<String, dynamic>))
            .toList(),
        vods: (j['vods'] as List)
            .map((e) => VodProgress.fromJson(e as Map<String, dynamic>))
            .toList(),
      );
}

/// One course result from INS. [letter] is '-' while a course is not graded.
class GradeRecord {
  final String term; // "2023 Fall Semester"
  final int termKey; // 20231, sortable
  final String code; // "SOC4020"
  final String name;
  final double credits;
  final String letter; // "A+", "B0", "-"
  final double points; // 4.5 scale
  final String category; // "MR-M"

  const GradeRecord({
    required this.term,
    required this.termKey,
    required this.code,
    required this.name,
    required this.credits,
    required this.letter,
    required this.points,
    this.category = '',
  });

  bool get graded => letter.isNotEmpty && letter != '-';

  Map<String, dynamic> toJson() => {
        'term': term,
        'termKey': termKey,
        'code': code,
        'name': name,
        'credits': credits,
        'letter': letter,
        'points': points,
        'category': category,
      };
  factory GradeRecord.fromJson(Map<String, dynamic> j) => GradeRecord(
        term: j['term'] as String,
        termKey: j['termKey'] as int,
        code: j['code'] as String,
        name: j['name'] as String,
        credits: (j['credits'] as num).toDouble(),
        letter: j['letter'] as String,
        points: (j['points'] as num).toDouble(),
        category: (j['category'] as String?) ?? '',
      );
}

/// Letters that count toward a GPA. Pass marks and withdrawals don't.
const _gpaLetters = {'A+', 'A0', 'A-', 'B+', 'B0', 'B-', 'C+', 'C0', 'C-', 'D+', 'D0', 'D-', 'F'};

/// Letters that earn no credit.
const _noCreditLetters = {'F', 'NP', 'U', 'W', 'I'};

/// The credits-weighted GPA of [records], one term's: "3.81". Null when none has
/// a letter that counts, or when a points figure isn't on the 4.5 scale (a passing
/// letter with 0 points, say), since then no figure here could be trusted.
double? termGpa(Iterable<GradeRecord> records) {
  var credits = 0.0, points = 0.0;
  for (final r in records) {
    if (!_gpaLetters.contains(r.letter) || r.credits <= 0) continue;
    if (r.points > 4.5 || (r.points <= 0 && r.letter != 'F')) return null;
    credits += r.credits;
    points += r.credits * r.points;
  }
  return credits == 0 ? null : points / credits;
}

/// Credits earned per INS category ("MR-M"), most first. A course taken more
/// than once counts by its latest result, in a term with a result.
Map<String, double> creditsByCategory(Iterable<GradeRecord> records) {
  final latest = <String, GradeRecord>{};
  for (final r in records.where((r) => r.graded)) {
    final key = r.code.isEmpty ? r.name : r.code;
    final seen = latest[key];
    if (seen == null || r.termKey >= seen.termKey) latest[key] = r;
  }
  final totals = <String, double>{};
  for (final r in latest.values) {
    if (_noCreditLetters.contains(r.letter)) continue;
    totals.update(r.category.isEmpty ? 'Other' : r.category, (v) => v + r.credits, ifAbsent: () => r.credits);
  }
  final order = totals.keys.toList()
    ..sort((a, b) {
      final byCredits = totals[b]!.compareTo(totals[a]!);
      return byCredits != 0 ? byCredits : a.compareTo(b);
    });
  return {for (final k in order) k: totals[k]!};
}

/// INS "View Grades and Standings". Deliberately has no field for the
/// national ID that the source XML carries.
class GradeReport {
  final double gpa; // cumulative, 4.5 scale
  final double creditsEarned;
  final int yearOfStudy;
  final List<GradeRecord> records;

  /// INS's own totals of major-required and general-required credits (JUNPIL and
  /// KYOPIL). Null when it gives none, and in an old cache.
  final double? majorRequired;
  final double? generalRequired;

  const GradeReport({
    required this.gpa,
    required this.creditsEarned,
    required this.yearOfStudy,
    required this.records,
    this.majorRequired,
    this.generalRequired,
  });

  Map<String, dynamic> toJson() => {
        'gpa': gpa,
        'creditsEarned': creditsEarned,
        'yearOfStudy': yearOfStudy,
        'majorRequired': majorRequired,
        'generalRequired': generalRequired,
        'records': records.map((e) => e.toJson()).toList(),
      };
  factory GradeReport.fromJson(Map<String, dynamic> j) => GradeReport(
        gpa: (j['gpa'] as num).toDouble(),
        creditsEarned: (j['creditsEarned'] as num).toDouble(),
        yearOfStudy: j['yearOfStudy'] as int,
        records: (j['records'] as List)
            .map((e) => GradeRecord.fromJson(e as Map<String, dynamic>))
            .toList(),
        majorRequired: (j['majorRequired'] as num?)?.toDouble(),
        generalRequired: (j['generalRequired'] as num?)?.toDouble(),
      );
}

/// A number the way a mark reads best: 37, 0.37, 6.25, never 37.00.
String plainNumber(double v) => v.toStringAsFixed(2).replaceFirst(RegExp(r'\.?0+$'), '');

/// One marked thing in an eClass course: a row of the course's grades page, or
/// of its assignment and quiz lists where that page is closed.
class GradeItem {
  final String key; // the same on every refresh: "m<module id>" or "g<grade item id>"
  final String name;
  final String category; // '' when it sits directly under the course
  final String mark; // as eClass shows it: "8.50", "A"; '-' or '' while unmarked
  final double? grade; // the mark as a number, when it is one
  final double? max;
  final double? weight; // % of its category ("Calculated weight"); null where eClass shows "-"
  final double? categoryWeight; // the category's % of the course total; 100 directly under the course
  final double? contribution; // points in the course total, eClass's "백분 환산 점수"
  final int? moduleId; // for opening it, when it is an activity
  final String? moduleType; // "assign", "quiz", ...

  const GradeItem({
    required this.key,
    required this.name,
    this.category = '',
    this.mark = '',
    this.grade,
    this.max,
    this.weight,
    this.categoryWeight,
    this.contribution,
    this.moduleId,
    this.moduleType,
  });

  bool get marked => mark.isNotEmpty && mark != '-';

  /// "8.5 / 10", or the mark alone when it isn't a number or has no maximum.
  String get score => switch ((grade, max)) {
        (final g?, final m?) => '${plainNumber(g)} / ${plainNumber(m)}',
        (final g?, null) => plainNumber(g),
        _ => mark,
      };

  GradeItem withMax(double max) => GradeItem(
      key: key,
      name: name,
      category: category,
      mark: mark,
      grade: grade,
      max: max,
      weight: weight,
      categoryWeight: categoryWeight,
      contribution: contribution,
      moduleId: moduleId,
      moduleType: moduleType);

  Map<String, dynamic> toJson() => {
        'key': key,
        'name': name,
        'category': category,
        'mark': mark,
        'grade': grade,
        'max': max,
        'weight': weight,
        'categoryWeight': categoryWeight,
        'contribution': contribution,
        'moduleId': moduleId,
        'moduleType': moduleType,
      };
  factory GradeItem.fromJson(Map<String, dynamic> j) => GradeItem(
        key: j['key'] as String,
        name: j['name'] as String,
        category: (j['category'] as String?) ?? '',
        mark: (j['mark'] as String?) ?? '',
        grade: (j['grade'] as num?)?.toDouble(),
        max: (j['max'] as num?)?.toDouble(),
        weight: (j['weight'] as num?)?.toDouble(),
        categoryWeight: (j['categoryWeight'] as num?)?.toDouble(),
        contribution: (j['contribution'] as num?)?.toDouble(),
        moduleId: j['moduleId'] as int?,
        moduleType: j['moduleType'] as String?,
      );
}

/// A category of the grades page and its % of the course total. Listed even
/// with nothing in it yet: a Final exam worth 25% before the final exists.
class GradeCategory {
  final String name;
  final double? weight;
  const GradeCategory(this.name, this.weight);

  Map<String, dynamic> toJson() => {'name': name, 'weight': weight};
  factory GradeCategory.fromJson(Map<String, dynamic> j) =>
      GradeCategory(j['name'] as String, (j['weight'] as num?)?.toDouble());
}

/// Where a course's marks came from. Professors can close the grades page
/// ("Can not view grades"), which leaves the assignment and quiz lists; those
/// have marks but no weights. [none]: neither has anything.
enum GradeSource { gradebook, activities, none }

/// One course's marks in eClass.
class CourseGrades {
  final Course course;
  final GradeSource source;
  final List<GradeItem> items;
  final List<GradeCategory> categories;
  final double? percent; // the course total, %, as eClass works it out

  const CourseGrades({
    required this.course,
    required this.source,
    this.items = const [],
    this.categories = const [],
    this.percent,
  });

  Map<String, dynamic> toJson() => {
        'course': course.toJson(),
        'source': source.name,
        'items': items.map((e) => e.toJson()).toList(),
        'categories': categories.map((e) => e.toJson()).toList(),
        'percent': percent,
      };
  factory CourseGrades.fromJson(Map<String, dynamic> j) => CourseGrades(
        course: Course.fromJson(j['course'] as Map<String, dynamic>),
        source: GradeSource.values.byName(j['source'] as String),
        items: (j['items'] as List).map((e) => GradeItem.fromJson(e as Map<String, dynamic>)).toList(),
        categories: (j['categories'] as List).map((e) => GradeCategory.fromJson(e as Map<String, dynamic>)).toList(),
        percent: (j['percent'] as num?)?.toDouble(),
      );
}

/// The mail folders the app shows, in the drawer's order, with their EWS
/// distinguished folder ids.
enum MailFolder {
  inbox('inbox', 'Inbox'),
  drafts('drafts', 'Drafts'),
  sent('sentitems', 'Sent'),
  deleted('deleteditems', 'Deleted'),
  junk('junkemail', 'Junk'),
  notes('notes', 'Notes');

  const MailFolder(this.ewsId, this.label);
  final String ewsId;
  final String label;

  /// Folders whose rows name who the mail went to rather than who sent it.
  bool get outgoing => this == drafts || this == sent;
}

/// Unread and total items in a folder, from Exchange.
class MailFolderCount {
  final int unread;
  final int total;
  const MailFolderCount(this.unread, this.total);
}

/// A person or list on a message: the display name and the SMTP address.
class MailAddress {
  final String name;
  final String address;
  const MailAddress(this.name, this.address);

  /// The name, or the address when there is none.
  String get label => name.isEmpty ? address : name;
}

/// A mail message header (no body) for a folder list.
class MailHeader {
  final String id;
  final String from;
  final String to; // Exchange's display line of the To recipients
  final String subject;
  final String preview;
  final DateTime received;
  final bool unread;
  final bool hasAttachments;

  const MailHeader({
    required this.id,
    required this.from,
    required this.subject,
    required this.received,
    this.to = '',
    this.preview = '',
    this.unread = false,
    this.hasAttachments = false,
  });

  Map<String, dynamic> toJson() => {
        'id': id,
        'from': from,
        'to': to,
        'subject': subject,
        'preview': preview,
        'received': _writeInstant(received),
        'unread': unread,
        'hasAttachments': hasAttachments,
      };
  factory MailHeader.fromJson(Map<String, dynamic> j) => MailHeader(
        id: j['id'] as String,
        from: j['from'] as String,
        to: (j['to'] as String?) ?? '',
        subject: j['subject'] as String,
        preview: (j['preview'] as String?) ?? '',
        received: _readInstant(j['received'] as String),
        unread: (j['unread'] as bool?) ?? false,
        hasAttachments: (j['hasAttachments'] as bool?) ?? false,
      );

  MailHeader withUnread(bool unread) => MailHeader(
      id: id,
      from: from,
      to: to,
      subject: subject,
      received: received,
      preview: preview,
      unread: unread,
      hasAttachments: hasAttachments);

  /// The same message under the id it has in another folder.
  MailHeader withId(String id) => MailHeader(
      id: id,
      from: from,
      to: to,
      subject: subject,
      received: received,
      preview: preview,
      unread: unread,
      hasAttachments: hasAttachments);
}

/// A file attached to a message: its name and size, not its content.
/// [id] is what `MailApi.attachment` fetches the file with.
class MailAttachment {
  final String id; // '' when Exchange gave none
  final String name;
  final int size; // bytes; 0 when Exchange didn't say
  final String contentType; // '' when Exchange didn't say
  const MailAttachment({required this.name, this.id = '', this.size = 0, this.contentType = ''});
}

/// A whole file: one fetched from a message, or one to attach to a new one.
class MailFile {
  final String name;
  final String contentType;
  final List<int> bytes;
  const MailFile({required this.name, required this.bytes, this.contentType = 'application/octet-stream'});
}

/// The most a message's new attachments may add up to. Exchange's default limit
/// for a message is 35 MB, and base64 makes a file a third larger on the way.
const maxMailAttachmentBytes = 25 * 1024 * 1024;

/// One opened message. Fetched when it is opened and not cached.
class MailMessage {
  final String id;
  final String changeKey; // the version Exchange wants for replies and for sending a draft
  final String from; // display name, or the address when there is none
  final String fromAddress;
  final String subject;
  final DateTime received;
  final bool unread;
  final String body; // plain text, \n line breaks
  final List<MailAttachment> attachments;
  final List<MailAddress> to;
  final List<MailAddress> cc;
  final List<MailAddress> bcc;
  final String receivedBy; // the student's own address, on mail they received
  final bool isDraft;

  const MailMessage({
    required this.id,
    required this.from,
    required this.subject,
    required this.received,
    required this.body,
    this.changeKey = '',
    this.fromAddress = '',
    this.unread = false,
    this.attachments = const [],
    this.to = const [],
    this.cc = const [],
    this.bcc = const [],
    this.receivedBy = '',
    this.isDraft = false,
  });
}

enum ComposeKind { fresh, reply, replyAll, forward, draft }

/// A message to send or to save as a draft.
///
/// For a reply or forward, [ref] is the original: Exchange adds the "RE:" or
/// "FW:" subject, works out a reply's recipients and quotes the original
/// below [body]. For [ComposeKind.draft], [ref] is the saved draft and a null
/// field stays as saved.
class OutgoingMail {
  final ComposeKind kind;
  final MailMessage? ref;
  final List<String>? to;
  final List<String>? cc;
  final List<String>? bcc;
  final String? subject;
  final String? body;

  /// New files to attach. A saved draft keeps the ones it already has.
  final List<MailFile> attachments;

  const OutgoingMail(this.kind,
      {this.ref, this.to, this.cc, this.bcc, this.subject, this.body, this.attachments = const []});
}
