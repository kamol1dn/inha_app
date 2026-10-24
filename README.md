# IUT

An Android app for students of Inha University in Tashkent. It answers the three things a student checks
between classes: where the next class is, what is due, and whether attendance is in trouble. It also reads
grades and university mail.

| Screen | What it shows | Source |
|---|---|---|
| Today | Next class and room, what needs attention in the next 3 days, unread mail | All of the below |
| Schedule | The week's classes, one day at a time | EduPage timetable |
| Deadlines | Assignments, quizzes and VOD watch windows, with "Open in eClass" | eClass |
| Courses | Absences against the limit you set, VOD progress, the INS grade | eClass, INS |
| Grades | GPA, credits and every course by term | INS |
| Mail | The inbox; messages open, and opening one marks it read | University Exchange mail |
| Exams | Your midterm or final exams: when, and the rooms each uses until you set yours (on Today, Schedule and course detail too) | The university's exam timetable PDF, bundled (`docs/EXAMS.md`) |

Reminders (deadlines, VOD windows, new absences, classes) come as notifications, each switchable in Settings,
with quiet hours from 23:00 to 07:30.

Three home-screen widgets (Up next, Today, Attendance) show the same answers without opening the app, and on
Android 16 the app offers read-only AppFunctions so an assistant such as Gemini can answer "where is my next
class?" (`docs/WIDGETS.md`, `docs/APPFUNCTIONS.md`).

## It only talks to IUT

The app has no server of its own and sends nothing anywhere else: no analytics, no crash reporting. It
connects directly to:

- `iut.edupage.org` (the public timetable; no login),
- `eclass.inha.ac.kr` (form login, then the pages a browser would load),
- `ins.inha.uz` (form login, grades),
- `mail.inha.uz` (Exchange Web Services with Basic auth over HTTPS).

The two typefaces, Fraunces and Public Sans (both under the SIL Open Font License), are bundled in the app;
nothing is downloaded at run time. So are the exam timetables: no IUT service publishes them, so each PDF the
university posts is read into `assets/exams/` and ships with the next version of the app. The per-student room
list is not bundled (it names every student); you set your own room in the app.

One exception is the student's choice, not the app's: when they ask an assistant such as Gemini about their
classes, Android hands it the answer of one of the app's AppFunctions, and Gemini may process that on Google's
servers. Those answers carry only what the question needs (no mail, logins, name or student ID); see
`docs/APPFUNCTIONS.md`.

Logins are typed only in the app's Settings and kept in Android's encrypted storage on the phone; each password
is sent only to the service it belongs to. `ins.inha.uz` still serves a certificate that expired on 2024-11-16;
the app accepts that one certificate, pinned by its SHA-256, and nothing else (see `docs/ENDPOINTS.md`).

## Building

Needs Flutter 3.47 with JDK 21 and the Android SDK (on the development laptop these live in
`D:\ProgramFiles`; `docs/ROADMAP.md` lists the environment variables).

```
flutter pub get
flutter analyze
flutter test
flutter run -d <device>
```

The Android side has JVM unit tests of its own: after a first `flutter build apk --debug` (which creates the
Gradle wrapper), `cd android && ./gradlew :app:testDebugUnitTest`. The app compiles against Android SDK
platform 37 (the AppFunctions library needs it); install it with the SDK manager if Gradle asks.

### Release APK

A release build is signed with a keystore that is kept outside the repository. Create
`android/key.properties` (git-ignored) pointing at it:

```
storeFile=C:/path/outside/the/repo/iut-release.jks
storePassword=...
keyAlias=iut
keyPassword=...
```

Then `flutter build apk --release --split-per-abi` and copy `build/app/outputs/flutter-apk/app-arm64-v8a-release.apk`
(about 20 MB; nearly every current phone is arm64) to the phone and install it (Android asks to allow installs from
that source once). Plain `flutter build apk --release` makes one 55 MB APK for every CPU instead. Stick to one
kind: a split APK's version code is 2001 for 1.0.0+1, so a universal APK (code 1) can't update it. Without `key.properties` the
release build falls back to the debug key, which is fine for testing but cannot update an installed signed copy.

### CI

`.github/workflows/release.yml` runs on every push to `main`, on `v*` tags and by hand (Actions,
"Release APK", Run workflow). It runs `flutter analyze`, `flutter test`, builds
`flutter build apk --release --split-per-abi`, runs the Android unit tests and uploads the APKs as an
artifact; a `v*` tag also attaches them to a GitHub release.

It signs with the same keystore as a local release build, read from four repository secrets. Set them
once from Git Bash in the repository (each `gh secret set` without `--body` asks for the value, so no
password lands in the shell history):

```
base64 -w0 /c/Users/User/.android/iut-release.jks | gh secret set IUT_KEYSTORE_BASE64
gh secret set IUT_KEYSTORE_PASSWORD
gh secret set IUT_KEY_ALIAS --body iut
gh secret set IUT_KEY_PASSWORD
```

Without them a branch build still runs, but its APK is signed with a debug key (the artifact name ends
in `-debug-key`) and cannot update the signed app on the phone; a tag build fails instead.

## Repository

| Path | What |
|---|---|
| `lib/services/` | One client per site: HTTP, login, parsers |
| `lib/data/` | `AppData`: cached data per source, refresh, the rules that decide what is urgent |
| `lib/features/` | Screens |
| `lib/notifications/` | Reminder rules (pure), the notifier, the WorkManager background refresh, the widget update hook |
| `android/app/src/main/kotlin/` | The Android side: `campus/` reads the app's cache with the app's rules, `widget/` the home-screen widgets (Glance), `appfunctions/` the AppFunctions; JVM tests in `android/app/src/test/` |
| `lib/ui/` | Theme (colours, type, status tones) and the one formatter for times and dates |
| `assets/fonts/` | The bundled fonts and their OFL licences |
| `tool/` | `make_fonts.py` cuts the fonts from the upstream variable files; `make_icons.py` draws the icons and splash; `exam_timetable.py` reads an exam timetable PDF into `assets/exams/` |
| `assets/exams/` | The exam timetables, one JSON file per exam week |
| `DESIGN.md` | The design guide every screen follows |
| `docs/ENDPOINTS.md` | What each site exposes and how the app reads it |
| `docs/NOTIFICATIONS.md` | Which reminders go out, when, and why |
| `docs/WIDGETS.md` | The home-screen widgets: what they show, how they refresh, how to test |
| `docs/APPFUNCTIONS.md` | The Gemini AppFunctions: what is exposed, availability, how to test |
| `docs/EXAMS.md` | The exam timetables: where they come from, adding the next one, matching them to your courses |
| `docs/ROADMAP.md` | What is done and what is next |

Tests run against anonymized copies of real pages in `test/fixtures/`. Real pages, which carry personal data,
belong in `test/fixtures/private/`, which git ignores; nothing personal is committed.
