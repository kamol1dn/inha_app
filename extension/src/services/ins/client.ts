import { loginMark, type CredentialSource, type RejectionSink } from '../../core/credentials.ts';
import { LoginRequired, NetworkError, ParseError } from '../../core/errors.ts';
import { request, type HttpResponse } from '../../core/http.ts';
import type { GradeReport } from '../../core/models.ts';
import {
  decodeInsBytes,
  extractXmlUrl,
  findMenuLink,
  formAction,
  hasMenuLinks,
  hiddenInputs,
  isInsLoginPage,
  isSessionExpired,
  loginError,
  pageRefs,
  parseGrades,
} from './parsers.ts';

/**
 * INS / ITIS the way a browser does it: WebForms login post, then the
 * frameset menu down to the grades XML. A port of lib/services/ins/ins_client.dart;
 * see docs/ENDPOINTS.md.
 *
 * Runs in two places with the same code: the service worker (cross-origin,
 * host permission) and a content script on an ins.inha.uz page (same-origin,
 * which works once the student has accepted INS's expired certificate in that
 * tab). Either way the browser follows redirects and keeps the ASP.NET session
 * cookie, so the session is the student's own browser session. In the worker
 * the expired certificate usually makes every request fail; that NetworkError
 * (certificate: true) is passed up unchanged for the caller to fall back on.
 *
 * Every request stays on [base]'s origin: the server sometimes redirects to
 * its internal name (http://ins.iutdev.ac.kr/...), which doesn't resolve
 * outside IUT. A response that lands there is fetched again on INS; off campus
 * the browser's fetch fails on that hop instead, so each step of the grades
 * chain has a way around a failed request.
 *
 * A login INS refused is not posted again: wrong passwords count toward a lockout.
 */
export class InsClient {
  /** Menu text in left.aspx. */
  static readonly gradesMenu = 'View Grades and Standings';

  /** Known location of the report frame, tried directly once main.aspx has been visited if the page chain did not lead there. */
  static readonly rpxPath = 'STD/SJ/SJ_51001/MarkView_rpx.aspx?gubun=inform';

  private static readonly maxFrameHops = 4;

  /** The ITIS root, e.g. `https://ins.inha.uz/ITIS/` (trailing slash matters). */
  readonly base: URL;
  private readonly creds: CredentialSource;
  private readonly http: typeof request;
  private readonly onRejected: RejectionSink;
  private readonly inTab: boolean;
  private loginInFlight: Promise<boolean> | null = null;
  private rejected: string | null = null; // the mark of the login INS last refused

  /**
   * `opts.base` is the INS origin (default https://ins.inha.uz); the ITIS root
   * under it is /ITIS/ unless the base names a path. `opts.inTab`: running in an
   * INS tab, where the certificate is already accepted.
   */
  constructor(creds: CredentialSource, opts: { base?: string; http?: typeof request; onRejected?: RejectionSink; inTab?: boolean } = {}) {
    const base = new URL(opts.base ?? 'https://ins.inha.uz');
    this.base = base.pathname === '/' ? new URL('/ITIS/', base) : base;
    this.creds = creds;
    this.http = opts.http ?? request;
    this.onRejected = opts.onRejected ?? (() => {});
    this.inTab = opts.inTab ?? false;
  }

  private get startUrl() {
    return this.resolve('Start.aspx');
  }
  private get leftUrl() {
    return this.resolve('left.aspx');
  }

  // -------------------------------------------------------------------------
  // API
  // -------------------------------------------------------------------------

  /** Throws LoginRequired if INS rejects the saved credentials. */
  async ensureLoggedIn(): Promise<void> {
    const left = await this.get(this.leftUrl);
    if (hasMenuLinks(left.body) && !isInsLoginPage(left.body)) return;
    await this.login();
  }

  /**
   * Tries the saved login even when a session looks alive, so saving one really
   * tests it. False when it can't be tested: INS answers Start.aspx with its
   * frames while a session lives, so there is no form to post it to.
   */
  async verifyLogin(): Promise<boolean> {
    this.rejected = null;
    await this.loginInFlight?.catch(() => {});
    return this.login();
  }

  /** The student asked to try the saved login again. */
  forgetRejected(): void {
    this.rejected = null;
  }

  /** All course results plus GPA and credits. */
  async grades(): Promise<GradeReport> {
    try {
      return await this.gradesOnce(false);
    } catch (e) {
      if (!(e instanceof SessionExpired)) throw e;
      await this.login();
    }
    try {
      return await this.gradesOnce(true);
    } catch (e) {
      if (e instanceof SessionExpired) throw new LoginRequired('ins', 'INS ended the session right after login');
      throw e;
    }
  }

  // -------------------------------------------------------------------------
  // Login
  // -------------------------------------------------------------------------

  /** One login at a time; concurrent callers share it. True when the login was posted and taken, false when INS was still logged in. */
  private login(): Promise<boolean> {
    this.loginInFlight ??= this.doLogin().finally(() => {
      this.loginInFlight = null;
    });
    return this.loginInFlight;
  }

  private async doLogin(): Promise<boolean> {
    const creds = await this.creds('ins');
    if (creds == null || !creds.username.trim() || !creds.password) {
      throw new LoginRequired('ins', 'No INS login saved');
    }
    const mark = await loginMark(creds);
    if (mark === this.rejected) throw new LoginRequired('ins', 'INS did not accept the ID or password', true);

    const start = await this.get(this.startUrl);
    if (!isInsLoginPage(start.body)) {
      if (isFrameset(start)) return false; // INS still considers us logged in
      throw new ParseError(`INS login page${statusSuffix(start)}`);
    }

    const fields: Record<string, string> = {
      ...hiddenInputs(start.body),
      txtInhaID: creds.username.trim().toUpperCase(),
      txtPW: creds.password,
      btnLogin: '', // the clicked submit's name must be present
    };
    const actionRef = formAction(start.body);
    const action = this.pin(actionRef == null ? start.url : new URL(actionRef, start.url).href);

    let page: Page;
    try {
      page = await this.send(action, fields);
    } catch (e) {
      // The browser followed the login redirect itself. When it pointed at
      // the internal host, that last hop fails; the session cookie came with
      // the redirect, so ask the menu whether the login took.
      if (!(e instanceof NetworkError)) throw e;
      const left = await this.get(this.leftUrl);
      if (hasMenuLinks(left.body) && !isInsLoginPage(left.body)) return true;
      throw e;
    }

    if (loginSucceeded(page)) return true;
    if (page.status >= 400 && !isInsLoginPage(page.body)) {
      throw new ParseError(`INS login response${statusSuffix(page)}`);
    }
    this.rejected = mark;
    await this.onRejected('ins', creds);
    throw new LoginRequired('ins', loginError(page.body) ?? 'INS did not accept the ID or password', true);
  }

  // -------------------------------------------------------------------------
  // Grades chain
  // -------------------------------------------------------------------------

  private async gradesOnce(afterLogin: boolean): Promise<GradeReport> {
    // 1. Menu. In an INS tab the certificate is accepted, so a failure here is
    // the session's redirect to the internal host: logging in again gets past it.
    let left: Page;
    try {
      left = await this.get(this.leftUrl);
    } catch (e) {
      if (this.inTab && !afterLogin && e instanceof NetworkError) throw new SessionExpired();
      throw e;
    }
    const link = findMenuLink(left.body, InsClient.gradesMenu, this.base.pathname);
    if (link == null) {
      // A missing menu before any login most likely means "logged out" in a
      // shape we do not recognise; after a fresh login it means the page changed.
      if (isSessionExpired(left.body) || (!afterLogin && !hasMenuLinks(left.body))) throw new SessionExpired();
      throw new ParseError(`INS menu (${InsClient.gradesMenu})${statusSuffix(left)}`);
    }

    // 2. main.aspx?param=... -> MarkView.aspx -> MarkView_rpx.aspx -> fileurl.
    const xmlUrl = await this.findXmlUrl(this.pin(this.resolve(link)));

    // 3. The XML itself: an empty POST, as the viewer does.
    const page = await this.send(xmlUrl, '');
    try {
      return parseGrades(page.body);
    } catch (e) {
      if (!(e instanceof ParseError)) throw e;
      if (isSessionExpired(page.body)) throw new SessionExpired();
      if (page.status !== 200) throw new ParseError(`INS grades${statusSuffix(page)}`);
      throw e;
    }
  }

  /**
   * Walks from the menu target down the frames until a page assigns
   * `fileurl`. main.aspx may redirect, be a frameset, or bounce by script;
   * MarkView.aspx iframes the rpx page. If that leads nowhere, the known rpx
   * URL is tried directly (the server likely only needs the menu visit).
   */
  private async findXmlUrl(menuTarget: string): Promise<string> {
    const visited = new Set<string>([menuTarget]);
    let failed: NetworkError | null = null;
    // A hop that fails (a redirect to the internal host) still visited the menu, so the direct URL may yet answer.
    const visit = async (url: string): Promise<Page | null> => {
      try {
        const p = await this.get(url);
        visited.add(p.url);
        return p;
      } catch (e) {
        if (!(e instanceof NetworkError)) throw e;
        failed ??= e;
        return null;
      }
    };

    let page = await visit(menuTarget);
    for (let hop = 0; page != null; hop++) {
      const xml = extractXmlUrl(page.body);
      if (xml != null) return this.pin(new URL(xml, page.url).href);
      const next = hop < InsClient.maxFrameHops ? this.nextFrame(page, visited) : null;
      if (next == null) break;
      visited.add(next);
      const nextPage: Page | null = await visit(next);
      if (nextPage == null) break;
      page = nextPage;
    }

    const direct = this.resolve(InsClient.rpxPath);
    if (!visited.has(direct)) {
      const rpx = await visit(direct);
      if (rpx != null) {
        const xml = extractXmlUrl(rpx.body);
        if (xml != null) return this.pin(new URL(xml, rpx.url).href);
        page = rpx;
      }
    }
    if (page != null && isSessionExpired(page.body)) throw new SessionExpired();
    if (page == null && failed != null) throw failed;
    throw new ParseError(`INS grades page${page == null ? '' : statusSuffix(page)}`);
  }

  /** The next page toward the report: a MarkView_rpx reference first, then any MarkView reference, skipping pages already loaded. */
  private nextFrame(page: Page, visited: Set<string>): string | null {
    for (const hint of ['markview_rpx', 'markview']) {
      for (const ref of pageRefs(page.body, hint)) {
        const url = this.pin(new URL(ref, page.url).href);
        if (!visited.has(url)) return url;
      }
    }
    return null;
  }

  // -------------------------------------------------------------------------
  // HTTP
  // -------------------------------------------------------------------------

  private resolve(ref: string): string {
    return new URL(ref, this.base).href;
  }

  /** Pins a URL to [base]'s origin: links and the XML url come from page content, and the extension only ever talks to INS. */
  private pin(url: string): string {
    const u = new URL(url);
    if (u.origin === this.base.origin) return u.href;
    return new URL(u.pathname + u.search, this.base.origin).href;
  }

  private get(url: string): Promise<Page> {
    return this.fetchPage(url, () => this.http(url, { credentials: 'include' }));
  }

  /** A form-urlencoded POST: the login fields, or the XML's empty body. */
  private send(url: string, body: Record<string, string> | string): Promise<Page> {
    return this.fetchPage(url, () =>
      this.http(url, {
        method: 'POST',
        body,
        headers: { 'Content-Type': 'application/x-www-form-urlencoded' },
        credentials: 'include',
      }),
    );
  }

  /**
   * Runs the request; a response that landed off INS (the internal host
   * resolving, on campus) is fetched again with a GET of the same path on INS,
   * which is what the redirect asked the browser to do.
   */
  private async fetchPage(url: string, run: () => Promise<HttpResponse>): Promise<Page> {
    let res = await run();
    if (new URL(res.url).origin !== this.base.origin) {
      res = await this.http(this.pin(res.url), { credentials: 'include' });
    }
    return { url: this.pin(res.url || url), status: res.status, body: decodeInsBytes(res.bytes) };
  }
}

interface Page {
  url: string; // final URL after redirects, on INS
  status: number;
  body: string;
}

const statusSuffix = (p: Page) => (p.status === 200 ? '' : ` (HTTP ${p.status})`);

const isFrameset = (p: Page) =>
  new URL(p.url).pathname.toLowerCase().endsWith('/frameset.htm') || p.body.toLowerCase().includes('<frameset');

/** Success = INS sends us to FRAMESET.htm (redirect, frameset, or script), or at least not back to the login form. */
function loginSucceeded(page: Page): boolean {
  if (page.status >= 400) return false;
  if (isInsLoginPage(page.body)) return false;
  if (isFrameset(page) || page.body.toLowerCase().includes('frameset.htm')) return true;
  return !isSessionExpired(page.body);
}

/** Internal signal: INS showed the login page mid-chain. */
class SessionExpired extends Error {}
