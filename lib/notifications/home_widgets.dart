/// The home-screen widgets (docs/WIDGETS.md). They are drawn on the Android
/// side, straight from the cache in SharedPreferences, so the Dart side only
/// tells them when the cache changed and routes their taps.
library;

import 'package:flutter/foundation.dart' show debugPrint;
import 'package:home_widget/home_widget.dart';

/// The widgets' receivers in android/app/src/main/kotlin/.../widget/.
const homeWidgetReceivers = [
  'uz.inha.kamol1dn.inha_app.widget.UpNextWidgetReceiver',
  'uz.inha.kamol1dn.inha_app.widget.TodayWidgetReceiver',
  'uz.inha.kamol1dn.inha_app.widget.AttendanceWidgetReceiver',
];

/// Asks every placed widget to redraw from the cache. Works from the
/// background isolate too. A widget that isn't placed costs nothing.
Future<void> updateHomeWidgets() async {
  for (final receiver in homeWidgetReceivers) {
    try {
      await HomeWidget.updateWidget(qualifiedAndroidName: receiver);
    } catch (e) {
      debugPrint('widgets: update failed: $e');
    }
  }
}

/// The key a widget tap carries in `iut://open?key=...`: the same key a
/// notification tap has (lib/notifications/routes.dart), or `tab:<n>`.
String? widgetTapKey(Uri? uri) {
  if (uri == null || uri.scheme != 'iut' || uri.host != 'open') return null;
  final key = uri.queryParameters['key'];
  return key == null || key.isEmpty ? null : key;
}

/// The key of the widget tap that started the app, if one did.
Future<String?> widgetLaunchKey() async {
  try {
    return widgetTapKey(await HomeWidget.initiallyLaunchedFromHomeWidget());
  } catch (e) {
    debugPrint('widgets: launch check failed: $e');
    return null;
  }
}

/// Keys of widget taps while the app runs.
Stream<String> widgetTaps() => HomeWidget.widgetClicked.map(widgetTapKey).where((k) => k != null).cast<String>();
