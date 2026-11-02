// What the extension adds into eClass's own layout, each where it fits:
// header buttons, a menu section, a line of facts on every course in the
// course list, side blocks for today, what's due and mail, the course strip,
// and the time left on an activity.

import { render } from 'preact';
import { useEffect, useState } from 'preact/hooks';
import { isMarked, plainNumber, type Service } from '../core/models.ts';
import type { Snapshot } from '../core/store.ts';
import { CourseScore } from '../data/scores.ts';
import { currentPeriod, matchExams, roomChoice, studentCourses } from '../data/exams.ts';
import { clock, dayHeader, dayKey, duration, pastWhen, relative, rowTitle } from '../data/format.ts';
import { AbsenceState, courseDeadlines, deadlineStatus, gradeFor, isDone, markedDone, needsAttention, vodFor } from '../data/status.ts';
import { isStale, Stale, useNow, useRoute } from '../ui/common.tsx';
import { classesOn, errorLine } from '../ui/derive.ts';
import { courseListSelector, dueHref, dueWhen } from './pages.ts';
import { Icon, shadowHost, StatusLine, Tally, useSnap, viewUrl, type IconName } from './shared.tsx';
import { openView } from './view.tsx';

// ---------------------------------------------------------------- left menu

/** A section under eClass's left menu with the views eClass doesn't have. */
function MenuSection({ host }: { host: HTMLElement }) {
  const snap = useSnap();
  // Inside a course eClass folds its menu to a 60 px strip of icons: then so does this section.
  const [narrow, setNarrow] = useState(false);
  useEffect(() => {
    const ro = new ResizeObserver(() => setNarrow(host.getBoundingClientRect().width < 120));
    ro.observe(host);
    return () => ro.disconnect();
  }, []);
  const now = Date.now();
  const due = snap ? needsAttention(snap.cache.deadlines?.value ?? [], snap.cache.attendance?.value ?? [], now, snap.settings.dismissed).length : 0;
  const unread = snap?.cache.mailUnread?.value ?? 0;
  const exams = !!currentPeriod(now);
  const here = useRoute()[0];
  const item = (route: string, icon: IconName, label: string, count = 0) => (
    <a class={`mitem ${here === route.split('/')[0] ? 'on' : ''}`} title={label} aria-label={label} href={viewUrl(route)}>
      <Icon name={icon} />
      {!narrow && <span class="grow">{label}</span>}
      {count > 0 && <span class="count">{count}</span>}
    </a>
  );
  return (
    <nav class={`menu-section ${narrow ? 'narrow' : ''}`} aria-label="IUT">
      <div class="mhead">IUT</div>
      {item('today', 'today', 'Today')}
      {item('schedule', 'schedule', 'Schedule')}
      {item('deadlines', 'deadlines', 'Deadlines', due)}
      {item('courses', 'courses', 'Attendance')}
      {item('grades', 'grades', 'Grades')}
      {item('mail/inbox', 'mail', 'Mail', unread)}
      {exams && item('exams', 'exams', 'Exams')}
      {item('settings', 'settings', 'Settings')}
    </nav>
  );
}

// ---------------------------------------------------------------- course list

/**
 * A course's facts in its row of eClass's list, in fixed columns so they line
 * up down the list: absences, VODs, the eClass score, the INS grade, the next
 * thing due. How many columns fit, and whether they go under the course's name,
 * is moodle.css's call from the room the row has.
 */
export function CourseFacts({ courseId }: { courseId: number }) {
  const snap = useSnap();
  const now = useNow();
  const c = snap?.cache.attendance?.value.find((x) => x.course.id === courseId);
  if (!snap || !c) return null;
  const att = snap.cache.attendance!.value;
  const s = AbsenceState.of(c, snap.settings.absenceLimits);
  const grade = gradeFor(c.course, snap.cache.grades?.value);
  const next = courseDeadlines(c.course, snap.cache.deadlines?.value ?? [], att, now).find((d) => d.end > now && !isDone(d, att, snap.settings.dismissed));
  const nextStatus = next ? deadlineStatus(next, now) : null;
  const watched = c.vods.filter((v) => v.percent >= 100).length;
  const marks = snap.cache.courseGrades?.value.find((g) => g.course.id === courseId);
  const score = marks ? CourseScore.of(marks) : null;
  const marked = marks?.items.filter(isMarked).length ?? 0;
  return (
    <div class="facts">
      <a class="fact abs" title="Absences" href={viewUrl(`courses/${courseId}`)}>
        <span class={`n ${s.status ? `fg-${s.status}` : ''}`}>{s.limit == null ? s.used : `${s.used}/${s.limit}`}</span>
        <span class="k">{s.limit == null && s.used === 1 ? 'absence' : 'absences'}</span>
        <Tally used={s.used} limit={s.limit} status={s.status} />
      </a>
      <span class="fact">
        {c.vods.length > 0 && (
          <>
            <span class={`n ${watched === c.vods.length ? 'fg-ok' : ''}`}>{watched}/{c.vods.length}</span>
            <span class="k">VODs</span>
          </>
        )}
      </span>
      {score || marked ? (
        <a class="fact" title="Your eClass score" href={viewUrl(`grades/${courseId}`)}>
          <span class="n">{score ? plainNumber(score.accumulated) : marked}</span>
          <span class="k">{score ? `of ${plainNumber(score.outOf)}` : 'marked'}</span>
        </a>
      ) : (
        <span class="fact" />
      )}
      <span class="fact grade">{grade && grade.letter !== '-' ? grade.letter : ''}</span>
      <span class="fact next">
        {next && (
          <a class={nextStatus ? `fg-${nextStatus}` : ''} href={dueHref(next)} title={next.title}>
            <span class="k">{relative(next.end, now)}</span>
            <span class="ellipsis">{rowTitle(next.title)}</span>
          </a>
        )}
      </span>
    </div>
  );
}

// ---------------------------------------------------------------- side blocks

/** A block's service failed: one line naming it, leading to the view that has the next step (DESIGN.md 7). */
function Failed({ snap, service, to }: { snap: Snapshot; service: Service; to: string }) {
  const error = snap.state[service]?.error;
  if (!error) return null;
  return <StatusLine status="danger"><a href={viewUrl(error.name === 'SetupNeeded' ? 'settings' : to)}>{errorLine(error, service)}</a></StatusLine>;
}

/** On a block's header, when what it shows is old or its service failed (DESIGN.md 7). */
const asOf = (snap: Snapshot, service: Service, fetchedAt: number | undefined, now: number) =>
  isStale(snap, service, fetchedAt, now) ? <Stale at={fetchedAt!} /> : null;

function TodayBlock({ snap, now }: { snap: Snapshot; now: number }) {
  const today = new Date(now);
  const lessons = snap.cache.lessons?.value;
  const failed = !!snap.state.edupage?.error;
  const period = currentPeriod(now);
  const match = period ? matchExams(period, studentCourses(lessons ?? [], snap.cache.attendance?.value ?? []), snap.settings.classGroup, snap.settings.examRooms) : null;

  type Slot = { start: number; end: number; title: string; room: string; line: string };
  const slotsOn = (day: Date): Slot[] => {
    const exams = (match?.exams ?? [])
      .filter((e) => dayKey(e.exam.start) === dayKey(day))
      .map((e) => ({ start: e.exam.start, end: e.exam.end, title: e.course.eclass?.name ?? e.course.name, room: e.room ?? '', line: e.room ? 'Exam' : `Exam · ${roomChoice(e.exam.rooms)}` }));
    const classes = classesOn(day, lessons ?? []).map(({ start, end, lesson: l }) => ({ start, end, title: l.subject, room: l.room, line: [l.kind, l.teacher].filter(Boolean).join(' · ') }));
    return [...exams, ...classes].sort((a, b) => a.start - b.start);
  };

  if (!lessons && !snap.settings.classGroup) {
    return (
      <section class="sblock">
        <h2>Today</h2>
        <a class="link" href={viewUrl('settings')}>Choose your class group to see classes and rooms.</a>
      </section>
    );
  }
  const todays = slotsOn(today);
  const live = todays.find((s) => s.start <= now && now < s.end);
  const next = live ?? todays.find((s) => s.start > now);
  let label = '';
  let shown = next;
  if (!next) {
    for (let i = 1; i <= 7 && !shown; i++) {
      const day = new Date(today.getFullYear(), today.getMonth(), today.getDate() + i);
      const first = slotsOn(day)[0];
      if (first) {
        shown = first;
        label = `${dayHeader(day, today)} · ${clock(first.start)}`;
      }
    }
  } else {
    label = live ? `Now · until ${clock(live.end)} · ${duration(live.end - now)} left` : `Next · ${relative(next.start, now)}`;
  }
  const later = todays.filter((s) => s !== next && s.start > now);
  return (
    <section class="sblock">
      <h2>
        <a class="link h" href={viewUrl('schedule')}>Today</a>
        {asOf(snap, 'edupage', snap.cache.lessons?.fetchedAt, now)}
      </h2>
      {failed && (!lessons || !shown) && <Failed snap={snap} service="edupage" to="schedule" />}
      {shown ? (
        <>
          <div class="label fg-primary">{label}</div>
          <div class="room">{shown.room || 'Room not set'}</div>
          <div class="course">{shown.title}</div>
          {shown.line && <div class="muted small">{shown.line}</div>}
          {!next && <div class="muted small" style={{ marginTop: '4px' }}>No more classes today.</div>}
          {later.length > 0 && (
            <div class="later">
              {later.map((s) => (
                <div key={s.start} class="lrow">
                  <span class="t">{clock(s.start)}</span>
                  <span class="grow ellipsis">{s.title}</span>
                  <span class="muted">{s.room}</span>
                </div>
              ))}
            </div>
          )}
        </>
      ) : (
        !failed && <div class="muted">{lessons ? 'No classes this week.' : 'Updating…'}</div>
      )}
    </section>
  );
}

function DueBlock({ snap, now }: { snap: Snapshot; now: number }) {
  const att = snap.cache.attendance?.value ?? [];
  const all = snap.cache.deadlines?.value;
  const failed = !!snap.state.eclass?.error;
  if (!all && !failed) return null;
  const soon = needsAttention(all ?? [], att, now, snap.settings.dismissed).slice(0, 6);
  return (
    <section class="sblock">
      <h2>
        <a class="link h" href={viewUrl('deadlines')}>Due soon</a>
        {asOf(snap, 'eclass', snap.cache.deadlines?.fetchedAt, now)}
      </h2>
      {!soon.length ? (
        failed ? <Failed snap={snap} service="eclass" to="deadlines" /> : <StatusLine status="ok">Nothing due in the next 3 days.</StatusLine>
      ) : (
        soon.map((d) => {
          const st = deadlineStatus(d, now);
          const vod = vodFor(d, att);
          const what = d.kind === 'vod' ? `${Math.floor(vod?.percent ?? 0)}% watched` : d.kind === 'quiz' ? 'not attempted' : d.kind === 'assignment' ? 'not submitted' : '';
          return (
            <a key={`${d.moduleId}${d.end}`} class="drow" href={dueHref(d)}>
              <span class={`t ${st ? `fg-${st}` : ''}`}>{clock(d.end)}</span>
              <span class="grow">
                <span class="dt">{rowTitle(d.title)}</span>
                <span class={st ? `small fg-${st}` : 'small muted'}>
                  {dueWhen(d.end, now)}
                  {what ? ` · ${what}` : ''}
                </span>
                <span class="small muted ellipsis">{d.courseName}</span>
              </span>
            </a>
          );
        })
      )}
    </section>
  );
}

function MailBlock({ snap, now }: { snap: Snapshot; now: number }) {
  if (!snap.logins.mail) {
    return (
      <section class="sblock">
        <h2>Mail</h2>
        <a class="link" href={viewUrl('settings')}>Add your university mail login.</a>
      </section>
    );
  }
  const unread = (snap.cache.inbox?.value ?? []).filter((m) => m.unread);
  const count = snap.cache.mailUnread?.value ?? unread.length;
  const failed = !!snap.state.mail?.error;
  const known = !!snap.cache.mailUnread || !!snap.cache.inbox;
  const open = (e: Event, id: string) => {
    // The message's id stays out of eClass's address: the frame gets it directly.
    if (openView(`mail/inbox/${encodeURIComponent(id)}`)) e.preventDefault();
  };
  return (
    <section class="sblock">
      <h2>
        <a class="link h" href={viewUrl('mail/inbox')}>{count ? `${count} unread` : 'Mail'}</a>
        {asOf(snap, 'mail', (snap.cache.inbox ?? snap.cache.mailUnread)?.fetchedAt, now)}
      </h2>
      {!count ? (
        failed ? <Failed snap={snap} service="mail" to="mail/inbox" /> : <div class="muted">{known ? 'No unread mail.' : 'Updating…'}</div>
      ) : (
        unread.slice(0, 3).map((m) => (
          <a key={m.id} class="mrow" href={viewUrl('mail/inbox')} onClick={(e) => open(e, m.id)}>
            <span class="grow">
              <span class="dt ellipsis">{m.subject || '(no subject)'}</span>
              <span class="small muted ellipsis">{m.from}</span>
            </span>
            <span class="small muted">{pastWhen(m.received)}</span>
          </a>
        ))
      )}
    </section>
  );
}

export function SideBlocks() {
  const snap = useSnap();
  const now = useNow();
  if (!snap) return null;
  return (
    <div class="side">
      <TodayBlock snap={snap} now={now} />
      <DueBlock snap={snap} now={now} />
      <MailBlock snap={snap} now={now} />
    </div>
  );
}

// ---------------------------------------------------------------- course and activity pages

/** On a course page: absences, VODs, the eClass score, the INS grade and what is due, above eClass's own content. */
function CourseStrip({ courseId }: { courseId: number }) {
  const snap = useSnap();
  const now = useNow();
  const c = snap?.cache.attendance?.value.find((x) => x.course.id === courseId);
  if (!snap || !c) return null;
  const att = snap.cache.attendance!.value;
  const s = AbsenceState.of(c, snap.settings.absenceLimits);
  const grade = gradeFor(c.course, snap.cache.grades?.value);
  const due = courseDeadlines(c.course, snap.cache.deadlines?.value ?? [], att, now).filter((d) => !isDone(d, att, snap.settings.dismissed)).slice(0, 4);
  const watched = c.vods.filter((v) => v.percent >= 100).length;
  const marks = snap.cache.courseGrades?.value.find((g) => g.course.id === courseId);
  const score = marks ? CourseScore.of(marks) : null;
  return (
    <div class="strip">
      <a class="cell" href={viewUrl(`courses/${courseId}`)}>
        <span class="label">Absences{s.limit == null ? ' · set your limit' : s.tag ? ` · ${s.tag}` : ` · ${s.left} left`}</span>
        <span class={`big ${s.status ? `fg-${s.status}` : ''}`}>
          {s.limit == null ? s.used : `${s.used} of ${s.limit}`}
          <Tally used={s.used} limit={s.limit} status={s.status} />
        </span>
      </a>
      {c.vods.length > 0 && (
        <div class="cell">
          <span class="label">VODs watched</span>
          <span class="big">{watched} of {c.vods.length}</span>
        </div>
      )}
      {marks && marks.items.length > 0 && (
        <a class="cell" href={viewUrl(`grades/${courseId}`)}>
          <span class="label">{score ? 'Score so far' : 'Marks'}</span>
          <span class="big">{score ? score.line : `${marks.items.filter(isMarked).length} of ${marks.items.length}`}</span>
        </a>
      )}
      {grade && grade.letter !== '-' && (
        <div class="cell">
          <span class="label">INS grade · {grade.term}</span>
          <span class="big">{grade.letter}</span>
        </div>
      )}
      {due.length > 0 && (
        <div class="due">
          <span class="label">Due</span>
          {due.map((d) => {
            const st = deadlineStatus(d, now);
            return (
              <a key={`${d.moduleId}${d.end}`} href={dueHref(d)}>
                <span class={`t ${st ? `fg-${st}` : ''}`}>{clock(d.end)}</span>
                <span class="grow">{rowTitle(d.title)}</span>
                <span class={st ? `fg-${st}` : 'muted'}>{relative(d.end, now)}</span>
              </a>
            );
          })}
        </div>
      )}
    </div>
  );
}

/** On an assignment, quiz or VOD page: how long is left, or that it's done. */
export function DueBanner({ moduleId }: { moduleId: number }) {
  const snap = useSnap();
  const now = useNow();
  const d = snap?.cache.deadlines?.value.find((x) => x.moduleId === moduleId);
  if (!snap || !d) return null;
  const done = isDone(d, snap.cache.attendance?.value ?? [], snap.settings.dismissed);
  const st = done ? 'ok' : deadlineStatus(d, now);
  const doneWord = d.kind === 'quiz' ? 'Attempted' : d.kind === 'vod' ? 'Watched' : 'Submitted';
  return (
    <div class="banner">
      <span class={`when ${st ? `fg-${st}` : ''}`}>{done ? (markedDone(d, snap.settings.dismissed) ? 'Marked done by you' : doneWord) : relative(d.end, now)}</span>
      <span class="muted">
        {d.kind === 'vod' ? 'Window closes' : 'Due'} {new Date(d.end).toLocaleString('en-GB', { weekday: 'short', day: 'numeric', month: 'short', hour: '2-digit', minute: '2-digit' })}
      </span>
    </div>
  );
}

// ---------------------------------------------------------------- placing them

/** Renders `node` in a shadow root placed by `place`. A part that fails never stops the others. */
function mount(id: string, place: (el: HTMLElement) => void, node: preact.ComponentChildren) {
  try {
    render(node, shadowHost(id, place));
  } catch (e) {
    console.warn(`IUT: couldn't add ${id}`, e);
  }
}

/** Adds every part that has a place on this page. */
export function decorate(path: string): void {
  const menus = document.querySelector('#page-lnb .left-menus');
  if (menus) {
    try {
      const at = shadowHost('iut-menu', (el) => menus.after(el));
      render(<MenuSection host={document.getElementById('iut-menu')!} />, at);
    } catch (e) {
      console.warn("IUT: couldn't add the menu section", e);
    }
  }

  // The course list on the dashboard: a line of facts on each course.
  const list = document.querySelector(courseListSelector);
  list?.querySelectorAll<HTMLElement>('.course_box').forEach((box) => {
    const id = Number(new URL(box.querySelector<HTMLAnchorElement>('a.course_link')?.href ?? location.href).searchParams.get('id'));
    // A column of its own beside eClass's link, or under it where the row is narrow.
    if (id) mount(`iut-course-${id}`, (el) => box.append(el), <CourseFacts courseId={id} />);
  });
  // moodle.css measures the row with a container query, which takes the row's
  // width from around it. If eClass's layout sizes it by its content instead, the
  // row comes out with no width: then it is laid out without measuring.
  const row = list?.querySelector('li');
  if (row && row.getBoundingClientRect().width < 120) document.documentElement.classList.add('iut-rows-plain');

  // The right column: today, what's due and mail above eClass's own blocks.
  const blocks = document.getElementById('page-blocks');
  if (blocks && list) {
    mount('iut-side', (el) => blocks.prepend(el), <SideBlocks />);
    document.documentElement.classList.add('iut-has-due');
  }

  const main = document.getElementById('region-main');
  const id = Number(new URLSearchParams(location.search).get('id'));
  if (main && id && path === '/course/view.php') mount('iut-course', (el) => main.prepend(el), <CourseStrip courseId={id} />);
  if (main && id && /^\/mod\/(assign|quiz|vod)\/view\.php$/.test(path)) mount('iut-due', (el) => main.prepend(el), <DueBanner moduleId={id} />);
}
