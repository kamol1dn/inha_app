# Endpoints

What each service actually exposes, as probed from a logged-in browser. Update this
when a site changes.

## eClass — `https://eclass.inha.ac.kr`

An old Coursemos build of Moodle (theme `coursemosv2`). The Moodle mobile app does
not work against it, and the AJAX web service (`/lib/ajax/service.php`) returns 404
for nearly every function. The only one that answered was
`message_popup_get_popup_notifications`. So the app works like a browser: it posts
the login form, keeps the cookie, and parses HTML.

| What | Request | Notes |
|---|---|---|
| Login | `POST /login/index.php` form: `username`, `password` | No `logintoken`. Success = redirect away from `/login/`, `MoodleSession` cookie set. Failure = the login page again (look for the form / an error box). |
| Session check | `GET /` | Logged out → you land on `/login/index.php`. |
| Courses | `GET /` | Links `a[href*="/course/view.php?id="]`; title text like `Multimedia Computing[202602-SOC4020-001]`, the professor's name is nearby. |
| Upcoming events | `GET /calendar/view.php?view=upcoming` | `.event` items: `.referer` (title, with `a` → `/mod/<type>/view.php?id=<moduleId>` when it is an activity), `.course`, `.date`. The `.date a[href]` links carry `time=<unix seconds>`: one link = due time, two = start and end of a window (VODs). Course-level events have no module link. |
| Class attendance | `GET /local/ubattendance/my_status.php?id=<courseId>` | `table.attendance_my`: Week (date `YYYY-MM-DD`) / Class / Attendance / Absence / Late / Others. The column holding `○` is the mark. A second table fills in by AJAX and is not needed. |
| VOD progress | `GET /report/ubcompletion/user_progress.php?id=<courseId>` | `table.user_progress`: Week / Resources / Contents time / max position / Progress `%`. The Week cell uses `rowspan`, so later rows in a week have one fewer cell. When a course has no progress-managed VODs the page says so and the table is missing; that is not an error. |
| Notifications | `POST /lib/ajax/service.php?sesskey=<M.cfg.sesskey>` body `[{"index":0,"methodname":"message_popup_get_popup_notifications","args":{"useridto":<id>,"newestfirst":true,"limit":20,"offset":0}}]` | `sesskey` is in the page's `M.cfg` JSON. The user id is not; take it from the `/user/edit.php?id=<id>` link on any logged-in page. |

Fixtures: `test/fixtures/private/` holds real pages (git-ignored). `test/fixtures/`
holds anonymized copies that tests use.

## EduPage timetable — `https://iut.edupage.org`

Public, no login. Port of `scripts/pull_timetable.py` from the study repo:

- `POST /timetable/server/ttviewer.js?__func=getTTViewerData` body
  `{"__args":[null,<year>],"__gsh":"00000000"}` → which timetables exist (pick the
  current/default `tt_num`).
- `POST /timetable/server/regulartt.js?__func=regularttGetData` body
  `{"__args":[null,"<tt_num>"],"__gsh":"00000000"}` → the whole university's
  dataset (`r.dbiAccessorRes.tables`: classes, subjects, teachers, classrooms,
  periods, daysdefs, lessons, cards). Filter lessons to the class group, join cards
  for day/period/room.
- With `{}` as the year argument, `default_num` comes back blank, so the client
  falls back to the newest visible timetable (145 for Fall 2026). Passing the
  year (`2026`) fills `default_num` in.

## INS — `https://ins.inha.uz`

"ITIS", an ASP.NET WebForms app inside a frameset.

**Certificate: expired.** `https://ins.inha.uz` serves `CN=*.inha.uz` (RapidSSL TLS
RSA CA G1), valid 2023-11-16 to **2024-11-16**, SHA-256
`C6:57:E8:B7:5A:4C:6D:D1:C3:35:8B:38:A5:16:D3:07:C1:2F:A0:24:5E:02:55:6B:25:AD:CE:0B:83:DF:7C:A0`.
Android rejects it, so `lib/core/session.dart` pins this exact certificate for
`ins.inha.uz` only (`pinnedExpiredCerts`, approved by the user 2026-10-22).
Normal validation runs first, so a renewed certificate needs no change; remove the
pin once it is renewed. Checked live: INS 200, `expired.badssl.com` still rejected.
Plain `http://` answers 200 but would send the password unencrypted, so don't use it.

**Login**
1. `GET /ITIS/Start.aspx` → read hidden inputs `__VIEWSTATE`, `__VIEWSTATEGENERATOR`,
   `__EVENTVALIDATION` (plus the other hidden inputs in `form1`; send them all back).
2. `POST /ITIS/Start.aspx` form-urlencoded: all hidden inputs, `txtInhaID` = student
   ID **uppercased**, `txtPW` = password in plain text, `btnLogin` = `` (the submit
   button's name must be present for WebForms to fire the click). The page loads
   an RSA library (`enc_login.js`) but the login never calls it.
3. Success → the response sends the browser to `/ITIS/FRAMESET.htm` (frames
   `top.aspx`, `left.aspx`, `main.aspx`). Failure → `Start.aspx` again with the hidden
   `errorMessage` input filled in.

**Grades** ("View Grades and Standings")
1. `GET /ITIS/left.aspx` → menu links are `main.aspx?param=<encrypted>&ENGYN=Y|N`. The
   param is opaque; find the link whose text is `View Grades and Standings` and
   follow it (don't hardcode it).
2. That leads to `/ITIS/STD/SJ/SJ_51001/MarkView.aspx`, which iframes
   `MarkView_rpx.aspx?gubun=inform`. The **raw** rpx page (about 3 KB) calls
   `ViewerReportInForm("HJ_03507_R01.rpx","MarkView_xml.aspx?Value=<token>%3d",...)`.
   The second argument, relative to the rpx page, is the XML URL. (In a live
   browser DOM the Cabsoft viewer has already turned it into
   `window.frm.fileurl.value = '...%253d'`; don't document from the DOM again.)
   GET and POST of the URL as written both return the XML.
   The server sometimes redirects to its internal name `http://ins.iutdev.ac.kr/...`,
   which doesn't resolve outside IUT; the client pins every redirect to ins.inha.uz.
3. `POST` that `fileurl` (empty body) → XML, **encoding EUC-KR** (decode bytes
   accordingly), shape:

```xml
<root><MAIN>
  <STNO/> <KNAME/> <JUMIN/>            <!-- student no, name, NATIONAL ID: never read/store/show JUMIN -->
  <DEPT_KNAME>School(...)</DEPT_KNAME> <ENT_DATE>September  1, 2023</ENT_DATE>
  <GRADE>3</GRADE>                     <!-- year of study -->
  <COM_CREDIT>999.9</COM_CREDIT> <SIN_CREDIT>999.9</SIN_CREDIT>   <!-- credits completed / registered -->
  <TOT_JUM>999.99</TOT_JUM>            <!-- total grade points -->
  <COM_PYUNG>9.999999</COM_PYUNG> <SIN_PYUNG>9.999999</SIN_PYUNG> <!-- GPA (cumulative), likely on a 4.5 scale -->
  <TODAYTIME>yyyy-MM-dd HH:mm:ss</TODAYTIME>
  ... per-category credit totals (KYOPIL, JUNPIL, ...) ...
  <MARK>                               <!-- one per course, ~46 -->
    <STNO/> <GRADE>Freshman|Sophomore|Junior|...|''</GRADE>
    <YEARTERM>20231</YEARTERM> <DISPLAY_YEARTERM>2023 Fall Semester</DISPLAY_YEARTERM>
    <HAKSU_NO>SOC4020</HAKSU_NO> <KWAMOK_KNAME>Course name</KWAMOK_KNAME>
    <CREDIT>3.0</CREDIT> <MARKS>A+|A0|B+|...|-</MARKS> <JUMSU>4.50</JUMSU>
    <JONG_AKNAME>MR-M</JONG_AKNAME>    <!-- course category -->
    <REG_GUBUN/> <RHAKSU_NO/> <SEASON_YN/> <HONOR/> <DEPT_TREE/> <MAJOR_CODE/>
  </MARK>
</MAIN></root>
```

`MARKS` = `-` means not graded yet (the current semester shows up that way, with a
`DISPLAY_YEARTERM` that is not "YYYY Term Semester").

Other menu items (same left.aspx pattern): Personal Information, Browse Course
Syllabus, Browse Course Timetable, Confirm Course Registration. Not used yet.

## Mail — `https://mail.inha.uz`

On-premises Exchange (OWA at `/owa/`, addresses like `x.surname@student.inha.uz`).
**EWS at `/EWS/Exchange.asmx` accepts Basic auth** (`WWW-Authenticate: Negotiate, NTLM,
Basic`), so the app uses EWS SOAP with `Authorization: Basic` and never touches OWA:

- `FindItem` on `distinguishedFolderId inbox`, `IndexedPageItemView` (MaxEntriesReturned
  30, offset 0), shape `IdOnly` + additional properties `item:Subject`,
  `message:From`, `item:DateTimeReceived`, `message:IsRead`, `item:Preview` (Exchange
  2013+; drop it if the server rejects it).
- `GetItem` with `BodyType Text` for one message, plus `item:Subject`, `message:From`,
  `item:DateTimeReceived`, `message:IsRead` and `item:Attachments` (name, size, `IsInline`;
  no content). GetItem does not change the read flag. Exchange writes HTML links as
  `label<url>` and leaves runs of blank lines and zero-width padding in the text body.
- `UpdateItem` `SetItemField message:IsRead` (`MessageDisposition="SaveOnly"`,
  `ConflictResolution="AlwaysOverwrite"`, no ChangeKey) marks a message read or unread.
  `SuppressReadReceipts="true"` (Exchange 2013 schema) so opening a message never sends a
  read receipt for the student. Checked live: the flag shows up in the next `GetFolder`.
- `GetFolder` inbox → `UnreadCount` for the badge.
- Paging: `IndexedPageItemView` `Offset` = messages already loaded; a page shorter than
  `MaxEntriesReturned` is the last one.
- Username: the **student ID**, not the email address (confirmed by the student;
  the OWA logon page asks for "user name", Exchange 2019 / 15.2.1544, so a default
  domain is configured). Sent exactly as saved, one attempt only, so a wrong
  password costs one failed logon toward any lockout.
- 401 → wrong credentials → `LoginRequired(Service.mail)`.

ActiveSync (`/Microsoft-Server-ActiveSync`) also answers with Basic, but EWS is simpler.
