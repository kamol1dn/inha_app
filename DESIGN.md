# Design guide

This guide covers every screen in `lib/`. The app is for one IUT student who opens it many times a day, often walking between classes,
to answer three questions: where do I need to be next, what is due, am I in attendance trouble. If a screen breaks a rule here, fix the
screen or change this file in the same commit.

The look is **Campus paper**: warm paper and ink, a serif for the words that answer the question, thin rules instead of boxes, and
absences drawn as tally marks. Today and Schedule are a **day rail**: one vertical timeline from now through the day's classes into the
next days. The student chose this mix from three directions in milestone 2 (canvas: B "Campus paper" with C's rail).

## 1. Principles

1. **Answer first.** The first thing on each screen answers its question: the next room and time until class on Today, the next item on
   Deadlines, the course closest to the absence limit on Courses. Nothing goes above it: no greeting, hero banner or summary tiles.
2. **Specific, not decorative.** Use real names, real times, and numbers with their denominator ("3 of 4"). If an element carries no
   information and offers no action, delete it.
3. **Neutral by default, colored by exception.** About 90% of a screen is ink on paper. Color is reserved for the accent's jobs and the
   four statuses.
4. **Never blank, never silent.** Show cached data first, show its age when that matters, and name every failure by service with a
   next step.
5. **Readable while walking.** The room is the largest text in the app, and the time until class sits right above it.

**Where the identity comes from.** Three things, and only these: the paper-and-ink palette, Fraunces for the words and numbers that
answer a screen's question, and the tally mark. Everything else stays plain: Public Sans, Material icons, M3 components with their
defaults. A screen gets its character from what it says and from those three, never from decoration added on top.

## 2. Slop patterns: don't / do

| Don't | Do instead |
|---|---|
| A greeting header ("Good morning" and a first name) or a big date hero | An app bar titled `Fri 23 Oct`, with the rail directly below it |
| Gradients anywhere: hero cards, buttons, text, borders | Flat paper. Color only for status and the accent |
| A purple/indigo palette, or `ColorScheme.fromSeed` | The explicit schemes in section 3 |
| Content in rounded cards, cards inside cards, one card per row | Rows on paper, separated by thin rules and section headers. No `Card` anywhere |
| Emoji in headings, labels, empty states or notifications | No emoji anywhere |
| An icon in a tinted circle before every heading or row | Icons only for status, navigation and actions. Headers have no icon (except Overdue's status icon) |
| Vanity or fake stats: "92% attendance" tiles, streaks, scores, progress rings | The real count with its denominator and limit: "3 of 4 absences used", and its tally |
| Vague, cheerful copy: "Oops! Something went wrong", "You're all caught up!" | What happened, which service, as of when, and what to do (section 10) |
| Glassmorphism, `BackdropFilter`, glows, shadows | Opaque paper at elevation 0 |
| Status dots, pulsing dots, or "New"/"Live" pills with no defined meaning | Only the four statuses, always as an icon plus words. A rail node's color never stands alone |
| A thick colored stripe down one side of a row | The rail's thin line, which is structure, not status |
| Pill shapes and 20–28 radii on everything | Radius by role (section 5) |
| Uppercase, letter-spaced eyebrow labels ("UPCOMING") | Sentence-case Fraunces headers |
| Staggered list entrances, bounce, confetti, shimmer | Default M3 transitions. Motion only to show that something changed |
| Illustrations or mascots in empty states | One sentence and at most one action |
| Every button filled | At most one `FilledButton` per screen. Row actions use `TextButton` |
| Paper texture, torn edges, handwriting fonts, drop caps | Paper is a color, not a picture |
| John Doe, Acme, or round invented numbers in mocks and tests | Real course names and realistic IUT rooms and times |

## 3. Color

Paper and ink, with the IUT deep blue as the one accent. The values are our own: no official IUT hex exists, so the blue is taken from
the deep blue of the emblem (hue about 212°, clear of indigo and violet).

- **The accent (`primary`) has five jobs:** the "Now"/"Next" label and the now marker on the rails, the selected tab, the one filled
  button on a screen, text buttons and links, and the `info` status. Headers, icons, rules and backgrounds are never blue.
- **Ink, not black.** Text is `onSurface` (ink) or `onSurfaceVariant` (muted). Rules, the rail line and the unused part of a tally are
  `outlineVariant`; they are decorative and never the only signal.
- **No `fromSeed`, no `dynamic_color`, and no `Colors.*` or hex literals in widgets.** Widgets read only `colorScheme` and
  `StatusColors`.
- **`surfaceTint` is transparent** and elevation is 0, so surfaces differ only by their `surfaceContainer*` step.
- **Dark mode is ink at night, designed, not inverted:** a warm near-black ground, paper-colored text, lighter status tones. Surfaces
  get lighter as they rise; nothing is pure black, and pure white appears only on the light theme's filled button.
- **Theme:** System by default; Settings offers System, Light and Dark.

```dart
// lib/ui/theme/app_colors.dart
const lightScheme = ColorScheme(brightness: Brightness.light,
  primary: Color(0xFF1D4E89), onPrimary: Color(0xFFFFFFFF), primaryContainer: Color(0xFFDAE3EF), onPrimaryContainer: Color(0xFF0F2E52),
  secondary: Color(0xFF5C584F), onSecondary: Color(0xFFFFFFFF), secondaryContainer: Color(0xFFE2DACA), onSecondaryContainer: Color(0xFF1C1B19),
  tertiary: Color(0xFF5C584F), onTertiary: Color(0xFFFFFFFF), // unused; mirrors secondary
  error: Color(0xFFA3321F), onError: Color(0xFFFFFFFF), errorContainer: Color(0xFFF6DDD5), onErrorContainer: Color(0xFF4F170D),
  surface: Color(0xFFF5F2EA), onSurface: Color(0xFF1C1B19), onSurfaceVariant: Color(0xFF5C584F),
  surfaceContainerLowest: Color(0xFFFBF9F4), surfaceContainerLow: Color(0xFFEFEBE1), surfaceContainer: Color(0xFFEAE5D9),
  surfaceContainerHigh: Color(0xFFE4DED0), surfaceContainerHighest: Color(0xFFDED7C8),
  surfaceDim: Color(0xFFDED7C8), surfaceBright: Color(0xFFFBF9F4), outline: Color(0xFF857E70), outlineVariant: Color(0xFFD8D1C2),
  inverseSurface: Color(0xFF2E2C28), onInverseSurface: Color(0xFFF2EEE4), inversePrimary: Color(0xFF9DBDE6),
  shadow: Color(0xFF000000), scrim: Color(0xFF000000), surfaceTint: Color(0x00000000));

const darkScheme = ColorScheme(brightness: Brightness.dark,
  primary: Color(0xFF9DBDE6), onPrimary: Color(0xFF0F2E52), primaryContainer: Color(0xFF1D3F66), onPrimaryContainer: Color(0xFFD9E3F0),
  secondary: Color(0xFFADA696), onSecondary: Color(0xFF2E2C28), secondaryContainer: Color(0xFF3A352C), onSecondaryContainer: Color(0xFFEDE7DA),
  tertiary: Color(0xFFADA696), onTertiary: Color(0xFF2E2C28),
  error: Color(0xFFF0A08C), onError: Color(0xFF4F170D), errorContainer: Color(0xFF4A1F16), onErrorContainer: Color(0xFFF8D3C8),
  surface: Color(0xFF1A1814), onSurface: Color(0xFFEDE7DA), onSurfaceVariant: Color(0xFFADA696),
  surfaceContainerLowest: Color(0xFF141210), surfaceContainerLow: Color(0xFF201E19), surfaceContainer: Color(0xFF25221D),
  surfaceContainerHigh: Color(0xFF2C2923), surfaceContainerHighest: Color(0xFF34302A),
  surfaceDim: Color(0xFF1A1814), surfaceBright: Color(0xFF2C2923), outline: Color(0xFF857E70), outlineVariant: Color(0xFF423D35),
  inverseSurface: Color(0xFFEDE7DA), onInverseSurface: Color(0xFF2E2C28), inversePrimary: Color(0xFF1D4E89),
  shadow: Color(0xFF000000), scrim: Color(0xFF000000), surfaceTint: Color(0x00000000));
```

**Where each surface is used:** `surface` is the paper of every screen, the app bar and the navigation bar. `surfaceBright` is a raised
sheet: bottom sheets and dialogs. `surfaceContainerHigh` is the offline row. `surfaceContainerHighest` is skeleton blocks only; no text
sits on it.

**Measured WCAG contrast** (light / dark):
- `onSurface` on `surface`: 15.4 / 14.4. `onSurfaceVariant` on `surface`: 6.3 / 7.3, and at least 5.3 / 6.0 on every surface text sits on.
- `primary` on `surface`: 7.5 / 9.2.
- `outline` (text field and chip borders): 3.6 / 4.4 on `surface`, at least 3.0 / 3.6 on any surface.
- `outlineVariant` is decorative only: rules, the rail line, the unused part of a tally, empty progress tracks.

```dart
// lib/ui/theme/status_colors.dart
typedef StatusTone = ({Color fg, Color container, Color onContainer});
enum Status { ok, warning, danger, info }

@immutable
class StatusColors extends ThemeExtension<StatusColors> {
  const StatusColors({required this.ok, required this.warning, required this.danger, required this.info});
  final StatusTone ok, warning, danger, info;
  static const light = StatusColors(
    ok:      (fg: Color(0xFF2F6B3A), container: Color(0xFFDDEBDC), onContainer: Color(0xFF173A1F)),
    warning: (fg: Color(0xFF8A5300), container: Color(0xFFF4E3C3), onContainer: Color(0xFF452A00)),
    danger:  (fg: Color(0xFFA3321F), container: Color(0xFFF6DDD5), onContainer: Color(0xFF4F170D)),
    info:    (fg: Color(0xFF1D4E89), container: Color(0xFFDAE3EF), onContainer: Color(0xFF0F2E52)));
  static const dark = StatusColors(
    ok:      (fg: Color(0xFF8FC79A), container: Color(0xFF1F3524), onContainer: Color(0xFFCBE8D0)),
    warning: (fg: Color(0xFFE3AE5B), container: Color(0xFF3D2C0E), onContainer: Color(0xFFF5DDB0)),
    danger:  (fg: Color(0xFFF0A08C), container: Color(0xFF4A1F16), onContainer: Color(0xFFF8D3C8)),
    info:    (fg: Color(0xFF9DBDE6), container: Color(0xFF1D3F66), onContainer: Color(0xFFD9E3F0)));
  StatusTone of(Status s) => switch (s) { Status.ok => ok, Status.warning => warning, Status.danger => danger, Status.info => info };
  @override StatusColors copyWith() => this;
  @override StatusColors lerp(StatusColors? other, double t) => t < 0.5 ? this : (other ?? this);
}
```

| Status | Icon (always shown) | Means | `fg` on `surface`, light / dark | `fg` on the offline row, light / dark |
|---|---|---|---|---|
| ok | `check_circle_outline` | Submitted, watched, within limits | 5.7 / 9.1 | 4.8 / 7.5 |
| warning | `warning_amber_rounded` | Act soon; data is stale | 5.7 / 8.8 | 4.7 / 7.2 |
| danger | `error_outline` | Due within hours, overdue, at or over the absence limit, sign-in broken | 6.2 / 8.5 | 5.2 / 7.0 |
| info | `info_outline` | Notable but nothing wrong ("No limit set") | 7.5 / 9.2 | 6.3 / 7.5 |

All `onContainer` pairs are at least 8.3:1. `ColorScheme.error` is the danger color.

- **Status is rendered by `StatusLine`:** a 16dp icon, a 6dp gap and `bodyMedium` text, both in `fg`. There are no status pills or
  tags; the `container` tones are for a tinted row, should one ever be needed.
- **Colored text alone is acceptable only when the words state the condition** ("in 2 h", "6 of 8", "Over limit"). A rail node, tally
  mark, bar or tint is never the only signal: the same row always says it in words.
- **Warning and danger have about the same lightness on purpose.** The icon shape and the wording tell them apart.
- **The offline row is the only tinted row** (`surfaceContainerHigh`). Never tint a row to show its status.

## 4. Typography

**Two bundled faces: Fraunces (serif) and Public Sans (sans).** Fraunces carries the answers: the room, app bar and section titles,
course names, and the numbers people scan (times on the rails, absence counts, grades). Public Sans carries everything else: item
titles, secondary lines, buttons, settings, mail.

- **Bundled, never fetched.** The fonts live in `assets/fonts/` with their OFL licence files. The app promises it only talks to IUT
  services, so there is no `google_fonts` and no runtime download.
- **Static instances.** `tool/make_fonts.py` cuts static TTFs from the upstream variable fonts (google/fonts, `ofl/fraunces` and
  `ofl/publicsans`): Fraunces at optical size 20 in Regular, SemiBold and Italic; "Fraunces Display" at optical size 72 in SemiBold for
  the room; Public Sans Regular, Medium and SemiBold. Fraunces keeps its defaults (SOFT 0, WONK 1).
- **Tabular figures.** Public Sans has `tnum`. Fraunces has no `tnum` feature and proportional digits, so `make_fonts.py` adds one:
  tabular copies of 0–9, centred on the widest digit's advance. `.tnum` therefore works the same in both faces.
- **Other scripts fall back to the system.** Neither face has Cyrillic, Hangul or Uzbek's `ʻ` (U+02BB) in Fraunces. Fraunces styles
  list `serif` as their fallback, so a Cyrillic course name continues in Noto Serif rather than Roboto; Public Sans falls back to the
  system sans (Roboto, Noto Sans CJK for Korean). Mixed lines are expected and acceptable.
- **The size cost** is about 0.5 MB in the APK (seven files), paid once.

These styles are the only ones allowed. Every style sets its family, size, line height, weight and letter spacing, so nothing depends
on the M3 defaults (which assume Roboto). `displayLarge`, `displaySmall` and `headlineLarge` are never used.

| Style | Face | Size / line (sp) | Weight | Used for |
|---|---|---|---|---|
| `displayMedium` | Fraunces Display | 60 / 64, tnum | 600 | Today's room, and nothing else. Scales down to fit one line |
| `headlineMedium` | Fraunces | 32 / 38, tnum | 600 | The absence count on course detail; the GPA |
| `headlineSmall` | Fraunces | 24 / 30 | 600 | App bar titles, dialog titles, the heading of a pushed detail or sheet |
| `titleLarge` | Fraunces Italic | 20 / 26 | 400 | The course name under Today's room |
| `titleMedium` | Fraunces | 19 / 24 | 600 | Section and day headers; a course name as a row's primary line; a grade letter |
| `titleSmall` | Public Sans | 16 / 22 | 600 | An item's primary line (a deadline title, an unread subject) |
| `bodyLarge` | Public Sans | 16 / 24 | 400 | Paragraphs, the mail body, settings rows, a read subject |
| `bodyMedium` | Public Sans | 14 / 20 | 400 | A row's secondary line in `onSurfaceVariant`; `StatusLine` |
| `bodySmall` | Public Sans | 12 / 16 | 400 | Metadata: "Updated 08:41", "as of Tue 18:04" |
| `labelLarge` | Public Sans | 15 / 20 | 600 | Buttons; the rail's "Next · in 40 min" in `primary` |
| `labelMedium` | Public Sans | 12 / 16 | 500 | Navigation labels, tags, the week strip's weekdays |
| `labelSmall` | Public Sans | 11 / 16 | 500 | The unread badge |
| `numeral` | Fraunces | 16 / 22, tnum | 400 | Start times on the rails and Deadlines; the count beside a tally |
| `numeralSmall` | Fraunces | 14 / 20, tnum | 400 | End times on the rails |

`numeral` and `numeralSmall` are getters on `TextTheme` in `lib/ui/theme/app_text.dart`, next to the theme.

- **`.tnum` on every number:** times, countdowns, counts, percentages and room numbers.
- **Sentence case everywhere.** No `toUpperCase()`. Letter spacing is 0 except the two largest Fraunces sizes, which are set slightly
  tight (−1 and −0.5).
- **Per row:** at most two faces, three sizes and two weights. No bold inside a sentence.
- **Even leading.** Every style uses `TextLeadingDistribution.even`, so the two faces sit on the same line in a row.
- **Text scaling up to `textScaler` 2.0.** Never set a fixed height on anything holding text; use minimum heights. The rail's time
  column grows with the text scale. Course names ellipsize to one line in rows and wrap on detail screens.

## 5. Spacing, rules, shape

**Spacing:** `4, 8, 12, 16, 20, 24, 32, 48` only.

| Where | Spacing |
|---|---|
| Gutter | 20 for text; 16 before the rail's time column |
| Section header | 16 above (after its rule) and 4 below |
| Between lines within a row | 2–4 |
| Icon to text | 16 in rows, 6 in `StatusLine` |
| After the last row | 24 |

**Rules instead of boxes.** There are no cards. Structure comes from thin rules (`Divider(height: 1, thickness: 1)` in `outlineVariant`):
- under the app bar, across the full width;
- above every section header except the first on a screen, inset by the 20dp gutter on both sides;
- between rows of a uniform list: Courses, Mail, Grades, attendance sessions, absence limits. Not between rail rows, which the rail
  line already joins;
- the navigation bar's top edge, which is a 1dp rule in `onSurface`: the one strong line in the app, like the bottom of a printed page.

**The rail** (Today and Schedule) is three columns:

| Column | Width | Holds |
|---|---|---|
| Time | 16 gutter + 48 (grows with text scale) | Start time in `numeral`, end time below it in `numeralSmall`, right-aligned |
| Node | 28 | A 2dp line in `outlineVariant` through the centre, and the row's node |
| Content | the rest, 20 to the right edge | The row's text |

| Node | Drawn as | For |
|---|---|---|
| Now | 10dp dot in `primary`; the row reads "Now" in `primary` with a 1dp `primary` line to the right edge | The current time |
| Class | 12dp ring, 2dp stroke in `onSurface` (`onSurfaceVariant` once past) | A class or an exam |
| Class in progress | 12dp dot in `primary` | The class or exam happening now |
| Due | 8dp dot in `onSurface`, or the status `fg` when warning or danger | A deadline or VOD window |
| none | the line only | Day headers, "Free for the rest of the day", breaks |

The line starts at the first node and ends at the last. The node sits on the centre of the row's first text line.

**Rows** keep a minimum height of 48 and are one tap target each; the only extra control allowed is a trailing `TextButton`.

| Row type | Minimum height | Used for |
|---|---|---|
| One-line | 48 | Rail day headers, settings rows, attendance sessions |
| Two-line | 56 | Rail and deadline rows, mail on Today |
| Three-line | 72 | Course rows, mail rows |

**Radius:**

| Element | Radius |
|---|---|
| Rows (full-bleed ripple), rules, the app and navigation bars | 0 |
| Skeleton blocks | 4 |
| Chips, buttons (override the M3 stadium shape), fields, snack bars | 8 |
| Top corners of sheets, and dialogs | 16 |

**Elevation** is 0 everywhere, including `AppBarTheme(scrolledUnderElevation: 0)`. Sheets and dialogs are `surfaceBright` paper over the
scrim, with no shadow.

## 6. Navigation

A `NavigationBar` with 5 destinations, on `surface`, under the 1dp `onSurface` rule. No indicator pill: the selected tab is `primary`,
its icon filled and its label 600; the others are `onSurfaceVariant`, outlined, 500. Labels are always shown.

| Tab | Icon | Answers | Notes |
|---|---|---|---|
| Today | `today` | Where next, what's urgent | The start screen. App bar action: Settings (gear) |
| Schedule | `calendar_view_day` | The day's classes and rooms | One day at a time on a rail, using the week strip or a swipe |
| Deadlines | `assignment` | Everything due, eClass VOD windows included | Grouped by day |
| Courses | `school` | Attendance, VOD progress and grades by course | App bar action "Grades" opens INS grades |
| Mail | `mail` | What the university wrote | Last. The inbox unread count is a `Badge` on the icon. The menu button (where Back would be) opens the folders; New writes a message |

- **The unread badge is ink** (`inverseSurface` with `onInverseSurface` text): a count, not an alarm.
- **Settings is a pushed screen, not a tab,** reached only from the gear on Today (tooltip "Settings"). Today's mail rows open the
  message on top of Today; its "N more" switches to the Mail tab.
- **Each tab keeps its own scroll position** (`IndexedStack`).
- **Back** from another tab goes to Today; back on Today exits.
- **Tapping a notification** opens the item's detail on top of the tab that owns it.

## 7. Today screen

```
Fri 23 Oct                                              [gear]
──────────────────────────────────────────────────────────────  rule
[offline row, only when offline]
 13:20  ●  Now ───────────────────────────────────────────────   primary
 14:00  ○  Next · in 40 min                                      labelLarge, primary
 15:30  │  B202                                                  displayMedium
        │  Embedded Software & Design                            titleLarge (italic)
        │  Lecture · J. Hong                                     bodyMedium, muted
 15:30  │  Free for the rest of the day                          bodyMedium, muted
        │
        │  Sun 25 Oct                                            titleMedium
 23:55  •  Assignment 1                                          titleSmall
        │  Not submitted · Multimedia Computing                  bodyMedium, muted
 23:59  •  Video 7 closes                                        status dot
        │  [!] 62% watched · in 2 d                              StatusLine
        │  Distinguished Lecture in Social Science and Art
        │  Mon 26 Oct
 13:00  ○  Artificial Intelligence                               titleMedium
 14:30     B101 Conf · Lecture
           [!] 6 of 8 absences used · 2 left                     StatusLine on this course's next class
──────────────────────────────────────────────────────────────
Attendance                                                       titleMedium
Artificial Intelligence                           |||| / | : :   tally, status fg + faint
[!] 2 left · next Mon 13:00                               6 of 8
[ok] The other 3 courses are within their limit.
──────────────────────────────────────────────────────────────
8 unread
IMPORTANT NOTICE                                         10 Oct
Fall 2026 semester drop-retake period                    14 Sep
6 more                                                           TextButton
Updated 13:18                                                    bodySmall, muted
```

1. **App bar:** titled with the date in `headlineSmall`. It never collapses and has no subtitle.
2. **The rail** runs top to bottom in time order:
   - **Overdue** items (not done, due in the last 24 h) come first, under a danger "Overdue" header, because on a timeline the past is
     above now.
   - **Now.** While a class is in progress there is no separate Now row: that class is the hero, labelled
     `Now · until 15:30 · 40 min left`, with a `primary` dot. Otherwise the Now row (current time, `primary` dot, "Now") comes first.
   - **The hero** is the class in progress or the next class today: label (`Next · in 40 min`), the room in `displayMedium`, the course
     in `titleLarge`, then `Lecture · J. Hong`. With no room in EduPage it reads "Room not set". The countdown ticks on the minute.
     Tapping it opens Schedule on its day; any other class opens its course.
   - **Later classes today** are ordinary class rows: the course in `titleMedium`, then `B202 · Lecture`.
   - **Exams** (`docs/EXAMS.md`) sit on the rail like classes, for the next 72 h: the course, then
     `Midterm · B209 or B210` (the rooms it uses until the student sets their own). An exam in progress, or the next
     thing today, is the hero: the room the student set, or `Room not set` in the room's place, then the course and
     `Midterm · 1 h · B304(A–C), B305 or B201`. The app never assigns a room: the university's room list names every
     student, so it is left out for their privacy, and the screens say so.
   - **An exam week has no classes:** from a period's first exam to its last, the timetable's classes are left off every
     rail, row and reminder.
   - **Deadlines and VOD windows due today** sit at their due time among the classes.
   - **After the last class** of the day: `Free for the rest of the day`, at the time it ends.
   - **No class today:** `No classes today` (or `No more classes today`) right after the Now row.
   - **The next days** follow under day headers ("Tomorrow", "Sun 25 Oct"). A day holds what is due on it within the next 72 h, the
     first class of the next day that has classes, and the next class of every course in attendance trouble. Days with nothing are left
     out, and the rail ends at its last item.
   - **Attendance trouble** goes on the course's next class on the rail (hero or row) as a `StatusLine`: `6 of 8 absences used · 2 left`.
   - **Nothing due in the next 3 days:** after the rail, one ok `StatusLine`:
     `Nothing due in the next 3 days. Next: Lab 6, Multimedia Computing, Mon 3 Nov 23:59.`, or `No deadlines in eClass`. Never a
     celebration, never empty space.
3. **Exams,** during an exam period and only while an exam lies beyond the rail's 72 h: a `Midterm exams` section
   with the student's exams still to come as Deadlines-style rows (start time and day), the info line
   `Rooms aren't included, for your privacy: tap an exam to set yours.` while a room isn't set, and "Show exam week".
4. **Attendance:** every course in trouble as a row with its tally and count, then one line for the rest:
   `The other 3 courses are within their limit.`, `All 4 courses are within their limit.`, or, while limits are missing, an info line
   with the raw counts (`No limit set: Artificial Intelligence 6 · Multimedia Computing 2`). The section taps through to Courses. The
   student opens the app partly to ask this, so the answer is always on screen.
5. **Unread mail:** shown only when there is unread mail, headed by the count (`8 unread`). Two rows (subject, then date), then
   `6 more`. Room changes often arrive by mail. When Exchange fails, this section gets only the stale marker; the error row is on the
   Mail screen.
6. **Footer:** `Updated 08:41`, or `Updating…` during a refresh.

**Rail rows by kind:**
- **Class:** time column start and end; course in `titleMedium` (one line), `B202 · Lecture` in muted `bodyMedium`.
- **Deadline:** time column the due time; title in `titleSmall` (up to two lines), tidied for rows by `rowTitle` in `lib/ui/format/`:
  Moodle's event suffix goes (`(Quiz closes)`, `is due`), and a leading kind tag goes too, or becomes a word before a number, so
  `[QUIZ] 2 Week 6 - 2% (Quiz closes)` reads `Quiz 2 Week 6 - 2%`. The deadline sheet shows eClass's full title. Then
  `Not submitted · Multimedia Computing` muted
  (`Not attempted` for a quiz, `Closes · 62% watched` for a VOD). When it is warning or danger the second line is a `StatusLine`
  (`Due in 5 h · not submitted`, `Overdue 2 h · not attempted`, for a VOD `62% watched, 21 min left`), the due time and the node take
  the status colour, and the course moves to a third line.

| Item | Shown on Today when | Plain | Warning | Danger |
|---|---|---|---|---|
| Deadline, not submitted | Due within 72 h | 24–72 h left | 3–24 h left | Under 3 h left, or overdue (kept for 24 h, then only on Deadlines) |
| VOD window, not fully watched | Closes within 72 h | — | 12–72 h left | Under 12 h left |
| Attendance | Remaining allowed absences ≤ max(1, 25% of the allowance) | — | That condition holds | 0 remaining, or over the limit |

VOD windows use 72 h rather than 48 h: a missed window is a recorded absence, and "closes Sunday" needs to be seen by Friday.

The absence allowance comes from the limit the student sets. **Never hardcode or guess it.** If it is unknown, show the raw count and
"limit not set": the tally then shows the used marks only, with no faint remainder.

**Stale and failed data.** Always render from cache first.

| Source | Feeds | Stale after |
|---|---|---|
| EduPage | The rails' classes, Schedule | 24 h |
| eClass | Deadlines, VOD windows, attendance | 3 h |
| Exchange mail | Mail | 30 min |
| INS | Grades | 24 h |

- **A stale or failed section** gets a trailing `bodySmall` marker on its header: `sync_problem` plus `as of Tue 18:04`, in warning
  `fg`. The rail has no header, so its marker is a line of its own at the top: `Timetable as of Tue 18:04`.
- **A failed service** gets one error row, at the top of the first part it feeds (for example `eClass sign-in needed.` with "Sign in").
  Its other parts get only the marker.
- **With no cache,** the error row replaces that part's content and every other part still renders. No service failure blanks the
  screen.

## 8. Screen patterns

**Schedule (day rail).**
- **Week strip:** Mon–Fri as a `TabBar`: the weekday in `labelMedium`, the date in `titleMedium` (tnum). Today's date is `primary`; the
  selected day has a 2dp `onSurface` underline. Swiping the rail changes the day. On the weekend it shows next week.
- **The day** is a rail like Today's: class rows with start and end, breaks of 30 min or more as a muted `Break 1 h 10 min` line with no
  node, and, on today, the Now row between the classes it falls between. The class in progress has the `primary` dot and a
  `Now · until 11:50` label; past classes are muted.
- **Changes:** EduPage publishes neither room changes nor cancellations yet. When it does, a room change gets a warning `StatusLine`
  ("Room changed to A-201") and a cancelled class is struck through with a danger `StatusLine` "Cancelled".
- **Tapping a class** opens its course.
- **Exams** take the classes' place in an exam week: each day shows that day's exams, or
  `No classes in midterm week, and no exam of yours on Thu 29 Oct.` During an exam period the app bar has "Exams".

**Exams** (the exam week, `docs/EXAMS.md`).
- **The answer first:** the student's exams by day, as Deadlines-style rows (start and end, the course, then
  `Midterm · B209 or B210`), past ones muted. Above them one muted line, `Fall 2026 midterm, Mon 26 – Fri 30 Oct, from the
  university's exam timetable.`, and while a room isn't set the info line
  `Rooms aren't included, for your privacy: tap an exam to set yours.`
- **Not on the timetable:** the student's courses with no sitting, in one sentence.
- **"Show every exam"** lists the whole sheet the same way, for checking the matching by hand. The source PDF's name closes
  the screen.
- **A course with several sittings** nothing tells apart (two teachers, say) shows each, with the sheet's note
  (`Midterm · Dr.Sarvar · B304(A–C) or B305`) and an info `StatusLine`: `The timetable lists 2 sittings; check which is yours.`
- **The exam sheet:** `Midterm · Fall 2026` muted, the course in `headlineSmall`, a rule, the day and time with the
  length, then the room (`Room B305` with `You set this room.`) or an info `StatusLine` `Room not set` with why
  (`For your privacy, the app doesn't include anyone's exam room: the university's room list names every student. Set
  yours once you know it.`) and the rooms the exam uses with their seats, the cell as printed with its slot in
  `bodySmall`, and the text buttons "Set my room" (a dialog of the exam's rooms; the student picks, nothing is
  guessed) and "Course attendance and grade".
- **Course detail** gets a `Midterm` section after Due: the sitting as a row, or `No midterm on the timetable for this course.`

**Deadlines.**
- **Filters** first: a course chip and kind chips in one scrolling row, then "Show done" as a checkbox on its own line under them
  (the whole line is the target).
- **Grouping:** day sections with rules and `titleMedium` headers. `Overdue` comes first, in danger `fg` with its icon, only when
  something is overdue. Then `Today`, `Tomorrow`, `Sat 25 Oct`. Empty days are omitted.
- **Row:** the rail's deadline row without the line: the due time in `numeral` on the left, the title, then state and course.
- **Done items** show by default and carry an ok `StatusLine`: `Submitted Tue 21:14`. Unticking "Show done" hides them, and counts as
  a filter for the "Nothing matches these filters" note.
- **Tapping a row** opens the deadline sheet: the kind (icon and word), eClass's full title in `headlineSmall`, the course, a rule, the due time or
  watch window, the status, submission or watch progress (a 4dp `onSurface` bar on `outlineVariant`), and a `FilledButton`
  "Open in eClass", with "Course attendance and grade" as a `TextButton` below.

**Courses (attendance and VOD).**
- **Order:** danger, then warning, then everything else in timetable order. This tab exists to answer "am I in trouble".
- **Intro line:** `Absences against the limits you set, as of 13:20.` While any course lacks a limit: `Set limits` instead.
- **Row**, ruled from the next:
  1. The course name in `titleMedium` (up to two lines).
  2. A `StatusLine` when in trouble (`2 left · next Mon 13:00`), otherwise the next class in muted `bodyMedium`
     (`Today 14:00 · B202`, `Next Mon 14:30 · A305`, led by `Limit not set` while there is none), or `No class attendance in eClass`.
  3. `VOD 10 of 12 watched`, when the course has VODs.
  4. On the right, the tally and below it the count in `numeral`: `6 of 8` in the status `fg` when in trouble, otherwise
     `onSurfaceVariant`; `6` with "limit not set" in the second line when there is no limit.
- **The tally:** one stroke per absence, in gates of five (four uprights and a diagonal through them). Used strokes are `onSurface`, or the
  status `fg` in trouble; the strokes still allowed are `outlineVariant`. Over the limit every stroke is danger and the count reads
  `10 of 8`. Strokes are 16dp tall (28 on course detail), 2dp wide, 7dp apart, with 10dp between gates; the faint strokes are painted
  first, so a faint diagonal never cuts an inked upright. More than 20 marks are not drawn; the words stand alone. It always appears
  next to its words and carries `Semantics(label: '6 of 8 allowed absences used')`.
- **Course detail** (opened from a course row, a class, or a deadline's sheet):
  - The course name in `headlineSmall` (wrapping), with the code and professor below it. The app bar starts empty; once the name has
    scrolled under it, the name fades in there (section 12).
  - The absence count in `headlineMedium` (`6 of 8`) with the large tally, a `StatusLine` for what is left, and the classes held so
    far. Then "Open in eClass" and "Set absence limit" / "Change limit" as text buttons.
  - The course's deadlines, then the INS grade: both short, so they come before the long lists.
  - VOD lectures, each with `Week 7 · 38 / 75 min` and a 4dp bar in `onSurface` on `outlineVariant`.
  - A ruled list of the eClass attendance sessions held so far, newest first: date plus Present, Absent, Late or Other, each as icon
    and word. eClass also lists the semester's future sessions; they are not shown.
- **A class with no eClass course** (Mental Education) opens a sheet with its time, room and teacher, and says there is no
  attendance record for it.

**Mail.**
- **Folders:** Inbox, Drafts, Sent, Deleted, Junk, Notes, in a drawer behind the menu button: paper with a rule on its open edge, no
  shadow. The selected folder is marked like the selected tab (`primary`, filled icon, 600). Inbox and Junk show their unread count,
  Drafts how many are waiting. The app bar title is the folder's name.
- **New** is the one floating button in the app: ink (`inverseSurface`) like the badge, radius 8, elevation 0, only on the Mail tab.
- **List:** in Sent and Drafts the first line is `To <recipients>` instead of the sender. A draft opens in the composer. ruled rows: the sender in muted `bodyMedium` with the time on the right, the subject (`titleSmall` when unread, `bodyLarge`
  when read), and a one-line preview. No unread dot: weight carries it.
- **Message:** the subject in `headlineSmall` (it fades into the empty app bar once scrolled away), the sender in `titleSmall` and the
  time, attachments (name and size), a rule, then the body in `bodyLarge` with tappable links. App bar: "Mark as unread" and Delete
  (in Deleted, "Move to Inbox"); in Inbox and Junk a menu moves it to Junk or back ("Not junk"). Under a rule at the foot: Reply,
  Reply all (only when someone besides the sender got it) and Forward; Sent mail gets only Forward. Every move says so in a snack bar
  with Undo. Nothing is deleted for good: Delete moves to Deleted, as Outlook does.
- **Composer:** plain text. Header lines (To, Cc and Bcc behind "Cc, Bcc", Subject) are label-and-field rows between rules, the fields
  without boxes; the body below. Typing three letters of a name lists matching people and lists from the university directory under
  the line. A reply shows its recipients and `RE:` subject as fixed lines, since Exchange sets them, and says the original is quoted
  under what you write. Send is the app bar's icon; leaving with anything written asks "Keep this as a draft?" (Discard, Save draft).

**Grades.** The GPA first, as a plain line: `3.87` in `headlineMedium` with `GPA of 4.5 · 98 credits · year 3` beside it. Then each term,
newest first, under a `titleMedium` header: ruled rows with the course in `bodyLarge`, its credits in muted `bodyMedium`, and the letter
in `titleMedium` on the right ("Not graded" in muted `bodyMedium`). The letter is the answer, so it is the Fraunces part.

**Settings.**
- **Sections:** Accounts, Notifications, Courses, Timetable, Appearance, About (the open-source licences, the fonts' OFL included),
  each under a ruled `titleMedium` header.
- **One row per service that needs a login:** eClass, INS, University mail. The subtitle carries the status:
  `Signed in as U… · checked 08:41`, `Sign-in rejected · checked 08:41` (a danger `StatusLine`), `U… · not checked yet`
  or `Not set up`. Every refresh updates it.
- **Tapping a row** opens a sheet: the service in `headlineSmall`, username, password (obscured, with a show toggle) and a
  `FilledButton` "Save and test". The result appears inline: `Signed in` or `eClass rejected this username or password.`
- **Never display a saved password.**
- **Sign out** is a `TextButton` in `error` color, behind a confirm dialog. It removes the saved login, the service's cookies and
  cached data, and (for eClass) the reminders planned from that data.
- **Notifications:** a switch per channel and one for quiet hours.
- **Appearance:** Theme, with System, Light and Dark in a dialog.
- **Absence limits** is its own screen: every eClass course that takes attendance, ruled, with its limit or `Not set`; tapping one asks
  for the number (empty clears it).

**Empty states.** One left-aligned `bodyLarge` sentence stating the fact, an optional `Checked 08:41`, and at most one `TextButton`.
- `No classes on Sunday. Next: Mon 27 Oct, 09:00 Multimedia Computing, B-305.`
- `No unread mail.`
- `Sign in to eClass to see deadlines and attendance.`, with a "Sign in" button. Signed out with nothing cached, this note stands in
  for the service's error row, so the screen offers one "Sign in", not two.

**Loading.**
- **Cache first.** Never replace visible data with a loader.
- **Background refresh:** a 2dp `LinearProgressIndicator` in `primary` under the app bar rule, and `Updating…` in the footer.
- **First run with no cache:** a static skeleton that mirrors the real rows (`surfaceContainerHighest` blocks, radius 4, no shimmer):
  the rail's time column and two lines of text per row.
- **Spinners:** never a full-screen `CircularProgressIndicator`. A small spinner is allowed only inside a button whose action is running.
- **Timeout:** 15 s per service.

**Errors.** One row per failed service, in the form `<what happened>. <what you are seeing>.` plus one action. Raw exceptions and HTTP
codes never reach the screen.

| Cause | Row text | Action |
|---|---|---|
| Timeout or server error | `Couldn't reach INS. Showing data from Tue 18:04.` | Retry |
| Sign-in expired or rejected | `eClass sign-in needed.` | Sign in |
| Page layout changed, so parsing failed | `Couldn't read the eClass page; it may have changed. Showing data from 08:12.` | Retry |
| Failed with no cache | `Couldn't reach EduPage. Check the connection.` | Retry |

**Pull to refresh.**
- **Every tab has a `RefreshIndicator`** with `AlwaysScrollableScrollPhysics`, so short lists can still be pulled.
- **Scope:** Today refreshes every service; other tabs refresh only their own.
- **Completion:** the indicator stays until every service finishes or times out. No success snack bar; the footer time is the feedback.

**Offline.**
- **Detection:** failed requests. The app counts as offline when both EduPage and eClass failed with a network error on their last
  refresh: two different hosts failing together means the connection, not a service.
- **Display:** one row at the top of Today, Schedule, Deadlines and Courses: `cloud_off_outlined` plus
  `Offline. Showing data from 08:12.` on `surfaceContainerHigh`, with "Retry". It replaces those services' own network error rows.
- **Recovery:** the next refresh (pull, Retry, or returning to the app) clears it. "Open in eClass" stays enabled.

## 9. Time and number formats

- **Clock and dates:** 24-hour clock (`09:00`, `23:59`); ranges with an en dash (`10:30–11:50`). Dates as `Thu 23 Oct`, with the year
  only if it is not the current one.
- **Relative times, future:** `now` under 1 min, `in 25 min` under 60 min, `in 2 h 15 min` for 1–3 h, `in 6 h` for 3–24 h,
  `Sat 23:59` within 7 days, otherwise `3 Nov 23:59`.
- **Relative times, past:** `2 h ago`, `Overdue 2 h`.
- **Time zone:** always show device time (Asia/Tashkent, UTC+5). Convert from each source's zone when parsing; Inha Korea-hosted
  pages may report KST (UTC+9).
- **Counts and durations:** counts are `3 of 4`, durations `1 h 10 min`. Percentages are whole numbers and always secondary to counts.
- **Course names, never codes,** in titles, rows and notifications. A code appears only as metadata on course detail.
- **One formatter:** every string comes from `lib/ui/format/`. Widgets never call `DateFormat` themselves.

## 10. Microcopy

- **State the fact, the source and the time,** in plain, specific sentences. Numbers are always digits.
- **Buttons** are a verb plus 1–3 words: "Retry", "Sign in", "Open in eClass".
- **Banned:** exclamation marks, "Oops", "Whoops", "Uh-oh", "Hey", "Let's", "Awesome", "Great job", "seamlessly",
  "Something went wrong", "please", "sorry".
- **Errors never blame the student,** and they say what still works ("Showing data from …").

| Don't | Do |
|---|---|
| Oops! Something went wrong. | Couldn't reach eClass. Showing data from 18:04. |
| You're all caught up! | Nothing due in the next 3 days. |
| Don't forget your assignment! | Lab 5 due in 3 h |
| SOC4020 HW3 | Lab 3, Multimedia Computing |
| Attendance: 75% | 3 of 4 absences used · 1 left |
| Loading your awesome schedule… | (a 2dp progress bar, then the data) |
| Invalid credentials | eClass rejected this username or password. |
| Last synced: 2026-10-22T03:41:00Z | Updated 08:41 |

## 11. Notifications

Notify only when the student must act, or would be hurt by not knowing. Following the Android guidance, never notify about syncing,
success, re-engagement, greetings, errors that recover on their own, or anything already done.

| Channel | Importance | Fires when | Default |
|---|---|---|---|
| Deadlines | DEFAULT | 24 h and 3 h before a deadline that isn't submitted | On |
| VOD windows | DEFAULT | 48 h and 6 h before a window closes while the VOD isn't fully watched | On |
| Attendance | DEFAULT | A new absence is recorded | On |
| Classes | LOW | 15 min before each class, with the room in the title | Off |

- **Wording:** title at most 30 characters, body at most 40. The most important fact goes first and the course name goes in the body.
  No app name, no emoji, no exclamation marks.
- **One notification per item,** with a stable id, so the 3 h reminder replaces the 24 h one.
- **Check before posting.** Re-sync first; if that sync fails, use the last known status. Never notify about something already
  submitted or watched.
- **Quiet hours:** 23:00–07:30. If a deadline falls inside them, its last reminder goes out at 22:00.
- **The status-bar icon** (`ic_stat_notify`) is white on transparent; Android tints it.
- **Tapping** opens the item's detail.

| Title | Body |
|---|---|
| `Lab 5 due in 3 h` | `Multimedia Computing · 23:59` |
| `Week 7 VOD closes tomorrow` | `Deep Learning for CV · 1 of 3 watched` |
| `Absence: Multimedia Computing` | `3 of 4 used · 1 left` |
| `B-305 in 15 min` | `Multimedia Computing · 10:30–11:50` |

Never send: "Don't forget!", "Hey, you have a deadline", "Sync complete", "You have 3 classes today", or course codes.
`docs/NOTIFICATIONS.md` has the details.

## 12. Motion, icons, launcher

- **Motion:**
  - Keep the M3 page transitions and ripples.
  - **One addition, the scroll title:** a pushed screen whose name is a heading in its body (course detail, a mail message) starts with
    an empty app bar; once that heading scrolls under the bar, the same name fades into it (200 ms, `easeInOut`, instant with
    animations off). The bar never sits empty while the name is off screen.
  - Animate only opacity and transform, for 150–250 ms with standard easing. No overshoot.
  - No list entrance animations. Changing numbers update in place.
  - Honor `MediaQuery.disableAnimations`.
- **Icons:**
  - Flutter `Icons` in the outlined style: 24dp in rows and bars, 16dp in `StatusLine`. Color them `onSurfaceVariant` unless they show a
    status or the selected tab.
  - Use icons only for navigation, status, actions and the deadline sheet's kind. Every icon-only button has a `tooltip`.
- **Launcher icon and splash:** "IUT" in Fraunces SemiBold, ink on paper, with a short IUT-blue rule under it; the themed (monochrome)
  layer is the letters alone. The splash is the paper (ink at night) with the icon in the middle. `tool/make_icons.py` draws all of
  them.

## 13. Review checklist

1. Does the first thing below the app bar answer the screen's question, with no greeting, hero banner or stat tiles above it?
2. Is the widget code free of `Colors.*`, hex literals, `fromSeed`, gradients, `BackdropFilter`, `BoxShadow` and `Card`?
3. Is every string free of emoji, including notifications and test fixtures?
4. Is there at most one `FilledButton` on the screen, and is structure made with rules, not boxes?
5. Is every status shown as icon plus words through `StatusLine`, never as a colored node, tally, dot or tint alone?
6. Does the screen render in both light and dark, using only `colorScheme` and `StatusColors` roles?
7. Is Fraunces used only for its roles (room, titles, headers, course names, numerals, grade letters) and Public Sans for the rest?
8. Do times, counts, percentages and rooms use `.tnum`? Are times 24-hour, in device time, and formatted by `lib/ui/format/`?
9. Are courses named, never shown by code?
10. Does the screen work at `textScaler` 2.0 without clipping? Are all targets at least 48dp, and do all icon buttons have tooltips?
11. Were all states built: first load with no cache, cached while refreshing, empty, stale, one service failed, offline, signed out?
12. Is there never a blank screen, a full-screen spinner, or raw exception text?
13. Does every error row name the service, show the age of the data, and offer an action?
14. Does pull to refresh work even on a short list?
15. Is the copy free of exclamation marks and of the banned words in section 10?
16. Do absence counts and limits come from data, never invented or hardcoded?
17. Do mocks and screenshots use realistic names, rooms and times?
18. Is there no motion beyond the M3 defaults and the scroll title, and is `disableAnimations` respected?

## Sources

1. Anthropic, "Prompting for frontend aesthetics" (on generic, on-distribution defaults): https://platform.claude.com/cookbook/coding-prompting-for-frontend-aesthetics
2. The Fountain Institute, "7 Signs a UI Has Been Vibe Coded": https://www.thefountaininstitute.com/blog/signs-vibe-coded-ui
3. Paul Bakaus, Impeccable, "Anti-patterns": https://mintlify.wiki/pbakaus/impeccable/concepts/anti-patterns
4. ux-skill wiki, "How to detect AI slop in your design" (checkable rules): https://github.com/Laith0003/ux-skill/wiki/How-to-detect-AI-slop-in-your-design
5. Android Developers, notification guidelines: https://developer.android.com/design/ui/mobile/guides/home-screen/notifications
6. Nielsen Norman Group, "Skeleton Screens 101": https://www.nngroup.com/articles/skeleton-screens/
7. GOV.UK Design System, "Error message": https://design-system.service.gov.uk/components/error-message/
8. MacStories on the Transit app's answer-first home screen: https://www.macstories.net/reviews/transit-is-still-the-best-designed-transit-app-on-the-iphone-in-2024/
9. W3C, WCAG 2.2 Understanding 1.4.1 "Use of Color": https://www.w3.org/WAI/WCAG22/Understanding/use-of-color.html
10. Flutter API, the `ColorScheme` constructor and its current roles: https://api.flutter.dev/flutter/material/ColorScheme/ColorScheme.html
11. Fraunces (Undercase Type, OFL): https://github.com/undercasetype/Fraunces; Public Sans (USWDS, OFL): https://github.com/uswds/public-sans
