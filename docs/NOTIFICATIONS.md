# Notifications

Code: `lib/notifications/`

| File | What it does |
|---|---|
| `rules.dart` | Pure logic. Data in, `List<PlannedNotification>` out. No plugins, no clock. |
| `notifier.dart` | Wraps flutter_local_notifications: channels, permission, show, schedule, cancel, sent-key store. |
| `background.dart` | WorkManager periodic refresh (~3 h, network required) that runs the rules and the notifier. |
| `routes.dart` | Pure. A tapped notification's key to what it opens. |

Tests: `flutter test test/notification_rules_test.dart test/notification_settings_test.dart`

## What gets sent

| Rule | When | Channel | On by default |
|---|---|---|---|
| Unwatched VOD (no progress data counts as unwatched) | 48 h and 6 h before the watch window closes | VOD windows (high) | Yes |
| Assignment, quiz, other eClass event | 24 h and 3 h before the deadline | Deadlines (high) | Yes |
| New absence (dated within the last 21 days) | Once, right away | Attendance (high) | Yes |
| Lesson today | 15 min before it starts | Classes (default) | No (DESIGN.md 11) |

Thresholds are constants at the top of `rules.dart`.

**Settings.** Each channel has a switch in the app's Settings, and so do quiet hours. They are stored in
shared_preferences (`notify.on.<channel>`, `notify.quietHours`) and read on every pass, so the background
isolate follows them. Turning a channel off cancels its scheduled reminders at once. Absences are still
recorded while Attendance is off, so turning it back on does not announce them.

**No first-run flood.** The first time a course's attendance is seen with any sessions in it (a first install,
a new semester), its absences are recorded as sent without a notification; only absences that appear after
that are announced. Seen course ids are kept under `notify.seenCourses.v1`. This also holds when the
notification permission has not been granted yet. (Milestone 1 posted one notification per absence of the
last 21 days on a first install.)

**Quiet hours, 23:00 to 07:30** (on by default). A reminder that falls inside them waits until 07:30 if the
item is still open at least an hour after that. Otherwise it goes out at 22:00 the evening before, and if
that has passed too (the item was found during the night), it is posted without sound or vibration. A new
absence found at night waits for 07:30.

**Tapping** a notification opens its item on top of the tab that owns it: a deadline or VOD opens its sheet
over Deadlines, an absence opens the course, a class reminder opens Schedule on that day. An item that is
gone opens its tab. While the app runs the tap arrives through `onDidReceiveNotificationResponse`; a tap
that starts the app is read from `getNotificationAppLaunchDetails`.

A reminder whose time has passed while the item is still open (phone off, item just appeared) goes out right away. Only the most urgent missed reminder is sent, and it is skipped if the next reminder for the same item is less than an hour away.

Every notification has a stable key (e.g. `vod:multimedia computing|week 8 ...|20261025T1859Z|6h`). The notification id is a 31-bit FNV-1a hash of that key. Sent keys are stored in shared_preferences under `notify.records.v1` and kept for 60 days. A key scheduled for later only counts as sent once its time has passed. Until then each pass schedules it again, which replaces the alarm, updates its text (e.g. "45% watched") and cancels it if it is no longer needed (VOD watched, deadline moved or removed).

## Installed versions (from pubspec.lock)

- flutter_local_notifications 22.3.2 (platform_interface 12.2.0)
- workmanager 0.10.10 (workmanager_android 0.10.9, platform_interface 0.10.5)
- timezone 0.11.2 (transitive, see pubspec change below)
- shared_preferences 2.5.6, intl 0.20.3
- Flutter 3.47.7: compileSdk 36, minSdk 24, targetSdk 36. AGP 9.1.0, Gradle 9.3.1.

## Changes to apply

### 1. `android/app/src/main/AndroidManifest.xml`

Add the permissions as children of `<manifest>`, before `<application>`:

```xml
    <!-- Network access for eClass/EduPage. The debug manifest has it, the main one does not,
         so release builds cannot fetch anything without this line. -->
    <uses-permission android:name="android.permission.INTERNET"/>
    <!-- Notifications. flutter_local_notifications also merges this in; declared here to be explicit. -->
    <uses-permission android:name="android.permission.POST_NOTIFICATIONS"/>
    <!-- Lets flutter_local_notifications re-create scheduled notifications after a reboot. -->
    <uses-permission android:name="android.permission.RECEIVE_BOOT_COMPLETED"/>
```

Add the receivers inside `<application>`, next to the `flutterEmbedding` meta-data:

```xml
        <!-- flutter_local_notifications 22.3.2: shows scheduled notifications... -->
        <receiver
            android:exported="false"
            android:name="com.dexterous.flutterlocalnotifications.ScheduledNotificationReceiver" />
        <!-- ...and re-creates them after a reboot or an app update. -->
        <receiver
            android:exported="false"
            android:name="com.dexterous.flutterlocalnotifications.ScheduledNotificationBootReceiver">
            <intent-filter>
                <action android:name="android.intent.action.BOOT_COMPLETED"/>
                <action android:name="android.intent.action.MY_PACKAGE_REPLACED"/>
                <action android:name="android.intent.action.QUICKBOOT_POWERON" />
                <action android:name="com.htc.intent.action.QUICKBOOT_POWERON"/>
            </intent-filter>
        </receiver>
```

Do **not** add:

- `SCHEDULE_EXACT_ALARM` / `USE_EXACT_ALARM`: scheduling is inexact (`AndroidScheduleMode.inexactAllowWhileIdle`).
- `ActionBroadcastReceiver`: the notifications have no action buttons.
- The plugin's `ForegroundService`, or `workmanager.enableDataSyncForegroundService`: not used.
- Anything for WorkManager. workmanager_android merges its own manifest (FOREGROUND_SERVICE, FOREGROUND_SERVICE_SHORT_SERVICE, SystemForegroundService), and androidx.work brings its boot receiver and network-state permission. The v2 embedding needs no custom Application class.

### 2. `android/app/build.gradle.kts`

flutter_local_notifications uses `java.time` for scheduling, and minSdk 24 does not have it, so it requires core library desugaring. Without it the build fails the AAR metadata check.

```kotlin
android {
    // ...
    compileOptions {
        isCoreLibraryDesugaringEnabled = true          // add this line
        sourceCompatibility = JavaVersion.VERSION_17
        targetCompatibility = JavaVersion.VERSION_17
    }
    // ...
}

// ... after the existing flutter { } block:
dependencies {
    coreLibraryDesugaring("com.android.tools:desugar_jdk_libs:2.1.4")
}
```

`2.1.4` is the version the plugin itself builds with. If AGP 9.1 asks for a newer one, use the version it names.

Not needed, despite the plugin README:

- `multiDexEnabled`: minSdk is 24, so multidex is built in.
- A `kotlinOptions` block: the template already sets `kotlin { compilerOptions { jvmTarget = JVM_17 } }`.
- A compileSdk change: `flutter.compileSdkVersion` is 36, and the plugin needs at least 35.
- An AGP change: 9.1.0 is above the plugin's minimum of 8.11.1.

### 3. `pubspec.yaml`

`notifier.dart` imports `package:timezone` (zonedSchedule takes a `TZDateTime`). It is currently only a transitive dependency, so the import carries `// ignore: depend_on_referenced_packages`. Add it as a direct dependency, then remove that ignore line:

```yaml
  timezone: ^0.11.2
```

Scheduling uses `tz.UTC` with absolute instants, so there is no need for `initializeTimeZones()` or flutter_timezone.

### 4. `lib/main.dart`

The background isolate shares no memory with the UI. The refresher must be registered inside it and must build its own services from persistent state. The full sketch is in the TODO at the top of `background.dart`. In short:

```dart
@pragma('vm:entry-point')
void backgroundMain() {
  setBackgroundRefresher(refreshEverything); // builds EclassClient/EdupageClient from
  callbackDispatcher();                      // Sessions + CredentialStore + JsonCache
}

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await Notifier().init(onTap: (r) { /* r.payload is the notification key */ });
  await initBackground(backgroundMain);
  await registerPeriodicRefresh();
  runApp(const App());
}
```

Also:

- Call `Notifier().requestPermission()` from the UI once, e.g. after onboarding. It needs an activity, and it shows the Android 13+ prompt.
- After each foreground refresh, and on app start from the cache, call `Notifier().sync(deadlines: ..., attendance: ..., lessons: ...)`. Pass `null` for a source with no data. This also covers days when the background task has no network.
- When the app resumes, call `prefs.reload()` before reading the JsonCache. Otherwise the UI isolate's SharedPreferences cache will not see what the background task wrote.
- On logout, call `Notifier().cancelAll()` and `cancelPeriodicRefresh()`.

### 5. Status bar icon

Done: `android/app/src/main/res/drawable/ic_stat_notify.xml` (the IUT wordmark, white on transparent) is the
`Notifier` default, so the background isolate uses it too, and `res/raw/keep.xml` keeps it (and the launcher
icon) from R8's resource shrinking, which can't see names used only from Dart.

## Known limits

- **Inexact timing.** Android may deliver an inexact alarm late: up to 1 hour on Android 12+, usually a few minutes. On Android 7 to 11 the delay can be up to 75% of the time until the alarm. Re-scheduling on every pass narrows this. For VOD and deadline reminders a short delay does not matter. For the 15-minute class reminder it can. If that becomes a problem, construct `Notifier(scheduleMode: AndroidScheduleMode.exactAllowWhileIdle)`, add `SCHEDULE_EXACT_ALARM`, and call `requestExactAlarmsPermission()` (the user grants it on Android 14+). Avoid `USE_EXACT_ALARM`: Play allows it only for alarm and calendar apps.
- **Background runs are best-effort.** WorkManager runs about every 3 h when there is a network, but Doze and OEM battery savers (Xiaomi, Huawei, some Samsung) can delay or block it (see dontkillmyapp.com). Class reminders are planned for today only, so the first class of the day depends on a pass after midnight or the app being opened.
- **Submitted work** (an assignment handed in, a quiz attempted) gets no reminders: each refresh reads the item's own eClass page and sets `Deadline.done`, and the pending reminders are cancelled. If that page fails to load, the last known state is kept; an item never checked counts as not submitted, which is the safe failure.
- **VOD matching is by course name and title** (case and whitespace ignored). If eClass's upcoming-events titles differ from the progress-page titles, a watched VOD looks unwatched and still gets reminders. That is the safe failure, but noisy. The eClass client should produce matching titles.
- **Absences older than 21 days are never announced,** even for a course seen before.
- **Grouping.** Android groups the app's notifications itself once several are showing; the app sets no group.
