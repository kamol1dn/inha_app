import 'dart:async';
import 'dart:convert';

import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart' show ThemeMode;
import 'package:flutter/services.dart' show AssetBundle;
import 'package:shared_preferences/shared_preferences.dart';

import '../core/cache.dart';
import '../core/session.dart';
import '../models/models.dart';
import '../notifications/notifier.dart';
import '../notifications/rules.dart' show reminderStem;
import '../services/eclass/eclass_api.dart';
import '../services/edupage/timetable_api.dart';
import '../services/edupage/timetable_parser.dart' show UnknownClassGroup;
import '../services/ins/ins_api.dart';
import '../services/mail/mail_api.dart';
import '../ui/format/format.dart';
import 'exams.dart';
import 'sync_progress.dart';

/// The last time a service answered with the saved login: [ok] when it let
/// the app in, false when it rejected the username or password.
class AccountCheck {
  final bool ok;
  final DateTime at;
  const AccountCheck(this.ok, this.at);

  Map<String, dynamic> toJson() => {'ok': ok, 'at': at.toUtc().toIso8601String()};
  static AccountCheck? fromJson(Object? j) {
    if (j is! Map<String, dynamic>) return null;
    final at = DateTime.tryParse(j['at'] as String? ?? '');
    return at == null ? null : AccountCheck(j['ok'] == true, at.toLocal());
  }
}

/// User choices that aren't secrets.
class Prefs {
  final SharedPreferences _p;
  Prefs(this._p) {
    _keepOldDefaults();
  }

  /// Once, for an install from when the class group and the hidden subjects had
  /// defaults instead of being the student's choice: what it has been running
  /// on becomes its saved choice. A missing pref alone can't tell such an
  /// install from a fresh one, so anything else it left behind is the sign.
  void _keepOldDefaults() {
    const done = 'prefs.defaultsSettled';
    if (_p.getBool(done) ?? false) return;
    const signs = ['classGroup', 'excludedSubjects', 'notify.asked', 'cache.lessons', 'cache.deadlines', Notifier.prefsKey];
    if (signs.any(_p.containsKey)) {
      if (!_p.containsKey('classGroup')) _p.setString('classGroup', 'ICE23-1');
      if (!_p.containsKey('excludedSubjects')) _p.setStringList('excludedSubjects', const ['Big Data']);
    }
    _p.setBool(done, true);
  }

  /// The student's class group, as EduPage names it; '' until they choose one.
  String get classGroup => _p.getString('classGroup') ?? '';
  set classGroup(String v) => _p.setString('classGroup', v);

  /// Subjects the student dropped but EduPage still lists for the group.
  Set<String> get excludedSubjects => (_p.getStringList('excludedSubjects') ?? const <String>[]).toSet();
  set excludedSubjects(Set<String> v) => _p.setStringList('excludedSubjects', v.toList());

  /// The deadlines the student marked done, by [reminderStem]: what eClass can't
  /// track, such as work handed in on paper.
  Set<String> get dismissedDeadlines => (_p.getStringList('deadlines.dismissed') ?? const <String>[]).toSet();
  set dismissedDeadlines(Set<String> v) => _p.setStringList('deadlines.dismissed', v.toList());

  // Deadlines-tab filters. A per-device convenience, so plain prefs.
  static const defaultDeadlineKinds = {
    DeadlineKind.assignment,
    DeadlineKind.quiz,
    DeadlineKind.vod,
    DeadlineKind.other,
  };

  Set<DeadlineKind> get deadlineKinds {
    final saved = _p.getStringList('deadlines.kinds');
    if (saved == null) return defaultDeadlineKinds;
    return {
      for (final n in saved)
        if (DeadlineKind.values.any((k) => k.name == n)) DeadlineKind.values.byName(n),
    };
  }

  set deadlineKinds(Set<DeadlineKind> v) =>
      _p.setStringList('deadlines.kinds', [for (final k in v) k.name]);

  /// Course name to show only, or null for all courses.
  String? get deadlineCourse => _p.getString('deadlines.course');
  set deadlineCourse(String? v) =>
      v == null ? _p.remove('deadlines.course') : _p.setString('deadlines.course', v);

  /// Light, dark, or following the system (the default).
  ThemeMode get themeMode =>
      ThemeMode.values.where((m) => m.name == _p.getString('theme')).firstOrNull ?? ThemeMode.system;
  set themeMode(ThemeMode v) => _p.setString('theme', v.name);

  /// Whether the Android notification permission prompt was shown once.
  bool get notificationsAsked => _p.getBool('notify.asked') ?? false;
  set notificationsAsked(bool v) => _p.setBool('notify.asked', v);

  /// Show submitted assignments, attempted quizzes and watched VODs too.
  /// On unless the student turned it off.
  bool get showDone => _p.getBool('deadlines.showDone') ?? true;
  set showDone(bool v) => _p.setBool('deadlines.showDone', v);

  /// Allowed absences per eClass course id, as the student set them.
  Map<int, int> get absenceLimits => Notifier.readAbsenceLimits(_p);

  void setAbsenceLimit(int courseId, int? limit) {
    final all = absenceLimits;
    limit == null ? all.remove(courseId) : all[courseId] = limit;
    _p.setString(Notifier.absenceLimitsKey, jsonEncode({for (final e in all.entries) '${e.key}': e.value}));
  }

  /// Forgets what the notifier and the student recorded about the eClass
  /// account, along with it: another account starts from its own baseline.
  void clearEclassMemory() {
    _p.remove(Notifier.seenGradesKey);
    _p.remove(Notifier.seenGradeSourcesKey);
    _p.remove(Notifier.seenCoursesKey);
    _p.remove(Notifier.noticesSeenKey);
    _p.remove('deadlines.dismissed');
  }

  /// The exam rooms the student set once they knew them, by [Exam.keyIn].
  Map<String, String> get examRooms {
    try {
      return {
        for (final e in (jsonDecode(_p.getString('exams.rooms.v1') ?? '{}') as Map<String, dynamic>).entries)
          e.key: e.value as String,
      };
    } catch (_) {
      return {};
    }
  }

  void setExamRoom(String key, String? room) {
    final all = examRooms;
    room == null ? all.remove(key) : all[key] = room;
    _p.setString('exams.rooms.v1', jsonEncode(all));
  }

  /// The exam weeks' days as last written by [AppData.loadExams].
  Set<DateTime> get classFreeDays => decodeDays(_p.getString(classFreeDaysKey));
  Future<void> setClassFreeDays(Set<DateTime> days) => _p.setString(classFreeDaysKey, encodeDays(days));

  AccountCheck? accountCheck(Service s) {
    final raw = _p.getString('account.${s.name}');
    if (raw == null) return null;
    try {
      return AccountCheck.fromJson(jsonDecode(raw));
    } catch (_) {
      return null;
    }
  }

  void setAccountCheck(Service s, AccountCheck? c) => c == null
      ? _p.remove('account.${s.name}')
      : _p.setString('account.${s.name}', jsonEncode(c.toJson()));

  void resetDeadlineFilters() {
    _p.remove('deadlines.kinds');
    _p.remove('deadlines.course');
    _p.remove('deadlines.showDone');
  }
}

/// The single source of truth the screens listen to. Each data source has
/// its own [Snapshot]: the newest cached value plus the last refresh error, so
/// one service being down never blanks the others.
class AppData extends ChangeNotifier {
  final EclassApi eclass;
  final TimetableApi timetable;
  final InsApi ins;
  final MailApi mail;
  final JsonCache cache;
  final Prefs prefs;

  /// What the refreshes are doing right now (the strip under the app bar).
  final sync = SyncProgress();

  AppData({
    required this.eclass,
    required this.timetable,
    required this.ins,
    required this.mail,
    required this.cache,
    required this.prefs,
  }) {
    _timetableGroup = prefs.classGroup;
    _timetableAsked = _timetableQuestion();
    _readCache();
  }

  /// Called after the timetable or eClass data changes, which is what
  /// reminders are planned from. The app hooks the notifier in here.
  Future<void> Function()? onReminderDataChanged;

  /// Called after a cache write the home-screen widgets read, a sign-out that
  /// clears one, or a change to the absence limits. The app hooks the widget
  /// update in here (docs/WIDGETS.md).
  Future<void> Function()? onWidgetDataChanged;

  /// Called from [forget], to take the account's notifications away too.
  Future<void> Function(Service)? onSignedOut;

  /// Whether a login is saved for the service. Hooked up to the credential
  /// store: a sign-out in the other isolate can't reach this one's refreshes,
  /// so they look before writing, and a resume looks at what was written.
  Future<bool> Function(Service)? hasLogin;

  Future<bool> _signedIn(Service s) async {
    if (!s.needsLogin || hasLogin == null) return true;
    try {
      return await hasLogin!(s);
    } catch (_) {
      return true; // the store can't say: nothing suggests a sign-out
    }
  }

  static const _widgetCacheKeys = {'lessons', 'deadlines', 'attendance', 'grades'};

  /// Reads every source from the cache. On a [reload] a
  /// source keeps its last error unless the cache holds something newer than
  /// it did; otherwise a signed-out source with nothing cached would go back
  /// to its loading skeleton and stay there.
  void _readCache({bool reload = false}) {
    Snapshot<T> read<T>(Snapshot<T> Function() before, Cached<T>? cached) {
      final old = reload ? before() : null;
      return Snapshot(data: cached, error: cached?.fetchedAt == old?.data?.fetchedAt ? old?.error : null);
    }

    lessons = read(() => lessons, cache.read('lessons', _decodeList(Lesson.fromJson)));
    if (lessons.data == null && prefs.classGroup.isEmpty) lessons = Snapshot(error: _noClassGroup);
    deadlines = read(() => deadlines, cache.read('deadlines', _decodeList(Deadline.fromJson)));
    attendance =
        read(() => attendance, cache.read('attendance', _decodeList(CourseAttendance.fromJson)));
    courseGrades = read(() => courseGrades, cache.read('courseGrades', _decodeList(CourseGrades.fromJson)));
    grades = read(
        () => grades, cache.read('grades', (j) => GradeReport.fromJson(j as Map<String, dynamic>)));
    eclassNotifications = read(
        () => eclassNotifications, cache.read('notifications', _decodeList(EclassNotification.fromJson)));
    for (final (f, box) in [for (final f in MailFolder.values) (f, _mailbox[f]!)]) {
      final cached = cache.read(_mailKey(f), _decodeList(MailHeader.fromJson));
      // Nothing but a refresh writes a folder, so the same fetch time means this
      // is the list on screen, and it may have older pages loaded since.
      if (reload && cached != null && cached.fetchedAt == box.list.data?.fetchedAt) continue;
      box.list = read(() => box.list, cached);
      if (reload) {
        box.hasMore = true;
        box.moreError = null;
      }
    }
    mailUnread = read(() => mailUnread, cache.read('mailUnread', (j) => j as int));
  }

  static final _noClassGroup = SetupNeeded('Choose your class group in Settings.');

  /// Picks up what the background refresh wrote while the app was away.
  Future<void> reloadFromCache() async {
    if ([lessons, deadlines, attendance, courseGrades, grades, eclassNotifications, mailUnread, for (final f in _mailbox.values) f.list]
        .any((s) => s.loading)) {
      return;
    }
    await cache.reload();
    // A refresh in the other isolate may have finished after a sign-out here.
    for (final s in Service.values) {
      if (await _signedIn(s)) continue;
      for (final key in _cacheKeys[s]!) {
        await cache.remove(key);
      }
    }
    _readCache(reload: true);
    notifyListeners();
  }

  late Snapshot<List<Lesson>> lessons;
  late Snapshot<List<Deadline>> deadlines;
  late Snapshot<List<CourseAttendance>> attendance;
  late Snapshot<List<CourseGrades>> courseGrades;
  late Snapshot<GradeReport> grades;

  /// The newest items of eClass's bell menu.
  late Snapshot<List<EclassNotification>> eclassNotifications;

  /// The course's marks in eClass, or null before they have loaded.
  CourseGrades? gradesOf(int courseId) =>
      courseGrades.data?.value.where((g) => g.course.id == courseId).firstOrNull;

  final _mailbox = {for (final f in MailFolder.values) f: MailboxFolder()};

  /// A mail folder as loaded so far.
  MailboxFolder mailbox(MailFolder f) => _mailbox[f]!;

  Snapshot<List<MailHeader>> get inbox => _mailbox[MailFolder.inbox]!.list;

  /// The inbox's unread count from Exchange, which also counts messages
  /// beyond the pages loaded into [inbox].
  late Snapshot<int> mailUnread;

  /// Every folder's unread and total count, for the drawer. In memory only.
  Map<MailFolder, MailFolderCount> mailCounts = const {};

  /// Messages per folder page.
  static const mailPageSize = 30;

  /// The inbox keeps the cache key it had before there were folders.
  static String _mailKey(MailFolder f) => f == MailFolder.inbox ? 'inbox' : 'mail.${f.name}';

  static List<T> Function(Object?) _decodeList<T>(T Function(Map<String, dynamic>) f) =>
      (j) => (j as List).map((e) => f(e as Map<String, dynamic>)).toList();
  static Object? _encodeList<T>(List<T> v) => v.map((e) => (e as dynamic).toJson()).toList();

  /// Refreshes everything in parallel. Each source fails independently.
  Future<void> refreshAll() => Future.wait([
        refreshTimetable(),
        refreshEclass(),
        refreshGrades(),
        refreshMail(),
      ]);

  late String _timetableGroup;
  late String _timetableAsked;

  String _timetableQuestion() =>
      '${prefs.classGroup}|${(prefs.excludedSubjects.toList()..sort()).join(',')}';

  /// Loads the saved class group's lessons. A fetch already running for another
  /// group or other hidden subjects answers the old question: it is dropped and
  /// this one runs instead. Lessons of another group never stay on screen as
  /// the student's own, and with no group chosen nothing is fetched at all.
  Future<void> refreshTimetable() async {
    final asked = _timetableQuestion();
    if (asked != _timetableAsked) {
      _timetableAsked = asked;
      _invalidate(Service.edupage);
      if (prefs.classGroup != _timetableGroup) {
        _timetableGroup = prefs.classGroup;
        await cache.remove('lessons');
        lessons = const Snapshot();
        unawaited(onWidgetDataChanged?.call());
      }
    }
    if (prefs.classGroup.isEmpty) {
      lessons = Snapshot(data: lessons.data, error: _noClassGroup);
      notifyListeners();
      return;
    }
    await _run<List<Lesson>>(
      get: () => lessons,
      set: (s) => lessons = s,
      fetch: () => sync.step('Timetable', prefs.classGroup,
          () => timetable.lessons(prefs.classGroup, excludeSubjects: prefs.excludedSubjects)),
      key: 'lessons',
      encode: _encodeList,
      service: Service.edupage,
    );
    // Not a group this timetable has: what's cached can't be the student's.
    if (lessons.error is UnknownClassGroup && lessons.data != null) {
      await cache.remove('lessons');
      lessons = Snapshot(error: lessons.error);
      notifyListeners();
    }
    await onReminderDataChanged?.call();
  }

  /// The class groups EduPage knows, for a picker.
  Future<List<String>> classGroups() => sync.step('Timetable', 'class groups', timetable.classGroups);

  /// Deadlines, attendance and marks share one eClass login, so they refresh together.
  Future<void> refreshEclass() async {
    await _refreshEclassData();
    await onReminderDataChanged?.call();
  }

  Future<void> _refreshEclassData() => sync.span(() async {
    // Asked for once, and only by a source that isn't already refreshing.
    Future<List<Course>>? asked;
    Future<List<Course>> courses() => asked ??= sync.step('eClass', 'course list', eclass.courses);
    PartialRefresh? attendanceGaps, marksGaps;
    await Future.wait([
      _run<List<Deadline>>(
        get: () => deadlines,
        set: (s) => deadlines = s,
        fetch: () async => _withDismissals(await _withSubmissions(await _upcoming(courses))),
        key: 'deadlines',
        encode: _encodeList,
        service: Service.eclass,
      ),
      _run<List<CourseAttendance>>(
        get: () => attendance,
        set: (s) => attendance = s,
        fetch: () async => _eachCourse(
          await courses(),
          (c) => sync.step('eClass', 'attendance for ${c.name}', () => eclass.attendance(c)),
          (c) =>
              attendance.data?.value.where((a) => a.course.id == c.id).firstOrNull ?? CourseAttendance(course: c),
          (gaps) => attendanceGaps = gaps,
        ),
        warning: () => attendanceGaps,
        key: 'attendance',
        encode: _encodeList,
        service: Service.eclass,
      ),
      _run<List<CourseGrades>>(
        get: () => courseGrades,
        set: (s) => courseGrades = s,
        fetch: () async => _eachCourse(
          await courses(),
          (c) => sync.step('eClass', 'marks for ${c.name}', () => eclass.courseGrades(c)),
          (c) => gradesOf(c.id) ?? CourseGrades(course: c, source: GradeSource.none),
          (gaps) => marksGaps = gaps,
        ),
        warning: () => marksGaps,
        key: 'courseGrades',
        encode: _encodeList,
        service: Service.eclass,
      ),
      _run<List<EclassNotification>>(
        get: () => eclassNotifications,
        set: (s) => eclassNotifications = s,
        fetch: () => sync.step('eClass', 'notifications', eclass.notifications),
        key: 'notifications',
        encode: _encodeList,
        service: Service.eclass,
      ),
    ]);
  });

  /// One fetch per course, all at once. A course that fails keeps [fallback],
  /// and [gaps] hears which did; one bad page doesn't hold back the others. Only
  /// a refused login, or every course failing, fails the whole list.
  Future<List<T>> _eachCourse<T>(
    List<Course> courses,
    Future<T> Function(Course) fetch,
    T Function(Course) fallback,
    void Function(PartialRefresh) gaps,
  ) async {
    final failed = <String>[];
    Object? first;
    final out = await Future.wait(courses.map((c) async {
      try {
        return await fetch(c);
      } on LoginRequired {
        rethrow;
      } catch (e) {
        if (kDebugMode) debugPrint('course ${c.id} failed: ${_debugDescribe(e)}');
        first ??= e;
        failed.add(c.name);
        return fallback(c);
      }
    }));
    final cause = first;
    if (cause != null) {
      if (failed.length == courses.length) throw cause;
      gaps(PartialRefresh(failed, cause));
    }
    return out;
  }

  /// Every upcoming event: the all-courses page, which stops after a fixed
  /// number of events, merged with each course's own page. Each page is
  /// optional: where one fails, the cache's events still to come stand in for
  /// it, so a deadline past the cut isn't lost to a bad page. Only a refused
  /// login, or nothing answering at all, fails the list.
  Future<List<Deadline>> _upcoming(Future<List<Course>> Function() courses) async {
    Object? firstError;
    var answered = false;
    var allPageFailed = false;
    final failedCourses = <Course>{};
    Future<List<Deadline>> page(String what, Future<List<Deadline>> Function() get, void Function() onFail) async {
      try {
        final events = await sync.step('eClass', what, get);
        answered = true;
        return events;
      } on LoginRequired {
        rethrow;
      } catch (e) {
        if (kDebugMode) debugPrint('$what failed: ${_debugDescribe(e)}');
        firstError ??= e;
        onFail();
        return const [];
      }
    }

    Future<List<List<Deadline>>> perCourse() async {
      final List<Course> list;
      try {
        list = await courses();
      } on LoginRequired {
        rethrow;
      } catch (e) {
        firstError ??= e;
        allPageFailed = true; // no way to tell which courses are covered
        return const [];
      }
      return Future.wait([
        for (final c in list)
          page('deadlines for ${c.name}', () => eclass.upcomingIn(c), () => failedCourses.add(c)),
      ]);
    }

    final allPage = page('upcoming deadlines', eclass.upcoming, () => allPageFailed = true);
    final coursePages = perCourse();
    await Future.wait<Object?>([allPage, coursePages]); // together, so neither failure goes unhandled
    final (all, each) = (await allPage, await coursePages);
    if (!answered) throw firstError ?? ParseError('eClass upcoming events');

    final now = DateTime.now();
    final kept = [
      for (final d in deadlines.data?.value ?? const <Deadline>[])
        if (d.end.isAfter(now) &&
            (allPageFailed || failedCourses.any((c) => d.courseId == c.id || d.courseName == c.name)))
          d,
    ];
    return _mergeEvents([all, ...each, kept]);
  }

  /// [pages] as one list without repeats, by start time. The first page to have
  /// an event wins, so put the freshest first.
  static List<Deadline> _mergeEvents(List<List<Deadline>> pages) {
    final byEvent = <String, Deadline>{};
    for (final page in pages) {
      for (final d in page) {
        byEvent.putIfAbsent('${d.moduleId}|${d.courseName}|${d.title}|${d.end.millisecondsSinceEpoch}', () => d);
      }
    }
    final order = [...byEvent.values.indexed]..sort((a, b) {
        final byTime = (a.$2.start ?? a.$2.end).compareTo(b.$2.start ?? b.$2.end);
        return byTime != 0 ? byTime : a.$1.compareTo(b.$1);
      });
    return [for (final (_, d) in order) d];
  }

  List<Deadline> _withDismissals(List<Deadline> list) {
    final marked = prefs.dismissedDeadlines;
    return [for (final d in list) d.withDismissed(marked.contains(reminderStem(d)))];
  }

  /// Marks [d] done here, or takes that back. Its reminders follow, and it reads
  /// as done everywhere, as [Deadline.dismissed].
  Future<void> markDeadlineDone(Deadline d, {bool done = true}) async {
    final stem = reminderStem(d);
    final marked = prefs.dismissedDeadlines;
    prefs.dismissedDeadlines = done ? {...marked, stem} : ({...marked}..remove(stem));
    final list = deadlines.data;
    if (list != null) {
      deadlines = Snapshot(
          data: await cache.write('deadlines', _withDismissals(list.value), _encodeList, at: list.fetchedAt),
          error: deadlines.error,
          loading: deadlines.loading);
    }
    notifyListeners();
    unawaited(onWidgetDataChanged?.call());
    await onReminderDataChanged?.call();
  }

  /// Marks each assignment and quiz handed in or not, from its own page.
  /// A page that fails keeps what the cache knew about that item, so a
  /// network blip never brings back reminders for submitted work.
  Future<List<Deadline>> _withSubmissions(List<Deadline> fresh) {
    final known = {
      for (final d in deadlines.data?.value ?? const <Deadline>[])
        if (d.moduleId != null) d.moduleId!: d,
    };
    return Future.wait(fresh.map((d) async {
      if (d.kind != DeadlineKind.assignment && d.kind != DeadlineKind.quiz) return d;
      try {
        final s = await sync.step('eClass', 'checking ${rowTitle(d.title)}', () => eclass.submission(d));
        return s == null ? d : d.withDone(s.done, s.at);
      } catch (e) {
        if (kDebugMode) debugPrint('submission ${d.moduleId} failed: ${_debugDescribe(e)}');
        final before = known[d.moduleId];
        return before == null ? d : d.withDone(before.done, before.doneAt);
      }
    }));
  }

  Future<void> refreshGrades() => _run<GradeReport>(
        get: () => grades,
        set: (s) => grades = s,
        fetch: () => sync.step('INS', 'grades', ins.grades),
        key: 'grades',
        encode: (v) => v.toJson(),
        service: Service.ins,
      );

  /// Refreshes [folder] (the inbox unless said), the unread count and the
  /// drawer's counts.
  Future<void> refreshMail({MailFolder folder = MailFolder.inbox}) => Future.wait([
        refreshMailFolder(folder),
        refreshMailCounts(),
        _run<int>(
          get: () => mailUnread,
          set: (s) => mailUnread = s,
          fetch: () => sync.step('Mail', 'unread count', mail.unreadCount),
          key: 'mailUnread',
          encode: (v) => v,
          service: Service.mail,
        ),
      ]);

  /// Reloads the first page of [f].
  Future<void> refreshMailFolder(MailFolder f) {
    final box = _mailbox[f]!;
    return _run<List<MailHeader>>(
      get: () => box.list,
      set: (s) => box.list = s,
      fetch: () async {
        final page = await sync.step('Mail', f.label, () => mail.folder(f, limit: mailPageSize));
        box.hasMore = page.length >= mailPageSize;
        box.moreError = null;
        return page;
      },
      key: _mailKey(f),
      encode: _encodeList,
      service: Service.mail,
    );
  }

  /// The drawer's counts. A failure keeps the last ones: the folder lists
  /// already show what went wrong.
  Future<void> refreshMailCounts() async {
    final generation = _generation[Service.mail];
    try {
      final counts = await sync.step('Mail', 'folder counts', mail.folderCounts);
      if (generation != _generation[Service.mail]) return;
      mailCounts = counts;
      notifyListeners();
    } catch (e) {
      if (kDebugMode) debugPrint('mail counts failed: ${_debugDescribe(e)}');
    }
  }

  /// Logs in to [s] with the saved login right away (the caller resets its
  /// cookies first, so the login really runs) and records the result. On
  /// success the service's data is refreshed. Returns the error, or null.
  Future<Object?> testLogin(Service s) async {
    // What is running now was asked with the login before this one.
    _invalidate(s);
    final generation = _generation[s];
    try {
      switch (s) {
        case Service.eclass:
          await eclass.ensureLoggedIn();
        case Service.ins:
          await ins.ensureLoggedIn();
        case Service.mail:
          await mail.unreadCount();
        case Service.edupage:
          return null;
      }
    } catch (e) {
      if (generation != _generation[s]) return e;
      if (e is LoginRequired) _check(s, ok: false);
      notifyListeners();
      return e;
    }
    if (generation != _generation[s]) return null;
    _check(s, ok: true);
    notifyListeners();
    unawaited(switch (s) {
      Service.eclass => refreshEclass(),
      Service.ins => refreshGrades(),
      Service.mail => refreshMail(),
      Service.edupage => Future.value(),
    });
    return null;
  }

  /// Which of a service's fetches still count: a fetch that started under an
  /// older number drops its result. See [_invalidate].
  final _generation = {for (final s in Service.values) s: 0};

  /// Whatever [s] is fetching now no longer counts, and it stops showing as
  /// loading, so a new refresh can start.
  void _invalidate(Service s) {
    _generation[s] = _generation[s]! + 1;
    Snapshot<T> settled<T>(Snapshot<T> x) => x.loading ? Snapshot(data: x.data, error: x.error) : x;
    switch (s) {
      case Service.eclass:
        deadlines = settled(deadlines);
        attendance = settled(attendance);
        courseGrades = settled(courseGrades);
        eclassNotifications = settled(eclassNotifications);
      case Service.ins:
        grades = settled(grades);
      case Service.mail:
        for (final box in _mailbox.values) {
          box.list = settled(box.list);
        }
        mailUnread = settled(mailUnread);
      case Service.edupage:
        lessons = settled(lessons);
    }
  }

  /// After signing out of [s]: drops its cached data and its account check,
  /// so nothing from that account stays on the phone, and a refresh still
  /// running can't bring it back.
  Future<void> forget(Service s) async {
    _invalidate(s);
    for (final key in _cacheKeys[s]!) {
      await cache.remove(key);
    }
    prefs.setAccountCheck(s, null);
    unawaited(onWidgetDataChanged?.call());
    switch (s) {
      case Service.eclass:
        deadlines = const Snapshot();
        attendance = const Snapshot();
        courseGrades = const Snapshot();
        eclassNotifications = const Snapshot();
        prefs.clearEclassMemory();
      case Service.ins:
        grades = const Snapshot();
      case Service.mail:
        _mailbox.updateAll((_, _) => MailboxFolder());
        mailUnread = const Snapshot();
        mailCounts = const {};
      case Service.edupage:
        lessons = const Snapshot();
    }
    notifyListeners();
    await onSignedOut?.call(s);
  }

  static final _cacheKeys = {
    Service.eclass: ['deadlines', 'attendance', 'courseGrades', 'notifications'],
    Service.ins: ['grades'],
    Service.mail: ['mailUnread', for (final f in MailFolder.values) _mailKey(f)],
    Service.edupage: ['lessons'],
  };

  void setAbsenceLimit(int courseId, int? limit) {
    prefs.setAbsenceLimit(courseId, limit);
    unawaited(onWidgetDataChanged?.call());
    notifyListeners();
  }

  /// The bundled exam timetables (lib/data/exams.dart), read once at start.
  List<ExamPeriod> examPeriods = const [];

  /// Reads [examSheets]. A sheet that doesn't parse is left out; the tests
  /// read every bundled sheet, so one never ships broken.
  Future<void> loadExams(AssetBundle bundle) async {
    final read = <ExamPeriod>[];
    for (final path in examSheets) {
      try {
        read.add(ExamPeriod.fromJson(jsonDecode(await bundle.loadString(path)) as Map<String, dynamic>));
      } catch (e) {
        if (kDebugMode) debugPrint('exam sheet $path: $e');
      }
    }
    examPeriods = read;
    // For the background refresh and the widgets, which don't read the sheets.
    await prefs.setClassFreeDays(classFreeDays(read));
    notifyListeners();
  }

  /// Days with no classes, whatever the timetable says: the exam weeks.
  Set<DateTime> get classFree => examPeriods.isEmpty ? prefs.classFreeDays : classFreeDays(examPeriods);

  /// The student's exams in the period on show at [now], matched from the
  /// timetable and eClass; null outside every exam period.
  ExamMatch? exams(DateTime now) {
    final period = ExamPeriod.current(examPeriods, now);
    if (period == null) return null;
    return matchExams(
      period,
      studentCourses(lessons.data?.value ?? const [], attendance.data?.value ?? const []),
      classGroup: prefs.classGroup,
      rooms: prefs.examRooms,
    );
  }

  void setExamRoom(Exam exam, ExamPeriod period, String? room) {
    prefs.setExamRoom(exam.keyIn(period), room);
    notifyListeners();
  }

  void setThemeMode(ThemeMode mode) {
    prefs.themeMode = mode;
    notifyListeners();
  }

  void _check(Service s, {required bool ok}) => prefs.setAccountCheck(s, AccountCheck(ok, DateTime.now()));

  /// Appends the next page of [f]. Kept in memory only: the cache holds the
  /// first page, which is what a refresh brings back.
  Future<void> loadMoreMail([MailFolder f = MailFolder.inbox]) async {
    final box = _mailbox[f]!;
    final have = box.list.data;
    if (have == null || !box.hasMore || box.loadingMore || box.list.loading) return;
    box.loadingMore = true;
    box.moreError = null;
    notifyListeners();
    try {
      final page = await mail.folder(f, limit: mailPageSize, offset: have.value.length);
      // A refresh that started meanwhile replaces the list: this page was cut
      // from the old one. An edit (read, moved) keeps the fetch time and stays.
      final now = box.list.data;
      if (now != null && !box.list.loading && now.fetchedAt == have.fetchedAt) {
        final known = {for (final m in now.value) m.id};
        box.hasMore = page.length >= mailPageSize;
        box.list = Snapshot(
            data: Cached([...now.value, ...page.where((m) => !known.contains(m.id))], now.fetchedAt),
            error: box.list.error);
      }
    } catch (e) {
      box.moreError = e;
    }
    box.loadingMore = false;
    notifyListeners();
  }

  /// The messages in [folder] matching [query], newest first. Not cached and not
  /// kept here: the search screen holds its own results.
  Future<List<MailHeader>> searchMail(String query,
          {MailFolder folder = MailFolder.inbox, int offset = 0}) =>
      mail.search(folder, query, limit: mailPageSize, offset: offset);

  /// A message's attached file, by [MailAttachment.id].
  Future<MailFile> mailAttachment(String id) => mail.attachment(id);

  /// Sets a message's read flag on the server, then in [folder]'s list and
  /// its counts here. Call it only when the flag actually changes.
  Future<void> setMailRead(String id, {bool read = true, MailFolder folder = MailFolder.inbox}) async {
    await mail.markRead(id, read: read);
    await _editMailList(folder, (list) => [for (final m in list) m.id == id ? m.withUnread(!read) : m]);
    final step = read ? -1 : 1;
    final count = mailUnread.data;
    if (folder == MailFolder.inbox && count != null) {
      final n = (count.value + step).clamp(0, 1 << 30);
      mailUnread = Snapshot(
          data: await cache.write('mailUnread', n, (v) => v, at: count.fetchedAt),
          error: mailUnread.error,
          loading: mailUnread.loading);
    }
    if (mailCounts[folder] case final c?) {
      mailCounts = {...mailCounts, folder: MailFolderCount((c.unread + step).clamp(0, c.total), c.total)};
    }
    notifyListeners();
  }

  /// Moves [m] from [from] to [to] (deleting is a move to Deleted) and takes
  /// it off [from]'s list. Returns the message as it now is in [to], for an
  /// undo, or null when Exchange didn't give its new id.
  Future<MailHeader?> moveMail(MailHeader m, {required MailFolder from, required MailFolder to}) async {
    final id = await mail.move(m.id, to);
    await _editMailList(from, (list) => [for (final x in list) if (x.id != m.id) x]);
    final count = mailUnread.data;
    if (m.unread && count != null && (from == MailFolder.inbox || to == MailFolder.inbox)) {
      final n = (count.value + (from == MailFolder.inbox ? -1 : 1)).clamp(0, 1 << 30);
      mailUnread = Snapshot(
          data: await cache.write('mailUnread', n, (v) => v, at: count.fetchedAt),
          error: mailUnread.error,
          loading: mailUnread.loading);
    }
    notifyListeners();
    _refreshLoaded([to]);
    return id == null ? null : m.withId(id);
  }

  /// Sends [m]. A sent draft leaves Drafts; Sent gets the copy.
  Future<void> sendMail(OutgoingMail m) async {
    try {
      await mail.send(m);
    } catch (_) {
      // With files it was saved first, and what got that far is in Drafts.
      if (m.attachments.isNotEmpty) _refreshLoaded([MailFolder.drafts]);
      rethrow;
    }
    if (m.kind == ComposeKind.draft) {
      await _editMailList(MailFolder.drafts, (list) => [for (final x in list) if (x.id != m.ref!.id) x]);
      notifyListeners();
    }
    _refreshLoaded([MailFolder.sent, MailFolder.drafts]);
  }

  /// Saves [m] to Drafts, or the changes to a saved draft.
  Future<void> saveMailDraft(OutgoingMail m) async {
    await mail.saveDraft(m);
    _refreshLoaded([MailFolder.drafts]);
  }

  /// Refreshes those of [folders] that have been opened, and the counts, in
  /// the background: after a send or a move they are out of date.
  void _refreshLoaded(List<MailFolder> folders) {
    for (final f in folders) {
      if (_mailbox[f]!.list.data != null) unawaited(refreshMailFolder(f));
    }
    unawaited(refreshMailCounts());
  }

  /// Rewrites [f]'s loaded list, keeping its fetch time (an edit, not a fetch).
  Future<void> _editMailList(MailFolder f, List<MailHeader> Function(List<MailHeader>) edit) async {
    final box = _mailbox[f]!;
    final list = box.list.data;
    if (list == null) return;
    box.list = Snapshot(
        data: await cache.write(_mailKey(f), edit(list.value), _encodeList, at: list.fetchedAt),
        error: box.list.error,
        loading: box.list.loading);
  }

  /// Refreshes one source. [warning] is read once the fetch has worked: what
  /// went wrong with part of it, kept as the source's error beside the new data.
  /// A fetch overtaken by [_invalidate] (a sign-out, a new login, another class
  /// group), or finishing with no login saved any more, leaves no trace.
  Future<void> _run<T>({
    required Snapshot<T> Function() get,
    required void Function(Snapshot<T>) set,
    required Future<T> Function() fetch,
    required String key,
    required Object? Function(T) encode,
    required Service service,
    Object? Function()? warning,
  }) async {
    if (get().loading) return;
    final generation = _generation[service];
    set(Snapshot(data: get().data, loading: true));
    notifyListeners();
    try {
      final value = await fetch();
      if (generation != _generation[service]) return;
      if (!await _signedIn(service)) {
        set(Snapshot(data: get().data));
        notifyListeners();
        return;
      }
      if (generation != _generation[service]) return;
      final written = await cache.write(key, value, encode);
      if (generation != _generation[service]) {
        await cache.remove(key);
        return;
      }
      set(Snapshot(data: written, error: warning?.call()));
      if (_widgetCacheKeys.contains(key)) unawaited(onWidgetDataChanged?.call());
      // Any fetch that got through is a working login (Settings shows when).
      if (service.needsLogin) _check(service, ok: true);
    } catch (e) {
      if (generation != _generation[service]) return;
      if (kDebugMode) debugPrint('refresh $key failed: ${_debugDescribe(e)}');
      set(Snapshot(data: get().data, error: e));
      if (e is LoginRequired && service.needsLogin) _check(service, ok: false);
    }
    notifyListeners();
  }
}

/// One mail folder as loaded so far: the first page from the last refresh
/// (cached) and any older pages loaded since (in memory only).
class MailboxFolder {
  Snapshot<List<MailHeader>> list = const Snapshot();

  /// Whether the server may have messages past the last loaded page.
  bool hasMore = true;
  bool loadingMore = false;
  Object? moreError;
}

/// Debug-build log line: error type, Dio failure kind and URL. Never headers,
/// bodies or credentials.
String _debugDescribe(Object e) {
  if (e is DioException) {
    final u = e.requestOptions.uri;
    return 'DioException ${e.type.name} ${e.response?.statusCode ?? ''} '
        '${u.host}${u.path} cause=${e.error.runtimeType}: ${e.error}';
  }
  return '${e.runtimeType}: $e';
}

/// One plain sentence naming the service and what happened (DESIGN.md 10).
/// Raw exception text never reaches the screen.
String describeError(Object e, String service) {
  if (e is LoginRequired) return '$service sign-in needed.';
  if (e is SetupNeeded) return e.message;
  if (e is UnknownClassGroup) return "${e.name} isn't on the timetable. Choose your class group in Settings.";
  if (e is PartialRefresh) return "Couldn't update ${e.courses.join(', ')} from $service.";
  if (e is ParseError) return "Couldn't read the $service page; it may have changed.";
  if (isNetworkError(e)) return "Couldn't reach $service. Check the connection.";
  if (isServerError(e)) return "Couldn't reach $service.";
  return "Couldn't load from $service.";
}
