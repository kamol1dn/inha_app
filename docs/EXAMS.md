# Exams

Code: `lib/data/exams.dart` (pure: the sheet, reading a cell, matching), `lib/features/exam_rows.dart` (rows, hero,
sheet, room picker), `lib/features/exams_screen.dart` (the exam week). Data: `assets/exams/`. Tool:
`tool/exam_timetable.py`.

Tests: `flutter test test/exams_test.dart` (the bundled sheets and the matching), plus the `exams` groups in
`test/rail_test.dart` and `test/screens_test.dart`, the room and week formats in `test/format_test.dart`, and the
class reminders in `test/notification_rules_test.dart`. On the Android side, the class-free days in
`CampusTest`, `RulesTest` and `AnswersTest`.

## Where the data comes from

No IUT system serves the exam timetable. The university posts it as a PDF (Telegram, mail): one grid per exam week,
rows of slots (`M-1 90` is Monday's first slot, 90 minutes, `09:30- 11:00`), columns of rooms with their seats
(`A202 35`), and in each cell the course sitting in that room (`(UK) Intro to Data Science (AI 25-01)`,
`Database (Dr.Sarvar)`). A course usually fills several rooms of one slot. Later the university publishes a second
sheet saying which room each student sits in.

The app bundles the first sheet as curated data: subjects and their schedule. `tool/exam_timetable.py` reads the
PDF (the same layout the Telegram bot's extractor in `D:\coding\inha_timetable` reads) into JSON: one entry per slot
and cell, the cell's text as printed, the rooms it fills, the date and times. Reading the cell is the app's job,
where it is tested.

**The app never assigns rooms.** The second sheet, the room list, names every student with their student ID, so it
is left out for the students' privacy (and the repository is public). Each student sets their own room once, from
the exam's sheet ("Set my room"), picking from the rooms that exam uses; it stays on the phone (`exams.rooms.v1`).
Wherever a room isn't set, the app says why: "For your privacy, the app doesn't include anyone's exam room: the
university's room list names every student. Set yours once you know it." Over a list of exams:
"Rooms aren't included, for your privacy: tap an exam to set yours."

**There are no classes in an exam week.** Every day from a period's first exam to its last is class-free, whatever
EduPage lists: Today's rail and attendance rows, Courses' next class, Schedule (`No classes in midterm week, and no
exam of yours on Thu 29 Oct.`), the class reminders, the widgets and the AppFunctions all skip the timetable then.
The app writes those days to prefs (`exams.classFreeDays.v1`, a JSON list of dates) each time it starts, for the
background refresh and the Android side (`Campus.classFree`), which don't read the bundled sheets.

### Adding a sheet (the finals)

1. `pip install pdfplumber`, then
   `python tool/exam_timetable.py "<the PDF>" "Fall 2026" final assets/exams/2026-fall-final.json`.
   It stops if the title has no day range or the first day isn't a Monday.
2. Compare the JSON with the PDF: every slot's time, every cell, every room. Fix a misread by hand; the file is
   curated, and the PDF is the authority.
3. Add the path to `examSheets` in `lib/data/exams.dart`. `test/exams_test.dart` reads every listed sheet; add a
   test with the new sheet's dates and a few sittings.
4. `flutter test`, then release as usual (CI builds the APKs on a push to `main`).

The room list needs nothing from the app: students set their rooms themselves.

### Why bundled, not fetched from GitHub

The README promises the app talks only to IUT. Fetching the JSON from this repository would add GitHub as a host that
sees the phone's address and when it asks. Bundling keeps the promise, works offline from the first launch, and every
sheet passes the tests before it ships. The cost: a new sheet or a correction needs an app update. With rooms set by
each student, that is one release per exam week.

If updates without reinstalling become worth it, the middle path is an opt-in fetch (a switch in Settings, off by
default, named in the README): the app would take a sheet from the repository only if it parses, has the same `id`
as a bundled one or a newer exam week, and passes the same checks as the tests; otherwise it keeps the bundled copy.

## Reading a cell

| Printed | Read as |
|---|---|
| `(UK) …` or a leading `UK ` | The UK programme's sitting (its groups: AI, CS, DS, BM, IT) |
| `(AI 25-01)`, `(IT 26-1/26-3)`, `(AI -DS 25-1)`, `(26-01/03, 26-02/04)` | Groups; the programme and year carry over, and a group without a programme fits any |
| `(SBL)`, `(SOCIE)` | The school: Business and Logistics, or Computer and Information Engineering (CSE, ICE, CIE) |
| `(CSE)`, `(ICE)` | The department |
| `(Dr.Sarvar)` | The teacher |
| `(90min)`, `(90 min)`, `(60)` | The exam's length; it starts with the slot and ends that much later |

The qualifiers (all but the length) are kept as the sitting's note and shown where they tell two sittings apart.

## Matching the student's courses

The student's courses are the timetable's subjects (the dropped ones already left out), each joined with its eClass
course, plus the eClass courses the timetable doesn't have. For each:

1. **Name.** Compared loosely: case, punctuation and `&`/`and` ignored, plurals dropped, `Intro`, `Math`, `Tech` and
   `II` spelled out, and an all-capitals acronym (`PCAD`) read against the course's initials. An exact match first;
   otherwise a prefix either way (`Basic Korean 1` and `Basic Korean 1-Rus`), but only if it points at one course.
2. **Audience.** UK sittings go only to a UK group (a programme the sheet's UK groups name); a UK student whose course
   has a UK sitting gets only that one.
3. **Qualifiers.** Where a course has several sittings, the group, school, department and teacher drop the ones
   that don't fit the class group (Settings → Timetable) and the course's teachers (EduPage's, eClass's professor).
   Sittings that nothing tells apart are all kept, and each says the timetable lists that many.

A course with no sitting is listed under "Not on the timetable" (Mental Education, a course with a project instead).

## Where exams show

A period shows from 21 days before its first exam until its last one ends.

- **Today's rail:** an exam sits at its time, like a class; the next 72 hours, as for deadlines. An exam in progress,
  or the next thing today, is the hero: the room once set, otherwise "Room not set", then the course,
  `Midterm · 1 h · B304(A–C), B305 or B201`.
- **Today's exam section** lists the exams still to come while one of them lies beyond the rail, with
  "Show exam week".
- **Schedule:** each exam-week day's rail has that day's exams and no classes. The app bar has "Exams".
- **The exam week** (`ExamsScreen`): the student's exams by day, the courses without one, and "Show every exam" for
  the whole sheet, to check the matching by hand.
- **Course detail:** a section with the course's sitting, or "No midterm on the timetable for this course."
- **The exam sheet:** the time, the room the student set or the privacy note and the rooms the exam uses with their
  seats, the cell as printed and its slot, "Set my room", and the course.

## Not yet

- Reminders: an "Exams" channel (the evening before, and an hour before with the room) would follow the Classes
  reminder's pattern in `lib/notifications/rules.dart`.
- The home-screen widgets and the AppFunctions (`android/.../campus/`) skip exam-week classes but don't show exams:
  the Kotlin side would need the bundled JSON from the APK's `flutter_assets` and the matching ported, as the rail
  was.
