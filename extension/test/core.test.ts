// The parts under every service: request(), what errors say, what storage keeps.
import { beforeEach, describe, test } from 'node:test';
import assert from 'node:assert/strict';
import './setup.ts';
import { browser, installFakeBrowser } from './fake_browser.ts';
import { describeError, errorInfo, LoginRequired, NetworkError, OtherAccount, ParseError } from '../src/core/errors.ts';
import { request } from '../src/core/http.ts';
import { RemoteError } from '../src/core/rpc.ts';
import { clearStaleBusy, defaultSettings, ensureCacheSchema, readCache, readSettings, readSnapshot, readState, writeCache, writeSettings, writeState } from '../src/core/store.ts';
import { clearLoginRejected, loginRejected, markLoginRejected, readLogin, readSealedLogin, refusalHolds, restoreLogin, saveLogin } from '../src/core/vault.ts';
import { missingHosts } from '../src/core/permissions.ts';

installFakeBrowser();
const realFetch = globalThis.fetch;

beforeEach(() => {
  browser.reset();
  globalThis.fetch = realFetch;
});

describe('request', () => {
  test('a timeout covers the body too', async () => {
    globalThis.fetch = (async (_: string, init: RequestInit) => ({
      status: 200,
      arrayBuffer: () =>
        new Promise((_, reject) => init.signal!.addEventListener('abort', () => reject(new Error('aborted')))),
    })) as unknown as typeof fetch;
    await assert.rejects(request('https://iut.edupage.org/x', { timeoutMs: 5 }), (e: unknown) => e instanceof NetworkError && /timed out/.test((e as Error).message));
  });

  test('a connection dropped in mid-body is a NetworkError', async () => {
    globalThis.fetch = (async () => ({ status: 200, arrayBuffer: async () => Promise.reject(new TypeError('network')) })) as unknown as typeof fetch;
    await assert.rejects(request('https://iut.edupage.org/x'), (e: unknown) => e instanceof NetworkError && e.status === 0);
  });

  test('a 5xx is an error unless the caller takes it', async () => {
    browser.route = async () => ({ status: 500, body: '<fault/>' });
    await assert.rejects(request('https://mail.inha.uz/x'), (e: unknown) => e instanceof NetworkError && e.status === 500);
    const res = await request('https://mail.inha.uz/x', { allow5xx: true });
    assert.equal(res.status, 500);
    assert.equal(res.text(), '<fault/>');
  });

  const failing = (probe: 'fails' | 'answers') => {
    browser.route = async (r) => {
      if (r.redirect === 'manual' && probe === 'answers') return { status: 302 };
      throw new TypeError('Failed to fetch');
    };
  };

  test('INS failing with the first answer refused too is its certificate', async () => {
    failing('fails');
    await assert.rejects(request('https://ins.inha.uz/ITIS/left.aspx'), (e: unknown) => e instanceof NetworkError && e.certificate);
    assert.deepEqual(browser.requests.map((r) => r.redirect), ['follow', 'manual']);
  });

  test('INS answering until a redirect fails is not its certificate', async () => {
    failing('answers');
    await assert.rejects(request('https://ins.inha.uz/ITIS/left.aspx'), (e: unknown) => e instanceof NetworkError && !e.certificate);
  });

  test('another site failing is never called a certificate, and costs no second request', async () => {
    failing('fails');
    await assert.rejects(request('https://eclass.inha.ac.kr/'), (e: unknown) => e instanceof NetworkError && !e.certificate);
    assert.equal(browser.requests.length, 1);
  });
});

describe('describeError', () => {
  test('"check the connection" only when nothing answered', () => {
    assert.equal(describeError(new NetworkError('x'), 'eclass'), "Couldn't reach eClass. Check the connection.");
    assert.equal(describeError(new NetworkError('x', 403), 'eclass'), "Couldn't load from eClass.");
    assert.equal(describeError(new NetworkError('x', 503), 'mail'), "Couldn't load from Mail.");
  });

  test('the status survives the trip from the worker', () => {
    const info = errorInfo(new NetworkError('x', 503));
    assert.equal(info.status, 503);
    assert.equal(describeError(info, 'eclass'), "Couldn't load from eClass.");
    assert.equal(describeError(new RemoteError(info), 'eclass'), "Couldn't load from eClass.");
  });

  test('each kind has its own sentence', () => {
    assert.equal(describeError(new LoginRequired('mail'), 'mail'), 'Mail sign-in needed.');
    assert.equal(describeError(new ParseError('x'), 'ins'), "Couldn't read the INS page; it may have changed.");
    assert.equal(describeError(new OtherAccount(), 'eclass'), 'eClass is signed in to another account in this browser.');
    assert.match(describeError(new NetworkError('x', 0, true), 'ins'), /Use Open INS and choose Proceed/);
    assert.match(describeError({ name: 'LoginUntested', message: '' }, 'ins'), /Saved, but not tested/);
  });

  test('errorInfo says whether a login was refused', () => {
    assert.equal(errorInfo(new LoginRequired('mail', 'x', true)).rejected, true);
    assert.equal(errorInfo(new LoginRequired('mail', 'x')).rejected, undefined);
  });
});

describe('state', () => {
  test('sources writing at once all land', async () => {
    await Promise.all([writeState('eclass', { busy: true }), writeState('mail', { busy: true }), writeState('ins', { busy: true }), writeState('edupage', { busy: true })]);
    const state = await readState();
    assert.deepEqual(Object.keys(state).sort(), ['eclass', 'edupage', 'ins', 'mail']);
    assert.ok(Object.values(state).every((s) => s?.busy));
  });

  test('patches to one source apply in turn', async () => {
    await Promise.all([writeState('eclass', { at: 5 }), writeState('eclass', { marksError: { name: 'X', message: 'y' } }), writeState('eclass', { busy: true })]);
    const s = (await readState()).eclass!;
    assert.deepEqual([s.at, s.marksError?.name, s.busy], [5, 'X', true]);
  });

  test('a busy flag left in storage is cleared; the rest of the state stays', async () => {
    await writeState('edupage', { busy: true, at: 7 });
    await writeState('mail', { busy: false, at: 8 });
    await clearStaleBusy();
    const state = await readState();
    assert.deepEqual([state.edupage?.busy, state.edupage?.at, state.mail?.at], [false, 7, 8]);
  });

  test('the snapshot puts it back together', async () => {
    await writeState('ins', { at: 3 });
    assert.equal((await readSnapshot()).state.ins?.at, 3);
  });
});

describe('settings', () => {
  test('two changes at once both land', async () => {
    await Promise.all([writeSettings({ theme: 'dark' }), writeSettings({ showDone: false }), writeSettings({ classGroup: 'ICE23-1' })]);
    const s = await readSettings();
    assert.deepEqual([s.theme, s.showDone, s.classGroup], ['dark', false, 'ICE23-1']);
  });

  test('new channels and fields have defaults for settings saved before them', async () => {
    browser.local.data.settings = { notify: { mail: false } };
    const s = await readSettings();
    assert.deepEqual([s.notify.mail, s.notify.exams, s.notify.notices, s.dismissed], [false, true, true, []]);
    assert.deepEqual(defaultSettings.dismissed, []);
  });
});

describe('cache', () => {
  test('a good value reads back', async () => {
    await writeCache('mailUnread', 3);
    assert.equal((await readCache('mailUnread'))?.value, 3);
  });

  test('a value of an old shape reads as no cache, here and in the snapshot', async () => {
    browser.local.data['cache.courseGrades'] = { value: [{ course: { id: 1 }, marks: [] }], fetchedAt: 1 };
    browser.local.data['cache.deadlines'] = { value: 'nonsense', fetchedAt: 1 };
    browser.local.data['cache.inbox'] = { value: [{ id: 'a' }] };
    assert.equal(await readCache('courseGrades'), undefined);
    assert.equal(await readCache('deadlines'), undefined);
    assert.equal(await readCache('inbox'), undefined);
    assert.deepEqual((await readSnapshot()).cache, {});
  });

  test('a cache from another version goes on update; other keys stay', async () => {
    await writeCache('mailUnread', 3);
    browser.local.data.settings = { theme: 'dark' };
    await ensureCacheSchema();
    assert.equal(await readCache('mailUnread'), undefined);
    assert.ok(browser.local.data.settings);
    await writeCache('mailUnread', 4);
    await ensureCacheSchema();
    assert.equal((await readCache('mailUnread'))?.value, 4, 'same version: kept');
  });
});

describe('vault', () => {
  const login = { username: ' U2610999 ', password: 'pw' };

  test('a saved login reads back, and the password is not in storage', async () => {
    await saveLogin('mail', login);
    assert.deepEqual(await readLogin('mail'), { username: 'U2610999', password: 'pw' });
    assert.ok(!JSON.stringify(browser.local.data).includes('pw'));
  });

  test('saves at once for two services both land', async () => {
    await Promise.all([saveLogin('mail', login), saveLogin('eclass', login), saveLogin('ins', login)]);
    assert.deepEqual(Object.keys((await readSnapshot()).logins).sort(), ['eclass', 'ins', 'mail']);
  });

  test('the refused mark sticks to that login; saving a new one clears it', async () => {
    await saveLogin('mail', login);
    await markLoginRejected('mail', { username: 'U2610999', password: 'pw' });
    assert.equal(await loginRejected('mail'), true);
    assert.deepEqual((await readSnapshot()).rejectedLogins, ['mail']);
    await clearLoginRejected('mail');
    assert.equal(await loginRejected('mail'), false);

    await markLoginRejected('mail', login);
    await saveLogin('mail', { username: 'U2610999', password: 'new' });
    assert.equal(await loginRejected('mail'), false);
  });

  test('after a day a refused login gets one more try: a server fault mends itself', async () => {
    await saveLogin('mail', login);
    await markLoginRejected('mail', login);
    const vault = browser.local.data['vault.v1'] as { mail: { rejected: number } };
    vault.mail.rejected -= refusalHolds - 60_000;
    assert.equal(await loginRejected('mail'), true);
    vault.mail.rejected -= 120_000;
    assert.equal(await loginRejected('mail'), false);
    assert.deepEqual((await readSnapshot()).rejectedLogins, []);
  });

  test('a refusal of an older login does not mark a newer one', async () => {
    await saveLogin('mail', { username: 'U2610999', password: 'new' });
    await markLoginRejected('mail', { username: 'U2610999', password: 'old' });
    assert.equal(await loginRejected('mail'), false);
  });

  test('restoring puts the old login back, or none', async () => {
    assert.equal(await readSealedLogin('ins'), undefined);
    await saveLogin('ins', login);
    await restoreLogin('ins', undefined);
    assert.equal(await readLogin('ins'), null);

    await saveLogin('ins', login);
    const before = await readSealedLogin('ins');
    await saveLogin('ins', { username: 'x', password: 'typo' });
    await restoreLogin('ins', before);
    assert.deepEqual(await readLogin('ins'), { username: 'U2610999', password: 'pw' });
  });
});

describe('site access', () => {
  test('names what the browser left off; a browser that can not say has nothing missing', async () => {
    assert.deepEqual(await missingHosts(), []);
    (chrome as { permissions?: unknown }).permissions = { contains: async ({ origins }: { origins: string[] }) => !origins[0].includes('ins.inha.uz') };
    assert.deepEqual(await missingHosts(), ['https://ins.inha.uz/*']);
    delete (chrome as { permissions?: unknown }).permissions;
  });
});
