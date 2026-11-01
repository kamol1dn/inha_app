// eClass (eclass.inha.ac.kr), an old Coursemos Moodle whose AJAX web service
// is mostly disabled, so the client posts the login form and parses pages.
// A port of eclass_client.dart; see docs/ENDPOINTS.md.
//
// It runs in the service worker, where fetch with credentials 'include' uses
// the browser's own cookie jar: a student already signed in on eClass needs
// no saved password, and a login done here signs the browser in too.

import { loginMark, type CredentialSource, type RejectionSink } from '../../core/credentials.ts';
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
  parseVodModules,
  parseVodProgress,
  withVodModules,
  type VodModule,
  type EclassNotification,
  type Submission,
} from './parsers.ts';

/**
 * Every fetch that lands on the login page (session expired) logs in once
 * with the saved credentials and retries once. A login eClass refused is not
 * posted again: wrong passwords count toward a lockout.
 */
export class EclassClient {
  private readonly creds: CredentialSource;
  private readonly http: typeof request;
  private readonly onRejected: RejectionSink;

  /** The login in progress, shared so parallel fetches that all find the session expired trigger one login. */
  private loggingIn: Promise<void> | null = null;

  /** M.cfg.sesskey and the user id for AJAX calls, from the last page that had them. */
  private ajax: { sesskey: string; userId: number } | null = null;

  private rejected: string | null = null; // the mark of the login eClass last refused

  /** Who the dashboard says is signed in, from its last fetch. Null when it didn't say. */
  sessionUser: number | null = null;

  constructor(creds: CredentialSource, http: typeof request = request, onRejected: RejectionSink = () => {}) {
    this.creds = creds;
    this.http = http;
    this.onRejected = onRejected;
  }

  /** Logs in with the saved login if the browser's session is missing or expired. Throws LoginRequired if eClass rejects it. */
  async ensureLoggedIn(): Promise<void> {
    if (isLoggedOut(await this.get('/'))) await this.login();
  }

  /** Always posts the saved login, even with a live session in the browser, so saving one really tests it. Throws LoginRequired if eClass rejects it. */
  async verifyLogin(): Promise<void> {
    this.rejected = null;
    await this.loggingIn?.catch(() => {});
    await this.login();
  }

  /** The student asked to try the saved login again. */
  forgetRejected(): void {
    this.rejected = null;
  }

  /** Ends the browser's eClass session, if it has one (Moodle's logout link needs the page's sesskey). */
  async logout(): Promise<void> {
    await this.loggingIn?.catch(() => {});
    const home = await this.get('/');
    this.ajax = null;
    this.sessionUser = null;
    if (isLoggedOut(home)) return;
    const sesskey = extractSesskey(home.text());
    if (sesskey == null) throw new ParseError('eClass session key');
    await this.http(`${eclassBase}/login/logout.php?sesskey=${encodeURIComponent(sesskey)}`);
  }

  /** Courses on the dashboard for the current term. */
  courses(): Promise<Course[]> {
    return this.fetchParsed('/', parseCourses);
  }

  /** Upcoming events: assignment and quiz deadlines and VOD watch windows. */
  upcoming(): Promise<Deadline[]> {
    return this.fetchParsed('/calendar/view.php?view=upcoming', parseUpcoming);
  }

  /**
   * Every upcoming event: the calendar's page, which appears to stop at 10
   * events (class periods use up the slots), and each course's own page. A page
   * that fails costs only what it alone would have shown, and comes back in
   * `failed`; with no page at all, or a login needed, it throws.
   */
  async allUpcoming(courses: Course[]): Promise<{ deadlines: Deadline[]; failed: unknown }> {
    const pages = await Promise.allSettled([
      this.upcoming(),
      ...courses.map((c) => this.fetchParsed<Deadline[]>(`/calendar/view.php?view=upcoming&course=${c.id}`, parseUpcoming, true)),
    ]);
    const lost = pages.flatMap((p) => (p.status === 'rejected' ? [p.reason as unknown] : []));
    const login = lost.find((e) => e instanceof LoginRequired);
    if (login || lost.length === pages.length) throw login ?? lost[0];
    return { deadlines: mergeUpcoming(pages.flatMap((p) => (p.status === 'fulfilled' ? [p.value] : []))), failed: lost[0] ?? null };
  }

  /** Class attendance and VOD progress for one course. */
  async attendance(course: Course): Promise<CourseAttendance> {
    // Both together, so a failure in one never goes unhandled.
    const [classes, vods] = await Promise.all([
      this.fetchParsed<AttendanceEntry[]>(`/local/ubattendance/my_status.php?id=${course.id}`, parseAttendance, true),
      this.fetchParsed<VodProgress[]>(`/report/ubcompletion/user_progress.php?id=${course.id}`, parseVodProgress, true),
    ]);
    return { course, classes, vods: await this.linkVods(course, vods) };
  }

  /** Each VOD's course module, from the course's VOD list. That page is optional: without it a VOD just has no link. */
  private async linkVods(course: Course, vods: VodProgress[]): Promise<VodProgress[]> {
    if (!vods.length) return vods;
    try {
      return withVodModules(vods, await this.fetchParsed<VodModule[]>(`/mod/vod/index.php?id=${course.id}`, parseVodModules, true));
    } catch (e) {
      if (e instanceof LoginRequired) throw e;
      return vods;
    }
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
    if (path === '/') {
      const userId = parseUserId(html);
      this.sessionUser = userId;
      if (this.ajax?.userId !== userId) this.ajax = null;
      const sesskey = this.ajax == null ? extractSesskey(html) : null;
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
    const mark = await loginMark(creds);
    if (mark === this.rejected) throw new LoginRequired('eclass', 'eClass rejected the saved login', true);
    this.ajax = null;

    // The browser follows Moodle's 303 → testsession → 303 → dashboard and
    // keeps the fresh MoodleSession cookie the redirects set.
    const res = await this.http(`${eclassBase}/login/index.php`, {
      method: 'POST',
      body: { username: creds.username, password: creds.password },
    });

    // A rejected login shows the login form again (with an error box).
    if (isLoginPage(res.text())) {
      this.rejected = mark;
      await this.onRejected('eclass', creds);
      throw new LoginRequired('eclass', 'eClass rejected the saved login', true);
    }
    if (res.status >= 400) throw new NetworkError(`eclass.inha.ac.kr answered ${res.status}`, res.status);
  }
}

/** Events from several calendar pages, each once. The same event reads the same on every page. */
export function mergeUpcoming(pages: Deadline[][]): Deadline[] {
  const seen = new Set<string>();
  return pages.flat().filter((d) => {
    const key = `${d.kind}|${d.moduleId ?? `${d.courseName}|${d.title}`}|${d.end}`;
    if (seen.has(key)) return false;
    seen.add(key);
    return true;
  });
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
