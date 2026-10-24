# Home-screen widgets

Three widgets, drawn on the Android side from the app's cache. Code:
`android/app/src/main/kotlin/uz/inha/kamol1dn/inha_app/` (`campus/` reads the cache, `widget/` draws).

| Widget | Default size | Shows | A tap opens |
|---|---|---|---|
| **Up next** | 2 × 2 (resizes from 110 dp) | The class in progress or the next one: `Next · in 40 min`, the room, the course, and the next open eClass item with its due time. Tall, it adds the time, kind, teacher and the course's attendance warning; wide, class and item sit side by side | The class: Schedule on its day. The item: its deadline sheet. Elsewhere: Today |
| **Today** | 3 × 2 | Today's date, then a small rail: overdue items first, the class in progress (`Now · until 15:30`), the classes still to come and what is due today, in time order, then `Free for the rest of the day` or `No more classes today`; then, under `Tomorrow`, whatever falls due after midnight but within 24 h (so homework due at 00:00 shows the evening before), and `Next: Mon 26 Oct, 09:00 Multimedia Computing, B-305.` Scrolls | A class: Schedule on its day. An item: its deadline sheet. Elsewhere: Today |
| **Attendance** | 3 × 2 | Courses at or near their absence limit (tally, `6 of 8`, `2 left · next Mon 13:00`), then the unwatched VOD windows closing within 72 h, then the other courses in timetable order. Scrolls | A course: course detail. A VOD: its deadline sheet. Elsewhere: Courses |

They follow DESIGN.md: paper and ink in light and dark (the launcher picks with the system theme),
Fraunces for titles, rooms, course names and numbers, thin rules, status as icon plus words through
a `StatusLine`, the rail's nodes and line, and the tally drawn with the uprights and diagonal of
section 8. Nothing on them is invented: every value is from the cache. The one departure: the
secondary lines are in the system sans (Roboto), not Public Sans (see below).

## How they work

```
Flutter app / WorkManager refresh ──cache.write──▶ FlutterSharedPreferences.xml
        │                                                    │
        └─ HomeWidget.updateWidget ─▶ APPWIDGET_UPDATE ─▶ Glance widget ─ Campus.read ─┘
```

- **No Dart engine.** `campus/Campus.kt` reads `FlutterSharedPreferences.xml` directly: the
  `flutter.cache.<lessons|deadlines|attendance|grades>` entries (`{"at", "value"}`, the JSON of
  `lib/models/models.dart`), `flutter.absenceLimits.v1`, `flutter.account.<service>` and
  `flutter.exams.classFreeDays.v1` (the exam weeks' days, which have no classes; `docs/EXAMS.md`).
  Times in the cache are local without a zone; UTC ones (ending in `Z`) are converted.
- **The same rules as the app.** `campus/Rules.kt` and `Answers.kt` port `lib/data/urgency.dart`,
  `absence.dart` and the today part of `rail.dart`: class periods are never deadlines, done items
  (submitted, attempted, fully watched) are hidden, overdue work stays 24 h, VOD and deadline
  status thresholds, absence warning at max(1, 25 % of the limit) left, no limit ever guessed,
  courses named, never coded (an eClass `[202602-AIE3010-001]` suffix is cut). The wording
  (`Due in 5 h · not submitted`, `62% watched, 21 min left`, `2 left · next Mon 13:00`) is the
  app's, from `lib/features/rail_rows.dart` and `courses_screen.dart`.
- **Fonts.** A widget's layout is inflated by the launcher in a restricted context, where
  `TextView` ignores font resources (`android:fontFamily="@font/..."` silently falls back to
  Roboto), and Glance's own `Text` only knows system families. So the Fraunces roles (titles,
  the room, course names, times, counts) are drawn by `widget/Serif.kt` into a white mask bitmap
  with the Fraunces files the Flutter app already ships (`flutter_assets/assets/fonts`, nothing
  bundled twice), at the system font scale, with tabular figures, ellipsized to the width the
  row has, and shown as an `Image` tinted with the theme colour; its content description is the
  text, so TalkBack reads it. The Public Sans roles (item titles, secondary lines) stay real
  `TextView`s (`res/layout/w_text_*.xml`) in the system sans. Colours are resources with a
  `values-night` twin (`widget_colors.xml`).
- **Sizes.** `SizeMode.Exact`, so the layout (Up next: small, wide or tall) and each Fraunces
  line's width come from the widget's real size.
- **Refresh.** The app calls `updateHomeWidgets()` (`lib/notifications/home_widgets.dart`)
  after every cache write the widgets read (timetable, deadlines, attendance, grades), after
  signing out of a service and after an absence limit changes (`AppData.onWidgetDataChanged`).
  The ~3-hourly WorkManager refresh calls it too, awaited, before its isolate ends.
  `home_widget` sends APPWIDGET_UPDATE; each widget reads `currentState()` at its root, so even a
  running Glance session recomposes and reads the cache again.
- **The clock.** `WidgetTicker` sets one inexact, non-waking alarm (`AlarmManager.RTC`) for the
  next moment the widgets would say something different (`nextTick`): a class starts or ends, an
  item turns urgent, overdue or drops off, midnight, or a countdown step (every 5 min within an
  hour of a class and during it, 15 min within 3 h, else 30). It costs nothing while the screen
  is off; it fires on the next wake. The system's own `updatePeriodMillis` (30 min) is the
  backstop, and also brings the ticker back after a reboot.
- **Taps** reuse notification routing. A tap starts `MainActivity` with
  `iut://open?key=<key>`, where the key is the one a notification for that item carries
  (`reminderStem(d)|widget`, `absent:<courseId>|widget`, `class:<yyyy-MM-dd>|widget`) or
  `tab:<n>`. `main.dart` hands it to `NotificationTaps`, and HomeShell opens it like a tapped
  notification. `TapKeys.kt` and `reminderStem` in Dart are tested against the same string.

## When there is nothing to show

They never go blank. Without data they say what is missing and what to do:

| Situation | Says |
|---|---|
| No timetable cached yet | `Open the app to load the timetable.` |
| No eClass data, not signed in (or rejected) | `Sign in to eClass in the app to see deadlines.` (or `attendance`) |
| No eClass data but signed in | `Open the app to load deadlines from eClass.` |
| eClass rejected the saved login, data cached | The data, plus `eClass sign-in needed.` in danger |
| Timetable older than 24 h, eClass older than 3 h | The data, plus `Timetable as of Tue 18:04` / `eClass as of 08:12` in warning |
| No class in the next 7 days | `No classes in the next 7 days.` |
| Nothing open in eClass | `Nothing due in eClass.` (ok) |

## Testing

- **Unit tests** (JVM): `cd android && ./gradlew :app:testDebugUnitTest` runs
  `app/src/test/kotlin/.../campus/`: parsing, every rule above, the plans each widget draws,
  `nextTick`, the wording and the tap keys. The data is synthetic.
- **Dart:** `flutter test test/widget_keys_test.dart` (tap keys and routing).
- **On the emulator:** long-press the home screen, Widgets, IUT, and drag each one out; or
  `adb shell am broadcast -a android.appwidget.action.APPWIDGET_UPDATE -n uz.inha.kamol1dn.inha_app/.widget.TodayWidgetReceiver`
  to redraw one by hand. Dark mode: `adb shell cmd uimode night yes` (and `no`).

## Known limits

- **Countdowns are approximate.** Inexact alarms can be late by several minutes (Android batches
  them), so `in 40 min` may lag; the start time beside it is exact. Exact alarms would need
  `SCHEDULE_EXACT_ALARM`, which the app avoids (docs/NOTIFICATIONS.md).
- **The theme follows the system**, not the app's own Theme setting: the launcher resolves the
  colours with its configuration.
- **Below Android 12** the widget has square corners and the colours are fixed when it is drawn
  (they update on the next redraw after a theme change).
- **The picker preview** is a static paper card with the widget's name and description (in the
  system serif and sans; a preview can't load fonts either); it shows no data until the widget
  is placed.
- **Long names are cut to one line** in rows, as in the app; the course's own screen has the
  full name.
