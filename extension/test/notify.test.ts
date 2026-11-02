// What goes out and when, beyond the grades rules in scores.test.ts: reminders
// replacing each other, exams, marked-done items, mail and eClass notifications
// at night, and what a click opens.
import { beforeEach, describe, test } from 'node:test';
import assert from 'node:assert/strict';
import './setup.ts';
import { browser, installFakeBrowser } from './fake_browser.ts';
import type { CourseAttendance, CourseGrades, Deadline, GradeItem, MailHeader } from '../src/core/models.ts';
import { writeCache, writeSettings } from '../src/core/store.ts';
import { readSheet, matchExams, type ExamPeriod } from '../src/data/exams.ts';
import { notificationId, planNotifications, reminderStem } from '../src/data/rules.ts';
import { AbsenceState, courseFor, courseOf, heldClasses, isDone, markedDone, needsAttention, vodFor, withDismissed } from '../src/data/status.ts';
import type { EclassNotification } from '../src/services/eclass/parsers.ts';

installFakeBrowser();
const { announceNewMail, announceNotices, forgetNotified, onNotificationClick, postDueReminders } = await import('../src/background/notify.ts');

const HOUR = 3600e3;
const noon = new Date(2026, 8, 22, 12).getTime();

const deadline = (over: Partial<Deadline> = {}): Deadline => ({
  title: 'Lab 5',
  courseName: 'Multimedia Computing',
  kind: 'assignment',
  start: null,
  end: noon + 48 * HOUR,
  moduleId: 7,
  moduleType: 'assign',
  done: false,
  doneAt: null,
  ...over,
});

const attendance = (id: number, name: string, over: Partial<CourseAttendance> = {}): CourseAttendance => ({
  course: { id, name, code: '', professor: '' },
  classes: [],
  vods: [],
  ...over,
});

const mailHeader = (id: string, unread = true): MailHeader => ({ id, from: 'Dean', to: '', subject: `About ${id}`, preview: '', received: 0, unread, hasAttachments: false });
const notice = (id: number, over: Partial<EclassNotification> = {}): EclassNotification => ({ id, subject: `Notice ${id}`, text: 'Read this', url: null, time: noon - HOUR, read: false, ...over });

beforeEach(() => {
  browser.reset();
});

describe('reminders for one item', () => {
  const at = (h: number) => noon + 48 * HOUR - h * HOUR;

  test('the 3 h reminder replaces the 24 h one: same notification id, its own sent record', async () => {
    await writeCache('deadlines', [deadline()]);
    await postDueReminders(at(23));
    await postDueReminders(at(2.5));
    assert.equal(browser.shown.length, 2);
    assert.equal(browser.shown[0].id, browser.shown[1].id);
    assert.equal(browser.shown[0].id, reminderStem(deadline()));
    const sent = Object.keys(browser.local.data['notify.sent'] as object);
    assert.deepEqual(sent.map((k) => k.split('|').pop()).sort(), ['24h', '3h']);
    await postDueReminders(at(2));
    assert.equal(browser.shown.length, 2, 'sent records still stop repeats');
  });

  test('a click after the second reminder still opens the item', async () => {
    await writeCache('deadlines', [deadline()]);
    await postDueReminders(at(2.5));
    await onNotificationClick(browser.shown[0].id);
    assert.deepEqual(browser.tabs.map((t) => t.url), ['https://eclass.inha.ac.kr/mod/assign/view.php?id=7']);
  });

  test('notificationId strips the lead from reminders only', () => {
    assert.equal(notificationId('due:quiz:a|b|c|3h'), 'due:quiz:a|b|c');
    assert.equal(notificationId('vod:a|b|c|48h'), 'vod:a|b|c');
    assert.equal(notificationId('exam:s|c|20261022T0900Z|eve'), 'exam:s|c|20261022T0900Z');
    assert.equal(notificationId('absent:1|2026-10-01|x'), 'absent:1|2026-10-01|x');
    assert.equal(notificationId('grade:1|m1|>5'), 'grade:1|m1|>5');
  });

  test('handed in elsewhere: the reminder in the tray is withdrawn', async () => {
    await writeCache('deadlines', [deadline()]);
    await postDueReminders(at(23));
    await writeCache('deadlines', [deadline({ done: true })]);
    await postDueReminders(at(22));
    assert.deepEqual(browser.cleared, [reminderStem(deadline())]);
    await postDueReminders(at(21));
    assert.equal(browser.cleared.length, 1);
  });

  test('still open: nothing is withdrawn', async () => {
    await writeCache('deadlines', [deadline()]);
    await postDueReminders(at(23));
    await postDueReminders(at(22));
    assert.deepEqual(browser.cleared, []);
  });
});

describe('marked done by hand', () => {
  test('stops its reminders and leaves the tray; isDone and the rail agree', async () => {
    const d = deadline({ end: noon + 2 * HOUR });
    await writeCache('deadlines', [d]);
    await postDueReminders(noon);
    assert.equal(browser.shown.length, 1);

    await writeSettings({ dismissed: withDismissed([], d, true) });
    await postDueReminders(noon + 1000);
    assert.deepEqual(browser.cleared, [reminderStem(d)]);

    const dismissed = withDismissed([], d, true);
    assert.equal(markedDone(d, dismissed), true);
    assert.equal(isDone(d, [], dismissed), true);
    assert.equal(isDone(d, []), false);
    assert.deepEqual(needsAttention([d], [], noon, dismissed), []);
    assert.deepEqual(needsAttention([d], [], noon).length, 1);
    assert.deepEqual(withDismissed(dismissed, d, false), []);
  });

  test('another item with the same title but another time is not marked', () => {
    const d = deadline();
    assert.equal(markedDone({ ...d, end: d.end + 60 * HOUR }, withDismissed([], d, true)), false);
  });
});

describe('exam reminders', () => {
  const period: ExamPeriod = readSheet({
    format: 1,
    id: 'test-mid',
    kind: 'midterm',
    term: 'Fall',
    source: 'test',
    exams: [
      { slot: 'Th-3', date: '2026-10-22', start: '14:00', end: '15:30', cell: 'Multimedia Computing', rooms: ['B209', 'B210'] },
      { slot: 'Fr-1', date: '2026-10-23', start: '08:00', end: '09:30', cell: 'Artificial Intelligence', rooms: [] },
    ],
  });
  const start = period.exams[0].start;
  const match = (rooms: Record<string, string> = {}) => matchExams(period, [{ name: 'Multimedia Computing', teachers: new Set(), eclass: null }, { name: 'Artificial Intelligence', teachers: new Set(), eclass: null }], '', rooms);
  const plan = (now: number, quiet = false, rooms: Record<string, string> = {}) => planNotifications({ now, exams: match(rooms), quiet }).filter((n) => n.title.endsWith('Multimedia Computing'));

  test('the evening before at 20:00 and 1 h before, with the rooms it may be in', () => {
    const [evening, soon] = plan(new Date(2026, 9, 20, 12).getTime());
    assert.deepEqual([new Date(evening.when).getHours(), new Date(evening.when).getDate()], [20, 21]);
    assert.equal(evening.channel, 'exams');
    // Word for word what rules.dart says, as test/notification_delivery_test.dart has it.
    assert.equal(evening.title, 'Exam: Multimedia Computing');
    assert.equal(evening.body, 'Thu 22 Oct, 14:00 · Room not set: B209 or B210');
    assert.equal(soon.when, start - HOUR);
    assert.equal(soon.title, 'Exam at 14:00: Multimedia Computing');
    assert.equal(soon.body, evening.body);
    assert.equal(notificationId(evening.key), notificationId(soon.key));
    assert.deepEqual([evening, soon].map((n) => n.key.split('|').at(-1)), ['eve', '1h']);
    assert.match(evening.key, /^exam:th-3\|multimedia computing\|\d{8}T\d{4}Z\|eve$/);
  });

  test('the room the student set wins', () => {
    const key = `test-mid|Th-3|Multimedia Computing`;
    assert.equal(plan(new Date(2026, 9, 20, 12).getTime(), false, { [key]: 'B210' })[1].body, 'Thu 22 Oct, 14:00 · Room B210');
  });

  test('found on the day, the evening one goes out at once and names the day', () => {
    const now = new Date(2026, 9, 22, 9).getTime();
    const [late] = plan(now);
    assert.equal(late.when, now);
    assert.equal(late.body, 'Thu 22 Oct, 14:00 · Room not set: B209 or B210');
  });

  test('a sitting with sections runs them together, and still says the room is not set', () => {
    const halls = readSheet({ format: 1, id: 'p', kind: 'midterm', term: '', source: '', exams: [{ slot: 'a', date: '2026-10-22', start: '09:00', end: '10:00', cell: 'Multimedia Computing', rooms: ['B304(A)', 'B304(B)', 'B304(C)', 'B305'] }] });
    const [n] = planNotifications({ now: new Date(2026, 9, 20, 12).getTime(), exams: matchExams(halls, [{ name: 'Multimedia Computing', teachers: new Set(), eclass: null }]) });
    assert.equal(n.body, 'Thu 22 Oct, 09:00 · Room not set: B304(A–C) or B305');
  });

  test('a sitting with no rooms says so; an hour before 07:30 moves out of quiet hours', () => {
    const ai = planNotifications({ now: new Date(2026, 9, 20, 12).getTime(), exams: match(), quiet: true }).filter((n) => n.title.endsWith('Artificial Intelligence'));
    assert.equal(ai[0].body, 'Fri 23 Oct, 08:00 · Room not set');
    assert.ok(ai.every((n) => !n.quiet));
  });

  test('over: none. Several sittings are flagged', () => {
    assert.deepEqual(plan(start + 1000), []);
    const twice = readSheet({
      format: 1, id: 'p', kind: 'midterm', term: '', source: '',
      exams: [
        { slot: 'a', date: '2026-10-22', start: '09:00', end: '10:00', cell: 'Multimedia Computing', rooms: ['B1'] },
        { slot: 'b', date: '2026-10-22', start: '12:00', end: '13:00', cell: 'Multimedia Computing', rooms: ['B2'] },
      ],
    });
    const [n] = planNotifications({ now: new Date(2026, 9, 20, 12).getTime(), exams: matchExams(twice, [{ name: 'Multimedia Computing', teachers: new Set(), eclass: null }]) });
    assert.equal(n.body, 'Thu 22 Oct, 09:00 · Room B1. The timetable lists 2 sittings; check which is yours.');
  });

  test('a class that day stays silent, the exam does not', () => {
    const now = new Date(2026, 9, 22, 9).getTime();
    const lessons = [{ weekday: 4, start: '10:00', end: '11:00', subject: 'Multimedia Computing', room: 'B1', teacher: '', kind: '' }];
    const planned = planNotifications({ now, lessons, classFree: new Set(['2026-10-22']), exams: match() });
    assert.ok(planned.every((n) => n.channel === 'exams'));
    assert.ok(planned.length > 0);
  });
});

describe('finding the VOD behind a reminder', () => {
  const vod = deadline({ kind: 'vod', moduleType: 'vod', title: 'Video 7', courseName: 'Distinguished Lecture in Social', moduleId: 72441 });
  const course = (over = {}) => attendance(2592, 'Distinguished Lecture in Social Science and Art', { vods: [{ week: 7, title: 'Video 7', lengthSec: 3333, percent: 100, ...over }] });

  test('a cut-short calendar name still finds the course, so a watched VOD gets no reminder', () => {
    assert.deepEqual(planNotifications({ now: noon, deadlines: [vod], attendance: [course()] }), []);
    assert.equal(isDone(vod, [course()]), true);
  });

  test('the course id on the event wins over the name', () => {
    const other = attendance(9, 'Distinguished Lecture in Social');
    assert.equal(courseOf({ ...vod, courseId: 2592 }, [other, course()])?.course.id, 2592);
    assert.equal(courseOf(vod, [other, course()])?.course.id, 9);
  });

  test('the module id wins over the title, for a VOD renamed since', () => {
    const renamed = course({ title: 'Video 7 (new)', moduleId: 72441 });
    assert.equal(vodFor(vod, [renamed])?.title, 'Video 7 (new)');
    assert.deepEqual(planNotifications({ now: noon, deadlines: [vod], attendance: [renamed] }), []);
  });
});

describe('courseFor', () => {
  const a = attendance(1, 'Database');
  const b = attendance(2, 'Database Management');

  test('an exact name wins, wherever it is in the list', () => {
    assert.equal(courseFor('Database Management', [a, b])?.course.id, 2);
    assert.equal(courseFor('Database', [b, a])?.course.id, 1);
  });

  test('a prefix either way, the longest course name the given one starts with', () => {
    assert.equal(courseFor('Database Management Systems', [a, b])?.course.id, 2);
    assert.equal(courseFor('Data', [b])?.course.id, 2);
  });

  test('a prefix several courses start with is no match', () => {
    assert.equal(courseFor('Data', [a, b]), null);
    assert.equal(courseFor('', [a]), null);
  });
});

describe('AbsenceState.line', () => {
  test('the "N of M" form always says absences; the count alone agrees with its number', () => {
    assert.equal(new AbsenceState(1, 2).line, '1 of 2 absences used');
    assert.equal(new AbsenceState(3, 4).line, '3 of 4 absences used');
    assert.equal(new AbsenceState(1, 0).line, '1 absence · limit 0');
    assert.equal(new AbsenceState(5, 4).line, '5 absences · limit 4');
    assert.equal(new AbsenceState(1, null).line, '1 absence · limit not set');
  });
});

describe('heldClasses', () => {
  test('an unmarked class today has not been held yet; a marked one has', () => {
    const c = attendance(1, 'AI', {
      classes: [
        { date: '2026-09-21', label: '1', mark: 'unmarked' },
        { date: '2026-09-22', label: '2', mark: 'unmarked' },
        { date: '2026-09-22', label: '3', mark: 'present' },
        { date: '2026-09-23', label: '4', mark: 'unmarked' },
      ],
    });
    assert.deepEqual(heldClasses(c, noon).map((e) => e.label), ['1', '3']);
  });
});

describe('overlapping passes', () => {
  const absent = attendance(5, 'AI', { classes: [{ date: '2026-09-20', label: '1', mark: 'absent' }] });

  test('old absences on first sight stay silent whichever pass wins', async () => {
    await writeCache('attendance', [absent]);
    await Promise.all([postDueReminders(noon), postDueReminders(noon), postDueReminders(noon)]);
    assert.equal(browser.shown.length, 0);
    assert.deepEqual(browser.local.data['notify.seenCourses'], [5]);
    assert.ok(Object.keys(browser.local.data['notify.sent'] as object).some((k) => k.startsWith('absent:5|')));
  });

  test('one reminder goes out once, without a second toast', async () => {
    await writeCache('deadlines', [deadline({ end: noon + 2 * HOUR })]);
    await Promise.all([postDueReminders(noon), postDueReminders(noon)]);
    assert.equal(browser.shown.length, 1);
  });

  test('every click target lands when mail and reminders post together', async () => {
    await announceNewMail([]);
    await writeCache('deadlines', [deadline({ end: noon + 2 * HOUR })]);
    await Promise.all([postDueReminders(noon), announceNewMail([mailHeader('m1')], noon), announceNotices([], noon)]);
    assert.equal(Object.keys(browser.local.data['notify.targets'] as object).length, 2);
  });
});

describe('a grades page opening or closing', () => {
  const item = (mark: string): GradeItem => ({ key: 'm1', name: 'Quiz', category: '', mark, grade: null, max: null, weight: null, categoryWeight: null, contribution: null, moduleId: 1, moduleType: 'quiz' });
  const grades = (source: CourseGrades['source'], mark: string): CourseGrades => ({ course: { id: 3, name: 'AI', code: '', professor: '' }, source, items: [item(mark)], categories: [] });

  test('the same mark read from the other page is not news; a real change after it is', async () => {
    await writeCache('courseGrades', [grades('activities', '37.00/100.00')]);
    await postDueReminders(noon);
    await writeCache('courseGrades', [grades('gradebook', '0.37')]);
    await postDueReminders(noon + 1000);
    assert.equal(browser.shown.length, 0);
    await writeCache('courseGrades', [grades('gradebook', '0.50')]);
    await postDueReminders(noon + 2000);
    assert.deepEqual(browser.shown.map((s) => s.title), ['Grade changed: Quiz']);
  });

  test('a mark changing on one page is still news', async () => {
    await writeCache('courseGrades', [grades('gradebook', '5.00')]);
    await postDueReminders(noon);
    await writeCache('courseGrades', [grades('gradebook', '6.00')]);
    await postDueReminders(noon + 1000);
    assert.equal(browser.shown.length, 1);
  });
});

describe('new mail', () => {
  const night = new Date(2026, 8, 22, 3).getTime();
  const morning = new Date(2026, 8, 22, 8).getTime();

  test('first look only learns; what comes after is announced once', async () => {
    await announceNewMail([mailHeader('a')], noon);
    assert.equal(browser.shown.length, 0);
    await announceNewMail([mailHeader('b'), mailHeader('a')], noon);
    await announceNewMail([mailHeader('b'), mailHeader('a')], noon);
    assert.deepEqual(browser.shown.map((s) => s.id), ['mail:b']);
  });

  test('in quiet hours it waits, and goes out in the morning', async () => {
    await announceNewMail([mailHeader('a')], noon);
    await announceNewMail([mailHeader('b'), mailHeader('a')], night);
    assert.equal(browser.shown.length, 0);
    await announceNewMail([mailHeader('b'), mailHeader('a')], morning);
    assert.deepEqual(browser.shown.map((s) => s.id), ['mail:b']);
  });

  test('with quiet hours off it goes out at night', async () => {
    await writeSettings({ quietHours: false });
    await announceNewMail([mailHeader('a')], noon);
    await announceNewMail([mailHeader('b'), mailHeader('a')], night);
    assert.equal(browser.shown.length, 1);
  });

  test('read overnight: nothing to say in the morning', async () => {
    await announceNewMail([mailHeader('a')], noon);
    await announceNewMail([mailHeader('b'), mailHeader('a')], night);
    await announceNewMail([mailHeader('b', false), mailHeader('a')], morning);
    assert.equal(browser.shown.length, 0);
  });

  test('a notification that fails is tried again, and fails quietly', async () => {
    await announceNewMail([mailHeader('a')], noon);
    browser.notificationsFail = true;
    await announceNewMail([mailHeader('b'), mailHeader('a')], noon);
    browser.notificationsFail = false;
    await announceNewMail([mailHeader('b'), mailHeader('a')], noon);
    assert.deepEqual(browser.shown.map((s) => s.id), ['mail:b']);
  });

  test('several at once make one notification', async () => {
    await announceNewMail([mailHeader('a')], noon);
    await announceNewMail([mailHeader('c'), mailHeader('b'), mailHeader('a')], noon);
    assert.deepEqual(browser.shown.map((s) => s.title), ['2 new messages']);
  });
});

describe('eClass notifications', () => {
  test('first look only learns; a new unread one is announced, and a read one is not', async () => {
    await announceNotices([notice(1)], noon);
    assert.equal(browser.shown.length, 0);
    await announceNotices([notice(3, { read: true }), notice(2), notice(1)], noon);
    assert.deepEqual(browser.shown.map((s) => [s.id, s.title, s.message]), [['notice:2', 'Notice 2', 'Read this']]);
  });

  test('an old one is not news', async () => {
    await announceNotices([], noon);
    await announceNotices([notice(1, { time: noon - 30 * 24 * HOUR })], noon);
    assert.equal(browser.shown.length, 0);
  });

  test('a click opens its eClass link, and only an eClass link', async () => {
    await announceNotices([], noon);
    await announceNotices([notice(1, { url: 'https://eclass.inha.ac.kr/mod/ubboard/view.php?id=4' })], noon);
    await onNotificationClick('notice:1');
    await announceNotices([notice(2, { url: 'https://elsewhere.example/x' })], noon);
    await onNotificationClick('notice:2');
    assert.deepEqual(browser.tabs.map((t) => t.url), ['https://eclass.inha.ac.kr/mod/ubboard/view.php?id=4', 'https://eclass.inha.ac.kr/#/today']);
  });

  test('switched off, they are remembered without a word', async () => {
    await writeSettings({ notify: { ...(await import('../src/core/store.ts')).defaultSettings.notify, notices: false } });
    await announceNotices([], noon);
    await announceNotices([notice(1)], noon);
    await writeSettings({ notify: (await import('../src/core/store.ts')).defaultSettings.notify });
    await announceNotices([notice(1)], noon);
    assert.equal(browser.shown.length, 0);
  });
});

describe('signing out', () => {
  test('of mail: the next account starts from a baseline', async () => {
    await announceNewMail([mailHeader('a')], noon);
    await forgetNotified('mail');
    await announceNewMail([mailHeader('b')], noon);
    assert.equal(browser.shown.length, 0);
  });

  test('of eClass: first sight again, and what was sent goes', async () => {
    const absent = (id: number) => attendance(id, 'AI', { classes: [{ date: '2026-09-20', label: '1', mark: 'absent' }] });
    await writeCache('attendance', [absent(5)]);
    await writeCache('deadlines', [deadline({ end: noon + 2 * HOUR })]);
    await postDueReminders(noon);
    assert.equal(browser.shown.length, 1);
    await forgetNotified('eclass');
    for (const k of ['notify.seenCourses', 'notify.seenGrades', 'notify.seenNotices', 'notify.seenSources']) assert.equal(browser.local.data[k], undefined);
    assert.deepEqual(Object.keys(browser.local.data['notify.sent'] as object), []);
    assert.deepEqual((browser.local.data.settings as { dismissed: string[] }).dismissed, []);

    await writeCache('attendance', [absent(5)]);
    browser.shown.length = 0;
    await writeCache('deadlines', []);
    await postDueReminders(noon);
    assert.equal(browser.shown.length, 0, "the next student's old absences are a baseline");
  });
});

describe('a click', () => {
  const clickable = async () => {
    await writeCache('deadlines', [deadline({ end: noon + 2 * HOUR, moduleId: null, moduleType: null })]);
    await postDueReminders(noon);
    return browser.shown[0].id;
  };

  test('opens the view inside eClass, and raises the window', async () => {
    await onNotificationClick(await clickable());
    assert.deepEqual(browser.tabs.map((t) => t.url), ['https://eclass.inha.ac.kr/#/deadlines']);
    assert.deepEqual(browser.focused, [1]);
  });

  test('with New look off, eClass has no views: it opens the extension page', async () => {
    await writeSettings({ takeover: false });
    await onNotificationClick(await clickable());
    assert.deepEqual(browser.tabs.map((t) => t.url), ['ext://pages/app.html#/deadlines']);
  });

  test('with no window open it opens one', async () => {
    const id = await clickable();
    browser.noWindow = true;
    await onNotificationClick(id);
    assert.deepEqual(browser.newWindows, ['https://eclass.inha.ac.kr/#/deadlines']);
    assert.deepEqual(browser.tabs, []);
  });

  test('an unknown notification opens nothing', async () => {
    await onNotificationClick('gone');
    assert.deepEqual(browser.tabs, []);
  });
});
