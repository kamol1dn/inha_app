// What the views compute, with no DOM: Today's lines and rail, Deadlines'
// sections, the what-if field, the tally, the failure lines.

import { describe, test } from 'node:test';
import assert from 'node:assert/strict';
import { termGpa, type CourseAttendance, type Deadline, type GradeRecord, type Lesson, type VodProgress } from '../src/core/models.ts';
import { defaultSettings, type Snapshot } from '../src/core/store.ts';
import { AbsenceState, withDismissed } from '../src/data/status.ts';
import {
  attendanceSummary,
  courseLine,
  creditsByCategory,
  creditWord,
  deadlineCourses,
  deadlineLine,
  deadlineSections,
  errorLine,
  insTotals,
  isOffline,
  nextClassSentence,
  nextLesson,
  nothingDue,
  noticeUrl,
  offlineCovers,
  oldestFetch,
  railLaterClasses,
  readWhatIf,
  tallyLabel,
  tallyStrokes,
  termLine,
  troubleLine,
  vodWindow,
} from '../src/ui/derive.ts';

// A Tuesday in November 2026, clear of every exam period.
const at = (day: number, h = 0, m = 0) => new Date(2026, 10, day, h, m).getTime();
const now = at(10, 10, 0);
const HOUR = 3600e3;

const course = (id: number, name: string, absent = 0, held = 8): CourseAttendance => ({
  course: { id, name, code: 'SOC4020', professor: '' },
  classes: Array.from({ length: held }, (_, i) => ({ date: `2026-10-${String(i + 1).padStart(2, '0')}`, label: `${i + 1}Class`, mark: i < absent ? ('absent' as const) : ('present' as const) })),
  vods: [],
});
const lesson = (weekday: number, subject: string, start = '13:00', room = 'B202'): Lesson => ({ weekday, start, end: '14:30', subject, room, teacher: 'J. Hong', kind: 'Lecture' });
const due = (over: Partial<Deadline> = {}): Deadline => ({ title: 'Lab 6', courseName: 'Multimedia Computing', kind: 'assignment', start: null, end: now + 5 * 24 * HOUR, moduleId: 1, moduleType: 'assign', done: false, doneAt: null, ...over });
const filters = { deadlineKinds: defaultSettings.deadlineKinds, deadlineCourse: '', showDone: true, dismissed: [] as string[] };

describe('attendanceSummary (F53)', () => {
  const ai = course(1, 'Artificial Intelligence', 6);
  const mc = course(2, 'Multimedia Computing', 2);
  const vod = course(3, 'VOD Only', 0, 0);

  test('one limit set out of five says nothing about the other four', () => {
    const att = [ai, mc, course(4, 'Deep Learning'), course(5, 'Data Mining', 1), vod];
    const s = attendanceSummary(att, { 4: 8 }, []);
    assert.equal(s.ok, '1 course is within its limit.');
    assert.equal(s.info, 'No limit set: Artificial Intelligence 6 · Multimedia Computing 2 · Data Mining 1');
  });

  test('every limit set, and fine', () => {
    assert.equal(attendanceSummary([ai, mc], { 1: 20, 2: 20 }, []).ok, 'All 2 courses are within their limit.');
    assert.equal(attendanceSummary([mc], { 2: 20 }, []).ok, 'The 1 course is within its limit.');
  });

  test('the others, beside a course in trouble', () => {
    const s = attendanceSummary([ai, mc, course(4, 'Deep Learning')], { 1: 8, 2: 20, 4: 20 }, []);
    assert.deepEqual(s.trouble.map((c) => c.course.id), [1]);
    assert.equal(s.ok, 'The other 2 courses are within their limit.');
    assert.equal(attendanceSummary([ai, mc], { 1: 8, 2: 20 }, []).ok, 'The other 1 course is within its limit.');
  });

  test('no course, or none with attendance, never reads "All 0 courses"', () => {
    assert.equal(attendanceSummary([], {}, []).ok, null);
    assert.equal(attendanceSummary([], {}, []).note, 'No course takes attendance in eClass.');
    assert.equal(attendanceSummary([vod], {}, []).ok, null);
    assert.equal(attendanceSummary([course(4, 'Deep Learning')], {}, []).note, 'No absences in 1 course.');
  });
});

describe('the next class (F177, F186, X13)', () => {
  const ai = course(1, 'Artificial Intelligence', 6);
  const lessons = [lesson(1, 'Artificial Intelligence'), lesson(3, 'Multimedia Computing', '09:00', '')];

  test('a course row says when, led by "Limit not set"', () => {
    assert.equal(courseLine(ai, 8, lessons, now), 'Next Mon 13:00 · B202');
    assert.equal(courseLine(ai, null, lessons, now), 'Limit not set · Next Mon 13:00 · B202');
    assert.equal(courseLine(ai, 8, [lesson(2, 'Artificial Intelligence')], now), 'Today 13:00 · B202');
  });

  test('a course with no attendance says so, whatever its limit', () => {
    assert.equal(courseLine(course(3, 'VOD Only', 0, 0), null, lessons, now), 'No class attendance in eClass');
  });

  test('trouble names the next class', () => {
    const s = AbsenceState.of(ai, { 1: 8 });
    assert.equal(troubleLine(s, ai, lessons, now), `${s.tag} · next Mon 13:00`);
    assert.equal(troubleLine(s, ai, [], now), s.tag);
  });

  test('the rail finds the next class up to a week ahead, for the first class and each course in trouble', () => {
    const friday = at(13, 18, 0);
    // Thursday-only timetable, seen on a Friday evening: 6 days on, past the old 3-day look.
    assert.equal(railLaterClasses([lesson(4, 'Multimedia Computing')], [], {}, friday)[0]?.start, at(19, 13, 0));
    const rail = railLaterClasses([lesson(1, 'Multimedia Computing'), lesson(4, 'Artificial Intelligence')], [ai], { 1: 8 }, friday);
    assert.deepEqual(rail.map((c) => c.lesson.subject), ['Multimedia Computing', 'Artificial Intelligence']);
    assert.equal(nextLesson([], now), null);
  });

  test('a course in trouble with a class left today gets no second row', () => {
    const today = [lesson(2, 'Artificial Intelligence'), lesson(3, 'Multimedia Computing')];
    assert.deepEqual(railLaterClasses(today, [ai], { 1: 8 }, now).map((c) => c.lesson.subject), ['Multimedia Computing']);
  });

  test('an empty day names the next class', () => {
    assert.equal(nextClassSentence(lessons, new Date(at(10)), now), 'Next: Wed 11 Nov, 09:00 Multimedia Computing.');
    assert.equal(nextClassSentence([lesson(1, 'Artificial Intelligence')], new Date(at(10)), now), 'Next: Mon 16 Nov, 13:00 Artificial Intelligence, B202.');
    assert.equal(nextClassSentence([], new Date(at(10)), now), '');
  });
});

describe('nothingDue', () => {
  test('names the next one past the rail, or that eClass lists none', () => {
    assert.equal(nothingDue([], [], now), 'No deadlines in eClass.');
    assert.match(nothingDue([due()], [], now), /^Nothing due in the next 3 days\. Next: Lab 6, Multimedia Computing, /);
    assert.equal(nothingDue([due({ done: true })], [], now), 'Nothing due in the next 3 days.');
  });
});

describe('deadlineSections (F78, F84, F180)', () => {
  test('what is still owed comes first, under Overdue, and done work stays under its day', () => {
    const late = due({ title: 'Late', end: now - 2 * HOUR });
    const done = due({ title: 'Done', end: now - 3 * HOUR, done: true });
    const later = due({ title: 'Later' });
    const { overdue, days } = deadlineSections([later, done, late], [], now, filters);
    assert.deepEqual(overdue.map((d) => d.title), ['Late']);
    assert.deepEqual(days.flatMap(([, l]) => l.map((d) => d.title)), ['Done', 'Later']);
  });

  test('past a day it is only old cache, as in the app', () => {
    const { overdue, days } = deadlineSections([due({ end: now - 25 * HOUR })], [], now, filters);
    assert.deepEqual([overdue.length, days.length], [0, 0]);
  });

  test('class periods stay out unless their chip is on, and are never overdue', () => {
    const period = due({ kind: 'classPeriod', end: now - HOUR });
    assert.equal(deadlineSections([period], [], now, filters).days.length, 0);
    const shown = deadlineSections([period], [], now, { ...filters, deadlineKinds: [...filters.deadlineKinds, 'classPeriod'] });
    assert.deepEqual([shown.overdue.length, shown.days.length], [0, 1]);
  });

  test('only a real filter counts as filtered', () => {
    assert.equal(deadlineSections([], [], now, filters).filtered, false);
    assert.equal(deadlineSections([], [], now, { ...filters, showDone: false }).filtered, true);
    assert.equal(deadlineSections([], [], now, { ...filters, deadlineCourse: 'Deep Learning' }).filtered, true);
    assert.equal(deadlineSections([], [], now, { ...filters, deadlineKinds: ['quiz'] }).filtered, true);
  });

  test('a course filter finds an event by the calendar\'s shortened name, and the choice stays on offer', () => {
    const att = [course(9, 'Multimedia Computing')];
    const short = due({ courseName: 'Multimedia', courseId: 9 });
    assert.equal(deadlineSections([short], att, now, { ...filters, deadlineCourse: 'Multimedia Computing' }).days.length, 1);
    assert.deepEqual(deadlineCourses([short], att, 'Dropped Course'), ['Dropped Course', 'Multimedia Computing']);
  });
});

describe('deadlineLine', () => {
  const vod = (percent: number): CourseAttendance => ({ ...course(9, 'Multimedia Computing'), vods: [{ week: 7, title: 'Video 7', lengthSec: 3000, percent, moduleId: 5 }] });
  const closing = (end: number) => due({ kind: 'vod', title: 'Video 7', moduleId: 5, moduleType: 'vod', end, courseId: 9 });

  test('a closed window never reads as time left', () => {
    assert.deepEqual(deadlineLine(closing(now - HOUR), [vod(62)], now), { text: 'Window closed · 62% watched', status: 'danger' });
  });

  test('an open one says how much is left', () => {
    assert.deepEqual(deadlineLine(closing(now + 5 * HOUR), [vod(62)], now), { text: '62% watched, 19 min left', status: 'danger' });
  });

  test('done says when, by calendar day and at any age (F85)', () => {
    const lastNight = deadlineLine(due({ done: true, doneAt: at(9, 23, 0), end: now - HOUR }), [], now);
    assert.deepEqual(lastNight, { text: 'Submitted Mon 23:00', status: 'ok' });
    const old = deadlineLine(due({ done: true, doneAt: at(1, 12, 0) }), [], now);
    assert.match(old.text, /^Submitted \S/);
  });

  test('marked done by hand says so', () => {
    const d = due({ kind: 'other', moduleId: 7, moduleType: 'ubboard' });
    assert.equal(deadlineLine(d, [], now).status, null);
    assert.deepEqual(deadlineLine(d, [], now, withDismissed([], d, true)), { text: 'Marked done by you', status: 'ok' });
    assert.deepEqual(deadlineSections([d], [], now, { ...filters, showDone: false, dismissed: withDismissed([], d, true) }).days, []);
  });
});

describe('vodWindow (F154)', () => {
  const v = (over: Partial<VodProgress>): VodProgress => ({ week: 7, title: 'Video 7', lengthSec: 3000, percent: 50, ...over });

  test('warns when it closed under 100%', () => {
    assert.deepEqual(vodWindow(v({ closes: now - HOUR }), now), { text: 'Window closed Tue 10 Nov · 50% watched', missed: true });
    assert.equal(vodWindow(v({ closes: now - HOUR, percent: 100 }), now).missed, false);
  });

  test('says nothing when the page gave no window', () => {
    assert.deepEqual(vodWindow(v({}), now), { text: '', missed: false });
    assert.match(vodWindow(v({ closes: now + 24 * HOUR }), now).text, /^Closes /);
    assert.match(vodWindow(v({ opens: now + 24 * HOUR }), now).text, /^Opens /);
  });
});

describe('grades (F90, F162)', () => {
  const r = (over: Partial<GradeRecord>): GradeRecord => ({ term: '2025 Fall Semester', termKey: 20252, code: 'A', name: 'A', credits: 3, letter: 'A+', points: 4.5, category: 'MR-M', ...over });

  test('one credit is one credit', () => {
    assert.deepEqual([1, 3, 1.5].map(creditWord), ['1 credit', '3 credits', '1.5 credits']);
  });

  test('term GPA is weighted by credits, leaving out letters with no points', () => {
    const term = [r({ code: 'A' }), r({ code: 'B', credits: 1, letter: 'B0', points: 3 }), r({ code: 'C', letter: 'P', points: 0 })];
    assert.equal(termGpa(term), (3 * 4.5 + 3) / 4);
    assert.equal(termLine(term, termGpa(term)), 'GPA 4.13 · 7 credits');
    assert.equal(termGpa([r({ letter: 'P', points: 0 })]), null);
    assert.equal(termLine([r({ letter: 'P', points: 0 })], null), '3 credits');
  });

  test('an F counts, and a figure off the scale means no GPA at all', () => {
    assert.equal(termGpa([r({ letter: 'F', points: 0 }), r({ code: 'B' })]), 2.25);
    assert.equal(termGpa([r({ points: 0 }), r({ code: 'B' })]), null);
    assert.equal(termGpa([r({ points: 95 })]), null);
  });

  test('credits by category: the latest result of a retake, nothing for a fail or an ungraded row', () => {
    const records = [
      r({ code: 'A', letter: 'F', points: 0, termKey: 20241 }),
      r({ code: 'A', termKey: 20252 }),
      r({ code: 'B', category: 'GR', credits: 2 }),
      r({ code: 'C', category: 'GR', letter: 'W', points: 0 }),
      r({ code: 'D', letter: '-', points: 0 }),
      r({ code: 'E', category: '', credits: 1 }),
    ];
    assert.deepEqual(creditsByCategory(records), [['MR-M', 3], ['GR', 2], ['Other', 1]]);
  });

  test("INS's own totals, when it gives them", () => {
    const report = { gpa: 3, creditsEarned: 90, yearOfStudy: 3, records: [] };
    assert.equal(insTotals(report), null);
    assert.equal(insTotals({ ...report, majorRequired: 72, generalRequired: null }), 'INS counts 72 major-required credits.');
    assert.equal(insTotals({ ...report, majorRequired: 72, generalRequired: 21 }), 'INS counts 72 major-required and 21 general-required credits.');
  });
});

describe('readWhatIf (F73)', () => {
  test('a comma is a decimal point', () => {
    assert.deepEqual(readWhatIf('8,5', 10), { text: '8.5', value: 8.5, bad: false });
  });

  test('over the maximum, or no number, counts for nothing and says so', () => {
    assert.deepEqual(readWhatIf('15', 10), { text: '15', value: null, bad: true });
    assert.deepEqual(readWhatIf('1.2.3', 10), { text: '1.2.3', value: null, bad: true });
  });

  test('empty is just empty, and other characters drop out', () => {
    assert.deepEqual(readWhatIf('', 10), { text: '', value: null, bad: false });
    assert.deepEqual(readWhatIf('7a', 10), { text: '7', value: 7, bad: false });
    assert.deepEqual(readWhatIf('10', 10), { text: '10', value: 10, bad: false });
  });
});

describe('tally (F67)', () => {
  test('gates of five: four uprights and a diagonal', () => {
    const t = tallyStrokes(5, null)!;
    assert.equal(t.strokes.length, 5);
    const uprights = t.strokes.filter((s) => s.x1 === s.x2);
    assert.equal(uprights.length, 4);
    const [slash] = t.strokes.filter((s) => s.x1 !== s.x2);
    assert.ok(slash.x1 < Math.min(...uprights.map((s) => s.x1)) && slash.x2 > Math.max(...uprights.map((s) => s.x1)));
    // 7 apart, and a gate's width plus 10 to the next.
    assert.deepEqual(uprights.map((s) => s.x1), [3, 10, 17, 24]);
    assert.equal(tallyStrokes(6, null)!.strokes[5].x1, 36);
  });

  test('faint strokes are painted first, so none cuts an inked one', () => {
    const t = tallyStrokes(2, 5)!;
    assert.deepEqual(t.strokes.map((s) => s.used), [false, false, false, true, true]);
  });

  test('over the limit shows every absence, all used', () => {
    assert.ok(tallyStrokes(10, 8)!.strokes.every((s) => s.used));
    assert.equal(tallyStrokes(10, 8)!.strokes.length, 10);
  });

  test('above 20 marks the words stand alone; nothing to draw is nothing', () => {
    assert.equal(tallyStrokes(1, 21), null);
    assert.equal(tallyStrokes(21, null), null);
    assert.ok(tallyStrokes(20, 20));
    assert.equal(tallyStrokes(0, null), null);
    assert.ok(tallyStrokes(0, 4));
  });

  test('says itself to a screen reader', () => {
    assert.equal(tallyLabel(6, 8), '6 of 8 allowed absences used');
    assert.equal(tallyLabel(1, null), '1 absence');
  });
});

describe('failures (F89, X14)', () => {
  const offline = { name: 'NetworkError', message: '' };
  const snap = (eclass: unknown, edupage: unknown) => ({ state: { eclass: { error: eclass }, edupage: { error: edupage } } }) as unknown as Snapshot;

  test('an error row says what happened and what is on screen', () => {
    const t = at(10, 8, 12);
    assert.equal(errorLine(offline, 'ins', t, new Date(now)), "Couldn't reach INS. Showing data from 08:12.");
    assert.equal(errorLine(offline, 'ins', null, new Date(now)), "Couldn't reach INS. Check the connection.");
    assert.equal(errorLine({ name: 'ParseError', message: '' }, 'eclass', t, new Date(now)), "Couldn't read the eClass page; it may have changed. Showing data from 08:12.");
    assert.equal(errorLine({ name: 'SetupNeeded', message: 'Choose your class group in Settings.' }, 'edupage', t, new Date(now)), 'Choose your class group in Settings.');
  });

  test('offline is both hosts failing on the network', () => {
    assert.equal(isOffline(snap(offline, offline)), true);
    assert.equal(isOffline(snap(offline, null)), false);
    assert.equal(isOffline(snap(offline, { name: 'NetworkError', message: '', status: 503 })), false);
    assert.equal(offlineCovers(snap(offline, offline), offline), true);
    assert.equal(offlineCovers(snap(offline, offline), { name: 'ParseError', message: '' }), false);
  });

  test('the age on show is the oldest main source, never mail', () => {
    const cached = (fetchedAt: number) => ({ fetchedAt, value: [] });
    const s = { cache: { lessons: cached(30), deadlines: cached(20), attendance: cached(25), inbox: cached(99) } } as unknown as Snapshot;
    assert.equal(oldestFetch(s), 20);
    assert.equal(oldestFetch({ cache: { inbox: cached(99) } } as unknown as Snapshot), null);
  });
});

describe('noticeUrl', () => {
  test('only ever to eClass: the link comes from a message', () => {
    assert.equal(noticeUrl({ url: 'https://eclass.inha.ac.kr/mod/ubboard/view.php?id=1' }), 'https://eclass.inha.ac.kr/mod/ubboard/view.php?id=1');
    assert.equal(noticeUrl({ url: 'https://eclass.inha.ac.kr.example.org/' }), null);
    assert.equal(noticeUrl({ url: 'https://example.org/' }), null);
    assert.equal(noticeUrl({ url: null }), null);
  });
});
