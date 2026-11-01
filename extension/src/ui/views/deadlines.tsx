// Deadlines: everything due in eClass, VOD windows included, grouped by day.

import { useState } from 'preact/hooks';
import type { DeadlineKind } from '../../core/models.ts';
import { writeSettings, type Snapshot } from '../../core/store.ts';
import { dayHeader, dayKey, HOUR } from '../../data/format.ts';
import { isDone, isDue } from '../../data/status.ts';
import { ErrorRow, isStale, Skeleton, Stale } from '../common.tsx';
import { DeadlineRow } from '../rows.tsx';

const kinds: [DeadlineKind, string][] = [
  ['assignment', 'Assignments'],
  ['quiz', 'Quizzes'],
  ['vod', 'VODs'],
  ['other', 'Other'],
];

export function Deadlines({ snap, now }: { snap: Snapshot; now: number }) {
  const [on, setOn] = useState<Set<DeadlineKind>>(new Set(kinds.map(([k]) => k)));
  const [course, setCourse] = useState('');
  const all = snap.cache.deadlines?.value;
  const att = snap.cache.attendance?.value ?? [];
  const err = snap.state.eclass?.error;
  const showDone = snap.settings.showDone;

  const shown = (all ?? [])
    .filter((d) => isDue(d) && on.has(d.kind) && d.end > now - 24 * HOUR)
    .filter((d) => !course || d.courseName === course)
    .filter((d) => showDone || !isDone(d, att))
    .sort((a, b) => a.end - b.end);
  const days = new Map<string, typeof shown>();
  for (const d of shown) days.set(dayKey(d.end), [...(days.get(dayKey(d.end)) ?? []), d]);
  const courses = [...new Set((all ?? []).filter(isDue).map((d) => d.courseName))].sort();

  return (
    <>
      <div class="chips" style={{ padding: '16px 0 8px' }}>
        {kinds.map(([k, label]) => (
          <button
            key={k}
            class={`chip ${on.has(k) ? 'on' : ''}`}
            aria-pressed={on.has(k)}
            onClick={() => {
              const next = new Set(on);
              next.has(k) ? next.delete(k) : next.add(k);
              setOn(next);
            }}
          >
            {label}
          </button>
        ))}
        <select class="chip" value={course} onChange={(e) => setCourse((e.target as HTMLSelectElement).value)} aria-label="Course">
          <option value="">All courses</option>
          {courses.map((c) => (
            <option key={c}>{c}</option>
          ))}
        </select>
        <label class="check" style={{ minHeight: '32px', marginLeft: '8px' }}>
          <input type="checkbox" checked={showDone} onChange={(e) => writeSettings({ showDone: (e.target as HTMLInputElement).checked })} />
          Show done
        </label>
        {snap.cache.deadlines && isStale(snap, 'eclass', snap.cache.deadlines.fetchedAt, now) && <Stale at={snap.cache.deadlines.fetchedAt} />}
      </div>
      {err && <ErrorRow service="eclass" error={err} />}
      {!all ? (
        !err && <Skeleton lines={6} />
      ) : !shown.length ? (
        <p class="empty">{all.length ? 'Nothing matches these filters.' : 'No deadlines in eClass.'}</p>
      ) : (
        [...days.entries()].map(([k, list]) => (
          <section class="section" key={k}>
            <h2>{dayHeader(list[0].end, new Date(now))}</h2>
            <div class="rows">
              {list.map((d) => (
                <DeadlineRow key={`${d.moduleId}${d.title}${d.end}`} d={d} att={att} now={now} />
              ))}
            </div>
          </section>
        ))
      )}
    </>
  );
}
