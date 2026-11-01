// Courses: absences against the limit the student sets, VOD progress and the
// INS grade, closest to trouble first. A course opens its detail.

import { useState } from 'preact/hooks';
import { plainNumber } from '../../core/models.ts';
import { writeSettings, type Snapshot } from '../../core/store.ts';
import { dayDate, duration, fromDayKey } from '../../data/format.ts';
import { CourseScore } from '../../data/scores.ts';
import { AbsenceState, courseDeadlines, gradeFor, lessonsOf, troubleOrder } from '../../data/status.ts';
import { courseUrl } from '../../services/eclass/links.ts';
import { eclassTarget, ErrorRow, Icon, isStale, Skeleton, Stale, StatusLine, Tally } from '../common.tsx';
import { DeadlineRow } from '../rows.tsx';
import { ScoresRow } from './scores.tsx';

const markWord = { present: 'Present', absent: 'Absent', late: 'Late', other: 'Other', unmarked: '' } as const;

export function Courses({ snap, now }: { snap: Snapshot; now: number }) {
  const att = snap.cache.attendance?.value;
  const err = snap.state.eclass?.error;
  const limits = snap.settings.absenceLimits;
  if (!att) return err ? <ErrorRow service="eclass" error={err} /> : <Skeleton lines={6} />;
  return (
    <>
      {err && <ErrorRow service="eclass" error={err} />}
      {isStale(snap, 'eclass', snap.cache.attendance!.fetchedAt, now) && <Stale at={snap.cache.attendance!.fetchedAt} />}
      <div class="rows">
        {troubleOrder(att, limits, snap.cache.lessons?.value ?? []).map((c) => {
          const s = AbsenceState.of(c, limits);
          const grade = gradeFor(c.course, snap.cache.grades?.value);
          const vods = c.vods.length;
          const watched = c.vods.filter((v) => v.percent >= 100).length;
          const marks = snap.cache.courseGrades?.value.find((g) => g.course.id === c.course.id);
          const score = marks ? CourseScore.of(marks) : null;
          return (
            <a key={c.course.id} class="row" href={`#/courses/${c.course.id}`} style={{ minHeight: '72px' }}>
              <div class="main">
                <span class="t-tm ellipsis">{c.course.name}</span>
                <span class="t-bm muted ellipsis">{[c.course.professor, c.course.code].filter(Boolean).join(' · ')}</span>
                {s.status ? <StatusLine status={s.status}>{s.line} · {s.tag}</StatusLine> : <span class="t-bm muted">{s.line}{vods ? ` · ${watched} of ${vods} VODs watched` : ''}</span>}
                {score && <span class="t-bm muted tnum">Score {score.line}</span>}
              </div>
              <div class="side">
                <Tally used={s.used} limit={s.limit} status={s.status} />
                {grade && grade.letter !== '-' && <span class="grade-letter">{grade.letter}</span>}
              </div>
            </a>
          );
        })}
      </div>
    </>
  );
}

export function CourseDetail({ snap, now, id }: { snap: Snapshot; now: number; id: number }) {
  const c = snap.cache.attendance?.value.find((x) => x.course.id === id);
  const [editing, setEditing] = useState(false);
  if (!c) return <Skeleton lines={6} />;
  const marks = snap.cache.courseGrades?.value.find((g) => g.course.id === id);
  const limits = snap.settings.absenceLimits;
  const s = AbsenceState.of(c, limits);
  const grade = gradeFor(c.course, snap.cache.grades?.value);
  const due = courseDeadlines(c.course, snap.cache.deadlines?.value ?? [], snap.cache.attendance?.value ?? [], now);
  const lessons = lessonsOf(c.course, snap.cache.lessons?.value ?? []);
  const today = new Date(now);
  const held = c.classes.filter((e) => fromDayKey(e.date) <= today);
  const setLimit = (v: string) => {
    const n = parseInt(v, 10);
    const next = { ...limits };
    if (Number.isFinite(n) && n >= 0) next[c.course.id] = n;
    else delete next[c.course.id];
    void writeSettings({ absenceLimits: next });
  };

  return (
    <div class="cols">
      <div>
        <section class="section">
          <div style={{ display: 'flex', alignItems: 'baseline', gap: '16px', flexWrap: 'wrap' }}>
            <span class={`t-hm ${s.status ? `fg-${s.status}` : ''}`}>{s.limit == null ? s.used : `${s.used} of ${s.limit}`}</span>
            <span class="t-bl">{s.used === 1 ? 'absence' : 'absences'}{s.limit == null ? ' · limit not set' : ' used'}</span>
          </div>
          <div style={{ margin: '8px 0' }}><Tally used={s.used} limit={s.limit} status={s.status} /></div>
          {s.status && <StatusLine status={s.status}>{s.tag}</StatusLine>}
          <div style={{ display: 'flex', gap: '8px', alignItems: 'center', marginTop: '8px' }}>
            {editing ? (
              <>
                <input
                  class="input"
                  type="number"
                  min={0}
                  max={40}
                  style={{ width: '96px' }}
                  value={s.limit ?? ''}
                  autoFocus
                  aria-label="Allowed absences"
                  onKeyDown={(e) => e.key === 'Enter' && setEditing(false)}
                  onChange={(e) => setLimit((e.target as HTMLInputElement).value)}
                />
                <button class="btn" onClick={() => setEditing(false)}>Done</button>
              </>
            ) : (
              <button class="btn" style={{ marginLeft: '-12px' }} onClick={() => setEditing(true)}>
                {s.limit == null ? 'Set the absence limit' : 'Change the limit'}
              </button>
            )}
            <a class="btn" href={courseUrl(c.course.id)} target={eclassTarget}>
              <Icon name="open" /> Open in eClass
            </a>
          </div>
        </section>

        {due.length > 0 && (
          <section class="section">
            <h2>Due</h2>
            <div class="rows">
              {due.map((d) => <DeadlineRow key={`${d.moduleId}${d.end}`} d={d} att={snap.cache.attendance!.value} now={now} showCourse={false} />)}
            </div>
          </section>
        )}

        <section class="section">
          <h2>Classes <span class="right muted">{held.length} held</span></h2>
          {!c.classes.length ? (
            <p class="empty">This course takes no attendance in eClass.</p>
          ) : (
            <div class="rows">
              {[...held].reverse().map((e) => (
                <div key={e.date + e.label} class="row" style={{ minHeight: '48px', alignItems: 'center' }}>
                  <span class="t-num tnum" style={{ width: '120px' }}>{dayDate(fromDayKey(e.date), today)}</span>
                  <span class="main t-bm muted">{e.label}</span>
                  {e.mark === 'absent' ? <StatusLine status="danger">Absent</StatusLine> : e.mark === 'late' ? <StatusLine status="warning">Late</StatusLine> : <span class="t-bm">{markWord[e.mark]}</span>}
                </div>
              ))}
            </div>
          )}
        </section>
      </div>

      <div>
        {marks && (
          <section class="section">
            <h2>Scores</h2>
            <ScoresRow g={marks} />
          </section>
        )}
        {grade && (
          <section class="section">
            <h2>Grade</h2>
            <div class="row" style={{ alignItems: 'center' }}>
              <div class="main">
                <span class="t-bm muted">{grade.term} · {grade.credits} credits</span>
              </div>
              <span class="t-hm">{grade.letter === '-' ? 'Not graded' : grade.letter}</span>
            </div>
          </section>
        )}
        {lessons.length > 0 && (
          <section class="section">
            <h2>In the timetable</h2>
            <div class="rows">
              {lessons.map((l) => (
                <div key={`${l.weekday}${l.start}`} class="row" style={{ minHeight: '48px' }}>
                  <span class="t-num tnum" style={{ width: '120px' }}>{['Mon', 'Tue', 'Wed', 'Thu', 'Fri'][l.weekday - 1]} {l.start}</span>
                  <span class="main t-bm">{[l.room, l.kind, l.teacher].filter(Boolean).join(' · ')}</span>
                </div>
              ))}
            </div>
          </section>
        )}
        {c.vods.length > 0 && (
          <section class="section">
            <h2>VODs <span class="right muted">{c.vods.filter((v) => v.percent >= 100).length} of {c.vods.length} watched</span></h2>
            <div class="rows">
              {c.vods.map((v) => (
                <div key={v.week + v.title} class="row" style={{ flexDirection: 'column', gap: '6px' }}>
                  <div style={{ display: 'flex', gap: '12px', width: '100%' }}>
                    <span class="t-bm muted" style={{ width: '56px' }}>Week {v.week}</span>
                    <span class="t-bm main ellipsis">{v.title}</span>
                    <span class={`t-num-s tnum ${v.percent >= 100 ? 'fg-ok' : ''}`}>{Math.floor(v.percent)}%</span>
                  </div>
                  <div class={`meter ${v.percent >= 100 ? 'ok' : ''}`}><i style={{ width: `${Math.min(100, v.percent)}%` }} /></div>
                  {v.lengthSec > 0 && v.percent < 100 && <span class="t-bs muted">{duration(v.lengthSec * 1000 * (1 - v.percent / 100))} left of {duration(v.lengthSec * 1000)}</span>}
                </div>
              ))}
            </div>
          </section>
        )}
      </div>
    </div>
  );
}
