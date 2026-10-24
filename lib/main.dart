import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';

import 'app.dart';
import 'data/app_data.dart';
import 'data/services.dart';
import 'notifications/background.dart';
import 'notifications/home_widgets.dart';
import 'notifications/notifier.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  LicenseRegistry.addLicense(_fontLicences);
  final services = await AppServices.open();
  final data = services.data;
  await data.loadExams(rootBundle);

  final notifier = Notifier();
  // A tap while the app runs arrives here; one that started the app is the
  // launch payload. HomeShell opens the item. Home-screen widget taps carry
  // the same keys and take the same path.
  final taps = NotificationTaps();
  await notifier.init(onTap: (r) => taps.value = r.payload);
  taps.value ??= await notifier.launchPayload();
  taps.value ??= await widgetLaunchKey();
  widgetTaps().listen((key) => taps.value = key);
  data.onReminderDataChanged = () => _syncReminders(notifier, data);
  data.onWidgetDataChanged = updateHomeWidgets;
  await initBackground(backgroundMain);
  await registerPeriodicRefresh();

  runApp(MultiProvider(
    providers: [
      ChangeNotifierProvider.value(value: data),
      Provider.value(value: services.sessions),
      Provider.value(value: services.credentials),
      Provider.value(value: notifier),
      ChangeNotifierProvider.value(value: taps),
    ],
    child: const InhaApp(),
  ));

  // Plan reminders from the cache straight away, so they exist even if
  // today's refresh fails; the refresh then re-plans them with fresh data.
  await _syncReminders(notifier, data);
  data.refreshAll();
}

/// The bundled fonts' OFL texts (DESIGN.md 4), for the app's licence page.
Stream<LicenseEntry> _fontLicences() async* {
  for (final (font, file) in [('Fraunces', 'OFL-Fraunces.txt'), ('Public Sans', 'OFL-PublicSans.txt')]) {
    yield LicenseEntryWithLineBreaks([font], await rootBundle.loadString('assets/fonts/$file'));
  }
}

/// Sync passes run one after another: the timetable and eClass refreshes
/// finish independently, and each triggers a pass over the newest data.
Future<void> _syncChain = Future.value();

Future<void> _syncReminders(Notifier notifier, AppData data) =>
    _syncChain = _syncChain.then((_) => notifier.sync(
          deadlines: data.deadlines.data?.value,
          attendance: data.attendance.data?.value,
          lessons: data.lessons.data?.value,
        )).then<void>((_) {}, onError: (Object e) => debugPrint('reminders: sync failed: $e'));

/// WorkManager's entry point, in a background isolate of its own.
@pragma('vm:entry-point')
void backgroundMain() {
  setBackgroundRefresher(refreshInBackground);
  callbackDispatcher();
}

/// Refreshes the sources reminders depend on and hands back the newest data
/// for each (fresh, or cached when a fetch failed). runRefreshTask then plans
/// and delivers the notifications.
Future<RefreshResult> refreshInBackground() async {
  final data = (await AppServices.open()).data;
  await Future.wait([data.refreshTimetable(), data.refreshEclass()]);
  await updateHomeWidgets(); // awaited here: the isolate may end soon after
  return RefreshResult(
    deadlines: data.deadlines.data?.value,
    attendance: data.attendance.data?.value,
    lessons: data.lessons.data?.value,
    retry: [data.lessons.error, data.deadlines.error, data.attendance.error].any(isNetworkError),
  );
}
