import 'package:inha_app/core/cache.dart';
import 'package:inha_app/data/app_data.dart';
import 'package:inha_app/models/models.dart';
import 'package:inha_app/services/eclass/eclass_api.dart';
import 'package:inha_app/services/edupage/timetable_api.dart';
import 'package:inha_app/services/ins/ins_api.dart';
import 'package:inha_app/services/mail/mail_api.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Stand-ins for the services, for tests of [AppData]. Each one answers from
/// its fields and counts the calls; anything not set up throws.
class FakeEclass implements EclassApi {
  List<Course> courseList = const [];
  List<Deadline> deadlines = const [];
  Map<int, CourseAttendance> attendanceById = const {};
  Object? loginError;
  int logins = 0;

  /// Thrown by every fetch when set (a dead network, an expired login).
  Object? error;

  @override
  Future<void> ensureLoggedIn() async {
    logins++;
    if (loginError != null) throw loginError!;
  }

  @override
  Future<List<Course>> courses() async => error == null ? courseList : throw error!;
  @override
  Future<List<Deadline>> upcoming() async => error == null ? deadlines : throw error!;
  @override
  Future<CourseAttendance> attendance(Course course) async =>
      attendanceById[course.id] ?? CourseAttendance(course: course);

  /// Submission state by module id; a module listed in [failing] throws.
  Map<int, ({bool done, DateTime? at})> submissions = {};
  Set<int> failing = {};
  final submissionChecks = <int>[];

  @override
  Future<({bool done, DateTime? at})?> submission(Deadline d) async {
    final id = d.moduleId;
    if (id == null) return null;
    submissionChecks.add(id);
    if (failing.contains(id)) throw Exception('eClass did not answer');
    return submissions[id] ?? (done: false, at: null);
  }
}

class FakeTimetable implements TimetableApi {
  List<Lesson> lessonList = const [];
  Object? error;
  @override
  Future<List<Lesson>> lessons(String classGroup, {Set<String> excludeSubjects = const {}}) async =>
      error == null ? lessonList : throw error!;
  @override
  Future<List<String>> classGroups() async => const [];
}

class FakeIns implements InsApi {
  Object? loginError;
  @override
  Future<void> ensureLoggedIn() async {
    if (loginError != null) throw loginError!;
  }

  @override
  Future<GradeReport> grades() async =>
      const GradeReport(gpa: 0, creditsEarned: 0, yearOfStudy: 1, records: []);
}

class FakeMail implements MailApi {
  /// The whole inbox, newest first; pages are cut from it.
  List<MailHeader> all = const [];

  /// The other folders, whole.
  final folders = <MailFolder, List<MailHeader>>{};
  int unread = 0;
  Map<MailFolder, MailFolderCount> counts = const {};
  List<MailAddress> directory = const [];
  Object? error;
  final pages = <(int limit, int offset)>[];
  final folderPages = <MailFolder>[];
  final marked = <(String id, bool read)>[];
  final sent = <OutgoingMail>[];
  final saved = <OutgoingMail>[];
  final moves = <(String id, MailFolder to)>[];

  @override
  Future<List<MailHeader>> folder(MailFolder folder, {int limit = 30, int offset = 0}) async {
    folderPages.add(folder);
    if (folder == MailFolder.inbox) pages.add((limit, offset));
    if (error != null) throw error!;
    final list = folder == MailFolder.inbox ? all : folders[folder] ?? const [];
    return list.skip(offset).take(limit).toList();
  }

  @override
  Future<Map<MailFolder, MailFolderCount>> folderCounts() async {
    if (error != null) throw error!;
    return counts;
  }

  @override
  Future<void> send(OutgoingMail m) async {
    if (error != null) throw error!;
    sent.add(m);
  }

  @override
  Future<void> saveDraft(OutgoingMail m) async {
    if (error != null) throw error!;
    saved.add(m);
  }

  @override
  Future<String?> move(String id, MailFolder to) async {
    if (error != null) throw error!;
    moves.add((id, to));
    return 'moved-$id';
  }

  @override
  Future<List<MailAddress>> lookup(String query) async =>
      [for (final a in directory) if (a.label.toLowerCase().startsWith(query.toLowerCase())) a];

  @override
  Future<MailMessage> message(String id) async {
    final h = all.firstWhere((m) => m.id == id);
    return MailMessage(id: id, from: h.from, subject: h.subject, received: h.received, body: '', unread: h.unread);
  }

  @override
  Future<void> markRead(String id, {bool read = true}) async {
    if (error != null) throw error!;
    marked.add((id, read));
  }

  @override
  Future<int> unreadCount() async {
    if (error != null) throw error!;
    return unread;
  }
}

/// An [AppData] over fakes and empty in-memory preferences.
Future<(AppData, FakeEclass, FakeTimetable, FakeIns, FakeMail)> makeAppData(
    {Map<String, Object> prefs = const {}}) async {
  SharedPreferences.setMockInitialValues(prefs);
  final p = await SharedPreferences.getInstance();
  final eclass = FakeEclass(), timetable = FakeTimetable(), ins = FakeIns(), mail = FakeMail();
  final data = AppData(
    eclass: eclass,
    timetable: timetable,
    ins: ins,
    mail: mail,
    cache: JsonCache(p),
    prefs: Prefs(p),
  );
  return (data, eclass, timetable, ins, mail);
}

MailHeader mailHeader(int i, {bool unread = false}) => MailHeader(
      id: 'id$i',
      from: 'Academic Affairs',
      subject: 'Notice $i',
      received: DateTime(2026, 10, 22, 9).subtract(Duration(hours: i)),
      unread: unread,
    );
