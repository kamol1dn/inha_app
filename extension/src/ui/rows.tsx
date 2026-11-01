// Rows shared by several views: a deadline, a class, a course's absences.

import type { CourseAttendance, Deadline, Lesson } from '../core/models.ts';
import { call } from '../core/rpc.ts';
import { readSettings, writeSettings } from '../core/store.ts';
import { clock, rowTitle, weekdayShort, isoWeekday } from '../data/format.ts';
import { AbsenceState, isDone, isDue, markedDone, withDismissed } from '../data/status.ts';
import { itemUrl } from '../services/eclass/links.ts';
import { eclassTarget, StatusLine, Tally } from './common.tsx';
import { deadlineKindWord, deadlineLine, troubleLine } from './derive.ts';

export { deadlineLine } from './derive.ts';

/** Marks or unmarks an item. The next pass withdraws its reminders, so one runs now. */
async function setMarked(d: Deadline, done: boolean) {
  const { dismissed } = await readSettings();
  await writeSettings({ dismissed: withDismissed(dismissed, d, done) });
  void call('sync', 'all').catch(() => {});
}

/** A deadline as a row of a list (Deadlines, a course): time, title, status, course. With showDay the day goes under the time, for a list with no day headers. */
export function DeadlineRow({ d, att, now, dismissed = [], showCourse = true, showDay = false }: { d: Deadline; att: CourseAttendance[]; now: number; dismissed?: readonly string[]; showCourse?: boolean; showDay?: boolean }) {
  const { text, status } = deadlineLine(d, att, now, dismissed);
  const url = itemUrl(d);
  const done = status === 'ok';
  const marked = markedDone(d, dismissed);
  const at = new Date(d.end);
  const inner = (
    <>
      <div class="t-num tnum row-time">
        <span class={status && !done ? `fg-${status}` : done ? 'muted' : ''}>{clock(d.end)}</span>
        {showDay && <span class="t-num-s muted">{weekdayShort(isoWeekday(at))} {at.getDate()}</span>}
      </div>
      <div class="main">
        <span class={`t-ts ${done ? 'muted' : ''}`}>{rowTitle(d.title)}</span>
        {status ? <StatusLine status={status}>{text}</StatusLine> : <span class="t-bm muted">{showCourse ? `${text} · ${d.courseName}` : text}</span>}
        {status && showCourse && <span class="t-bm muted ellipsis">{d.courseName}</span>}
      </div>
    </>
  );
  return (
    <div class="row with-action">
      {url ? <a class="row-link" href={url} target={eclassTarget}>{inner}</a> : <div class="row-link">{inner}</div>}
      <div class="side">
        <span class="t-bs muted">{deadlineKindWord(d.kind)}</span>
        {isDue(d) && marked && <button class="btn" onClick={() => setMarked(d, false)}>Undo</button>}
        {isDue(d) && !isDone(d, att, dismissed) && <button class="btn" onClick={() => setMarked(d, true)}>Mark as done</button>}
      </div>
    </div>
  );
}

/** "B202 · Lecture" */
export const lessonLine = (l: Lesson) => [l.room || 'Room not set', l.kind].filter(Boolean).join(' · ');

/** A course in trouble on Today: name, what is left and its next class, tally and count. */
export function AbsenceRow({ c, limits, lessons, now, href }: { c: CourseAttendance; limits: Record<string, number>; lessons: Lesson[]; now: number; href: string }) {
  const s = AbsenceState.of(c, limits);
  return (
    <a class="row" href={href} style={{ minHeight: '72px' }}>
      <div class="main">
        <span class="t-tm clamp2">{c.course.name}</span>
        {s.status ? <StatusLine status={s.status}>{troubleLine(s, c, lessons, now)}</StatusLine> : <span class="t-bm muted">{s.limit == null ? 'Limit not set' : `${s.left} left`}</span>}
      </div>
      <div class="side">
        <Tally used={s.used} limit={s.limit} status={s.status} />
        <span class={`t-num tnum ${s.status ? `fg-${s.status}` : 'muted'}`}>{s.limit == null ? `${s.used}` : `${s.used} of ${s.limit}`}</span>
      </div>
    </a>
  );
}
