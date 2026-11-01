import 'dart:async';

import 'package:cookie_jar/cookie_jar.dart';
import 'package:dio/dio.dart';
import 'package:dio_cookie_manager/dio_cookie_manager.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:inha_app/app.dart';
import 'package:inha_app/core/session.dart';
import 'package:inha_app/data/app_data.dart';
import 'package:inha_app/features/course_detail_screen.dart';
import 'package:inha_app/features/details.dart';
import 'package:inha_app/features/vod_player_screen.dart';
import 'package:inha_app/models/models.dart';
import 'package:inha_app/ui/format/format.dart';
import 'package:provider/provider.dart';
import 'package:webview_flutter_platform_interface/webview_flutter_platform_interface.dart';

import 'fakes.dart';

const ai = Course(id: 2622, name: 'Artificial Intelligence', code: 'SOC4040');
const mmc = Course(id: 2615, name: 'Multimedia Computing', code: 'SOC4020');

VodProgress video({
  double percent = 40,
  int? moduleId = 72100,
  DateTime? opens,
  DateTime? closes,
}) =>
    VodProgress(
      week: 7,
      title: 'Video 7',
      length: const Duration(minutes: 75),
      percent: percent,
      moduleId: moduleId,
      opens: opens,
      closes: closes,
    );

/// A [FakeEclass] whose attendance pages wait, to overlap a fetch with something.
class GatedEclass extends FakeEclass {
  Completer<void>? gate;
  int attendanceCalls = 0;

  @override
  Future<CourseAttendance> attendance(Course course) async {
    attendanceCalls++;
    final answer = attendanceById[course.id] ?? CourseAttendance(course: course); // what this request saw
    await gate?.future;
    return answer;
  }
}

Future<void> pumpScreen(WidgetTester tester, AppData data, Widget screen) async {
  tester.view.physicalSize = const Size(412, 2400) * 3;
  tester.view.devicePixelRatio = 3;
  addTearDown(tester.view.reset);
  await tester.pumpWidget(ChangeNotifierProvider.value(
    value: data,
    child: MaterialApp(theme: InhaApp.light, home: screen),
  ));
  await tester.pump();
}

/// A stand-in WebView: it records what the screen asks of it, and a test plays the
/// page's part through [nav] and [dialogs]. What is Android's own (fullscreen,
/// autoplay) needs a phone.
class FakeWebView extends WebViewPlatform {
  FakeWebController? controller;
  FakeNavigation? navigation;
  final cookies = FakeCookies(const PlatformWebViewCookieManagerCreationParams());

  @override
  PlatformWebViewController createPlatformWebViewController(PlatformWebViewControllerCreationParams params) =>
      controller = FakeWebController(params);
  @override
  PlatformNavigationDelegate createPlatformNavigationDelegate(PlatformNavigationDelegateCreationParams params) =>
      navigation = FakeNavigation(params);
  @override
  PlatformWebViewCookieManager createPlatformCookieManager(PlatformWebViewCookieManagerCreationParams params) => cookies;
  @override
  PlatformWebViewWidget createPlatformWebViewWidget(PlatformWebViewWidgetCreationParams params) => FakeWebWidget(params);
}

class FakeWebWidget extends PlatformWebViewWidget {
  FakeWebWidget(super.params) : super.implementation();
  @override
  Widget build(BuildContext context) => const SizedBox(key: ValueKey('webview'));
}

class FakeCookies extends PlatformWebViewCookieManager {
  FakeCookies(super.params) : super.implementation();
  final log = <String>[];
  @override
  Future<bool> clearCookies() async {
    log.add('clear');
    return true;
  }

  @override
  Future<void> setCookie(WebViewCookie cookie) async => log.add('${cookie.name}=${cookie.value}');
}

class FakeNavigation extends PlatformNavigationDelegate {
  FakeNavigation(super.params) : super.implementation();
  NavigationRequestCallback? request;
  PageEventCallback? finished;
  WebResourceErrorCallback? error;
  @override
  Future<void> setOnNavigationRequest(NavigationRequestCallback onNavigationRequest) async =>
      request = onNavigationRequest;
  @override
  Future<void> setOnPageFinished(PageEventCallback onPageFinished) async => finished = onPageFinished;
  @override
  Future<void> setOnWebResourceError(WebResourceErrorCallback onWebResourceError) async => error = onWebResourceError;
}

class FakeWebController extends PlatformWebViewController {
  FakeWebController(super.params) : super.implementation();
  final loads = <String>[];
  final ran = <String>[];
  String? userAgent;
  Object clock = 'null'; // what the video element answers
  Object loginPage = false;
  bool throwOnClock = false;
  Future<void> Function(JavaScriptAlertDialogRequest)? alert;
  Future<bool> Function(JavaScriptConfirmDialogRequest)? confirm;

  @override
  Future<void> setJavaScriptMode(JavaScriptMode javaScriptMode) async {}
  @override
  Future<void> setUserAgent(String? userAgent) async => this.userAgent = userAgent;
  @override
  Future<void> setBackgroundColor(Color color) async {}
  @override
  Future<void> setPlatformNavigationDelegate(PlatformNavigationDelegate handler) async {}
  @override
  Future<void> setOnJavaScriptAlertDialog(Future<void> Function(JavaScriptAlertDialogRequest) onJavaScriptAlertDialog) async =>
      alert = onJavaScriptAlertDialog;
  @override
  Future<void> setOnJavaScriptConfirmDialog(Future<bool> Function(JavaScriptConfirmDialogRequest) onJavaScriptConfirmDialog) async =>
      confirm = onJavaScriptConfirmDialog;
  @override
  Future<void> loadRequest(LoadRequestParams params) async => loads.add(params.uri.toString());
  @override
  Future<void> runJavaScript(String javaScript) async => ran.add(javaScript);
  @override
  Future<Object> runJavaScriptReturningResult(String javaScript) async {
    ran.add(javaScript);
    if (javaScript == loginPageJs) return loginPage;
    if (throwOnClock) throw StateError('no page');
    return clock;
  }
}

class FakeSessions implements Sessions {
  final dio = Dio(BaseOptions(headers: {'User-Agent': 'Desktop agent'}))..interceptors.add(CookieManager(CookieJar()));

  @override
  Dio client(Service s) => dio;
  @override
  Future<void> init() async {}
  @override
  Future<void> reset(Service s) async {}
}

void main() {
  final now = DateTime(2026, 10, 23, 9);

  test('the player is viewer.php on eClass, by module id', () {
    expect(vodViewerUrl(72100).toString(), 'https://eclass.inha.ac.kr/mod/vod/viewer.php?id=72100');
  });

  group('session cookies', () {
    final url = vodViewerUrl(72100);

    test('come from the Dio jar, without expired ones', () async {
      final jar = CookieJar();
      await jar.saveFromResponse(url, [
        Cookie('MoodleSession', 'abc123')
          ..path = '/'
          ..httpOnly = true,
        Cookie('Old', 'x')..expires = DateTime(2020),
      ]);
      final dio = Dio()..interceptors.add(CookieManager(jar));
      expect((await dioCookies(dio, url)).map((c) => c.name), ['MoodleSession']);
    });

    test('a Dio with no jar has none', () async {
      expect(await dioCookies(Dio(), url), isEmpty);
    });

    test('become WebView cookies bound to the https origin, with a path', () {
      final out = webViewCookies([
        Cookie('MoodleSession', 'abc123')..path = '/',
        Cookie('Scoped', 'y')..path = '/mod/vod',
        Cookie('NoPath', 'z'),
      ], url);
      expect(out.map((c) => c.name), ['MoodleSession', 'Scoped', 'NoPath']);
      expect(out.first.value, 'abc123');
      expect(out.map((c) => c.domain).toSet(), {'https://eclass.inha.ac.kr'});
      expect(out.map((c) => c.path), ['/', '/mod/vod', '/']);
    });
  });

  group('navigation', () {
    VodNavigation top(String url) => vodNavigation(Uri.tryParse(url), mainFrame: true);

    test('eClass stays, other sites go to the browser', () {
      expect(top('https://eclass.inha.ac.kr/mod/vod/viewer.php?id=1'), VodNavigation.stay);
      expect(top('https://eclass.inha.ac.kr/course/view.php?id=2622'), VodNavigation.stay);
      expect(top('https://example.org/help'), VodNavigation.browser);
      expect(top('mailto:office@inha.uz'), VodNavigation.browser);
    });

    test('the login page asks for a sign-in; logging out and other schemes do nothing', () {
      expect(top('https://eclass.inha.ac.kr/login/index.php'), VodNavigation.signIn);
      expect(top('https://eclass.inha.ac.kr/login/logout.php?sesskey=x'), VodNavigation.block);
      expect(top('intent://open#Intent;end'), VodNavigation.block);
    });

    test('closing the page and whatever a subframe loads are left alone', () {
      expect(top('about:blank'), VodNavigation.stay);
      expect(vodNavigation(Uri.parse('https://cdn.example.org/embed'), mainFrame: false), VodNavigation.stay);
      expect(vodNavigation(null, mainFrame: true), VodNavigation.block);
    });
  });

  group('reading the video', () {
    test('as it comes back from Android, in JSON quotes', () {
      final c = parseVideoClock('"1390.5|2700|4|1"')!;
      expect(c.position, 1390.5);
      expect(c.duration, 2700);
      expect(c.hasMetadata, isTrue);
      expect(c.playing, isTrue);
    });

    test('a duration not known yet, and no metadata', () {
      final c = parseVideoClock('0|NaN|0|0')!;
      expect(c.duration, isNull);
      expect(c.hasMetadata, isFalse);
      expect(c.playing, isFalse);
      expect(parseVideoClock('12|Infinity|1|0')!.duration, isNull);
    });

    test('no video, no page, or anything else is null', () {
      for (final raw in <Object?>[null, 'null', '', '""', 12, true, 'garbage', 'NaN|1|1|0', '-1|1|1|0', '1|2|3']) {
        expect(parseVideoClock(raw), isNull, reason: '$raw');
      }
    });
  });

  group('the place in a video', () {
    VideoClock at(double s, {double? of = 2700, bool ready = true}) =>
        VideoClock(position: s, duration: of, hasMetadata: ready);

    test('no saved place: from 10 s on, the reading is saved', () {
      final p = VodPlace();
      expect(p.tick(at(4)).keep, isNull);
      expect(p.tick(at(12.7)).keep, 12);
      expect(p.tick(at(1390)).seekTo, isNull);
    });

    test('the player stays near the start: it goes to the saved place, a reading later', () {
      final p = VodPlace(saved: 1390);
      expect(p.tick(at(0)), (seekTo: null, keep: null, clear: false)); // the player's own jump may still come
      expect(p.tick(at(0)).seekTo, 1390);
      expect(p.tick(at(1393)).keep, 1393);
      expect(p.tick(at(1396)).seekTo, isNull);
    });

    test("eClass's player went there by itself: no seek", () {
      final p = VodPlace(saved: 1390);
      p.tick(at(0));
      final step = p.tick(at(1500));
      expect(step.seekTo, isNull);
      expect(step.keep, 1500);
    });

    test('waits for the video, and saves nothing over the place meanwhile', () {
      final p = VodPlace(saved: 1390);
      expect(p.tick(null).keep, isNull);
      expect(p.tick(at(0, of: null, ready: false)).keep, isNull);
      expect(p.note(at(0)).keep, isNull);
      expect(p.tick(at(0)).seekTo, isNull);
      expect(p.tick(at(0)).seekTo, 1390);
    });

    test('a small jump, or a place at the very end, is not worth seeking to', () {
      final near = VodPlace(saved: 25)
        ..tick(at(0));
      expect(near.tick(at(0)).seekTo, isNull);
      final end = VodPlace(saved: 2690)
        ..tick(at(0));
      expect(end.tick(at(0)).seekTo, isNull);
    });

    test('at the end there is nothing to continue', () {
      final p = VodPlace()..tick(at(100));
      expect(p.tick(at(2680)).clear, isTrue);
      expect(p.note(at(2690)).clear, isTrue);
    });

    test('leaving saves the reading once settled, and never seeks', () {
      final p = VodPlace()..tick(at(50));
      final step = p.note(at(60));
      expect(step.keep, 60);
      expect(step.seekTo, isNull);
    });
  });

  test('a position reads 23:10, with hours when it has them', () {
    expect(playPosition(1390), '23:10');
    expect(playPosition(65), '1:05');
    expect(playPosition(3909), '1:05:09');
  });

  group('what a row offers', () {
    final opens = now.subtract(const Duration(days: 1));
    final closes = now.add(const Duration(days: 1));

    test('with a module id in its window: Watch, or Watch again once fully watched', () {
      expect(vodOffer(moduleId: 1, opens: opens, closes: closes, now: now), VodOffer.watch);
      expect(vodOffer(moduleId: 1, now: now), VodOffer.watch); // no window on the page
      expect(vodOffer(moduleId: 1, closes: closes, done: true, now: now), VodOffer.watchAgain);
    });

    test('no module id: eClass in the browser', () {
      expect(vodOffer(moduleId: null, closes: closes, now: now), VodOffer.browser);
    });

    test('the window closed or not open yet, module id or not', () {
      final past = now.subtract(const Duration(minutes: 1));
      expect(vodOffer(moduleId: 1, closes: past, now: now), VodOffer.closed);
      expect(vodOffer(moduleId: null, closes: past, now: now), VodOffer.closed);
      expect(vodOffer(moduleId: 1, closes: past, done: true, now: now), VodOffer.closed);
      expect(vodOffer(moduleId: 1, opens: closes, now: now), VodOffer.notOpen);
    });
  });

  group('saved positions', () {
    test('are kept per module, and can be removed', () async {
      final (data, _, _, _, _) = await makeAppData();
      expect(data.prefs.vodPosition(1), isNull);
      data.prefs.setVodPosition(1, 1390);
      data.prefs.setVodPosition(2, 60);
      expect(data.prefs.vodPosition(1), 1390);
      data.prefs.setVodPosition(1, null);
      expect(data.prefs.vodPosition(1), isNull);
      expect(data.prefs.vodPosition(2), 60);
    });

    test('a broken value reads as none', () async {
      final (data, _, _, _, _) = await makeAppData(prefs: {'vod.positions.v1': 'not json'});
      expect(data.prefs.vodPosition(1), isNull);
      data.prefs.setVodPosition(1, 90);
      expect(data.prefs.vodPosition(1), 90);
    });

    test('go with the eClass account', () async {
      final (data, _, _, _, _) = await makeAppData();
      data.prefs.setVodPosition(1, 1390);
      await data.forget(Service.eclass);
      expect(data.prefs.vodPosition(1), isNull);
    });
  });

  group('refreshing one course after watching', () {
    Future<(AppData, FakeEclass)> loaded() async {
      final (data, eclass, _, _, _) = await makeAppData();
      eclass.courseList = const [ai, mmc];
      eclass.attendanceById = {
        ai.id: CourseAttendance(course: ai, vods: [video(percent: 40)]),
        mmc.id: const CourseAttendance(course: mmc),
      };
      await data.refreshEclass();
      return (data, eclass);
    }

    double percentOf(AppData data, Course c) =>
        data.attendance.data!.value.firstWhere((a) => a.course.id == c.id).vods.single.percent;

    test('changes that course only, keeps the fetch time, and writes the cache', () async {
      final (data, eclass) = await loaded();
      final fetched = data.attendance.data!.fetchedAt;
      eclass.courseCalls = 0;
      eclass.attendanceById = {
        ai.id: CourseAttendance(course: ai, vods: [video(percent: 62)]),
        mmc.id: CourseAttendance(course: mmc, vods: [video(percent: 99)]), // not asked for
      };
      await data.refreshCourseAttendance(ai.id);
      expect(percentOf(data, ai), 62);
      expect(data.attendance.data!.value.firstWhere((a) => a.course.id == mmc.id).vods, isEmpty);
      expect(data.attendance.data!.fetchedAt, fetched);
      expect(eclass.courseCalls, 0);
      await data.reloadFromCache();
      expect(percentOf(data, ai), 62);
    });

    test('tells the reminders and the widgets', () async {
      final (data, _) = await loaded();
      var reminders = 0, widgets = 0;
      data.onReminderDataChanged = () async => reminders++;
      data.onWidgetDataChanged = () async => widgets++;
      await data.refreshCourseAttendance(ai.id);
      expect(reminders, 1);
      expect(widgets, 1);
    });

    test('a failure keeps the rows and says so', () async {
      final (data, eclass) = await loaded();
      eclass.failingCourses = {ai.id: Exception('eClass did not answer')};
      await data.refreshCourseAttendance(ai.id);
      expect(percentOf(data, ai), 40);
      expect(data.attendance.error, isA<Exception>());
    });

    test('an expired login is recorded', () async {
      final (data, eclass) = await loaded();
      eclass.failingCourses = {ai.id: LoginRequired(Service.eclass)};
      await data.refreshCourseAttendance(ai.id);
      expect(data.attendance.error, isA<LoginRequired>());
      expect(data.prefs.accountCheck(Service.eclass)!.ok, isFalse);
    });

    test('a course not on the list, or none known, asks for nothing', () async {
      final (data, eclass) = await loaded();
      eclass.failingCourses = {999: Exception('never asked')};
      var told = 0;
      data.addListener(() => told++);
      await data.refreshCourseAttendance(999);
      await data.refreshCourseAttendance(null);
      expect(data.attendance.error, isNull);
      expect(told, 2); // the row's "Continue from" still gets redrawn
    });

    test('a refresh already running lands first, then the course is read again', () async {
      final (data, _, _, _, _) = await makeAppData();
      final gated = GatedEclass()
        ..courseList = const [ai]
        ..attendanceById = {ai.id: CourseAttendance(course: ai, vods: [video(percent: 40)])};
      final d = AppData(
          eclass: gated, timetable: data.timetable, ins: data.ins, mail: data.mail, cache: data.cache, prefs: data.prefs);
      gated.gate = Completer<void>();
      final full = d.refreshEclass();
      await pumpEventQueue();
      expect(d.attendance.loading, isTrue);

      gated.attendanceById = {ai.id: CourseAttendance(course: ai, vods: [video(percent: 62)])};
      final one = d.refreshCourseAttendance(ai.id);
      await pumpEventQueue();
      final before = gated.attendanceCalls;
      gated.gate!.complete();
      await Future.wait([full, one]);
      expect(gated.attendanceCalls, before + 1);
      expect(d.attendance.data!.value.single.vods.single.percent, 62);
    });

    test('a sign-out while it runs leaves nothing behind', () async {
      final (data, _, _, _, _) = await makeAppData();
      final gated = GatedEclass()
        ..courseList = const [ai]
        ..attendanceById = {ai.id: CourseAttendance(course: ai, vods: [video()])};
      final d = AppData(
          eclass: gated, timetable: data.timetable, ins: data.ins, mail: data.mail, cache: data.cache, prefs: data.prefs);
      await d.refreshEclass();
      gated.gate = Completer<void>();
      final one = d.refreshCourseAttendance(ai.id);
      await pumpEventQueue();
      await d.forget(Service.eclass);
      gated.gate!.complete();
      await one;
      expect(d.attendance.data, isNull);
    });
  });

  group('checking the session before the player', () {
    test('logs in through the client', () async {
      final (data, eclass, _, _, _) = await makeAppData();
      await data.ensureEclassSession();
      expect(eclass.logins, 1);
    });

    test('a refused login comes back, and shows in Settings', () async {
      final (data, eclass, _, _, _) = await makeAppData();
      eclass.loginError = LoginRequired(Service.eclass);
      await expectLater(data.ensureEclassSession(), throwsA(isA<LoginRequired>()));
      expect(data.prefs.accountCheck(Service.eclass)!.ok, isFalse);
    });
  });

  group('the VOD row', () {
    Future<AppData> withVod(VodProgress v, {Map<String, Object> prefs = const {}}) async {
      final (data, eclass, _, _, _) = await makeAppData(prefs: prefs);
      eclass.courseList = const [ai];
      eclass.attendanceById = {ai.id: CourseAttendance(course: ai, vods: [v])};
      await data.refreshEclass();
      return data;
    }

    final day = DateTime.now().add(const Duration(days: 2));
    final past = DateTime.now().subtract(const Duration(days: 2));
    const screen = CourseDetailScreen(courseId: 2622, name: 'Artificial Intelligence');

    Finder button(String label) => find.widgetWithText(TextButton, label);

    testWidgets('offers Watch, and no filled button', (tester) async {
      await pumpScreen(tester, await withVod(video(closes: day)), screen);
      expect(button('Watch'), findsOneWidget);
      expect(find.textContaining('Continue from'), findsNothing);
      expect(find.byType(FilledButton), findsNothing);
    });

    testWidgets('says where the student left it', (tester) async {
      final data = await withVod(video(closes: day), prefs: {'vod.positions.v1': '{"72100":1390}'});
      await pumpScreen(tester, data, screen);
      expect(find.text('Continue from 23:10'), findsOneWidget);
      expect(button('Watch'), findsOneWidget);
    });

    testWidgets('fully watched: Watch again, and no place to continue from', (tester) async {
      final data = await withVod(video(percent: 100), prefs: {'vod.positions.v1': '{"72100":1390}'});
      await pumpScreen(tester, data, screen);
      expect(button('Watch again'), findsOneWidget);
      expect(find.textContaining('Continue from'), findsNothing);
    });

    testWidgets('no module id: only eClass in the browser', (tester) async {
      await pumpScreen(tester, await withVod(video(moduleId: null)), screen);
      expect(button('Watch'), findsNothing);
      // The course's own button is there as well.
      expect(button('Open in eClass'), findsNWidgets(2));
    });

    testWidgets('closed: says so, and links to it if it can', (tester) async {
      await pumpScreen(tester, await withVod(video(closes: past)), screen);
      expect(button('Watch'), findsNothing);
      expect(find.text('Closed ${dayDateTime(past)}'), findsOneWidget);
      expect(button('Open in eClass'), findsNWidgets(2));
    });

    testWidgets('closed with no module id: says so, with no link', (tester) async {
      await pumpScreen(tester, await withVod(video(closes: past, moduleId: null)), screen);
      expect(find.text('Closed ${dayDateTime(past)}'), findsOneWidget);
      expect(button('Open in eClass'), findsOneWidget);
    });

    testWidgets('not open yet: says when', (tester) async {
      await pumpScreen(tester, await withVod(video(opens: day)), screen);
      expect(button('Watch'), findsNothing);
      expect(find.text('Opens ${dayDateTime(day)}'), findsOneWidget);
    });

    testWidgets('reads at double text size without overflowing', (tester) async {
      tester.view.physicalSize = const Size(360, 2400) * 3;
      tester.view.devicePixelRatio = 3;
      addTearDown(tester.view.reset);
      final data = await withVod(video(closes: day), prefs: {'vod.positions.v1': '{"72100":1390}'});
      await tester.pumpWidget(ChangeNotifierProvider.value(
        value: data,
        child: MaterialApp(
          theme: InhaApp.light,
          builder: (context, child) => MediaQuery(
            data: MediaQuery.of(context).copyWith(textScaler: const TextScaler.linear(2)),
            child: child!,
          ),
          home: screen,
        ),
      ));
      await tester.pump();
      expect(tester.takeException(), isNull);
      expect(find.text('Continue from 23:10'), findsOneWidget);
    });
  });

  group('the deadline sheet', () {
    Deadline window({int? moduleId = 72100, DateTime? start, DateTime? end}) => Deadline(
          title: 'Video 7 (Vod closes)',
          courseName: ai.name,
          courseId: ai.id,
          kind: DeadlineKind.vod,
          start: start,
          end: end ?? DateTime.now().add(const Duration(days: 2)),
          moduleId: moduleId,
          moduleType: 'vod',
        );

    Future<void> openSheet(WidgetTester tester, Deadline d, {VodProgress? progress, Map<String, Object> prefs = const {}}) async {
      final (data, eclass, _, _, _) = await makeAppData(prefs: prefs);
      eclass.courseList = const [ai];
      eclass.attendanceById = {
        ai.id: CourseAttendance(course: ai, vods: [?progress])
      };
      await data.refreshEclass();
      await pumpScreen(
        tester,
        data,
        Builder(
          builder: (context) => Scaffold(
            body: TextButton(onPressed: () => showDeadlineSheet(context, d), child: const Text('open')),
          ),
        ),
      );
      await tester.tap(find.text('open'));
      await tester.pumpAndSettle();
    }

    testWidgets('a VOD in its window: Watch is the one filled button, eClass a text button', (tester) async {
      await openSheet(tester, window());
      expect(find.widgetWithText(FilledButton, 'Watch'), findsOneWidget);
      expect(find.byType(FilledButton), findsOneWidget);
      expect(find.widgetWithText(TextButton, 'Open in eClass'), findsOneWidget);
    });

    testWidgets('a VOD with a saved place says so', (tester) async {
      await openSheet(tester, window(), prefs: {'vod.positions.v1': '{"72100":1390}'});
      expect(find.text('Continue from 23:10'), findsOneWidget);
    });

    testWidgets('the window has closed: no Watch, eClass stays the filled button', (tester) async {
      await openSheet(tester, window(end: DateTime.now().subtract(const Duration(hours: 2))));
      expect(find.text('Watch'), findsNothing);
      expect(find.widgetWithText(FilledButton, 'Open in eClass'), findsOneWidget);
      expect(find.textContaining('Closed 2 h ago'), findsOneWidget);
    });

    testWidgets('not open yet: no Watch', (tester) async {
      await openSheet(tester, window(start: DateTime.now().add(const Duration(days: 1))));
      expect(find.text('Watch'), findsNothing);
    });

    testWidgets('no module id anywhere: no Watch', (tester) async {
      await openSheet(tester, window(moduleId: null));
      expect(find.text('Watch'), findsNothing);
    });

    testWidgets("the progress row's module id does when the event has none", (tester) async {
      final d = Deadline(
          title: 'Video 7',
          courseName: ai.name,
          courseId: ai.id,
          kind: DeadlineKind.vod,
          end: DateTime.now().add(const Duration(days: 2)));
      await openSheet(tester, d, progress: video());
      expect(find.widgetWithText(FilledButton, 'Watch'), findsOneWidget);
    });

    testWidgets('an assignment is untouched', (tester) async {
      await openSheet(
        tester,
        Deadline(
            title: 'Lab 5',
            courseName: ai.name,
            courseId: ai.id,
            kind: DeadlineKind.assignment,
            end: DateTime.now().add(const Duration(days: 2)),
            moduleId: 9,
            moduleType: 'assign'),
      );
      expect(find.text('Watch'), findsNothing);
      expect(find.widgetWithText(FilledButton, 'Open in eClass'), findsOneWidget);
    });
  });

  group('the player screen', () {
    late FakeWebView web;
    late FakeSessions sessions;
    late AppData data;
    late FakeEclass eclass;

    setUp(() async {
      web = FakeWebView();
      WebViewPlatform.instance = web;
      sessions = FakeSessions();
      final (d, e, _, _, _) = await makeAppData();
      (data, eclass) = (d, e);
      await sessions.dio.interceptors.whereType<CookieManager>().first.cookieJar.saveFromResponse(
          vodViewerUrl(72100), [Cookie('MoodleSession', 'abc123')..path = '/']);
    });

    /// A course screen under the player, so Back has somewhere to go.
    Future<void> open(WidgetTester tester, {bool resume = true}) async {
      await tester.pumpWidget(MultiProvider(
        providers: [ChangeNotifierProvider.value(value: data), Provider<Sessions>.value(value: sessions)],
        child: MaterialApp(
          theme: InhaApp.light,
          home: Builder(
            builder: (context) => Scaffold(
              body: TextButton(
                onPressed: () => watchVod(context, moduleId: 72100, title: 'Video 7', resume: resume),
                child: const Text('watch'),
              ),
            ),
          ),
        ),
      ));
      await tester.tap(find.text('watch'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 400)); // the route's transition; the page's 15 s still runs
    }

    FakeWebController page() => web.controller!;

    /// Ends the test's timers: the page's 15 s and the close's waits.
    Future<void> finish(WidgetTester tester) async {
      await tester.pumpWidget(const SizedBox());
      await tester.pump(const Duration(seconds: 2));
    }

    Future<void> tick(WidgetTester tester, {int times = 1}) async {
      for (var i = 0; i < times; i++) {
        await tester.pump(const Duration(seconds: 3));
      }
    }

    NavigationRequest top(String url) => NavigationRequest(url: url, isMainFrame: true);

    /// The page has loaded, and the screen has looked at what it is.
    Future<void> pageLoaded(WidgetTester tester) async {
      web.navigation!.finished!('https://eclass.inha.ac.kr/mod/vod/viewer.php?id=72100');
      await tester.pump();
      await tester.pump();
    }

    testWidgets('checks the session, hands over its cookies, then loads viewer.php', (tester) async {
      await open(tester);
      expect(eclass.logins, 1);
      expect(web.cookies.log, ['clear', 'MoodleSession=abc123']);
      expect(page().loads, ['https://eclass.inha.ac.kr/mod/vod/viewer.php?id=72100']);
      expect(page().userAgent, 'Desktop agent');
      await finish(tester);
    });

    testWidgets('stays covered until the page has shown it is not the login page', (tester) async {
      await open(tester);
      expect(find.text('Opening the video in eClass.'), findsOneWidget);
      await pageLoaded(tester);
      expect(find.text('Opening the video in eClass.'), findsNothing);
      await finish(tester);
    });

    testWidgets('a slow page shows itself after 15 s', (tester) async {
      await open(tester);
      await tester.pump(const Duration(seconds: 16));
      expect(find.text('Opening the video in eClass.'), findsNothing);
      await finish(tester);
    });

    testWidgets('a refused login says so with Sign in, and loads nothing', (tester) async {
      eclass.loginError = LoginRequired(Service.eclass);
      await open(tester);
      expect(find.text('eClass sign-in needed.'), findsOneWidget);
      expect(find.widgetWithText(TextButton, 'Sign in'), findsOneWidget);
      expect(page().loads, isEmpty);
      await finish(tester);
    });

    testWidgets('a failed session check says so with Retry, which loads', (tester) async {
      eclass.loginError = Exception('no network');
      await open(tester);
      expect(find.text("Couldn't load from eClass."), findsOneWidget);
      eclass.loginError = null;
      await tester.tap(find.widgetWithText(TextButton, 'Retry'));
      await tester.pump();
      expect(page().loads, hasLength(1));
      await finish(tester);
    });

    testWidgets('eClass redirecting to its login page is stopped, with Sign in', (tester) async {
      await open(tester);
      final decision = web.navigation!.request!(top('https://eclass.inha.ac.kr/login/index.php'));
      await tester.pump();
      expect(await decision, NavigationDecision.prevent);
      expect(find.text('eClass sign-in needed.'), findsOneWidget);
      await finish(tester);
    });

    testWidgets('a login form on the page itself is never shown', (tester) async {
      await open(tester);
      page().loginPage = true;
      await pageLoaded(tester);
      expect(find.text('eClass sign-in needed.'), findsOneWidget);
      await tick(tester);
      expect(page().ran, isNot(contains(videoClockJs)));
      await finish(tester);
    });

    testWidgets('a link off eClass goes to the browser; eClass stays', (tester) async {
      await open(tester);
      expect(await web.navigation!.request!(top('https://eclass.inha.ac.kr/course/view.php?id=2622')),
          NavigationDecision.navigate);
      expect(await web.navigation!.request!(top('https://example.org/')), NavigationDecision.prevent);
      await finish(tester);
    });

    testWidgets('the main page failing says so, a subframe failing does not', (tester) async {
      await open(tester);
      web.navigation!.error!(const WebResourceError(errorCode: -2, description: 'x', isForMainFrame: false));
      await tester.pump();
      expect(find.text("Couldn't reach eClass. Check the connection."), findsNothing);
      web.navigation!.error!(const WebResourceError(errorCode: -2, description: 'x', isForMainFrame: true));
      await tester.pump();
      expect(find.text("Couldn't reach eClass. Check the connection."), findsOneWidget);
      await finish(tester);
    });

    testWidgets("eClass's alert shows in a line the student can dismiss, and doesn't wait", (tester) async {
      await open(tester);
      await page().alert!(const JavaScriptAlertDialogRequest(message: 'Tracking failed.', url: ''));
      await tester.pump();
      expect(find.text('eClass says: Tracking failed.'), findsOneWidget);
      await tester.tap(find.widgetWithText(TextButton, 'Dismiss'));
      await tester.pump();
      expect(find.textContaining('eClass says'), findsNothing);
      await finish(tester);
    });

    testWidgets("eClass's confirm asks the student, in its words", (tester) async {
      await open(tester);
      await pageLoaded(tester);
      final answer = page().confirm!(const JavaScriptConfirmDialogRequest(message: 'Continue where you left?', url: ''));
      await tester.pumpAndSettle();
      expect(find.text('Continue where you left?'), findsOneWidget);
      await tester.tap(find.widgetWithText(TextButton, 'OK'));
      await tester.pumpAndSettle();
      expect(await answer, isTrue);
      await finish(tester);
    });

    testWidgets('keeps the place every few seconds, and tolerates no video', (tester) async {
      await open(tester);
      await pageLoaded(tester);
      await tick(tester); // no video element yet
      expect(data.prefs.vodPosition(72100), isNull);
      page().throwOnClock = true;
      await tick(tester);
      expect(tester.takeException(), isNull);
      page().throwOnClock = false;
      page().clock = '"1390.4|2700|4|1"';
      await tick(tester);
      expect(data.prefs.vodPosition(72100), 1390);
      await finish(tester);
    });

    testWidgets('goes back to the saved place when the player starts near zero', (tester) async {
      data.prefs.setVodPosition(72100, 1390);
      await open(tester);
      await pageLoaded(tester);
      page().clock = '"0|2700|4|0"';
      await tick(tester, times: 2);
      expect(page().ran, contains(seekVideoJs(1390)));
      await finish(tester);
    });

    testWidgets('watching again does not jump to the old place', (tester) async {
      data.prefs.setVodPosition(72100, 1390);
      await open(tester, resume: false);
      await pageLoaded(tester);
      page().clock = '"0|2700|4|0"';
      await tick(tester, times: 2);
      expect(page().ran, isNot(contains(seekVideoJs(1390))));
      await finish(tester);
    });

    testWidgets('Back pauses, waits for the tracking to go out, closes the page, then leaves', (tester) async {
      await open(tester);
      await pageLoaded(tester);
      page().clock = '"300|2700|4|1"';
      await tick(tester);
      await tester.tap(find.byTooltip('Back'));
      await tester.pump();
      expect(page().ran.last, pauseVideoJs);
      expect(find.text('watch'), findsNothing);
      expect(page().loads.last, isNot('about:blank')); // still in its grace

      await tester.pump(const Duration(milliseconds: 1300));
      expect(page().loads.last, 'about:blank');
      web.navigation!.finished!('about:blank');
      await tester.pump();
      await tester.pump();
      expect(web.cookies.log.last, 'clear');
      await tester.pumpAndSettle();
      expect(find.text('watch'), findsOneWidget);
      expect(data.prefs.vodPosition(72100), 300);
      await finish(tester);
    });

    testWidgets('Back with a paused video has nothing to wait for', (tester) async {
      await open(tester);
      page().clock = '"300|2700|4|0"';
      await tester.tap(find.byTooltip('Back'));
      await tester.pump();
      expect(page().loads.last, 'about:blank');
      web.navigation!.finished!('about:blank');
      await tester.pumpAndSettle();
      expect(find.text('watch'), findsOneWidget);
      await finish(tester);
    });

    testWidgets('going to the background pauses and saves; a glance at the shade does not', (tester) async {
      await open(tester);
      await pageLoaded(tester);
      page().clock = '"300|2700|4|1"';
      await tick(tester);
      page().ran.clear();
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.inactive);
      await tester.pump();
      expect(page().ran, isNot(contains(pauseVideoJs)));
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.paused);
      await tester.pump();
      expect(page().ran, contains(pauseVideoJs));
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
      await finish(tester);
    });

    testWidgets('the app bar names the video and offers the browser', (tester) async {
      await open(tester);
      expect(find.text('Video 7'), findsOneWidget);
      expect(find.byTooltip('Open in eClass'), findsOneWidget);
      await finish(tester);
    });
  });

  testWidgets('returning from the player brings the course up to date', (tester) async {
    final (data, eclass, _, _, _) = await makeAppData();
    eclass.courseList = const [ai];
    eclass.attendanceById = {
      ai.id: CourseAttendance(course: ai, vods: [video(percent: 40)])
    };
    await tester.runAsync(data.refreshEclass);
    await pumpScreen(
      tester,
      data,
      Builder(
        builder: (context) => Scaffold(
          body: TextButton(
            onPressed: () => watchVod(context,
                moduleId: 72100,
                title: 'Video 7',
                courseId: ai.id,
                screen: (ctx) => TextButton(onPressed: () => Navigator.of(ctx).pop(), child: const Text('back'))),
            child: const Text('watch'),
          ),
        ),
      ),
    );
    await tester.tap(find.text('watch'));
    await tester.pumpAndSettle();
    eclass.attendanceById = {
      ai.id: CourseAttendance(course: ai, vods: [video(percent: 62)])
    };
    await tester.tap(find.text('back'));
    await tester.pumpAndSettle();
    await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 20)));
    expect(data.attendance.data!.value.single.vods.single.percent, 62);
  });
}
