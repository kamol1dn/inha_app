# Roadmap

Status as of 2026-10-23, branch `v2` (commits `8445505`, `d87fabb`). Milestone 2 has
two phases, in this order: **A. finish the functionality**, then **B. overhaul the UI**.
Don't start B until A is done and checked on the emulator against the live services.

## Done (milestone 1)

| Area | State |
|---|---|
| Toolchain | Flutter 3.47.7, JDK 21, Android SDK in `D:\ProgramFiles`; emulator `Pixel_8_API_36` (Android 16) |
| Timetable | EduPage public API, matches `scripts/pull_timetable.py` for all 82 groups |
| eClass | Form login, upcoming events (deadlines, VOD windows, class periods), class attendance, VOD progress |
| INS | WebForms login, grades XML (GPA, credits, every course by term); pins the expired `*.inha.uz` cert |
| Mail | EWS with Basic auth as `INHA\<student id>`; inbox list with preview |
| Screens | Today, Schedule, Deadlines (with filters), Courses (+ detail), Grades, Mail list, Settings (logins) |
| Data | Per-service cache, errors shown per source, logins in Android encrypted storage |
| Notifications | Rules, notifier, WorkManager refresh every ~3 h, permission prompt; checked on the emulator |
| Tests | 170, all passing (`flutter test`) |

All four services load real data on the emulator.

## Phase A: functionality

Roughly in priority order. Each item is done when it works on the emulator against the
live site and has tests for its logic.

1. **Mail can be read.** Tapping a message opens it: sender, time, subject, plain-text
   body (`EwsClient.body` already exists), and links that open. Opening marks it read
   (new `MailApi.markRead`, an EWS `UpdateItem` on `message:IsRead`). The unread badge
   uses `GetFolder` `UnreadCount`. Load more on scroll (`offset`). Attachments: list
   names and sizes; opening them can wait.
2. **Everything that looks tappable does something.** Today: unread mail rows open that
   message, deadline rows open the item, the next-class card opens Schedule. Deadlines:
   a row opens a detail sheet (title, course, window or due time, watch progress, and an
   **Open in eClass** button for `/mod/<type>/view.php?id=<moduleId>` through
   `url_launcher`). Schedule: a lesson opens its course. Courses detail: show that
   course's deadlines and its INS grade. Audit every row; nothing tappable-looking may be dead.
3. **Notifications.**
   - **First-run flood.** A first install posted 9 "Marked absent" notifications at once (one
     per absence in the last 21 days). The first sync must record existing absences
     silently, or post one summary, and announce only absences that appear later.
   - **Tapping** a notification opens the item. The payload is the notification key; route it.
   - **Settings** get a toggle per channel (deadlines, VOD windows, attendance, classes).
   - **Quiet hours** 23:00–07:30 (DESIGN.md 11).
4. **Settings: "Save and test".** Saving a login runs that service's login right away and
   shows the result inline ("Signed in" / "eClass rejected this username or password").
   Each account row shows its status ("Signed in · checked 08:41", "Sign-in expired", "Not set
   up"). Signing out also clears that service's cache and cookies.
5. **Absence limits.** No source publishes them, so Settings → Courses lets the student
   set the allowed absences per course. With a limit set, Courses and Today show
   "3 of 4 used" with the status colours and the bar from DESIGN.md 8; without one, the
   raw counts stay.
6. **Submitted assignments.** Read the submission status from the assignment's own page
   (`/mod/assign/view.php?id=`) so submitted work leaves Needs attention and stops reminding.
   Same for a finished quiz attempt.
7. **Cleanups.** Remove the debug-only INS page-shape logging (`InsClient._debugShape`)
   once INS has been stable for a few days. Delete `lib/services/pending.dart` if nothing
   uses it. Replace the template `README.md` with a real one (what it is, how to build,
   that it only talks to IUT services directly).
8. **Release build on the phone.** A signed release APK the student installs on their
   Android phone (keystore outside the repo, path in `android/key.properties`, git-ignored).
   App name "IUT", a real launcher icon and a monochrome notification icon
   (`ic_stat_notify`, see docs/NOTIFICATIONS.md §5). Verify the release build fetches
   (INTERNET permission is in the main manifest) and that R8 keeps what the plugins need.

Nice to have, if time allows: the exam schedule (the student's Telegram bot
`D:\coding\inha_timetable` already parses the Fall 2026 exam PDFs), eClass announcements,
and a home-screen widget for the next class.

## Phase B: UI overhaul

The student's verdict on the current UI: **it looks generic**. DESIGN.md was followed, but
following a restraint-first guide literally produced a plain Material list app. Phase B
keeps what is right about the guide (answer first, honest data, status as icon and words, no
slop) and gives the app an identity.

1. **Explore before building.** Make 2–3 distinct visual directions for Today and one
   other screen (static mockups or a throwaway Flutter branch, rendered with real-looking
   IUT data, never invented). Show them to the student and let them pick. Things to vary: typeface
   (the guide chose system Roboto; reconsider a characterful but legible face via
   `google_fonts`), how the next class is presented, density, how colour carries status,
   iconography.
2. **Update DESIGN.md** to the chosen direction before implementing it, so the guide and
   the app stay in step.
3. **Implement across every screen**, including the empty, loading, stale, error and
   offline states and dark mode. Run DESIGN.md's review checklist on each screen.
4. **App icon and splash** to match.

## How to work on this

- **Repo:** `D:\coding\inha_app`, branch `v2`. Commit in small steps. Never add a Claude
  co-author line. Don't push without the student's OK.
- **Never commit personal data.** Real eClass pages live in `test/fixtures/private/`
  (git-ignored); committed fixtures are anonymized or synthetic. Before committing, grep the
  staged files for the student's name and ID.
- **Toolchain:** in Bash, `export PATH="/d/ProgramFiles/flutter/bin:$PATH"
  JAVA_HOME=/d/ProgramFiles/jdk-21 ANDROID_HOME=/d/ProgramFiles/Android/Sdk`. `adb` is
  `/d/ProgramFiles/Android/Sdk/platform-tools/adb`.
- **Emulator:** `Pixel_8_API_36`, AVDs in `D:\ProgramFiles\Android\avd`. Start it with
  `emulator -avd Pixel_8_API_36 -no-boot-anim -no-snapshot-save` if it isn't running
  (`adb devices` shows `emulator-5554`). The student's logins are already saved in the
  app on it. The app's own Settings is the only place they are typed, by the student.
- **Hot reload:** run `flutter run` in the background with its stdin fed from a file:
  `tail -f cmd.txt | flutter run -d emulator-5554 --no-pub 2>&1 | tee run.log`, then
  `echo r >> cmd.txt` reloads in about 1 s (`R` restarts, `q` quits). A full rebuild is
  only needed for Android-side changes (manifest, Gradle, new plugins). First Gradle
  builds are slow on this laptop in silent mode; incremental ones take 1–3 min.
- **Gotchas already solved:** `kotlin.incremental=false` (project on D:, pub cache on
  C:); NDK 28.2 had to be installed by hand (`android sdk install ndk/28.2.13676358`);
  `TestWidgetsFlutterBinding` replaces HttpClient with a fake that returns 400, so live
  checks must not initialise it.
- **Endpoints:** everything known about each site is in `docs/ENDPOINTS.md`. Trace a real
  request in the student's Chrome (Claude in Chrome) before guessing; remember a live
  DOM can differ from the raw page (INS's report viewer did).
- **Checks:** `flutter analyze` and `flutter test` must stay clean. Screenshot the
  emulator with `adb exec-out screencap -p` to verify UI changes.
- **Copy:** course names, never codes; no exclamation marks or emoji (DESIGN.md 10).
