/// Periodic background refresh with WorkManager: fetch, then notify.
///
/// Every ~3 hours (with a network connection) Android wakes the app's
/// [callbackDispatcher] in a fresh background isolate. It runs the refresher
/// the app registered with [setBackgroundRefresher], feeds the data to the
/// rules and hands the result to the [Notifier].
///
/// A background isolate shares no memory with the UI isolate: no providers,
/// no service objects, no static fields set by the app. So the refresher
/// builds everything itself from persistent state (`AppServices.open()`:
/// the JSON cache, the credential store, the cookie jars), and it is
/// registered *inside* the background isolate: main.dart passes its own
/// entry point, `backgroundMain`, to [initBackground], and that calls
/// [setBackgroundRefresher] before [callbackDispatcher].
///
/// The UI isolate's SharedPreferences caches values in memory; the app
/// calls `prefs.reload()` (AppData.reloadFromCache) when it resumes, or it
/// would not see what the background task wrote.
library;

import 'dart:ui' show DartPluginRegistrant;

import 'package:flutter/foundation.dart' show debugPrint;
import 'package:flutter/widgets.dart' show WidgetsFlutterBinding;
import 'package:workmanager/workmanager.dart';

import '../models/models.dart';
import 'notifier.dart';

/// What a refresh produced: the newest data for each source (fresh if the
/// fetch worked, otherwise the cached copy), or null for a source with no
/// data at all. Null keeps that source's pending reminders as they are.
class RefreshResult {
  final List<Deadline>? deadlines;
  final List<CourseAttendance>? attendance;
  final List<Lesson>? lessons;

  /// Ask WorkManager to retry soon with backoff (e.g. a network failure).
  /// Notifications from the data above are still delivered first.
  final bool retry;

  const RefreshResult({this.deadlines, this.attendance, this.lessons, this.retry = false});
}

/// Fetches from the services, updates the cache, returns the data.
typedef BackgroundRefresher = Future<RefreshResult> Function();

BackgroundRefresher? _refresher;

/// Registers the refresher for the current isolate. Call it from the
/// background entry point before [callbackDispatcher] (see the top of this
/// file); calling it in the UI isolate alone is not enough.
void setBackgroundRefresher(BackgroundRefresher? refresher) => _refresher = refresher;

/// WorkManager task name and unique work name.
const refreshTaskName = 'inha.refresh';
const refreshUniqueName = 'inha.periodicRefresh';

/// How often to refresh. WorkManager's minimum is 15 minutes; Android may
/// run it later than this while the phone is idle.
const refreshInterval = Duration(hours: 3);

/// The default background entry point. Usable directly, but the app should
/// pass its own entry point that calls [setBackgroundRefresher] first.
@pragma('vm:entry-point')
void callbackDispatcher() {
  Workmanager().executeTask((task, inputData) async {
    if (task == refreshTaskName || task == refreshUniqueName) {
      return runRefreshTask();
    }
    return true; // unknown or retired task: succeed so it is not retried
  });
}

/// Initialises WorkManager with [dispatcher], a top-level function marked
/// `@pragma('vm:entry-point')`. Call once from main().
Future<void> initBackground([Function dispatcher = callbackDispatcher]) =>
    Workmanager().initialize(dispatcher);

/// Registers (or updates) the periodic refresh. Safe to call on every start.
Future<void> registerPeriodicRefresh() => Workmanager().registerPeriodicTask(
      refreshUniqueName,
      refreshTaskName,
      frequency: refreshInterval,
      constraints: Constraints(networkType: NetworkType.connected),
      existingWorkPolicy: ExistingPeriodicWorkPolicy.update,
      backoffPolicy: BackoffPolicy.exponential,
      backoffPolicyDelay: const Duration(minutes: 15),
    );

/// Stops the periodic refresh, e.g. when the user turns notifications off.
Future<void> cancelPeriodicRefresh() => Workmanager().cancelByUniqueName(refreshUniqueName);

/// The task body: refresh, then run the rules and deliver. Returns false to
/// have WorkManager retry. The parameters are for tests; by default it uses
/// the registered refresher, a new [Notifier] and the real clock.
Future<bool> runRefreshTask({
  BackgroundRefresher? refresher,
  Notifier? notifier,
  DateTime Function()? clock,
}) async {
  WidgetsFlutterBinding.ensureInitialized();
  DartPluginRegistrant.ensureInitialized();

  final refresh = refresher ?? _refresher;
  if (refresh == null) {
    debugPrint('notifications: no background refresher registered; '
        'see the top of lib/notifications/background.dart');
    return true; // retrying cannot help
  }

  final RefreshResult result;
  try {
    result = await refresh();
  } catch (e) {
    debugPrint('notifications: background refresh failed: $e');
    return false;
  }

  try {
    await (notifier ?? Notifier()).sync(
      deadlines: result.deadlines,
      attendance: result.attendance,
      lessons: result.lessons,
      now: clock?.call(),
    );
  } catch (e) {
    debugPrint('notifications: delivering failed: $e');
    return false;
  }
  return !result.retry;
}
