import { beforeEach, describe, test } from 'node:test';
import assert from 'node:assert/strict';
import { readFileSync } from 'node:fs';
import { fixture } from './setup.ts';
import { documentTokens, isDark } from '../src/content/theme.ts';
import { ParseError } from '../src/core/errors.ts';
import type { HttpRequest, HttpResponse } from '../src/core/http.ts';
import { isMarked, itemScore, plainNumber, type Course, type CourseGrades, type GradeItem } from '../src/core/models.ts';
import { gradeCourseId, gradeKey, planNotifications } from '../src/data/rules.ts';
import { CourseScore, isAttendanceMark, markedLine } from '../src/data/scores.ts';
import { EclassClient } from '../src/services/eclass/client.ts';
import { parseActivityGrades, parseAssignMax, parseGradeBook } from '../src/services/eclass/parsers.ts';

const ai: Course = { id: 2626, name: 'Artificial Intelligence', code: 'SOC4040', professor: '' };
const book = parseGradeBook(fixture('eclass_grades.html'), ai)!;
const item = (name: string) => book.items.find((i) => i.name === name)!;

const row = (over: Partial<GradeItem>): GradeItem => ({
  key: 'g1', name: 'Item', category: '', mark: '-', grade: null, max: null, weight: null, categoryWeight: null, contribution: null, moduleId: null, moduleType: null, ...over,
});

describe('plainNumber', () => {
  test('reads the way a mark reads best', () => {
    assert.deepEqual([37, 0.37, 6.25, 8.5, 100, 0].map(plainNumber), ['37', '0.37', '6.25', '8.5', '100', '0']);
  });
});

describe('parseGradeBook', () => {
  test('reads items with their category, weight, range and contribution', () => {
    const hw = item('Homework-1');
    assert.equal(hw.key, 'm7001');
    assert.deepEqual([hw.moduleType, hw.moduleId], ['assign', 7001]);
    assert.equal(hw.category, 'Assign');
    assert.deepEqual([hw.weight, hw.categoryWeight], [50, 20]);
    assert.deepEqual([hw.mark, hw.grade, hw.max, hw.contribution], ['8.50', 8.5, 10, 8.5]);
    assert.equal(itemScore(hw), '8.5 / 10');
    assert.ok(isMarked(hw));
  });

  test('an unmarked item, and a manual one with no link, keeps its grade item id', () => {
    const hw2 = item('Homework-2');
    assert.equal(hw2.key, 'g204');
    assert.deepEqual([isMarked(hw2), hw2.grade, hw2.contribution], [false, null, 0]);
  });

  test('an item directly under the course has the whole course as its category', () => {
    const quiz = item('[QUIZ] Week 6');
    assert.deepEqual([quiz.category, quiz.categoryWeight, quiz.weight], ['', 100, 0]);
    assert.equal(item('Attendance book').weight, null);
  });

  test('category names and weights come from the headings and total rows, totals are not items', () => {
    assert.deepEqual(book.categories, [
      { name: 'Midterm exam', weight: 25 },
      { name: 'Final exam', weight: 25 },
      { name: 'Assign', weight: 20 },
      { name: 'Etc.', weight: 30 },
    ]);
    const names = book.items.map((i) => i.name);
    assert.ok(!names.includes('Assign SUM'));
    assert.ok(!names.includes('Course total'));
    assert.equal(book.percent, 28.5);
    assert.equal(book.source, 'gradebook');
  });

  test("where a course hides the Percentage column, the total is its Grade over its Range", () => {
    const hidden = fixture('eclass_grades.html').replace('column-percentage">28.50 %</td>', 'column-percentage"></td>').replace('column-grade">35.63</td>', 'column-grade">0.11</td>').replace('column-range">0–125</td>', 'column-range">0–200</td>');
    assert.equal(parseGradeBook(hidden, ai)!.percent, 0.055);
  });

  test('a page with no table is a closed page; any other page has changed', () => {
    assert.equal(parseGradeBook('<html><body id="page-grade-report-user-index">Can not view grades.</body></html>', ai), null);
    assert.throws(() => parseGradeBook(fixture('eclass_dashboard.html'), ai), ParseError);
  });

  test('survives the cache', () => {
    assert.deepEqual(JSON.parse(JSON.stringify(book)), book);
  });
});

describe('parseActivityGrades', () => {
  test('a quiz list has the mark and its maximum', () => {
    const quizzes = parseActivityGrades(fixture('eclass_quiz_index.html'), 'quiz');
    assert.deepEqual(quizzes.map((q) => [q.key, q.name, q.category]), [['m8001', 'Quiz 1', 'Quizzes'], ['m8002', 'Quiz 2', 'Quizzes']]);
    assert.deepEqual([quizzes[0].grade, quizzes[0].max, itemScore(quizzes[0])], [37, 100, '37 / 100']);
    assert.ok(!isMarked(quizzes[1]));
  });

  test('an assignment list has the mark alone, and skips the spacer rows', () => {
    const list = parseActivityGrades(fixture('eclass_assign_index.html'), 'assign');
    assert.deepEqual(list.map((a) => a.name), ['Assignment 1', 'Assignment 2']);
    assert.deepEqual([list[0].grade, list[0].max, itemScore(list[0])], [85, null, '85']);
    assert.ok(!isMarked(list[1]));
  });

  test('a course with none has no table; any other page has changed', () => {
    assert.deepEqual(parseActivityGrades('<html><body id="page-mod-quiz-index">There are no Quizzes</body></html>', 'quiz'), []);
    assert.throws(() => parseActivityGrades(fixture('eclass_dashboard.html'), 'quiz'), ParseError);
  });

  test('parseAssignMax reads the Feedback box', () => {
    const page = (grade: string) =>
      `<html><body id="page-mod-assign-view"><div class="feedback"><table><tr><td>Grade</td><td>${grade}</td></tr><tr><td>Graded on</td><td>2026-10-30 12:00</td></tr></table></div></body></html>`;
    assert.equal(parseAssignMax(page('85.00 / 100.00')), 100);
    assert.equal(parseAssignMax(page('A')), null);
    assert.equal(parseAssignMax('<html><body id="page-mod-assign-view">Not graded</body></html>'), null);
    assert.throws(() => parseAssignMax(fixture('eclass_dashboard.html')), ParseError);
  });
});

describe('EclassClient.courseGrades', () => {
  const logout = '<a href="/login/logout.php?sesskey=K">Log out</a>';
  const fake = (pages: Record<string, { status?: number; body: string }>, asked: string[] = []): EclassClient =>
    new EclassClient(
      async () => ({ username: 'u', password: 'p' }),
      async (url: string, _req?: HttpRequest): Promise<HttpResponse> => {
        const path = new URL(url).pathname + new URL(url).search;
        asked.push(path);
        const page = pages[path] ?? { status: 404, body: `${logout}Not found` };
        return {
          status: page.status ?? 200,
          url,
          redirected: false,
          headers: new Headers(),
          bytes: new Uint8Array(),
          text: () => page.body,
        };
      },
    );

  test('an open grades page is all it asks for', async () => {
    const asked: string[] = [];
    const g = await fake({ '/grade/report/user/index.php?id=2626': { body: fixture('eclass_grades.html') } }, asked).courseGrades(ai);
    assert.equal(g.source, 'gradebook');
    assert.equal(g.percent, 28.5);
    assert.equal(asked.length, 1);
  });

  test('a closed page falls back on the lists, and a marked assignment finds its maximum', async () => {
    const g = await fake({
      '/grade/report/user/index.php?id=2626': { status: 404, body: `${logout}Can not view grades.` },
      '/mod/assign/index.php?id=2626': { body: fixture('eclass_assign_index.html') },
      '/mod/quiz/index.php?id=2626': { body: fixture('eclass_quiz_index.html') },
      '/mod/assign/view.php?id=9001': {
        body: `<html><body id="page-mod-assign-view">${logout}<div class="feedback"><table><tr><td>Grade</td><td>85.00 / 100.00</td></tr></table></div></body></html>`,
      },
    }).courseGrades(ai);
    assert.equal(g.source, 'activities');
    assert.equal(g.percent ?? null, null);
    assert.deepEqual(g.items.map((i) => i.name), ['Assignment 1', 'Assignment 2', 'Quiz 1', 'Quiz 2']);
    assert.equal(itemScore(g.items[0]), '85 / 100');
    assert.equal(CourseScore.of(g), null);
  });

  test("an assignment page that fails only costs the maximum", async () => {
    const g = await fake({
      '/grade/report/user/index.php?id=2626': { status: 404, body: `${logout}Can not view grades.` },
      '/mod/assign/index.php?id=2626': { body: fixture('eclass_assign_index.html') },
      '/mod/assign/view.php?id=9001': { status: 403, body: `${logout}Denied` },
    }).courseGrades(ai);
    assert.equal(itemScore(g.items[0]), '85');
  });

  test('nothing anywhere has nothing to show', async () => {
    const g = await fake({}).courseGrades(ai);
    assert.deepEqual([g.source, g.items.length], ['none', 0]);
  });

  test('a page that changed is an error, not an empty course', async () => {
    await assert.rejects(
      fake({ '/grade/report/user/index.php?id=2626': { body: `${logout}<p>Something else</p>` } }).courseGrades(ai),
      ParseError,
    );
  });
});

describe('CourseScore', () => {
  const score = CourseScore.of(book)!;

  test("the accumulated score is eClass's course total", () => {
    assert.equal(score.accumulated, 28.5);
  });

  test('worth is item weight × category weight, empty categories count whole', () => {
    assert.deepEqual(Object.fromEntries(score.lines.map((l) => [l.name, l.worth])), {
      'Mid-term exam result': 25,
      'Homework-1': 10,
      'Homework-2': 10,
      'Final exam': 25,
      'Etc.': 30,
    });
    assert.equal(score.lines.reduce((s, l) => s + l.worth, 0), 100);
  });

  test('what is marked, what is open and the best still possible', () => {
    assert.equal(score.markedWorth, 35);
    assert.equal(score.openWorth, 65);
    assert.equal(score.best, 93.5);
  });

  test('what-if scores add to the total, as far as each line goes', () => {
    assert.equal(score.withScores({}), 28.5);
    assert.equal(score.withScores({ 'category:Final exam': 80 }), 48.5); // 80% of 25
    assert.equal(score.withScores({ g204: 5 }), 33.5); // 5 of 10 on a 10-point item
    assert.equal(score.withScores({ g204: 500 }), 38.5); // capped at 10 of 10
    assert.equal(score.withScores({ m7001: 0 }), 28.5); // already marked: not what-if
  });

  test('items with a weight of 0 add nothing; those with none are shown apart', () => {
    assert.deepEqual(score.uncounted.map((i) => i.name), ['[QUIZ] Week 6']);
    assert.deepEqual(score.unweighted.map((i) => i.name), ['Attendance book']);
  });

  // Live pages. The contribution column adds up 81 + 70 + 6.25 = 157.25 here; eClass's own total is 26 of 100.
  const hiddenCategories: CourseGrades = {
    course: ai,
    source: 'gradebook',
    percent: 26,
    categories: [{ name: 'Midterm', weight: null }, { name: 'Attendance', weight: null }, { name: 'Assign', weight: null }],
    items: [
      row({ key: 'm1', name: 'Midterm', category: 'Midterm', mark: '81.00', grade: 81, max: 100, weight: 100, contribution: 81 }),
      row({ key: 'm2', name: 'Attendance', category: 'Attendance', mark: '14.00', grade: 14, max: 20, weight: 100, contribution: 70 }),
      row({ key: 'm3', name: 'Lab 1', category: 'Assign', mark: '10.00', grade: 10, max: 10, weight: 6.25, contribution: 6.25 }),
    ],
  };

  test("the course total is eClass's, not what its contribution column adds up to", () => {
    const s = CourseScore.of(hiddenCategories)!;
    assert.equal(s.line, '26 of 100');
    assert.deepEqual([s.accumulated, s.outOf], [26, 100]);
  });

  test('marks under a hidden category weight are shown, and make no invented points', () => {
    const s = CourseScore.of(hiddenCategories)!;
    assert.deepEqual(s.lines, []);
    assert.deepEqual(s.unweighted.map((i) => i.name), ['Midterm', 'Attendance', 'Lab 1']);
    assert.equal(s.complete, false);
  });

  test('a column that holds a raw mark does not count for more than its share', () => {
    const s = CourseScore.of({
      course: ai, source: 'gradebook', categories: [],
      items: [
        row({ key: 'm1', name: 'Project', mark: '75.25', grade: 75.25, max: 100, weight: 30, categoryWeight: 100, contribution: 75.25 }),
        row({ key: 'm2', name: 'Final', mark: '-', max: 100, weight: 70, categoryWeight: 100, contribution: 0 }),
      ],
    })!;
    assert.equal(s.lines[0].earned, 22.575);
    assert.equal(s.line, '22.57 of 100');
    assert.equal(s.complete, true);
  });

  test('with no total and weights past 100, the score says what it is out of', () => {
    const s = CourseScore.of({
      course: ai, source: 'gradebook', categories: [],
      items: [
        row({ key: 'm1', name: 'A', mark: '50.00', grade: 50, max: 100, weight: 100, categoryWeight: 100 }),
        row({ key: 'm2', name: 'B', mark: '-', max: 100, weight: 100, categoryWeight: 100 }),
      ],
    })!;
    assert.deepEqual([s.accumulated, s.outOf, s.line, s.of(75)], [50, 200, '50 of 200', '75 of 200']);
  });

  test("a mark that is not a number takes eClass's figure, no more than the line is worth", () => {
    const letter = (contribution: number): CourseGrades => ({
      course: ai, source: 'gradebook', categories: [],
      items: [row({ key: 'm1', name: 'A', mark: 'A', max: null, weight: 20, categoryWeight: 100, contribution })],
    });
    assert.equal(CourseScore.of(letter(15))!.accumulated, 15);
    assert.equal(CourseScore.of(letter(95))!.accumulated, 20);
  });

  test('a category holding categories is counted through them, not again', () => {
    const page = `<html><body id="page-grade-report-user-index"><table class="user-grade"><tbody>
      <tr><th class="level1 column-itemname">Course</th></tr>
      <tr><th class="level2 column-itemname">Exams</th></tr>
      <tr><th class="level3 column-itemname">Midterm</th></tr>
      <tr><th class="level3 baggt column-itemname">Midterm total</th><td class="column-weight">50.00 %</td></tr>
      <tr><th class="level3 column-itemname">Final</th></tr>
      <tr><th class="level3 baggt column-itemname">Final total</th><td class="column-weight">50.00 %</td></tr>
      <tr><th class="level2 baggt column-itemname">Exams total</th><td class="column-weight">40.00 %</td></tr>
      <tr><th class="level2 column-itemname">Assign</th></tr>
      <tr><th class="level2 baggt column-itemname">Assign total</th><td class="column-weight">60.00 %</td></tr>
      <tr><th class="level1 baggt column-itemname">Course total</th><td class="column-grade">-</td><td class="column-range">0–100</td></tr>
    </tbody></table></body></html>`;
    const g = parseGradeBook(page, ai)!;
    assert.deepEqual(g.categories, [{ name: 'Midterm', weight: 20 }, { name: 'Final', weight: 20 }, { name: 'Assign', weight: 60 }]);
    assert.deepEqual(CourseScore.of(g)!.lines.map((l) => [l.name, l.worth]), [['Midterm', 20], ['Final', 20], ['Assign', 60]]);
  });

  test('no weights at all, or marks from the activity lists: no score', () => {
    const noWeights: CourseGrades = { course: ai, source: 'gradebook', categories: [{ name: 'Assign', weight: null }], items: [row({ category: 'Assign', max: 10 })] };
    assert.equal(CourseScore.of(noWeights), null);
    const activities: CourseGrades = { course: ai, source: 'activities', categories: [], items: [row({ key: 'm1', category: 'Quizzes', mark: '37.00/100.00', grade: 37, max: 100 })] };
    assert.equal(CourseScore.of(activities), null);
  });

  test('how much is marked, in a line', () => {
    assert.equal(markedLine(book), '4 of 5 marked');
    assert.equal(markedLine({ ...book, items: [row({})] }), 'Nothing marked yet');
  });
});

describe('planNotifications, grades', () => {
  const now = new Date(2026, 9, 22, 12).getTime();
  const plan = (seen: Record<string, string>, at = now, quiet = false) =>
    planNotifications({ now: at, courseGrades: [book], seenGrades: { [ai.id]: seen }, quiet });
  const allSeen = { m7000: '20.00', m7001: '8.50', m7002: '99.25' };
  const fresh = { m7000: '20.00', m7002: '99.25' };

  test('a new mark goes out once, with the score so far', () => {
    const [n, ...rest] = plan(fresh);
    assert.equal(rest.length, 0);
    assert.equal(n.title, 'Graded: Homework-1');
    assert.equal(n.body, 'Artificial Intelligence · 8.5 / 10 · 28.5 of 100 so far');
    assert.equal(n.channel, 'grades');
    assert.equal(n.when, now);
    assert.equal(gradeCourseId(n.key), ai.id);
  });

  test('a changed mark says so and says what it was', () => {
    const [n] = plan({ ...allSeen, m7001: '7.00' });
    assert.equal(n.title, 'Grade changed: Homework-1');
    assert.match(n.body, /was 7/);
    assert.notEqual(n.key, plan(fresh)[0].key);
  });

  test('nothing new, unmarked items and the attendance book stay quiet', () => {
    assert.deepEqual(plan(allSeen), []);
    assert.ok(isAttendanceMark(item('Attendance book')));
    assert.ok(!isAttendanceMark(item('Homework-1')));
    assert.ok(isAttendanceMark(row({ category: '출석' })));
  });

  test('a mark found at night waits for the morning', () => {
    const [n] = plan(fresh, new Date(2026, 9, 22, 23, 30).getTime(), true);
    assert.equal(n.when, new Date(2026, 9, 23, 7, 30).getTime());
    assert.equal(n.quiet, false);
  });

  test('keys belong to grades alone', () => {
    assert.equal(gradeCourseId('absent:2626|2026-10-01|x'), null);
    assert.equal(gradeKey(1, item('Homework-1'), undefined), 'grade:1|m7001|>8.50');
    assert.equal(gradeKey(1, item('Homework-1'), '7.00'), 'grade:1|m7001|7.00>8.50');
  });
});

// The notifier, against a stand-in for chrome.storage, chrome.notifications and chrome.alarms.
const opened: string[] = [];
const shown: { id: string; title: string }[] = [];
let store: Record<string, unknown> = {};
let failing = false;
let permission = 'granted';

(globalThis as { chrome?: unknown }).chrome = {
  runtime: { getURL: (p: string) => `ext://${p}` },
  storage: {
    local: {
      get: async (k: string | null) => (k == null ? { ...store } : { [k]: store[k] }),
      set: async (o: Record<string, unknown>) => void Object.assign(store, JSON.parse(JSON.stringify(o))),
      remove: async (k: string | string[]) => void [k].flat().forEach((x) => delete store[x]),
    },
  },
  notifications: {
    create: async (id: string, o: { title: string }) => {
      if (failing) throw new Error('blocked');
      shown.push({ id, title: o.title });
    },
    clear: () => {},
    getPermissionLevel: (cb: (l: string) => void) => cb(permission),
  },
  alarms: { create: async () => {}, clear: async () => {} },
  windows: { getLastFocused: async () => ({ id: 1 }) },
  tabs: { create: async (o: { url: string }) => void opened.push(o.url) },
};
const { forgetSeenGrades, onNotificationClick, postDueReminders } = await import('../src/background/notify.ts');

describe('notifier, grades', () => {
  const noon = new Date(2026, 9, 22, 12).getTime();
  const put = (g: CourseGrades[]) => (store['cache.courseGrades'] = { value: g, fetchedAt: noon });
  const settings = (notify: object, quietHours = false) => (store.settings = { notify, quietHours });
  const seen = () => store['notify.seenGrades'] as Record<string, Record<string, string>>;
  const withMark = (mark: string): CourseGrades => ({
    course: ai, source: 'gradebook', percent: 5, categories: [],
    items: [row({ key: 'm1', name: 'Lab', mark, grade: Number(mark) || null, max: 10, weight: 50, categoryWeight: 100, contribution: Number(mark) || null })],
  });
  const empty: CourseGrades = { course: ai, source: 'none', categories: [], items: [] };

  beforeEach(() => {
    store = {};
    shown.length = 0;
    opened.length = 0;
    failing = false;
    permission = 'granted';
  });

  test('first sight of a course is a silent baseline; what changes after is announced once', async () => {
    put([withMark('5.00')]);
    await postDueReminders(noon);
    assert.equal(shown.length, 0);
    assert.deepEqual(seen(), { 2626: { m1: '5.00' } });

    put([withMark('6.00')]);
    await postDueReminders(noon + 1000);
    assert.deepEqual(shown.map((s) => s.title), ['Grade changed: Lab']);
    await postDueReminders(noon + 2000);
    assert.equal(shown.length, 1);
  });

  test('a course with nothing to show yet is no baseline: its first mark is news', async () => {
    put([empty]);
    await postDueReminders(noon);
    assert.deepEqual(seen(), { 2626: {} });
    put([withMark('5.00')]);
    await postDueReminders(noon + 1000);
    assert.deepEqual(shown.map((s) => s.title), ['Graded: Lab']);
  });

  test('nothing repeats, however long after, once the sent key has been dropped', async () => {
    put([empty]);
    await postDueReminders(noon);
    put([withMark('5.00')]);
    await postDueReminders(noon + 1000);
    await postDueReminders(noon + 120 * 24 * 3600e3); // past sentKeyRetention
    assert.equal(shown.length, 1);
  });

  test('a mark that could not be delivered stays new', async () => {
    put([empty]);
    await postDueReminders(noon);
    put([withMark('5.00')]);
    failing = true;
    await postDueReminders(noon + 1000);
    assert.deepEqual(seen()[ai.id], {});
    failing = false;
    await postDueReminders(noon + 2000);
    assert.deepEqual(shown.map((s) => s.title), ['Graded: Lab']);
    assert.deepEqual(seen()[ai.id], { m1: '5.00' });
  });

  test('blocked notifications keep a mark new too, without trying', async () => {
    put([empty]);
    await postDueReminders(noon);
    put([withMark('5.00')]);
    permission = 'denied';
    await postDueReminders(noon + 1000);
    assert.deepEqual(seen()[ai.id], {});
    permission = 'granted';
    await postDueReminders(noon + 2000);
    assert.equal(shown.length, 1);
  });

  test('with Grades off marks are recorded silently, so turning it on announces nothing old', async () => {
    put([empty]);
    await postDueReminders(noon);
    settings({ grades: false });
    put([withMark('5.00')]);
    await postDueReminders(noon + 1000);
    assert.equal(shown.length, 0);
    assert.deepEqual(seen()[ai.id], { m1: '5.00' });
    settings({ grades: true });
    await postDueReminders(noon + 2000);
    assert.equal(shown.length, 0);
  });

  test('at night a mark waits, and goes out in the morning', async () => {
    const night = new Date(2026, 9, 22, 23, 30).getTime();
    settings({}, true);
    put([empty]);
    await postDueReminders(night);
    put([withMark('5.00')]);
    await postDueReminders(night + 1000);
    assert.equal(shown.length, 0);
    assert.deepEqual(seen()[ai.id], {});
    await postDueReminders(new Date(2026, 9, 23, 7, 31).getTime());
    assert.deepEqual(shown.map((s) => s.title), ['Graded: Lab']);
  });

  test("an attendance mark is never announced", async () => {
    put([empty]);
    await postDueReminders(noon);
    put([{ ...empty, source: 'gradebook', items: [row({ key: 'g9', name: 'Attendance book', mark: '14.00', grade: 14, max: 20 })] }]);
    await postDueReminders(noon + 1000);
    assert.equal(shown.length, 0);
  });

  test('clicking one opens that course\'s scores, at a route the views can read', async () => {
    put([empty]);
    await postDueReminders(noon);
    put([withMark('5.00')]);
    await postDueReminders(noon + 1000);
    await onNotificationClick(shown[0].id);
    assert.deepEqual(opened, ['https://eclass.inha.ac.kr/#/grades/2626']);
  });

  test('signing out forgets what was announced', async () => {
    put([withMark('5.00')]);
    await postDueReminders(noon);
    await forgetSeenGrades();
    assert.equal(seen(), undefined);
  });
});

describe('the theme on eClass pages', () => {
  const css = documentTokens(readFileSync(new URL('../src/ui/theme.css', import.meta.url), 'utf8'));

  test('every token block reaches the document, dark included', () => {
    assert.match(css, /html\.iut, html\.iut-wait \{\s+color-scheme: light;/);
    assert.match(css, /@media \(prefers-color-scheme: dark\) \{\s+html\.iut:not\(\[data-theme="light"\]\), html\.iut-wait:not\(\[data-theme="light"\]\) \{\s+color-scheme: dark;/);
    assert.match(css, /html\.iut\[data-theme="dark"\], html\.iut-wait\[data-theme="dark"\] \{\s+color-scheme: dark;/);
    assert.ok(!/:root|:host/.test(css));
  });

  test("eClass's frame stays put: its Headroom plugin can't slide the header away", () => {
    const moodle = readFileSync(new URL('../src/content/moodle.css', import.meta.url), 'utf8');
    assert.match(moodle, /#page-header \.headroom \{ animation: none !important; transform: none !important; \}/);
    assert.match(moodle, /#page-header \{ position: sticky; top: 0;/);
  });

  test("the type scale stays out of eClass's pages", () => {
    assert.ok(!css.includes('.t-display'));
    assert.ok(!css.includes('.muted'));
  });

  test('the setting wins, and System follows the preference', () => {
    assert.equal(isDark('dark', false), true);
    assert.equal(isDark('light', true), false);
    assert.equal(isDark('system', true), true);
    assert.equal(isDark('system', false), false);
  });
});
