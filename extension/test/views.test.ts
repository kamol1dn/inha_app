// The views, drawn for real, as in mailview.test.ts: bundled as the build does
// and rendered into linkedom, with a fake worker behind `call` and a fake
// chrome.storage behind writeSettings. Nothing here touches a network.

import { afterEach, beforeEach, test } from 'node:test';
import assert from 'node:assert/strict';
import { readFileSync } from 'node:fs';
import { fileURLToPath } from 'node:url';
import * as esbuild from 'esbuild';
import { parseHTML } from 'linkedom';
import type { CourseAttendance, CourseGrades, Deadline, GradeItem, Lesson } from '../src/core/models.ts';
import { defaultSettings, type Settings, type Snapshot } from '../src/core/store.ts';
import type { EclassNotification } from '../src/services/eclass/parsers.ts';
import type { View } from '../src/ui/views/index.tsx';

const { window, document } = parseHTML('<!doctype html><html><head></head><body><div id="app"></div></body></html>');
const root = document.getElementById('app')!;

for (const e of ['click', 'input', 'change', 'keydown', 'mousedown', 'focus', 'blur', 'submit']) {
  (window.HTMLElement.prototype as unknown as Record<string, unknown>)[`on${e}`] = null;
}

const g = globalThis as unknown as Record<string, unknown>;
g.__DEV__ = false;
g.document = document;
g.requestAnimationFrame = (cb: () => void) => setTimeout(cb, 0);
g.cancelAnimationFrame = clearTimeout;
g.addEventListener = () => {};
g.removeEventListener = () => {};
g.location = { host: 'ext', search: '', hash: '' };
g.getComputedStyle = () => ({ fontSize: '60px' });
g.ResizeObserver = class {
  observe() {}
  disconnect() {}
};

const asked: { rpc: string; args: unknown[] }[] = [];
let answer: (rpc: string, args: unknown[]) => unknown = () => null;
let stored: Record<string, unknown> = {};
g.chrome = {
  runtime: {
    getURL: (p: string) => `ext://${p}`,
    getManifest: () => ({ version: '9.8.7' }),
    sendMessage: async ({ rpc, args }: { rpc: string; args: unknown[] }) => {
      asked.push({ rpc, args });
      try {
        return { ok: true, value: (await answer(rpc, args)) ?? null };
      } catch (e) {
        const { name, message } = e as Error;
        return { ok: false, error: { name, message } };
      }
    },
  },
  storage: {
    local: {
      get: async (k: string) => ({ [k]: stored[k] }),
      set: async (o: Record<string, unknown>) => void Object.assign(stored, o),
    },
  },
};

const bundle = await esbuild.build({
  stdin: {
    contents: `export { viewFor } from './src/ui/views/index.tsx'; export { Today } from './src/ui/views/today.tsx'; export { Schedule } from './src/ui/views/schedule.tsx'; export { Settings } from './src/ui/views/settings.tsx'; export { h, render } from 'preact';`,
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
interface Bundle {
  viewFor: (route: string[], snap: Snapshot, now: number) => View;
  h: (type: unknown, props?: unknown, ...children: unknown[]) => unknown;
  render: (vnode: unknown, at: Element) => void;
}
const ui = (await import(`data:text/javascript;base64,${Buffer.from(bundle.outputFiles[0].text).toString('base64')}`)) as Bundle;

// A Tuesday in November 2026, clear of every exam period.
const now = new Date(2026, 10, 10, 10, 0).getTime();
const cached = <T,>(value: T) => ({ value, fetchedAt: now - 60e3 });
const snapshot = (over: { settings?: Partial<Settings>; cache?: Snapshot['cache']; state?: Snapshot['state']; logins?: Snapshot['logins']; rejectedLogins?: Snapshot['rejectedLogins'] } = {}): Snapshot => ({
  cache: {},
  state: {},
  logins: {},
  rejectedLogins: [],
  ...over,
  settings: { ...defaultSettings, ...over.settings },
});
const failed = (name: string, message = '') => ({ error: { name, message }, at: now, busy: false });
const course = (id: number, name: string, marks: ('absent' | 'present')[] = ['present']): CourseAttendance => ({
  course: { id, name, code: 'SOC4020', professor: 'J. Hong' },
  classes: marks.map((mark, i) => ({ date: `2026-10-${String(i + 1).padStart(2, '0')}`, label: `${i + 1}Class`, mark })),
  vods: [],
});
const lesson = (weekday: number, subject: string): Lesson => ({ weekday, start: '13:00', end: '14:30', subject, room: 'B202', teacher: 'J. Hong', kind: 'Lecture' });

async function settle() {
  for (let i = 0; i < 6; i++) await new Promise((resolve) => setTimeout(resolve, 2));
}
async function show(route: string[], snap: Snapshot): Promise<View> {
  const view = ui.viewFor(route, snap, now);
  ui.render(view.body, root);
  await settle();
  return view;
}
const words = () => root.textContent!.replace(/\s+/g, ' ');
const has = (text: string) => assert.ok(words().includes(text), `no "${text}" in: ${words()}`);
const hasNot = (text: string) => assert.ok(!words().includes(text), `"${text}" in: ${words()}`);
const button = (text: string) => ([...root.querySelectorAll('button')] as unknown as HTMLButtonElement[]).find((b) => b.textContent!.trim() === text) ?? null;
async function click(text: string, within?: string) {
  const b = ([...root.querySelectorAll(`${within ?? ''} button`.trim())] as unknown as HTMLButtonElement[]).find((x) => x.textContent!.trim() === text);
  assert.ok(b, `no button "${text}" in: ${words()}`);
  b.dispatchEvent(new window.Event('click'));
  await settle();
}
const sent = (rpc: string) => asked.filter((a) => a.rpc === rpc);
const link = (text: string) => ([...root.querySelectorAll('a')] as unknown as HTMLAnchorElement[]).find((a) => a.textContent!.includes(text)) ?? null;

beforeEach(() => {
  asked.length = 0;
  answer = () => null;
  stored = {};
});

afterEach(async () => {
  ui.render(null, root);
  await settle();
});

// ---- Routes ----

test('every detail has a way back, and a course no longer listed says so (F77)', async () => {
  const snap = snapshot({ cache: { attendance: cached([course(1, 'Artificial Intelligence')]) } });
  assert.equal(ui.viewFor(['courses', '1'], snap, now).back, '#/courses');
  assert.equal(ui.viewFor(['courses'], snap, now).back, null);
  assert.equal(ui.viewFor(['grades', '1'], snap, now).back, '#/grades');
  assert.equal(ui.viewFor(['mail', 'inbox', 'm1'], snap, now).back, '#/mail/inbox');
  assert.equal(ui.viewFor(['mail', 'inbox'], snap, now).back, null);

  const gone = await show(['courses', '999'], snap);
  assert.equal(gone.back, '#/courses');
  has('eClass has no course with this link.');
  assert.equal((await show(['courses', 'abc'], snap)).back, '#/courses');
  has('eClass has no course with this link.');
});

test('a course page with eClass failing and no cache shows the failure, not bars (F77)', async () => {
  await show(['courses', '1'], snapshot({ state: { eclass: failed('ParseError') } }));
  has("Couldn't read the eClass page; it may have changed.");
  assert.equal(root.querySelector('.skeleton'), null);
});

test('signed out, with nothing cached, a tab says "Sign in" once, not bars', async () => {
  const out = snapshot({ state: { eclass: { error: null, at: 0, busy: false } } });
  for (const route of [['courses'], ['courses', '1'], ['deadlines'], ['grades', '1']]) {
    await show(route, out);
    has('Sign in to eClass to see deadlines and attendance.');
    assert.equal(root.querySelector('.skeleton'), null, route.join('/'));
  }
  // The refused sign-in is that same note, not a second "Sign in".
  await show(['deadlines'], snapshot({ state: { eclass: failed('LoginRequired') } }));
  has('Sign in to eClass');
  hasNot('sign-in needed');
  // Still on its way: bars.
  await show(['courses'], snapshot({ state: { eclass: { error: null, at: 0, busy: true } } }));
  assert.ok(root.querySelector('.skeleton'));
});

// ---- Attendance ----

test('Attendance leads to the limits, which are a view of their own (F76)', async () => {
  const snap = snapshot({ cache: { attendance: cached([course(1, 'Artificial Intelligence', ['absent']), course(2, 'VOD Only', [])]) } });
  await show(['courses'], snap);
  has('Set limits');
  assert.equal(link('Set limits')!.getAttribute('href'), '#/courses/limits');
  const view = await show(['courses', 'limits'], snap);
  assert.equal(view.title, 'Absence limits');
  assert.equal(view.back, '#/courses');
  has('Artificial Intelligence');
  hasNot('VOD Only');
  assert.ok(root.querySelector('[aria-label="Allowed absences in Artificial Intelligence"]'));
});

test('an empty list says so', async () => {
  await show(['courses'], snapshot({ cache: { attendance: cached([]) } }));
  has('eClass lists no courses for you.');
});

test('a course with no attendance has no count, no tally and no limit (X10)', async () => {
  const snap = snapshot({ cache: { attendance: cached([course(2, 'VOD Only', [])]) } });
  await show(['courses'], snap);
  has('No class attendance in eClass');
  hasNot('limit not set');
  assert.equal(root.querySelector('.tally'), null);
  await show(['courses', '2'], snap);
  has('No class attendance in eClass');
  hasNot('Set the absence limit');
});

test("a limit's field keeps what is typed through a redraw (F57)", async () => {
  const snap = snapshot({ cache: { attendance: cached([course(1, 'Artificial Intelligence')]) } });
  await show(['courses', 'limits'], snap);
  const field = () => root.querySelector('[aria-label="Allowed absences in Artificial Intelligence"]') as unknown as HTMLInputElement;
  field().value = '12';
  field().dispatchEvent(new window.Event('input'));
  await settle();
  ui.render(ui.viewFor(['courses', 'limits'], { ...snap }, now + 60e3).body, root);
  await settle();
  assert.equal(field().value, '12');
});

test('a VOD row links to its module only when it has one, and warns on a closed window (F154)', async () => {
  const c = course(1, 'Artificial Intelligence');
  c.vods = [
    { week: 7, title: 'Linked', lengthSec: 600, percent: 40, moduleId: 55, closes: now - 3600e3 },
    { week: 8, title: 'Unlinked', lengthSec: 600, percent: 100 },
  ];
  await show(['courses', '1'], snapshot({ cache: { attendance: cached([c]) } }));
  assert.equal(link('Linked')!.getAttribute('href'), 'https://eclass.inha.ac.kr/mod/vod/view.php?id=55');
  assert.equal(link('Unlinked'), null);
  has('Window closed Tue 10 Nov · 40% watched');
});

test('held classes leave out what is still to come today (F83)', async () => {
  const c = course(1, 'Artificial Intelligence');
  c.classes = [
    { date: '2026-11-03', label: 'Past', mark: 'unmarked' },
    { date: '2026-11-10', label: 'Later today', mark: 'unmarked' },
    { date: '2026-11-17', label: 'Next week', mark: 'unmarked' },
  ];
  await show(['courses', '1'], snapshot({ cache: { attendance: cached([c]) } }));
  has('1 held');
  has('Not marked');
  hasNot('Later today');
  hasNot('Next week');
});

// ---- Today ----

test('no timetable is not "no classes" (F54)', async () => {
  await show(['today'], snapshot({ state: { edupage: failed('NetworkError') }, cache: { attendance: cached([]) } }));
  hasNot('No classes today');
  has("Couldn't reach Timetable.");
  await show(['schedule'], snapshot({ state: { edupage: failed('SetupNeeded', 'Choose your class group in Settings.') } }));
  hasNot('No classes on');
  has('Choose your class group in Settings.');
  has('Settings');
  await show(['today'], snapshot({ cache: { lessons: cached([]), attendance: cached([]) } }));
  has('No classes today');
});

test('an empty day on Schedule names the next class (F186)', async () => {
  await show(['schedule', '2026-11-11'], snapshot({ cache: { lessons: cached([lesson(1, 'Artificial Intelligence')]) } }));
  has('No classes on Wed 11 Nov. Next: Mon 16 Nov, 13:00 Artificial Intelligence, B202.');
});

test('offline, Schedule has the one offline row, and its own says what is on screen (F89)', async () => {
  const net = failed('NetworkError');
  await show(['schedule'], snapshot({ state: { edupage: net, eclass: net }, cache: { lessons: cached([]) } }));
  has('Offline. Showing data from');
  hasNot("Couldn't reach");
  await show(['schedule'], snapshot({ state: { edupage: net }, cache: { lessons: cached([]) } }));
  has("Couldn't reach Timetable. Showing data from");
  hasNot('Check the connection');
  has('Retry');
});

test('a class on the rail opens its course, or Schedule on its day (F69)', async () => {
  const lessons = [lesson(2, 'Multimedia Computing'), lesson(2, 'Artificial Intelligence'), lesson(3, 'Mental Education')];
  lessons[1] = { ...lessons[1], start: '15:00', end: '16:00' };
  await show(['today'], snapshot({ cache: { lessons: cached(lessons), attendance: cached([course(7, 'Artificial Intelligence')]) } }));
  // Later today, with a course.
  assert.equal(link('Artificial Intelligence')!.getAttribute('href'), '#/courses/7');
  // Tomorrow, with none.
  assert.equal(link('Mental Education')!.getAttribute('href'), '#/schedule/2026-11-11');
});

test('an all-clear needs a refresh to back it (X3)', async () => {
  const deadlines: Deadline[] = [];
  const clear = { cache: { deadlines: cached(deadlines), lessons: cached([]), attendance: cached([]) } };
  await show(['today'], snapshot(clear));
  has('No deadlines in eClass.');
  await show(['today'], snapshot({ ...clear, state: { eclass: failed('LoginRequired') } }));
  hasNot('No deadlines in eClass.');
  has('eClass sign-in needed.');
});

test('Today marks old eClass data on the rail, and its footer gives the oldest source (X14)', async () => {
  const old = now - 5 * 3600e3;
  await show(['today'], snapshot({ cache: { deadlines: { value: [], fetchedAt: old }, lessons: cached([]), attendance: cached([]), inbox: cached([]) } }));
  has('eClass as of');
  has(`Updated ${new Date(old).toTimeString().slice(0, 5)}`);
});

// ---- Marks done ----

test('Mark as done writes the item, and the row then offers Undo (F163)', async () => {
  const d: Deadline = { title: 'Paper hand-in', courseName: 'Artificial Intelligence', kind: 'other', start: null, end: now + 48 * 3600e3, moduleId: 8, moduleType: 'ubboard', done: false, doneAt: null };
  const snap = snapshot({ cache: { deadlines: cached([d]) } });
  await show(['deadlines'], snap);
  await click('Mark as done');
  const { dismissed } = stored.settings as Settings;
  assert.equal(dismissed.length, 1);
  await show(['deadlines'], snapshot({ cache: snap.cache, settings: { dismissed } }));
  has('Marked done by you');
  assert.ok(button('Undo'));
  assert.equal(button('Mark as done'), null);
});

test('Nothing matches blames filters only when one is on (F84)', async () => {
  const cache = { deadlines: cached<Deadline[]>([]) };
  await show(['deadlines'], snapshot({ cache }));
  has('No upcoming deadlines in eClass.');
  hasNot('Nothing matches');
  await show(['deadlines'], snapshot({ cache, settings: { showDone: false } }));
  has('Nothing matches these filters.');
  await click('Clear filters');
  assert.equal((stored.settings as Settings).showDone, true);
});

// ---- From eClass ----

test('From eClass lists them all with their text, linked only when the link stays on eClass (F164)', async () => {
  const n = (id: number, over: Partial<EclassNotification>): EclassNotification => ({ id, subject: `Subject ${id}`, text: `Text ${id}`, url: null, time: now - 3600e3, read: false, ...over });
  const view = await show(['notifications'], snapshot({ cache: { notifications: cached([n(1, { url: 'https://eclass.inha.ac.kr/mod/assign/view.php?id=4' }), n(2, { url: 'https://example.org/x', read: true }), n(3, {})]) } }));
  assert.equal(view.title, 'From eClass');
  assert.equal(view.back, '#/today');
  for (const i of [1, 2, 3]) {
    has(`Subject ${i}`);
    has(`Text ${i}`);
  }
  assert.equal(root.querySelectorAll('a.row').length, 1);
  assert.equal(link('Subject 1')!.getAttribute('href'), 'https://eclass.inha.ac.kr/mod/assign/view.php?id=4');
  await show(['notifications'], snapshot({ cache: { notifications: cached([]) } }));
  has('No notifications from eClass.');
});

// ---- Scores ----

const item = (over: Partial<GradeItem>): GradeItem => ({ key: 'm1', name: 'Item', category: 'Assign', mark: '-', grade: null, max: 10, weight: 50, categoryWeight: 20, contribution: null, moduleId: null, moduleType: null, ...over });
const grades = (items: GradeItem[]): CourseGrades => ({ course: { id: 1, name: 'Artificial Intelligence', code: 'SOC4040', professor: '' }, source: 'gradebook', items, categories: [] }) as unknown as CourseGrades;

test('what-if: a comma counts as a point, and what is over the range says so (F73)', async () => {
  const snap = snapshot({ cache: { courseGrades: cached([grades([item({ name: '[QUIZ] 2 Week 6 - 2% (Quiz closes)', key: 'm1' }), item({ name: 'Homework-2', key: 'm2' })])]) } });
  await show(['grades', '1'], snap);
  const label = 'What-if score for Quiz 2 Week 6 - 2%';
  const field = root.querySelector(`[aria-label="${label}"]`) as unknown as HTMLInputElement;
  assert.ok(field, words());
  const type = async (text: string) => {
    field.value = text;
    field.dispatchEvent(new window.Event('input'));
    await settle();
  };
  await type('8,5');
  assert.equal(field.value, '8.5');
  has('With these scores: 8.5 of ');
  hasNot('Out of 10');
  await type('15');
  has("Out of 10. This one isn't counted.");
  hasNot('With these scores');
  assert.equal(field.getAttribute('aria-invalid'), 'true');
  await type('1.2.3');
  has('Out of 10.');
});

test('Scores tidies names and links an activity, leaving the field out of the link (F178, X18)', async () => {
  const snap = snapshot({
    cache: {
      courseGrades: cached([
        grades([
          item({ name: '[QUIZ] Week 6', key: 'm1', moduleId: 77, moduleType: 'quiz', mark: '8.00', grade: 8 }),
          item({ name: 'Homework-2', key: 'm2', moduleId: 78, moduleType: 'assign' }),
          item({ name: 'Manual', key: 'g3', mark: '5.00', grade: 5 }),
        ]),
      ]),
    },
  });
  await show(['grades', '1'], snap);
  hasNot('[QUIZ]');
  assert.equal(link('Week 6')!.getAttribute('href'), 'https://eclass.inha.ac.kr/mod/quiz/view.php?id=77');
  assert.equal(link('Homework-2')!.getAttribute('href'), 'https://eclass.inha.ac.kr/mod/assign/view.php?id=78');
  assert.equal(link('Manual'), null);
  assert.equal(root.querySelector('a input'), null);
});

// ---- Grades ----

test('Grades is one plain line, with no codes, and a term GPA (F90, F162, F184)', async () => {
  const report = {
    gpa: 3.87,
    creditsEarned: 98,
    yearOfStudy: 3,
    majorRequired: 72,
    records: [
      { term: 'Course registration', termKey: 20262, code: 'SOC9999', name: 'Now', credits: 3, letter: '-', points: 0, category: 'MR-M' },
      { term: '2025 Fall Semester', termKey: 20252, code: 'SOC4020', name: 'Then', credits: 1, letter: 'A+', points: 4.5, category: 'MR-M' },
    ],
  };
  await show(['grades'], snapshot({ cache: { grades: cached(report) } }));
  has('GPA of 4.5 · 98 credits · year 3');
  has('Credits by category');
  has('INS counts 72 major-required credits.');
  has('This semester');
  hasNot('Course registration');
  has('GPA 4.50 · 1 credit');
  hasNot('SOC4020');
  has('Not graded');
});

test('Grades flags marks that did not refresh (F185)', async () => {
  const state = { eclass: { error: null, at: now, busy: false, marksError: { name: 'NetworkError', message: '' } } };
  await show(['grades'], snapshot({ state, cache: { courseGrades: cached([grades([item({})])]) } }));
  has("Some marks didn't update from eClass.");
});

// ---- Exams ----

test('Exams works for a sole room, and keeps the sheet a click away (F75, F160)', async () => {
  // Inside the Fall 2026 midterm: outside a period there is nothing to show.
  const during = new Date(2026, 9, 26, 8, 0).getTime();
  const view = ui.viewFor(['exams'], snapshot({ cache: { lessons: cached([]), attendance: cached([]) } }), during);
  ui.render(view.body, root);
  await settle();
  has('None of your courses is on the');
  has('From “');
  await click('Show every exam');
  assert.ok(button('Hide other exams'));
  assert.ok(root.querySelectorAll('button.row').length > 0);
});

// ---- Settings ----

const accountSnap = (over = {}) => snapshot({ logins: { eclass: 'U1234567' }, state: { eclass: { error: null, at: now, busy: false } }, cache: { classGroups: cached(['CSE-23-1']) }, ...over });

test('Sign out asks first, and only then leaves (F62)', async () => {
  await show(['settings'], accountSnap());
  await click('Sign out');
  assert.equal(sent('clearLogin').length, 0);
  has('Sign out of eClass?');
  await click('Cancel', '.dialog');
  assert.equal(root.querySelector('.dialog'), null);
  assert.equal(sent('clearLogin').length, 0);
  await click('Sign out');
  await click('Sign out', '.dialog');
  assert.deepEqual(sent('clearLogin')[0].args, ['eclass']);
  assert.equal(root.querySelector('.dialog'), null);
});

async function saveLogin() {
  const pass = root.querySelector('#eclass-pass') as unknown as HTMLInputElement;
  pass.value = 'typed';
  pass.dispatchEvent(new window.Event('input'));
  await settle();
  root.querySelector('form')!.dispatchEvent(new window.Event('submit'));
  await settle();
  return pass;
}

test("saving a login leaves its status and Sign out on show (F62, X20)", async () => {
  await show(['settings'], accountSnap());
  const pass = await saveLogin();
  has('Signed in. Loading your data.');
  has('Saved for U1234567');
  assert.ok(button('Sign out'));
  assert.equal(pass.value, '');
});

test('a refused login says so and keeps the typing; an unreachable service saved it untested', async () => {
  answer = (rpc) => (rpc === 'saveLogin' ? { name: 'LoginRequired', message: '' } : null);
  await show(['settings'], accountSnap());
  let pass = await saveLogin();
  has('eClass rejected this username or password.');
  assert.equal(pass.value, 'typed');
  ui.render(null, root);
  await settle();

  answer = (rpc) => (rpc === 'saveLogin' ? { name: 'NetworkError', message: '' } : null);
  await show(['settings'], accountSnap());
  pass = await saveLogin();
  has("Saved, but not tested. Couldn't reach eClass.");
  assert.equal(pass.value, '');
});

test('a saved login refused later asks for the password again', async () => {
  await show(['settings'], accountSnap({ rejectedLogins: ['eclass'] }));
  has('Sign-in failed for U1234567.');
});

test('a refusal asks for the password; being signed out never blames it', async () => {
  await show(['settings'], accountSnap({ state: { eclass: { error: { name: 'LoginRequired', message: 'x', rejected: true }, at: now, busy: false } } }));
  has('Sign-in failed for U1234567.');
  ui.render(null, root);
  await settle();
  // eClass's own Log out: the next refresh has no login it may use, and tried none.
  await show(['settings'], accountSnap({ state: { eclass: { error: { name: 'LoginRequired', message: 'No eClass login saved' }, at: now, busy: false } } }));
  hasNot('Sign-in failed');
  has('Saved for U1234567 · signed out of eClass');
  assert.ok(button('Sign out'));
});

test('groups that failed to load say so, and Retry asks again (F88)', async () => {
  answer = (rpc) => {
    if (rpc === 'classGroups') throw Object.assign(new Error(''), { name: 'NetworkError' });
    return null;
  };
  await show(['settings'], snapshot());
  has('Groups not loaded');
  hasNot('Loading groups');
  answer = (rpc) => (rpc === 'classGroups' ? ['CSE-23-1'] : null);
  await click('Retry');
  assert.equal(sent('classGroups').length, 2);
  has('Choose your group');
  has('CSE-23-1');
  assert.equal(button('Retry'), null);
});

test('hidden subjects are picked from the timetable, plus what is already hidden (F179)', async () => {
  await show(
    ['settings'],
    snapshot({
      settings: { excludedSubjects: ['Mental Education'] },
      cache: { lessons: cached([lesson(1, 'Artificial Intelligence'), lesson(2, 'Artificial Intelligence')]), classGroups: cached([]) },
    }),
  );
  has('Mental Education');
  await click('Choose subjects');
  const boxes = [...root.querySelectorAll('.dialog input[type="checkbox"]')] as unknown as HTMLInputElement[];
  assert.equal(boxes.length, 2);
  boxes[0].checked = true;
  boxes[0].dispatchEvent(new window.Event('change'));
  await settle();
  await click('Save', '.dialog');
  assert.deepEqual((stored.settings as Settings).excludedSubjects, ['Mental Education', 'Artificial Intelligence']);
  assert.deepEqual(sent('sync').at(-1)!.args, ['edupage', true]);
  assert.equal(root.querySelector('.dialog'), null);
});

test('Settings has Absence limits and the version, and not on the welcome (F76, F183)', async () => {
  const snap = snapshot({ cache: { classGroups: cached([]), attendance: cached([course(1, 'Artificial Intelligence'), course(2, 'Deep Learning')]) }, settings: { absenceLimits: { 1: 8 } } });
  await show(['settings'], snap);
  has('Version 9.8.7');
  has('1 of 2 courses set');
  assert.equal(link('Absence limits')!.getAttribute('href'), '#/courses/limits');
});

// ---- The stylesheet ----

const css = readFileSync(new URL('../src/ui/app.css', import.meta.url), 'utf8');

test('Mail keeps its list when narrow (F50)', () => {
  assert.ok(!/grid-template-columns:\s*0\b/.test(css), 'a 0 track: the hidden folders take no cell, so the list lands in it');
  assert.ok(/\.mail\s+\.folders\s*\{[^}]*grid-column/.test(css), 'New and the folders stay reachable');
  assert.ok(css.includes('.mail:has(> .reader:not(.empty)) > .list { display: none; }'));
});

test('rows that are buttons keep the rule between them (F82)', () => {
  assert.ok(!/^button\.row\s*\{[^}]*\bborder\b/m.test(css));
  assert.ok(css.includes(':where(button.row) { border: 0; }'));
});

test('Undo stays readable under the pointer (F65)', () => {
  assert.ok(/\.toast \.btn:hover\s*\{[^}]*background: transparent/.test(css));
});

test('the bar keeps a long name on one line (F71)', () => {
  assert.ok(/\.bar h1\s*\{[^}]*white-space: nowrap[^}]*text-overflow: ellipsis/.test(css));
});

test('the popup has its tabs (F55)', () => {
  assert.ok(!/body\.popup \.nav \{ display: none; \}/.test(css));
  assert.ok(/body\.popup \.nav\s*\{[^}]*grid-row: 2/.test(css));
});

test('every class the views use is defined', () => {
  const dir = new URL('../src/ui/', import.meta.url);
  const theme = readFileSync(new URL('theme.css', dir), 'utf8');
  const files = ['common.tsx', 'rows.tsx', 'tally.tsx', 'main.tsx', ...['today', 'schedule', 'deadlines', 'courses', 'exams', 'grades', 'scores', 'settings', 'notifications'].map((v) => `views/${v}.tsx`)];
  const missing = new Set<string>();
  for (const f of files) {
    const source = readFileSync(new URL(f, dir), 'utf8');
    for (const m of source.matchAll(/class="([^"]+)"/g)) {
      for (const c of m[1].split(/\s+/)) if (c !== 'offline' && !new RegExp(`\\.${c}(?![\\w-])`).test(css + theme)) missing.add(`${c} (${f})`);
    }
  }
  assert.deepEqual([...missing], []);
});
