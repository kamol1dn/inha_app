// Schedule (DESIGN.md 8): the week strip, then one day as a rail. Exams take
// the classes' place in an exam week.

import { Fragment, type ComponentChildren } from 'preact';
import type { Snapshot } from '../../core/store.ts';
import { periodName, roomChoice } from '../../data/exams.ts';
import { clock, dayDate, dayKey, duration, fromDayKey, isoWeekday, weekdayShort } from '../../data/format.ts';
import { AbsenceState, courseFor } from '../../data/status.ts';
import { ErrorRow, isStale, Skeleton, Stale, StatusLine } from '../common.tsx';
import { classesOn, examMatch, examsOn, isClassFree } from '../derive.ts';
import { lessonLine } from '../rows.tsx';

/** Monday of the week on show: this week, or next week on the weekend. */
function weekStart(now: Date): Date {
  const wd = isoWeekday(now);
  const shift = wd >= 6 ? 8 - wd : 1 - wd;
  return new Date(now.getFullYear(), now.getMonth(), now.getDate() + shift);
}

export function Schedule({ snap, now, day: dayParam }: { snap: Snapshot; now: number; day?: string }) {
  const today = new Date(now);
  const monday = weekStart(today);
  const week = Array.from({ length: 5 }, (_, i) => new Date(monday.getFullYear(), monday.getMonth(), monday.getDate() + i));
  const day = dayParam ? fromDayKey(dayParam) : isoWeekday(today) >= 6 ? week[0] : today;
  const lessons = snap.cache.lessons?.value;
  const att = snap.cache.attendance?.value ?? [];
  const match = examMatch(snap, now);
  const classes = classesOn(day, lessons ?? []);
  const exams = examsOn(day, match);
  const isToday = dayKey(day) === dayKey(today);
  const err = snap.state.edupage?.error;

  const rows: { start: number; end: number; title: string; line: string; extra?: ComponentChildren; href?: string }[] = [
    ...classes.map((c) => {
      const course = courseFor(c.lesson.subject, att);
      const s = course ? AbsenceState.of(course, snap.settings.absenceLimits) : null;
      return {
        start: c.start,
        end: c.end,
        title: c.lesson.subject,
        line: [lessonLine(c.lesson), c.lesson.teacher].filter(Boolean).join(' · '),
        extra: s?.trouble ? <StatusLine status={s.status!}>{s.line} · {s.tag}</StatusLine> : undefined,
        href: course ? `#/courses/${course.course.id}` : undefined,
      };
    }),
    ...exams.map((e) => ({
      start: e.exam.start,
      end: e.exam.end,
      title: e.course.eclass?.name ?? e.course.name,
      line: `${match ? periodName(match.period) : 'Exam'} · ${e.room ?? roomChoice(e.exam.rooms)}`,
      href: '#/exams',
    })),
  ].sort((a, b) => a.start - b.start);

  return (
    <>
      <nav class="week">
        {week.map((d) => (
          <a key={dayKey(d)} href={`#/schedule/${dayKey(d)}`} class={`${dayKey(d) === dayKey(day) ? 'on' : ''} ${dayKey(d) === dayKey(today) ? 'today' : ''}`}>
            <span class="t-lm">{weekdayShort(isoWeekday(d))}</span>
            <span class="d">{d.getDate()}</span>
          </a>
        ))}
      </nav>
      {err && <ErrorRow service="edupage" error={err} />}
      {snap.cache.lessons && isStale(snap, 'edupage', snap.cache.lessons.fetchedAt, now) && <Stale at={snap.cache.lessons.fetchedAt} />}
      {!lessons && !err ? (
        <Skeleton lines={4} />
      ) : rows.length === 0 ? (
        <p class="empty">
          {isClassFree(day) && match
            ? `No classes in ${periodName(match.period).toLowerCase()} week, and no exam of yours on ${dayDate(day)}.`
            : `No classes on ${dayDate(day)}.`}
        </p>
      ) : (
        <div class="rail">
          {rows.map((r, i) => {
            const past = r.end <= now;
            const live = r.start <= now && now < r.end;
            const prev = rows[i - 1];
            const gap = prev ? r.start - prev.end : 0;
            const showNow = isToday && !live && now < r.start && (!prev || now >= prev.end);
            const cls = `rail-row ${i === 0 && !showNow ? 'first' : ''} ${i === rows.length - 1 ? 'last' : ''} ${past ? 'past' : ''}`;
            return (
              <Fragment key={r.start + r.title}>
                {gap >= 30 * 60e3 && !showNow && (
                  <div class="rail-row">
                    <div class="time" />
                    <div class="node" />
                    <div class="body t-bm muted">Break {duration(gap)}</div>
                  </div>
                )}
                {showNow && (
                  <div class={`rail-row ${i === 0 ? 'first' : ''}`}>
                    <div class="time"><span class="t-num tnum">{clock(now)}</span></div>
                    <div class="node"><i class="now" /></div>
                    <div class="body"><span class="nowline">Now</span></div>
                  </div>
                )}
                <a class={cls} href={r.href}>
                  <div class="time">
                    <span class="t-num tnum">{clock(r.start)}</span>
                    <span class="t-num-s tnum muted">{clock(r.end)}</span>
                  </div>
                  <div class="node"><i class={`class ${past ? 'past' : ''} ${live ? 'live' : ''}`} /></div>
                  <div class="body">
                    {live && <span class="t-ll fg-primary">Now · until {clock(r.end)}</span>}
                    <span class="t-tm">{r.title}</span>
                    <span class="t-bm muted">{r.line}</span>
                    {r.extra}
                  </div>
                </a>
              </Fragment>
            );
          })}
        </div>
      )}
    </>
  );
}
