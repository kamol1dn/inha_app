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

Reminders (deadlines, VOD windows, new absences, classes) come as notifications, each switchable in Settings,
with quiet hours from 23:00 to 07:30.

## It only talks to IUT

The app has no server of its own and sends nothing anywhere else: no analytics, no crash reporting. It
connects directly to:

- `iut.edupage.org` (the public timetable; no login),
- `eclass.inha.ac.kr` (form login, then the pages a browser would load),
- `ins.inha.uz` (form login, grades),
- `mail.inha.uz` (Exchange Web Services with Basic auth over HTTPS).

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

## Repository

| Path | What |
|---|---|
| `lib/services/` | One client per site: HTTP, login, parsers |
| `lib/data/` | `AppData`: cached data per source, refresh, the rules that decide what is urgent |
| `lib/features/` | Screens |
| `lib/notifications/` | Reminder rules (pure), the notifier, the WorkManager background refresh |
| `DESIGN.md` | The design guide every screen follows |
| `docs/ENDPOINTS.md` | What each site exposes and how the app reads it |
| `docs/NOTIFICATIONS.md` | Which reminders go out, when, and why |
| `docs/ROADMAP.md` | What is done and what is next |

Tests run against anonymized copies of real pages in `test/fixtures/`. Real pages, which carry personal data,
belong in `test/fixtures/private/`, which git ignores; nothing personal is committed.
