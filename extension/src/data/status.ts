// When items need attention, and absences against the limits the student set.
// Ports of lib/data/urgency.dart and lib/data/absence.dart (DESIGN.md 7).

import type { Course, CourseAttendance, Deadline, GradeRecord, GradeReport, Lesson, VodProgress } from '../core/models.ts';
import { HOUR } from './format.ts';

export type Status = 'ok' | 'warning' | 'danger' | 'info';

/** Deadlines and VOD windows show on Today within 72 h: a missed window is a recorded absence. */
export const todayWindow = 72 * HOUR;

const norm = (s: string) => s.toLowerCase().replace(/\s+/g, ' ').trim();

/** Kinds that are something due. Class periods are only shown on request. */
export const isDue = (d: Deadline) => d.kind !== 'classPeriod';

/** Calendar course names can be cut short, so match on prefix either way. */
export function courseFor(courseName: string, all: CourseAttendance[]): CourseAttendance | null {
  const n = norm(courseName);
  if (!n) return null;
  return all.find((c) => {
    const m = norm(c.course.name);
    return m === n || m.startsWith(n) || n.startsWith(m);
  }) ?? null;
}

/** The progress row for a VOD-window event, or null if unknown. */
export function vodFor(d: Deadline, all: CourseAttendance[]): VodProgress | null {
  if (d.kind !== 'vod') return null;
  const t = norm(d.title);
  return courseFor(d.courseName, all)?.vods.find((v) => norm(v.title) === t) ?? null;
}

/** Nothing left to do: handed in, attempted, or (a VOD) fully watched. */
export const isDone = (d: Deadline, att: CourseAttendance[]) => d.done || (vodFor(d, att)?.percent ?? 0) >= 100;

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
export function needsAttention(all: Deadline[], att: CourseAttendance[], now: number): Deadline[] {
  return all
    .filter((d) => {
      if (!isDue(d)) return false;
      const left = d.end - now;
      if (d.kind === 'vod') return left >= 0 && left <= todayWindow && (vodFor(d, att)?.percent ?? 0) < 100;
      return !d.done && left > -24 * HOUR && left <= todayWindow;
    })
    .sort((a, b) => a.end - b.end);
}

/** A course's own due items, not more than a day overdue, soonest first. */
export function courseDeadlines(course: Course, all: Deadline[], att: CourseAttendance[], now: number): Deadline[] {
  return all
    .filter((d) => isDue(d) && d.end > now - 24 * HOUR && courseFor(d.courseName, att)?.course.id === course.id)
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
    if (this.used > this.limit) return `${this.used} absences · limit ${this.limit}`;
    return `${this.used} of ${this.limit} ${noun} used`;
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
