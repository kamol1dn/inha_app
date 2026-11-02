# IUT for eClass: privacy policy

IUT for eClass is an unofficial extension for students of Inha University in Tashkent. It is not made or endorsed by the university.

## What it sends, and where

The extension has no server of its own. It sends nothing to its developer or to anyone else: no analytics, no crash reports, no tracking.

It connects only to the university's own services, as the student who uses it, over HTTPS:

| Service | What the extension does there |
|---|---|
| `eclass.inha.ac.kr` | Signs in with the student's eClass login and reads their courses, deadlines, attendance, marks and notifications |
| `ins.inha.uz` | Signs in with the student's INS login and reads their grades |
| `mail.inha.uz` | Signs in with the student's university mail login, reads their mail, and sends or saves the messages they write |
| `iut.edupage.org` | Reads the public timetable, with no login |

So the data that leaves the browser is the student's own: their logins, sent only to the service each one belongs to, and the mail they write, sent to the university's mail server. Firefox lists these as "authentication information" and "personal communications" when the extension is installed.

## What it keeps, and where

- **Logins.** A login is saved only when the student saves it, in Settings or by ticking "Remember" on eClass's sign-in page. The password is encrypted with AES-GCM under a key that can't be read back out, kept in the extension's own storage in this browser. It is never synced to other devices.
- **What it has read.** Courses, marks, deadlines, attendance, the timetable and recent mail are kept in the extension's storage in this browser, so the views open at once and work offline.
- **Settings.** Theme, class group, absence limits, notification switches.

Signing out of a service in Settings removes its saved login and the data read from it. Removing the extension removes everything it kept.

## Pages it changes

On `eclass.inha.ac.kr` the extension restyles the page and adds its own parts. Those parts, and the views that show mail and passwords, are kept out of reach of eClass's own scripts: the views run in the extension's own page, in a frame eClass can't read into.

## Contact

Questions and problems: https://github.com/kamol1dn/inha_app/issues

The source code is public: https://github.com/kamol1dn/inha_app
