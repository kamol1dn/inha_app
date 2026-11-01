// Grades: GPA and credits from INS, this semester's scores from eClass, then
// every course by term from INS, newest first. The scores don't wait for INS,
// whose expired certificate can keep it out of reach.

import type { GradeRecord } from '../../core/models.ts';
import type { Snapshot } from '../../core/store.ts';
import { ErrorRow, isStale, Skeleton, Stale } from '../common.tsx';
import { ScoresRow } from './scores.tsx';

function ScoresThisSemester({ snap, now }: { snap: Snapshot; now: number }) {
  const cached = snap.cache.courseGrades;
  if (!cached?.value.length) return null;
  return (
    <section class="section">
      <h2>
        Scores this semester
        {isStale(snap, 'eclass', cached.fetchedAt, now) && <span class="right"><Stale at={cached.fetchedAt} /></span>}
      </h2>
      <div class="rows">
        {cached.value.map((g) => <ScoresRow key={g.course.id} g={g} showCourse />)}
      </div>
    </section>
  );
}

export function Grades({ snap, now }: { snap: Snapshot; now: number }) {
  const report = snap.cache.grades?.value;
  const err = snap.state.ins?.error;
  if (!report) {
    return (
      <>
        {err ? <ErrorRow service="ins" error={err} /> : <Skeleton lines={6} />}
        <ScoresThisSemester snap={snap} now={now} />
      </>
    );
  }
  const terms = new Map<number, GradeRecord[]>();
  for (const r of report.records) terms.set(r.termKey, [...(terms.get(r.termKey) ?? []), r]);
  const graded = report.records.filter((r) => r.letter && r.letter !== '-');
  return (
    <>
      {err && <ErrorRow service="ins" error={err} />}
      {isStale(snap, 'ins', snap.cache.grades!.fetchedAt, now) && <Stale at={snap.cache.grades!.fetchedAt} />}
      <div class="gpa">
        <div>
          <span class="t-hm">{report.gpa.toFixed(2)}</span>
          <span class="t-bm muted">GPA of 4.5</span>
        </div>
        <div>
          <span class="t-hm">{report.creditsEarned}</span>
          <span class="t-bm muted">credits earned</span>
        </div>
        <div>
          <span class="t-hm">{graded.length}</span>
          <span class="t-bm muted">courses graded</span>
        </div>
      </div>
      <ScoresThisSemester snap={snap} now={now} />
      {[...terms.entries()]
        .sort((a, b) => b[0] - a[0])
        .map(([key, records]) => {
          // INS labels the term in progress "Course registration"; nothing in it is graded yet.
          const inProgress = records.every((r) => !r.letter || r.letter === '-');
          const credits = records.reduce((sum, r) => sum + r.credits, 0);
          return (
            <section class="section" key={key}>
              <h2>
                {inProgress ? 'This semester' : records[0].term}
                <span class="right muted">{inProgress ? 'Not graded yet' : `${credits} credits`}</span>
              </h2>
              <div class="rows">
                {records.map((r) => (
                  <div key={r.code + r.name} class="row" style={{ alignItems: 'center' }}>
                    <div class="main">
                      <span class="t-ts ellipsis">{r.name}</span>
                      <span class="t-bm muted">{[r.code, `${r.credits} credits`, r.category].filter(Boolean).join(' · ')}</span>
                    </div>
                    <span class={`grade-letter ${r.letter === '-' ? 'muted' : ''}`}>{r.letter === '-' ? '–' : r.letter}</span>
                  </div>
                ))}
              </div>
            </section>
          );
        })}
    </>
  );
}
