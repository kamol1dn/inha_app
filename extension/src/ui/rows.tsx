// Rows shared by several views: a deadline, a class, a course's absences.

import type { CourseAttendance, Deadline, Lesson } from '../core/models.ts';
import { clock, duration, relative, rowTitle } from '../data/format.ts';
import { AbsenceState, deadlineStatus, isDone, vodFor, type Status } from '../data/status.ts';
import { itemUrl } from '../services/eclass/links.ts';
import { eclassTarget, StatusLine, Tally } from './common.tsx';

const kindWord: Record<string, string> = { assignment: 'Assignment', quiz: 'Quiz', vod: 'VOD', other: 'Event', classPeriod: 'Class' };

/** What a deadline's second line says, and its status (null = plain). */
export function deadlineLine(d: Deadline, att: CourseAttendance[], now: number): { text: string; status: Status | null } {
  const vod = vodFor(d, att);
  if (isDone(d, att)) {
    const word = d.kind === 'quiz' ? 'Attempted' : d.kind === 'vod' ? 'Watched' : 'Submitted';
    return { text: d.doneAt ? `${word} ${relativePast(d.doneAt, now)}` : word, status: 'ok' };
  }
  const status = d.kind === 'classPeriod' ? null : deadlineStatus(d, now);
  if (d.kind === 'vod') {
    const pct = Math.floor(vod?.percent ?? 0);
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

const relativePast = (t: number, now: number) => {
  const days = Math.floor((now - t) / 86400e3);
  return days < 1 ? `at ${clock(t)}` : days < 7 ? `${days} d ago` : '';
};

/** A deadline as a row of a list (Deadlines, a course): time, title, status, course. */
export function DeadlineRow({ d, att, now, showCourse = true, onOpen }: { d: Deadline; att: CourseAttendance[]; now: number; showCourse?: boolean; onOpen?: () => void }) {
  const { text, status } = deadlineLine(d, att, now);
  const url = itemUrl(d);
  const done = status === 'ok';
  const inner = (
    <>
      <div class="t-num tnum" style={{ width: '48px', textAlign: 'right' }}>
        <span class={status && !done ? `fg-${status}` : done ? 'muted' : ''}>{clock(d.end)}</span>
      </div>
      <div class="main">
        <span class={`t-ts ${done ? 'muted' : ''}`}>{rowTitle(d.title)}</span>
        {status ? <StatusLine status={status}>{text}</StatusLine> : <span class="t-bm muted">{showCourse ? `${text} · ${d.courseName}` : text}</span>}
        {status && showCourse && <span class="t-bm muted ellipsis">{d.courseName}</span>}
      </div>
      <div class="side t-bs muted">{kindWord[d.kind]}</div>
    </>
  );
  if (onOpen) return <button class="row" onClick={onOpen}>{inner}</button>;
  return url ? <a class="row" href={url} target={eclassTarget}>{inner}</a> : <div class="row">{inner}</div>;
}

/** "B202 · Lecture" */
export const lessonLine = (l: Lesson) => [l.room || 'Room not set', l.kind].filter(Boolean).join(' · ');

/** A course's absences: name, tally and count, and the status line when in trouble. */
export function AbsenceRow({ c, limits, href }: { c: CourseAttendance; limits: Record<string, number>; href: string }) {
  const s = AbsenceState.of(c, limits);
  return (
    <a class="row" href={href} style={{ minHeight: '72px' }}>
      <div class="main">
        <span class="t-tm ellipsis">{c.course.name}</span>
        {s.status ? <StatusLine status={s.status}>{s.tag}</StatusLine> : <span class="t-bm muted">{s.limit == null ? 'Limit not set' : `${s.left} left`}</span>}
      </div>
      <div class="side">
        <Tally used={s.used} limit={s.limit} status={s.status} />
        <span class="t-num-s tnum muted">{s.limit == null ? `${s.used}` : `${s.used} of ${s.limit}`}</span>
      </div>
    </a>
  );
}
