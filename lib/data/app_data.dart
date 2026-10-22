import 'dart:async';
import 'dart:io';

import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../core/cache.dart';
import '../core/session.dart';
import '../models/models.dart';
import '../services/eclass/eclass_api.dart';
import '../services/edupage/timetable_api.dart';
import '../services/ins/ins_api.dart';
import '../services/mail/mail_api.dart';

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

  /// Whether the Android notification permission prompt was shown once.
  bool get notificationsAsked => _p.getBool('notify.asked') ?? false;
  set notificationsAsked(bool v) => _p.setBool('notify.asked', v);

  bool get showWatchedVods => _p.getBool('deadlines.showWatched') ?? false;
  set showWatchedVods(bool v) => _p.setBool('deadlines.showWatched', v);

  void resetDeadlineFilters() {
    _p.remove('deadlines.kinds');
    _p.remove('deadlines.course');
    _p.remove('deadlines.showWatched');
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

  void _readCache() {
    lessons = Snapshot(data: cache.read('lessons', _decodeList(Lesson.fromJson)));
    deadlines = Snapshot(data: cache.read('deadlines', _decodeList(Deadline.fromJson)));
    attendance =
        Snapshot(data: cache.read('attendance', _decodeList(CourseAttendance.fromJson)));
    grades = Snapshot(
        data: cache.read('grades', (j) => GradeReport.fromJson(j as Map<String, dynamic>)));
    inbox = Snapshot(data: cache.read('inbox', _decodeList(MailHeader.fromJson)));
  }

  /// Picks up what the background refresh wrote while the app was away.
  Future<void> reloadFromCache() async {
    if ([lessons, deadlines, attendance, grades, inbox].any((s) => s.loading)) return;
    await cache.reload();
    _readCache();
    notifyListeners();
  }

  late Snapshot<List<Lesson>> lessons;
  late Snapshot<List<Deadline>> deadlines;
  late Snapshot<List<CourseAttendance>> attendance;
  late Snapshot<GradeReport> grades;
  late Snapshot<List<MailHeader>> inbox;

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
        fetch: eclass.upcoming,
        key: 'deadlines',
        encode: _encodeList,
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
      ),
    ]);
  }

  Future<void> refreshGrades() => _run<GradeReport>(
        get: () => grades,
        set: (s) => grades = s,
        fetch: ins.grades,
        key: 'grades',
        encode: (v) => v.toJson(),
      );

  Future<void> refreshMail() => _run<List<MailHeader>>(
        get: () => inbox,
        set: (s) => inbox = s,
        fetch: () => mail.inbox(),
        key: 'inbox',
        encode: _encodeList,
      );

  Future<void> _run<T>({
    required Snapshot<T> Function() get,
    required void Function(Snapshot<T>) set,
    required Future<T> Function() fetch,
    required String key,
    required Object? Function(T) encode,
  }) async {
    if (get().loading) return;
    set(Snapshot(data: get().data, loading: true));
    notifyListeners();
    try {
      final value = await fetch();
      set(Snapshot(data: await cache.write(key, value, encode)));
    } catch (e) {
      if (kDebugMode) debugPrint('refresh $key failed: ${_debugDescribe(e)}');
      set(Snapshot(data: get().data, error: e));
    }
    notifyListeners();
  }
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
      return "Couldn't reach $service. Check the connection or VPN.";
    }
  }
  return "Couldn't load from $service.";
}
