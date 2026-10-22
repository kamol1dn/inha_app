# Design guide

This guide covers every screen in `lib/`. The app is for one IUT student who opens it many times a day, often walking between classes,
to answer three questions: where do I need to be next, what is due, am I in attendance trouble. If a screen breaks a rule here, fix the
screen or change this file in the same commit.

## 1. Principles

1. **Answer first.** The first row on each screen answers its question: the next room and time until class on Today, the next item on
   Deadlines, the course closest to the absence limit on Courses. Nothing goes above that row: no greeting, hero or summary tiles.
2. **Specific, not decorative.** Use real names, real times, and numbers with their denominator ("3 of 4"). If an element carries no
   information and offers no action, delete it.
3. **Neutral by default, colored by exception.** About 90% of a screen is neutral. Color is reserved for the accent's four jobs and the
   four statuses.
4. **Never blank, never silent.** Show cached data first, show its age when that matters, and name every failure by service with a
   next step.
5. **Readable while walking.** The room and the time until class are the largest text in the app. Everything else is 16sp or smaller.

Most anti-slop advice is written for marketing pages: distinctive display fonts, layered backgrounds, staggered reveals on load. It
does not transfer to a utility opened 20 times a day. Here the opposite of generic is specific, not decorated.

## 2. Slop patterns: don't / do

| Don't | Do instead |
|---|---|
| A greeting header ("Good morning, Kamol") or a big date hero | A small app bar titled `Thu 23 Oct`, with the next class directly below it |
| Gradients anywhere: hero cards, buttons, text, borders | Flat tonal surfaces. Color only for status and the accent |
| A purple/indigo palette, or `ColorScheme.fromSeed` (the Flutter template seeds `Colors.deepPurple`) | The explicit schemes in section 3. Replace the `fromSeed` in `lib/app.dart` |
| Everything in a rounded card, cards inside cards, one card per row | Plain lists on `surface`, grouped by section headers. At most one card per screen |
| Emoji in headings, labels, empty states or notifications | No emoji anywhere |
| An icon in a tinted circle before every heading or row | Icons only for item type, status, navigation and actions. Headers have no icon |
| Vanity or fake stats: "92% attendance" tiles, streaks, scores, progress rings | The real count with its denominator and limit: "3 of 4 absences used" |
| Vague, cheerful copy: "Oops! Something went wrong", "You're all caught up!" | What happened, which service, as of when, and what to do (section 10) |
| Glassmorphism, `BackdropFilter`, glows, colored shadows | Opaque surfaces at elevation 0 |
| Status dots, pulsing dots, or "New"/"Live" pills with no defined meaning | Only the four defined statuses, always shown as an icon plus words |
| A thick colored stripe down one side of a card or row | A status icon and words. The current item gets `primary` text and the word "Now" |
| A 20–28 radius and pill shapes on everything | Radius by role: 0 for rows, 8 for controls, 12 for the one card |
| Uppercase, letter-spaced eyebrow labels ("UPCOMING") | Sentence-case `titleSmall` headers |
| Staggered list entrances, bounce, confetti, shimmer | Default M3 transitions. Motion only to show that something changed |
| Illustrations or mascots in empty states | One sentence and at most one action |
| Every button filled | At most one `FilledButton` per screen. Row actions use `TextButton` |
| John Doe, Acme, or round invented numbers in mocks and golden tests | Real course names and realistic IUT rooms and times |

## 3. Color

- **Accent (`primary`):** `#1D4E89` in light mode, `#A9C7EF` in dark. It is taken from the deep blue of the IUT emblem, which uses sky
  blue and deep blue. I found no official hex value, so these are our own. The hue (~212°) stays clear of indigo and violet (240–290°).
- **The accent has exactly four jobs:** the "Next"/"Now" label and the current-time marker, the one filled button on a screen, text
  buttons and links, and the `info` status. Headers, icons and backgrounds are never blue.
- **`secondary`** is slate, used only implicitly by M3 (navigation indicator, selected chips). **`tertiary`** mirrors it and is never
  referenced.
- **No `fromSeed`, no `dynamic_color`, and no `Colors.*` or hex literals in widgets.** `fromSeed` invents tertiary and container tones
  nobody has checked for contrast. Widgets read only `colorScheme` and `StatusColors`.
- **`surfaceTint` is transparent.** Surfaces are told apart by their `surfaceContainer*` step, never by elevation tint.
- **Dark mode is designed, not inverted.** Surfaces get lighter as they rise, statuses use lighter tones, and nothing is pure black.
  Pure white is used only as text on `primary` or `error` in light mode.

```dart
// lib/ui/theme/app_colors.dart
const lightScheme = ColorScheme(brightness: Brightness.light,
  primary: Color(0xFF1D4E89), onPrimary: Color(0xFFFFFFFF), primaryContainer: Color(0xFFD5E3F5), onPrimaryContainer: Color(0xFF0D2A4C),
  secondary: Color(0xFF4A5868), onSecondary: Color(0xFFFFFFFF), secondaryContainer: Color(0xFFDCE3EB), onSecondaryContainer: Color(0xFF1D2833),
  tertiary: Color(0xFF4A5868), onTertiary: Color(0xFFFFFFFF), // unused; mirrors secondary
  error: Color(0xFFB42318), onError: Color(0xFFFFFFFF), errorContainer: Color(0xFFFBE3DF), onErrorContainer: Color(0xFF5A130B),
  surface: Color(0xFFF7F8FA), onSurface: Color(0xFF191C20), onSurfaceVariant: Color(0xFF4A525C),
  surfaceContainerLowest: Color(0xFFFDFDFE), surfaceContainerLow: Color(0xFFF1F3F5), surfaceContainer: Color(0xFFEBEEF1),
  surfaceContainerHigh: Color(0xFFE5E8EC), surfaceContainerHighest: Color(0xFFDFE2E6),
  surfaceDim: Color(0xFFD7DADE), surfaceBright: Color(0xFFF7F8FA), outline: Color(0xFF737B85), outlineVariant: Color(0xFFD8DCE1),
  inverseSurface: Color(0xFF2D3136), onInverseSurface: Color(0xFFEEF0F3), inversePrimary: Color(0xFFA9C7EF),
  shadow: Color(0xFF000000), scrim: Color(0xFF000000), surfaceTint: Color(0x00000000));

const darkScheme = ColorScheme(brightness: Brightness.dark,
  primary: Color(0xFFA9C7EF), onPrimary: Color(0xFF0D2A4C), primaryContainer: Color(0xFF1F4573), onPrimaryContainer: Color(0xFFD5E3F5),
  secondary: Color(0xFFB5C0CC), onSecondary: Color(0xFF1F2A35), secondaryContainer: Color(0xFF353F4A), onSecondaryContainer: Color(0xFFDCE3EB),
  tertiary: Color(0xFFB5C0CC), onTertiary: Color(0xFF1F2A35),
  error: Color(0xFFFFB3A8), onError: Color(0xFF5A130B), errorContainer: Color(0xFF5E1A12), onErrorContainer: Color(0xFFFCD9D3),
  surface: Color(0xFF121418), onSurface: Color(0xFFE2E4E8), onSurfaceVariant: Color(0xFFA8AFB8),
  surfaceContainerLowest: Color(0xFF0C0E11), surfaceContainerLow: Color(0xFF181B1F), surfaceContainer: Color(0xFF1C1F24),
  surfaceContainerHigh: Color(0xFF24282D), surfaceContainerHighest: Color(0xFF2C3036),
  surfaceDim: Color(0xFF121418), surfaceBright: Color(0xFF383D44), outline: Color(0xFF878E98), outlineVariant: Color(0xFF353A41),
  inverseSurface: Color(0xFFE2E4E8), onInverseSurface: Color(0xFF2D3136), inversePrimary: Color(0xFF1D4E89),
  shadow: Color(0xFF000000), scrim: Color(0xFF000000), surfaceTint: Color(0x00000000));
```

**Measured WCAG contrast:**
- `onSurface` on `surface`: 16.1:1 light, 14.5:1 dark.
- `onSurfaceVariant` and `primary` on the darkest container: at least 6.0:1.
- `outline` (input and selection borders): at least 3.3:1 on every surface.
- `outlineVariant` is decorative only: dividers and empty bar cells.

```dart
// lib/ui/theme/status_colors.dart
typedef StatusTone = ({Color fg, Color container, Color onContainer});
enum Status { ok, warning, danger, info }

@immutable
class StatusColors extends ThemeExtension<StatusColors> {
  const StatusColors({required this.ok, required this.warning, required this.danger, required this.info});
  final StatusTone ok, warning, danger, info;
  static const light = StatusColors(
    ok:      (fg: Color(0xFF1A6B3A), container: Color(0xFFD9EFE0), onContainer: Color(0xFF0E3D20)),
    warning: (fg: Color(0xFF8A5000), container: Color(0xFFFBEAC6), onContainer: Color(0xFF4A2C00)),
    danger:  (fg: Color(0xFFB42318), container: Color(0xFFFBE3DF), onContainer: Color(0xFF5A130B)),
    info:    (fg: Color(0xFF1D4E89), container: Color(0xFFD5E3F5), onContainer: Color(0xFF0D2A4C)));
  static const dark = StatusColors(
    ok:      (fg: Color(0xFF7DCB96), container: Color(0xFF163A23), onContainer: Color(0xFFC4EACF)),
    warning: (fg: Color(0xFFEDB65A), container: Color(0xFF3E2B07), onContainer: Color(0xFFF8E2B5)),
    danger:  (fg: Color(0xFFFFB3A8), container: Color(0xFF5E1A12), onContainer: Color(0xFFFCD9D3)),
    info:    (fg: Color(0xFFA9C7EF), container: Color(0xFF1F4573), onContainer: Color(0xFFD5E3F5)));
  StatusTone of(Status s) => switch (s) { Status.ok => ok, Status.warning => warning, Status.danger => danger, Status.info => info };
  @override StatusColors copyWith() => this;
  @override StatusColors lerp(StatusColors? other, double t) => t < 0.5 ? this : (other ?? this);
}
```

| Status | Icon (always shown) | Means | `fg` on the darkest surface, light / dark | `fg` on its container |
|---|---|---|---|---|
| ok | `check_circle_outline` | Submitted, watched, within limits | 5.0 / 6.9 | 5.4 / 6.5 |
| warning | `warning_amber_rounded` | Act soon; data is stale | 5.0 / 7.2 | 5.5 / 7.4 |
| danger | `error_outline` | Due within hours, overdue, at or over the absence limit, sign-in broken | 5.1 / 7.8 | 5.4 / 7.5 |
| info | `info_outline` | Notable but nothing wrong ("VOD window opens Mon") | 6.5 / 7.6 | 6.5 / 5.6 |

All `onContainer` pairs are at least 9.6:1. `ColorScheme.error` uses the danger color.

- **Status is always rendered by one of two widgets.** `StatusLine` is an 18dp icon, an 8dp gap and `bodyMedium` text in `fg`. `StatusTag`
  is a container fill with `onContainer` text in `labelMedium`, height 20, radius 4.
- **Colored text alone is acceptable only when the words state the condition** ("in 2 h", "Over limit", "1 left"). A dot, stripe, border,
  bar or tint is never the only signal.
- **In light mode, warning and danger have the same lightness on purpose** (1.0:1 between them). The icon shape and the wording tell
  them apart.
- **Tinted containers are only for `StatusTag` and the offline row.** Never tint a whole row or card.

## 4. Typography

**Font: the platform default, Roboto. Do not add `google_fonts`.** Roboto appears on "overused font" lists, but those lists are about
web pages, where the typeface is the brand. In a native Android utility the system font is the right choice:
- **No startup cost.** Nothing to bundle or fetch, and no layout shift, in an app opened 20 times a day.
- **Script coverage.** Course and professor names and Inha pages can be Korean, Cyrillic or Uzbek Latin. System Noto fallback matches
  Roboto's metrics; a bundled font would mix with mismatched fallback glyphs.
- **It matches notifications and the status bar.**
- **Tabular digits.** Roboto supports `tnum`, and we still set it explicitly so alignment never depends on a font default.

The deliberate part is the scale, not the typeface. These 9 styles are the only ones allowed, in weights 400, 500 and 700 only.
`display*`, `headlineLarge` and `headlineSmall` are never used.

| Style | Size / line (sp) | Weight | Used for |
|---|---|---|---|
| `headlineMedium` | 28 / 34 | 500, tnum | Only Today's room and time until class, and the absence count on course detail |
| `titleLarge` | 22 / 28 | 500 | App bar titles |
| `titleMedium` | 16 / 22 | 500 | A row's primary line (course name, item title) |
| `titleSmall` | 14 / 20 | 700 | Section and day headers ("Needs attention", "Tomorrow") |
| `bodyLarge` | 16 / 24 | 400 | Paragraphs: mail body, item description |
| `bodyMedium` | 14 / 20 | 400 | A row's secondary line in `onSurfaceVariant`; `StatusLine` |
| `bodySmall` | 12 / 16 | 400 | Metadata: "Updated 08:41", "as of Tue 18:04" |
| `labelLarge` | 14 / 20 | 500 | Buttons |
| `labelMedium` | 12 / 16 | 500 | Tags, chips, navigation labels |

```dart
// lib/ui/theme/app_text.dart. Pass as ThemeData.textTheme; M3 typography supplies color and letter spacing.
const _tnum = [FontFeature.tabularFigures()];
const appTextTheme = TextTheme(
  headlineMedium: TextStyle(fontSize: 28, height: 34 / 28, fontWeight: FontWeight.w500, fontFeatures: _tnum),
  titleLarge: TextStyle(fontSize: 22, height: 28 / 22, fontWeight: FontWeight.w500),
  titleMedium: TextStyle(fontSize: 16, height: 22 / 16, fontWeight: FontWeight.w500),
  titleSmall: TextStyle(fontSize: 14, height: 20 / 14, fontWeight: FontWeight.w700),
  bodyLarge: TextStyle(fontSize: 16, height: 24 / 16), bodyMedium: TextStyle(fontSize: 14, height: 20 / 14),
  bodySmall: TextStyle(fontSize: 12, height: 16 / 12),
  labelLarge: TextStyle(fontSize: 14, height: 20 / 14, fontWeight: FontWeight.w500),
  labelMedium: TextStyle(fontSize: 12, height: 16 / 12, fontWeight: FontWeight.w500));
extension Tnum on TextStyle { TextStyle get tnum => copyWith(fontFeatures: _tnum); }
```

- **`.tnum` on every number:** times, countdowns, counts, percentages and room numbers.
- **Sentence case everywhere.** No `toUpperCase()` and no added letter spacing.
- **Per row:** at most 3 sizes and 2 weights. No bold inside a sentence.
- **Text scaling up to `textScaler` 2.0.** Never set a fixed height on anything holding text; use minimum heights. Course names
  ellipsize to one line in rows and wrap on detail screens.

## 5. Spacing, shape, density

**Spacing:** `4, 8, 12, 16, 24, 32, 48` only.

| Where | Spacing |
|---|---|
| Gutter | 16 |
| Section header | 24 above (16 for the first) and 8 below |
| Between lines within a row | 2–4 |
| Card padding | 16 |
| Icon to text | 16 in rows, 8 in `StatusLine` |
| After the last row | 24 |

**Rows** use the M3 `ListTile` heights, with `contentPadding: EdgeInsets.symmetric(horizontal: 16)`:

| Row type | Minimum height | Used for |
|---|---|---|
| One-line | 56 (48 when dense) | Settings rows; Today's "Later today" rows, which are dense |
| Two-line | 72 | Deadline, mail and Needs attention rows |
| Three-line | 88 | Course rows: name, absence bar, VOD line |

Tap targets are at least 48×48. The whole row is one target; the only extra control allowed is a trailing `TextButton`.

**Lists, dividers and cards.**
- **The default is a plain list:** rows on `surface`, grouped by section headers and 24dp gaps. Multi-line rows have no dividers.
- **Dividers** only in uniform one-line lists: mail, attendance by session, Settings. Use `Divider(height: 1, indent: 16)` in
  `outlineVariant`. Never next to a header or between sections.
- **Exactly one card in the app:** Today's next class. `Card.filled` in `surfaceContainerLow`, elevation 0, radius 12, no border, no
  shadow. Never a card per row, never nested cards, never shadow, border and tint together.

**Radius:**

| Element | Radius |
|---|---|
| Rows (full-bleed ripple) | 0 |
| Absence bar cells | 2 |
| `StatusTag`, skeleton blocks | 4 |
| Chips, buttons (override the M3 stadium shape), fields, snack bars | 8 |
| The card | 12 |
| Top corners of sheets and dialogs | 16, not the M3 default of 28 |

**Elevation** is 0 everywhere, including `AppBarTheme(scrolledUnderElevation: 0)`. Menus, dialogs and sheets keep their M3 defaults.

## 6. Navigation

Use a `NavigationBar` with 4 destinations. Labels are always shown. Icons are outlined, and filled when selected.

| Tab | Icon | Answers | Notes |
|---|---|---|---|
| Today | `today` | Where next, what's urgent | The start screen. App bar actions: Mail (unread `Badge`) and Settings (gear) |
| Schedule | `calendar_view_day` | The day's classes and rooms | One day at a time, using the week strip or a swipe |
| Deadlines | `assignment` | Everything due, eClass VOD windows included | Grouped by day |
| Courses | `school` | Attendance, VOD progress and grades by course | App bar action "Grades" opens INS grades |

- **Settings and Mail are pushed screens, not tabs.** Settings is reached only from the gear on Today (tooltip "Settings"). Mail is
  reached from Today's app bar or its mail rows.
- **Each tab keeps its own stack and scroll position** (`StatefulShellRoute` or `IndexedStack`). Tapping the active tab scrolls to the
  top.
- **Back** from another tab goes to Today; back on Today exits.
- **Tapping a notification** opens the item's detail on top of the tab that owns it.

## 7. Today screen

```
Thu 23 Oct                                          [mail 3] [gear]
[offline row, only when offline]
+--------------------------------------------------------------+
| Next  10:30–11:50                                            |  labelLarge, primary; tnum
| B-305                                              in 25 min |  headlineMedium both sides, tnum
| Multimedia Computing                                         |  titleMedium
| Lecture · Prof. Kim                                          |  bodyMedium, onSurfaceVariant
| [!] 3 of 4 absences used                                     |  StatusLine, only at warning/danger
+--------------------------------------------------------------+
Later today                                                         titleSmall
13:00   Deep Learning for CV                              A-201     dense rows, 48dp time column
Needs attention                                                     only if non-empty, max 5 rows
[x] Artificial Intelligence                           [At limit]    attendance first
    4 of 4 allowed absences used
[doc] Lab 5: JPEG quantization                           in 5 h     then by time left
    Multimedia Computing · not submitted                  23:59
All 8 deadlines                                                     TextButton, only if more than 5
Unread mail                                                         only if unread > 0, max 2 rows
Updated 08:41                                                       bodySmall, onSurfaceVariant
```

1. **App bar:** small, titled with the date. It never collapses and has no subtitle.
2. **Next-class card.**
   - **Before or between classes:** "Next".
   - **During a class:** "Now · until 11:50", with `40 min left` on the right. The following class becomes the first "Later today"
     row.
   - **After the last class:** the card shrinks to "No more classes today" and "Tomorrow 09:00 · Multimedia Computing · B-305", with no
     big numbers.
   - **No classes today:** the next class day.
   - **Attendance trouble:** if this course is at warning or danger, its `StatusLine` goes inside the card.
   - **Countdown** ticks on the minute.
3. **Later today:** the remaining classes, each with start time, course and room. Past classes are not listed.
4. **Needs attention:** attendance items first, then deadlines and VOD windows ordered by time left. The leading icon gives the type
   (`assignment_outlined`, `quiz_outlined`, `play_circle_outline`, `event_busy_outlined`). The trailing column shows relative and
   absolute time, colored per the thresholds below.
5. **No attendance trouble:** show `[ok] All 6 courses within the absence limit` in place of attendance rows; it taps through to
   Courses. The student opens the app partly to ask this, so the answer is always on screen.
6. **Mail:** shown only when there is unread mail. Two rows (sender and time, then subject) plus "3 more". Room changes often arrive by
   mail.
7. **Footer:** `Updated 08:41`, or `Updating…` during a refresh.

| Item | Shown on Today when | Plain | Warning | Danger |
|---|---|---|---|---|
| Deadline, not submitted | Due within 72 h | 24–72 h left | 3–24 h left | Under 3 h left, or overdue (kept for 24 h, then only on Deadlines) |
| VOD window, not fully watched | Closes within 48 h | — | 12–48 h left | Under 12 h left |
| Attendance | Remaining allowed absences ≤ max(1, 25% of the allowance) | — | That condition holds | 0 remaining, or over the limit |

The absence allowance comes from data or the course config. **Never hardcode or guess it.** If it is unknown, show the raw counts
and "Limit not set", with no bar.

**Nothing urgent:** one ok `StatusLine` takes the place of Needs attention:
`Nothing due in the next 3 days. Next: Lab 6, Multimedia Computing, Mon 3 Nov 23:59.` If eClass has no deadlines at all, show
`No deadlines in eClass`. Never a celebration, never empty space.

**Stale and failed data.** Always render from cache first.

| Source | Feeds | Stale after |
|---|---|---|
| EduPage | Card, Later today, Schedule | 24 h |
| eClass | Deadlines, VOD windows, attendance | 3 h |
| Outlook Web | Mail | 30 min |
| INS | Grades | 24 h |

- **A stale or failed section** gets a trailing `bodySmall` marker on its header: `sync_problem` plus `as of Tue 18:04`, in warning
  `fg`. Fresh sections get no marker.
- **A failed service** gets one error row, under the first section it feeds (for example `eClass sign-in expired.` with "Sign in").
  Its other sections get only the marker.
- **With no cache,** the error row replaces that section's content and every other section still renders. No service failure blanks
  the screen.

## 8. Screen patterns

**Schedule (day view).**
- **Week strip:** Mon–Sat with weekday and date (tnum). The selected day uses `secondaryContainer`; today uses `primary` text. A
  `PageView` swipes between days.
- **Day list:** an agenda list, not an hour grid. Each row has a 56dp time column (start above end, tnum), the course in `titleMedium`,
  and `B-305 · Lecture · Prof. Kim`.
- **Breaks** of 30 min or more show as a `bodySmall` row: "Break 1 h 10 min".
- **Now:** a 1dp `primary` divider labelled `Now 10:52` sits between rows. The current class has a "Now" label and its time in
  `primary`.
- **Past classes** use `onSurfaceVariant`.
- **Changes:** a room change gets a warning `StatusLine` ("Room changed to A-201"). A cancelled class is struck through and gets a
  `StatusTag` "Cancelled".

**Deadlines.**
- **Grouping:** sticky day headers. `Overdue` comes first with a danger header, only when something is overdue. Then `Today`,
  `Tomorrow`, `Sat 25 Oct`. Empty days are omitted (Fantastical's day ticker does the same by default). Beyond 14 days, group by
  `Week of 3 Nov`.
- **Row:** a type icon, the eClass item name, and the course name (plus `1 of 3 watched` for VODs). The trailing column has `23:59`,
  with the relative time below it when under 48 h.
- **Done items** are hidden behind a `FilterChip` "Show done"; when shown, they carry an ok `StatusLine`: "Submitted Tue 21:14".
- **Tapping a row** opens detail: description, window, status, and a `FilledButton` "Open in eClass".

**Courses (attendance and VOD).**
- **Order:** danger, then warning, then everything else in timetable order. This tab exists to answer "am I in trouble".
- **Row:**
  1. The course name, with a trailing `StatusTag` ("1 left", "At limit", "Over limit").
  2. The absence bar and `3 of 4 absences used`.
  3. `VOD: week 7 1 of 3 watched · closes Fri 23:59`, or `VOD: all watched`.
- **Absence bar:** one cell per allowed absence, each 12×6dp with 2dp gaps. Used cells take the status `fg`; empty cells use
  `outlineVariant`. Over the limit, every cell is danger and the text reads `5 absences · limit 4`. The bar always appears next to its
  text and carries `Semantics(label: '3 of 4 allowed absences used')`.
- **Course detail** (opened from a course row, a lesson in Schedule or Today, or a deadline's sheet):
  - The absence count in `headlineMedium` ("3 of 4"), counted over the sessions held so far, and "Open in eClass".
  - The course's deadlines, then the INS grade: both short, so they come before the long lists.
  - VOD weeks, each with `38 / 75 min`, a 4dp `LinearProgressIndicator`, and the window dates.
  - A divided list of the eClass attendance sessions held so far, newest first: date plus Present, Absent, Late or
    Other, each as icon and word. eClass also lists the semester's future sessions; they are not shown.
- **A lesson with no eClass course** (Mental Education) opens a sheet with its time, room and teacher, and says
  there is no attendance record for it.

**Mail and grades.**
- **Mail** is a divided list of sender, time, subject and a one-line preview. Unread subjects use `titleMedium`, read ones `bodyLarge`.
  No unread dot.
- **INS grades** is a list of courses with their grades. The semester GPA is a plain row at the top, not a hero tile.

**Settings (saved logins).**
- **One row per service that needs a login:** eClass, INS, University mail. The subtitle carries the status:
  `Signed in as U… · checked 08:41`, `Sign-in rejected · checked 08:41` (a danger `StatusLine`), `U… · not checked yet`
  or `Not set up`. Every refresh updates it: a fetch that gets through is a working login, a rejected one is not, and a
  network failure says nothing.
- **Tapping a row** opens a sheet with username, password (obscured, with a show toggle) and a `FilledButton` "Save and test". The
  result appears inline: `Signed in` or `eClass rejected this username or password.`
- **Never display a saved password.**
- **Sign out** is a `TextButton` in `error` color, behind a confirm dialog. It removes the saved login, the service's
  cookies and cached data, and (for eClass) the reminders planned from that data.
- **Also in Settings:** notifications per channel, theme (System / Light / Dark), and absence limits per course.
- **Absence limits** is its own screen: every eClass course that takes attendance, with its limit or `Not set`;
  tapping one asks for the number (empty clears it). Courses shows `Set limits` above the list while any course
  lacks one, and course detail has `Set absence limit` / `Change limit`. The new-absence notification adds
  `3 of 4 allowed absences used, 1 left.` once a limit is set.

**Empty states.** One left-aligned `bodyLarge` sentence stating the fact, an optional `Checked 08:41`, and at most one `TextButton`.
Examples:
- `No classes on Sunday. Next: Mon 27 Oct, 09:00 Multimedia Computing, B-305.`
- `No unread mail.`
- `Sign in to eClass to see deadlines and attendance.`, with a "Sign in" button.

**Loading.**
- **Cache first.** Never replace visible data with a loader.
- **Background refresh:** show nothing for the first second. After that, show a 2dp `LinearProgressIndicator` under the app bar and
  `Updating…` in the footer.
- **First run with no cache:** a static skeleton that mirrors the real rows (`surfaceContainerHighest` blocks, radius 4, no shimmer).
- **Spinners:** never a full-screen `CircularProgressIndicator` on a tab. A small spinner is allowed only inside a button whose action
  is running.
- **Timeout:** 15 s per service.

**Errors.** One row per failed service, in the form `<what happened>. <what you are seeing>.` plus one action. Raw exceptions and HTTP
codes go only in a "Details" sheet.

| Cause | Row text | Action |
|---|---|---|
| Timeout or server error | `Couldn't reach INS. Showing data from Tue 18:04.` | Retry |
| Sign-in expired or rejected | `eClass sign-in expired.` | Sign in |
| Page layout changed, so parsing failed | `Couldn't read the eClass page; it may have changed. Showing data from 08:12.` | Details |
| Failed with no cache | `Couldn't load your timetable from EduPage.` | Retry |

**Pull to refresh.**
- **Every tab has a `RefreshIndicator`** with `AlwaysScrollableScrollPhysics`, so short lists can still be pulled.
- **Scope:** Today refreshes every service; other tabs refresh only their own.
- **Completion:** the indicator stays until every service finishes or times out. No success snack bar; the footer time is the
  feedback.

**Offline.**
- **Detection:** failed requests, not only `connectivity_plus`.
- **Display:** one non-dismissible row at the top of Today, Deadlines and Courses: `cloud_off_outlined` plus
  `Offline. Showing data from 08:12.` on `surfaceContainerHigh`.
- **Recovery:** retry automatically when the connection returns. "Open in eClass" stays enabled.

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
- **Buttons** are a verb plus 1–3 words: "Retry", "Sign in", "Open in eClass", "Show done".
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
| Loading your awesome schedule… | (nothing for 1 s, then a 2dp progress bar) |
| Invalid credentials | eClass rejected this username or password. |
| Last synced: 2026-10-22T03:41:00Z | Updated 08:41 |

## 11. Notifications

Notify only when the student must act, or would be hurt by not knowing. Following the Android guidance, never notify about syncing,
success, re-engagement, greetings, errors that recover on their own, or anything already done.

| Channel | Importance | Fires when | Default |
|---|---|---|---|
| Deadlines | DEFAULT | 24 h and 3 h before a deadline that isn't submitted | On |
| VOD windows | DEFAULT | 24 h before a window closes while the VOD isn't fully watched | On |
| Attendance | DEFAULT | A new absence is recorded, or remaining absences reach 1 or 0 | On |
| Classes | LOW | 10 min before each class, with the room in the title | Off |
| Grades | LOW | A new grade is posted in INS | On |
| Sign-in problems | LOW | A saved login stops working (at most once a day per service) | On |

- **Wording:** title at most 30 characters, body at most 40. The most important fact goes first and the course name goes in the body.
  No app name, no emoji, no exclamation marks.
- **One notification per item,** with a stable id, so the 3 h reminder replaces the 24 h one. Group a channel's notifications once
  more than 2 are showing.
- **Check before posting.** Re-sync first; if that sync fails, use the last known status. Never notify about something already
  submitted or watched.
- **Quiet hours:** 23:00–07:30. If a deadline falls inside them, its last reminder goes out at 22:00.
- **Lock screen:** Grades and Attendance use `VISIBILITY_PRIVATE`, with the public text "New grade posted" or "Attendance updated".
- **Tapping** opens the item's detail. At most one action ("Open in eClass").

| Title | Body |
|---|---|
| `Lab 5 due in 3 h` | `Multimedia Computing · 23:59` |
| `Week 7 VOD closes tomorrow` | `Deep Learning for CV · 1 of 3 watched` |
| `Absence: Multimedia Computing` | `3 of 4 used · 1 left` |
| `B-305 in 10 min` | `Multimedia Computing · 10:30–11:50` |
| `eClass sign-in expired` | `Deadlines aren't updating` |
| `New grade posted` | `Artificial Intelligence midterm` |

Never send: "Don't forget!", "Hey, you have a deadline", "Sync complete", "You have 3 classes today", or course codes.

## 12. Motion and icons

- **Motion:**
  - Keep the M3 page transitions and ripples.
  - Animate only opacity and transform, for 150–250 ms with standard easing. No overshoot.
  - No list entrance animations. Changing numbers update in place.
  - Honor `MediaQuery.disableAnimations`.
- **Icons:**
  - Flutter `Icons` in the outlined style: 24dp in rows, 18dp in `StatusLine`. Color them `onSurfaceVariant` unless they show a status.
  - Use icons only for navigation, item type, status and app bar actions. Every icon-only button has a `tooltip`.

## 13. Review checklist

1. Does the first row below the app bar answer the screen's question, with no greeting, hero or stat tiles above it?
2. Is the widget code free of `Colors.*`, hex literals, `fromSeed`, gradients, `BackdropFilter` and `BoxShadow`?
3. Is every string free of emoji, including notifications and test fixtures?
4. Is there at most one `Card` (no card per row, no nested cards) and at most one `FilledButton`?
5. Is every status shown as icon plus words through `StatusLine` or `StatusTag`, never as a colored dot, stripe or tint alone?
6. Does the screen render in both light and dark, using only `colorScheme` and `StatusColors` roles?
7. Do times, counts, percentages and rooms use `.tnum`? Are times 24-hour, in device time, and formatted by `lib/ui/format/`?
8. Are courses named, never shown by code?
9. Does the screen work at `textScaler` 2.0 without clipping? Are all targets at least 48dp, and do all icon buttons have tooltips?
10. Were all states built: first load with no cache, cached while refreshing, empty, stale, one service failed, offline, signed out?
11. Is there never a blank screen, a full-screen spinner, or raw exception text?
12. Does every error row name the service, show the age of the data, and offer an action?
13. Does pull to refresh work even on a short list?
14. Is the copy free of exclamation marks and of the banned words in section 10?
15. Do absence counts and limits come from data, never invented or hardcoded?
16. Do mocks and screenshots use realistic names, rooms and times?
17. Is there no motion beyond the M3 defaults, and is `disableAnimations` respected?

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
