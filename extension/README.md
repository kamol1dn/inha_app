# IUT for eClass (browser extension)

A browser extension (Chrome, and Zen or Firefox) that gives eClass the app's look and puts the app's features where they fit in
eClass's own layout:

| Where | What |
|---|---|
| Sign-in page | Redone: **Continue as &lt;ID&gt;** with the saved login, or the form, which can remember a new one |
| Left menu | An IUT section: Today, Schedule, Deadlines, Attendance, Grades, Mail, Exams, Settings. Each opens as an eClass page (`/#/mail/inbox`) |
| Course list | At the right of each course, in columns: absences (tally), VODs watched, the eClass score, the INS grade, the next thing due |
| Right column | Today (next class and room, or exam), Due soon, unread Mail, above eClass's blocks |
| Course page | Absences, VODs, the eClass score, grade and what's due, above eClass's content |
| Assignment, quiz, VOD | How long is left, or that it's done |

The full views (mail with search, compose and reply, and files to attach; grades, schedule, deadlines, exams, settings) open in
eClass's content area, under its header and beside its menu. The toolbar button shows Today. Reminders follow the app's rules
(`docs/NOTIFICATIONS.md`), plus new-mail notifications, each switchable in Settings.

**Scores** (`/#/grades/<course>`, also listed under "Scores this semester" in Grades) are a course's marks from eClass, as in the app
(`DESIGN.md`, Scores): the total, each category with its weight, and what-if numbers on the rows still open, which are never saved.
Where a professor closed the grades page, the assignment and quiz lists give the marks, without a total. "Grade" stays the INS letter.
A new or changed mark notifies once, under the Grades switch.

**Theme.** Settings' System, Light or Dark applies to the popup, the views and eClass's own pages. `src/content/theme.ts` puts the tokens
on eClass's document. In the dark, `src/content/darkrules.ts` reads eClass's stylesheets as they load and answers every near-white background
and near-black text with the same selector on the tokens, and `moodle.css` refines what needs more than that, under `html.iut-dark`. Colors a professor set inside their
text give way to the page's ink in the dark. With "New look on eClass" off, eClass stays as it is, light. Content in an iframe (the VOD
player, an embedded editor) isn't restyled, since the content script runs only in the top frame.

## Logins

Saved in Settings (or by ticking "Remember" on the sign-in page). The password is encrypted with
AES-GCM under a non-extractable key kept in the extension's IndexedDB (`src/core/vault.ts`), never
synced, and readable only by the extension's worker and pages; each one is sent only to its own
service. Like the app, the extension talks to nothing but eclass.inha.ac.kr, ins.inha.uz,
mail.inha.uz and iut.edupage.org.

Saving a login always tries it, even with a live session in the browser. One a service refuses isn't
kept, and the login before it stays. A wrong password counts toward the domain's lockout, so a saved
login that later gets refused is not posted again for a day, unless the student saves a login or presses
Update on that service; a refresh costs at most one failed logon.

**Signing out** ends the browser's eClass session too and forgets that account's data and what it was
told. Clicking Log out on eClass stops background logins until the student signs in again by hand. If
someone else signs in to eClass in this browser while a login is saved, their session isn't read.

**INS** still serves a certificate that expired in 2024. Browsers refuse it for background requests,
so when the worker can't reach INS, Grades and Settings offer "Open INS": choose Proceed once, and the
extension reads the grades from that tab (`src/content/ins.ts`). The saved password goes only to a
tab the extension opened or one where the student clicked "Read my grades", never to a page just
because its address says `#iut-sync`: that certificate can't tell the real INS from a fake.

## Building

Needs Node 24 (the tests run TypeScript directly).

```
npm ci
npm run typecheck
npm test
npm run build        # dist/, what Chrome loads
npm run build:dev    # the same, plus a reload hook for testing from an eClass page
```

Load it in Chrome: `chrome://extensions` → Developer mode → Load unpacked → `extension/dist`. After a rebuild, press the reload icon
on its card there, then reload any open eClass tab.

## Zen and Firefox

`npm run build:firefox` writes `dist-firefox/`: the same code, with Firefox's manifest (a background
script instead of a service worker, a fixed add-on ID, Firefox 128 or newer). `npm run lint:firefox`
runs Mozilla's checks on it.

- **To try it:** `about:debugging#/runtime/this-firefox` → Load Temporary Add-on → pick
  `dist-firefox/manifest.json` (or the `.xpi` from CI). It stays until the browser restarts.
- **To keep it:** Firefox and Zen install only add-ons Mozilla has signed. Signing is free for an
  unlisted add-on (signed, not published): create an API key at addons.mozilla.org → Developer Hub →
  Manage API Keys and save it as the repository secrets `AMO_JWT_ISSUER` and `AMO_JWT_SECRET`. Then a
  `v*` tag gets a signed `.xpi` on the release, which installs by opening it in Zen. Mozilla signs a
  version once, so bump `version` in `static/manifest.json` for each release.
- Zen may ask to allow the four sites. If they are off, Settings shows "Allow access", and a source that can't
  load says so instead of blaming the connection.
- INS: Firefox keeps "Accept the risk" for INS's expired certificate as a lasting exception, so after
  doing that once in a tab, the background sync may reach INS directly.

The tests run the ported parsers against the app's anonymized fixtures in `../test/fixtures`.
CI (`.github/workflows/extension.yml`) builds and tests on every push that touches the extension
and, for `v*` tags, attaches the Chrome `.zip` and the Zen/Firefox `.xpi` to the release.

## Layout

| Path | What |
|---|---|
| `src/services/` | eClass, INS, EduPage and Exchange clients: ports of `lib/services/` |
| `src/data/` | Urgency, absences, exams, scores, notification rules, formatting: ports of `lib/data/` and `lib/notifications/rules.dart` |
| `src/background/` | The service worker: sync, notifications, and the calls pages make |
| `src/content/` | What runs on eClass (`eclass.tsx`, `parts.tsx`, `signin.tsx`, `moodle.css`) and INS |
| `src/ui/` | The views, shown inside eClass, in the popup and in a tab |
