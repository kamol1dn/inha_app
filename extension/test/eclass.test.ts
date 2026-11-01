import { beforeEach, describe, test } from 'node:test';
import assert from 'node:assert/strict';
import { fixture } from './setup.ts';
import { LoginRequired, NetworkError, ParseError } from '../src/core/errors.ts';
import type { HttpRequest, HttpResponse } from '../src/core/http.ts';
import { courseFromTitle, type Course, type Deadline } from '../src/core/models.ts';
import type { Credentials } from '../src/core/credentials.ts';
import { EclassClient } from '../src/services/eclass/client.ts';
import { itemUrl } from '../src/services/eclass/links.ts';
import {
  extractSesskey,
  isLoginPage,
  parseAssignSubmission,
  parseAttendance,
  parseCourses,
  parseNotifications,
  parseQuizSubmission,
  parseUpcoming,
  parseUserId,
  parseVodProgress,
} from '../src/services/eclass/parsers.ts';

const unix = (seconds: number) => seconds * 1000;
const local = (y: number, mo: number, d: number, h = 0, mi = 0) => new Date(y, mo - 1, d, h, mi).getTime();

describe('courseFromTitle', () => {
  test('drops the term-code-section bracket', () => {
    const c = courseFromTitle(1, 'Multimedia Computing[202602-SOC4020-001]');
    assert.deepEqual([c.name, c.code], ['Multimedia Computing', 'SOC4020']);
  });

  test('drops a badge after the bracket, so the name is never a code', () => {
    const c = courseFromTitle(2622, 'Artificial Intelligence[202602-SOC4040-001]NEW');
    assert.deepEqual([c.name, c.code], ['Artificial Intelligence', 'SOC4040']);
    assert.equal(courseFromTitle(1, 'Artificial Intelligence [202602-SOC4040-001] NEW').name, 'Artificial Intelligence');
  });

  test('keeps a title without the bracket', () => {
    assert.equal(courseFromTitle(1, 'Mental Education').name, 'Mental Education');
  });
});

describe('parseCourses', () => {
  const courses = parseCourses(fixture('eclass_dashboard.html'));

  test('finds every dashboard course once', () => {
    assert.deepEqual(
      courses.map((c) => c.id),
      [2592, 2615, 2622, 2626, 2634, 2635],
    );
  });

  test('splits the title into a clean name and code', () => {
    const mm = courses.find((c) => c.id === 2622)!;
    assert.equal(mm.name, 'Multimedia Computing');
    assert.equal(mm.code, 'SOC4020');
    assert.equal(mm.professor, 'Minhaz Uddin Ahmed');
    const esd = courses.find((c) => c.id === 2615)!;
    assert.equal(esd.name, 'Embedded Software & Design');
    assert.equal(esd.code, 'SOC3050');
    for (const c of courses) {
      assert.ok(!c.name.includes('['), c.name);
      assert.match(c.code, /^[A-Z]+\d+$/);
      assert.ok(c.professor.length > 0);
    }
  });

  test('a dashboard with no courses is empty, not an error', () => {
    const html =
      '<body id="page-site-index"><div class="course_lists">' +
      '<ul class="my-course-lists"><li class="nocourses">No courses</li></ul></div></body>';
    assert.deepEqual(parseCourses(html), []);
  });

  test('an unrecognisable page throws ParseError', () => {
    assert.throws(() => parseCourses('<html><body><p>Maintenance</p></body></html>'), ParseError);
    assert.throws(() => parseCourses(fixture('eclass_login.html')), ParseError);
  });
});

describe('parseUpcoming', () => {
  const events = parseUpcoming(fixture('eclass_upcoming.html'));
  const ofKind = (k: string) => events.filter((e) => e.kind === k);

  test('finds every event, course-level ones included', () => {
    assert.equal(events.length, 10);
    assert.equal(ofKind('vod').length, 2);
    assert.equal(ofKind('assignment').length, 1);
    assert.equal(ofKind('quiz').length, 1);
    // The six course-level "...[001]-N교시" events are class periods, not deadlines.
    assert.equal(ofKind('classPeriod').length, 6);
    assert.equal(ofKind('other').length, 0);
  });

  test('a VOD window has start and end from the time= stamps', () => {
    const vod = events[0];
    assert.equal(vod.title, 'Midterm info');
    assert.equal(vod.kind, 'vod');
    assert.equal(vod.moduleId, 72743);
    assert.equal(vod.moduleType, 'vod');
    assert.equal(vod.courseName, 'Distinguished Lecture in Social Science and Art');
    assert.equal(vod.start, unix(1792177200));
    assert.equal(vod.end, unix(1792954799));
    // 17 Oct 00:00 .. 25 Oct 23:59:59 in Tashkent (UTC+5).
    assert.equal(vod.start, Date.UTC(2026, 9, 16, 19));
    assert.equal(vod.end, Date.UTC(2026, 9, 25, 18, 59, 59));
  });

  test('an assignment has only a due time', () => {
    const a = ofKind('assignment')[0];
    assert.equal(a.title, 'Assignment 1');
    assert.equal(a.courseName, 'Multimedia Computing');
    assert.equal(a.moduleId, 72061);
    assert.equal(a.moduleType, 'assign');
    assert.equal(a.start, null);
    assert.equal(a.end, Date.UTC(2026, 9, 25, 18, 55));
    assert.equal(a.done, false);
  });

  test('a quiz is recognised from its module link', () => {
    const q = ofKind('quiz')[0];
    assert.equal(q.moduleId, 72454);
    assert.equal(q.moduleType, 'quiz');
    assert.equal(q.courseName, 'Blockchain Basics and Platforms');
    assert.equal(q.end, unix(1792954740));
  });

  test('a course event without a module link is kept, dated by time= not "Today"', () => {
    const today = events[2];
    assert.equal(today.title, 'Deep learning for computer vision[001]-9교시');
    assert.equal(today.kind, 'classPeriod');
    assert.equal(today.moduleId, null);
    assert.equal(today.moduleType, null);
    assert.equal(today.start, null);
    assert.equal(today.courseName, 'Deep learning for computer vision');
    assert.equal(today.end, unix(1792609200));
    assert.equal(events[3].title, 'Embedded Software & Design[001]-3교시');
    assert.equal(events[3].end, unix(1792695600));
  });

  test('a calendar with no upcoming events is empty, not an error', () => {
    const html =
      '<body id="page-calendar-view"><div class="maincalendar">' +
      '<h2>Calendar</h2>There are no upcoming events</div></body>';
    assert.deepEqual(parseUpcoming(html), []);
  });

  test('an unrecognisable page throws ParseError', () => {
    assert.throws(() => parseUpcoming(fixture('eclass_login.html')), ParseError);
    const noTime =
      '<div class="eventlist"><div class="event"><h3 class="referer">' +
      '<a href="/mod/assign/view.php?id=1">A</a></h3><span class="date">Soon</span></div></div>';
    assert.throws(() => parseUpcoming(noTime), ParseError);
  });
});

describe('parseAttendance', () => {
  const rows = parseAttendance(fixture('eclass_attendance_2622.html'));
  const count = (m: string) => rows.filter((r) => r.mark === m).length;

  test('reads every class with the column that holds the mark', () => {
    assert.equal(rows.length, 13);
    assert.equal(count('present'), 11);
    assert.equal(count('absent'), 2);
    assert.equal(count('late'), 0);
    assert.equal(count('other'), 0);
    assert.equal(count('unmarked'), 0);
  });

  test('rows carry the date and class label', () => {
    assert.deepEqual(rows[0], { date: '2026-09-08', label: '1Class', mark: 'present' });
    assert.deepEqual(rows[10], { date: '2026-10-13', label: '11Class', mark: 'absent' });
    // The ○ can sit inside a button (auto-attendance) or be plain text.
    assert.equal(rows[11].mark, 'absent');
    assert.equal(rows[9].mark, 'present');
    assert.equal(rows[rows.length - 1].date, '2026-10-21');
  });

  test('a page without the table is empty, an unknown page is a ParseError', () => {
    const noTable =
      '<body id="page-local-ubattendance-my_status">' +
      '<div class="attendance"><div class="attendance_book">No attendance</div></div></body>';
    assert.deepEqual(parseAttendance(noTable), []);
    assert.throws(() => parseAttendance(fixture('eclass_dashboard.html')), ParseError);
  });
});

describe('parseVodProgress', () => {
  const vods = parseVodProgress(fixture('eclass_progress_2592.html'));
  const named = (t: string) => vods.find((v) => v.title === t)!;

  test('reads one row per VOD and skips empty weeks', () => {
    assert.deepEqual(
      vods.map((v) => v.week),
      [1, 1, 2, 3, 3, 4, 5, 6, 6, 6, 7, 7],
    );
  });

  test('rows under a rowspan Week cell get that week', () => {
    const l62 = named('Lecture 6-2');
    assert.equal(l62.week, 6); // third row of a rowspan="3" week
    assert.equal(l62.lengthSec, 26 * 60 + 43);
    assert.equal(l62.percent, 100);
    const midterm = named('Midterm info');
    assert.equal(midterm.week, 7);
    assert.equal(midterm.lengthSec, 3 * 60 + 19);
    const video7 = named('Video 7');
    assert.equal(video7.week, 7);
    assert.equal(video7.lengthSec, 55 * 60 + 33);
    assert.ok(Math.abs(video7.percent - 62.86) < 1e-9);
  });

  test('parses h:mm:ss lengths and fractional percents', () => {
    assert.equal(named('Lecture 1').week, 1);
    assert.ok(Math.abs(named('Lecture 1').percent - 98.21) < 1e-9);
    assert.equal(named('Lecture 2').lengthSec, 3600 + 34);
  });

  test('a course without progress-managed VODs is empty', () => {
    assert.deepEqual(parseVodProgress(fixture('eclass_progress_2635.html')), []);
  });

  test('an unrecognisable page throws ParseError', () => {
    assert.throws(() => parseVodProgress(fixture('eclass_login.html')), ParseError);
  });
});

describe('isLoginPage', () => {
  test('detects the logged-out login page', () => {
    assert.equal(isLoginPage(fixture('eclass_login.html')), true);
  });

  test('logged-in pages are not the login page', () => {
    for (const f of [
      'eclass_dashboard.html',
      'eclass_upcoming.html',
      'eclass_attendance_2622.html',
      'eclass_progress_2592.html',
      'eclass_progress_2635.html',
    ]) {
      assert.equal(isLoginPage(fixture(f)), false, f);
    }
  });
});

describe('extractSesskey and parseUserId', () => {
  test('read M.cfg.sesskey and the user menu link', () => {
    assert.equal(extractSesskey(fixture('eclass_dashboard.html')), 'TESTSESSKY');
    assert.equal(parseUserId(fixture('eclass_dashboard.html')), 1);
  });

  test('are null when the page has none', () => {
    assert.equal(extractSesskey('<html><body></body></html>'), null);
    assert.equal(parseUserId('<html><body></body></html>'), null);
  });
});

describe('parseNotifications', () => {
  test('reads Moodle popup notifications', () => {
    const reply = JSON.stringify([
      {
        error: false,
        data: {
          notifications: [
            {
              id: 501,
              subject: 'Assignment 1 is due',
              smallmessage: '<p>Due <b>tomorrow</b>&nbsp;23:55</p>',
              fullmessage: 'ignored',
              contexturl: 'https://eclass.inha.ac.kr/mod/assign/view.php?id=72061',
              timecreated: 1792609200,
              read: false,
            },
            { id: 502, subject: 'Grade', smallmessage: '', fullmessage: 'Graded', contexturl: null, timecreated: 1, read: true },
          ],
          unreadcount: 1,
        },
      },
    ]);
    assert.deepEqual(parseNotifications(reply), [
      {
        id: 501,
        subject: 'Assignment 1 is due',
        text: 'Due tomorrow 23:55',
        url: 'https://eclass.inha.ac.kr/mod/assign/view.php?id=72061',
        time: unix(1792609200),
        read: false,
      },
      { id: 502, subject: 'Grade', text: 'Graded', url: null, time: 1000, read: true },
    ]);
  });

  test('a Moodle error reply is a ParseError', () => {
    assert.throws(
      () => parseNotifications('[{"error":true,"exception":{"errorcode":"invalidsesskey"}}]'),
      ParseError,
    );
    assert.throws(() => parseNotifications('<html>'), ParseError);
  });
});

// The assignment and quiz pages, cut down to what the parsers read
// (test/submission_test.dart).
function assignPage({
  statusCell = '<td class="cell c1 lastcol">No attempt</td>',
  grading = '<td class="submissionnotgraded cell c1 lastcol">Not graded</td>',
  modified = '-',
} = {}) {
  return `<html><body id="page-mod-assign-view"><div id="region-main"><div role="main">
<h2>Lab 5: JPEG quantization</h2>
<div class="submissionstatustable"><h3>Submission status</h3>
<div class="box boxaligncenter submissionsummarytable"><table class="generaltable"><tbody>
<tr><td class="cell c0">Submission status</td>${statusCell}</tr>
<tr><td class="cell c0">Grading status</td>${grading}</tr>
<tr><td class="cell c0">Due date</td><td class="cell c1 lastcol">2026-10-25 23:55</td></tr>
<tr><td class="cell c0">Time remaining</td><td class="cell c1 lastcol">2 days 22 hours</td></tr>
<tr><td class="cell c0">Last modified</td><td class="cell c1 lastcol">${modified}</td></tr>
<tr class="lastrow"><td class="cell c0">Submission comments</td><td class="cell c1 lastcol">Comments (0)</td></tr>
</tbody></table></div></div></div></div></body></html>`;
}

function quizPage(states: string[] = []) {
  const attempts =
    states.length === 0
      ? '<div class="box quizattempt"><form><button>Attempt quiz now</button></form></div>'
      : `<table class="generaltable quizattemptsummary"><thead><tr><th class="header c0">State</th>
<th class="header c1">Grade / 100.00</th><th class="header c2 lastcol">Review</th></tr></thead><tbody>
${states.map((s) => `<tr><td class="cell c0">${s}</td><td class="cell c1">37.00</td><td class="cell c2 lastcol"><a>Review</a></td></tr>`).join('')}
</tbody></table><div class="box quizattempt"><p>No more attempts are allowed</p></div>`;
  return `<html><body id="page-mod-quiz-view"><div id="region-main"><div role="main">
<h2>Quiz 2: Week 6</h2>
<div class="box quizinfo well"><p>Attempts allowed: 1</p><p>This quiz will close at 2026-10-25 23:59</p></div>
${attempts}
</div></div></body></html>`;
}

describe('assignment page', () => {
  test('no attempt is not done', () => {
    assert.deepEqual(parseAssignSubmission(assignPage()), { done: false, at: null });
  });

  test('submitted for grading is done, at the last modified time', () => {
    const s = parseAssignSubmission(
      assignPage({
        statusCell: '<td class="submissionstatussubmitted cell c1 lastcol">Submitted for grading</td>',
        modified: '2026-10-21 21:14',
      }),
    );
    assert.deepEqual(s, { done: true, at: local(2026, 10, 21, 21, 14) });
  });

  test('a draft is not handed in', () => {
    const s = parseAssignSubmission(
      assignPage({
        statusCell: '<td class="submissionstatusdraft cell c1 lastcol">Draft (not submitted)</td>',
        modified: '2026-10-21 21:14',
      }),
    );
    assert.deepEqual(s, { done: false, at: null });
  });

  test('graded counts as done whatever the status cell says', () => {
    const s = parseAssignSubmission(assignPage({ grading: '<td class="submissiongraded cell c1 lastcol">Graded</td>' }));
    assert.equal(s.done, true);
  });

  test('the same classes in Korean are read the same', () => {
    const s = parseAssignSubmission(
      assignPage({
        statusCell: '<td class="submissionstatussubmitted cell c1 lastcol">채점을 위해 제출됨</td>',
        modified: '2026-10-21 21:14',
      }).replace('Last modified', '최종 수정 일시'),
    );
    assert.deepEqual(s, { done: true, at: local(2026, 10, 21, 21, 14) });
  });

  test('another page is a ParseError', () => {
    assert.throws(() => parseAssignSubmission('<html><body id="page-login-index"></body></html>'), ParseError);
  });
});

describe('quiz page', () => {
  test('not attempted is not done', () => {
    assert.deepEqual(parseQuizSubmission(quizPage()), { done: false, at: null });
  });

  test('a finished attempt is done, at its submitted time', () => {
    assert.deepEqual(
      parseQuizSubmission(quizPage(['Finished<span class="statedetails">Submitted 2026-10-04 23:13</span>'])),
      { done: true, at: local(2026, 10, 4, 23, 13) },
    );
  });

  test('an attempt still in progress is not done; the newest finished one counts', () => {
    assert.equal(parseQuizSubmission(quizPage(['In progress'])).done, false);
    const s = parseQuizSubmission(
      quizPage([
        'Finished<span class="statedetails">Submitted 2026-10-04 23:13</span>',
        'Finished<span class="statedetails">Submitted 2026-10-05 08:02</span>',
        'Never submitted',
      ]),
    );
    assert.equal(s.at, local(2026, 10, 5, 8, 2));
  });

  test('another page is a ParseError', () => {
    assert.throws(() => parseQuizSubmission('<html><body id="page-site-index"></body></html>'), ParseError);
  });
});

describe('itemUrl', () => {
  const base: Deadline = {
    title: 'Lab 1',
    courseName: 'Multimedia Computing',
    kind: 'assignment',
    start: null,
    end: 0,
    moduleId: 72061,
    moduleType: 'assign',
    done: false,
    doneAt: null,
  };

  test('links the activity, falling back on the kind', () => {
    assert.equal(itemUrl(base), 'https://eclass.inha.ac.kr/mod/assign/view.php?id=72061');
    assert.equal(itemUrl({ ...base, kind: 'quiz', moduleType: null }), 'https://eclass.inha.ac.kr/mod/quiz/view.php?id=72061');
    assert.equal(itemUrl({ ...base, moduleId: null }), null);
  });
});

/**
 * A tiny eClass behind the browser: one live session at a time (the browser's
 * cookie jar, which the client never sees), the login form, and fixture pages.
 * Redirects are already followed, as fetch does: a logged-out request ends on
 * the login page.
 */
class FakeEclass {
  pages: Map<string, string>;
  /** Pages served to a logged-out browser instead of the login redirect, like the calendar. */
  guestPages = new Map<string, string>();
  username = 'student';
  password = 'secret';
  loggedIn = false;
  /** Every request as "METHOD path?query". */
  log: string[] = [];
  loginForms: Record<string, string>[] = [];
  notificationBodies: string[] = [];

  constructor(pages: Record<string, string>) {
    this.pages = new Map(Object.entries(pages));
  }

  get loginCount() {
    return this.loginForms.length;
  }

  http = async (url: string, req: HttpRequest = {}): Promise<HttpResponse> => {
    const u = new URL(url);
    const target = u.pathname + u.search;
    const method = req.method ?? (req.body == null ? 'GET' : 'POST');
    this.log.push(`${method} ${target}`);

    if (method === 'POST' && u.pathname === '/login/index.php') {
      const form = req.body as Record<string, string>;
      this.loginForms.push(form);
      if (form.username === this.username && form.password === this.password) {
        this.loggedIn = true;
        return respond(fixture('eclass_dashboard.html'), { url: 'https://eclass.inha.ac.kr/', redirected: true });
      }
      return respond(fixture('eclass_login.html'), { url }); // login form again, with an error
    }

    if (u.pathname === '/lib/ajax/service.php') {
      this.notificationBodies.push(String(req.body));
      const ok = u.searchParams.get('sesskey') === 'TESTSESSKY' && this.loggedIn;
      return respond(
        ok
          ? '[{"error":false,"data":{"notifications":[{"id":1,"subject":"Hi","smallmessage":"Hi","contexturl":"","timecreated":2,"read":false}],"unreadcount":1}}]'
          : '[{"error":true,"exception":{"errorcode":"servicerequireslogin"}}]',
        { url },
      );
    }

    if (!this.loggedIn && this.guestPages.has(target)) return respond(this.guestPages.get(target)!, { url });
    if (!this.loggedIn) {
      return respond(fixture('eclass_login.html'), {
        url: 'https://eclass.inha.ac.kr/login/index.php',
        redirected: true,
      });
    }
    const page = this.pages.get(target);
    return page == null ? respond('<h1>Not found</h1>', { url, status: 404 }) : respond(page, { url });
  };
}

function respond(body: string, { url, status = 200, redirected = false }: { url: string; status?: number; redirected?: boolean }): HttpResponse {
  const bytes = new TextEncoder().encode(body);
  return { status, url, redirected, headers: new Headers(), bytes, text: () => body };
}

describe('EclassClient', () => {
  let server: FakeEclass;
  let saved: Credentials | null;
  let client: EclassClient;

  const multimedia: Course = { id: 2622, name: 'Multimedia Computing', code: 'SOC4020', professor: '' };
  const lecture: Course = { id: 2592, name: 'Distinguished Lecture in Social Science and Art', code: 'NTS4070', professor: '' };

  beforeEach(() => {
    server = new FakeEclass({
      '/': fixture('eclass_dashboard.html'),
      '/calendar/view.php?view=upcoming': fixture('eclass_upcoming.html'),
      '/local/ubattendance/my_status.php?id=2622': fixture('eclass_attendance_2622.html'),
      '/report/ubcompletion/user_progress.php?id=2592': fixture('eclass_progress_2592.html'),
      '/report/ubcompletion/user_progress.php?id=2635': fixture('eclass_progress_2635.html'),
    });
    saved = { username: 'student', password: 'secret' };
    client = new EclassClient(async () => saved, server.http);
  });

  describe('signed in in the browser', () => {
    beforeEach(() => {
      server.loggedIn = true;
    });

    test('courses() fetches the dashboard without logging in', async () => {
      const courses = await client.courses();
      assert.equal(courses.length, 6);
      assert.equal(courses.find((c) => c.id === 2622)!.name, 'Multimedia Computing');
      assert.equal(server.loginCount, 0);
      assert.deepEqual(server.log, ['GET /']);
    });

    test('needs no saved login at all', async () => {
      saved = null;
      assert.equal((await client.upcoming()).length, 10);
      assert.deepEqual(server.log, ['GET /calendar/view.php?view=upcoming']);
    });

    test('ensureLoggedIn() does nothing when the session is alive', async () => {
      await client.ensureLoggedIn();
      assert.equal(server.loginCount, 0);
    });

    test('attendance() combines both pages; a 404 part is just empty', async () => {
      const mm = await client.attendance(multimedia);
      assert.equal(mm.course.id, 2622);
      assert.equal(mm.classes.length, 13);
      assert.equal(mm.classes.filter((c) => c.mark === 'absent').length, 2);
      assert.deepEqual(mm.vods, []); // progress page 404s in the fake

      const dl = await client.attendance(lecture);
      assert.deepEqual(dl.classes, []); // attendance page 404s in the fake
      assert.equal(dl.vods.length, 12);
    });

    test('attendance() with VODs that are not progress-managed gives no VODs', async () => {
      const bc = await client.attendance({ id: 2635, name: 'Blockchain Basics and Platforms', code: 'SOC4190', professor: '' });
      assert.deepEqual(bc.vods, []);
      assert.deepEqual(bc.classes, []);
    });

    test('a non-optional page that 404s is an error, not an empty list', async () => {
      server.pages.delete('/calendar/view.php?view=upcoming');
      await assert.rejects(client.upcoming(), NetworkError);
    });

    test('submission() reads assignment and quiz pages only', async () => {
      server.pages.set(
        '/mod/assign/view.php?id=1',
        assignPage({
          statusCell: '<td class="submissionstatussubmitted cell c1 lastcol">Submitted</td>',
          modified: '2026-10-21 21:14',
        }).replace('</div></body>', '<a href="/login/logout.php">Log out</a></div></body>'),
      );
      const d: Deadline = { title: 'Lab', courseName: '', kind: 'assignment', start: null, end: 0, moduleId: 1, moduleType: 'assign', done: false, doneAt: null };
      assert.deepEqual(await client.submission(d), { done: true, at: local(2026, 10, 21, 21, 14) });
      assert.equal(await client.submission({ ...d, kind: 'vod' }), null);
      assert.equal(await client.submission({ ...d, moduleId: null }), null);
    });

    test('notifications() takes the sesskey and user id from the dashboard', async () => {
      const list = await client.notifications();
      assert.equal(list.length, 1);
      assert.deepEqual(server.log, ['GET /', 'POST /lib/ajax/service.php?sesskey=TESTSESSKY']);
      const call = JSON.parse(server.notificationBodies[0]);
      assert.equal(call[0].methodname, 'message_popup_get_popup_notifications');
      assert.equal(call[0].args.useridto, 1);

      server.log = [];
      await client.notifications();
      assert.deepEqual(server.log, ['POST /lib/ajax/service.php?sesskey=TESTSESSKY']); // keys kept
    });
  });

  describe('guest page', () => {
    test('a page that renders for guests, without the logout link, still logs in first', async () => {
      server.guestPages.set(
        '/calendar/view.php?view=upcoming',
        '<html><body id="page-calendar-view"><div class="calendar_event_upcoming"></div>' +
          '<a href="https://eclass.inha.ac.kr/login/index.php">Log in</a></body></html>',
      );
      assert.equal((await client.upcoming()).length, 10);
      assert.equal(server.loginCount, 1);
    });

    test('with no saved login it is LoginRequired, not an empty list', async () => {
      server.guestPages.set('/calendar/view.php?view=upcoming', '<html><body></body></html>');
      saved = null;
      await assert.rejects(client.upcoming(), LoginRequired);
    });
  });

  describe('session expired', () => {
    test('logs in once with the form and retries the fetch', async () => {
      assert.equal((await client.upcoming()).length, 10);
      assert.equal(server.loginCount, 1);
      assert.deepEqual(server.loginForms[0], { username: 'student', password: 'secret' });
      assert.deepEqual(server.log, [
        'GET /calendar/view.php?view=upcoming', // → login page
        'POST /login/index.php', // → redirects to the dashboard
        'GET /calendar/view.php?view=upcoming', // retry
      ]);
    });

    test('keeps the session for later requests', async () => {
      await client.courses();
      server.log = [];
      await client.upcoming();
      assert.equal(server.loginCount, 1);
      assert.deepEqual(server.log, ['GET /calendar/view.php?view=upcoming']);
    });

    test('attendance() fetches both pages in parallel but logs in only once', async () => {
      const mm = await client.attendance(multimedia);
      assert.equal(mm.classes.length, 13);
      assert.equal(server.loginCount, 1);
    });

    test('ensureLoggedIn() logs in', async () => {
      await client.ensureLoggedIn();
      assert.equal(server.loginCount, 1);
      assert.equal(server.loggedIn, true);
    });
  });

  describe('bad or missing credentials', () => {
    test('a rejected password throws LoginRequired after one attempt', async () => {
      saved = { username: 'student', password: 'wrong' };
      await assert.rejects(client.courses(), (e: unknown) => e instanceof LoginRequired && e.service === 'eclass');
      assert.equal(server.loginCount, 1);
      assert.equal(server.log.filter((l) => l === 'GET /').length, 1); // no retry
    });

    test('ensureLoggedIn() with a rejected password throws LoginRequired', async () => {
      saved = { username: 'student', password: 'wrong' };
      await assert.rejects(client.ensureLoggedIn(), LoginRequired);
    });

    test('no saved login throws LoginRequired without posting anything', async () => {
      saved = null;
      await assert.rejects(client.upcoming(), LoginRequired);
      assert.equal(server.loginCount, 0);
    });
  });
});
