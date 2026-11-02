// Courses: absences against the limit the student sets, VOD progress and the
// INS grade, closest to trouble first. A course opens its detail.

import { useState } from 'preact/hooks';
import { isGraded, type CourseAttendance } from '../../core/models.ts';
import { writeSettings, type Snapshot } from '../../core/store.ts';
import { dayDate, dayKey, duration, fromDayKey, isoWeekday, updatedAt, weekdayShort } from '../../data/format.ts';
import { CourseScore } from '../../data/scores.ts';
import { AbsenceState, courseDeadlines, gradeFor, heldClasses, lessonsOf, troubleOrder } from '../../data/status.ts';
import { courseUrl, vodUrl } from '../../services/eclass/links.ts';
import { eclassTarget, Icon, isStale, NoData, OfflineRow, SourceError, Stale, StatusLine, Tally } from '../common.tsx';
import { courseLine, creditWord, troubleLine, vodWindow } from '../derive.ts';
import { DeadlineRow } from '../rows.tsx';
import { ScoresRow } from './scores.tsx';

const markWord = { present: 'Present', absent: 'Absent', late: 'Late', other: 'Other', unmarked: 'Not marked' } as const;

export function Courses({ snap, now }: { snap: Snapshot; now: number }) {
  const att = snap.cache.attendance?.value;
  const limits = snap.settings.absenceLimits;
  const lessons = snap.cache.lessons?.value ?? [];
  if (!att) {
    return (
      <>
        <OfflineRow snap={snap} />
        <NoData snap={snap} service="eclass" />
      </>
    );
  }
  const fetchedAt = snap.cache.attendance!.fetchedAt;
  const tracked = att.filter((c) => c.classes.length);
  const unset = tracked.filter((c) => limits[c.course.id] == null).length;
  return (
    <>
      <OfflineRow snap={snap} />
      <SourceError snap={snap} service="eclass" at={fetchedAt} />
      {isStale(snap, 'eclass', fetchedAt, now) && <Stale at={fetchedAt} />}
      {!att.length && <p class="t-bl" style={{ margin: '16px 0' }}>eClass lists no courses for you.</p>}
      {unset > 0 ? (
        <div class="intro">
          <span class="t-bm grow">{unset === tracked.length ? "Set each course's allowed absences to see how many are left." : `${unset} ${unset === 1 ? 'course has' : 'courses have'} no absence limit set.`}</span>
          <a class="btn" href="#/courses/limits">Set limits</a>
        </div>
      ) : (
        tracked.length > 0 && <p class="t-bm muted tnum" style={{ margin: '16px 0 8px' }}>Absences against the limits you set, as of {updatedAt(fetchedAt)}.</p>
      )}
      <div class="rows">
        {troubleOrder(att, limits, lessons).map((c) => {
          const takesAttendance = c.classes.length > 0;
          const s = AbsenceState.of(c, limits);
          const grade = gradeFor(c.course, snap.cache.grades?.value);
          const vods = c.vods.length;
          const watched = c.vods.filter((v) => v.percent >= 100).length;
          const marks = snap.cache.courseGrades?.value.find((g) => g.course.id === c.course.id);
          const score = marks ? CourseScore.of(marks) : null;
          const line = courseLine(c, s.limit, lessons, now);
          return (
            <a key={c.course.id} class="row" href={`#/courses/${c.course.id}`} style={{ minHeight: '72px' }}>
              <div class="main">
                <span class="t-tm clamp2">{c.course.name}</span>
                {c.course.professor && <span class="t-bm muted ellipsis">{c.course.professor}</span>}
                {takesAttendance && s.status ? <StatusLine status={s.status}>{troubleLine(s, c, lessons, now)}</StatusLine> : line && <span class="t-bm muted">{line}</span>}
                {vods > 0 && <span class="t-bm muted tnum">VOD {watched} of {vods} watched</span>}
                {score && <span class="t-bm muted tnum">Score {score.line}</span>}
              </div>
              <div class="side">
                {takesAttendance && (
                  <>
                    <Tally used={s.used} limit={s.limit} status={s.status} />
                    <span class={`t-num tnum ${s.status ? `fg-${s.status}` : 'muted'}`}>{s.limit == null ? s.used : `${s.used} of ${s.limit}`}</span>
                  </>
                )}
                {grade && isGraded(grade) && <span class="grade-letter">{grade.letter}</span>}
              </div>
            </a>
          );
        })}
      </div>
    </>
  );
}

/**
 * A number field for a course's limit. What is typed stays local until it is
 * done, so a redraw from a sync or the minute tick can't wipe it mid-word.
 */
function LimitField({ c, limits, onDone }: { c: CourseAttendance; limits: Record<string, number>; onDone?: () => void }) {
  const saved = limits[c.course.id];
  const [text, setText] = useState(saved == null ? '' : String(saved));
  const save = () => {
    const n = parseInt(text, 10);
    const next = { ...limits };
    if (Number.isFinite(n) && n >= 0) next[c.course.id] = n;
    else delete next[c.course.id];
    if (next[c.course.id] !== saved) void writeSettings({ absenceLimits: next });
  };
  return (
    <input
      class="input"
      type="number"
      min={0}
      style={{ width: '96px' }}
      value={text}
      placeholder="Not set"
      aria-label={`Allowed absences in ${c.course.name}`}
      onInput={(e) => setText((e.target as HTMLInputElement).value)}
      onChange={save}
      onKeyDown={(e) => {
        if (e.key !== 'Enter') return;
        save();
        onDone?.();
      }}
    />
  );
}

/** Every course that takes attendance with its limit, in one place (DESIGN.md 8). Empty clears a limit. */
export function AbsenceLimits({ snap }: { snap: Snapshot }) {
  const limits = snap.settings.absenceLimits;
  const courses = (snap.cache.attendance?.value ?? []).filter((c) => c.classes.length).sort((a, b) => a.course.name.localeCompare(b.course.name));
  return (
    <div style={{ maxWidth: '760px' }}>
      <p class="t-bm muted" style={{ margin: '16px 0 8px' }}>
        How many absences each course allows. eClass doesn't publish this, so take it from the syllabus. With a limit set, Today and Attendance show how many are left.
      </p>
      {!courses.length && <p class="t-bl">No eClass course takes attendance yet.</p>}
      <div class="rows">
        {courses.map((c) => (
          <div key={c.course.id} class="row" style={{ alignItems: 'center' }}>
            <span class="main t-tm clamp2">{c.course.name}</span>
            <LimitField c={c} limits={limits} />
          </div>
        ))}
      </div>
    </div>
  );
}

/** The next date on this weekday, today included. */
const nextWeekday = (weekday: number, from: Date) => new Date(from.getFullYear(), from.getMonth(), from.getDate() + ((weekday - isoWeekday(from) + 7) % 7));

/** The course isn't on the list: why, instead of bars that never resolve. */
function NoCourse({ snap }: { snap: Snapshot }) {
  if (!snap.cache.attendance) {
    return (
      <>
        <OfflineRow snap={snap} />
        <NoData snap={snap} service="eclass" />
      </>
    );
  }
  return (
    <>
      <p class="t-bl" style={{ margin: '16px 0 8px' }}>eClass has no course with this link.</p>
      <a class="btn" href="#/courses" style={{ marginLeft: '-12px' }}>Show attendance</a>
    </>
  );
}

export function CourseDetail({ snap, now, id }: { snap: Snapshot; now: number; id: number }) {
  const c = snap.cache.attendance?.value.find((x) => x.course.id === id);
  const [editing, setEditing] = useState(false);
  if (!c) return <NoCourse snap={snap} />;
  const marks = snap.cache.courseGrades?.value.find((g) => g.course.id === id);
  const limits = snap.settings.absenceLimits;
  const s = AbsenceState.of(c, limits);
  const grade = gradeFor(c.course, snap.cache.grades?.value);
  const due = courseDeadlines(c.course, snap.cache.deadlines?.value ?? [], snap.cache.attendance?.value ?? [], now);
  const lessons = lessonsOf(c.course, snap.cache.lessons?.value ?? []);
  const today = new Date(now);
  const held = heldClasses(c, now);
  const takesAttendance = c.classes.length > 0;
  const openInEclass = (
    <a class="btn" style={takesAttendance ? undefined : { marginLeft: '-12px' }} href={courseUrl(c.course.id)} target={eclassTarget}>
      <Icon name="open" /> Open in eClass
    </a>
  );

  return (
    <div class="cols">
      <div>
        <OfflineRow snap={snap} />
        <SourceError snap={snap} service="eclass" at={snap.cache.attendance!.fetchedAt} />
        <div class="course-head">
          <h2 class="t-hs">{c.course.name}</h2>
          <span class="t-bm muted">{[c.course.code, c.course.professor].filter(Boolean).join(' · ')}</span>
        </div>
        <section class="section">
          {!takesAttendance ? (
            <>
              <p class="t-bl" style={{ margin: 0 }}>No class attendance in eClass for this course.</p>
              <div style={{ marginTop: '8px' }}>{openInEclass}</div>
            </>
          ) : (
            <>
              <div style={{ display: 'flex', alignItems: 'baseline', gap: '16px', flexWrap: 'wrap' }}>
                <span class={`t-hm ${s.status ? `fg-${s.status}` : ''}`}>{s.limit == null ? s.used : `${s.used} of ${s.limit}`}</span>
                <span class="t-bl">{s.used === 1 && s.limit == null ? 'absence' : 'absences'}{s.limit == null ? ' · limit not set' : ' used'}</span>
              </div>
              <div style={{ margin: '8px 0' }}><Tally used={s.used} limit={s.limit} status={s.status} height={28} /></div>
              {s.status && <StatusLine status={s.status}>{s.tag}</StatusLine>}
              <div style={{ display: 'flex', flexWrap: 'wrap', gap: '8px', alignItems: 'center', marginTop: '8px' }}>
                {editing ? (
                  <>
                    <LimitField c={c} limits={limits} onDone={() => setEditing(false)} />
                    <button class="btn" onClick={() => setEditing(false)}>Done</button>
                  </>
                ) : (
                  <button class="btn" style={{ marginLeft: '-12px' }} onClick={() => setEditing(true)}>
                    {s.limit == null ? 'Set the absence limit' : 'Change the limit'}
                  </button>
                )}
                {openInEclass}
              </div>
            </>
          )}
        </section>

        {due.length > 0 && (
          <section class="section">
            <h2>Due</h2>
            <div class="rows">
              {due.map((d) => <DeadlineRow key={`${d.moduleId}${d.end}`} d={d} att={snap.cache.attendance!.value} now={now} dismissed={snap.settings.dismissed} showCourse={false} showDay />)}
            </div>
          </section>
        )}

        {takesAttendance && (
          <section class="section">
            <h2>Classes <span class="right muted">{held.length} held</span></h2>
            <div class="rows">
              {[...held].reverse().map((e) => (
                <div key={e.date + e.label} class="row" style={{ minHeight: '48px', alignItems: 'center' }}>
                  <span class="t-num tnum" style={{ width: '120px' }}>{dayDate(fromDayKey(e.date), today)}</span>
                  <span class="main t-bm muted">{e.label}</span>
                  {e.mark === 'absent' ? <StatusLine status="danger">Absent</StatusLine> : e.mark === 'late' ? <StatusLine status="warning">Late</StatusLine> : <span class={`t-bm ${e.mark === 'unmarked' ? 'muted' : ''}`}>{markWord[e.mark]}</span>}
                </div>
              ))}
            </div>
          </section>
        )}
      </div>

      <div>
        {marks && (
          <section class="section">
            <h2>Scores</h2>
            {snap.state.eclass?.marksError && <StatusLine status="warning">Some marks didn't update from eClass.</StatusLine>}
            <ScoresRow g={marks} />
          </section>
        )}
        {grade && (
          <section class="section">
            <h2>Grade</h2>
            <div class="row" style={{ alignItems: 'center' }}>
              <div class="main">
                {/* INS labels the term in progress "Course registration"; nothing in it is graded yet. */}
                <span class="t-bm muted">{isGraded(grade) ? grade.term : 'This semester'} · {creditWord(grade.credits)}</span>
              </div>
              {isGraded(grade) ? <span class="t-hm">{grade.letter}</span> : <span class="t-bm muted">Not graded</span>}
            </div>
          </section>
        )}
        {lessons.length > 0 && (
          <section class="section">
            <h2>In the timetable</h2>
            <div class="rows">
              {lessons.map((l) => (
                <a key={`${l.weekday}${l.start}`} class="row" href={`#/schedule/${dayKey(nextWeekday(l.weekday, today))}`} style={{ minHeight: '48px' }}>
                  <span class="t-num tnum" style={{ width: '120px' }}>{weekdayShort(l.weekday)} {l.start}</span>
                  <span class="main t-bm">{[l.room, l.kind, l.teacher].filter(Boolean).join(' · ')}</span>
                </a>
              ))}
            </div>
          </section>
        )}
        {c.vods.length > 0 && (
          <section class="section">
            <h2>VODs <span class="right muted">{c.vods.filter((v) => v.percent >= 100).length} of {c.vods.length} watched</span></h2>
            <div class="rows">
              {c.vods.map((v) => {
                const url = vodUrl(v);
                const window = vodWindow(v, now);
                const body = (
                  <>
                    <div style={{ display: 'flex', gap: '12px', width: '100%' }}>
                      <span class="t-bm muted" style={{ width: '56px' }}>Week {v.week}</span>
                      <span class="t-bm main ellipsis">{v.title}</span>
                      <span class={`t-num-s tnum ${v.percent >= 100 ? 'fg-ok' : ''}`}>{Math.floor(v.percent)}%</span>
                    </div>
                    <div class={`meter ${v.percent >= 100 ? 'ok' : ''}`}><i style={{ width: `${Math.min(100, v.percent)}%` }} /></div>
                    {v.lengthSec > 0 && v.percent < 100 && <span class="t-bs muted">{duration(v.lengthSec * 1000 * (1 - v.percent / 100))} left of {duration(v.lengthSec * 1000)}</span>}
                    {window.missed ? <StatusLine status="warning">{window.text}</StatusLine> : window.text && <span class="t-bs muted tnum">{window.text}</span>}
                  </>
                );
                return url ? (
                  <a key={v.week + v.title} class="row" href={url} target={eclassTarget} style={{ flexDirection: 'column', gap: '6px' }}>{body}</a>
                ) : (
                  <div key={v.week + v.title} class="row" style={{ flexDirection: 'column', gap: '6px' }}>{body}</div>
                );
              })}
            </div>
          </section>
        )}
      </div>
    </div>
  );
}
