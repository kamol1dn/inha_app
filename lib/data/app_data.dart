import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart' show ThemeMode;
import 'package:shared_preferences/shared_preferences.dart';

import '../core/cache.dart';
import '../core/session.dart';
import '../models/models.dart';
import '../notifications/notifier.dart';
import '../services/eclass/eclass_api.dart';
import '../services/edupage/timetable_api.dart';
import '../services/ins/ins_api.dart';
import '../services/mail/mail_api.dart';

/// The last time a service answered with the saved login: [ok] when it let
/// the app in, false when it rejected the username or password.
class AccountCheck {
  final bool ok;
  final DateTime at;
  const AccountCheck(this.ok, this.at);

  Map<String, dynamic> toJson() => {'ok': ok, 'at': at.toIso8601String()};
  static AccountCheck? fromJson(Object? j) {
    if (j is! Map<String, dynamic>) return null;
    final at = DateTime.tryParse(j['at'] as String? ?? '');
    return at == null ? null : AccountCheck(j['ok'] == true, at);
  }
}

/// User choices that aren't secrets.
class Prefs {
  final SharedPreferences _p;
  Prefs(this._p);

  String get classGroup => _p.getString('classGroup') ?? 'ICE23-1';
  set classGroup(String v) => _p.setString('classGroup', v);

  /// Subjects the student dropped but EduPage still lists for the group.
  Set<String> get excludedSubjects =>
      (_p.getStringList('excludedSubjects') ?? const ['Big Data']).toSet();
  set excludedSubjects(Set<String> v) => _p.setStringList('excludedSubjects', v.toList());

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

  AppData({
    required this.eclass,
    required this.timetable,
    required this.ins,
    required this.mail,
    required this.cache,
    required this.prefs,
  }) {
    _readCache();
  }

  /// Called after the timetable or eClass data changes, which is what
  /// reminders are planned from. The app hooks the notifier in here.
  Future<void> Function()? onReminderDataChanged;

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
    deadlines = read(() => deadlines, cache.read('deadlines', _decodeList(Deadline.fromJson)));
    attendance =
        read(() => attendance, cache.read('attendance', _decodeList(CourseAttendance.fromJson)));
    grades = read(
        () => grades, cache.read('grades', (j) => GradeReport.fromJson(j as Map<String, dynamic>)));
    for (final box in [for (final f in MailFolder.values) (f, _mailbox[f]!)]) {
      box.$2.list = read(() => box.$2.list, cache.read(_mailKey(box.$1), _decodeList(MailHeader.fromJson)));
    }
    mailUnread = read(() => mailUnread, cache.read('mailUnread', (j) => j as int));
  }

  /// Picks up what the background refresh wrote while the app was away.
  Future<void> reloadFromCache() async {
    if ([lessons, deadlines, attendance, grades, mailUnread, for (final f in _mailbox.values) f.list]
        .any((s) => s.loading)) {
      return;
    }
    await cache.reload();
    _readCache(reload: true);
    notifyListeners();
  }

  late Snapshot<List<Lesson>> lessons;
  late Snapshot<List<Deadline>> deadlines;
  late Snapshot<List<CourseAttendance>> attendance;
  late Snapshot<GradeReport> grades;

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

  Future<void> refreshTimetable() async {
    await _run<List<Lesson>>(
      get: () => lessons,
      set: (s) => lessons = s,
      fetch: () => timetable.lessons(prefs.classGroup, excludeSubjects: prefs.excludedSubjects),
      key: 'lessons',
      encode: _encodeList,
      service: Service.edupage,
    );
    await onReminderDataChanged?.call();
  }

  /// Deadlines and attendance share one eClass login, so they refresh together.
  Future<void> refreshEclass() async {
    await _refreshEclassData();
    await onReminderDataChanged?.call();
  }

  Future<void> _refreshEclassData() async {
    await Future.wait([
      _run<List<Deadline>>(
        get: () => deadlines,
        set: (s) => deadlines = s,
        fetch: () async => _withSubmissions(await eclass.upcoming()),
        key: 'deadlines',
        encode: _encodeList,
        service: Service.eclass,
      ),
      _run<List<CourseAttendance>>(
        get: () => attendance,
        set: (s) => attendance = s,
        fetch: () async {
          final courses = await eclass.courses();
          return Future.wait(courses.map(eclass.attendance));
        },
        key: 'attendance',
        encode: _encodeList,
        service: Service.eclass,
      ),
    ]);
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
        final s = await eclass.submission(d);
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
        fetch: ins.grades,
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
          fetch: mail.unreadCount,
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
        final page = await mail.folder(f, limit: mailPageSize);
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
    try {
      mailCounts = await mail.folderCounts();
      notifyListeners();
    } catch (e) {
      if (kDebugMode) debugPrint('mail counts failed: ${_debugDescribe(e)}');
    }
  }

  /// Logs in to [s] with the saved login right away (the caller resets its
  /// cookies first, so the login really runs) and records the result. On
  /// success the service's data is refreshed. Returns the error, or null.
  Future<Object?> testLogin(Service s) async {
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
      if (e is LoginRequired) _check(s, ok: false);
      notifyListeners();
      return e;
    }
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

  /// After signing out of [s]: drops its cached data and its account check,
  /// so nothing from that account stays on the phone.
  Future<void> forget(Service s) async {
    for (final key in _cacheKeys[s]!) {
      await cache.remove(key);
    }
    prefs.setAccountCheck(s, null);
    switch (s) {
      case Service.eclass:
        deadlines = const Snapshot();
        attendance = const Snapshot();
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
  }

  static final _cacheKeys = {
    Service.eclass: ['deadlines', 'attendance'],
    Service.ins: ['grades'],
    Service.mail: ['mailUnread', for (final f in MailFolder.values) _mailKey(f)],
    Service.edupage: ['lessons'],
  };

  void setAbsenceLimit(int courseId, int? limit) {
    prefs.setAbsenceLimit(courseId, limit);
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
      final known = {for (final m in have.value) m.id};
      box.hasMore = page.length >= mailPageSize;
      box.list = Snapshot(
          data: Cached([...have.value, ...page.where((m) => !known.contains(m.id))], have.fetchedAt),
          error: box.list.error);
    } catch (e) {
      box.moreError = e;
    }
    box.loadingMore = false;
    notifyListeners();
  }

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
    return id == null
        ? null
        : MailHeader(
            id: id, from: m.from, to: m.to, subject: m.subject, received: m.received, preview: m.preview, unread: m.unread);
  }

  /// Sends [m]. A sent draft leaves Drafts; Sent gets the copy.
  Future<void> sendMail(OutgoingMail m) async {
    await mail.send(m);
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

  Future<void> _run<T>({
    required Snapshot<T> Function() get,
    required void Function(Snapshot<T>) set,
    required Future<T> Function() fetch,
    required String key,
    required Object? Function(T) encode,
    required Service service,
  }) async {
    if (get().loading) return;
    set(Snapshot(data: get().data, loading: true));
    notifyListeners();
    try {
      final value = await fetch();
      set(Snapshot(data: await cache.write(key, value, encode)));
      // Any fetch that got through is a working login (Settings shows when).
      if (service.needsLogin) _check(service, ok: true);
    } catch (e) {
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
  if (e is ParseError) return "Couldn't read the $service page; it may have changed.";
  if (e is DioException) {
    if (e.type == DioExceptionType.connectionTimeout ||
        e.type == DioExceptionType.receiveTimeout ||
        e.type == DioExceptionType.connectionError ||
        e.error is SocketException) {
      return "Couldn't reach $service. Check the connection.";
    }
  }
  return "Couldn't load from $service.";
}
