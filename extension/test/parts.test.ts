// What goes on eClass's own pages, drawn for real: parts.tsx and signin.tsx are
// bundled as the build does and rendered into linkedom, over a fake storage and
// a fake worker behind `call`.

import { afterEach, beforeEach, describe, mock, test } from 'node:test';
import assert from 'node:assert/strict';
import { fileURLToPath } from 'node:url';
import * as esbuild from 'esbuild';
import { parseHTML } from 'linkedom';
import { reminderStem } from '../src/data/status.ts';
import type { Deadline, Lesson } from '../src/core/models.ts';
import { dueWhen } from '../src/content/pages.ts';
import { browser, installFakeBrowser } from './fake_browser.ts';

const { window, document } = parseHTML('<!doctype html><html><head></head><body><div id="app"></div></body></html>');
const root = document.getElementById('app')!;

// Preact infers an event's casing from these being on the element.
for (const e of ['click', 'input', 'change', 'submit']) {
  (window.HTMLElement.prototype as unknown as Record<string, unknown>)[`on${e}`] = null;
}

installFakeBrowser();

const g = globalThis as unknown as Record<string, unknown>;
const gh = g as { chrome: { runtime: { sendMessage?: unknown }; storage: { onChanged: { removeListener: unknown } } } };
g.document = document;
g.requestAnimationFrame = (cb: () => void) => setTimeout(cb, 0);
g.cancelAnimationFrame = clearTimeout;
g.addEventListener = () => {};
g.removeEventListener = () => {};

const replaced: string[] = [];
const place = { hash: '', search: '' };
g.location = {
  host: 'eclass.inha.ac.kr',
  get hash() {
    return place.hash;
  },
  get search() {
    return place.search;
  },
  href: 'https://eclass.inha.ac.kr/',
  replace: (to: string) => void replaced.push(to),
};

const tabStore = new Map<string, string>();
g.sessionStorage = { getItem: (k: string) => tabStore.get(k) ?? null, setItem: (k: string, v: string) => void tabStore.set(k, v), removeItem: (k: string) => void tabStore.delete(k) };

let submitted = 0;
(window.HTMLFormElement.prototype as unknown as { submit: () => void }).submit = () => void submitted++;
g.HTMLFormElement = window.HTMLFormElement;

// The fake worker. Each test sets `answer`; what it was asked is in `asked`.
type Asked = { rpc: string; args: unknown[] };
const asked: Asked[] = [];
let answer: (rpc: string, args: unknown[]) => unknown = () => null;
gh.chrome.runtime.sendMessage = async ({ rpc, args }: Asked) => {
  asked.push({ rpc, args });
  try {
    return { ok: true, value: (await answer(rpc, args)) ?? null };
  } catch (e) {
    return { ok: false, error: { name: (e as Error).name, message: (e as Error).message } };
  }
};
gh.chrome.storage.onChanged.removeListener = () => {};

const bundle = await esbuild.build({
  stdin: {
    contents: `export { CourseFacts, DueBanner, SideBlocks } from './src/content/parts.tsx'; export { SignIn } from './src/content/signin.tsx'; export { h, render } from 'preact';`,
    resolveDir: fileURLToPath(new URL('..', import.meta.url)),
    loader: 'ts',
  },
  bundle: true,
  write: false,
  format: 'esm',
  target: 'es2022',
  jsx: 'automatic',
  jsxImportSource: 'preact',
  loader: { '.css': 'text' },
  define: { __DEV__: 'false' },
  logLevel: 'silent',
});
interface Parts {
  CourseFacts: unknown;
  DueBanner: unknown;
  SideBlocks: unknown;
  SignIn: unknown;
  h: (type: unknown, props?: unknown, ...children: unknown[]) => unknown;
  render: (vnode: unknown, at: Element) => void;
}
const parts = (await import(`data:text/javascript;base64,${Buffer.from(bundle.outputFiles[0].text).toString('base64')}`)) as Parts;

async function settle(ms = 25) {
  await new Promise((resolve) => setTimeout(resolve, ms));
  for (let i = 0; i < 6; i++) await new Promise((resolve) => setTimeout(resolve, 2));
}

async function show(type: unknown, props: unknown = {}) {
  parts.render(parts.h(type, props), root);
  await settle();
}

const shown = () => root.textContent ?? '';
const links = () => [...root.querySelectorAll('a')].map((a) => a.getAttribute('href'));

/** Puts a cache entry where the worker would. */
const cache = (key: string, value: unknown, fetchedAt = Date.now()) => void (browser.local.data[`cache.${key}`] = { value, fetchedAt });
const state = (service: string, error: unknown) => void (browser.local.data[`state.${service}`] = { error, at: Date.now(), busy: false });
const settings = (s: unknown) => void (browser.local.data.settings = s);
const saved = (service: string) => void (browser.local.data['vault.v1'] = { [service]: { username: 'U2610999' } });

const lesson = (over: Partial<Lesson>): Lesson =>
  ({ weekday: ((new Date().getDay() + 6) % 7) + 1, start: '23:58', end: '23:59', subject: 'Multimedia Computing', room: 'B305', kind: 'Lecture', teacher: 'J. Hong', ...over }) as Lesson;
const due = (over: Partial<Deadline>): Deadline =>
  ({ title: 'Lab 5', courseName: 'Multimedia Computing', courseId: null, moduleId: null, moduleType: null, kind: 'assignment', end: Date.now() + 3600e3, done: false, ...over }) as Deadline;

beforeEach(() => {
  browser.reset();
  asked.length = 0;
  answer = () => null;
  replaced.length = 0;
  tabStore.clear();
  submitted = 0;
  place.hash = '';
  place.search = '';
});

afterEach(() => {
  parts.render(null, root); // ends the minute's ticker, or the test would never exit
});

describe('side blocks', () => {
  test("a refused mail login isn't told as no unread mail", async () => {
    saved('mail');
    state('mail', { name: 'LoginRequired', message: 'rejected' });
    await show(parts.SideBlocks);
    assert.doesNotMatch(shown(), /No unread mail/);
    assert.match(shown(), /mail/i);
    assert.ok(root.querySelector('.status.danger'));
    assert.ok(links().includes('/#/mail/inbox'));
  });

  test("EduPage unreachable with nothing cached isn't told as no classes", async () => {
    settings({ classGroup: 'CS-24' });
    state('edupage', { name: 'NetworkError', message: 'down' });
    await show(parts.SideBlocks);
    assert.doesNotMatch(shown(), /No classes this week/);
    assert.match(shown(), /Couldn't reach Timetable/);
  });

  test('on its way with nothing cached, it says so', async () => {
    settings({ classGroup: 'CS-24' });
    saved('mail');
    await show(parts.SideBlocks);
    assert.doesNotMatch(shown(), /No classes this week|No unread mail/);
    assert.match(shown(), /Updating…/);
  });

  test('with data and no failure the empty sentences stand', async () => {
    settings({ classGroup: 'CS-24' });
    saved('mail');
    cache('lessons', []);
    cache('mailUnread', 0);
    cache('deadlines', []);
    await show(parts.SideBlocks);
    assert.match(shown(), /No classes this week\./);
    assert.match(shown(), /No unread mail\./);
    assert.match(shown(), /Nothing due in the next 3 days\./);
    assert.ok(!root.querySelector('.stale'));
  });

  test('old data is marked, per source', async () => {
    settings({ classGroup: 'CS-24' });
    saved('mail');
    cache('lessons', [lesson({})], Date.now() - 48 * 3600e3);
    cache('deadlines', [], Date.now() - 4 * 3600e3);
    cache('mailUnread', 0, Date.now() - 3600e3);
    await show(parts.SideBlocks);
    assert.equal(root.querySelectorAll('.stale').length, 3);
    assert.match(shown(), /as of/);
  });

  test("failed mail with mail on show keeps the rows and marks them, and a message's id stays out of the link", async () => {
    saved('mail');
    cache('mailUnread', 1);
    cache('inbox', [{ id: 'AAMkAD+secret=', subject: 'Room change', from: 'Registrar', received: Date.now(), unread: true }]);
    state('mail', { name: 'NetworkError', message: 'down' });
    await show(parts.SideBlocks);
    assert.match(shown(), /Room change/);
    assert.ok(root.querySelector('.stale'));
    assert.ok(!links().some((l) => l?.includes('secret')));
  });

  test("a lesson with a time that can't be read is left out, and the blocks stay up", async () => {
    settings({ classGroup: 'CS-24' });
    cache('lessons', [lesson({ start: 'TBA', subject: 'Unreadable' }), lesson({})]);
    await show(parts.SideBlocks);
    assert.doesNotMatch(shown(), /Unreadable/);
    assert.match(shown(), /Multimedia Computing/);
  });

  test("a course-level event links somewhere real, and what's marked done is gone", async () => {
    settings({ classGroup: 'CS-24' });
    const marked = due({ title: 'Marked one' });
    settings({ classGroup: 'CS-24', dismissed: [reminderStem(marked)] });
    cache('lessons', []);
    cache('deadlines', [due({ courseId: 2622 }), due({ title: 'No course' }), marked]);
    await show(parts.SideBlocks);
    assert.ok(!links().includes('#'));
    assert.ok(links().includes('https://eclass.inha.ac.kr/course/view.php?id=2622'));
    assert.ok(links().includes('/#/deadlines'));
    assert.doesNotMatch(shown(), /Marked one/);
  });
});

describe('due soon says the day once', () => {
  const now = new Date(2026, 10, 2, 12, 0).getTime();
  const h = 3600e3;

  test('under a day, the day and how long', () => assert.equal(dueWhen(now + 6 * h, now), 'Today · in 6 h'));
  test('past a day, only the day: the clock is on the row', () => {
    assert.equal(dueWhen(now + 30 * h, now), 'Tomorrow');
    assert.equal(dueWhen(now + 50 * h, now), 'Wed 4 Nov');
  });
  test('overdue says by how much', () => assert.equal(dueWhen(now - 2 * h, now), 'Overdue 2 h'));
});

describe('the time left on a page keeps moving', () => {
  test('the banner counts down with no write to storage', async () => {
    const at = new Date(2026, 10, 2, 12, 0, 30).getTime();
    cache('deadlines', [due({ moduleId: 5, end: at + 25 * 60e3 })], at);
    mock.timers.enable({ apis: ['setTimeout', 'Date'], now: at });
    try {
      const run = async () => {
        for (let i = 0; i < 20; i++) {
          mock.timers.tick(100);
          await Promise.resolve();
          await new Promise((resolve) => setImmediate(resolve));
        }
      };
      parts.render(parts.h(parts.DueBanner, { moduleId: 5 }), root);
      await run();
      assert.match(shown(), /in 25 min/);
      mock.timers.tick(61_000);
      await run();
      assert.match(shown(), /in 23 min|in 24 min/);
    } finally {
      parts.render(null, root);
      mock.timers.reset();
    }
  });

  test('what the student marked done says so', async () => {
    const d = due({ moduleId: 7 });
    settings({ dismissed: [reminderStem(d)] });
    cache('deadlines', [d]);
    await show(parts.DueBanner, { moduleId: 7 });
    assert.match(shown(), /Marked done by you/);
  });
});

describe('the sign-in page', () => {
  /** eClass's own form, as its sign-in page has it. */
  const eclassForm = () => {
    const { document: d } = parseHTML('<html><body><form action="https://eclass.inha.ac.kr/login/index.php"><input name="username"><input name="password"></form></body></html>');
    return d.querySelector('form')!;
  };
  const type = (id: string, value: string) => {
    const el = root.querySelector(`#${id}`) as unknown as HTMLInputElement;
    el.value = value;
    el.dispatchEvent(new window.Event('input'));
  };
  const send = async () => {
    await settle(); // what was typed has reached the state
    const e = new window.Event('submit');
    (e as unknown as { preventDefault: () => void }).preventDefault = () => {};
    root.querySelector('form')!.dispatchEvent(e);
    await settle();
  };
  const tried = (rpc: string) => asked.filter((a) => a.rpc === rpc);

  test('a mistyped password goes nowhere near the saved one, and the page says so', async () => {
    answer = (rpc) => (rpc === 'saveLogin' ? { name: 'LoginRequired', message: 'rejected' } : null);
    const form = eclassForm();
    await show(parts.SignIn, { saved: null, form });
    type('iut-user', 'U2610999');
    type('iut-pass', 'typo');
    await send();
    assert.deepEqual(tried('saveLogin')[0].args, ['eclass', 'U2610999', 'typo']);
    assert.equal(submitted, 0, "eClass's form isn't tried a second time");
    assert.deepEqual(replaced, []);
    assert.match(shown(), /eClass rejected this username or password\./);
  });

  test('once accepted the browser is signed in, and the view the link wanted opens', async () => {
    place.hash = '#/grades/2622';
    await show(parts.SignIn, { saved: null, form: eclassForm() });
    type('iut-user', 'U2610999');
    type('iut-pass', 'right');
    await send();
    assert.deepEqual(replaced, ['/#/grades/2622']);
    assert.equal(submitted, 0);
  });

  test("the worker can't reach eClass: eClass's own form still tries", async () => {
    answer = (rpc) => (rpc === 'saveLogin' ? { name: 'NetworkError', message: 'down' } : null);
    const form = eclassForm();
    await show(parts.SignIn, { saved: null, form });
    type('iut-user', ' U2610999 ');
    type('iut-pass', 'right');
    await send();
    assert.equal(submitted, 1);
    assert.equal((form.querySelector('input[name="username"]') as unknown as HTMLInputElement).value, 'U2610999');
    assert.deepEqual(replaced, []);
  });

  test('Remember unticked saves nothing and uses the form', async () => {
    await show(parts.SignIn, { saved: null, form: eclassForm() });
    type('iut-user', 'U2610999');
    type('iut-pass', 'right');
    const box = root.querySelector('input[type="checkbox"]') as unknown as HTMLInputElement;
    box.checked = false;
    box.dispatchEvent(new window.Event('change'));
    await settle();
    await send();
    assert.equal(tried('saveLogin').length, 0);
    assert.equal(submitted, 1);
  });

  test("Continue goes on, and keeps a view's route", async () => {
    answer = (rpc) => (rpc === 'eclassAutoLogin' ? true : null);
    place.hash = '#/deadlines';
    await show(parts.SignIn, { saved: 'U2610999', form: eclassForm() });
    root.querySelector('.continue')!.dispatchEvent(new window.Event('click'));
    await settle();
    assert.deepEqual(replaced, ['/#/deadlines']);
    assert.ok(tabStore.has('iut.signInTry'));
  });

  test("back here right after signing in: no loop, and the tab's own form does it", async () => {
    tabStore.set('iut.signInTry', String(Date.now() - 3000));
    await show(parts.SignIn, { saved: 'U2610999', form: eclassForm() });
    assert.ok(!root.querySelector('.continue'));
    assert.match(shown(), /keeps its own session/);
    assert.equal(tabStore.has('iut.signInTry'), false);
    type('iut-user', 'U2610999');
    type('iut-pass', 'right');
    await send();
    assert.equal(submitted, 1);
    assert.deepEqual(replaced, []);
  });
});
