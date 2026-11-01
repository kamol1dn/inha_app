// eClass (eclass.inha.ac.kr), an old Coursemos Moodle whose AJAX web service
// is mostly disabled, so the client posts the login form and parses pages.
// A port of eclass_client.dart; see docs/ENDPOINTS.md.
//
// It runs in the service worker, where fetch with credentials 'include' uses
// the browser's own cookie jar: a student already signed in on eClass needs
// no saved password, and a login done here signs the browser in too.

import type { CredentialSource } from '../../core/credentials.ts';
import { LoginRequired, NetworkError, ParseError } from '../../core/errors.ts';
import { request, type HttpResponse } from '../../core/http.ts';
import { isMarked, type AttendanceEntry, type Course, type CourseAttendance, type CourseGrades, type Deadline, type GradeItem, type VodProgress } from '../../core/models.ts';
import { eclassBase } from './links.ts';
import {
  extractSesskey,
  isLoginPage,
  parseActivityGrades,
  parseAssignMax,
  parseAssignSubmission,
  parseAttendance,
  parseCourses,
  parseGradeBook,
  parseNotifications,
  parseQuizSubmission,
  parseUpcoming,
  parseUserId,
  parseVodProgress,
  type EclassNotification,
  type Submission,
} from './parsers.ts';

/**
 * Every fetch that lands on the login page (session expired) logs in once
 * with the saved credentials and retries once.
 */
export class EclassClient {
  private readonly creds: CredentialSource;
  private readonly http: typeof request;

  /** The login in progress, shared so parallel fetches that all find the session expired trigger one login. */
  private loggingIn: Promise<void> | null = null;

  /** M.cfg.sesskey and the user id for AJAX calls, from the last page that had them. */
  private ajax: { sesskey: string; userId: number } | null = null;

  constructor(creds: CredentialSource, http: typeof request = request) {
    this.creds = creds;
    this.http = http;
  }

  /** Logs in with the saved login if the browser's session is missing or expired. Throws LoginRequired if eClass rejects it. */
  async ensureLoggedIn(): Promise<void> {
    if (isLoggedOut(await this.get('/'))) await this.login();
  }

  /** Courses on the dashboard for the current term. */
  courses(): Promise<Course[]> {
    return this.fetchParsed('/', parseCourses);
  }

  /** Upcoming events: assignment and quiz deadlines and VOD watch windows. */
  upcoming(): Promise<Deadline[]> {
    return this.fetchParsed('/calendar/view.php?view=upcoming', parseUpcoming);
  }

  /** Class attendance and VOD progress for one course. */
  async attendance(course: Course): Promise<CourseAttendance> {
    // Both together, so a failure in one never goes unhandled.
    const [classes, vods] = await Promise.all([
      this.fetchParsed<AttendanceEntry[]>(`/local/ubattendance/my_status.php?id=${course.id}`, parseAttendance, true),
      this.fetchParsed<VodProgress[]>(`/report/ubcompletion/user_progress.php?id=${course.id}`, parseVodProgress, true),
    ]);
    return { course, classes, vods };
  }

  /** Whether an assignment was handed in or a quiz attempted, from the item's own page. Null for items with no such page. */
  async submission(d: Deadline): Promise<Submission | null> {
    if (d.moduleId == null) return null;
    if (d.kind === 'assignment') return this.fetchParsed(`/mod/assign/view.php?id=${d.moduleId}`, parseAssignSubmission);
    if (d.kind === 'quiz') return this.fetchParsed(`/mod/quiz/view.php?id=${d.moduleId}`, parseQuizSubmission);
    return null;
  }

  /** A course's marks: its grades page, or its assignment and quiz lists where a professor closed that page. */
  async courseGrades(course: Course): Promise<CourseGrades> {
    const book = await this.fetchParsed<CourseGrades[]>(
      `/grade/report/user/index.php?id=${course.id}`,
      (html) => {
        const parsed = parseGradeBook(html, course);
        return parsed ? [parsed] : [];
      },
      true,
    );
    if (book.length) return book[0];

    // A closed grades page answers 404 "Can not view grades".
    const [assignments, quizzes] = await Promise.all([
      this.fetchParsed<GradeItem[]>(`/mod/assign/index.php?id=${course.id}`, (html) => parseActivityGrades(html, 'assign'), true),
      this.fetchParsed<GradeItem[]>(`/mod/quiz/index.php?id=${course.id}`, (html) => parseActivityGrades(html, 'quiz'), true),
    ]);
    const items = [...(await Promise.all(assignments.map((a) => this.withAssignMax(a)))), ...quizzes];
    return { course, source: items.length ? 'activities' : 'none', items, categories: [] };
  }

  /** The assignment list gives a mark without its maximum; the assignment's own page has both. A page that fails only costs the "/ 100". */
  private async withAssignMax(item: GradeItem): Promise<GradeItem> {
    if (!isMarked(item) || item.max != null || item.moduleId == null) return item;
    try {
      return { ...item, max: await this.fetchParsed(`/mod/assign/view.php?id=${item.moduleId}`, parseAssignMax) };
    } catch (e) {
      if (e instanceof NetworkError || e instanceof ParseError) return item;
      throw e;
    }
  }

  /**
   * The newest 20 notifications of the bell menu, through the one AJAX call
   * eClass answers. The sesskey and user id come from a logged-in page; a
   * rejected call (sesskey expired) reads them again and retries once.
   */
  async notifications(): Promise<EclassNotification[]> {
    for (let attempt = 0; ; attempt++) {
      const ajax = this.ajax ?? (await this.readAjaxKeys());
      const res = await this.http(`${eclassBase}/lib/ajax/service.php?sesskey=${encodeURIComponent(ajax.sesskey)}`, {
        method: 'POST',
        headers: { 'Content-Type': 'application/json' },
        body: JSON.stringify([
          {
            index: 0,
            methodname: 'message_popup_get_popup_notifications',
            args: { useridto: ajax.userId, newestfirst: true, limit: 20, offset: 0 },
          },
        ]),
      });
      try {
        if (res.status >= 400) throw new NetworkError(`eclass.inha.ac.kr answered ${res.status}`, res.status);
        return parseNotifications(res.text());
      } catch (e) {
        this.ajax = null;
        if (attempt >= 1) throw e;
      }
    }
  }

  private async readAjaxKeys(): Promise<{ sesskey: string; userId: number }> {
    return this.fetchParsed('/', (html) => {
      const sesskey = extractSesskey(html);
      const userId = parseUserId(html);
      if (sesskey == null || userId == null) throw new LoginRequired('eclass', 'eClass page had no session key');
      return (this.ajax = { sesskey, userId });
    });
  }

  /**
   * GETs path and parses it, logging in and retrying once if the session had
   * expired. With optional, a 404 or a redirect to some other page (the
   * course does not have this page) gives an empty list.
   */
  private async fetchParsed<T>(path: string, parse: (html: string) => T, optional = false): Promise<T> {
    let res = await this.get(path);
    if (isLoggedOut(res)) {
      await this.login();
      res = await this.get(path);
      if (isLoggedOut(res)) throw new LoginRequired('eclass', 'eClass logged in but did not keep the session');
    }

    if (optional && (res.status === 404 || redirectedAway(res, path))) return [] as T;
    if (res.status >= 400) throw new NetworkError(`eclass.inha.ac.kr answered ${res.status}`, res.status);
    const html = res.text();
    // Keep the AJAX keys fresh from any page that has them, at no extra request.
    if (path === '/' && this.ajax == null) {
      const sesskey = extractSesskey(html);
      const userId = parseUserId(html);
      if (sesskey != null && userId != null) this.ajax = { sesskey, userId };
    }
    return parse(html);
  }

  private get(path: string): Promise<HttpResponse> {
    return this.http(new URL(path, eclassBase).toString());
  }

  private login(): Promise<void> {
    return (this.loggingIn ??= this.postLogin().finally(() => {
      this.loggingIn = null;
    }));
  }

  private async postLogin(): Promise<void> {
    const creds = await this.creds('eclass');
    if (!creds?.username || !creds.password) throw new LoginRequired('eclass', 'No eClass login saved');
    this.ajax = null;

    // The browser follows Moodle's 303 → testsession → 303 → dashboard and
    // keeps the fresh MoodleSession cookie the redirects set.
    const res = await this.http(`${eclassBase}/login/index.php`, {
      method: 'POST',
      body: { username: creds.username, password: creds.password },
    });

    // A rejected login shows the login form again (with an error box).
    if (isLoginPage(res.text())) throw new LoginRequired('eclass', 'eClass rejected the saved login');
    if (res.status >= 400) throw new NetworkError(`eclass.inha.ac.kr answered ${res.status}`, res.status);
  }
}

/** True when eClass answered with (or redirected to) its login page. */
function isLoggedOut(res: HttpResponse): boolean {
  if (pathOf(res.url).startsWith('/login/')) return true;
  const body = res.text();
  if (body.includes('password') && isLoginPage(body)) return true;
  // Some pages (the calendar) render for guests too, empty. Every logged-in
  // page carries the logout link in its header.
  return res.status >= 200 && res.status < 300 && !body.includes('/login/logout.php');
}

/** True when eClass sent us somewhere other than path (but not to login). */
function redirectedAway(res: HttpResponse, path: string): boolean {
  return res.redirected && pathOf(res.url) !== new URL(path, eclassBase).pathname;
}

function pathOf(url: string): string {
  try {
    return new URL(url, eclassBase).pathname;
  } catch {
    return '';
  }
}
