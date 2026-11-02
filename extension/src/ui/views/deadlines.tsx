// Deadlines: everything due in eClass, VOD windows included, overdue work
// first and the rest by day. The filters are kept between visits.

import type { DeadlineKind } from '../../core/models.ts';
import { defaultDeadlineKinds, writeSettings, type Snapshot } from '../../core/store.ts';
import { dayHeader } from '../../data/format.ts';
import { isStale, NoData, OfflineRow, SourceError, Stale, StatusLine } from '../common.tsx';
import { deadlineCourses, deadlineSections } from '../derive.ts';
import { DeadlineRow } from '../rows.tsx';

const kinds: [DeadlineKind, string][] = [
  ['assignment', 'Assignments'],
  ['quiz', 'Quizzes'],
  ['vod', 'VODs'],
  ['other', 'Other'],
  ['classPeriod', 'Class periods'],
];

const clearFilters = () => writeSettings({ deadlineKinds: defaultDeadlineKinds, deadlineCourse: '', showDone: true });

export function Deadlines({ snap, now }: { snap: Snapshot; now: number }) {
  const { settings } = snap;
  const on = settings.deadlineKinds;
  const all = snap.cache.deadlines?.value;
  const att = snap.cache.attendance?.value ?? [];
  const { overdue, days, filtered } = deadlineSections(all ?? [], att, now, settings);
  const row = (d: (typeof overdue)[number]) => <DeadlineRow key={`${d.moduleId}${d.title}${d.end}`} d={d} att={att} now={now} dismissed={settings.dismissed} />;

  return (
    <>
      <div class="chips" style={{ padding: '16px 0 8px' }}>
        {kinds.map(([k, label]) => (
          <button
            key={k}
            class={`chip ${on.includes(k) ? 'on' : ''}`}
            aria-pressed={on.includes(k)}
            onClick={() => writeSettings({ deadlineKinds: on.includes(k) ? on.filter((x) => x !== k) : [...on, k] })}
          >
            {label}
          </button>
        ))}
        <select class="chip" value={settings.deadlineCourse} onChange={(e) => writeSettings({ deadlineCourse: (e.target as HTMLSelectElement).value })} aria-label="Course">
          <option value="">All courses</option>
          {deadlineCourses(all ?? [], att, settings.deadlineCourse).map((c) => (
            <option key={c}>{c}</option>
          ))}
        </select>
      </div>
      <label class="check">
        <input type="checkbox" checked={settings.showDone} onChange={(e) => writeSettings({ showDone: (e.target as HTMLInputElement).checked })} />
        Show done
      </label>
      {snap.cache.deadlines && isStale(snap, 'eclass', snap.cache.deadlines.fetchedAt, now) && <Stale at={snap.cache.deadlines.fetchedAt} />}
      <OfflineRow snap={snap} />
      {all && <SourceError snap={snap} service="eclass" at={snap.cache.deadlines!.fetchedAt} />}
      {!all ? (
        <NoData snap={snap} service="eclass" />
      ) : !overdue.length && !days.length ? (
        filtered ? (
          <>
            <p class="empty" style={{ paddingBottom: '4px' }}>Nothing matches these filters.</p>
            <button class="btn" style={{ marginLeft: '-12px' }} onClick={clearFilters}>Clear filters</button>
          </>
        ) : (
          <p class="empty">No upcoming deadlines in eClass.</p>
        )
      ) : (
        <>
          {overdue.length > 0 && (
            <section class="section">
              <h2><StatusLine status="danger"><span class="t-tm">Overdue</span></StatusLine></h2>
              <div class="rows">{overdue.map(row)}</div>
            </section>
          )}
          {days.map(([k, list]) => (
            <section class="section" key={k}>
              <h2>{dayHeader(list[0].end, new Date(now))}</h2>
              <div class="rows">{list.map(row)}</div>
            </section>
          ))}
        </>
      )}
    </>
  );
}
