// Today (DESIGN.md 7): where next, what's urgent, attendance trouble, unread
// mail. On a wide screen the rail is the left column and the rest the right.

import type { ComponentChildren } from 'preact';
import type { CourseAttendance, Deadline } from '../../core/models.ts';
import type { Snapshot } from '../../core/store.ts';
import { roomChoice, periodName, type MyExam } from '../../data/exams.ts';
import { clock, dayHeader, duration, HOUR, pastWhen, relative, rowTitle, updatedAt } from '../../data/format.ts';
import { AbsenceState, courseFor, isDone, isDue, needsAttention, troubleOrder } from '../../data/status.ts';
import { itemUrl } from '../../services/eclass/links.ts';
import { eclassTarget, ErrorRow, isStale, Skeleton, Stale, StatusLine } from '../common.tsx';
import { classesOn, examMatch, examsOn, type DayClass } from '../derive.ts';
import { AbsenceRow, deadlineLine, lessonLine } from '../rows.tsx';

type Node = 'now' | 'class' | 'class past' | 'class live' | 'due' | 'due warning' | 'due danger' | null;

interface RailItem {
  key: string;
  node: Node;
  time?: string;
  end?: string;
  href?: string;
  external?: boolean;
  day?: boolean;
  past?: boolean;
  body: ComponentChildren;
}

function troubleFor(subject: string, att: CourseAttendance[], limits: Record<string, number>): AbsenceState | null {
  const c = courseFor(subject, att);
  if (!c) return null;
  const s = AbsenceState.of(c, limits);
  return s.trouble ? s : null;
}

function classBody(c: DayClass, att: CourseAttendance[], limits: Record<string, number>) {
  const trouble = troubleFor(c.lesson.subject, att, limits);
  return (
    <>
      <span class="t-tm ellipsis">{c.lesson.subject}</span>
      <span class="t-bm muted">{lessonLine(c.lesson)}</span>
      {trouble && (
        <StatusLine status={trouble.status!}>
          {trouble.line} · {trouble.tag}
        </StatusLine>
      )}
    </>
  );
}

function dueItem(d: Deadline, att: CourseAttendance[], now: number): RailItem {
  const { text, status } = deadlineLine(d, att, now);
  const plain = !status || status === 'ok';
  return {
    key: `due${d.moduleId ?? d.title}${d.end}`,
    node: plain ? 'due' : (`due ${status}` as Node),
    time: clock(d.end),
    href: itemUrl(d) ?? undefined,
    external: true,
    body: (
      <>
        <span class="t-ts">{rowTitle(d.title)}</span>
        {plain ? (
          <span class="t-bm muted">
            {text} · {d.courseName}
          </span>
        ) : (
          <>
            <StatusLine status={status!}>{text}</StatusLine>
            <span class="t-bm muted ellipsis">{d.courseName}</span>
          </>
        )}
      </>
    ),
  };
}

function examBody(e: MyExam, periodLabel: string) {
  return (
    <>
      <span class="t-tm ellipsis">{e.course.eclass?.name ?? e.course.name}</span>
      <span class="t-bm muted">
        {periodLabel} · {e.room ?? roomChoice(e.exam.rooms)}
      </span>
    </>
  );
}

/** Builds the rail: overdue, now and the hero, the rest of today, then the next days up to 72 h. */
function buildRail(snap: Snapshot, now: number): { items: RailItem[]; hero: ComponentChildren | null; anyDue: boolean } {
  const att = snap.cache.attendance?.value ?? [];
  const lessons = snap.cache.lessons?.value ?? [];
  const limits = snap.settings.absenceLimits;
  const deadlines = (snap.cache.deadlines?.value ?? []).filter(isDue);
  const match = examMatch(snap, now);
  const attention = needsAttention(deadlines, att, now);
  const today = new Date(now);
  const items: RailItem[] = [];

  // Overdue first: on a timeline the past is above now.
  const overdue = attention.filter((d) => d.end < now);
  if (overdue.length) {
    items.push({ key: 'overdue', node: null, day: true, body: <StatusLine status="danger">Overdue</StatusLine> });
    overdue.forEach((d) => items.push(dueItem(d, att, now)));
  }

  // Today's classes, or exams in an exam week.
  const classes = classesOn(today, lessons);
  const exams = examsOn(today, match);
  type Slot = { start: number; end: number; cls?: DayClass; exam?: MyExam };
  const slots: Slot[] = [...classes.map((c) => ({ start: c.start, end: c.end, cls: c })), ...exams.map((e) => ({ start: e.exam.start, end: e.exam.end, exam: e }))].sort(
    (a, b) => a.start - b.start,
  );
  const live = slots.find((s) => s.start <= now && now < s.end);
  const next = live ?? slots.find((s) => s.start > now);

  let hero: ComponentChildren | null = null;
  if (next) {
    const label = live
      ? `Now · until ${clock(next.end)} · ${duration(next.end - now)} left`
      : `Next · ${relative(next.start, now)}`;
    const room = next.cls ? next.cls.lesson.room || 'Room not set' : next.exam!.room ?? 'Room not set';
    const name = next.cls ? next.cls.lesson.subject : next.exam!.course.eclass?.name ?? next.exam!.course.name;
    const detail = next.cls
      ? [next.cls.lesson.kind, next.cls.lesson.teacher].filter(Boolean).join(' · ')
      : `${match ? periodName(match.period) : 'Exam'} · ${duration(next.exam!.exam.end - next.exam!.exam.start)}${next.exam!.room ? '' : ` · ${roomChoice(next.exam!.exam.rooms)}`}`;
    const trouble = next.cls ? troubleFor(next.cls.lesson.subject, att, limits) : null;
    hero = (
      <>
        <span class="t-ll fg-primary">{label}</span>
        <span class="t-display" style={{ margin: '4px 0' }}>{room}</span>
        <span class="t-tl">{name}</span>
        {detail && <span class="t-bm muted">{detail}</span>}
        {trouble && (
          <StatusLine status={trouble.status!}>
            {trouble.line} · {trouble.tag}
          </StatusLine>
        )}
      </>
    );
  }

  if (!live) items.push({ key: 'now', node: 'now', time: clock(now), body: <span class="nowline">Now</span> });
  if (next) {
    items.push({
      key: 'hero',
      node: live ? 'class live' : 'class',
      time: clock(next.start),
      end: clock(next.end),
      href: next.exam ? '#/exams' : '#/schedule',
      body: hero,
    });
  }

  // The rest of today: later classes and what is due today, in time order.
  const endOfToday = new Date(today.getFullYear(), today.getMonth(), today.getDate() + 1).getTime();
  const later: { at: number; item: RailItem }[] = [];
  for (const s of slots) {
    if (s === next || s.end <= now) continue;
    if (s.cls) later.push({ at: s.start, item: { key: `c${s.start}`, node: 'class', time: clock(s.start), end: clock(s.end), href: '#/schedule', body: classBody(s.cls, att, limits) } });
    else later.push({ at: s.start, item: { key: `e${s.start}`, node: 'class', time: clock(s.start), end: clock(s.end), href: '#/exams', body: examBody(s.exam!, match ? periodName(match.period) : 'Exam') } });
  }
  attention.filter((d) => d.end >= now && d.end < endOfToday).forEach((d) => later.push({ at: d.end, item: dueItem(d, att, now) }));
  later.sort((a, b) => a.at - b.at).forEach((x) => items.push(x.item));

  const lastEnd = slots.length ? Math.max(...slots.map((s) => s.end)) : null;
  if (!slots.length) items.push({ key: 'noclass', node: null, body: <span class="t-bm muted">No classes today</span> });
  else if (lastEnd! > now) items.push({ key: 'free', node: null, time: clock(lastEnd!), body: <span class="t-bm muted">Free for the rest of the day</span> });
  else if (!next) items.push({ key: 'nomore', node: null, body: <span class="t-bm muted">No more classes today</span> });

  // The next days within 72 h: what is due, the first class of the next day
  // with classes, the next class of every course in trouble, and exams.
  let firstClassShown = false;
  const troubleShown = new Set<string>();
  for (let i = 1; i <= 3; i++) {
    const day = new Date(today.getFullYear(), today.getMonth(), today.getDate() + i);
    const dayEnd = new Date(today.getFullYear(), today.getMonth(), today.getDate() + i + 1).getTime();
    const dayItems: { at: number; item: RailItem }[] = [];
    const dayClasses = classesOn(day, lessons);
    dayClasses.forEach((c, idx) => {
      const t = troubleFor(c.lesson.subject, att, limits);
      const show = (!firstClassShown && idx === 0) || (t && !troubleShown.has(c.lesson.subject));
      if (!show) return;
      if (t) troubleShown.add(c.lesson.subject);
      dayItems.push({ at: c.start, item: { key: `c${c.start}`, node: 'class', time: clock(c.start), end: clock(c.end), href: '#/schedule', body: classBody(c, att, limits) } });
    });
    if (dayClasses.length) firstClassShown = true;
    examsOn(day, match).forEach((e) => {
      if (e.exam.start - now > 72 * HOUR) return;
      dayItems.push({ at: e.exam.start, item: { key: `e${e.exam.start}${e.exam.cell}`, node: 'class', time: clock(e.exam.start), end: clock(e.exam.end), href: '#/exams', body: examBody(e, match ? periodName(match.period) : 'Exam') } });
    });
    attention.filter((d) => d.end >= dayEnd - 24 * HOUR && d.end < dayEnd && d.end >= endOfToday).forEach((d) => dayItems.push({ at: d.end, item: dueItem(d, att, now) }));
    if (!dayItems.length) continue;
    items.push({ key: `day${i}`, node: null, day: true, body: <span class="t-tm">{dayHeader(day, today)}</span> });
    dayItems.sort((a, b) => a.at - b.at).forEach((x) => items.push(x.item));
  }

  return { items, hero, anyDue: attention.length > 0 };
}

function Rail({ items }: { items: RailItem[] }) {
  const nodes = items.map((it, i) => ({ it, i })).filter((x) => x.it.node);
  const first = nodes[0]?.i ?? -1;
  const last = nodes[nodes.length - 1]?.i ?? -1;
  return (
    <div class="rail">
      {items.map((it, i) => {
        const cls = `rail-row ${i === first ? 'first' : ''} ${i === last ? 'last' : ''} ${it.day ? 'day' : ''} ${i < first || i > last ? 'outside' : ''}`;
        const content = (
          <>
            <div class="time">
              {it.time && <span class="t-num tnum">{it.time}</span>}
              {it.end && <span class="t-num-s tnum muted">{it.end}</span>}
            </div>
            <div class="node" style={i < first || i > last ? { visibility: 'hidden' } : undefined}>{it.node && <i class={it.node} />}</div>
            <div class="body">{it.body}</div>
          </>
        );
        return it.href ? (
          <a key={it.key} class={cls} href={it.href} target={it.external ? eclassTarget : undefined}>
            {content}
          </a>
        ) : (
          <div key={it.key} class={cls}>
            {content}
          </div>
        );
      })}
    </div>
  );
}

/** "Nothing due in the next 3 days. Next: Lab 6, Multimedia Computing, Mon 3 Nov 23:59." */
function nothingDue(deadlines: Deadline[], att: CourseAttendance[], now: number): string {
  const next = deadlines.filter((d) => isDue(d) && d.end > now && !isDone(d, att)).sort((a, b) => a.end - b.end)[0];
  if (!next) return deadlines.length ? 'Nothing due in the next 3 days.' : 'No deadlines in eClass.';
  return `Nothing due in the next 3 days. Next: ${rowTitle(next.title)}, ${next.courseName}, ${relative(next.end, now)}.`;
}

export function Today({ snap, now }: { snap: Snapshot; now: number }) {
  const { cache, state, settings } = snap;
  const att = cache.attendance?.value ?? [];
  const lessons = cache.lessons?.value ?? [];
  const deadlines = cache.deadlines?.value ?? [];
  const { items, anyDue } = buildRail(snap, now);
  const eclassErr = state.eclass?.error;
  const timetableErr = state.edupage?.error;
  const loading = !cache.attendance && !cache.lessons && (state.eclass?.busy || state.edupage?.busy || !state.eclass);

  const ordered = troubleOrder(att, settings.absenceLimits, lessons);
  const trouble = ordered.filter((c) => AbsenceState.of(c, settings.absenceLimits).trouble);
  const rest = att.length - trouble.length;
  const noLimits = att.filter((c) => settings.absenceLimits[c.course.id] == null);

  const inbox = (cache.inbox?.value ?? []).filter((m) => m.unread);
  const unread = cache.mailUnread?.value ?? inbox.length;
  const notes = (cache.notifications?.value ?? []).filter((n) => !n.read).slice(0, 4);
  const updated = Math.max(...(['lessons', 'deadlines', 'attendance', 'inbox'] as const).map((k) => cache[k]?.fetchedAt ?? 0));
  const busy = Object.values(state).some((s) => s?.busy);

  return (
    <div class="cols">
      <div>
        {timetableErr && !cache.lessons && <ErrorRow service="edupage" error={timetableErr} />}
        {eclassErr && <ErrorRow service="eclass" error={eclassErr} />}
        {cache.lessons && isStale(snap, 'edupage', cache.lessons.fetchedAt, now) && (
          <div style={{ padding: '8px 0' }}>
            <span class="stale">Timetable as of {pastWhen(cache.lessons.fetchedAt)}</span>
          </div>
        )}
        {loading ? <Skeleton lines={5} /> : <Rail items={items} />}
        {!loading && !anyDue && cache.deadlines && (
          <div style={{ padding: '12px 0 0 92px' }}>
            <StatusLine status="ok">{nothingDue(deadlines, att, now)}</StatusLine>
          </div>
        )}
      </div>

      <div>
        <section class="section">
          <h2>
            <a href="#/courses" style={{ color: 'inherit' }}>Attendance</a>
            {cache.attendance && isStale(snap, 'eclass', cache.attendance.fetchedAt, now) && <span class="right"><Stale at={cache.attendance.fetchedAt} /></span>}
          </h2>
          {!cache.attendance ? (
            eclassErr ? <p class="empty">Attendance comes from eClass.</p> : <Skeleton lines={2} />
          ) : (
            <>
              <div class="rows">
                {trouble.map((c) => (
                  <AbsenceRow key={c.course.id} c={c} limits={settings.absenceLimits} href={`#/courses/${c.course.id}`} />
                ))}
              </div>
              <div style={{ padding: '8px 0' }}>
                {noLimits.length === att.length && att.length ? (
                  <StatusLine status="info">
                    No limit set:{' '}
                    {att
                      .map((c) => `${c.course.name} ${c.classes.filter((e) => e.mark === 'absent').length}`)
                      .join(' · ')}
                  </StatusLine>
                ) : (
                  <StatusLine status="ok">
                    {trouble.length ? `The other ${rest} ${rest === 1 ? 'course is' : 'courses are'} within their limit.` : `All ${att.length} courses are within their limit.`}
                  </StatusLine>
                )}
              </div>
            </>
          )}
        </section>

        {unread > 0 && (
          <section class="section">
            <h2>
              <a href="#/mail/inbox" style={{ color: 'inherit' }}>{unread} unread</a>
              {cache.inbox && isStale(snap, 'mail', cache.inbox.fetchedAt, now) && <span class="right"><Stale at={cache.inbox.fetchedAt} /></span>}
            </h2>
            <div class="rows">
              {inbox.slice(0, 3).map((m) => (
                <a key={m.id} class="row" href={`#/mail/inbox/${encodeURIComponent(m.id)}`}>
                  <div class="main">
                    <span class="t-ts ellipsis">{m.subject || '(no subject)'}</span>
                    <span class="t-bm muted ellipsis">{m.from}</span>
                  </div>
                  <span class="side t-bs muted">{pastWhen(m.received)}</span>
                </a>
              ))}
            </div>
            {unread > 3 && (
              <a class="btn" href="#/mail/inbox" style={{ marginLeft: '-12px' }}>
                {unread - Math.min(3, inbox.length)} more
              </a>
            )}
          </section>
        )}

        {notes.length > 0 && (
          <section class="section">
            <h2>From eClass</h2>
            <div class="rows">
              {notes.map((n) => (
                <a key={n.id} class="row" href={n.url ?? 'https://eclass.inha.ac.kr/'} target={eclassTarget}>
                  <div class="main">
                    <span class="t-ts">{n.subject}</span>
                  </div>
                  <span class="side t-bs muted">{pastWhen(n.time)}</span>
                </a>
              ))}
            </div>
          </section>
        )}

        <p class="t-bs muted" style={{ marginTop: '24px' }}>
          {busy ? 'Updating…' : updated ? `Updated ${updatedAt(updated)}` : ''}
        </p>
      </div>
    </div>
  );
}

export const todayTitle = (now: number) => {
  const d = new Date(now);
  return d.toLocaleDateString('en-GB', { weekday: 'short', day: 'numeric', month: 'short' }).replace(',', '');
};
