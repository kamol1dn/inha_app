// Exams (docs/EXAMS.md): the student's exams by day, with the rooms each uses
// until the student sets their own. The room list names every student, so it
// is never bundled.

import { useState } from 'preact/hooks';
import { writeSettings, type Snapshot } from '../../core/store.ts';
import { examKey, periodFirst, periodLast, periodName, roomChoice, type MyExam } from '../../data/exams.ts';
import { clock, dayHeader, dayKey, dayRange } from '../../data/format.ts';
import { Dialog, StatusLine } from '../common.tsx';
import { examMatch } from '../derive.ts';

export function Exams({ snap, now }: { snap: Snapshot; now: number }) {
  const match = examMatch(snap, now);
  const [editing, setEditing] = useState<MyExam | null>(null);
  if (!match) return <p class="empty">No exam period is coming up.</p>;
  const { period } = match;
  const days = new Map<string, MyExam[]>();
  for (const e of match.exams) days.set(dayKey(e.exam.start), [...(days.get(dayKey(e.exam.start)) ?? []), e]);
  const unset = match.exams.some((e) => !e.room);

  return (
    <>
      <p class="t-bm muted" style={{ marginTop: '16px' }}>
        {period.term} {period.kind}, {dayRange(new Date(periodFirst(period)), new Date(periodLast(period)))}, from the university's exam timetable.
      </p>
      {unset && <StatusLine status="info">Rooms aren't included, for your privacy: choose an exam to set yours.</StatusLine>}
      {!match.exams.length && <p class="empty">None of your courses is on this timetable{snap.settings.classGroup ? '' : ' (set your class group in Settings)'}.</p>}
      {[...days.entries()].map(([k, list]) => (
        <section class="section" key={k}>
          <h2>{dayHeader(list[0].exam.start, new Date(now))}</h2>
          <div class="rows">
            {list.map((e) => (
              <button key={e.exam.cell + e.exam.slot} class={`row ${e.exam.end < now ? 'muted' : ''}`} onClick={() => setEditing(e)}>
                <div style={{ width: '48px', textAlign: 'right' }}>
                  <div class="t-num tnum">{clock(e.exam.start)}</div>
                  <div class="t-num-s tnum muted">{clock(e.exam.end)}</div>
                </div>
                <div class="main">
                  <span class="t-tm">{e.course.eclass?.name ?? e.course.name}</span>
                  <span class="t-bm muted">
                    {periodName(period)} · {e.room ? `Your room ${e.room}` : roomChoice(e.exam.rooms)}
                    {e.sittings > 1 && e.exam.read.note ? ` · ${e.exam.read.note}` : ''}
                  </span>
                </div>
              </button>
            ))}
          </div>
        </section>
      ))}
      {match.unlisted.length > 0 && (
        <p class="t-bm muted" style={{ marginTop: '24px' }}>
          Not on this timetable: {match.unlisted.map((c) => c.name).join(', ')}.
        </p>
      )}
      {editing && (
        <Dialog title={editing.course.eclass?.name ?? editing.course.name} onClose={() => setEditing(null)}>
          <p class="t-bm muted">{editing.exam.cell} · uses {roomChoice(editing.exam.rooms)}</p>
          <div class="chips">
            {editing.exam.rooms.map((r) => (
              <button
                key={r}
                class={`chip ${editing.room === r ? 'on' : ''}`}
                onClick={async () => {
                  await writeSettings({ examRooms: { ...snap.settings.examRooms, [examKey(period, editing.exam)]: r } });
                  setEditing(null);
                }}
              >
                {r}
              </button>
            ))}
          </div>
          <div class="actions">
            {editing.room && (
              <button
                class="btn"
                onClick={async () => {
                  const rooms = { ...snap.settings.examRooms };
                  delete rooms[examKey(period, editing.exam)];
                  await writeSettings({ examRooms: rooms });
                  setEditing(null);
                }}
              >
                Clear my room
              </button>
            )}
            <button class="btn" onClick={() => setEditing(null)}>Close</button>
          </div>
        </Dialog>
      )}
    </>
  );
}
