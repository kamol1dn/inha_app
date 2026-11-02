// Pure parsing of the two public EduPage timetable replies. No I/O, so it is
// tested against saved fixtures. A port of lib/services/edupage/timetable_parser.dart,
// itself a port of `scripts/pull_timetable.py` from the study repo; keep them in
// step. See docs/ENDPOINTS.md for the requests.

import { ParseError } from '../../core/errors.ts';
import type { Lesson } from '../../core/models.ts';

type Row = Record<string, unknown>;

/** `r.dbiAccessorRes.tables` of a `regularttGetData` reply, as table id ("cards", "lessons", ...) -> its `data_rows`. */
export type EdupageTables = Record<string, Row[]>;

/** The class group asked for is not in this timetable (renamed, or a new year). */
export class UnknownClassGroup extends Error {
  readonly group: string;
  /** Every class group the timetable does have, sorted. */
  readonly available: string[];
  constructor(group: string, available: string[]) {
    super(`Class group "${group}" is not on the EduPage timetable`);
    this.name = 'UnknownClassGroup';
    this.group = group;
    this.available = available;
  }
}

/** EduPage only has names for Monday..Friday; cards flagged for a later day are dropped, as in the Python script. */
const weekdays = 5;

/**
 * Picks the `tt_num` to load from a `getTTViewerData` reply (the whole body
 * `{"r": ...}`, or just `r`, or its JSON text).
 *
 * EduPage fills in `default_num` only when the request named the right school
 * year. When it is blank or names a hidden timetable, take the newest visible
 * one: highest `year`, then highest numeric `tt_num`; the first wins a tie.
 */
export function chooseTtNum(ttViewerJson: unknown): string {
  const what = 'EduPage timetable list';
  const regular = asMap(unwrap(ttViewerJson, what)['regular']);
  if (regular == null) throw new ParseError(what);

  const available = rows(regular['timetables']).filter((t) => !truthy(t['hidden']));
  if (available.length === 0) throw new ParseError(`${what} (no visible timetables)`);

  const num = pyStr(regular['default_num']);
  if (available.some((t) => str(t['tt_num']) === num)) return num;

  let newest: Row | null = null;
  let best: [number, number] = [-1, -1];
  for (const t of available) {
    const ttNum = str(t['tt_num']);
    const key: [number, number] = [toInt(t['year']) ?? 0, digits.test(ttNum) ? Number(ttNum) : 0];
    if (newest == null || key[0] > best[0] || (key[0] === best[0] && key[1] > best[1])) {
      newest = t;
      best = key;
    }
  }
  return str(newest!['tt_num']);
}

/** The tables of a `regularttGetData` reply (the whole body, just `r`, or its JSON text). */
export function parseTables(regularttJson: unknown): EdupageTables {
  const what = 'EduPage timetable data';
  const res = asMap(unwrap(regularttJson, what)['dbiAccessorRes']);
  const tables = rows(res?.['tables']);
  if (tables.length === 0) throw new ParseError(`${what} (no tables)`);
  const out: EdupageTables = {};
  for (const t of tables) out[str(t['id'])] = rows(t['data_rows']);
  return out;
}

/** Every class group name in the timetable, sorted, e.g. "AI25-1" .. "SBL(L)26-6". */
export function classGroupsIn(tables: EdupageTables): string[] {
  const names = new Set<string>();
  for (const c of table(tables, 'classes')) if (str(c['name'])) names.add(str(c['name']));
  return [...names].sort(compareCodeUnits);
}

/** parseTables then lessonsFor. */
export function parseLessons(regularttJson: unknown, classGroup: string, excludeSubjects: Iterable<string> = []): Lesson[] {
  return lessonsFor(parseTables(regularttJson), classGroup, excludeSubjects);
}

/**
 * One Lesson per scheduled block of classGroup, sorted by weekday, then start
 * (period order, which is time order).
 *
 * A subject is left out when its full name contains an entry of
 * excludeSubjects, or its short code equals one ("BDA"); both ignore case,
 * and blank entries are ignored.
 *
 * Throws UnknownClassGroup if classGroup is not in the timetable.
 */
export function lessonsFor(tables: EdupageTables, classGroup: string, excludeSubjects: Iterable<string> = []): Lesson[] {
  const subjects = byId(table(tables, 'subjects'));
  const teachers = byId(table(tables, 'teachers'));
  const rooms = byId(table(tables, 'classrooms'));
  const lessons = byId(table(tables, 'lessons'));
  const periods = new Map(table(tables, 'periods').map((p) => [str(p['period']), p] as const));
  const classes = table(tables, 'classes');
  const cards = table(tables, 'cards');

  const klass = classes.find((c) => str(c['name']) === classGroup);
  if (klass == null) throw new UnknownClassGroup(classGroup, classGroupsIn(tables));
  const classId = str(klass['id']);

  const mine = new Set<string>();
  for (const [id, l] of lessons) if (list(l['classids']).map(str).includes(classId)) mine.add(id);

  const exclude = [...excludeSubjects].map((x) => x.trim().toLowerCase()).filter((x) => x !== '');

  const out: { dayIndex: number; periodStart: number; order: number; lesson: Lesson }[] = [];
  for (const card of cards) {
    const lessonId = str(card['lessonid']);
    const lesson = lessons.get(lessonId);
    if (lesson == null || !mine.has(lessonId)) continue;

    // Unplaced cards carry an empty period/days: EduPage keeps one per lesson
    // for slots the scheduler has not assigned. Skip them.
    const periodRaw = pyStr(card['period']).trim();
    const days = pyStr(card['days']);
    if (!digits.test(periodRaw) || !days.includes('1')) continue;

    // A lesson spans `durationperiods` consecutive 30-minute periods.
    const startNo = Number(periodRaw);
    let span = truthy(lesson['durationperiods']) ? (toInt(lesson['durationperiods']) ?? 1) : 1;
    if (span < 1) span = 1;
    const endNo = startNo + span - 1;
    const start = periods.get(`${startNo}`);
    const end = periods.get(`${endNo}`);
    if (start == null || end == null) continue;

    const subject = subjects.get(str(lesson['subjectid'])) ?? {};
    if (excluded(subject, exclude)) continue;

    const on = (weekday: number): Lesson => ({
      weekday,
      start: hhmm(str(start['starttime'])),
      end: hhmm(str(end['endtime'])),
      subject: 'name' in subject ? str(subject['name']) : '?',
      room: list(card['classroomids']).map((r) => short(rooms, str(r))).join(', '),
      teacher: list(lesson['teacherids']).map((t) => short(teachers, str(t))).join(', '),
      kind: '',
    });

    // `days` is a bitmask string, one char per weekday from Monday: "00100".
    // A card flagged for several days is one block on each.
    for (let idx = 0; idx < days.length && idx < weekdays; idx++) {
      if (days[idx] !== '1') continue;
      out.push({ dayIndex: idx, periodStart: startNo, order: out.length, lesson: on(1 + idx) });
    }
  }

  out.sort((a, b) => a.dayIndex - b.dayIndex || a.periodStart - b.periodStart || a.order - b.order);

  // Two cards that come out identical in every field (same slot, room and
  // teacher) are one block on screen.
  const seen = new Set<string>();
  return out.map((r) => r.lesson).filter((l) => {
    const key = JSON.stringify(l);
    if (seen.has(key)) return false;
    seen.add(key);
    return true;
  });
}

const digits = /^\d+$/;

/** Dart's String.compareTo: by UTF-16 code units, not locale. */
const compareCodeUnits = (a: string, b: string) => (a < b ? -1 : a > b ? 1 : 0);

function excluded(subject: Row, exclude: string[]): boolean {
  if (exclude.length === 0) return false;
  const name = str(subject['name']).toLowerCase();
  const shortName = str(subject['short']).toLowerCase();
  return exclude.some((x) => name.includes(x) || shortName === x);
}

/** A room's or teacher's short name, or the raw id if the row has none. */
function short(rowsById: Map<string, Row>, id: string): string {
  const row = rowsById.get(id);
  return row != null && 'short' in row ? str(row['short']) : id;
}

/** "8:00" -> "08:00"; anything that is not H:MM / HH:MM is left alone. */
function hhmm(t: string): string {
  const m = /^(\d{1,2}):(\d{2})$/.exec(t.trim());
  return m == null ? t : `${m[1].padStart(2, '0')}:${m[2]}`;
}

function table(tables: EdupageTables, id: string): Row[] {
  const t = tables[id];
  if (t == null) throw new ParseError(`EduPage "${id}" table`);
  return t;
}

function byId(rs: Row[]): Map<string, Row> {
  return new Map(rs.map((r) => [str(r['id']), r] as const));
}

/** An RPC reply's `r` payload. Accepts the raw JSON text, the decoded body, or the payload itself. */
function unwrap(json: unknown, what: string): Row {
  let j = json;
  if (typeof j === 'string') {
    try {
      j = JSON.parse(j);
    } catch {
      throw new ParseError(what);
    }
  }
  const m = asMap(j);
  if (m != null && 'r' in m) j = m['r'];
  const out = asMap(j);
  if (out == null) throw new ParseError(what);
  return out;
}

function asMap(v: unknown): Row | null {
  return v != null && typeof v === 'object' && !Array.isArray(v) ? (v as Row) : null;
}

function list(v: unknown): unknown[] {
  return Array.isArray(v) ? v : [];
}

function rows(v: unknown): Row[] {
  return list(v).map(asMap).filter((r): r is Row => r != null);
}

function str(v: unknown): string {
  return v == null ? '' : `${v}`;
}

/** Python truthiness, which the reference script leans on (`x or default`). */
function truthy(v: unknown): boolean {
  if (v == null || v === false || v === 0 || v === '') return false;
  if (Array.isArray(v)) return v.length > 0;
  if (typeof v === 'object') return Object.keys(v).length > 0;
  return true;
}

/** Python's `str(x or "")`. */
function pyStr(v: unknown): string {
  return truthy(v) ? `${v}` : '';
}

function toInt(v: unknown): number | null {
  if (typeof v === 'number') return Number.isInteger(v) ? v : null;
  if (typeof v === 'string' && /^\s*[+-]?\d+\s*$/.test(v)) return Number(v.trim());
  return null;
}
