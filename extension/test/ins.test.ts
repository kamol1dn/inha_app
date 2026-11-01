// Port of test/ins_parsers_test.dart and test/ins_client_test.dart.
import { describe, test, beforeEach } from 'node:test';
import assert from 'node:assert/strict';
import { fixture, fixtureBytes } from './setup.ts';
import { LoginRequired, NetworkError, ParseError } from '../src/core/errors.ts';
import type { Credentials } from '../src/core/credentials.ts';
import type { HttpRequest, HttpResponse } from '../src/core/http.ts';
import type { GradeReport } from '../src/core/models.ts';
import {
  decodeInsBytes,
  extractXmlUrl,
  findMenuLink,
  formAction,
  graded,
  hasMenuLinks,
  hiddenInputs,
  isInsLoginPage,
  isSessionExpired,
  loginError,
  pageRefs,
  parseGrades,
  parseGradesBytes,
} from '../src/services/ins/parsers.ts';
import { InsClient } from '../src/services/ins/client.ts';

const fakeJumin = 'FAKE-JUMIN-000000-0000000';
const close = (a: number, b: number, eps: number) => assert.ok(Math.abs(a - b) < eps, `${a} ≈ ${b}`);

describe('login page', () => {
  test('hiddenInputs returns every hidden input of form1, in order', () => {
    const hidden = hiddenInputs(fixture('ins_start.html'));
    assert.deepEqual(Object.keys(hidden), [
      '__EVENTTARGET',
      '__EVENTARGUMENT',
      '__VIEWSTATE',
      '__VIEWSTATEGENERATOR',
      '__EVENTVALIDATION',
      'errorMessage',
      'hdnPublicKey',
    ]);
    assert.equal(hidden['__VIEWSTATE'], '/wEPDwUKLTFBS0VWSUVXU1RBVEUPZBYCAgMPZBYCZg8PFgIeBFRleHQFBEZBS0VkZGQ+v1ewFAKE/9z+Q==');
    assert.equal(hidden['__VIEWSTATEGENERATOR'], 'FA4E0001');
    assert.equal(hidden['__EVENTVALIDATION'], '/wEdAAXFAKEeventVALIDATIONxx+yy/zz==');
    assert.equal(hidden['__EVENTTARGET'], '');
    // Not hidden, or not in form1.
    assert.ok(!('txtInhaID' in hidden));
    assert.ok(!('btnLogin' in hidden));
    assert.ok(!('noticeToken' in hidden));
  });

  test('hiddenInputs falls back to the whole page when form1 has none', () => {
    const html = '<table><form id="form1"><tr><td><input type="HIDDEN" name="__VIEWSTATE" value="vs"></td></tr></form></table>';
    assert.deepEqual(hiddenInputs(html), { __VIEWSTATE: 'vs' });
  });

  test('formAction', () => {
    assert.equal(formAction(fixture('ins_start.html')), './Start.aspx');
    assert.equal(formAction('<form id="form1"></form>'), null);
  });

  test('isInsLoginPage', () => {
    assert.equal(isInsLoginPage(fixture('ins_start.html')), true);
    assert.equal(isInsLoginPage(fixture('ins_start_error.html')), true);
    assert.equal(isInsLoginPage(fixture('ins_left.html')), false);
    assert.equal(isInsLoginPage(fixture('ins_rpx.html')), false);
  });

  test('loginError reads the hidden errorMessage', () => {
    assert.equal(loginError(fixture('ins_start.html')), null);
    assert.equal(loginError(fixture('ins_start_error.html')), 'The ID or password is incorrect. (fake message)');
  });

  test('isSessionExpired', () => {
    assert.equal(isSessionExpired(fixture('ins_start.html')), true);
    assert.equal(isSessionExpired("<script>top.location.href='/ITIS/Start.aspx';</script>"), true);
    assert.equal(isSessionExpired('<script>location.replace("Start.aspx")</script>'), true);
    assert.equal(isSessionExpired('<p>Your session has expired.</p>'), true);
    assert.equal(isSessionExpired(fixture('ins_rpx.html')), false);
    // left.aspx has a logout script, which is why callers look for the menu first.
    assert.equal(isSessionExpired(fixture('ins_left.html')), true);
  });
});

describe('menu', () => {
  const left = fixture('ins_left.html');

  test('findMenuLink resolves each documented item against /ITIS/', () => {
    assert.equal(findMenuLink(left, 'View Grades and Standings'), '/ITIS/main.aspx?param=FAKEgRaD3s+St4nd/1ngs==&ENGYN=Y');
    assert.equal(findMenuLink(left, 'Personal Information'), '/ITIS/main.aspx?param=FAKEpErS0nAL1nf0x9Kq&ENGYN=Y');
    assert.equal(findMenuLink(left, 'Browse Course Syllabus'), '/ITIS/main.aspx?param=FAKEsYlLaBuS77Qw0pZ&ENGYN=Y');
    assert.equal(findMenuLink(left, 'Browse Course Timetable'), '/ITIS/main.aspx?param=FAKEt1meTaBLe4Rt5nM&ENGYN=N');
    assert.equal(findMenuLink(left, 'Confirm Course Registration'), '/ITIS/main.aspx?param=FAKEc0nF1rMreG8uV2s&ENGYN=Y');
  });

  test('findMenuLink: case-insensitive fallback, unknown text, javascript links', () => {
    assert.equal(findMenuLink(left, 'view grades and standings'), '/ITIS/main.aspx?param=FAKEgRaD3s+St4nd/1ngs==&ENGYN=Y');
    assert.equal(findMenuLink(left, 'View Grades'), null);
    assert.equal(findMenuLink(left, 'Logout'), null); // href="#", no .aspx in onclick
    const js =
      '<a href="javascript:void(0)" onclick="go(\'main.aspx?param=J&amp;ENGYN=Y\')">View Grades and Standings</a>';
    assert.equal(findMenuLink(js, 'View Grades and Standings'), '/ITIS/main.aspx?param=J&ENGYN=Y');
    assert.equal(findMenuLink('<a href="/ITIS/main.aspx?param=A">X</a>', 'X'), '/ITIS/main.aspx?param=A');
  });

  test('findMenuLink: menu written by script', () => {
    const scripted =
      '<script>document.write("<li><a href=\\"main.aspx?param=P1&amp;ENGYN=Y\\">' +
      'Personal Information</a></li>");' +
      "menu.innerHTML += '<li><a href=\"main.aspx?param=G+r/9==&ENGYN=Y\" target=\"main\">" +
      "<span></span>View Grades and Standings</a></li>';</script>";
    assert.equal(findMenuLink(scripted, 'View Grades and Standings'), '/ITIS/main.aspx?param=G+r/9==&ENGYN=Y');
    assert.equal(findMenuLink(scripted, 'Personal Information'), '/ITIS/main.aspx?param=P1&ENGYN=Y');
    assert.equal(findMenuLink(scripted, 'Standings'), null);
    assert.equal(hasMenuLinks(scripted), true);
  });

  test('hasMenuLinks', () => {
    assert.equal(hasMenuLinks(left), true);
    assert.equal(hasMenuLinks(fixture('ins_start.html')), false);
  });
});

describe('report pages', () => {
  test('extractXmlUrl reads the raw page: ViewerReportInForm second argument, as written', () => {
    assert.equal(extractXmlUrl(fixture('ins_rpx.html')), 'MarkView_xml.aspx?Value=FAKE0T0KEN0abc%3d');
  });

  test('extractXmlUrl: browser-built fileurl assignment (live DOM) still works', () => {
    assert.equal(
      extractXmlUrl(
        "<script>window.frm.fileurl.value = '';\n" +
          "window.frm.fileurl.value = 'https://ins.inha.uz/ITIS/STD/SJ/SJ_51001/MarkView_xml.aspx?Value=T';</script>",
      ),
      'https://ins.inha.uz/ITIS/STD/SJ/SJ_51001/MarkView_xml.aspx?Value=T',
    );
  });

  test('extractXmlUrl: double quotes, escaped slashes, input fallback, absent', () => {
    assert.equal(extractXmlUrl('<script>window.frm.fileurl.value="a\\/b.aspx?Value=1";</script>'), 'a/b.aspx?Value=1');
    assert.equal(
      extractXmlUrl('<form name="frm"><input type="hidden" name="fileurl" value="x.aspx?Value=2"></form>'),
      'x.aspx?Value=2',
    );
    assert.equal(extractXmlUrl(fixture('ins_left.html')), null);
    assert.equal(extractXmlUrl("<script>window.frm.fileurl.value = '';</script>"), null);
  });

  test('pageRefs finds frames first, then quoted references', () => {
    const frameset =
      '<frameset rows="0,*"><frame src="blank.htm"><frame name="body" src="STD/SJ/SJ_51001/MarkView.aspx"></frameset>';
    assert.deepEqual(pageRefs(frameset, 'markview'), ['STD/SJ/SJ_51001/MarkView.aspx']);
    const markView =
      '<form action="./MarkView.aspx"></form><iframe id="rpt" src="MarkView_rpx.aspx?gubun=inform"></iframe>';
    assert.deepEqual(pageRefs(markView, 'markview_rpx'), ['MarkView_rpx.aspx?gubun=inform']);
    assert.deepEqual(pageRefs(markView, 'markview'), ['MarkView_rpx.aspx?gubun=inform', './MarkView.aspx']);
    assert.deepEqual(pageRefs("<script>location.href = 'STD/SJ/SJ_51001/MarkView.aspx';</script>", 'markview'), [
      'STD/SJ/SJ_51001/MarkView.aspx',
    ]);
  });
});

describe('grades XML', () => {
  test('decodeInsBytes: ASCII, UTF-8 with BOM, and real EUC-KR', () => {
    const enc = new TextEncoder();
    assert.equal(decodeInsBytes(enc.encode('<a>1</a>')), '<a>1</a>');
    assert.equal(decodeInsBytes(enc.encode('﻿café')), 'café');
    // EUC-KR bytes are not valid UTF-8; the browser decoder reads them properly.
    assert.equal(decodeInsBytes(new Uint8Array([0x41, 0xc1, 0xa4, 0xba, 0xb8, 0x42])), 'A정보B');
  });

  test('parses the fixture', () => {
    const report = parseGradesBytes(fixtureBytes('ins_grades.xml'));
    close(report.gpa, 3.558824, 1e-9);
    assert.equal(report.creditsEarned, 17.0);
    assert.equal(report.yearOfStudy, 2); // MAIN/GRADE, not MARK/GRADE
    assert.equal(report.records.length, 8);

    const first = report.records[0];
    assert.deepEqual(first, {
      term: '2025 Fall Semester',
      termKey: 20251,
      code: 'CSE1001',
      name: 'Introduction to Programming',
      credits: 3.0,
      letter: 'A+',
      points: 4.5,
      category: 'MR-M',
    });
    assert.ok(graded(first));

    assert.deepEqual(new Set(report.records.map((r) => r.termKey)), new Set([20251, 20252, 20261]));
    assert.equal(report.records[4].name, 'Signals & Systems');
    assert.equal(report.records[4].letter, 'C+');
    assert.equal(report.records[5].points, 3.0);

    const current = report.records.filter((r) => r.termKey === 20261);
    assert.equal(current.length, 2);
    for (const r of current) {
      assert.equal(r.term, 'Current Semester');
      assert.equal(r.letter, '-');
      assert.equal(graded(r), false);
      assert.equal(r.points, 0);
    }

    const done = report.records.filter(graded);
    const credits = done.reduce((s, r) => s + r.credits, 0);
    const points = done.reduce((s, r) => s + r.credits * r.points, 0);
    assert.equal(credits, report.creditsEarned);
    close(points / credits, report.gpa, 1e-6);
  });

  test('never carries JUMIN', () => {
    const xml = decodeInsBytes(fixtureBytes('ins_grades.xml'));
    assert.ok(xml.includes(fakeJumin)); // the fixture does have it...
    const json = JSON.stringify(parseGrades(xml));
    assert.ok(!json.includes(fakeJumin)); // ...the report does not
    assert.ok(!json.includes('000000-0000000'));
    assert.ok(!json.toLowerCase().includes('jumin'));
  });

  test('MAIN fields are direct children; MARKs may sit beside MAIN', () => {
    const xml =
      '<NewDataSet>' +
      '<MAIN><MARK><GRADE>7</GRADE><YEARTERM>20241</YEARTERM><HAKSU_NO>X1</HAKSU_NO>' +
      '<MARKS>B0</MARKS><JUMSU>3.00</JUMSU><CREDIT>1.0</CREDIT></MARK>' +
      '<GRADE>Junior</GRADE><COM_PYUNG>3.0</COM_PYUNG><COM_CREDIT>1.0</COM_CREDIT>' +
      '<JUMIN>secret<GRADE>9</GRADE></JUMIN></MAIN>' +
      '<MARK><YEARTERM>20242</YEARTERM><HAKSU_NO>X2</HAKSU_NO><MARKS></MARKS></MARK>' +
      '</NewDataSet>';
    const r = parseGrades(xml);
    assert.equal(r.yearOfStudy, 3); // "Junior"; MARK's 7 and JUMIN's 9 ignored
    assert.deepEqual(r.records.map((e) => e.code), ['X1', 'X2']);
    assert.equal(r.records[0].term, '20241'); // no DISPLAY_YEARTERM -> YEARTERM
    assert.equal(r.records[1].letter, '-'); // empty MARKS -> not graded
  });

  test('non-XML responses are a ParseError', () => {
    assert.throws(() => parseGrades(fixture('ins_start.html')), ParseError);
    assert.throws(() => parseGrades(''), ParseError);
    assert.throws(() => parseGrades('<html><body><main>hi</main></body></html>'), ParseError);
  });

  test('an XML with no courses yet is still a report', () => {
    const r = parseGrades('<root><MAIN><GRADE>1</GRADE><COM_PYUNG>0</COM_PYUNG><COM_CREDIT>0</COM_CREDIT></MAIN></root>');
    assert.deepEqual(r.records, []);
    assert.equal(r.yearOfStudy, 1);
  });
});

// ---------------------------------------------------------------------------
// InsClient against a fake ITIS behind a fake browser
// ---------------------------------------------------------------------------

const studentId = 'U2510001'; // fake
const password = 'p@ss w+rd&=1'; // fake, with characters that need form-encoding
const gradesParam = 'param=FAKEgRaD3s+St4nd/1ngs==&ENGYN=Y';
const xmlQuery = 'Value=FAKE0T0KEN0abc%3d'; // as the raw rpx page writes it

type MainMode = 'redirect' | 'frameset' | 'script' | 'opaque' | 'internal';
type LoggedOutMode = 'redirect' | 'script';

interface Req {
  method: string;
  url: URL;
  body: string;
  headers: Record<string, string>;
}
const show = (r: Req) => `${r.method} ${r.url.pathname}${r.url.search}`;

interface Answer {
  status: number;
  body: string | Uint8Array;
  location?: string;
  setCookie?: string;
}

/**
 * A tiny ITIS (Start.aspx login, FRAMESET.htm, left.aspx, main.aspx,
 * MarkView.aspx, MarkView_rpx.aspx, MarkView_xml.aspx) seen through what
 * fetch does in a browser: one cookie jar, redirects followed (a 302 to a
 * POST becomes a GET), and an unresolvable host as a network failure.
 */
class FakeIns {
  mainMode: MainMode = 'redirect';
  loggedOutMode: LoggedOutMode = 'redirect';
  loginRedirects = true; // 302 to FRAMESET.htm, else a 200 script page
  /** When set, the login redirect names this host absolutely, like the real server's http://ins.iutdev.ac.kr/... answers. */
  loginRedirectHost: string | null = null;
  forgetLoginImmediately = false; // login "succeeds" but the session is never authed

  sessions = new Map<string, { authed: boolean; gradesMenuVisited: boolean }>();
  requests: Req[] = [];
  private cookie: string | null = null; // the browser's jar
  private next = 0;

  expireAllSessions() {
    this.sessions.clear();
  }
  get logins() {
    return this.requests.filter((r) => r.method === 'POST' && r.url.pathname.toLowerCase() === '/itis/start.aspx');
  }
  get xmlRequest() {
    const xs = this.requests.filter((r) => r.url.pathname.toLowerCase().endsWith('markview_xml.aspx'));
    assert.equal(xs.length, 1);
    return xs[0];
  }

  http = async (url: string, req: HttpRequest = {}): Promise<HttpResponse> => {
    let method = req.method ?? (req.body == null ? 'GET' : 'POST');
    let body = typeof req.body === 'string' ? req.body : req.body ? new URLSearchParams(req.body).toString() : '';
    let at = new URL(url);
    let redirected = false;
    for (let hop = 0; hop < 10; hop++) {
      if (at.host !== 'ins.inha.uz') throw new NetworkError(`${at.host} unreachable`, 0, true);
      const r: Req = { method, url: at, body, headers: { ...(req.headers ?? {}) } };
      this.requests.push(r);
      const a = this.answer(r);
      if (a.setCookie) this.cookie = a.setCookie;
      if (a.location && a.status >= 300 && a.status < 400) {
        at = new URL(a.location, at);
        method = 'GET';
        body = '';
        redirected = true;
        continue;
      }
      const bytes = typeof a.body === 'string' ? new TextEncoder().encode(a.body) : a.body;
      return {
        status: a.status,
        url: at.href,
        redirected,
        headers: new Headers(),
        bytes,
        text: (enc = 'utf-8') => new TextDecoder(enc).decode(bytes),
      };
    }
    throw new NetworkError('too many redirects');
  };

  private answer(req: Req): Answer {
    let sess = this.cookie == null ? undefined : this.sessions.get(this.cookie);
    let setCookie: string | undefined;
    if (sess == null) {
      const id = `fakesession${this.next++}`;
      sess = { authed: false, gradesMenuVisited: false };
      this.sessions.set(id, sess);
      setCookie = id;
    }
    const html = (text: string, status = 200): Answer => ({ status, body: text, setCookie });
    const redirect = (location: string): Answer => ({ status: 302, body: 'Object moved', location, setCookie });
    const loggedOut = () =>
      this.loggedOutMode === 'redirect'
        ? redirect('/ITIS/Start.aspx')
        : html("<script>alert('Session expired.');top.location.href='/ITIS/Start.aspx';</script>");

    const path = req.url.pathname.toLowerCase();
    const query = req.url.search.replace(/^\?/, '');
    switch (`${req.method} ${path}`) {
      case 'GET /itis/start.aspx':
        return html(fixture('ins_start.html'));

      case 'POST /itis/start.aspx': {
        const form = new URLSearchParams(req.body);
        const ok =
          form.get('txtInhaID') === studentId &&
          form.get('txtPW') === password &&
          form.has('btnLogin') &&
          form.get('__VIEWSTATE') === '/wEPDwUKLTFBS0VWSUVXU1RBVEUPZBYCAgMPZBYCZg8PFgIeBFRleHQFBEZBS0VkZGQ+v1ewFAKE/9z+Q==' &&
          form.get('__EVENTVALIDATION') === '/wEdAAXFAKEeventVALIDATIONxx+yy/zz==';
        if (!ok) return html(fixture('ins_start_error.html'));
        if (!this.forgetLoginImmediately) sess.authed = true;
        return this.loginRedirects
          ? redirect(this.loginRedirectHost == null ? '/ITIS/FRAMESET.htm' : `http://${this.loginRedirectHost}/ITIS/FRAMESET.htm`)
          : html("<script>top.location.href='FRAMESET.htm';</script>");
      }

      case 'GET /itis/frameset.htm':
        return html('<html><frameset cols="200,*"><frame name="left" src="left.aspx"><frame name="main" src="main.aspx"></frameset></html>');

      case 'GET /itis/left.aspx':
        return sess.authed ? html(fixture('ins_left.html')) : loggedOut();

      case 'GET /itis/main.aspx':
        if (!sess.authed) return loggedOut();
        if (decodeURIComponent(query) !== decodeURIComponent(gradesParam)) return html('<p>Other menu</p>');
        sess.gradesMenuVisited = true;
        switch (this.mainMode) {
          case 'redirect':
            return redirect('/ITIS/STD/SJ/SJ_51001/MarkView.aspx');
          case 'frameset':
            return html('<frameset rows="0,*"><frame src="blank.htm"><frame name="body" src="STD/SJ/SJ_51001/MarkView.aspx"></frameset>');
          case 'script':
            return html("<script>location.href = 'STD/SJ/SJ_51001/MarkView.aspx';</script>");
          case 'opaque':
            return html('<html><body onload="go()"></body></html>');
          case 'internal':
            return redirect('http://ins.iutdev.ac.kr/ITIS/STD/SJ/SJ_51001/MarkView.aspx');
        }
        break;

      case 'GET /itis/std/sj/sj_51001/markview.aspx':
        if (!sess.authed) return loggedOut();
        if (!sess.gradesMenuVisited) return html('<p>Invalid access</p>');
        return html('<form id="form1" action="./MarkView.aspx"></form><iframe id="ifrReport" src="MarkView_rpx.aspx?gubun=inform"></iframe>');

      case 'GET /itis/std/sj/sj_51001/markview_rpx.aspx':
        if (!sess.authed) return loggedOut();
        if (!sess.gradesMenuVisited || query !== 'gubun=inform') return html('<p>Invalid access</p>');
        return html(fixture('ins_rpx.html'));

      case 'POST /itis/std/sj/sj_51001/markview_xml.aspx':
        if (!sess.authed) return loggedOut();
        // compared decoded: %3d and %3D are the same
        if (decodeURIComponent(query) !== decodeURIComponent(xmlQuery)) return html('<p>Bad token</p>', 400);
        return { status: 200, body: fixtureBytes('ins_grades.xml'), setCookie };
    }
    return html('<h1>404</h1>', 404);
  }
}

describe('InsClient', () => {
  let server: FakeIns;
  let creds: Credentials | null;
  let client: InsClient;

  beforeEach(() => {
    server = new FakeIns();
    creds = { username: 'u2510001 ', password };
    client = new InsClient(async (s) => (s === 'ins' ? creds : null), { http: server.http });
  });

  async function expectGrades(): Promise<GradeReport> {
    const report = await client.grades();
    assert.equal(report.records.length, 8);
    close(report.gpa, 3.558824, 1e-9);
    assert.equal(report.creditsEarned, 17);
    assert.equal(report.yearOfStudy, 2);
    return report;
  }

  test('fresh start: logs in and walks the whole grades chain', async () => {
    const report = await expectGrades();
    assert.equal(report.records.filter((r) => !graded(r)).length, 2);

    assert.deepEqual(server.requests.map(show), [
      'GET /ITIS/left.aspx', // no session yet
      'GET /ITIS/Start.aspx', // ...bounced to the login page by the browser
      'GET /ITIS/Start.aspx', // login: fresh hidden fields
      'POST /ITIS/Start.aspx',
      'GET /ITIS/FRAMESET.htm',
      'GET /ITIS/left.aspx',
      `GET /ITIS/main.aspx?${gradesParam}`,
      'GET /ITIS/STD/SJ/SJ_51001/MarkView.aspx',
      'GET /ITIS/STD/SJ/SJ_51001/MarkView_rpx.aspx?gubun=inform',
      `POST /ITIS/STD/SJ/SJ_51001/MarkView_xml.aspx?${xmlQuery}`,
    ]);

    // The login post: every hidden input of form1, uppercased ID, btnLogin present.
    const login = server.logins[0];
    assert.equal(server.logins.length, 1);
    assert.match(login.headers['Content-Type'], /^application\/x-www-form-urlencoded/);
    assert.deepEqual(Object.fromEntries(new URLSearchParams(login.body)), {
      __EVENTTARGET: '',
      __EVENTARGUMENT: '',
      __VIEWSTATE: '/wEPDwUKLTFBS0VWSUVXU1RBVEUPZBYCAgMPZBYCZg8PFgIeBFRleHQFBEZBS0VkZGQ+v1ewFAKE/9z+Q==',
      __VIEWSTATEGENERATOR: 'FA4E0001',
      __EVENTVALIDATION: '/wEdAAXFAKEeventVALIDATIONxx+yy/zz==',
      errorMessage: '',
      hdnPublicKey: 'FAKE00PUBLIC00KEY',
      txtInhaID: studentId,
      txtPW: password,
      btnLogin: '',
    });
    assert.ok(login.body.includes('btnLogin='));

    // The XML is fetched with an empty POST.
    assert.equal(server.xmlRequest.body, '');
  });

  test('the report never carries JUMIN', async () => {
    const json = JSON.stringify(await expectGrades());
    assert.ok(!json.includes(fakeJumin));
    assert.ok(!json.includes('000000-0000000'));
  });

  test('second call reuses the session (no new login)', async () => {
    await expectGrades();
    server.requests = [];
    await expectGrades();
    assert.equal(server.logins.length, 0);
    assert.equal(show(server.requests[0]), 'GET /ITIS/left.aspx');
  });

  for (const mode of ['redirect', 'frameset', 'script', 'opaque'] as const) {
    test(`main.aspx as ${mode} still reaches the XML`, async () => {
      server.mainMode = mode;
      await expectGrades();
      if (mode === 'opaque') {
        // Fell back to the known rpx URL after visiting main.aspx.
        const paths = server.requests.map(show);
        assert.ok(
          paths.indexOf('GET /ITIS/STD/SJ/SJ_51001/MarkView_rpx.aspx?gubun=inform') > paths.indexOf(`GET /ITIS/main.aspx?${gradesParam}`),
        );
      }
    });
  }

  test('a login redirect naming the internal host: the menu confirms the login', async () => {
    server.loginRedirectHost = 'ins.iutdev.ac.kr';
    await expectGrades();
    assert.equal(server.logins.length, 1);
    assert.deepEqual(new Set(server.requests.map((r) => r.url.origin)), new Set(['https://ins.inha.uz']));
  });

  test('login answered with a script redirect counts as success', async () => {
    server.loginRedirects = false;
    await expectGrades();
    assert.equal(server.logins.length, 1);
  });

  test('bad password: LoginRequired with the server message, one attempt', async () => {
    creds = { username: 'u2510001', password: 'wrong' };
    await assert.rejects(
      client.grades(),
      (e: unknown) =>
        e instanceof LoginRequired && e.service === 'ins' && e.message.endsWith('The ID or password is incorrect. (fake message)'),
    );
    assert.equal(server.logins.length, 1);
    assert.equal(server.requests.filter((r) => r.url.pathname.toLowerCase().includes('markview')).length, 0);
  });

  test('ensureLoggedIn: bad password throws, good password passes', async () => {
    creds = { username: 'u2510001', password: 'wrong' };
    await assert.rejects(client.ensureLoggedIn(), LoginRequired);
    creds = { username: 'u2510001', password };
    await client.ensureLoggedIn();
    server.requests = [];
    await client.ensureLoggedIn(); // already in: just the menu check
    assert.deepEqual(server.requests.map(show), ['GET /ITIS/left.aspx']);
  });

  test('verifyLogin posts the login; a wrong one throws, and a live session is reported as untested', async () => {
    creds = { username: 'u2510001', password: 'wrong' };
    await assert.rejects(client.verifyLogin(), (e: unknown) => e instanceof LoginRequired && e.rejected);
    creds = { username: 'u2510001', password };
    assert.equal(await client.verifyLogin(), true);
    assert.equal(server.logins.length, 2);

    // INS answers Start.aspx with its frames while a session lives: there is no form to post to.
    const frames = new InsClient(async () => creds, {
      http: async (url, req) => {
        const res = await server.http(url, req);
        if (!url.endsWith('Start.aspx')) return res;
        const bytes = new TextEncoder().encode('<frameset><frame src="left.aspx"></frameset>');
        return { ...res, bytes, text: () => '<frameset><frame src="left.aspx"></frameset>' };
      },
    });
    assert.equal(await frames.verifyLogin(), false);
    assert.equal(server.logins.length, 2);
  });

  test('a refused login is not posted again until something changes', async () => {
    creds = { username: 'u2510001', password: 'wrong' };
    const told: string[] = [];
    const c = new InsClient(async () => creds, { http: server.http, onRejected: (_, login) => void told.push(login.password) });
    await assert.rejects(c.grades(), LoginRequired);
    await assert.rejects(c.grades(), LoginRequired);
    assert.equal(server.logins.length, 1);
    assert.deepEqual(told, ['wrong']);
    c.forgetRejected();
    await assert.rejects(c.grades(), LoginRequired);
    assert.equal(server.logins.length, 2);
    creds = { username: 'u2510001', password };
    await c.grades();
    assert.equal(server.logins.length, 3);
  });

  test('a menu hop redirected to the internal host falls through to the direct report URL', async () => {
    server.mainMode = 'internal';
    await expectGrades();
    assert.ok(server.requests.some((r) => r.url.pathname.toLowerCase().endsWith('markview_rpx.aspx')));
  });

  test('every hop failing is the network error, not a changed page', async () => {
    await client.ensureLoggedIn();
    const refused = new NetworkError('ins.inha.uz unreachable', 0, true);
    const c = new InsClient(async () => creds, {
      http: async (url, req) => {
        if (url.includes('main.aspx') || url.includes('MarkView')) throw refused;
        return server.http(url, req);
      },
    });
    await assert.rejects(c.grades(), (e: unknown) => e === refused);
  });

  test('in an INS tab a failed menu means the session redirect: it logs in and goes on', async () => {
    await client.ensureLoggedIn();
    let failed = false;
    const c = new InsClient(async () => creds, {
      inTab: true,
      http: async (url, req) => {
        if (url.endsWith('left.aspx') && !failed) {
          failed = true;
          throw new NetworkError('ins.iutdev.ac.kr unreachable');
        }
        return server.http(url, req);
      },
    });
    assert.ok((await c.grades()).records.length > 0);
    // In the worker the same failure is passed up, for the caller to fall back on.
    failed = false;
    const worker = new InsClient(async () => creds, {
      http: async (url, req) => {
        if (url.endsWith('left.aspx') && !failed) {
          failed = true;
          throw new NetworkError('ins.inha.uz unreachable', 0, true);
        }
        return server.http(url, req);
      },
    });
    await assert.rejects(worker.grades(), NetworkError);
  });

  test('no saved login: LoginRequired without posting anything', async () => {
    creds = null;
    await assert.rejects(client.grades(), LoginRequired);
    assert.equal(server.logins.length, 0);
  });

  for (const mode of ['redirect', 'script'] as const) {
    test(`expired session (${mode}): logs in again once and retries`, async () => {
      server.loggedOutMode = mode;
      await expectGrades();
      assert.equal(server.logins.length, 1);

      server.expireAllSessions();
      server.requests = [];
      await expectGrades();
      assert.equal(server.logins.length, 1); // exactly one re-login
      assert.equal(show(server.requests[0]), 'GET /ITIS/left.aspx');
    });
  }

  test('session that never sticks: one re-login, then LoginRequired', async () => {
    server.forgetLoginImmediately = true;
    await assert.rejects(client.grades(), (e: unknown) => e instanceof LoginRequired && e.service === 'ins');
    assert.equal(server.logins.length, 1);
  });

  test('concurrent calls share one login', async () => {
    const results = await Promise.all([client.grades(), client.grades()]);
    assert.equal(results.length, 2);
    assert.equal(server.logins.length, 1);
  });

  test("the browser's certificate refusal is passed up unchanged", async () => {
    const refused = new NetworkError('ins.inha.uz unreachable: Failed to fetch', 0, true);
    const blocked = new InsClient(async () => creds, {
      http: async () => {
        throw refused;
      },
    });
    await assert.rejects(blocked.grades(), (e: unknown) => e === refused);
  });
});
