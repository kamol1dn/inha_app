// Pure parsers for INS / ITIS (ins.inha.uz) pages. No I/O here, so every
// function can be tested against fixtures. A port of
// lib/services/ins/ins_parsers.dart; see docs/ENDPOINTS.md.

import { parseHtml } from '../../core/dom.ts';
import { ParseError } from '../../core/errors.ts';
import type { GradeRecord, GradeReport } from '../../core/models.ts';

// ---------------------------------------------------------------------------
// Bytes -> text
// ---------------------------------------------------------------------------

/**
 * The single place INS response bytes become text (HTML pages and the grades
 * XML alike). Strict UTF-8 first (the HTML pages, and in case the server ever
 * sends UTF-8); otherwise EUC-KR, which the grades XML declares. Unlike the
 * app, the browser has a real EUC-KR decoder, so Korean text survives.
 */
export function decodeInsBytes(bytes: Uint8Array): string {
  let text: string;
  try {
    text = new TextDecoder('utf-8', { fatal: true, ignoreBOM: true }).decode(bytes);
  } catch {
    text = new TextDecoder('euc-kr').decode(bytes);
  }
  return text.startsWith('\uFEFF') ? text.substring(1) : text;
}

// ---------------------------------------------------------------------------
// Login page (Start.aspx)
// ---------------------------------------------------------------------------

/** `form1`, or the first form, or null. */
function form1(doc: Document): Element | null {
  return doc.querySelector('form#form1') ?? doc.querySelector('form[name="form1"]') ?? doc.querySelector('form');
}

/** The input's lowercased name, else its lowercased id. */
const lowerName = (e: Element) => (e.getAttribute('name') ?? e.getAttribute('id') ?? '').toLowerCase();

const isHidden = (e: Element) => (e.getAttribute('type') ?? '').trim().toLowerCase() === 'hidden';

/**
 * Every `input[type=hidden]` inside `form1` (name -> value, document order),
 * i.e. `__VIEWSTATE`, `__VIEWSTATEGENERATOR`, `__EVENTVALIDATION`,
 * `errorMessage` and whatever else WebForms put there. All of them go back in
 * the login POST.
 *
 * If `form1` exists but the HTML parser left the inputs outside it (a form
 * inside a table does that), falls back to every hidden input in the page.
 */
export function hiddenInputs(html: string): Record<string, string> {
  const doc = parseHtml(html);
  const collect = (scope: Element | null): Record<string, string> => {
    const out: Record<string, string> = {};
    if (scope == null) return out;
    for (const input of Array.from(scope.querySelectorAll('input'))) {
      const name = input.getAttribute('name');
      if (!name || !isHidden(input)) continue;
      out[name] = input.getAttribute('value') ?? '';
    }
    return out;
  };
  const fromForm = collect(form1(doc));
  return Object.keys(fromForm).length > 0 ? fromForm : collect(doc.documentElement);
}

/** The `action` attribute of `form1` as written (e.g. `./Start.aspx`), or null. */
export function formAction(html: string): string | null {
  const action = form1(parseHtml(html))?.getAttribute('action')?.trim();
  return action ? action : null;
}

/** True for the ITIS login form: it has the `txtInhaID` / `txtPW` inputs. */
export function isInsLoginPage(html: string): boolean {
  return Array.from(parseHtml(html).querySelectorAll('input')).some((e) => {
    const name = lowerName(e);
    return name.endsWith('txtpw') || name.endsWith('txtinhaid');
  });
}

/** The server's reason for a failed login: the hidden `errorMessage` input that Start.aspx fills in. Null when there is none or it is blank. */
export function loginError(html: string): string | null {
  for (const input of Array.from(parseHtml(html).querySelectorAll('input'))) {
    if (lowerName(input) !== 'errormessage') continue;
    const value = squash(input.getAttribute('value') ?? '');
    return value ? value : null;
  }
  return null;
}

const loginRedirect =
  /location(?:\.href)?\s*(?:=\s*|\.(?:replace|assign)\s*\(\s*)['"][^'"]*start\.aspx/i;
const sessionMessage = /session\s+(?:has\s+|is\s+)?(?:expired|timed?\s*out)/i;

/**
 * True when a page is the login form, or a stub that bounces the browser to
 * Start.aspx, or says the session expired. Pages that legitimately contain a
 * logout script also match, so callers check for the content they expected
 * first and only then ask this.
 */
export function isSessionExpired(html: string): boolean {
  return isInsLoginPage(html) || loginRedirect.test(html) || sessionMessage.test(html);
}

// ---------------------------------------------------------------------------
// Menu (left.aspx)
// ---------------------------------------------------------------------------

const squash = (s: string) => s.replace(/[\s\u00a0]+/g, ' ').trim();

const quotedAspx = /['"]([^'"\s<>]*\.aspx[^'"\s<>]*)['"]/i;

/** The menu target of an `<a>`: its href, or for `href="#"` / `javascript:` links, the first quoted `.aspx` URL in its href/onclick. */
function anchorTarget(a: Element): string | null {
  const href = (a.getAttribute('href') ?? '').trim();
  const lower = href.toLowerCase();
  if (href && !href.startsWith('#') && !lower.startsWith('javascript:')) return href;
  for (const source of [href, a.getAttribute('onclick') ?? '']) {
    const m = quotedAspx.exec(source);
    if (m) return m[1];
  }
  return null;
}

/**
 * Resolves `ref` against the path `base` the way Dart's Uri.resolve does
 * here: a same-origin result is a path with its query (`/ITIS/main.aspx?...`),
 * anything absolute elsewhere stays absolute.
 */
function resolvePath(base: string, ref: string): string {
  const origin = 'https://ins.invalid';
  const u = new URL(ref, origin + base);
  return u.origin === origin ? u.pathname + u.search + u.hash : u.href;
}

/**
 * The menu link whose text (whitespace-collapsed, trimmed) equals `text`,
 * resolved against `base` (default `/ITIS/`, where left.aspx lives). Returns
 * e.g. `/ITIS/main.aspx?param=<opaque>&ENGYN=Y` with the opaque param exactly
 * as the page had it, or null. Exact match wins; a case-insensitive match is
 * the fallback; last, the raw source is searched for `href="...">text<`, which
 * catches menus written into the page by script (`document.write`, innerHTML).
 */
export function findMenuLink(leftHtml: string, text: string, base = '/ITIS/'): string | null {
  const want = squash(text);
  const anchors = Array.from(parseHtml(leftHtml).querySelectorAll('a'));
  const hit =
    anchors.find((a) => squash(a.textContent ?? '') === want && anchorTarget(a) != null) ??
    anchors.find((a) => squash(a.textContent ?? '').toLowerCase() === want.toLowerCase() && anchorTarget(a) != null);
  const target = hit == null ? scriptedMenuTarget(leftHtml, want) : anchorTarget(hit);
  return target == null ? null : resolvePath(base, target);
}

const escapeRegExp = (s: string) => s.replace(/[.*+?^${}()|[\]\\]/g, '\\$&');

function scriptedMenuTarget(source: string, text: string): string | null {
  if (!text) return null;
  const gap = String.raw`(?:\s|&nbsp;|\\[nrt])`;
  const words = text.split(' ').map(escapeRegExp).join(`${gap}+`);
  const m = new RegExp(
    String.raw`href\s*=\s*\\?["']([^"'\\]*\.aspx[^"'\\]*)\\?["'][^>]*>` + `(?:${gap}|<[^>]*>)*` + words + `${gap}*<`,
    'i',
  ).exec(source);
  return m?.[1]?.replace(/&amp;/g, '&') ?? null;
}

const menuParam = /main\.aspx\?param=/i;

/** True when the page source has a `main.aspx?param=` menu link anywhere (markup or script), i.e. it is a logged-in left.aspx. */
export function hasMenuLinks(leftHtml: string): boolean {
  return menuParam.test(leftHtml);
}

// ---------------------------------------------------------------------------
// Grades pages (main.aspx -> MarkView.aspx -> MarkView_rpx.aspx)
// ---------------------------------------------------------------------------

/**
 * URLs on a page that mention `hint` (case-insensitive): `frame`/`iframe`
 * srcs first, then any other quoted URL (script redirects, `src = '...'`
 * assignments, links). Raw, unresolved, in document order, no duplicates.
 */
export function pageRefs(html: string, hint: string): string[] {
  const needle = hint.toLowerCase();
  const out: string[] = [];
  const add = (ref: string | null | undefined) => {
    const r = ref?.trim();
    if (!r || out.includes(r)) return;
    if (r.toLowerCase().startsWith('javascript:')) return;
    if (r.toLowerCase().includes(needle)) out.push(r);
  };

  for (const f of Array.from(parseHtml(html).querySelectorAll('frame, iframe'))) add(f.getAttribute('src'));
  const quoted = new RegExp(`['"]([^'"\\s<>]*${escapeRegExp(hint)}[^'"\\s<>]*)['"]`, 'gi');
  for (const m of html.matchAll(quoted)) add(m[1]);
  return out;
}

/** `ViewerReportInForm("<report>.rpx", "<xml url>", ...)`, any ViewerReportIn* variant. */
const viewerCall = /ViewerReportIn\w*\s*\(\s*["'][^"']*["']\s*,\s*["']([^"']+)["']/;

const fileUrlAssign = /fileurl\s*\.\s*value\s*=\s*(?:'([^']*)'|"([^"]*)")/gi;

/**
 * The grades XML URL from MarkView_rpx.aspx, relative to that page.
 *
 * The server's raw page calls the Cabsoft viewer:
 * `ViewerReportInForm("HJ_03507_R01.rpx","MarkView_xml.aspx?Value=...",...)`,
 * and the second argument is the URL. The viewer script then builds
 * `window.frm.fileurl` in the browser, which is what a live DOM shows; those
 * forms are kept as fallbacks. Null if absent.
 */
export function extractXmlUrl(rpxHtml: string): string | null {
  const viewer = viewerCall.exec(rpxHtml);
  if (viewer) return viewer[1].trim();
  for (const m of rpxHtml.matchAll(fileUrlAssign)) {
    const raw = (m[1] ?? m[2] ?? '').trim();
    if (!raw) continue;
    return raw.replace(/\\\//g, '/').replace(/\\\\/g, '\\');
  }
  for (const input of Array.from(parseHtml(rpxHtml).querySelectorAll('input'))) {
    if ((input.getAttribute('name') ?? '').toLowerCase() !== 'fileurl') continue;
    const v = (input.getAttribute('value') ?? '').trim();
    if (v) return v;
  }
  return null;
}

// ---------------------------------------------------------------------------
// Grades XML (MarkView_xml.aspx)
// ---------------------------------------------------------------------------

/** Elements whose content is skipped unread by the XML reader. `JUMIN` is the national ID number: it is never read, stored or shown. */
const redacted = new Set(['jumin']);

class XmlElement {
  readonly name: string; // lowercased
  readonly children: XmlElement[] = [];
  textParts: string[] = [];
  constructor(name: string) {
    this.name = name;
  }

  /** Own text (not descendants'), whitespace-collapsed. */
  get text(): string {
    return squash(this.textParts.join(''));
  }

  child(name: string): XmlElement | null {
    return this.children.find((c) => c.name === name) ?? null;
  }

  field(name: string): string {
    return this.child(name)?.text ?? '';
  }

  *descendants(name: string): Generator<XmlElement> {
    for (const c of this.children) {
      if (c.name === name) yield c;
      yield* c.descendants(name);
    }
  }
}

const xmlToken = new RegExp(
  String.raw`<!\[CDATA\[([\s\S]*?)\]\]>` + // 1: CDATA
    String.raw`|<!--[\s\S]*?-->` + // comment
    String.raw`|<\?[\s\S]*?\?>` + // <?xml ...?>
    String.raw`|<![^>]*>` + // DOCTYPE
    String.raw`|</\s*([^\s>]+)\s*>` + // 2: end tag
    String.raw`|<([A-Za-z_][\w:.\-]*)((?:[^>"']|"[^"]*"|'[^']*')*?)(/?)>`, // 3: name, 4: attrs, 5: '/'
  'g',
);

const entity = /&(#x[0-9a-fA-F]+|#\d+|amp|lt|gt|quot|apos);/g;
const named: Record<string, string> = { amp: '&', lt: '<', gt: '>', quot: '"', apos: "'" };

function unescapeXml(s: string): string {
  return s.replace(entity, (whole, e: string) => {
    if (e in named) return named[e];
    const code = e.startsWith('#x') ? parseInt(e.substring(2), 16) : parseInt(e.substring(1), 10);
    return Number.isNaN(code) || code > 0x10ffff ? whole : String.fromCodePoint(code);
  });
}

/**
 * A small, tolerant XML reader: enough for the flat DataSet-style XML INS
 * serves (elements and text; attributes ignored). Tag names are lowercased.
 * Self-closing tags, comments, CDATA and entities are handled; a stray end
 * tag is ignored and a missing one is implied. `redacted` elements are
 * skipped without their content ever being extracted.
 */
function readXml(xml: string): XmlElement {
  const root = new XmlElement('#document');
  const stack = [root];
  const top = () => stack[stack.length - 1];
  let pos = 0;
  while (pos < xml.length) {
    xmlToken.lastIndex = pos;
    const m = xmlToken.exec(xml);
    if (m == null) break;
    if (m.index > pos) top().textParts.push(unescapeXml(xml.substring(pos, m.index)));
    pos = m.index + m[0].length;

    if (m[1] != null) {
      top().textParts.push(m[1]);
    } else if (m[2] != null) {
      const name = m[2].toLowerCase();
      let at = -1;
      for (let i = stack.length - 1; i >= 0; i--) {
        if (stack[i].name === name) {
          at = i;
          break;
        }
      }
      if (at > 0) stack.length = at;
    } else if (m[3] != null) {
      const name = m[3].toLowerCase();
      const selfClosing = m[5] === '/';
      if (redacted.has(name)) {
        if (!selfClosing) {
          const end = new RegExp(`</\\s*${escapeRegExp(name)}\\s*>`, 'ig');
          end.lastIndex = pos;
          const e = end.exec(xml);
          pos = e == null ? xml.length : e.index + e[0].length;
        }
        continue;
      }
      const el = new XmlElement(name);
      top().children.push(el);
      if (!selfClosing) stack.push(el);
    }
  }
  return root;
}

function toDouble(s: string): number {
  const t = s.trim();
  if (!/^[+-]?(\d+\.?\d*|\.\d+)([eE][+-]?\d+)?$/.test(t)) return 0;
  return Number(t);
}

function yearOfStudy(s: string): number {
  const digitsOnly = s.replace(/\D/g, '');
  if (digitsOnly) return Number(digitsOnly);
  return ({ freshman: 1, sophomore: 2, junior: 3, senior: 4 } as Record<string, number>)[s.trim().toLowerCase()] ?? 0;
}

/**
 * Parses the "View Grades and Standings" XML (`<root><MAIN>... <MARK>...`).
 *
 * GPA = `MAIN/COM_PYUNG`, credits earned = `MAIN/COM_CREDIT`, year of study =
 * `MAIN/GRADE` (direct children of MAIN only: each MARK has its own GRADE
 * like "Junior"). One GradeRecord per `MARK`, in document order, wherever
 * the MARKs sit (inside MAIN as documented, or beside it). `JUMIN` is never
 * read. Throws ParseError if the text is not this XML (e.g. an HTML page).
 */
export function parseGrades(xml: string): GradeReport {
  const doc = readXml(xml);
  let main: XmlElement | null = null;
  for (const e of doc.descendants('main')) {
    if (e.child('com_pyung') != null || e.child('com_credit') != null) {
      main = e;
      break;
    }
  }
  if (main == null) throw new ParseError('INS grades');

  const records: GradeRecord[] = [];
  for (const m of doc.descendants('mark')) {
    const code = m.field('haksu_no');
    const kname = m.field('kwamok_kname');
    const name = kname || m.field('kwamok_ename');
    if (!code && !name) continue;
    const yearTerm = m.field('yearterm');
    const display = m.field('display_yearterm');
    const letter = m.field('marks');
    const key = yearTerm.replace(/\D/g, '');
    records.push({
      term: display || yearTerm,
      termKey: key ? Number(key) : 0,
      code,
      name,
      credits: toDouble(m.field('credit')),
      letter: letter || '-',
      points: toDouble(m.field('jumsu')),
      category: m.field('jong_akname'),
    });
  }

  return {
    gpa: toDouble(main.field('com_pyung')),
    creditsEarned: toDouble(main.field('com_credit')),
    yearOfStudy: yearOfStudy(main.field('grade')),
    records,
  };
}

/** parseGrades straight from response bytes, via decodeInsBytes. */
export function parseGradesBytes(bytes: Uint8Array): GradeReport {
  return parseGrades(decodeInsBytes(bytes));
}

/** Whether a GradeRecord has a final letter (not '-' while the term runs). */
export const graded = (r: GradeRecord) => r.letter !== '' && r.letter !== '-';
