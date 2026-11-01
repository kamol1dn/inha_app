// What the views compute from the snapshot, with no DOM: a day's classes or
// exams, the next class, Today's lines, Deadlines' sections, the tally's strokes.

import { describeError, type ErrorInfo } from '../core/errors.ts';
import { isGraded, plainNumber, type CourseAttendance, type Course, type Deadline, type DeadlineKind, type GradeRecord, type GradeReport, type Lesson, type Service, type VodProgress } from '../core/models.ts';
import { defaultDeadlineKinds, type Settings, type Snapshot } from '../core/store.ts';
import { classFreeDays, currentPeriod, matchExams, studentCourses, type ExamMatch, type MyExam } from '../data/exams.ts';
import { atTime, classWhen, dayDate, dayDateTime, dayKey, duration, HOUR, isoWeekday, midnight, pastWhen, relative, rowTitle, updatedAt } from '../data/format.ts';
import { AbsenceState, courseFor, courseOf, deadlineStatus, isDone, isDue, markedDone, troubleOrder, vodFor, type Status } from '../data/status.ts';
import { eclassBase } from '../services/eclass/links.ts';

const classFree = classFreeDays();

/** The student's exams in the period on show at `now`, or null outside every period. */
export function examMatch(snap: Snapshot, now: number): ExamMatch | null {
  const period = currentPeriod(now);
  if (!period) return null;
  const courses = studentCourses(snap.cache.lessons?.value ?? [], snap.cache.attendance?.value ?? []);
  return matchExams(period, courses, snap.settings.classGroup, snap.settings.examRooms);
}

export interface DayClass {
  start: number;
  end: number;
  lesson: Lesson;
}

/** The timetable's classes on `day`, in time order. None in an exam week, whatever the timetable says. */
export function classesOn(day: Date, lessons: Lesson[]): DayClass[] {
  if (classFree.has(dayKey(day))) return [];
  const wd = isoWeekday(day);
  return lessons
    .filter((l) => l.weekday === wd)
    .flatMap((lesson) => {
      const start = atTime(day, lesson.start), end = atTime(day, lesson.end);
      return start && end ? [{ start: start.getTime(), end: end.getTime(), lesson }] : [];
    })
    .sort((a, b) => a.start - b.start);
}

export const isClassFree = (day: Date) => classFree.has(dayKey(day));

/** The student's exams on `day`, in time order. */
export const examsOn = (day: Date, match: ExamMatch | null): MyExam[] =>
  (match?.exams ?? []).filter((e) => dayKey(e.exam.start) === dayKey(day)).sort((a, b) => a.exam.start - b.exam.start);

// ---- The next class ----

const dayAfter = (t: number, days: number) => {
  const d = midnight(t);
  return new Date(d.getFullYear(), d.getMonth(), d.getDate() + days);
};

/** The next class `test` accepts: one in progress or still to come at `now`, then the next 7 days. Null when there is none in that week. */
export function nextLesson(lessons: Lesson[], now: number, test: (l: Lesson) => boolean = () => true): DayClass | null {
  for (let i = 0; i <= 7; i++) {
    const found = classesOn(dayAfter(now, i), lessons).find((c) => test(c.lesson) && c.end > now);
    if (found) return found;
  }
  return null;
}

/** Whether a timetable subject is this eClass course (names can be cut short on either side). */
export const isLessonOf = (l: Lesson, course: Course) => courseFor(l.subject, [{ course, classes: [], vods: [] }]) != null;

/** The course's absences, when it takes attendance and they are near or over the limit. */
export function inTrouble(c: CourseAttendance, limits: Record<string, number>): AbsenceState | null {
  if (!c.classes.length) return null;
  const s = AbsenceState.of(c, limits);
  return s.trouble ? s : null;
}

/** "today 14:00", or null: when the course's next class is. */
export function courseNextWhen(c: CourseAttendance, lessons: Lesson[], now: number): { when: string; room: string } | null {
  const next = nextLesson(lessons, now, (l) => isLessonOf(l, c.course));
  return next ? { when: classWhen(next.start, next.lesson.start, now), room: next.lesson.room } : null;
}

/** A course row's second line when not in trouble: "Today 14:00 · B202", "Next Mon 14:30 · A305", led by "Limit not set" while there is none. */
export function courseLine(c: CourseAttendance, limit: number | null, lessons: Lesson[], now: number): string {
  if (!c.classes.length) return 'No class attendance in eClass';
  const next = courseNextWhen(c, lessons, now);
  const when = next ? (next.when.startsWith('to') ? next.when[0].toUpperCase() + next.when.slice(1) : `Next ${next.when}`) : null;
  return [...(limit == null ? ['Limit not set'] : []), ...(when ? [when] : []), ...(next?.room ? [next.room] : [])].join(' · ');
}

/** The status line of a course in trouble: "2 left · next Mon 13:00". */
export function troubleLine(s: AbsenceState, c: CourseAttendance, lessons: Lesson[], now: number): string {
  const next = courseNextWhen(c, lessons, now);
  return next ? `${s.tag} · next ${next.when}` : (s.tag ?? '');
}

/**
 * The classes of the next days on Today's rail: the first class of the next day
 * with classes, and the next class of every course in trouble that has none
 * left today. Each looks up to a week ahead, as the app's does.
 */
export function railLaterClasses(lessons: Lesson[], att: CourseAttendance[], limits: Record<string, number>, now: number): DayClass[] {
  const tomorrow = dayAfter(now, 1).getTime();
  const out = new Map<string, DayClass>();
  const put = (c: DayClass | null) => {
    if (c) out.set(`${c.start}/${c.lesson.subject}`, c);
  };
  put(nextLesson(lessons, tomorrow));
  const today = classesOn(dayAfter(now, 0), lessons).filter((c) => c.end > now);
  for (const c of att) {
    if (!inTrouble(c, limits)) continue;
    if (today.some((t) => isLessonOf(t.lesson, c.course))) continue;
    put(nextLesson(lessons, tomorrow, (l) => isLessonOf(l, c.course)));
  }
  return [...out.values()].sort((a, b) => a.start - b.start);
}

/** "Next: Mon 27 Oct, 09:00 Multimedia Computing, B-305.", for a day with no classes; '' when none is coming up. */
export function nextClassSentence(lessons: Lesson[], day: Date, now: number): string {
  const next = nextLesson(lessons, dayAfter(day.getTime(), 1).getTime());
  if (!next) return '';
  const where = next.lesson.room ? `, ${next.lesson.room}` : '';
  return `Next: ${dayDate(next.start, new Date(now))}, ${next.lesson.start} ${next.lesson.subject}${where}.`;
}

// ---- Today's lines ----

/**
 * The answer to "am I in attendance trouble": the courses in trouble, then one
 * line for those within a limit and one for those with none. Only courses that
 * take attendance count, and a limit is never guessed.
 */
export function attendanceSummary(att: CourseAttendance[], limits: Record<string, number>, lessons: Lesson[]) {
  const tracked = att.filter((c) => c.classes.length);
  const trouble = troubleOrder(tracked, limits, lessons).filter((c) => inTrouble(c, limits));
  const limited = tracked.filter((c) => limits[c.course.id] != null).length;
  const used = (c: CourseAttendance) => c.classes.filter((e) => e.mark === 'absent').length;
  const unset = tracked.filter((c) => limits[c.course.id] == null && used(c) > 0).sort((a, b) => used(b) - used(a));
  const fine = limited - trouble.length;
  const are = fine === 1 ? 'course is' : 'courses are';
  const their = fine === 1 ? 'its' : 'their';
  let ok: string | null = null;
  if (fine > 0) {
    if (trouble.length) ok = fine === 1 ? 'The other course is within its limit.' : `The other ${fine} courses are within their limit.`;
    else if (fine === tracked.length) ok = fine === 1 ? 'The 1 course is within its limit.' : `All ${fine} courses are within their limit.`;
    else ok = `${fine} ${are} within ${their} limit.`;
  }
  const info = unset.length ? `No limit set: ${unset.map((c) => `${c.course.name} ${used(c)}`).join(' · ')}` : null;
  let note: string | null = null;
  if (!ok && !info && !trouble.length) {
    note = !tracked.length ? 'No course takes attendance in eClass.' : `No absences in ${tracked.length} ${tracked.length === 1 ? 'course' : 'courses'}.`;
  }
  return { trouble, ok, info, note };
}

/** With nothing due in the next 3 days: "Nothing due in the next 3 days. Next: Lab 6, Multimedia Computing, Mon 3 Nov 23:59." */
export function nothingDue(deadlines: Deadline[], att: CourseAttendance[], now: number, dismissed: readonly string[] = []): string {
  const due = deadlines.filter(isDue);
  if (!due.length) return 'No deadlines in eClass.';
  const next = due.filter((d) => d.end > now && !isDone(d, att, dismissed)).sort((a, b) => a.end - b.end)[0];
  if (!next) return 'Nothing due in the next 3 days.';
  return `Nothing due in the next 3 days. Next: ${rowTitle(next.title)}, ${next.courseName}, ${dayDateTime(next.end, new Date(now))}.`;
}

/** The exams Today lists under its own header: those still to come, while some lie beyond the rail's 72 h. Null when the section stays out. */
export function examSection(snap: Snapshot, match: ExamMatch | null, now: number): MyExam[] | null {
  if (!match || (!snap.cache.lessons && !snap.cache.attendance)) return null;
  const left = match.exams.filter((e) => e.exam.end > now);
  if (match.exams.length && !left.some((e) => e.exam.start > now + 72 * HOUR)) return null;
  return left;
}

/** The age of what is on screen: the oldest of the main sources. Mail refreshes far more often, so it would hide old eClass data. */
export function oldestFetch(snap: Snapshot): number | null {
  const at = [snap.cache.lessons, snap.cache.deadlines, snap.cache.attendance].flatMap((c) => (c ? [c.fetchedAt] : []));
  return at.length ? Math.min(...at) : null;
}

/** A notification's link, only when it stays on eClass: the link comes from a message's content. */
export const noticeUrl = (n: { url: string | null }): string | null => (n.url?.startsWith(`${eclassBase}/`) ? n.url : null);

// ---- Failures ----

const isNetwork = (e: ErrorInfo | null | undefined) => e?.name === 'NetworkError' && !e.certificate && !e.status;

/** Offline: EduPage and eClass, two different hosts, both failed on the network on their last refresh (DESIGN.md 8). */
export const isOffline = (snap: Snapshot) => isNetwork(snap.state.edupage?.error) && isNetwork(snap.state.eclass?.error);

/** Whether the offline row already says what this error would. */
export const offlineCovers = (snap: Snapshot, error: ErrorInfo) => isNetwork(error) && isOffline(snap);

/** `<what happened>. <what you are seeing>.` for an error row: "Couldn't reach INS. Showing data from Tue 18:04." */
export function errorLine(error: ErrorInfo, service: Service, at?: number | null, now = new Date()): string {
  if (error.name === 'SetupNeeded') return error.message;
  const said = describeError(error, service);
  if (at == null) return said;
  return `${said.replace(' Check the connection.', '')} Showing data from ${updatedAt(at, now)}.`;
}

// ---- Deadlines ----

/** Past a day it is only old cache: the upcoming page no longer lists it. */
const onShow = (d: Deadline, now: number) => d.end > now - 24 * HOUR;

export interface DeadlineSections {
  /** Not done and past its time, oldest first. */
  overdue: Deadline[];
  /** The rest, by day. Work done after its day stays under that day. */
  days: [string, Deadline[]][];
  /** Some filter narrows the list, so an empty list is the filters' doing. */
  filtered: boolean;
}

/** Deadlines' list: the student's filters applied, overdue work first, the rest by day. */
export function deadlineSections(all: Deadline[], att: CourseAttendance[], now: number, s: Pick<Settings, 'deadlineKinds' | 'deadlineCourse' | 'showDone' | 'dismissed'>): DeadlineSections {
  const shown = all
    .filter((d) => s.deadlineKinds.includes(d.kind) && onShow(d, now))
    .filter((d) => !s.deadlineCourse || d.courseName === s.deadlineCourse || courseOf(d, att)?.course.name === s.deadlineCourse)
    .filter((d) => s.showDone || !isDone(d, att, s.dismissed))
    .sort((a, b) => a.end - b.end);
  const late = (d: Deadline) => isDue(d) && d.end < now && !isDone(d, att, s.dismissed);
  const days = new Map<string, Deadline[]>();
  for (const d of shown.filter((d) => !late(d))) days.set(dayKey(d.end), [...(days.get(dayKey(d.end)) ?? []), d]);
  const sameKinds = s.deadlineKinds.length === defaultDeadlineKinds.length && defaultDeadlineKinds.every((k) => s.deadlineKinds.includes(k));
  return { overdue: shown.filter(late), days: [...days.entries()], filtered: !sameKinds || !!s.deadlineCourse || !s.showDone };
}

/** Course names to offer: attendance's full names over the calendar's sometimes-shortened ones, and whatever is chosen now. */
export function deadlineCourses(all: Deadline[], att: CourseAttendance[], chosen = ''): string[] {
  const names = new Set(att.map((c) => c.course.name));
  for (const d of all) if (d.courseName && !courseOf(d, att)) names.add(d.courseName);
  if (chosen) names.add(chosen);
  return [...names].sort();
}

const kindWord: Record<DeadlineKind, string> = { assignment: 'Assignment', quiz: 'Quiz', vod: 'VOD', other: 'Event', classPeriod: 'Class' };

export const deadlineKindWord = (k: DeadlineKind) => kindWord[k];

/** What a deadline's second line says, and its status (null = plain). */
export function deadlineLine(d: Deadline, att: CourseAttendance[], now: number, dismissed: readonly string[] = []): { text: string; status: Status | null } {
  const vod = vodFor(d, att);
  if (markedDone(d, dismissed) && !d.done && (vod?.percent ?? 0) < 100) return { text: 'Marked done by you', status: 'ok' };
  if (isDone(d, att)) {
    const word = d.kind === 'quiz' ? 'Attempted' : d.kind === 'vod' ? 'Watched' : 'Submitted';
    return { text: d.doneAt ? `${word} ${pastWhen(d.doneAt, new Date(now))}` : word, status: 'ok' };
  }
  const status = d.kind === 'classPeriod' ? null : deadlineStatus(d, now);
  if (d.kind === 'vod') {
    const pct = Math.floor(vod?.percent ?? 0);
    if (d.end < now) return { text: `Window closed · ${vod ? `${pct}% watched` : 'not watched'}`, status: 'danger' };
    const left = vod ? vod.lengthSec * (1 - Math.min(100, vod.percent) / 100) * 1000 : 0;
    if (status) return { text: vod ? `${pct}% watched${left >= 60e3 ? `, ${duration(left)} left` : ''}` : 'Not watched yet', status };
    return { text: `Closes · ${vod ? `${pct}% watched` : 'not watched yet'}`, status: null };
  }
  const missing = d.kind === 'quiz' ? 'not attempted' : d.kind === 'assignment' ? 'not submitted' : '';
  if (status) {
    const when = d.end < now ? relative(d.end, now) : `Due ${relative(d.end, now)}`;
    return { text: missing ? `${when} · ${missing}` : when, status };
  }
  return { text: missing ? missing[0].toUpperCase() + missing.slice(1) : kindWord[d.kind], status: null };
}

// ---- A VOD's watch window ----

/** Its window as a line, and whether it closed before it was watched. '' when the page gave no window. */
export function vodWindow(v: VodProgress, now: number): { text: string; missed: boolean } {
  const at = new Date(now);
  if (v.closes != null && v.closes < now) return v.percent >= 100 ? { text: `Closed ${dayDate(v.closes, at)}`, missed: false } : { text: `Window closed ${dayDate(v.closes, at)} · ${Math.floor(v.percent)}% watched`, missed: true };
  if (v.opens != null && v.opens > now) return { text: `Opens ${dayDateTime(v.opens, at)}`, missed: false };
  return { text: v.closes != null ? `Closes ${dayDateTime(v.closes, at)}` : '', missed: false };
}

// ---- Grades ----

/** "1 credit", "3 credits", "1.5 credits". */
export const creditWord = (n: number) => `${plainNumber(n)} ${n === 1 ? 'credit' : 'credits'}`;

/** A term's header: "GPA 3.81 · 18 credits". The GPA only where its letters carry points. */
export function termLine(records: GradeRecord[], gpa: number | null): string {
  const credits = records.reduce((sum, r) => sum + r.credits, 0);
  return gpa == null ? creditWord(credits) : `GPA ${gpa.toFixed(2)} · ${creditWord(credits)}`;
}

/** Letters that earn no credit. */
const noCreditLetters = new Set(['F', 'NP', 'U', 'W', 'I']);

/** Credits earned per INS category ("MR-M"), most first. A course taken more than once counts by its latest result, in a term with a result. */
export function creditsByCategory(records: GradeRecord[]): [string, number][] {
  const latest = new Map<string, GradeRecord>();
  for (const r of records.filter(isGraded)) {
    const key = r.code || r.name;
    const seen = latest.get(key);
    if (!seen || r.termKey >= seen.termKey) latest.set(key, r);
  }
  const by = new Map<string, number>();
  for (const r of latest.values()) {
    if (noCreditLetters.has(r.letter)) continue;
    const category = r.category || 'Other';
    by.set(category, (by.get(category) ?? 0) + r.credits);
  }
  return [...by.entries()].sort((a, b) => b[1] - a[1] || a[0].localeCompare(b[0]));
}

/** INS's own required-credit totals, to compare with the rows counted above; null when it gives neither. */
export function insTotals(r: GradeReport): string | null {
  const parts = [
    ...(r.majorRequired != null ? [`${plainNumber(r.majorRequired)} major-required`] : []),
    ...(r.generalRequired != null ? [`${plainNumber(r.generalRequired)} general-required`] : []),
  ];
  return parts.length ? `INS counts ${parts.join(' and ')} credits.` : null;
}

// ---- What-if scores ----

export interface WhatIf {
  /** The field's text: a comma decimal read as a point, anything else that can't be in a number dropped. */
  text: string;
  /** The score to count, or null. A value that doesn't parse or is over the maximum counts for nothing. */
  value: number | null;
  /** The value can't stand: the field says what it is out of, so the total never quietly differs from what is typed. */
  bad: boolean;
}

export function readWhatIf(raw: string, max: number): WhatIf {
  const text = raw.replace(/,/g, '.').replace(/[^0-9.]/g, '');
  if (text === '') return { text, value: null, bad: false };
  const v = Number(text);
  if (Number.isNaN(v)) return { text, value: null, bad: true };
  return v > max ? { text, value: null, bad: true } : { text, value: v, bad: false };
}

// ---- The tally (DESIGN.md 8) ----

export const tallyMax = 20;

export interface TallyStroke {
  x1: number;
  y1: number;
  x2: number;
  y2: number;
  used: boolean;
}

// At 16 tall: strokes 7 apart, a gate's diagonal 2 past its ends, gates 33 apart.
const step = 7, pitch = 33, left = 3;

/**
 * One stroke per absence in gates of five, four uprights and a diagonal, in
 * painting order: the faint first, so a faint diagonal never cuts an inked
 * upright. Null when there is nothing to draw, or more than 20: the words stand alone.
 */
export function tallyStrokes(used: number, limit: number | null): { strokes: TallyStroke[]; width: number } | null {
  const total = limit == null ? used : Math.max(used, limit);
  if (total < 1 || total > tallyMax) return null;
  const stroke = (i: number): TallyStroke => {
    const x0 = left + Math.floor(i / 5) * pitch;
    if (i % 5 === 4) return { x1: x0 - 2, y1: 11.5, x2: x0 + 3 * step + 2, y2: 4.5, used: i < used };
    const x = x0 + (i % 5) * step;
    return { x1: x, y1: 1, x2: x, y2: 15, used: i < used };
  };
  const faint = Array.from({ length: total - Math.min(used, total) }, (_, i) => stroke(used + i));
  const inked = Array.from({ length: Math.min(used, total) }, (_, i) => stroke(i));
  const gates = Math.floor((total - 1) / 5) + 1;
  const last = total - 5 * (gates - 1);
  const x0 = left + (gates - 1) * pitch;
  return { strokes: [...faint, ...inked], width: (last === 5 ? x0 + 3 * step + 2 : x0 + (last - 1) * step) + 3 };
}

/** What a course's tally says to a screen reader. */
export const tallyLabel = (used: number, limit: number | null) =>
  limit == null ? `${used} ${used === 1 ? 'absence' : 'absences'}` : `${used} of ${limit} allowed absences used`;
