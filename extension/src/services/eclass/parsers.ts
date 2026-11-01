// Pure HTML → model parsers for eClass pages. A port of
// lib/services/eclass/eclass_parsers.dart; see docs/ENDPOINTS.md for which
// page each one reads.
//
// Every parser throws ParseError when the page does not look like the page
// it expects (the site changed), and returns an empty list when the page is
// the right one but simply has nothing in it.

import { intParam, parseHtml, text } from '../../core/dom.ts';
import { ParseError } from '../../core/errors.ts';
import {
  courseFromTitle,
  type AttendanceEntry,
  type AttendanceMark,
  type Course,
  type CourseGrades,
  type Deadline,
  type DeadlineKind,
  type GradeItem,
  type VodProgress,
} from '../../core/models.ts';

/** Courses on the dashboard (`GET /`). */
export function parseCourses(html: string): Course[] {
  const doc = parseHtml(html);
  let links = Array.from(doc.querySelectorAll('.course_lists a.course_link[href]'));
  if (links.length === 0) {
    // Older or different layout: any course link that carries a course title.
    links = Array.from(doc.querySelectorAll('a[href*="/course/view.php?id="]')).filter(
      (a) => a.querySelector('.course-title') != null,
    );
  }

  const seen = new Set<number>();
  const courses: Course[] = [];
  for (const a of links) {
    const id = intParam(a.getAttribute('href'), 'id');
    if (id == null || seen.has(id)) continue;
    seen.add(id);
    const title = text(
      a.querySelector('.course-title h3') ?? a.querySelector('.course-title') ?? a.querySelector('h3') ?? a,
    );
    if (!title) continue;
    courses.push(courseFromTitle(id, title, text(a.querySelector('.prof'))));
  }

  if (courses.length === 0 && doc.querySelector('.course_lists, .progress_courses') == null) {
    throw new ParseError('eClass courses');
  }
  return courses;
}

/**
 * Events on `GET /calendar/view.php?view=upcoming`.
 *
 * Times come from the `time=<unix>` parameter of the date links, never from
 * the visible "Today"/"Tomorrow" text. One link is the due time; two are the
 * start and end of a window (VODs). Moodle splits a long quiz window into
 * "(Quiz opens)" and "(Quiz closes)" events; only the closing one is due, so the
 * opening one is left out.
 */
export function parseUpcoming(html: string): Deadline[] {
  const doc = parseHtml(html);
  let events = Array.from(doc.querySelectorAll('.eventlist .event'));
  if (events.length === 0) events = Array.from(doc.querySelectorAll('#region-main .event'));
  if (events.length === 0) {
    const isCalendar = doc.body?.id === 'page-calendar-view' || doc.querySelector('.maincalendar') != null;
    if (isCalendar) return [];
    throw new ParseError('eClass upcoming events');
  }

  const out: Deadline[] = [];
  for (const e of events) {
    const referer = e.querySelector('.referer');
    const title = text(referer ?? e.querySelector('h3.name') ?? e.querySelector('h3'));
    if (!title) throw new ParseError('eClass upcoming event title');

    const href = referer?.querySelector('a[href]')?.getAttribute('href');
    const mod = href ? modulePattern.exec(href) : null;
    const type = mod?.[1] ?? null;
    if (opensEvent.test(title)) continue;
    const kind: DeadlineKind =
      type === 'vod'
        ? 'vod'
        : type === 'assign'
          ? 'assignment'
          : type === 'quiz'
            ? 'quiz'
            : type == null && classPeriodTitle.test(title)
              ? 'classPeriod'
              : 'other';

    const dateEl = e.querySelector('.card-header .date') ?? e.querySelector('.date');
    const times = Array.from(dateEl?.querySelectorAll('a[href]') ?? [])
      .map((a) => intParam(a.getAttribute('href'), 'time'))
      .filter((s): s is number => s != null)
      .map((s) => s * 1000);
    if (times.length === 0) throw new ParseError('eClass upcoming event time');

    out.push({
      title,
      courseName: text(e.querySelector('.course')),
      courseId: intParam(e.querySelector('.course a[href]')?.getAttribute('href') ?? null, 'id'),
      kind,
      start: times.length >= 2 ? times[0] : null,
      end: times[times.length - 1],
      moduleId: mod ? Number(mod[2]) : null,
      moduleType: type,
      done: false,
      doneAt: null,
    });
  }
  return out;
}

/**
 * Class attendance on `GET /local/ubattendance/my_status.php?id=<course>`.
 *
 * The mark is whichever column (Attendance / Absence / Late / Others) holds
 * the `○`. A page without the table (the course does not take attendance)
 * gives an empty list.
 */
export function parseAttendance(html: string): AttendanceEntry[] {
  const doc = parseHtml(html);
  const table = doc.querySelector('table.attendance_my');
  if (table == null) {
    const isAttendancePage =
      doc.body?.id === 'page-local-ubattendance-my_status' || doc.querySelector('.attendance_book') != null;
    if (isAttendancePage) return [];
    throw new ParseError('eClass attendance');
  }

  const headers = Array.from(table.querySelectorAll('thead th')).map((th) => text(th));
  const markOf = attendanceColumns(headers);

  const out: AttendanceEntry[] = [];
  for (const row of expandRows(table)) {
    if (row.isMessage) continue; // "no data" row spanning the whole table
    const cells = row.cells;
    if (cells.length < 3) throw new ParseError('eClass attendance row');

    const m = /(\d{4})-(\d{1,2})-(\d{1,2})/.exec(text(cells[0]));
    if (!m) throw new ParseError('eClass attendance date');
    const date = `${m[1]}-${m[2].padStart(2, '0')}-${m[3].padStart(2, '0')}`;

    let mark: AttendanceMark = 'unmarked';
    for (const [col, value] of markOf) {
      if (col < cells.length && text(cells[col]).includes('○')) {
        mark = value;
        break;
      }
    }
    if (mark === 'unmarked') {
      // Some other symbol than ○ (e.g. "O" or "V"): take the first filled mark cell.
      for (const [col, value] of markOf) {
        if (col < cells.length && text(cells[col])) {
          mark = value;
          break;
        }
      }
    }

    out.push({ date, label: text(cells[1]), mark });
  }
  return out;
}

/**
 * VOD progress on `GET /report/ubcompletion/user_progress.php?id=<course>`.
 *
 * The Week cell spans all of a week's rows, so later rows have one cell
 * fewer. Weeks without VODs show an empty row and are skipped. A course
 * without progress-managed VODs has no table and gives an empty list.
 */
export function parseVodProgress(html: string): VodProgress[] {
  const doc = parseHtml(html);
  const table = doc.querySelector('table.user_progress');
  if (table == null) {
    const isProgressPage =
      doc.body?.id === 'page-report-ubcompletion-user_progress' ||
      doc.querySelector('.report_ubcompletion, #ubcompletion-progress-wrapper') != null;
    if (isProgressPage) return [];
    throw new ParseError('eClass VOD progress');
  }

  const out: VodProgress[] = [];
  for (const row of expandRows(table)) {
    if (row.isMessage) continue;
    const cells = row.cells;
    // Week, Resources, Contents time, max position, Progress.
    if (cells.length < 4) throw new ParseError('eClass VOD progress row');

    const title = text(cells[1]);
    if (!title) continue; // a week with nothing in it

    const weekCell = cells[0];
    const week =
      toInt(text(weekCell.querySelector('.sectiontitle'))) ??
      firstInt(text(weekCell)) ??
      firstInt(weekCell.querySelector('[title]')?.getAttribute('title') ?? '');
    if (week == null) throw new ParseError('eClass VOD progress week');

    const window = cells.map((c) => c.querySelector('[data-eterm]')).find((b) => b != null);
    out.push({
      week,
      title,
      lengthSec: parseClock(text(cells[2])),
      percent: parsePercent(text(cells[cells.length - 1])),
      opens: unixAttr(window, 'data-sterm'),
      closes: unixAttr(window, 'data-eterm'),
    });
  }
  return out;
}

export interface VodModule {
  name: string;
  moduleId: number;
}

/**
 * A course's VOD list, `GET /mod/vod/index.php?id=<course>`: each VOD's name and
 * course module id, from its `view.php?id=<module>` link, in page order. The
 * progress page's `data-modid` is the VOD's instance id, not a course module, so
 * a VOD's link can only come from here. The page is an extra: anything unexpected
 * gives an empty list, never an error.
 */
export function parseVodModules(html: string): VodModule[] {
  const doc = parseHtml(html);
  const root = doc.querySelector('#region-main') ?? doc.body;
  const out: VodModule[] = [];
  for (const a of Array.from(root?.querySelectorAll('a[href]') ?? [])) {
    const href = (a.getAttribute('href') ?? '').trim();
    const moduleId = vodLink.test(href) ? intParam(href, 'id') : null;
    const name = text(a);
    if (moduleId != null && name) out.push({ name, moduleId });
  }
  return out;
}

/**
 * Fills in each VOD's moduleId from parseVodModules, matching on the name with
 * case and spacing ignored. A repeated name takes the links in order; a row with
 * no link stays without an id.
 */
export function withVodModules(vods: VodProgress[], modules: VodModule[]): VodProgress[] {
  const norm = (s: string) => s.toLowerCase().replace(/\s+/g, ' ').trim();
  const byName = new Map<string, number[]>();
  for (const m of modules) byName.set(norm(m.name), [...(byName.get(norm(m.name)) ?? []), m.moduleId]);
  return vods.map((v) => {
    const moduleId = byName.get(norm(v.title))?.shift();
    return moduleId == null ? v : { ...v, moduleId };
  });
}

export interface Submission {
  done: boolean;
  at: number | null;
}

/**
 * Whether an assignment is handed in, from `GET /mod/assign/view.php?id=`.
 *
 * Moodle puts a `submissionstatus<state>` class on the "Submission status"
 * cell once there is a submission: `submitted` (done), `draft` (not handed
 * in), `reopened`, `new`. A graded assignment (`submissiongraded`) is done
 * too. With no class there is no attempt. `at` is the "Last modified" time.
 */
export function parseAssignSubmission(html: string): Submission {
  const doc = parseHtml(html);
  const isAssignPage = doc.body?.id === 'page-mod-assign-view';
  const table =
    doc.querySelector('.submissionstatustable table') ??
    (isAssignPage ? doc.querySelector('#region-main table.generaltable') : null);
  if (table == null) {
    if (isAssignPage) return { done: false, at: null };
    throw new ParseError('eClass assignment');
  }
  let state: string | null = null;
  for (const cell of Array.from(table.querySelectorAll('td'))) {
    for (const c of Array.from(cell.classList)) {
      if (c.startsWith('submissionstatus') && c.length > 'submissionstatus'.length) {
        state ??= c.substring('submissionstatus'.length);
      }
    }
  }
  const graded = table.querySelector('td.submissiongraded') != null;
  const done = state === 'submitted' || state === 'marked' || graded;
  let at: number | null = null;
  for (const row of Array.from(table.querySelectorAll('tr'))) {
    const cells = Array.from(row.children).filter((c) => c.localName === 'td' || c.localName === 'th');
    if (cells.length < 2) continue;
    const label = text(cells[0]).toLowerCase();
    if (label.includes('last modified') || label.includes('최종 수정')) at = parseDateTime(text(cells[1]));
  }
  return { done, at: done ? at : null };
}

/**
 * Whether a quiz is done, from `GET /mod/quiz/view.php?id=`: any attempt in
 * `table.quizattemptsummary` whose state is "Finished" (종료됨). `at` is the
 * newest "Submitted ..." time in the state details.
 */
export function parseQuizSubmission(html: string): Submission {
  const doc = parseHtml(html);
  if (doc.body?.id !== 'page-mod-quiz-view' && doc.querySelector('.quizinfo') == null) {
    throw new ParseError('eClass quiz');
  }
  let done = false;
  let at: number | null = null;
  for (const row of Array.from(doc.querySelectorAll('table.quizattemptsummary tbody tr'))) {
    // The state's column moves: a quiz with several attempts allowed adds an attempt number before it.
    const state = Array.from(row.querySelectorAll('td')).map((td) => text(td)).find((t) => /^(Finished|종료)/i.test(t));
    if (state == null) continue;
    done = true;
    const when = parseDateTime(state);
    if (when != null && (at == null || when > at)) at = when;
  }
  return { done, at };
}

/**
 * A course's grades page, `GET /grade/report/user/index.php?id=<course>`, or
 * null when the page has no table.
 *
 * The column classes hold whatever language the page is in. A row is a
 * category heading, an item (`th.item`) or a category's total (`th.baggt`),
 * which comes after the category's items and is the row carrying its weight;
 * the course's own total is that row at level 1. Nested categories multiply.
 */
export function parseGradeBook(html: string, course: Course): CourseGrades | null {
  const doc = parseHtml(html);
  const table = doc.querySelector('table.user-grade');
  if (table == null) {
    if (doc.body?.id === 'page-grade-report-user-index') return null;
    throw new ParseError('eClass grades');
  }

  const open = new Map<number, GradeCategoryRows>(); // the category being read at each level
  const rows: [Element, GradeCategoryRows | undefined][] = [];
  const categories: GradeCategoryRows[] = [];
  let percent: number | null = null;
  for (const tr of Array.from(table.querySelectorAll('tbody tr'))) {
    const th = tr.querySelector('th.column-itemname');
    if (th == null) continue;
    const level = Number(/\blevel(\d+)\b/.exec(th.className)?.[1] ?? NaN);
    if (Number.isNaN(level)) throw new ParseError('eClass grades row');

    if (th.classList.contains('item')) {
      rows.push([tr, open.get(level - 1)]);
    } else if (th.classList.contains('baggt') || th.classList.contains('baggb')) {
      if (level === 1) {
        percent = courseTotalPercent(tr);
      } else {
        const c = open.get(level);
        if (c) c.weight = gradeNumber(gradeCell(tr, 'weight'));
      }
    } else {
      const c = new GradeCategoryRows(text(th), open.get(level - 1) ?? null);
      open.set(level, c);
      if (level > 1) categories.push(c);
    }
  }

  return {
    course,
    source: 'gradebook',
    percent,
    // A category holding categories is already counted through them.
    categories: categories.filter((c) => !categories.some((o) => o.parent === c)).map((c) => ({ name: c.name, weight: c.courseWeight })),
    items: rows.map(([tr, category]) => gradeItem(tr, category)),
  };
}

function gradeItem(tr: Element, category: GradeCategoryRows | undefined): GradeItem {
  const th = tr.querySelector('th.column-itemname')!;
  const id = /^row_(\d+)/.exec(th.id)?.[1];
  const link = th.querySelector('a.gradeitemheader[href]')?.getAttribute('href');
  const mod = link ? modulePattern.exec(link) : null;
  const moduleId = mod ? Number(mod[2]) : null;
  if (id == null && moduleId == null) throw new ParseError('eClass grades item');
  const mark = gradeCell(tr, 'grade');
  const direct = category == null || category.parent == null;
  return {
    key: moduleId != null ? `m${moduleId}` : `g${id}`,
    name: text(th.querySelector('.gradeitemheader') ?? th),
    category: direct ? '' : category.name,
    mark,
    grade: gradeNumber(mark),
    max: rangeMax(gradeCell(tr, 'range')),
    weight: gradeNumber(gradeCell(tr, 'weight')),
    categoryWeight: direct ? 100 : category.courseWeight,
    contribution: gradeNumber(gradeCell(tr, 'contributiontocoursetotal')),
    moduleId,
    moduleType: mod?.[1] ?? null,
  };
}

/**
 * The course total's row, as %. Not its contribution column, which adds up
 * marks as if every category were worth the whole course: 157.25 on a page whose
 * total is 26 of 100. Some courses hide the Percentage column; Grade over Range is the same.
 */
function courseTotalPercent(tr: Element): number | null {
  const shown = gradeNumber(gradeCell(tr, 'percentage'));
  if (shown != null) return shown;
  const grade = gradeNumber(gradeCell(tr, 'grade'));
  const max = rangeMax(gradeCell(tr, 'range'));
  return grade != null && max != null && max > 0 ? (grade / max) * 100 : null;
}

/** "0–100" → 100; a scale has no number. */
function rangeMax(s: string): number | null {
  const m = /[–-]\s*(\d+(?:\.\d+)?)\s*$/.exec(s);
  return m ? Number(m[1]) : null;
}

const gradeCell = (tr: Element, column: string) => text(tr.querySelector(`td.column-${column}`));

/** "100.00 %" → 100, "8.50" → 8.5; "-", a letter or a word → null. */
function gradeNumber(s: string): number | null {
  const m = /^(-?\d+(?:\.\d+)?)\s*%?$/.exec(s.trim());
  return m ? Number(m[1]) : null;
}

/** A category while its rows are read. The course itself is the root, with no parent. Its weight comes from its total row, after its items. */
class GradeCategoryRows {
  readonly name: string;
  readonly parent: GradeCategoryRows | null;
  weight: number | null = null;

  constructor(name: string, parent: GradeCategoryRows | null) {
    this.name = name;
    this.parent = parent;
  }

  /** % of the course total; null when eClass shows "-" here or above. */
  get courseWeight(): number | null {
    if (this.parent == null) return 100;
    const above = this.parent.courseWeight;
    return this.weight == null || above == null ? null : (this.weight * above) / 100;
  }
}

/**
 * A course's assignment or quiz list, `GET /mod/<type>/index.php?id=<course>`,
 * the marks of a course with its grades page closed. Quizzes read
 * `37.00/100.00`; assignments give the mark alone, or `-`. A course with none
 * has no table.
 */
export function parseActivityGrades(html: string, type: 'assign' | 'quiz'): GradeItem[] {
  const doc = parseHtml(html);
  const table = doc.querySelector('#region-main table.generaltable');
  if (table == null) {
    if (doc.body?.id === `page-mod-${type}-index`) return [];
    throw new ParseError(`eClass ${type} list`);
  }
  const headers = Array.from(table.querySelectorAll('thead th')).map((th) => text(th));
  const found = headers.findIndex((h) => h === 'Grade' || h === '성적');
  const gradeColumn = found >= 0 ? found : headers.length - 1;

  const out: GradeItem[] = [];
  for (const tr of Array.from(table.querySelectorAll('tbody tr'))) {
    const cells = Array.from(tr.querySelectorAll('td'));
    const link = tr.querySelector('a[href*="view.php"]');
    if (link == null || gradeColumn < 0 || cells.length <= gradeColumn) continue; // the spacer between weeks
    const id = intParam(link.getAttribute('href'), 'id');
    if (id == null) throw new ParseError(`eClass ${type} list row`);
    const mark = text(cells[gradeColumn]);
    const outOf = /^(\d+(?:\.\d+)?)\s*\/\s*(\d+(?:\.\d+)?)$/.exec(mark);
    out.push({
      key: `m${id}`,
      name: text(link),
      category: type === 'assign' ? 'Assignments' : 'Quizzes',
      mark,
      grade: outOf ? Number(outOf[1]) : gradeNumber(mark),
      max: outOf ? Number(outOf[2]) : null,
      weight: null,
      categoryWeight: null,
      contribution: null,
      moduleId: id,
      moduleType: type,
    });
  }
  return out;
}

/**
 * The maximum in the Feedback box of `GET /mod/assign/view.php?id=`, whose
 * Grade row reads `85.00 / 100.00`. Null before there is a mark, or on a
 * grading scale.
 */
export function parseAssignMax(html: string): number | null {
  const doc = parseHtml(html);
  if (doc.body?.id !== 'page-mod-assign-view') throw new ParseError('eClass assignment');
  for (const row of Array.from(doc.querySelectorAll('.feedback tr'))) {
    const cells = Array.from(row.querySelectorAll('td, th'));
    if (cells.length < 2 || !/^(Grade|성적)$/.test(text(cells[0]))) continue;
    const m = /\/\s*(\d+(?:\.\d+)?)\s*$/.exec(text(cells[1]));
    return m ? Number(m[1]) : null;
  }
  return null;
}

/**
 * True for eClass's login page, which is also what a logged-out request for
 * any other page ends up on.
 */
export function isLoginPage(html: string): boolean {
  const doc = parseHtml(html);
  if (doc.body?.id === 'page-login-index') return true;
  return doc.querySelector('form[action*="/login/index.php"] input[name="password"]') != null;
}

/** The `sesskey` from the page's `M.cfg`, needed for AJAX calls and logout. */
export function extractSesskey(html: string): string | null {
  const cfg = /"sesskey"\s*:\s*"([^"]+)"/.exec(html);
  if (cfg) return cfg[1];
  const value = parseHtml(html).querySelector('input[name="sesskey"]')?.getAttribute('value');
  if (value) return value;
  return /[?&]sesskey=([A-Za-z0-9]+)/.exec(html)?.[1] ?? null;
}

/**
 * The signed-in student's Moodle user id, from the `/user/edit.php?id=<id>`
 * link every logged-in page carries in its user menu. M.cfg does not have it.
 */
export function parseUserId(html: string): number | null {
  for (const a of Array.from(parseHtml(html).querySelectorAll('a[href*="/user/edit.php"]'))) {
    const id = intParam(a.getAttribute('href'), 'id');
    if (id != null) return id;
  }
  const m = /\/user\/edit\.php\?(?:[^"'#]*&(?:amp;)?)?id=(\d+)/.exec(html);
  return m ? Number(m[1]) : null;
}

/** One eClass notification (the bell menu). */
export interface EclassNotification {
  id: number;
  subject: string;
  text: string; // the short message, plain text
  url: string | null; // what it is about, when Moodle gives a link
  time: number;
  read: boolean;
}

/**
 * The reply of `message_popup_get_popup_notifications` through
 * `/lib/ajax/service.php`: `[{"error": false, "data": {"notifications": [...]}}]`.
 * Moodle's fields are `id`, `subject`, `smallmessage` (else `fullmessage`),
 * `contexturl`, `timecreated` (seconds) and `read`. A Moodle error reply
 * (`"error": true`, e.g. an expired sesskey) is a ParseError.
 */
export function parseNotifications(json: string): EclassNotification[] {
  let body: unknown;
  try {
    body = JSON.parse(json);
  } catch {
    throw new ParseError('eClass notifications');
  }
  const first = Array.isArray(body) ? body[0] : body;
  const data = (first as { error?: unknown; data?: { notifications?: unknown } } | null) ?? null;
  if (data == null || data.error || !Array.isArray(data.data?.notifications)) {
    throw new ParseError('eClass notifications');
  }
  return (data.data.notifications as Record<string, unknown>[]).map((n) => ({
    id: Number(n.id),
    subject: plain(String(n.subject ?? '')),
    text: plain(String(n.smallmessage || n.fullmessage || '')),
    url: typeof n.contexturl === 'string' && n.contexturl ? n.contexturl : null,
    time: Number(n.timecreated ?? 0) * 1000,
    read: Boolean(n.read),
  }));
}

// ---------------------------------------------------------------------------

/** Course-level class-period events: "Artificial Intelligence[001]-1교시". */
const classPeriodTitle = /\[\d+\]\s*-\s*\d+\s*교시\s*$/;

const modulePattern = /\/mod\/([a-z0-9_]+)\/view\.php\?(?:[^#]*&)?id=(\d+)/;

/** An event that only says when something opens: "(Quiz opens)", "(Assignment opens)". Nothing is due then. */
const opensEvent = /\((?:[^()]*\s)?opens\)\s*$/i;

/** `view.php?id=<module>` as the VOD list writes it, relative or in full. */
const vodLink = /^(?:view\.php|.*\/mod\/vod\/view\.php)\?/;

/** A time attribute in unix seconds, as ms; null when missing or zero. */
function unixAttr(el: Element | null | undefined, name: string): number | null {
  const v = Number(el?.getAttribute(name)?.trim() || NaN);
  return v > 0 ? v * 1000 : null;
}

/**
 * Text of an HTML snippet (Moodle sends some notification fields as HTML).
 * Wrapped in a whole document: linkedom leaves `body` empty for a fragment.
 */
function plain(s: string): string {
  return s.includes('<') || s.includes('&') ? text(parseHtml(`<html><body>${s}</body></html>`).body) : s.trim();
}

/** The first "2026-10-21 21:14" in s, in local time (eClass shows times in the profile's zone, the same as the device). */
function parseDateTime(s: string): number | null {
  const m = /(\d{4})-(\d{2})-(\d{2})\s+(\d{1,2}):(\d{2})/.exec(s);
  if (!m) return null;
  return new Date(+m[1], +m[2] - 1, +m[3], +m[4], +m[5]).getTime();
}

function toInt(s: string): number | null {
  return /^\d+$/.test(s) ? Number(s) : null;
}

function firstInt(s: string): number | null {
  const m = /\d+/.exec(s);
  return m ? Number(m[0]) : null;
}

/** "18:09" (m:ss) or "01:00:34" (h:mm:ss) in seconds; anything else is zero. */
function parseClock(s: string): number {
  const m = /^(?:(\d+):)?(\d+):(\d{2})$/.exec(s.trim());
  if (!m) return 0;
  return Number(m[1] ?? 0) * 3600 + Number(m[2]) * 60 + Number(m[3]);
}

/** "98.21%" → 98.21; no number (not started, "-") → 0. */
function parsePercent(s: string): number {
  const m = /(\d+(?:\.\d+)?)\s*%/.exec(s) ?? /^(\d+(?:\.\d+)?)$/.exec(s.trim());
  return m ? Number(m[1]) : 0;
}

/**
 * Column index → mark for the ubattendance table, from its header labels
 * (English or Korean), falling back to the usual positions.
 */
function attendanceColumns(headers: string[]): Map<number, AttendanceMark> {
  const found = new Map<number, AttendanceMark>();
  headers.forEach((raw, i) => {
    const h = raw.toLowerCase();
    const mark: AttendanceMark | null =
      h.includes('absen') || h.includes('결석')
        ? 'absent'
        : h.includes('late') || h.includes('지각')
          ? 'late'
          : h.includes('other') || h.includes('기타')
            ? 'other'
            : h.includes('attend') || h.includes('출석')
              ? 'present'
              : null;
    if (mark != null && i >= 2 && ![...found.values()].includes(mark)) found.set(i, mark);
  });
  if (found.size === 4) return found;
  return new Map<number, AttendanceMark>([
    [2, 'present'],
    [3, 'absent'],
    [4, 'late'],
    [5, 'other'],
  ]);
}

interface Row {
  cells: Element[];
  /** A single cell spanning several columns, e.g. "No data". */
  isMessage: boolean;
}

const span = (cell: Element, name: string) => {
  const n = Number.parseInt(cell.getAttribute(name) ?? '', 10);
  return Number.isNaN(n) ? 1 : n;
};

/**
 * The table's body rows with `rowspan` cells copied down into the rows they
 * cover, so every row has the same columns. Header rows (all `th`) are skipped.
 */
function expandRows(table: Element): Row[] {
  const children = Array.from(table.children);
  const bodies = children.filter((c) => c.localName === 'tbody');
  const rows = (bodies.length === 0 ? [table] : bodies).flatMap((b) =>
    Array.from(b.children).filter((c) => c.localName === 'tr'),
  );

  const pending = new Map<number, { cell: Element; left: number }>();
  const out: Row[] = [];
  for (const tr of rows) {
    const physical = Array.from(tr.children).filter((c) => c.localName === 'td' || c.localName === 'th');
    if (physical.length === 0 || physical.every((c) => c.localName === 'th')) continue;

    const cells: Element[] = [];
    let i = 0;
    let col = 0;
    while (i < physical.length || [...pending.keys()].some((k) => k >= col)) {
      const carried = pending.get(col);
      if (carried) {
        cells.push(carried.cell);
        if (carried.left <= 1) pending.delete(col);
        else pending.set(col, { cell: carried.cell, left: carried.left - 1 });
        col++;
        continue;
      }
      if (i >= physical.length) {
        col++;
        continue;
      }
      const cell = physical[i++];
      const colspan = span(cell, 'colspan');
      const rowspan = span(cell, 'rowspan');
      for (let s = 0; s < (colspan < 1 ? 1 : colspan); s++) {
        cells.push(cell);
        if (rowspan > 1) pending.set(col, { cell, left: rowspan - 1 });
        col++;
      }
    }

    out.push({ cells, isMessage: physical.length === 1 && span(physical[0], 'colspan') > 1 });
  }
  return out;
}
