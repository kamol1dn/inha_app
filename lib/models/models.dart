/// Plain data types shared by every service and screen.
///
/// Every type round-trips through JSON so the last good fetch can be cached
/// and shown offline, except an opened [MailMessage], which is fetched each time.
library;

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
  final int? moduleId; // eClass module id, for opening it
  final String? moduleType; // "assign", "quiz", "vod", "ubboard", ...

  /// Handed in (an assignment) or attempted (a quiz), read from the item's
  /// own eClass page, and when. False when unknown.
  final bool done;
  final DateTime? doneAt;

  const Deadline({
    required this.title,
    required this.courseName,
    required this.kind,
    required this.end,
    this.start,
    this.moduleId,
    this.moduleType,
    this.done = false,
    this.doneAt,
  });

  Deadline withDone(bool done, DateTime? at) => Deadline(
      title: title,
      courseName: courseName,
      kind: kind,
      end: end,
      start: start,
      moduleId: moduleId,
      moduleType: moduleType,
      done: done,
      doneAt: done ? at : null);

  Map<String, dynamic> toJson() => {
        'title': title,
        'courseName': courseName,
        'kind': kind.name,
        'start': start?.toIso8601String(),
        'end': end.toIso8601String(),
        'moduleId': moduleId,
        'moduleType': moduleType,
        'done': done,
        'doneAt': doneAt?.toIso8601String(),
      };
  factory Deadline.fromJson(Map<String, dynamic> j) => Deadline(
        title: j['title'] as String,
        courseName: j['courseName'] as String,
        kind: DeadlineKind.values.byName(j['kind'] as String),
        start: j['start'] == null ? null : DateTime.parse(j['start'] as String),
        end: DateTime.parse(j['end'] as String),
        moduleId: j['moduleId'] as int?,
        moduleType: j['moduleType'] as String?,
        done: (j['done'] as bool?) ?? false,
        doneAt: j['doneAt'] == null ? null : DateTime.parse(j['doneAt'] as String),
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

  const VodProgress({
    required this.week,
    required this.title,
    required this.length,
    required this.percent,
  });

  bool get done => percent >= 100;

  Map<String, dynamic> toJson() =>
      {'week': week, 'title': title, 'lengthSec': length.inSeconds, 'percent': percent};
  factory VodProgress.fromJson(Map<String, dynamic> j) => VodProgress(
        week: j['week'] as int,
        title: j['title'] as String,
        length: Duration(seconds: j['lengthSec'] as int),
        percent: (j['percent'] as num).toDouble(),
      );
}

/// Everything attendance-related for one course.
class CourseAttendance {
  final Course course;
  final List<AttendanceEntry> classes; // from ubattendance; empty if the course has none
  final List<VodProgress> vods; // empty if VODs are not progress-tracked

  const CourseAttendance({required this.course, this.classes = const [], this.vods = const []});

  int count(AttendanceMark m) => classes.where((e) => e.mark == m).length;

  /// Sessions dated on or before [now]'s day. eClass lists the whole
  /// semester, the weeks still to come as unmarked rows.
  List<AttendanceEntry> held(DateTime now) {
    final end = DateTime(now.year, now.month, now.day).add(const Duration(days: 1));
    return classes.where((e) => e.date.isBefore(end)).toList();
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

/// INS "View Grades and Standings". Deliberately has no field for the
/// national ID that the source XML carries.
class GradeReport {
  final double gpa; // cumulative, 4.5 scale
  final double creditsEarned;
  final int yearOfStudy;
  final List<GradeRecord> records;

  const GradeReport({
    required this.gpa,
    required this.creditsEarned,
    required this.yearOfStudy,
    required this.records,
  });

  Map<String, dynamic> toJson() => {
        'gpa': gpa,
        'creditsEarned': creditsEarned,
        'yearOfStudy': yearOfStudy,
        'records': records.map((e) => e.toJson()).toList(),
      };
  factory GradeReport.fromJson(Map<String, dynamic> j) => GradeReport(
        gpa: (j['gpa'] as num).toDouble(),
        creditsEarned: (j['creditsEarned'] as num).toDouble(),
        yearOfStudy: j['yearOfStudy'] as int,
        records: (j['records'] as List)
            .map((e) => GradeRecord.fromJson(e as Map<String, dynamic>))
            .toList(),
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

  const MailHeader({
    required this.id,
    required this.from,
    required this.subject,
    required this.received,
    this.to = '',
    this.preview = '',
    this.unread = false,
  });

  Map<String, dynamic> toJson() => {
        'id': id,
        'from': from,
        'to': to,
        'subject': subject,
        'preview': preview,
        'received': received.toIso8601String(),
        'unread': unread,
      };
  factory MailHeader.fromJson(Map<String, dynamic> j) => MailHeader(
        id: j['id'] as String,
        from: j['from'] as String,
        to: (j['to'] as String?) ?? '',
        subject: j['subject'] as String,
        preview: (j['preview'] as String?) ?? '',
        received: DateTime.parse(j['received'] as String),
        unread: (j['unread'] as bool?) ?? false,
      );

  MailHeader withUnread(bool unread) => MailHeader(
      id: id, from: from, to: to, subject: subject, received: received, preview: preview, unread: unread);
}

/// A file attached to a message: only its name and size, not its content.
class MailAttachment {
  final String name;
  final int size; // bytes; 0 when Exchange didn't say
  const MailAttachment({required this.name, this.size = 0});
}

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

  const OutgoingMail(this.kind, {this.ref, this.to, this.cc, this.bcc, this.subject, this.body});
}
