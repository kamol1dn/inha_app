// The service worker from outside: its RPCs and refreshes against fake sites
// behind a fake fetch, so what is asserted is what eClass, Exchange and INS
// actually get sent. Rejected logins come first: they can lock a university account.
import { beforeEach, describe, test } from 'node:test';
import assert from 'node:assert/strict';
import { fixture } from './setup.ts';
import { browser, installFakeBrowser, rpc, settle, type Answer, type Seen } from './fake_browser.ts';
import type { Deadline } from '../src/core/models.ts';
import { readCache, readState, readSnapshot, writeCache, writeSettings, writeState } from '../src/core/store.ts';
import { markLoginRejected, readLogin, saveLogin } from '../src/core/vault.ts';

installFakeBrowser();
await writeState('edupage', { busy: true, at: Date.now() }); // left by a worker that died
const { refresh, refreshDue, retryLogin, setEclassStop, startOver } = await import('../src/background/sync.ts');
await import('../src/background/index.ts');
await settle();
const busyAfterWaking = (await readState()).edupage?.busy;

const courseIds = [2592, 2615, 2622, 2626, 2634, 2635];
const dashboard = fixture('eclass_dashboard.html');
const loginPage = fixture('eclass_login.html');
const signedIn = (body: string) => `<a href="/login/logout.php?sesskey=TESTSESSKY">Log out</a>${body}`;

/** A small eClass and Exchange behind fetch. */
const site = {
  session: false,
  sessionUser: 1,
  eclassPassword: 'good',
  mailPassword: 'good',
  pages: new Map<string, Answer>(),
  gate: null as Promise<void> | null,
};

const count = (test: (r: Seen) => boolean) => browser.requests.filter(test).length;
const eclassLogins = () => count((r) => r.method === 'POST' && r.url.endsWith('/login/index.php'));
const mailPosts = () => count((r) => r.url.includes('mail.inha.uz'));
const logouts = () => count((r) => r.url.includes('/login/logout.php'));

function reply(xml: string): Answer {
  return { status: 200, body: xml };
}

async function route(r: Seen): Promise<Answer> {
  const u = new URL(r.url);
  if (u.host === 'mail.inha.uz') return routeMail(r);
  if (u.host === 'ins.inha.uz') throw new TypeError('Failed to fetch');
  if (u.host === 'iut.edupage.org') {
    if (u.pathname.includes('ttviewer')) return { body: fixture('edupage_ttviewer.json') };
    if (u.pathname.includes('regulartt')) return { body: fixture('edupage_regulartt.json') };
    return { body: '' };
  }
  return routeEclass(u, r);
}

let lastAuth = '';
function routeMail(r: Seen): Answer {
  if (!lastAuth.endsWith(btoa(`INHA\\U2610999:${site.mailPassword}`))) return { status: 401 };
  if (r.body.includes('<m:FindItem')) return reply(fixture('ews_finditem.xml'));
  if (r.body.includes('<m:UpdateItem')) {
    return reply(
      '<s:Envelope xmlns:s="http://schemas.xmlsoap.org/soap/envelope/"><s:Body><m:UpdateItemResponse xmlns:m="m"><m:ResponseMessages><m:UpdateItemResponseMessage ResponseClass="Success"><m:ResponseCode>NoError</m:ResponseCode></m:UpdateItemResponseMessage></m:ResponseMessages></m:UpdateItemResponse></s:Body></s:Envelope>',
    );
  }
  return reply(fixture('ews_getfolder.xml'));
}

async function routeEclass(u: URL, r: Seen): Promise<Answer> {
  const target = u.pathname + u.search;
  if (r.method === 'POST' && u.pathname === '/login/index.php') {
    const form = new URLSearchParams(r.body);
    if (form.get('password') === site.eclassPassword) {
      site.session = true;
      return { body: dashboard };
    }
    return { body: loginPage };
  }
  if (u.pathname === '/login/logout.php') {
    site.session = false;
    return { body: loginPage };
  }
  if (u.pathname === '/lib/ajax/service.php') {
    return { body: site.session ? '[{"error":false,"data":{"notifications":[{"id":1,"subject":"Hi","smallmessage":"Hi","contexturl":"","timecreated":2,"read":false}]}}]' : '[{"error":true}]' };
  }
  if (!site.session) return { body: loginPage };
  if (site.gate && target !== '/') await site.gate;
  const page = site.pages.get(target);
  if (page) return page;
  if (target === '/') return { body: dashboard.replace(/user\/edit\.php\?id=1/g, `user/edit.php?id=${site.sessionUser}`) };
  if (target === '/calendar/view.php?view=upcoming') return { body: fixture('eclass_upcoming.html') };
  return { status: 404, body: '<h1>Not found</h1>' };
}

// fetch's headers, for the mail route.
const baseFetch = globalThis.fetch;
globalThis.fetch = (async (input: string, init: RequestInit = {}) => {
  lastAuth = (init.headers as Record<string, string> | undefined)?.Authorization ?? '';
  return baseFetch(input, init);
}) as typeof fetch;

const age = (service: 'mail' | 'eclass' | 'ins' | 'edupage', by = 24 * 3600e3) => writeState(service, { at: Date.now() - by });

beforeEach(async () => {
  await settle();
  for (const s of ['eclass', 'mail', 'ins', 'edupage'] as const) {
    await startOver(s);
    await retryLogin(s);
  }
  browser.reset();
  site.session = false;
  site.sessionUser = 1;
  site.eclassPassword = 'good';
  site.mailPassword = 'good';
  site.pages.clear();
  site.gate = null;
  browser.route = route;
  // Fresh, so a sync only runs what a test made due.
  for (const s of ['eclass', 'mail', 'ins', 'edupage'] as const) await writeState(s, { at: Date.now() });
});

test('a busy flag left by a dead worker is gone once the worker wakes', () => {
  assert.equal(busyAfterWaking, false);
});

describe('a mail password that went stale', () => {
  const save = () => saveLogin('mail', { username: 'U2610999', password: 'good' });

  test('costs one failed logon, however many refreshes follow', async () => {
    await save();
    site.mailPassword = 'changed';
    await refresh('mail');
    assert.equal(mailPosts(), 1, 'one refresh, one logon');
    assert.equal((await readState()).mail?.error?.name, 'LoginRequired');
    assert.deepEqual((await readSnapshot()).rejectedLogins, ['mail']);

    for (let i = 0; i < 3; i++) {
      await age('mail');
      await refreshDue();
    }
    await refresh('mail');
    assert.equal(mailPosts(), 1, 'never again');
    assert.ok(await readLogin('mail'), 'the login stays, marked, for the student to fix');
  });

  test('a page opening with Refresh forced still posts nothing', async () => {
    await save();
    site.mailPassword = 'changed';
    await refresh('mail');
    await rpc('sync', ['all', true]);
    assert.equal(mailPosts(), 1);
  });

  test('Update on that one service, asked for by hand, tries it once more', async () => {
    await save();
    site.mailPassword = 'changed';
    await refresh('mail');
    await rpc('sync', ['mail', true]);
    assert.equal(mailPosts(), 2);
    site.mailPassword = 'good';
    await rpc('sync', ['mail', true]);
    assert.equal((await readState()).mail?.error, null);
    assert.deepEqual((await readSnapshot()).rejectedLogins, []);
  });

  test('a newly saved password goes through', async () => {
    await save();
    site.mailPassword = 'changed';
    await refresh('mail');
    browser.requests.length = 0;
    const err = await rpc('saveLogin', ['mail', 'U2610999', 'changed']);
    assert.equal(err, null);
    assert.deepEqual((await readSnapshot()).rejectedLogins, []);
    await settle();
    assert.ok((await readCache('inbox'))?.value.length);
  });
});

describe('an eClass or INS password that went stale', () => {
  test('eClass is not posted to again, but a session the student opens is still read', async () => {
    await saveLogin('eclass', { username: 'student', password: 'old' });
    await refresh('eclass');
    assert.equal(eclassLogins(), 1);
    assert.equal((await readState()).eclass?.error?.name, 'LoginRequired');

    for (let i = 0; i < 3; i++) {
      await age('eclass');
      await refreshDue();
    }
    assert.equal(eclassLogins(), 1);

    site.session = true; // signed in by hand, with the new password
    await age('eclass');
    await refreshDue();
    assert.equal(eclassLogins(), 1);
    assert.equal((await readState()).eclass?.error, null);
    assert.ok((await readCache('deadlines'))?.value.length);
  });

  test('INS is left alone once refused', async () => {
    await saveLogin('ins', { username: 'student', password: 'old' });
    await markLoginRejected('ins', { username: 'student', password: 'old' });
    await age('ins');
    await refreshDue();
    assert.equal(count((r) => r.url.includes('ins.inha.uz')), 0);
  });
});

describe('saving a login', () => {
  test('tests it even with a live eClass session', async () => {
    site.session = true;
    site.eclassPassword = 'right';
    const err = await rpc<{ name: string }>('saveLogin', ['eclass', 'student', 'typo']);
    assert.equal(err?.name, 'LoginRequired');
    assert.equal(eclassLogins(), 1);
    assert.equal(await readLogin('eclass'), null);
  });

  test('a typo keeps the login that worked', async () => {
    await saveLogin('mail', { username: 'U2610999', password: 'good' });
    const err = await rpc<{ name: string }>('saveLogin', ['mail', 'U2610999', 'typo']);
    assert.equal(err?.name, 'LoginRequired');
    assert.deepEqual(await readLogin('mail'), { username: 'U2610999', password: 'good' });
    assert.deepEqual((await readSnapshot()).rejectedLogins, []);
  });

  test('the same typo typed again is a fresh try, as the student asked', async () => {
    await rpc('saveLogin', ['mail', 'U2610999', 'typo']);
    await rpc('saveLogin', ['mail', 'U2610999', 'typo']);
    assert.equal(mailPosts(), 2);
  });

  test("an unreachable INS keeps the login, untested, and says why", async () => {
    const err = await rpc<{ name: string; certificate?: boolean }>('saveLogin', ['ins', 'student', 'pw']);
    assert.equal(err?.certificate, true);
    assert.ok(await readLogin('ins'));
  });

  test('another account: nothing of the last one stays', async () => {
    await saveLogin('mail', { username: 'U1', password: 'x' });
    await writeCache('mailUnread', 9);
    site.mailPassword = 'good';
    browser.route = async (r) => (r.url.includes('mail.inha.uz') ? reply(fixture('ews_getfolder.xml')) : route(r));
    await rpc('saveLogin', ['mail', 'U2', 'y']);
    assert.notEqual((await readCache('mailUnread'))?.value, 9);
    await settle();
  });
});

describe('INS with no login saved', () => {
  test('sign-in is what is needed, not the certificate', async () => {
    await refresh('ins');
    const error = (await readState()).ins?.error;
    assert.equal(error?.name, 'LoginRequired');
    assert.ok(!error?.certificate);
  });

  test('with one saved, the certificate is reported', async () => {
    await saveLogin('ins', { username: 'student', password: 'pw' });
    await refresh('ins');
    assert.equal((await readState()).ins?.error?.certificate, true);
  });
});

describe('eClass, part by part', () => {
  const lab: Deadline = { title: 'Old lab', courseName: 'AI', kind: 'other', start: null, end: Date.now() + 3600e3, moduleId: null, moduleType: null, done: false, doneAt: null };

  beforeEach(() => {
    site.session = true;
  });

  test('one bad course page leaves deadlines fresh and that course as it was', async () => {
    const before = { course: { id: 2626, name: 'Artificial Intelligence', code: '', professor: '' }, classes: [{ date: '2026-09-01', label: '1', mark: 'present' as const }], vods: [] };
    await writeCache('attendance', [before]);
    site.pages.set('/local/ubattendance/my_status.php?id=2626', { status: 403, body: 'Forbidden' });
    await refresh('eclass');

    assert.equal((await readCache('deadlines'))?.value.length, 10);
    const attendance = (await readCache('attendance'))!.value;
    assert.equal(attendance.length, courseIds.length);
    assert.deepEqual(attendance.find((a) => a.course.id === 2626), before);
    assert.ok((await readCache('courseGrades'))?.value);
    const error = (await readState()).eclass?.error;
    assert.equal(error?.name, 'NetworkError');
    assert.equal(error?.status, 403);
  });

  test('a course with no attendance row it can read costs only that course', async () => {
    site.pages.set('/local/ubattendance/my_status.php?id=2626', { body: signedIn('<table class="attendance_my"><thead><tr><th>Date</th></tr></thead><tbody><tr><td>no date</td><td>x</td><td>y</td></tr></tbody></table>') });
    await refresh('eclass');
    assert.equal((await readCache('deadlines'))?.value.length, 10);
    assert.equal((await readCache('attendance'))?.value.length, courseIds.length - 1);
    assert.equal((await readState()).eclass?.error?.name, 'ParseError');
  });

  test('a dashboard that does not read still gets deadlines from the calendar', async () => {
    site.pages.set('/', { body: signedIn('<html><body>changed</body></html>') });
    await refresh('eclass');
    assert.equal((await readCache('deadlines'))?.value.length, 10);
    assert.equal((await readState()).eclass?.error?.name, 'ParseError');
  });

  test('deadlines past the calendar page come in from the course pages', async () => {
    site.pages.set('/calendar/view.php?view=upcoming&course=2622', {
      body: signedIn(
        '<html><body id="page-calendar-view"><div class="maincalendar"><div class="eventlist"><div class="event"><h3 class="referer"><a href="https://eclass.inha.ac.kr/mod/assign/view.php?id=99">Slot eleven</a></h3><span class="date"><a href="/calendar/view.php?view=day&amp;time=1792954500">Sunday</a></span><div class="course"><a href="https://eclass.inha.ac.kr/course/view.php?id=2622">Multimedia Computing</a></div></div></div></div></body></html>',
      ),
    });
    await refresh('eclass');
    const deadlines = (await readCache('deadlines'))!.value;
    assert.equal(deadlines.length, 11);
    assert.equal(deadlines.find((d) => d.title === 'Slot eleven')?.courseId, 2622);
  });

  test('a course page failing keeps what it last showed, until it answers', async () => {
    await writeCache('deadlines', [lab]);
    site.pages.set('/calendar/view.php?view=upcoming&course=2622', { status: 503, body: '' });
    await refresh('eclass').catch(() => {});
    assert.ok((await readCache('deadlines'))!.value.some((d) => d.title === 'Old lab'));
    site.pages.clear();
    await refresh('eclass');
    assert.ok(!(await readCache('deadlines'))!.value.some((d) => d.title === 'Old lab'));
  });

  test('a refresh that finds new eClass notifications announces them after the first look', async () => {
    await refresh('eclass');
    assert.ok(!browser.shown.some((s) => s.id.startsWith('notice:')));
    assert.ok(browser.local.data['notify.seenNotices']);
  });
});

describe('signing out', () => {
  beforeEach(async () => {
    site.session = true;
    await saveLogin('eclass', { username: 'student', password: 'good' });
  });

  test('ends the eClass session too, so the next refresh has nothing to read', async () => {
    await refresh('eclass');
    assert.ok((await readCache('deadlines'))?.value.length);
    await rpc('clearLogin', ['eclass']);
    assert.equal(logouts(), 1);
    assert.equal(site.session, false);
    assert.equal(await readCache('deadlines'), undefined);

    await age('eclass');
    await refreshDue();
    assert.equal(await readCache('deadlines'), undefined);
    assert.equal(eclassLogins(), 0);
  });

  test('offline at the time: the session is ended first thing on the next refresh, before anything is read', async () => {
    await refresh('eclass');
    browser.route = async () => {
      throw new TypeError('offline');
    };
    await rpc('clearLogin', ['eclass']);
    assert.equal(site.session, true);
    browser.route = route;
    browser.requests.length = 0;
    await refresh('eclass');
    assert.ok(browser.requests.findIndex((r) => r.url.includes('logout')) >= 0);
    assert.equal(await readCache('deadlines'), undefined);
  });

  test('a refresh in flight lands nothing afterwards', async () => {
    let open!: () => void;
    site.gate = new Promise((resolve) => (open = resolve));
    const running = refresh('eclass');
    await settle();
    await rpc('clearLogin', ['eclass']);
    open();
    site.gate = null;
    site.session = true; // nothing it writes should land, whatever it gets back
    await running;
    await settle();
    for (const k of ['deadlines', 'attendance', 'courseGrades', 'notifications'] as const) assert.equal(await readCache(k), undefined, k);
    const state = (await readState()).eclass!;
    assert.deepEqual([state.at, state.error, state.busy], [0, null, false]);
  });

  test('a refresh in flight when mail signs out lands nothing either', async () => {
    await saveLogin('mail', { username: 'U2610999', password: 'good' });
    const running = refresh('mail');
    await rpc('clearLogin', ['mail']);
    await running;
    await settle();
    assert.equal(await readCache('inbox'), undefined);
    assert.equal((await readState()).mail?.at, 0);
  });

  test('forgets what that account was told', async () => {
    await refresh('eclass');
    await rpc('sync', ['eclass']);
    await rpc('clearLogin', ['eclass']);
    assert.deepEqual(browser.local.data['notify.seenCourses'], []);
    assert.equal(browser.local.data['notify.seenNotices'], undefined);
  });
});

describe('Log out clicked on eClass', () => {
  const fromEclass = { url: 'https://eclass.inha.ac.kr/my/' };

  beforeEach(async () => {
    await saveLogin('eclass', { username: 'student', password: 'good' });
  });

  test('nothing signs the browser back in', async () => {
    await rpc('eclassLoggedOut', [], fromEclass);
    await age('eclass');
    await refreshDue();
    assert.equal(eclassLogins(), 0);
    assert.equal(site.session, false);
    assert.equal((await readState()).eclass?.error?.name, 'LoginRequired');
    assert.ok(await readLogin('eclass'), 'the saved login stays');
  });

  test('signing in by hand starts it all again', async () => {
    await rpc('eclassLoggedOut', [], fromEclass);
    site.session = true;
    await refresh('eclass');
    assert.equal((await readState()).eclass?.error, null);
    site.session = false; // expired later
    await refresh('eclass');
    assert.equal(eclassLogins(), 1, 'background logins are back');
  });

  test('a stop that is only "still to log out" ends the session before reading anything', async () => {
    site.session = true;
    await setEclassStop('logout');
    await refresh('eclass');
    assert.equal(logouts(), 1);
    assert.equal(eclassLogins(), 0);
    assert.equal(await readCache('deadlines'), undefined);
  });

  test('"Continue as" is the student asking, so it signs in', async () => {
    await rpc('eclassLoggedOut', [], fromEclass);
    assert.equal(await rpc('eclassAutoLogin'), true);
    assert.equal(eclassLogins(), 1);
    await settle();
  });

  test('only eClass can say so', async () => {
    await assert.rejects(rpc('eclassLoggedOut', [], { url: 'https://elsewhere.example/' }));
  });
});

describe('someone else signed in to eClass in this browser', () => {
  beforeEach(() => {
    site.session = true;
  });

  test('with a login saved, their session is not read', async () => {
    await saveLogin('eclass', { username: 'student', password: 'good' });
    await refresh('eclass');
    const mine = (await readCache('deadlines'))!.fetchedAt;
    site.sessionUser = 2;
    await settle();
    await refresh('eclass');
    assert.equal((await readState()).eclass?.error?.name, 'OtherAccount');
    assert.equal((await readCache('deadlines'))!.fetchedAt, mine);
  });

  test('with none saved, the cache follows the browser and the last one\'s data goes', async () => {
    await refresh('eclass');
    await writeCache('grades', { gpa: 1, creditsEarned: 1, yearOfStudy: 1, records: [] });
    await writeCache('courseGrades', [{ course: { id: 77, name: 'Theirs', code: '', professor: '' }, source: 'none', items: [], categories: [] }]);
    site.sessionUser = 2;
    await refresh('eclass');
    assert.equal((await readState()).eclass?.error, null);
    assert.ok(!(await readCache('courseGrades'))!.value.some((g) => g.course.id === 77));
  });
});

describe('how often sources run', () => {
  test('mail is due on every 5-minute tick, not every other one', async () => {
    await saveLogin('mail', { username: 'U2610999', password: 'good' });
    await writeState('mail', { at: Date.now() - 5 * 60e3 + 3000, error: null }); // the last run ended 3 s after its tick
    await refreshDue();
    assert.ok(mailPosts() > 0);
  });

  test('a fresh source is left alone', async () => {
    await refreshDue();
    assert.equal(browser.requests.length, 0);
  });

  test('a failure retries sooner, but setup that is missing waits for the student', async () => {
    await writeState('eclass', { at: Date.now() - 10 * 60e3, error: { name: 'NetworkError', message: '' } });
    await writeState('edupage', { at: Date.now() - 10 * 60e3, error: { name: 'SetupNeeded', message: '' } });
    await refreshDue();
    assert.ok(count((r) => r.url.includes('eclass')) > 0);
    assert.equal(count((r) => r.url.includes('edupage')), 0);
  });
});

describe('asking again during a refresh', () => {
  test('a change made during the mail refresh gets one more run, shared by everyone asking', async () => {
    await saveLogin('mail', { username: 'U2610999', password: 'good' });
    const first = refresh('mail');
    const a = refresh('mail', true);
    const b = refresh('mail', true);
    assert.equal(a, b);
    await Promise.all([first, a]);
    assert.equal(count((r) => r.body.includes('<m:FindItem')), 2);
  });

  test('asking without changing anything shares the run', async () => {
    await saveLogin('mail', { username: 'U2610999', password: 'good' });
    await Promise.all([refresh('mail'), refresh('mail')]);
    assert.equal(count((r) => r.body.includes('<m:FindItem')), 1);
  });

  test('a group picked during the download is the one that sticks', async () => {
    await writeSettings({ classGroup: 'ICE23-1' });
    const first = rpc('sync', ['edupage', true]);
    await writeSettings({ classGroup: 'CSE23-1' });
    const second = rpc('sync', ['edupage', true]);
    await Promise.all([first, second]);
    const { EdupageClient } = await import('../src/services/edupage/client.ts');
    const expected = await new EdupageClient().lessons('CSE23-1', []);
    assert.deepEqual((await readCache('lessons'))?.value, expected);
  });

  test('marking a message read refreshes the inbox behind it', async () => {
    await saveLogin('mail', { username: 'U2610999', password: 'good' });
    await rpc('mailMarkRead', ['id1', true]);
    await settle();
    assert.equal(count((r) => r.body.includes('<m:FindItem')), 1);
  });
});

describe('a renamed class group', () => {
  test('the list still lands, the old lessons go, and it says what to do', async () => {
    await writeSettings({ classGroup: 'ICE99-9' });
    await writeCache('lessons', [{ weekday: 1, start: '09:00', end: '10:00', subject: 'Old', room: '', teacher: '', kind: '' }]);
    await refresh('edupage');
    assert.ok((await readCache('classGroups'))!.value.includes('ICE23-1'));
    assert.equal(await readCache('lessons'), undefined);
    const error = (await readState()).edupage?.error;
    assert.equal(error?.name, 'SetupNeeded');
    assert.equal(error?.message, "Your class group isn't on the timetable. Choose it in Settings.");
  });

  test('no group chosen yet says choose one', async () => {
    await writeSettings({ classGroup: '' });
    await refresh('edupage');
    assert.equal((await readState()).edupage?.error?.message, 'Choose your class group in Settings.');
    assert.ok((await readCache('classGroups'))?.value.length);
  });
});

describe('a site the browser left off', () => {
  test('reads as a setting to change, not a dead connection', async () => {
    (chrome as { permissions?: unknown }).permissions = { contains: async () => false };
    browser.route = async () => {
      throw new TypeError('Failed to fetch');
    };
    await refresh('edupage');
    const error = (await readState()).edupage?.error;
    assert.equal(error?.name, 'SetupNeeded');
    assert.match(error!.message, /Allow this extension to reach Timetable/);
    delete (chrome as { permissions?: unknown }).permissions;
  });
});

describe('INS tabs', () => {
  const insPage = (tab: number) => ({ url: 'https://ins.inha.uz/ITIS/Start.aspx', tab: { id: tab } as chrome.tabs.Tab });
  const report = { gpa: 4, creditsEarned: 10, yearOfStudy: 3, records: [] };

  beforeEach(async () => {
    await saveLogin('ins', { username: 'student', password: 'pw' });
  });

  test('the password goes to a tab the extension opened, and to no other INS page', async () => {
    await assert.rejects(rpc('insLogin', [], insPage(555)), /Not from INS/);
    assert.equal(await rpc('insSyncAllowed', [], insPage(555)), false);
    await rpc('insOpenForSync');
    const tab = browser.tabs[0].id;
    assert.equal(await rpc('insSyncAllowed', [], insPage(tab)), true);
    assert.deepEqual(await rpc('insLogin', [], insPage(tab)), { username: 'student', password: 'pw' });
    await assert.rejects(rpc('insLogin', [], { url: 'https://elsewhere.example/', tab: { id: tab } as chrome.tabs.Tab }), /Not from INS/);
  });

  test('grades are taken only from such a tab', async () => {
    await assert.rejects(rpc('insReport', [report, null], insPage(555)), /Not from INS/);
    assert.equal(await readCache('grades'), undefined);
  });

  test('a tab opened for it closes itself after reporting', async () => {
    await rpc('insOpenForSync');
    const tab = browser.tabs[0].id;
    await rpc('insReport', [report, null], insPage(tab));
    assert.equal((await readCache('grades'))?.value.gpa, 4);
    assert.deepEqual(browser.closedTabs, [tab]);
    assert.equal(await rpc('insSyncAllowed', [], insPage(tab)), false);
  });

  test("a tab the student picked by clicking is used, and stays open", async () => {
    await rpc('insAdoptTab', [], insPage(77));
    assert.deepEqual(await rpc('insLogin', [], insPage(77)), { username: 'student', password: 'pw' });
    await rpc('insReport', [report, null], insPage(77));
    assert.deepEqual(browser.closedTabs, []);
    assert.equal(await rpc('insSyncAllowed', [], insPage(77)), false);
  });

  test('a refused login reported from the tab stops it being offered again', async () => {
    await rpc('insOpenForSync');
    const tab = browser.tabs[0].id;
    await rpc('insReport', [null, { name: 'LoginRequired', message: 'x', rejected: true }], insPage(tab));
    assert.deepEqual((await readSnapshot()).rejectedLogins, ['ins']);
    assert.equal(await rpc('insLogin', [], insPage(tab)), null);
  });
});

