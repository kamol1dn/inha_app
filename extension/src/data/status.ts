// When items need attention, and absences against the limits the student set.
// Ports of lib/data/urgency.dart and lib/data/absence.dart (DESIGN.md 7).

import { courseFromTitle, type AttendanceEntry, type Course, type CourseAttendance, type Deadline, type GradeRecord, type GradeReport, type Lesson, type VodProgress } from '../core/models.ts';
import { dayKey, HOUR, MIN } from './format.ts';

export type Status = 'ok' | 'warning' | 'danger' | 'info';

/** Deadlines and VOD windows show on Today within 72 h: a missed window is a recorded absence. */
export const todayWindow = 72 * HOUR;

const norm = (s: string) => s.toLowerCase().replace(/\s+/g, ' ').trim();

/** Kinds that are something due. Class periods are only shown on request. */
export const isDue = (d: Deadline) => d.kind !== 'classPeriod';

/**
 * The course's attendance record for a name from another source. Calendar
 * course names can be cut short, so after an exact match it tries a prefix
 * either way: the longest course name the given one starts with, or the one
 * course that starts with it. Several courses starting with it can't be told
 * apart, so that is no match.
 */
export function courseFor(courseName: string, all: CourseAttendance[]): CourseAttendance | null {
  const n = norm(courseName);
  if (!n) return null;
  let shorter: CourseAttendance | null = null;
  const longer: CourseAttendance[] = [];
  for (const c of all) {
    const m = norm(c.course.name);
    if (m === n) return c;
    if (!m) continue;
    if (m.startsWith(n)) longer.push(c);
    if (n.startsWith(m) && m.length > (shorter ? norm(shorter.course.name).length : 0)) shorter = c;
  }
  if (!longer.length) return shorter;
  return !shorter && longer.length === 1 ? longer[0] : null;
}

/** An event's course: by the id its link carries, else by name. */
export function courseOf(d: Deadline, all: CourseAttendance[]): CourseAttendance | null {
  const byId = d.courseId == null ? null : all.find((c) => c.course.id === d.courseId);
  return byId ?? courseFor(d.courseName, all);
}

/** The progress row for a VOD-window event, or null if unknown: by course module where known, else by title. */
export function vodFor(d: Deadline, all: CourseAttendance[]): VodProgress | null {
  if (d.kind !== 'vod') return null;
  const vods = courseOf(d, all)?.vods ?? [];
  const t = norm(d.title);
  return (d.moduleId == null ? null : vods.find((v) => v.moduleId === d.moduleId)) ?? vods.find((v) => norm(v.title) === t) ?? null;
}

/** Minute-precision UTC stamp, so keys don't depend on the zone. */
const stamp = (t: number) => new Date(Math.floor(t / MIN) * MIN).toISOString().slice(0, 16).replace(/[-:]/g, '') + 'Z';

/** The part of a deadline's reminder keys that names the item: every key is `<stem>|<lead>`. Also what Settings.dismissed holds. */
export function reminderStem(d: Deadline): string {
  const item = `${norm(courseFromTitle(0, d.courseName.replace(/\s+/g, ' ').trim()).name)}|${norm(d.title)}|${stamp(d.end)}`;
  return d.kind === 'vod' ? `vod:${item}` : `due:${d.kind}:${item}`;
}

/** The student marked this as done themselves, as opposed to eClass saying so. Show it as "Marked done by you". */
export const markedDone = (d: Deadline, dismissed: readonly string[] = []) => dismissed.length > 0 && dismissed.includes(reminderStem(d));

/** Settings.dismissed with an item marked or unmarked. Oldest marks go first; they are long past by then. */
export function withDismissed(dismissed: readonly string[], d: Deadline, done: boolean): string[] {
  const stem = reminderStem(d);
  const others = dismissed.filter((s) => s !== stem);
  return (done ? [...others, stem] : others).slice(-200);
}

/** Nothing left to do: handed in, attempted, (a VOD) fully watched, or marked done by the student. */
export const isDone = (d: Deadline, att: CourseAttendance[], dismissed: readonly string[] = []) =>
  d.done || (vodFor(d, att)?.percent ?? 0) >= 100 || markedDone(d, dismissed);

/**
 * Sessions held so far: those before now's day, and today's once marked. eClass
 * lists the whole semester, the weeks still to come as unmarked rows, and an
 * unmarked class today may not have happened yet.
 */
export function heldClasses(c: CourseAttendance, now: number): AttendanceEntry[] {
  const today = dayKey(now);
  return c.classes.filter((e) => e.date < today || (e.date === today && e.mark !== 'unmarked'));
}

/** null = plain, otherwise the status the guide assigns. */
export function deadlineStatus(d: Deadline, now: number): Status | null {
  const left = d.end - now;
  if (d.kind === 'vod') {
    if (left < 12 * HOUR) return 'danger';
    if (left < 72 * HOUR) return 'warning';
    return null;
  }
  if (left < 3 * HOUR) return 'danger';
  if (left < 24 * HOUR) return 'warning';
  return null;
}

/** Unwatched VOD windows and other deadlines due within 72 h (overdue ones kept for 24 h). Soonest first. */
export function needsAttention(all: Deadline[], att: CourseAttendance[], now: number, dismissed: readonly string[] = []): Deadline[] {
  return all
    .filter((d) => {
      if (!isDue(d) || markedDone(d, dismissed)) return false;
      const left = d.end - now;
      if (d.kind === 'vod') return left >= 0 && left <= todayWindow && (vodFor(d, att)?.percent ?? 0) < 100;
      return !d.done && left > -24 * HOUR && left <= todayWindow;
    })
    .sort((a, b) => a.end - b.end);
}

/** A course's own due items, not more than a day overdue, soonest first. */
export function courseDeadlines(course: Course, all: Deadline[], att: CourseAttendance[], now: number): Deadline[] {
  return all
    .filter((d) => isDue(d) && d.end > now - 24 * HOUR && courseOf(d, att)?.course.id === course.id)
    .sort((a, b) => a.end - b.end);
}

/** The course's INS result for its latest term, matched on the code, else the name. */
export function gradeFor(course: Course, report: GradeReport | undefined): GradeRecord | null {
  const records = report?.records ?? [];
  const byCode = course.code ? records.filter((r) => r.code === course.code) : [];
  const matches = byCode.length ? byCode : records.filter((r) => norm(r.name) === norm(course.name));
  if (!matches.length) return null;
  return matches.reduce((a, b) => (a.termKey >= b.termKey ? a : b));
}

/** Timetable lessons of an eClass course, matched on name prefix either way. */
export function lessonsOf(course: Course, lessons: Lesson[]): Lesson[] {
  const name = norm(course.name);
  return lessons.filter((l) => {
    const s = norm(l.subject);
    return s && (s === name || s.startsWith(name) || name.startsWith(s));
  });
}

/** A course's absences against the limit the student set. No source publishes limits: never guess one. */
export class AbsenceState {
  readonly used: number;
  readonly limit: number | null;

  constructor(used: number, limit: number | null) {
    this.used = used;
    this.limit = limit;
  }

  static of(c: CourseAttendance, limits: Record<string, number>): AbsenceState {
    return new AbsenceState(c.classes.filter((e) => e.mark === 'absent').length, limits[c.course.id] ?? null);
  }

  get left(): number | null {
    return this.limit == null ? null : this.limit - this.used;
  }

  /** Warning once the absences left are at most max(1, 25% of the allowance); danger at 0 left or over. */
  get status(): Status | null {
    const l = this.left;
    if (l == null) return null;
    if (l <= 0) return 'danger';
    if (l <= Math.max(1, this.limit! * 0.25)) return 'warning';
    return null;
  }

  get trouble(): boolean {
    return this.status != null;
  }

  /** "1 left", "At limit", "Over limit"; null when not in trouble. */
  get tag(): string | null {
    const l = this.left;
    if (l == null || !this.status) return null;
    if (l < 0) return 'Over limit';
    if (l === 0) return 'At limit';
    return `${l} left`;
  }

  /** "3 of 4 absences used", "5 absences · limit 4", or the raw count. */
  get line(): string {
    const noun = this.used === 1 ? 'absence' : 'absences';
    if (this.limit == null) return `${this.used} ${noun} · limit not set`;
    if (this.used > this.limit) return `${this.used} ${noun} · limit ${this.limit}`;
    return `${this.used} of ${this.limit} absences used`;
  }
}

/** Courses for "am I in trouble": danger, then warning, then timetable order. */
export function troubleOrder(courses: CourseAttendance[], limits: Record<string, number>, lessons: Lesson[]): CourseAttendance[] {
  const rank = (c: CourseAttendance) => ({ danger: 0, warning: 1 } as Record<string, number>)[AbsenceState.of(c, limits).status ?? ''] ?? 2;
  const firstClass = (c: CourseAttendance) => {
    let best = Infinity;
    for (const l of lessonsOf(c.course, lessons)) {
      const [h, m] = l.start.split(':').map(Number);
      best = Math.min(best, l.weekday * 1440 + (h || 0) * 60 + (m || 0));
    }
    return best;
  };
  return [...courses].sort(
    (a, b) => rank(a) - rank(b) || firstClass(a) - firstClass(b) || a.course.name.localeCompare(b.course.name),
  );
}
