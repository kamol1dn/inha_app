// Exam timetables (docs/EXAMS.md). No IUT service publishes them, so each
// sheet is curated from the university's PDF into ../assets/exams/ and
// bundled. A port of lib/data/exams.dart: reading a sheet, reading a cell, and
// matching sittings to the student's courses.

import type { Course, CourseAttendance, Lesson } from '../core/models.ts';
import { courseFor } from './status.ts';
import { dayKey, DAY, MIN } from './format.ts';
import fallMidterm2026 from '../../../assets/exams/2026-fall-midterm.json' with { type: 'json' };

/** The bundled sheets. A new one (the finals) is one more import here. */
export const examSheets: unknown[] = [fallMidterm2026];

/** How long before its first exam a period shows. It shows until its last exam ends. */
export const examLead = 21 * DAY;

export interface ExamGroup {
  program: string; // empty when the sheet leaves it out ("26-05")
  year: number;
  number: number;
}

/** What a cell says: "(UK) Intro to Data Science (AI 25-01)". */
export interface ExamCell {
  course: string;
  uk: boolean;
  groups: ExamGroup[];
  teacher: string | null;
  school: string | null;
  department: string | null;
  minutes: number | null;
  /** The qualifiers that tell sittings of one course apart, as printed: "Dr.Sarvar · AI 25-01". */
  note: string;
}

export interface Exam {
  slot: string; // "Th-3"
  start: number;
  end: number;
  cell: string; // as printed
  rooms: string[];
  read: ExamCell;
}

/** One exam week. A sitting has the rooms it uses, never a student's own: the room list names every student. */
export interface ExamPeriod {
  id: string;
  kind: string; // "midterm", "final"
  term: string;
  source: string;
  exams: Exam[]; // in time order
}

export const periodName = (p: ExamPeriod) => (p.kind === 'final' ? 'Final' : 'Midterm');
export const periodFirst = (p: ExamPeriod) => p.exams[0].start;
export const periodLast = (p: ExamPeriod) => Math.max(...p.exams.map((e) => e.end));
export const examKey = (p: ExamPeriod, e: Exam) => `${p.id}|${e.slot}|${e.cell}`;

const groupPattern = /^([A-Z]+(?:\([A-Z]\))?)\s*-?\s*(\d{2})-(\d+)$/;

/** EduPage's group name, e.g. "ICE23-1"; null if it has another shape. */
export function groupOfClass(name: string): ExamGroup | null {
  const m = groupPattern.exec(name.trim().toUpperCase());
  return m ? { program: m[1], year: Number(m[2]), number: Number(m[3]) } : null;
}

const includes = (a: ExamGroup, g: ExamGroup) => (!a.program || a.program === g.program) && a.year === g.year && a.number === g.number;

const schools = new Set(['SBL', 'SOCIE']);
const yearNumber = /(\d{2})\s*-\s*(\d{1,2})/;

/** "IT 26-1/26-3" -> IT26-1, IT26-3; "26-01/03, 26-02/04" -> 26-1, 26-3, 26-2, 26-4. */
export function parseGroups(q: string): ExamGroup[] {
  const out: ExamGroup[] = [];
  let programs = [''];
  let year: number | null = null;
  for (const chunk of q.split(/[/,]/)) {
    const named = chunk.match(/[A-Z]{2,}/g);
    if (named) programs = named;
    const yn = yearNumber.exec(chunk);
    const lone = /^\s*(\d{1,2})\s*$/.exec(chunk);
    if (yn) {
      year = Number(yn[1]);
      for (const p of programs) out.push({ program: p, year, number: Number(yn[2]) });
    } else if (lone && year != null) {
      for (const p of programs) out.push({ program: p, year, number: Number(lone[1]) });
    }
  }
  return out;
}

export function parseCell(cell: string): ExamCell {
  let s = cell.trim();
  let uk = false;
  const mark = /^(\(UK\)|UK\s)\s*/.exec(s);
  if (mark) {
    uk = true;
    s = s.slice(mark[0].length);
  }
  const qualifiers: string[] = [];
  for (let m = /\s*\(([^()]*)\)\s*$/.exec(s); m && m.index > 0; m = /\s*\(([^()]*)\)\s*$/.exec(s)) {
    qualifiers.unshift(m[1].trim());
    s = s.slice(0, m.index);
  }
  const out: ExamCell = { course: '', uk, groups: [], teacher: null, school: null, department: null, minutes: null, note: '' };
  const notes: string[] = [];
  for (const q of qualifiers) {
    const mins = /^(\d{2,3})\s*(min)?$/i.exec(q);
    if (mins) {
      out.minutes = Number(mins[1]);
      continue;
    }
    notes.push(q);
    const dr = /^Dr\.?\s*(.+)$/.exec(q);
    if (dr) out.teacher = dr[1].trim();
    else if (schools.has(q.toUpperCase())) out.school = q.toUpperCase();
    else if (/^[A-Z]{2,5}$/.test(q)) out.department = q;
    else if (yearNumber.test(q)) out.groups.push(...parseGroups(q));
  }
  out.course = s.replace(/[\s\-–]+$/, '').trim();
  out.note = notes.join(' · ');
  return out;
}

interface SheetExam {
  slot: string;
  date: string;
  start: string;
  end: string;
  cell: string;
  rooms: string[];
}

export function readSheet(j: unknown): ExamPeriod {
  const sheet = j as { format: number; id: string; kind: string; term: string; source: string; exams: SheetExam[] };
  if (sheet.format !== 1) throw new Error(`Unknown exam sheet format ${sheet.format}`);
  const exams = sheet.exams.map((e, i) => {
    const [y, mo, d] = e.date.split('-').map(Number);
    const at = (hhmm: string) => {
      const [h, m] = hhmm.split(':').map(Number);
      return new Date(y, mo - 1, d, h, m).getTime();
    };
    const read = parseCell(e.cell);
    const start = at(e.start);
    return {
      i,
      exam: { slot: e.slot, start, end: read.minutes == null ? at(e.end) : start + read.minutes * MIN, cell: e.cell, rooms: e.rooms, read },
    };
  });
  // By start, keeping the sheet's order (its columns) within a slot.
  exams.sort((a, b) => a.exam.start - b.exam.start || a.i - b.i);
  return { id: sheet.id, kind: sheet.kind, term: sheet.term, source: sheet.source, exams: exams.map((x) => x.exam) };
}

/** Every bundled sheet that reads. */
export const examPeriods: ExamPeriod[] = examSheets.flatMap((s) => {
  try {
    return [readSheet(s)];
  } catch {
    return [];
  }
});

/** The period on show at `now`, the earliest first; null outside every window. */
export function currentPeriod(now: number, all = examPeriods): ExamPeriod | null {
  return (
    all
      .filter((p) => p.exams.length && now > periodFirst(p) - examLead && now < periodLast(p))
      .sort((a, b) => periodFirst(a) - periodFirst(b))[0] ?? null
  );
}

/** Every exam week's days, first exam's to last's: no classes then, whatever the timetable says. */
export function classFreeDays(all = examPeriods): Set<string> {
  const out = new Set<string>();
  for (const p of all) {
    if (!p.exams.length) continue;
    const last = dayKey(periodLast(p));
    const d = new Date(periodFirst(p));
    for (let day = new Date(d.getFullYear(), d.getMonth(), d.getDate()); dayKey(day) <= last; day.setDate(day.getDate() + 1)) {
      out.add(dayKey(day));
    }
  }
  return out;
}

/** One of the student's courses, from the timetable and eClass together. */
export interface StudentCourse {
  name: string;
  teachers: Set<string>;
  eclass: Course | null;
}

export function studentCourses(lessons: Lesson[], attendance: CourseAttendance[]): StudentCourse[] {
  const out: StudentCourse[] = [];
  const joined = new Set<number>();
  for (const subject of new Set(lessons.map((l) => l.subject))) {
    const course = courseFor(subject, attendance)?.course ?? null;
    if (course) joined.add(course.id);
    const teachers = new Set(lessons.filter((l) => l.subject === subject && l.teacher).map((l) => l.teacher));
    if (course?.professor) teachers.add(course.professor);
    out.push({ name: subject, teachers, eclass: course });
  }
  for (const c of attendance) {
    if (joined.has(c.course.id)) continue;
    out.push({ name: c.course.name, teachers: new Set(c.course.professor ? [c.course.professor] : []), eclass: c.course });
  }
  return out;
}

export interface MyExam {
  course: StudentCourse;
  exam: Exam;
  /** Sittings of this course nothing the extension knows tells apart. Usually 1. */
  sittings: number;
  room: string | null;
}

export interface ExamMatch {
  period: ExamPeriod;
  exams: MyExam[];
  unlisted: StudentCourse[];
}

const short: Record<string, string> = { intro: 'introduction', math: 'mathematics', tech: 'technical', ii: '2', iii: '3', iv: '4' };
const minor = new Set(['and', 'of', 'to', 'the', 'in', 'for', 'with', 'on']);

/** A course name for comparing: lower case, "&" as "and", no punctuation, short words spelled out, plurals dropped. */
export function examName(name: string): string {
  return name
    .toLowerCase()
    .replace(/&/g, ' and ')
    .replace(/[^a-z0-9 ]/g, ' ')
    .split(' ')
    .filter(Boolean)
    .map((w) => short[w] ?? w)
    .map((w) => (w.length > 3 && w.endsWith('ies') ? `${w.slice(0, -3)}y` : w.length > 3 && w.endsWith('s') && !w.endsWith('ss') ? w.slice(0, -1) : w))
    .join(' ');
}

function sameCourse(sheet: string, mine: string): boolean {
  if (examName(sheet) === examName(mine)) return true;
  if (!/^[A-Z]{3,6}$/.test(sheet)) return false;
  const initials = mine.split(/[\s-]+/).filter((w) => w && !minor.has(w.toLowerCase()));
  return initials.map((w) => w[0].toUpperCase()).join('') === sheet;
}

function nearCourse(sheet: string, mine: string): boolean {
  const a = examName(sheet), b = examName(mine);
  const shorter = a.length < b.length ? a : b;
  return shorter.length >= 5 && (a.startsWith(b) || b.startsWith(a));
}

const schoolOf = (program: string) =>
  ({ CSE: 'SOCIE', ICE: 'SOCIE', CIE: 'SOCIE', 'SBL(B)': 'SBL', 'SBL(L)': 'SBL' })[program] ?? null;

function fits(cell: ExamCell, group: ExamGroup | null, teachers: Set<string>): boolean | null {
  const votes: boolean[] = [];
  if (cell.groups.length && group) votes.push(cell.groups.some((g) => includes(g, group)));
  if (cell.school && group) {
    const school = schoolOf(group.program);
    if (school) votes.push(school === cell.school);
  }
  if (cell.department && group) votes.push(cell.department === group.program);
  if (cell.teacher && teachers.size) {
    const name = cell.teacher.toLowerCase();
    votes.push([...teachers].some((t) => t.toLowerCase().includes(name)));
  }
  return votes.length ? votes.every(Boolean) : null;
}

/**
 * Matches the sheet to the student's courses: an exact name first, else a
 * prefix either way that points at one course. UK sittings go only to UK
 * groups, and qualifiers narrow a course with several sittings to the one that
 * fits classGroup and the teachers. Sittings nothing tells apart are all kept.
 */
export function matchExams(period: ExamPeriod, courses: StudentCourse[], classGroup = '', rooms: Record<string, string> = {}): ExamMatch {
  const group = groupOfClass(classGroup);
  const ukPrograms = new Set(period.exams.filter((e) => e.read.uk).flatMap((e) => e.read.groups.map((g) => g.program).filter(Boolean)));
  const ukStudent = group != null && ukPrograms.has(group.program);
  const forAudience = (found: Exam[]) => {
    if (!ukStudent) return found.filter((e) => !e.read.uk);
    return found.some((e) => e.read.uk) ? found.filter((e) => e.read.uk) : found;
  };

  const mine = new Map<Exam, MyExam>();
  const unlisted: StudentCourse[] = [];
  for (const c of courses) {
    let found = forAudience(period.exams.filter((e) => sameCourse(e.read.course, c.name)));
    if (!found.length) {
      const near = forAudience(period.exams.filter((e) => nearCourse(e.read.course, c.name)));
      if (new Set(near.map((e) => examName(e.read.course))).size === 1) found = near;
    }
    const fitting = found.filter((e) => fits(e.read, group, c.teachers) !== false);
    const chosen = fitting.length ? fitting : found;
    if (!chosen.length) {
      unlisted.push(c);
      continue;
    }
    for (const e of chosen) {
      // A timetable subject and an eClass course the names didn't join meet here, at one sitting.
      const before = mine.get(e);
      const course =
        !before || before.course.eclass || !c.eclass
          ? (before?.course ?? c)
          : { name: before.course.name, teachers: new Set([...before.course.teachers, ...c.teachers]), eclass: c.eclass };
      mine.set(e, { course, exam: e, sittings: chosen.length, room: rooms[examKey(period, e)] ?? null });
    }
  }
  const order = new Map(period.exams.map((e, i) => [e, i]));
  return { period, exams: [...mine.values()].sort((a, b) => order.get(a.exam)! - order.get(b.exam)!), unlisted };
}

/** "B209", "B209 or B210", "B304(A–C), B305 or B201". */
export function roomChoice(rooms: string[]): string {
  const parts: string[] = [];
  for (let i = 0; i < rooms.length; ) {
    const m = /^(.+)\(([A-Z])\)$/.exec(rooms[i]);
    let j = i + 1;
    if (!m) {
      parts.push(rooms[i]);
    } else {
      const letters = [m[2]];
      for (; j < rooms.length; j++) {
        const n = /^(.+)\(([A-Z])\)$/.exec(rooms[j]);
        if (!n || n[1] !== m[1]) break;
        letters.push(n[2]);
      }
      const run = letters.length >= 3 && letters.every((l, k) => k === 0 || l.charCodeAt(0) - letters[k - 1].charCodeAt(0) === 1);
      parts.push(...(run ? [`${m[1]}(${letters[0]}–${letters[letters.length - 1]})`] : letters.map((l) => `${m[1]}(${l})`)));
    }
    i = j;
  }
  if (parts.length < 2) return parts.join('');
  return `${parts.slice(0, -1).join(', ')} or ${parts[parts.length - 1]}`;
}
