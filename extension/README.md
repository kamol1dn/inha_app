# IUT for eClass (browser extension)

A browser extension (Chrome, and Zen or Firefox) that gives eClass the app's look and puts the app's features where they fit in
eClass's own layout:

| Where | What |
|---|---|
| Sign-in page | Redone: **Continue as &lt;ID&gt;** with the saved login, or the form, which remembers a new one once eClass accepts it |
| Left menu | An IUT section: Today, Schedule, Deadlines, Attendance, Grades, Mail, Exams, Settings. Each opens as an eClass page (`/#/mail/inbox`) |
| Course list | At the right of each course, in columns: absences (tally), VODs watched, the eClass score, the INS grade, the next thing due. In a narrower row the next thing due goes, and narrower still the facts move under the course's name |
| Right column | Today (next class and room, or exam), Due soon, unread Mail, above eClass's blocks. Each says when its service failed, and marks data that is old |
| Course page | Absences, VODs, the eClass score, grade and what's due, above eClass's content |
| Assignment, quiz, VOD | How long is left, or that it's done |

The full views (mail with search, compose and reply, and files to attach; grades, schedule, deadlines, exams, settings) open in
eClass's content area, under its header and beside its menu, in a frame of the extension's own page. The toolbar button shows the same views, Today first, with tabs at its foot; Settings opens in a tab, since a file or password dialog would close the popup. Reminders follow the app's rules
(`docs/NOTIFICATIONS.md`), plus new-mail notifications, each switchable in Settings.

## Install

Every `v*` release on GitHub has two builds, next to the APKs. Neither browser updates them by itself: to update, install the newer
one the same way. Logins and settings stay, since each build keeps one fixed ID.

**Chrome.** The extension isn't in the Chrome Web Store, so it loads from a folder:

1. Download `iut-eclass-chrome-<version>.zip` and unzip it into a folder you will keep, such as `Documents/iut-eclass`. Chrome reads the
   extension from that folder every time it starts, so deleting the folder removes it.
2. Open `chrome://extensions` and turn on **Developer mode**, at the top right.
3. Press **Load unpacked** and pick the folder that holds `manifest.json`.

To update, unzip the new zip over the same folder, press the reload icon on the extension's card, and reload any open eClass tab. If
Chrome asks at startup to turn off developer-mode extensions, say no. The manifest's `key` keeps the ID fixed (`feadfmhjcfeploeapmephijhhmkcolbn`), so
loading a newer copy from another folder replaces the old one instead of adding a second that posts every notification again. Only the
public half of that key exists in the repository; Chrome needs no more for an unpacked install. A copy loaded before the `key` was added has another ID: remove it, and save the logins again.

**Zen or Firefox** (128 or newer):

1. Download `iut-eclass-zen-firefox-<version>.xpi`.
2. Open `about:addons`, press the gear, choose **Install Add-on From File** and pick it, then **Add**.
3. Zen may ask to allow the four sites. If they are off, Settings shows "Allow access", and a source that can't load says so instead
   of blaming the connection.

**A file ending in `-unsigned-temporary.xpi`** means Mozilla didn't sign that build (the release says so too), and Zen and Firefox
refuse to install it for good. It loads only as a temporary add-on, gone when the browser restarts: `about:debugging#/runtime/this-firefox`,
**Load Temporary Add-on**, pick the file. Take a signed build from another release if there is one.

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

Saved in Settings (or by ticking "Remember" on the sign-in page, once eClass has accepted it). The password is encrypted with
AES-GCM under a non-extractable key kept in the extension's IndexedDB (`src/core/vault.ts`), never
synced, and readable only by the extension's worker and pages; each one is sent only to its own
service. Like the app, the extension talks to nothing but eclass.inha.ac.kr, ins.inha.uz,
mail.inha.uz and iut.edupage.org.

**What eClass's page can see.** eClass runs its own scripts, Google's tag among them, so the password fields of Settings and the mail
reader are never in its document: inside eClass the views are the extension's own page (`pages/app.html?frame=inline`) in a frame
(`src/content/view.tsx`), which those scripts can't read into. The frame tells the page only its route and title, and a mail message's
id stays out of eClass's address. The parts added to the page itself, a mail's subject in the side block among them, sit in closed
shadow roots. The one password typed on eClass's document is eClass's own, on its sign-in page.

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

Needs Node 24 (the tests and `manifest.ts` in the build run TypeScript directly).

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
script instead of a service worker, a fixed add-on ID, Firefox 128 or newer, no Chrome `key`). `npm run lint:firefox`
runs Mozilla's checks on it.

- **To try it:** `about:debugging#/runtime/this-firefox` → Load Temporary Add-on → pick
  `dist-firefox/manifest.json`. It stays until the browser restarts.
- INS: Firefox keeps "Accept the risk" for INS's expired certificate as a lasting exception, so after
  doing that once in a tab, the background sync may reach INS directly.

## Releases

The tests run the ported parsers against the app's anonymized fixtures in `../test/fixtures`.
CI (`.github/workflows/extension.yml`) builds and tests on every push that touches the extension. A `v*` tag does the following:

1. Its number becomes the version of both builds (`v1.4.0` gives `1.4.0`), whatever `static/manifest.json` says, so each release has a
   new version for Mozilla to sign.
2. The Chrome `.zip` goes on the tag's GitHub release, the one the APKs go on, before anything else can fail.
3. Mozilla signs the `.xpi`, unlisted (signed, not published), with the repository secrets `AMO_JWT_ISSUER` and `AMO_JWT_SECRET`: an
   API key from addons.mozilla.org → Developer Hub → Manage API Keys. If the secrets are missing or signing fails, the job stays green with a warning and
   attaches `iut-eclass-zen-firefox-<version>-unsigned-temporary.xpi` instead. Running the same tag again reuses the signed file already on the release.
4. The release's text gets the install steps above.

## Layout

| Path | What |
|---|---|
| `src/services/` | eClass, INS, EduPage and Exchange clients: ports of `lib/services/` |
| `src/data/` | Urgency, absences, exams, scores, notification rules, formatting: ports of `lib/data/` and `lib/notifications/rules.dart` |
| `src/background/` | The service worker: sync, notifications, and the calls pages make |
| `src/content/` | What runs on eClass (`eclass.tsx`, `parts.tsx`, `signin.tsx`, `view.tsx`, `moodle.css`) and INS |
| `src/ui/` | The views: the extension's own page, as the frame inside eClass, the popup and a tab |
| `manifest.ts` | The manifest each browser gets, from `static/manifest.json` |
