import 'package:dio/dio.dart';

import '../../core/credentials.dart';
import '../../core/session.dart';
import '../../models/models.dart';
import 'eclass_api.dart';
import 'eclass_links.dart';
import 'eclass_parsers.dart';

/// [EclassApi] over eClass's HTML pages: posts the login form, keeps the
/// session cookie in the [Sessions] cookie jar, and parses what comes back.
///
/// Every fetch that lands on the login page (session expired) logs in once
/// with the saved credentials and retries once.
class EclassClient implements EclassApi {
  EclassClient(this._sessions, this._credentials);

  static final Uri base = eclassBase;
  static const _maxLoginRedirects = 5;

  final Sessions _sessions;
  final CredentialStore _credentials;

  /// The login in progress, shared so parallel fetches that all find the
  /// session expired trigger one login, not several.
  Future<void>? _loggingIn;

  Dio get _dio => _sessions.client(Service.eclass);

  @override
  Future<void> ensureLoggedIn() async {
    final res = await _get('/');
    if (_isLoggedOut(res)) await _login();
  }

  @override
  Future<List<Course>> courses() => _fetchList('/', parseCourses);

  @override
  Future<List<Deadline>> upcoming() =>
      _fetchList('/calendar/view.php?view=upcoming', parseUpcoming);

  @override
  Future<CourseAttendance> attendance(Course course) async {
    final classes = _fetchList<AttendanceEntry>(
        '/local/ubattendance/my_status.php?id=${course.id}', parseAttendance,
        optional: true);
    final vods = _fetchList<VodProgress>(
        '/report/ubcompletion/user_progress.php?id=${course.id}', parseVodProgress,
        optional: true);
    // Wait on both together so a failure in one never goes unhandled.
    await Future.wait([classes, vods]);
    return CourseAttendance(course: course, classes: await classes, vods: await vods);
  }

  @override
  Future<({bool done, DateTime? at})?> submission(Deadline d) async {
    final id = d.moduleId;
    if (id == null) return null;
    final (path, parse) = switch (d.kind) {
      DeadlineKind.assignment => ('/mod/assign/view.php?id=$id', parseAssignSubmission),
      DeadlineKind.quiz => ('/mod/quiz/view.php?id=$id', parseQuizSubmission),
      _ => (null, null),
    };
    if (path == null || parse == null) return null;
    return (await _fetchList(path, (html) => [parse(html)])).single;
  }

  /// GETs [path] and parses it, logging in and retrying once if the session
  /// had expired. With [optional], a 404 or a redirect to some other page
  /// (the course does not have this page) gives an empty list.
  Future<List<E>> _fetchList<E>(
    String path,
    List<E> Function(String html) parse, {
    bool optional = false,
  }) async {
    var res = await _get(path);
    if (_isLoggedOut(res)) {
      await _login();
      res = await _get(path);
      if (_isLoggedOut(res)) {
        throw LoginRequired(Service.eclass, 'eClass logged in but did not keep the session');
      }
    }

    final status = res.statusCode ?? 0;
    if (optional && (status == 404 || _redirectedAway(res, path))) return <E>[];
    if (status >= 400) {
      throw DioException.badResponse(
          statusCode: status, requestOptions: res.requestOptions, response: res);
    }
    return parse(res.data ?? '');
  }

  Future<Response<String>> _get(String path) => _dio.get<String>(
        base.resolve(path).toString(),
        options: Options(responseType: ResponseType.plain),
      );

  Future<void> _login() =>
      _loggingIn ??= _postLogin().whenComplete(() => _loggingIn = null);

  Future<void> _postLogin() async {
    final creds = await _credentials.read(Service.eclass);
    if (creds == null || creds.username.isEmpty || creds.password.isEmpty) {
      throw LoginRequired(Service.eclass, 'No eClass login saved');
    }

    var at = base.resolve('/login/index.php');
    var res = await _dio.post<String>(
      at.toString(),
      data: {'username': creds.username, 'password': creds.password},
      options: _manualRedirects(contentType: Headers.formUrlEncodedContentType),
    );

    // Follow redirects by hand: with followRedirects on, the cookie manager
    // only sees the final response, and the fresh MoodleSession cookie that
    // the login redirect sets would be lost. Moodle answers a good login with
    // 303 → /login/index.php?testsession=<id> → 303 → the dashboard.
    for (var hop = 0; hop < _maxLoginRedirects && _isRedirect(res); hop++) {
      final location = res.headers.value('location');
      if (location == null) break;
      at = at.resolve(location);
      res = await _dio.get<String>(at.toString(), options: _manualRedirects());
    }

    // A rejected login shows the login form again (with an error box).
    if (isLoginPage(res.data ?? '')) {
      throw LoginRequired(Service.eclass, 'eClass rejected the saved login');
    }
    final status = res.statusCode ?? 0;
    if (status >= 400) {
      throw DioException.badResponse(
          statusCode: status, requestOptions: res.requestOptions, response: res);
    }
  }

  Options _manualRedirects({String? contentType}) => Options(
        followRedirects: false,
        responseType: ResponseType.plain,
        contentType: contentType,
        validateStatus: (code) => code != null && code < 500,
      );

  static bool _isRedirect(Response<Object?> res) {
    final code = res.statusCode ?? 0;
    return code >= 300 && code < 400;
  }

  /// Where the response actually came from, after any redirects.
  static Uri _finalUri(Response<Object?> res) =>
      res.requestOptions.uri.resolveUri(res.realUri);

  /// True when eClass answered with (or redirected to) its login page.
  static bool _isLoggedOut(Response<String> res) {
    final at = _finalUri(res);
    if (at.path.startsWith('/login/')) return true;
    if (_isRedirect(res)) {
      final location = res.headers.value('location');
      if (location != null && at.resolve(location).path.startsWith('/login/')) return true;
    }
    final body = res.data ?? '';
    if (body.contains('password') && isLoginPage(body)) return true;
    // Some pages (the calendar) render for guests too, empty. Every
    // logged-in page carries the logout link in its header.
    final status = res.statusCode ?? 0;
    return status >= 200 && status < 300 && !body.contains('/login/logout.php');
  }

  /// True when eClass sent us somewhere other than [path] (but not to login).
  static bool _redirectedAway(Response<Object?> res, String path) =>
      res.redirects.isNotEmpty && _finalUri(res).path != base.resolve(path).path;
}
