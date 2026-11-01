import 'dart:async';
import 'dart:io' show Cookie;

import 'package:dio/dio.dart';
import 'package:dio_cookie_manager/dio_cookie_manager.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';
import 'package:webview_flutter/webview_flutter.dart';
import 'package:webview_flutter_android/webview_flutter_android.dart'
    show AndroidWebViewController, AndroidWebViewCookieManager;

import '../core/session.dart';
import '../data/app_data.dart';
import '../models/models.dart';
import '../services/eclass/eclass_links.dart';
import '../ui/theme/status_colors.dart';
import 'common.dart';
import 'settings_screen.dart';

/// eClass's own player page for a VOD. Playing it with the student's session
/// reports progress exactly as the website does (docs/ENDPOINTS.md): the app
/// never posts tracking itself.
Uri vodViewerUrl(int moduleId) => eclassBase.replace(path: '/mod/vod/viewer.php', query: 'id=$moduleId');

/// What a VOD row or sheet can offer the student at a moment in time.
enum VodOffer {
  watch,
  watchAgain, // eClass counts it as fully watched
  browser, // the window is open, but eClass didn't say which module it is
  closed,
  notOpen,
}

VodOffer vodOffer({int? moduleId, DateTime? opens, DateTime? closes, bool done = false, required DateTime now}) {
  if (closes != null && now.isAfter(closes)) return VodOffer.closed;
  if (opens != null && now.isBefore(opens)) return VodOffer.notOpen;
  if (moduleId == null) return VodOffer.browser;
  return done ? VodOffer.watchAgain : VodOffer.watch;
}

/// The cookies [dio]'s jar would send to [url]: the app's eClass session.
Future<List<Cookie>> dioCookies(Dio dio, Uri url) async {
  for (final i in dio.interceptors) {
    if (i is CookieManager) return i.cookieJar.loadForRequest(url);
  }
  return const [];
}

/// The same cookies for the WebView. Android's cookie manager takes a URL where
/// the plugin says domain, and binds the cookie to that host and scheme, so the
/// jar's own domain attribute isn't what matters here.
List<WebViewCookie> webViewCookies(Iterable<Cookie> jar, Uri url) => [
      for (final c in jar)
        WebViewCookie(
          name: c.name,
          value: c.value,
          domain: '${url.scheme}://${url.host}',
          path: c.path == null || c.path!.isEmpty ? '/' : c.path!,
        ),
    ];

enum VodNavigation { stay, signIn, browser, block }

/// What to do with a navigation the page starts. Subframes and media are the
/// video's own hosts, whatever they are, and never leave the page; a top-level
/// link stays only on eClass. The login form is never shown, and eClass's logout
/// link would end the app's session too.
VodNavigation vodNavigation(Uri? to, {required bool mainFrame}) {
  if (!mainFrame) return VodNavigation.stay;
  if (to == null) return VodNavigation.block;
  if (to.scheme == 'about') return VodNavigation.stay;
  final web = to.scheme == 'https' || to.scheme == 'http';
  if (web && to.host == eclassBase.host) {
    if (to.path == '/login/logout.php') return VodNavigation.block;
    return to.path.startsWith('/login/') ? VodNavigation.signIn : VodNavigation.stay;
  }
  return web || to.scheme == 'mailto' ? VodNavigation.browser : VodNavigation.block;
}

// video.js moves the page's id="my-video" to its wrapper and calls the element
// inside my-video_html5_api, so these look for the element itself.
const _video = "document.querySelector('video.vjs-tech')||document.querySelector('video')";
const _clockOf = "[v.currentTime,v.duration,v.readyState,v.paused?0:1].join('|')";

/// Reads the video's clock for [parseVideoClock]; null with no video on the page.
const videoClockJs = '(function(){var v=$_video;return v?$_clockOf:null;})()';

/// The same, and pauses it. The video's pause event is what makes eClass's own
/// script post the tracking it would otherwise send at its next interval.
const pauseVideoJs = '(function(){var v=$_video;if(!v)return null;var c=$_clockOf;v.pause();return c;})()';

String seekVideoJs(int seconds) => '(function(){var v=$_video;if(v)v.currentTime=$seconds;})()';

/// True on the login page, by the same signs as [isLoginPage].
const loginPageJs = "!!(document.body&&document.body.id==='page-login-index'"
    "||document.querySelector('form[action*=\"/login/index.php\"] input[name=\"password\"]'))";

/// One reading of the video element.
class VideoClock {
  final double position; // seconds
  final double? duration; // null until the video has said
  final bool hasMetadata;
  final bool playing;
  const VideoClock({required this.position, this.duration, this.hasMetadata = true, this.playing = false});
}

/// [videoClockJs]'s answer: "12.5|600|4|1" as it comes back, in JSON quotes on
/// Android. Anything else is null: no video, no page, or a result that isn't one.
VideoClock? parseVideoClock(Object? raw) {
  if (raw is! String) return null;
  final parts = raw.replaceAll('"', '').split('|');
  if (parts.length != 4) return null;
  final position = double.tryParse(parts[0]);
  if (position == null || !position.isFinite || position < 0) return null;
  final duration = double.tryParse(parts[1]);
  return VideoClock(
    position: position,
    duration: duration != null && duration.isFinite && duration > 0 ? duration : null,
    hasMetadata: (int.tryParse(parts[2]) ?? 0) >= 1,
    playing: parts[3] == '1',
  );
}

typedef VodPlaceStep = ({int? seekTo, int? keep, bool clear});

/// The student's place in one video on this phone, decided a reading at a time.
/// eClass knows the place too and its player may go there by itself, so ours
/// only steps in when the player stays near the start. Until that is settled
/// nothing is saved, so a player sitting at 0 can't wipe the saved place.
class VodPlace {
  static const nearStart = 15; // seconds still counted as "started from the top"
  static const worthSeeking = 30; // a smaller jump isn't worth it
  static const keepFrom = 10; // the first seconds aren't a place to come back to
  static const finishedWithin = 30; // this close to the end there is nothing to continue

  static const VodPlaceStep _nothing = (seekTo: null, keep: null, clear: false);

  final int? saved;
  var _looks = 0;
  var _settled = false;
  VodPlace({this.saved});

  /// One periodic reading: where to seek, if anywhere, and what to save.
  VodPlaceStep tick(VideoClock? clock) {
    if (clock == null || !clock.hasMetadata) return _nothing;
    if (!_settled) {
      // A reading for the player's own jump to land.
      if (saved != null && ++_looks < 2) return _nothing;
      _settled = true;
      if (saved case final s?
          when clock.position < nearStart &&
              s - clock.position >= worthSeeking &&
              (clock.duration == null || s < clock.duration! - finishedWithin)) {
        return (seekTo: s, keep: null, clear: false);
      }
    }
    return note(clock);
  }

  /// What to save from a reading, with no seek: for leaving, or going to the
  /// background.
  VodPlaceStep note(VideoClock? clock) {
    if (!_settled || clock == null || !clock.hasMetadata) return _nothing;
    if (clock.duration case final d? when clock.position >= d - finishedWithin) {
      return (seekTo: null, keep: null, clear: true);
    }
    if (clock.position >= keepFrom) return (seekTo: null, keep: clock.position.floor(), clear: false);
    return _nothing;
  }
}

/// Plays a VOD, then brings that course's row up to date. [screen] stands in for
/// the player in tests, where a WebView can't run.
Future<void> watchVod(
  BuildContext context, {
  required int moduleId,
  required String title,
  int? courseId,
  bool resume = true,
  @visibleForTesting WidgetBuilder? screen,
}) async {
  final data = context.read<AppData>();
  await Navigator.of(context).push(MaterialPageRoute<void>(
    builder: screen ?? (_) => VodPlayerScreen(moduleId: moduleId, title: title, resume: resume),
  ));
  await data.refreshCourseAttendance(courseId);
}

/// eClass's player page in a WebView, on the app's eClass session (DESIGN.md 8,
/// VOD player). The page does the tracking; this screen gets the session in,
/// keeps the student on eClass, and lets the page report before it goes away.
class VodPlayerScreen extends StatefulWidget {
  final int moduleId;
  final String title;

  /// Whether to go back to the saved place. Off for watching a finished video again.
  final bool resume;
  const VodPlayerScreen({super.key, required this.moduleId, required this.title, this.resume = true});

  @override
  State<VodPlayerScreen> createState() => _VodPlayerScreenState();
}

class _VodPlayerScreenState extends State<VodPlayerScreen> with WidgetsBindingObserver {
  /// How long a pause gets for its tracking request to go out.
  static const _trackingGrace = Duration(milliseconds: 1200);
  static const _tickEvery = Duration(seconds: 3);

  /// A page slower than this shows itself as it is, rather than stay covered
  /// (DESIGN.md 8, Loading).
  static const _revealAfter = Duration(seconds: 15);

  final _controller = WebViewController();
  final _cookies = WebViewCookieManager();
  late final AppData _data;
  late final Sessions _sessions;
  late final VodPlace _place;
  Future<void>? _setup;
  Timer? _ticker;
  Timer? _revealTimer;

  var _covered = true; // nothing the student should see yet
  ({String text, String action, VoidCallback run})? _problem;
  String? _notice; // what eClass said with alert()
  var _leaving = false;
  var _closed = false;
  Completer<void>? _blank;
  Color? _background;

  // The player's fullscreen, drawn over the WebView, and how to tell it that it ended.
  Widget? _full;
  void Function()? _fullHidden;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _data = context.read<AppData>();
    _sessions = context.read<Sessions>();
    _place = VodPlace(saved: widget.resume ? _data.prefs.vodPosition(widget.moduleId) : null);
    scheduleMicrotask(_open);
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final paper = Theme.of(context).colorScheme.surface;
    if (paper != _background) {
      _background = paper;
      unawaited(_controller.setBackgroundColor(paper).catchError((Object _) {}));
    }
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _ticker?.cancel();
    _revealTimer?.cancel();
    if (_full != null) _restoreSystemUi();
    if (!_closed) unawaited(_closePage());
    super.dispose();
  }

  /// Android's WebView keeps playing when the app goes away, sound and all: the
  /// plugin never calls WebView.onPause. So this pauses it, and playing on is the
  /// student's own tap. The screen staying on needs nothing: a playing video
  /// holds it on by itself.
  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.paused || state == AppLifecycleState.hidden) unawaited(_pauseAndKeep());
  }

  Future<void> _setUp() async {
    final c = _controller;
    await c.setJavaScriptMode(JavaScriptMode.unrestricted);
    // The player page was read with this desktop agent, the one the session
    // logged in with. Coursemos serves mobile agents a different theme.
    final agent = _sessions.client(Service.eclass).options.headers['User-Agent'];
    if (agent is String) await c.setUserAgent(agent);
    await c.setNavigationDelegate(NavigationDelegate(
      onNavigationRequest: _onNavigation,
      onPageFinished: _onPageFinished,
      onWebResourceError: _onWebError,
    ));
    await c.setOnJavaScriptAlertDialog((r) async {
      // Answered at once, so the page and the video don't wait on it.
      if (mounted && r.message.trim().isNotEmpty) setState(() => _notice = r.message.trim());
    });
    await c.setOnJavaScriptConfirmDialog(_onConfirm);
    final platform = c.platform;
    if (platform is AndroidWebViewController) {
      await platform.setMediaPlaybackRequiresUserGesture(false);
      await platform.setCustomWidgetCallbacks(onShowCustomWidget: _enterFullscreen, onHideCustomWidget: _exitFullscreen);
      // As a browser would: the video's hosts may set their own.
      final jar = _cookies.platform;
      if (jar is AndroidWebViewCookieManager) await jar.setAcceptThirdPartyCookies(platform, true);
    }
  }

  /// Checks the session, hands it to the WebView and loads the player.
  Future<void> _open() async {
    if (!mounted) return;
    setState(() {
      _problem = null;
      _notice = null;
      _covered = true;
    });
    _revealTimer?.cancel();
    final url = vodViewerUrl(widget.moduleId);
    try {
      await (_setup ??= _setUp());
      await _data.ensureEclassSession();
      final dio = _sessions.client(Service.eclass);
      await _cookies.clearCookies();
      for (final cookie in webViewCookies(await dioCookies(dio, url), url)) {
        await _cookies.setCookie(cookie);
      }
      if (!mounted) return;
      _revealTimer = Timer(_revealAfter, _reveal);
      await _controller.loadRequest(url);
    } catch (e) {
      if (mounted) _fail(e);
    }
  }

  void _fail(Object e) {
    _revealTimer?.cancel();
    if (e is LoginRequired) return _needSignIn();
    setState(() => _problem = (text: describeError(e, 'eClass'), action: 'Retry', run: _open));
  }

  void _needSignIn() {
    _revealTimer?.cancel();
    setState(() => _problem = (text: 'eClass sign-in needed.', action: 'Sign in', run: _signIn));
  }

  /// Settings, where logins are typed, then the player again with the new session.
  Future<void> _signIn() async {
    await Navigator.of(context).push(MaterialPageRoute<void>(builder: (_) => const SettingsScreen()));
    await _open();
  }

  void _reveal() {
    if (mounted && _covered) setState(() => _covered = false);
  }

  NavigationDecision _onNavigation(NavigationRequest r) {
    final to = Uri.tryParse(r.url);
    switch (vodNavigation(to, mainFrame: r.isMainFrame)) {
      case VodNavigation.stay:
        return NavigationDecision.navigate;
      case VodNavigation.signIn:
        if (mounted) _needSignIn();
      case VodNavigation.browser:
        if (mounted) unawaited(openUrl(context, to!));
      case VodNavigation.block:
        break;
    }
    return NavigationDecision.prevent;
  }

  Future<void> _onPageFinished(String url) async {
    if (url == 'about:blank') {
      if (_blank case final b? when !b.isCompleted) b.complete();
      return;
    }
    if (!mounted || _leaving || _problem != null) return;
    var login = false;
    try {
      login = await _controller.runJavaScriptReturningResult(loginPageJs) == true;
    } catch (_) {
      // Can't tell: the page is what it is.
    }
    if (!mounted || _leaving) return;
    if (login) return _needSignIn();
    _revealTimer?.cancel();
    _reveal();
    _ticker ??= Timer.periodic(_tickEvery, (_) => _tick());
  }

  void _onWebError(WebResourceError e) {
    if (e.isForMainFrame != true || e.url == 'about:blank' || !mounted || _leaving) return;
    _revealTimer?.cancel();
    setState(() => _problem = (text: "Couldn't reach eClass. Check the connection.", action: 'Retry', run: _open));
  }

  /// The page's own question, in its words: answering false by default could
  /// turn down something like continuing from where the student was.
  Future<bool> _onConfirm(JavaScriptConfirmDialogRequest r) async {
    if (!mounted) return false;
    final answer = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        content: Text(r.message),
        actions: [
          TextButton(onPressed: () => Navigator.of(ctx).pop(false), child: const Text('Cancel')),
          TextButton(onPressed: () => Navigator.of(ctx).pop(true), child: const Text('OK')),
        ],
      ),
    );
    return answer ?? false;
  }

  Future<VideoClock?> _readClock(String js) async {
    try {
      return parseVideoClock(await _controller.runJavaScriptReturningResult(js).timeout(const Duration(seconds: 2)));
    } catch (_) {
      return null; // no video on this page, or none yet
    }
  }

  Future<void> _tick() async {
    final step = _place.tick(await _readClock(videoClockJs));
    if (_leaving || _closed) return;
    _keep(step);
    if (step.seekTo case final at?) {
      unawaited(_controller.runJavaScript(seekVideoJs(at)).catchError((Object _) {}));
    }
  }

  void _keep(VodPlaceStep step) {
    if (step.clear) {
      _data.prefs.setVodPosition(widget.moduleId, null);
    } else if (step.keep case final at?) {
      _data.prefs.setVodPosition(widget.moduleId, at);
    }
  }

  /// Pauses and saves the place. True if the video was playing, so that eClass's
  /// script has a request to send.
  Future<bool> _pauseAndKeep() async {
    final clock = await _readClock(pauseVideoJs);
    _keep(_place.note(clock));
    return clock?.playing ?? false;
  }

  void _enterFullscreen(Widget view, void Function() hidden) {
    if (!mounted) return hidden();
    setState(() {
      _full = view;
      _fullHidden = hidden;
    });
    SystemChrome.setEnabledSystemUIMode(SystemUiMode.immersiveSticky);
    SystemChrome.setPreferredOrientations(const [DeviceOrientation.landscapeLeft, DeviceOrientation.landscapeRight]);
  }

  void _exitFullscreen() {
    if (_full == null) return;
    _restoreSystemUi();
    if (mounted) {
      setState(() {
        _full = null;
        _fullHidden = null;
      });
    }
  }

  static void _restoreSystemUi() {
    SystemChrome.setEnabledSystemUIMode(SystemUiMode.manual, overlays: SystemUiOverlay.values);
    SystemChrome.setPreferredOrientations(const []);
  }

  void _onBack() {
    if (_full == null) {
      unawaited(_leave());
      return;
    }
    final hidden = _fullHidden;
    _exitFullscreen();
    hidden?.call();
  }

  /// Back: pause, give eClass's script time to report it, close the page, pop.
  Future<void> _leave() async {
    if (_leaving) return;
    setState(() => _leaving = true);
    _ticker?.cancel();
    _revealTimer?.cancel();
    if (await _pauseAndKeep()) await Future<void>.delayed(_trackingGrace);
    await _closePage();
    if (mounted) Navigator.of(context).pop();
  }

  /// The WebView lives until it is garbage-collected, with the page's 60-second
  /// timer still going, so the page is closed first. The session goes last, once
  /// anything the page sends as it unloads has gone with it, and isn't left in the
  /// WebView for after a sign-out.
  Future<void> _closePage() async {
    _closed = true;
    final blank = _blank = Completer<void>();
    try {
      await _controller.loadRequest(Uri.parse('about:blank'));
      await blank.future.timeout(const Duration(milliseconds: 800));
    } catch (_) {
      // Closing is best effort: the next open starts clean regardless.
    }
    try {
      await _cookies.clearCookies();
    } catch (_) {
      // The same.
    }
  }

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context);
    final full = _full;
    final inset = full == null;
    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop) _onBack();
      },
      child: Scaffold(
        appBar: full != null
            ? null
            : AppBar(
                title: Text(widget.title, maxLines: 1, overflow: TextOverflow.ellipsis),
                actions: [
                  IconButton(
                    icon: const Icon(Icons.open_in_browser),
                    tooltip: 'Open in eClass',
                    onPressed: () => openUrl(context, eclassVodUrl(widget.moduleId)),
                  ),
                ],
              ),
        body: SafeArea(
          top: false,
          left: inset,
          right: inset,
          bottom: inset,
          child: Column(children: [
            if (full == null && (_leaving || (_covered && _problem == null))) const LinearProgressIndicator(minHeight: 2),
            if (full == null)
              if (_notice case final said?)
                Padding(
                  padding: const EdgeInsets.only(right: 8),
                  child: Row(children: [
                    Expanded(child: StatusLine(Status.warning, 'eClass says: $said', maxLines: 3)),
                    TextButton(onPressed: () => setState(() => _notice = null), child: const Text('Dismiss')),
                  ]),
                ),
            Expanded(
              key: const ValueKey('player'),
              child: Stack(fit: StackFit.expand, children: [
                WebViewWidget(controller: _controller),
                if (_problem != null || _covered)
                  ColoredBox(
                    color: t.colorScheme.surface,
                    child: _problem == null ? _opening(t) : _problemRows(_problem!),
                  ),
                ?full,
              ]),
            ),
          ]),
        ),
      ),
    );
  }

  Widget _opening(ThemeData t) => Padding(
        padding: const EdgeInsets.fromLTRB(gutter, 16, gutter, 8),
        child: Text('Opening the video in eClass.',
            style: t.textTheme.bodyLarge?.copyWith(color: t.colorScheme.onSurfaceVariant)),
      );

  Widget _problemRows(({String text, String action, VoidCallback run}) p) => ListView(children: [
        Padding(
          padding: const EdgeInsets.only(right: 8, top: 4, bottom: 4),
          child: Row(children: [
            Expanded(child: StatusLine(Status.danger, p.text)),
            TextButton(onPressed: p.run, child: Text(p.action)),
          ]),
        ),
        Padding(
          padding: const EdgeInsets.only(left: 8),
          child: Align(
            alignment: AlignmentDirectional.centerStart,
            child: TextButton(
              onPressed: () => openUrl(context, eclassVodUrl(widget.moduleId)),
              child: const Text('Open in eClass'),
            ),
          ),
        ),
      ]);
}
