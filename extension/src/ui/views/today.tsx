// Today (DESIGN.md 7): where next, what's urgent, attendance trouble, unread
// mail. On a wide screen the rail is the left column and the rest the right.

import type { ComponentChildren } from 'preact';
import { useLayoutEffect, useRef } from 'preact/hooks';
import type { CourseAttendance, Deadline } from '../../core/models.ts';
import type { Snapshot } from '../../core/store.ts';
import { examLine, examRoom, roomChoice, periodName, sittingsLine, type ExamPeriod, type MyExam } from '../../data/exams.ts';
import { clock, dayHeader, dayKey, duration, HOUR, pastWhen, relative, rowTitle, updatedAt, weekdayShort, isoWeekday } from '../../data/format.ts';
import { AbsenceState, courseFor, isDue, needsAttention } from '../../data/status.ts';
import { itemUrl } from '../../services/eclass/links.ts';
import { eclassTarget, isStale, OfflineRow, Skeleton, SourceError, Stale, StatusLine } from '../common.tsx';
import { attendanceSummary, classesOn, deadlineLine, examMatch, examSection, examsOn, inTrouble, nothingDue, oldestFetch, railLaterClasses, type DayClass } from '../derive.ts';
import { AbsenceRow, lessonLine } from '../rows.tsx';

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

/** A class opens its course; with no course in eClass, Schedule on its day. */
function classHref(c: DayClass, att: CourseAttendance[]): string {
  const course = courseFor(c.lesson.subject, att);
  return course ? `#/courses/${course.course.id}` : `#/schedule/${dayKey(c.start)}`;
}

/** Hands out each course's attendance warning once: it goes on the course's first class on the rail. */
function firstWarning(att: CourseAttendance[], limits: Record<string, number>) {
  const warned = new Set<number>();
  return (subject: string): AbsenceState | null => {
    const c = courseFor(subject, att);
    const s = c ? inTrouble(c, limits) : null;
    if (!c || !s || warned.has(c.course.id)) return null;
    warned.add(c.course.id);
    return s;
  };
}

function classBody(c: DayClass, trouble: AbsenceState | null) {
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

function dueItem(d: Deadline, att: CourseAttendance[], now: number, dismissed: readonly string[]): RailItem {
  const { text, status } = deadlineLine(d, att, now, dismissed);
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

function examBody(e: MyExam, period: ExamPeriod | null) {
  return (
    <>
      <span class="t-tm ellipsis">{e.course.eclass?.name ?? e.course.name}</span>
      <span class="t-bm muted">{period ? examLine(e, period) : examRoom(e) ?? roomChoice(e.exam.rooms)}</span>
      {e.sittings > 1 && <StatusLine status="info">{sittingsLine(e)}</StatusLine>}
    </>
  );
}

/**
 * The room, the largest text in the app: on one line, scaled down until it fits
 * (DESIGN.md 4). It is measured rather than set by width, so it also fits the
 * narrower content area inside eClass.
 */
function RoomLine({ text }: { text: string }) {
  const ref = useRef<HTMLSpanElement>(null);
  useLayoutEffect(() => {
    const el = ref.current!;
    const fit = () => {
      el.style.fontSize = '';
      const full = parseFloat(getComputedStyle(el).fontSize);
      if (el.scrollWidth > el.clientWidth && el.clientWidth > 0) el.style.fontSize = `${Math.floor((full * el.clientWidth) / el.scrollWidth)}px`;
    };
    fit();
    const seen = new ResizeObserver(fit);
    seen.observe(el);
    // The bundled face can arrive after the first measure.
    void document.fonts?.ready.then(fit);
    return () => seen.disconnect();
  }, [text]);
  return <span ref={ref} class="t-display room-line">{text}</span>;
}

/** Builds the rail: overdue, now and the hero, the rest of today, then the next days. */
function buildRail(snap: Snapshot, now: number): { items: RailItem[]; anyDue: boolean } {
  const att = snap.cache.attendance?.value ?? [];
  const lessons = snap.cache.lessons?.value ?? [];
  // No timetable at all (first run, EduPage failing, no group chosen) says nothing about classes.
  const timetableKnown = !!snap.cache.lessons;
  const limits = snap.settings.absenceLimits;
  const dismissed = snap.settings.dismissed;
  const deadlines = (snap.cache.deadlines?.value ?? []).filter(isDue);
  const match = examMatch(snap, now);
  const period = match?.period ?? null;
  const attention = needsAttention(deadlines, att, now, dismissed);
  const warning = firstWarning(att, limits);
  const today = new Date(now);
  const items: RailItem[] = [];

  // Overdue first: on a timeline the past is above now.
  const overdue = attention.filter((d) => d.end < now);
  if (overdue.length) {
    items.push({ key: 'overdue', node: null, day: true, body: <StatusLine status="danger">Overdue</StatusLine> });
    overdue.forEach((d) => items.push(dueItem(d, att, now, dismissed)));
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

  if (!live) items.push({ key: 'now', node: 'now', time: clock(now), body: <span class="nowline">Now</span> });
  if (next) {
    const label = live
      ? `Now · until ${clock(next.end)} · ${duration(next.end - now)} left`
      : `Next · ${relative(next.start, now)}`;
    const room = next.cls ? next.cls.lesson.room || 'Room not set' : examRoom(next.exam!) ?? 'Room not set';
    const name = next.cls ? next.cls.lesson.subject : next.exam!.course.eclass?.name ?? next.exam!.course.name;
    const detail = next.cls
      ? [next.cls.lesson.kind, next.cls.lesson.teacher].filter(Boolean).join(' · ')
      : `${period ? periodName(period) : 'Exam'} · ${duration(next.exam!.exam.end - next.exam!.exam.start)}${examRoom(next.exam!) ? '' : ` · ${roomChoice(next.exam!.exam.rooms)}`}`;
    const trouble = next.cls ? warning(next.cls.lesson.subject) : null;
    items.push({
      key: 'hero',
      node: live ? 'class live' : 'class',
      time: clock(next.start),
      end: clock(next.end),
      href: next.exam ? '#/exams' : `#/schedule/${dayKey(next.start)}`,
      body: (
        <>
          <span class="t-ll fg-primary">{label}</span>
          <RoomLine text={room} />
          <span class="t-tl">{name}</span>
          {detail && <span class="t-bm muted">{detail}</span>}
          {trouble && (
            <StatusLine status={trouble.status!}>
              {trouble.line} · {trouble.tag}
            </StatusLine>
          )}
          {next.exam && next.exam.sittings > 1 && <StatusLine status="info">{sittingsLine(next.exam)}</StatusLine>}
        </>
      ),
    });
  }

  // The rest of today: later classes and what is due today, in time order.
  const endOfToday = new Date(today.getFullYear(), today.getMonth(), today.getDate() + 1).getTime();
  const later: { at: number; item: RailItem }[] = [];
  for (const s of slots) {
    if (s === next || s.end <= now) continue;
    if (s.cls) later.push({ at: s.start, item: { key: `c${s.start}`, node: 'class', time: clock(s.start), end: clock(s.end), href: classHref(s.cls, att), body: classBody(s.cls, warning(s.cls.lesson.subject)) } });
    else later.push({ at: s.start, item: { key: `e${s.start}`, node: 'class', time: clock(s.start), end: clock(s.end), href: '#/exams', body: examBody(s.exam!, period) } });
  }
  attention.filter((d) => d.end >= now && d.end < endOfToday).forEach((d) => later.push({ at: d.end, item: dueItem(d, att, now, dismissed) }));
  later.sort((a, b) => a.at - b.at).forEach((x) => items.push(x.item));

  const lastEnd = slots.length ? Math.max(...slots.map((s) => s.end)) : null;
  if (!slots.length) {
    if (timetableKnown) items.push({ key: 'noclass', node: null, body: <span class="t-bm muted">No classes today</span> });
  } else if (lastEnd! > now) items.push({ key: 'free', node: null, time: clock(lastEnd!), body: <span class="t-bm muted">Free for the rest of the day</span> });
  else if (!next) items.push({ key: 'nomore', node: null, body: <span class="t-bm muted">No more classes today</span> });

  // The next days: what is due and exams within 72 h, the first class of the
  // next day with classes, and the next class of every course in trouble.
  const days = new Map<string, { at: number; item: RailItem }[]>();
  const put = (at: number, item: RailItem) => days.set(dayKey(at), [...(days.get(dayKey(at)) ?? []), { at, item }]);
  for (const c of railLaterClasses(lessons, att, limits, now)) {
    put(c.start, { key: `c${c.start}`, node: 'class', time: clock(c.start), end: clock(c.end), href: classHref(c, att), body: classBody(c, warning(c.lesson.subject)) });
  }
  for (const e of match?.exams ?? []) {
    if (e.exam.start < endOfToday || e.exam.start - now > 72 * HOUR) continue;
    put(e.exam.start, { key: `e${e.exam.start}${e.exam.cell}`, node: 'class', time: clock(e.exam.start), end: clock(e.exam.end), href: '#/exams', body: examBody(e, period) });
  }
  attention.filter((d) => d.end >= endOfToday).forEach((d) => put(d.end, dueItem(d, att, now, dismissed)));
  for (const [key, list] of [...days.entries()].sort((a, b) => a[0].localeCompare(b[0]))) {
    items.push({ key: `day${key}`, node: null, day: true, body: <span class="t-tm">{dayHeader(list[0].at, today)}</span> });
    list.sort((a, b) => a.at - b.at).forEach((x) => items.push(x.item));
  }

  return { items, anyDue: attention.length > 0 };
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

/** The exam week at a glance, while some of the student's exams lie beyond the rail's 72 h. */
function ExamsSection({ snap, now }: { snap: Snapshot; now: number }) {
  const match = examMatch(snap, now);
  const left = examSection(snap, match, now);
  if (!match || !left) return null;
  const name = periodName(match.period);
  return (
    <section class="section">
      <h2>{name} exams</h2>
      {!left.length && <p class="t-bm" style={{ margin: '4px 0' }}>None of your courses is on the {name.toLowerCase()} timetable.</p>}
      <div class="rows">
        {left.map((e) => {
          const at = new Date(e.exam.start);
          return (
            <a key={e.exam.cell + e.exam.slot} class="row" href="#/exams">
              <div class="t-num tnum row-time">
                <span>{clock(at)}</span>
                <span class="t-num-s muted">{weekdayShort(isoWeekday(at))} {at.getDate()}</span>
              </div>
              <div class="main">{examBody(e, match.period)}</div>
            </a>
          );
        })}
      </div>
      {left.some((e) => !examRoom(e)) && <StatusLine status="info">Rooms aren't included, for your privacy: choose an exam to set yours.</StatusLine>}
      <div><a class="btn" href="#/exams" style={{ marginLeft: '-12px' }}>Show exam week</a></div>
    </section>
  );
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

  const summary = attendanceSummary(att, settings.absenceLimits, lessons);

  const inbox = (cache.inbox?.value ?? []).filter((m) => m.unread);
  const unread = cache.mailUnread?.value ?? inbox.length;
  const notices = cache.notifications?.value ?? [];
  const notes = notices.filter((n) => !n.read).slice(0, 4);
  const updated = oldestFetch(snap);
  const busy = Object.values(state).some((s) => s?.busy);
  const timetableOld = !timetableErr && cache.lessons && isStale(snap, 'edupage', cache.lessons.fetchedAt, now);
  const eclassOld = !eclassErr && cache.deadlines && isStale(snap, 'eclass', cache.deadlines.fetchedAt, now);

  return (
    <div class="cols">
      <div>
        <OfflineRow snap={snap} />
        <SourceError snap={snap} service="edupage" at={cache.lessons?.fetchedAt} />
        <SourceError snap={snap} service="eclass" at={cache.deadlines?.fetchedAt} />
        {(timetableOld || eclassOld) && (
          <div style={{ padding: '8px 0', display: 'flex', flexWrap: 'wrap', gap: '4px 16px' }}>
            {timetableOld && <span class="stale">Timetable as of {pastWhen(cache.lessons!.fetchedAt)}</span>}
            {eclassOld && <span class="stale">eClass as of {pastWhen(cache.deadlines!.fetchedAt)}</span>}
          </div>
        )}
        {loading ? <Skeleton lines={5} /> : <Rail items={items} />}
        {/* Never an all-clear a failed refresh can't back up. */}
        {!loading && !anyDue && cache.deadlines && !eclassErr && (
          <div style={{ padding: '12px 0 0 92px' }}>
            <StatusLine status="ok">{nothingDue(deadlines, att, now, settings.dismissed)}</StatusLine>
          </div>
        )}
      </div>

      <div>
        <ExamsSection snap={snap} now={now} />

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
                {summary.trouble.map((c) => (
                  <AbsenceRow key={c.course.id} c={c} limits={settings.absenceLimits} lessons={lessons} now={now} href={`#/courses/${c.course.id}`} />
                ))}
              </div>
              <div class="status-lines">
                {summary.ok && <StatusLine status="ok">{summary.ok}</StatusLine>}
                {summary.info && <StatusLine status="info">{summary.info}</StatusLine>}
                {summary.note && <span class="t-bm">{summary.note}</span>}
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

        {notices.length > 0 && (
          <section class="section">
            <h2><a href="#/notifications" style={{ color: 'inherit' }}>From eClass</a></h2>
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
            <a class="btn" href="#/notifications" style={{ marginLeft: '-12px' }}>All {notices.length} notifications</a>
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
