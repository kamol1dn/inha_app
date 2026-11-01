// Which notifications the current data calls for. A port of
// lib/notifications/rules.dart: pure logic with `now` passed in.
//
// Late reminders: when a reminder's time has passed but its item has not (the
// browser was closed, or the item just appeared), the most urgent missed one
// goes out now and older missed ones are dropped.

import { courseFromTitle, isMarked, itemScore, plainNumber, type CourseAttendance, type CourseGrades, type Deadline, type GradeItem, type Lesson, type VodProgress } from '../core/models.ts';
import type { NotifyChannel } from '../core/store.ts';
import { clock, dayKey, fromDayKey, HOUR, isoWeekday, MIN, parseHm, DAY } from './format.ts';
import { CourseScore, isAttendanceMark } from './scores.ts';

/** Reminders before a VOD window closes. Watching in the window is what counts for attendance. */
export const vodReminderLeads = [48 * HOUR, 6 * HOUR];
export const deadlineReminderLeads = [24 * HOUR, 3 * HOUR];
const remindedKinds = new Set(['assignment', 'quiz', 'other']);
export const classReminderLead = 15 * MIN;
/** A late reminder is skipped when the next one for the same item comes within this anyway. */
const lateSkipWithin = HOUR;
/** Absences older than this are not announced, so a first run doesn't announce a semester. */
const absenceLookback = 21 * DAY;
/** How long a sent key is kept. Longer than absenceLookback. */
export const sentKeyRetention = 60 * DAY;

/** Quiet hours, minutes after midnight, local time: 23:00 to 07:30. */
export const quietHours = { start: 23 * 60, end: 7 * 60 + 30 };
const quietMorningMargin = HOUR;
const quietEveningLead = HOUR;

export interface PlannedNotification {
  /** Stable: the same reminder always gets the same key, so what was sent is known. */
  key: string;
  title: string;
  body: string;
  when: number;
  channel: NotifyChannel;
  /** Due in quiet hours and could neither wait for the morning nor go out before. */
  quiet: boolean;
  /** What a click opens: an eClass URL. */
  url: string | null;
}

const clean = (s: string) => s.replace(/\s+/g, ' ').trim();
const norm = (s: string) => clean(s).toLowerCase();
const courseName = (s: string) => clean(courseFromTitle(0, clean(s)).name);

const wd = ['Mon', 'Tue', 'Wed', 'Thu', 'Fri', 'Sat', 'Sun'];
const mon = ['Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun', 'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec'];
/** Sun 25 Oct, 23:59 */
const dayTime = (t: number) => {
  const d = new Date(t);
  return `${wd[isoWeekday(d) - 1]} ${d.getDate()} ${mon[d.getMonth()]}, ${clock(d)}`;
};
const weekdayDayMonth = (d: Date) => `${wd[isoWeekday(d) - 1]} ${d.getDate()} ${mon[d.getMonth()]}`;
const dayMonth = (d: Date) => `${d.getDate()} ${mon[d.getMonth()]}`;

/** Minute-precision UTC stamp, so keys don't depend on the zone. */
const stamp = (t: number) => new Date(Math.floor(t / MIN) * MIN).toISOString().slice(0, 16).replace(/[-:]/g, '') + 'Z';
const leadTag = (ms: number) => (ms % HOUR === 0 ? `${ms / HOUR}h` : `${ms / MIN}m`);

function lengthText(sec: number): string {
  const mins = Math.round(sec / 60);
  const h = Math.floor(mins / 60), m = mins % 60;
  if (h === 0) return `${m} min`;
  return m === 0 ? `${h} h` : `${h} h ${m} min`;
}

/** The part of a deadline's reminder keys that names the item: every key is `<stem>|<lead>`. */
export function reminderStem(d: Deadline): string {
  const item = `${norm(courseName(d.courseName))}|${norm(d.title)}|${stamp(d.end)}`;
  return d.kind === 'vod' ? `vod:${item}` : `due:${d.kind}:${item}`;
}

function inQuiet(t: number): boolean {
  const d = new Date(t);
  const m = d.getHours() * 60 + d.getMinutes();
  return m >= quietHours.start || m < quietHours.end;
}

function quietEnd(t: number): number {
  const d = new Date(t);
  let end = new Date(d.getFullYear(), d.getMonth(), d.getDate(), 7, 30);
  if (end.getTime() <= t) end = new Date(d.getFullYear(), d.getMonth(), d.getDate() + 1, 7, 30);
  return end.getTime();
}

function quietStart(t: number): number {
  const d = new Date(t);
  let start = new Date(d.getFullYear(), d.getMonth(), d.getDate(), 23, 0);
  if (start.getTime() > t) start = new Date(d.getFullYear(), d.getMonth(), d.getDate() - 1, 23, 0);
  return start.getTime();
}

/** Moves reminders out of quiet hours; those landing on one instant collapse into the most urgent. */
function moveOutOfQuiet(reminders: PlannedNotification[], end: number, now: number, quiet: boolean): PlannedNotification[] {
  if (!quiet) return reminders;
  const byTime = new Map<number, PlannedNotification>();
  for (const n of reminders) {
    let when = n.when;
    let silent = false;
    if (inQuiet(when)) {
      const morning = quietEnd(when);
      const evening = quietStart(when) - quietEveningLead;
      if (end > morning + quietMorningMargin) when = morning;
      else if (evening > now) when = evening;
      else silent = true;
    }
    byTime.set(when, { ...n, when, quiet: silent });
  }
  return [...byTime.values()];
}

/** When to send each reminder for something at `end`, as [lead, when] pairs. Empty once `end` has passed. */
function reminderTimes(now: number, end: number, leads: number[], notBefore: number | null = null): [number, number][] {
  if (end <= now) return [];
  const sorted = [...leads].sort((a, b) => b - a); // earliest reminder first
  let late: number | null = null;
  const upcoming: [number, number][] = [];
  for (const lead of sorted) {
    let at = end - lead;
    if (notBefore != null && at < notBefore) at = notBefore;
    if (at <= now) late = lead;
    else if (upcoming.length && upcoming[upcoming.length - 1][1] === at) upcoming[upcoming.length - 1] = [lead, at];
    else upcoming.push([lead, at]);
  }
  const skipLate = upcoming.length > 0 && upcoming[0][1] - now < lateSkipWithin;
  return [...(late != null && !skipLate ? [[late, now] as [number, number]] : []), ...upcoming];
}

function findVod(d: Deadline, attendance: CourseAttendance[]): VodProgress[] {
  const course = norm(courseName(d.courseName));
  const title = norm(d.title);
  return attendance.filter((a) => norm(a.course.name) === course).flatMap((a) => a.vods.filter((v) => norm(v.title) === title));
}

function vodStatus(progress: VodProgress[]): string {
  if (!progress.length) return 'Not watched yet';
  const p = progress.reduce((a, b) => (a.percent <= b.percent ? a : b));
  const pct = Math.floor(Math.min(100, Math.max(0, p.percent)));
  if (pct === 0) return p.lengthSec > 0 ? `Not watched yet (${lengthText(p.lengthSec)})` : 'Not watched yet';
  const left = p.lengthSec * ((100 - Math.min(100, p.percent)) / 100);
  return left >= 60 ? `${pct}% watched (${lengthText(left)} left)` : `${pct}% watched`;
}

const gradeKeyPrefix = 'grade:';

/** The notification key for an item's mark, after `was`. The change is in the key, so a mark going back to an earlier value is news again. */
export const gradeKey = (courseId: number, item: GradeItem, was: string | undefined) =>
  `${gradeKeyPrefix}${courseId}|${item.key}|${was ?? ''}>${item.mark}`;

/** The eClass course id in a grade key, or null for another key. */
export function gradeCourseId(key: string): number | null {
  if (!key.startsWith(gradeKeyPrefix)) return null;
  const id = Number(key.slice(gradeKeyPrefix.length).split('|')[0]);
  return Number.isFinite(id) ? id : null;
}

function newMarks(now: number, g: CourseGrades, seen: Record<string, string>, url: string | null): PlannedNotification[] {
  const score = CourseScore.of(g);
  const course = clean(g.course.name);
  const out: PlannedNotification[] = [];
  for (const item of g.items) {
    if (!isMarked(item) || isAttendanceMark(item)) continue;
    const was = seen[item.key] as string | undefined;
    if (was === item.mark) continue;
    const name = clean(item.name);
    const before = was != null && was.trim() !== '' ? Number(was) : NaN;
    out.push({
      key: gradeKey(g.course.id, item, was),
      title: was == null ? `Graded: ${name}` : `Grade changed: ${name}`,
      body: [
        course,
        itemScore(item),
        ...(was != null ? [`was ${Number.isNaN(before) ? was : plainNumber(before)}`] : []),
        ...(score ? [`${score.line} so far`] : []),
      ].join(' · '),
      when: now,
      channel: 'grades',
      quiet: false,
      url,
    });
  }
  return out;
}

export interface PlanInput {
  now: number;
  deadlines?: Deadline[];
  attendance?: CourseAttendance[];
  lessons?: Lesson[];
  courseGrades?: CourseGrades[];
  /** The last mark announced for each item, by course id and item key: a mark goes out when it differs from that one. */
  seenGrades?: Record<string, Record<string, string>>;
  sentKeys?: Set<string>;
  quiet?: boolean;
  absenceLimits?: Record<string, number>;
  /** Days with no classes ('YYYY-MM-DD'): the exam weeks. */
  classFree?: Set<string>;
  /** eClass URL of a deadline's activity. */
  itemUrl?: (d: Deadline) => string | null;
  courseUrl?: (id: number) => string;
}

/** Everything to show or schedule, minus sentKeys, sorted by time then key. Nothing is placed before now. */
export function planNotifications(p: PlanInput): PlannedNotification[] {
  const { now, deadlines = [], attendance = [], lessons = [], sentKeys = new Set(), quiet = false } = p;
  const out = new Map<string, PlannedNotification>();
  const add = (n: PlannedNotification) => {
    if (!out.has(n.key)) out.set(n.key, n);
  };

  for (const d of deadlines) {
    const url = p.itemUrl?.(d) ?? null;
    const course = courseName(d.courseName);
    if (d.kind === 'vod') {
      const progress = findVod(d, attendance);
      if (progress.length && progress.every((v) => v.percent >= 100)) continue;
      const reminders = reminderTimes(now, d.end, vodReminderLeads, d.start).map(([lead, at]) => ({
        key: `${reminderStem(d)}|${leadTag(lead)}`,
        title: `${course}: ${clean(d.title)}`,
        body: `${vodStatus(progress)}, closes ${dayTime(d.end)}.`,
        when: at,
        channel: 'vod' as const,
        quiet: false,
        url,
      }));
      moveOutOfQuiet(reminders, d.end, now, quiet).forEach(add);
    } else if (remindedKinds.has(d.kind) && !d.done) {
      const due = dayTime(d.end);
      const body = d.kind === 'assignment' ? `Assignment due ${due}.` : d.kind === 'quiz' ? `Quiz closes ${due}.` : `Due ${due}.`;
      const reminders = reminderTimes(now, d.end, deadlineReminderLeads).map(([lead, at]) => ({
        key: `${reminderStem(d)}|${leadTag(lead)}`,
        title: `${course}: ${clean(d.title)}`,
        body,
        when: at,
        channel: 'deadlines' as const,
        quiet: false,
        url,
      }));
      moveOutOfQuiet(reminders, d.end, now, quiet).forEach(add);
    }
  }

  for (const a of attendance) {
    const total = a.classes.filter((e) => e.mark === 'absent').length;
    const limit = p.absenceLimits?.[a.course.id];
    const tally =
      limit == null
        ? `${total === 1 ? '1 absence' : `${total} absences`} in this course so far.`
        : total > limit
          ? `${total} absences, over the limit of ${limit}.`
          : total === limit
            ? `${total} of ${limit} allowed absences used, none left.`
            : `${total} of ${limit} allowed absences used, ${limit - total} left.`;
    for (const e of a.classes) {
      const date = fromDayKey(e.date);
      if (e.mark !== 'absent' || date.getTime() < now - absenceLookback) continue;
      const label = clean(e.label);
      const n: PlannedNotification = {
        key: `absent:${a.course.id}|${e.date}|${norm(label)}`,
        title: `Marked absent: ${clean(a.course.name)}, ${dayMonth(date)}`,
        body: `eClass recorded an absence for ${label || 'the class'} on ${weekdayDayMonth(date)}. ${tally}`,
        when: now,
        channel: 'attendance',
        quiet: false,
        url: p.courseUrl?.(a.course.id) ?? null,
      };
      // Nothing closes: an absence can always wait for the morning.
      moveOutOfQuiet([n], Infinity, now, quiet).forEach(add);
    }
  }

  for (const g of p.courseGrades ?? []) {
    // A mark can wait for the morning too.
    for (const n of newMarks(now, g, p.seenGrades?.[g.course.id] ?? {}, p.courseUrl?.(g.course.id) ?? null)) moveOutOfQuiet([n], Infinity, now, quiet).forEach(add);
  }

  const today = new Date(now);
  if (!p.classFree?.has(dayKey(today))) {
    for (const l of lessons) {
      if (l.weekday !== isoWeekday(today)) continue;
      const mins = parseHm(l.start);
      if (mins == null) continue;
      const start = new Date(today.getFullYear(), today.getMonth(), today.getDate(), Math.floor(mins / 60), mins % 60).getTime();
      const times = reminderTimes(now, start, [classReminderLead]);
      if (!times.length) continue;
      const subject = clean(l.subject);
      const room = clean(l.room);
      const at = clock(start);
      const n: PlannedNotification = {
        key: `class:${dayKey(start)}|${at}|${norm(subject)}`,
        title: subject,
        body: room ? `${room.toLowerCase().startsWith('room') ? room : `Room ${room}`} at ${at}` : `Starts at ${at}`,
        when: times[0][1],
        channel: 'classes',
        quiet: false,
        url: null,
      };
      moveOutOfQuiet([n], start, now, quiet).forEach(add);
    }
  }

  return [...out.values()]
    .filter((n) => !sentKeys.has(n.key))
    .sort((a, b) => a.when - b.when || a.key.localeCompare(b.key));
}
