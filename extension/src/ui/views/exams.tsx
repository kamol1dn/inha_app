// Exams (docs/EXAMS.md): the student's exams by day, with the rooms each uses
// until the student sets their own, and on request every sitting on the sheet.
// The room list names every student, so it is never bundled.

import { useState } from 'preact/hooks';
import { writeSettings, type Snapshot } from '../../core/store.ts';
import { examKey, examLine, examRoom, periodFirst, periodLast, periodName, roomChoice, sittingsLine, type ExamPeriod, type MyExam } from '../../data/exams.ts';
import { clock, dayDate, dayHeader, dayKey, dayRange, duration } from '../../data/format.ts';
import { Dialog, StatusLine } from '../common.tsx';
import { examMatch } from '../derive.ts';

/** The exams as sections by day. */
function byDay(exams: MyExam[], now: number, row: (e: MyExam) => preact.ComponentChildren) {
  const days = new Map<string, MyExam[]>();
  for (const e of exams) days.set(dayKey(e.exam.start), [...(days.get(dayKey(e.exam.start)) ?? []), e]);
  return [...days.entries()].map(([k, list]) => (
    <section class="section" key={k}>
      <h2>{dayHeader(list[0].exam.start, new Date(now))}</h2>
      <div class="rows">{list.map(row)}</div>
    </section>
  ));
}

function ExamRow({ e, period, now, sheet, onOpen }: { e: MyExam; period: ExamPeriod; now: number; sheet?: boolean; onOpen: () => void }) {
  const past = e.exam.end < now;
  return (
    <button class={`row ${past ? 'muted' : ''}`} onClick={onOpen}>
      <div class="row-time">
        <div class="t-num tnum">{clock(e.exam.start)}</div>
        <div class="t-num-s tnum muted">{clock(e.exam.end)}</div>
      </div>
      <div class="main">
        {sheet ? (
          <>
            <span class="t-ts">{e.exam.read.course}</span>
            <span class="t-bm muted">{[...(e.exam.read.uk ? ['UK programme'] : []), ...(e.exam.read.note ? [e.exam.read.note] : []), roomChoice(e.exam.rooms)].join(' · ')}</span>
          </>
        ) : (
          <>
            <span class="t-tm">{e.course.eclass?.name ?? e.course.name}</span>
            <span class="t-bm muted">{examLine(e, period)}</span>
            {e.sittings > 1 && !past && <StatusLine status="info">{sittingsLine(e)}</StatusLine>}
          </>
        )}
      </div>
    </button>
  );
}

export function Exams({ snap, now }: { snap: Snapshot; now: number }) {
  const match = examMatch(snap, now);
  const [editing, setEditing] = useState<MyExam | null>(null);
  const [every, setEvery] = useState(false);
  if (!match) return <p class="empty">No exam timetable for now. The next one comes with an update.</p>;
  const { period } = match;
  const what = periodName(period).toLowerCase();
  const known = !!snap.cache.lessons || !!snap.cache.attendance;
  const key = editing && examKey(period, editing.exam);
  const setRoom = async (room: string | null) => {
    const rooms = { ...snap.settings.examRooms };
    if (room) rooms[key!] = room;
    else delete rooms[key!];
    await writeSettings({ examRooms: rooms });
    setEditing(null);
  };
  const sheet: MyExam[] = period.exams.map((exam) => ({
    course: { name: exam.read.course, teachers: new Set(), eclass: null },
    exam,
    sittings: 1,
    room: snap.settings.examRooms[examKey(period, exam)] ?? null,
  }));

  return (
    <>
      <p class="t-bm muted" style={{ marginTop: '16px' }}>
        {period.term} {period.kind}, {dayRange(new Date(periodFirst(period)), new Date(periodLast(period)))}, from the university's exam timetable.
      </p>
      {known && match.exams.some((e) => !examRoom(e)) && <StatusLine status="info">Rooms aren't included, for your privacy: choose an exam to set yours.</StatusLine>}
      {!known && <p class="empty">Your courses come from the timetable and eClass, and neither has loaded yet.</p>}
      {known && !match.exams.length && <p class="empty">None of your courses is on the {what} timetable{snap.settings.classGroup ? '' : ' (set your class group in Settings)'}.</p>}
      {byDay(match.exams, now, (e) => <ExamRow key={e.exam.cell + e.exam.slot} e={e} period={period} now={now} onOpen={() => setEditing(e)} />)}
      {known && match.unlisted.length > 0 && (
        <p class="t-bm muted" style={{ marginTop: '24px' }}>
          No {what} listed for {match.unlisted.map((c) => c.name).join(', ')}.
        </p>
      )}
      <div style={{ marginTop: '16px' }}>
        <button class="btn" style={{ marginLeft: '-12px' }} aria-expanded={every} onClick={() => setEvery(!every)}>{every ? 'Hide other exams' : 'Show every exam'}</button>
      </div>
      {every && byDay(sheet, now, (e) => <ExamRow key={e.exam.cell + e.exam.slot} e={e} period={period} now={now} sheet onOpen={() => setEditing(e)} />)}
      <p class="t-bs muted" style={{ margin: '16px 0 24px' }}>From “{period.source}”.</p>
      {editing && (
        <Dialog title={editing.course.eclass?.name ?? editing.course.name} onClose={() => setEditing(null)}>
          <p class="t-bm tnum" style={{ margin: '0 0 8px' }}>
            {dayDate(editing.exam.start, new Date(now))}, {clock(editing.exam.start)}–{clock(editing.exam.end)} · {duration(editing.exam.end - editing.exam.start)}
          </p>
          <p class="t-bm muted">{editing.exam.cell} · uses {roomChoice(editing.exam.rooms)}</p>
          {editing.sittings > 1 && <p style={{ margin: '0 0 8px' }}><StatusLine status="info">{sittingsLine(editing)}</StatusLine></p>}
          {!editing.room && examRoom(editing) && <p class="t-bm muted">The only room this exam uses.</p>}
          {editing.exam.rooms.length > 1 && (
            <div class="chips">
              {editing.exam.rooms.map((r) => (
                <button key={r} class={`chip ${editing.room === r ? 'on' : ''}`} onClick={() => setRoom(r)}>{r}</button>
              ))}
            </div>
          )}
          <div class="actions">
            {editing.room && <button class="btn" onClick={() => setRoom(null)}>Clear my room</button>}
            <button class="btn" onClick={() => setEditing(null)}>Close</button>
          </div>
        </Dialog>
      )}
    </>
  );
}
