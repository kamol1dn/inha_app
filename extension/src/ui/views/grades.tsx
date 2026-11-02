// Grades: GPA and credits from INS, this semester's scores from eClass, then
// every course by term from INS, newest first. The scores don't wait for INS,
// whose expired certificate can keep it out of reach.

import { isGraded, plainNumber, termGpa, type GradeRecord } from '../../core/models.ts';
import type { Snapshot } from '../../core/store.ts';
import { ErrorRow, isStale, NoData, Stale, StatusLine } from '../common.tsx';
import { creditsByCategory, creditWord, insTotals, termLine } from '../derive.ts';
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
      {/* One course's pages failed: the rest are fresh, and its old marks are still listed. */}
      {snap.state.eclass?.marksError && <StatusLine status="warning">Some marks didn't update from eClass.</StatusLine>}
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
        <NoData snap={snap} service="ins" />
        <ScoresThisSemester snap={snap} now={now} />
      </>
    );
  }
  const fetchedAt = snap.cache.grades!.fetchedAt;
  const terms = new Map<number, GradeRecord[]>();
  for (const r of report.records) terms.set(r.termKey, [...(terms.get(r.termKey) ?? []), r]);
  const categories = creditsByCategory(report.records);
  return (
    <>
      {err && <ErrorRow service="ins" error={err} at={fetchedAt} />}
      {isStale(snap, 'ins', fetchedAt, now) && <Stale at={fetchedAt} />}
      <div class="gpa">
        <span class="t-hm">{report.gpa.toFixed(2)}</span>
        <span class="t-bm muted tnum">GPA of 4.5 · {plainNumber(report.creditsEarned)} credits{report.yearOfStudy ? ` · year ${report.yearOfStudy}` : ''}</span>
      </div>
      {categories.length > 0 && (
        <section class="section">
          <h2>Credits by category</h2>
          <div class="rows">
            {categories.map(([name, credits]) => (
              <div key={name} class="row" style={{ minHeight: '48px', alignItems: 'center' }}>
                <span class="main t-bl">{name}</span>
                <span class="t-bm muted tnum">{creditWord(credits)}</span>
              </div>
            ))}
          </div>
          {insTotals(report) && <p class="t-bm muted tnum" style={{ margin: '4px 0 0' }}>{insTotals(report)}</p>}
        </section>
      )}
      <ScoresThisSemester snap={snap} now={now} />
      {[...terms.entries()]
        .sort((a, b) => b[0] - a[0])
        .map(([key, records]) => {
          // INS labels the term in progress "Course registration"; nothing in it is graded yet.
          const inProgress = records.every((r) => !isGraded(r));
          return (
            <section class="section" key={key}>
              <h2>{inProgress ? 'This semester' : records[0].term}</h2>
              <p class="t-bm muted tnum" style={{ margin: 0 }}>{inProgress ? 'Not graded yet' : termLine(records, termGpa(records))}</p>
              <div class="rows">
                {records.map((r) => (
                  <div key={r.code + r.name} class="row" style={{ alignItems: 'center' }}>
                    <div class="main">
                      <span class="t-bl clamp2">{r.name}</span>
                      <span class="t-bm muted tnum">{[creditWord(r.credits), r.category].filter(Boolean).join(' · ')}</span>
                    </div>
                    {isGraded(r) ? <span class="grade-letter">{r.letter}</span> : <span class="t-bm muted">Not graded</span>}
                  </div>
                ))}
              </div>
            </section>
          );
        })}
    </>
  );
}
