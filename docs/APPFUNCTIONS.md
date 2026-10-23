# Gemini AppFunctions

Five read-only functions that let an agent such as Gemini answer questions about the student's
classes, deadlines, attendance and grades without opening the app. Code:
`android/app/src/main/kotlin/uz/inha/kamol1dn/inha_app/appfunctions/`.

## Availability (as of October 2026)

- **Android 16 or newer.** The platform API (`android.app.appfunctions`) exists from Android 16
  (API 36). On older phones the service is simply not registered; the widgets and the app are
  unaffected.
- **Gemini's use of third-party AppFunctions is a preview.** It runs on the Pixel 10 and Galaxy
  S26 in the US and Korea, and Google has said wider rollout comes with Android 17. Google's own
  page calls the Gemini integration a private preview with trusted testers, and says only a
  limited number of apps can use the full pipeline, so a phone that supports AppFunctions may
  still not route this app's functions to Gemini.
- **The library is beta.** `androidx.appfunctions` 1.0.0-beta01 (21 October 2026); the API may
  still change. It needs compileSdk 37, so `android/app/build.gradle.kts` sets `compileSdk = 37`
  (targetSdk stays Flutter's).
- **`adb shell cmd app_function` needs Android 16 QPR2 (API 36.1) or newer.** The first Android
  16 emulator image (BE2A.250530, the one with the student's logins) has the `app_function`
  service but answers "No shell command implementation". Testing used a second emulator on the
  36.1 image (below).

## What is exposed

| Function | Parameters | Returns |
|---|---|---|
| `getNextClass` | none | The class in progress or the next one within 7 days: course, room, start, end, kind, teacher, whether it is in progress, the course's attendance warning if any. Plus when the timetable was fetched |
| `getSchedule` | `day: LocalDate?` (null = today) | That day's classes in time order, same fields |
| `getUpcomingDeadlines` | `withinDays: Int = 7` (1 to 120) | Open eClass items due in that window, overdue ones (under 24 h) first: tidied title, course, kind, due time, overdue, urgency (`danger`/`warning`/`normal`), what is left (`Not submitted`, `62% watched`) |
| `getAttendance` | `course: String?` (part of a name; null = all) | Per course: absences, lates, the limit the student set (null when unset), absences left, status (`over limit`, `at limit`, `warning`, `ok`, `limit not set`, `no attendance record`), videos watched of total, next class |
| `getGradesSummary` | none | GPA (of 4.5), credits earned, year of study, the latest graded term's courses and letters, courses not graded yet |

Every result carries the time its source was last fetched, so the agent can say "as of 08:41".
The same rules as the app and the widgets apply (they share `campus/`): class periods aren't
deadlines, submitted or watched items are left out, no absence limit is ever guessed, courses are
named, never coded.

**Left out on purpose.** Gemini may process results on Google's servers, so the functions return
only what answers the question: no mail (subjects, senders or bodies), no credentials or session
cookies, no student name or ID, no course codes, no INS category codes, no professor of eClass
courses beyond the public timetable's teacher. Nothing is written, nothing is fetched: the
functions read the cache the app keeps and never go online or sign in.

**Errors** are AppFunction exceptions with a next step the agent can relay:
`AppFunctionElementNotFoundException` when data is missing ("The user isn't signed in to eClass.
Ask them to sign in in the IUT app's Settings.", "The timetable hasn't been loaded yet...") or
when no course matches (the message lists the course names), and
`AppFunctionInvalidArgumentException` for `withinDays` outside 1 to 120.

## How it is built

- `BaseCampusAppFunctionService` is annotated `@AppFunctionServiceEntryPoint`; each function is
  `@AppFunctionDeclaration(isDescribedByKDoc = true)`, so its KDoc becomes the description the
  agent reads. Result classes (`Results.kt`) are `@AppFunctionSerializable` with KDoc on every
  property (KSP ignores class-level `@property` tags).
- KSP (`com.google.devtools.ksp` 2.3.12, `appfunctions-compiler`, with
  `appfunctions:aggregateAppFunctions=true`) generates `CampusAppFunctionService` and
  `assets/campus_app_functions.xml`. The manifest declares the service with
  `BIND_APP_FUNCTION_SERVICE`, the schema properties and `res/xml/app_metadata.xml` (the
  app-level `instructions` the agent reads first).
- `CampusFunctions.kt` holds the answers as pure code over `Campus` and a clock; the service only
  reads the cache on `Dispatchers.IO` and maps its two exceptions.

## Testing

Unit tests: `cd android && ./gradlew :app:testDebugUnitTest` (includes `CampusFunctionsTest`).

On a device or emulator with Android 16 QPR2+:

```
adb shell cmd app_function list-app-functions | grep -A3 inha_app
adb shell cmd app_function execute-app-function --package uz.inha.kamol1dn.inha_app --function 'uz.inha.kamol1dn.inha_app.appfunctions.CampusAppFunctionService#getNextClass' --parameters '{}'
adb shell cmd app_function execute-app-function --package uz.inha.kamol1dn.inha_app --function 'uz.inha.kamol1dn.inha_app.appfunctions.CampusAppFunctionService#getSchedule' --parameters '{"day":"2026-10-26"}'
adb shell cmd app_function execute-app-function --package uz.inha.kamol1dn.inha_app --function 'uz.inha.kamol1dn.inha_app.appfunctions.CampusAppFunctionService#getUpcomingDeadlines' --parameters '{"withinDays":7}'
adb shell cmd app_function execute-app-function --package uz.inha.kamol1dn.inha_app --function 'uz.inha.kamol1dn.inha_app.appfunctions.CampusAppFunctionService#getAttendance' --parameters '{"course":"multimedia"}'
adb shell cmd app_function execute-app-function --package uz.inha.kamol1dn.inha_app --function 'uz.inha.kamol1dn.inha_app.appfunctions.CampusAppFunctionService#getGradesSummary' --parameters '{}'
```

Add `--brief-yaml` for shorter output. `adb shell cmd app_function help` lists the rest
(`set-enabled` turns one off for testing).
