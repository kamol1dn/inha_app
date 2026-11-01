// A course's marks from eClass: the accumulated score, each category with its
// weight, and what-if scores on whatever is still open (DESIGN.md 8, Scores).
// "Grade" stays the INS letter. What-if scores live here and are never saved.

import { useState } from 'preact/hooks';
import { isMarked, itemScore, plainNumber, type CourseGrades, type GradeItem } from '../../core/models.ts';
import type { Snapshot } from '../../core/store.ts';
import { CourseScore, markedLine, type ScoreLine } from '../../data/scores.ts';
import { courseUrl, gradesUrl } from '../../services/eclass/links.ts';
import { eclassTarget, ErrorRow, Icon, isStale, Skeleton, Stale } from '../common.tsx';

/** A course's accumulated score and how much is marked, leading to its scores. */
export function ScoresRow({ g, showCourse = false }: { g: CourseGrades; showCourse?: boolean }) {
  const score = CourseScore.of(g);
  return (
    <a class="row" href={`#/grades/${g.course.id}`} style={{ alignItems: 'center' }}>
      <div class="main">
        {showCourse && <span class="t-bl ellipsis">{g.course.name}</span>}
        <span class="t-bm muted tnum">{markedLine(g)}</span>
      </div>
      {score && <span class="t-tm tnum">{score.line}</span>}
    </a>
  );
}

const Mark = ({ item }: { item: GradeItem }) =>
  isMarked(item) ? <span class="t-tm tnum grade-mark">{itemScore(item)}</span> : <span class="t-bm muted">Not marked</span>;

/** Marks as they are, adding nothing up. */
function PlainRows({ items }: { items: GradeItem[] }) {
  return (
    <div class="rows">
      {items.map((i) => (
        <div key={i.key} class="row" style={{ alignItems: 'center' }}>
          <div class="main"><span class="t-bl">{i.name}</span></div>
          <Mark item={i} />
        </div>
      ))}
    </div>
  );
}

function LineRow({ line, onScore }: { line: ScoreLine; onScore: (v: number | null) => void }) {
  const worth = plainNumber(line.worth);
  if (line.item && line.marked) {
    return (
      <div class="row" style={{ alignItems: 'center' }}>
        <div class="main">
          <span class="t-bl">{line.name}</span>
          <span class="t-bm muted tnum">{plainNumber(line.earned)} of {worth} points</span>
        </div>
        <Mark item={line.item} />
      </div>
    );
  }
  const name = line.item ? line.name : 'Nothing posted yet';
  return (
    <div class="row" style={{ alignItems: 'center' }}>
      <div class="main">
        <span class="t-bl">{name}</span>
        <span class="t-bm muted tnum">{worth} points</span>
      </div>
      <span class="score-open">
        <input
          class="input score-field"
          inputMode="decimal"
          placeholder="–"
          aria-label={`What-if score for ${line.name}`}
          onInput={(e) => {
            const input = e.target as HTMLInputElement;
            input.value = input.value.replace(/[^0-9.]/g, '');
            const v = input.value === '' ? NaN : Number(input.value);
            onScore(Number.isNaN(v) ? null : v);
          }}
        />
        <span class="t-bm muted tnum">{line.item ? `/ ${plainNumber(line.max)}` : '%'}</span>
      </span>
    </div>
  );
}

/** The score first, then the lines by category, in eClass's order, then what adds nothing. */
function Scored({ score }: { score: CourseScore }) {
  const [whatIf, setWhatIf] = useState<Record<string, number>>({});
  const [round, setRound] = useState(0); // part of each field's key, so Clear empties them all
  const byCategory = new Map<string, ScoreLine[]>();
  for (const l of score.lines) byCategory.set(l.category, [...(byCategory.get(l.category) ?? []), l]);
  const open = score.lines.some((l) => !l.marked && whatIf[l.id] != null);
  return (
    <>
      <div class="score-total">
        <span class="t-hm">{plainNumber(score.accumulated)}</span>
        <span class="t-bm muted tnum">of {plainNumber(score.outOf)} so far</span>
      </div>
      {score.complete ? (
        <p class="t-bm muted tnum" style={{ margin: '2px 0 0' }}>
          {plainNumber(score.markedWorth)} points marked · {plainNumber(score.openWorth)} still open · best possible {plainNumber(score.best)}
        </p>
      ) : (
        <p class="t-bm muted" style={{ margin: '2px 0 0' }}>{hiddenWeights}</p>
      )}
      {open && (
        <div class="whatif">
          <span class="t-ts tnum grow">With these scores: {score.of(score.withScores(whatIf))}</span>
          <button class="btn" onClick={() => { setWhatIf({}); setRound(round + 1); }}>Clear</button>
        </div>
      )}
      {[...byCategory.entries()].map(([category, lines]) => (
        <section class="section" key={category}>
          <h2>{category ? `${category} · ${plainNumber(lines.reduce((s, l) => s + l.worth, 0))} points` : 'Other'}</h2>
          <div class="rows">
            {lines.map((l) => (
              <LineRow
                key={`${l.id}/${round}`}
                line={l}
                onScore={(v) => setWhatIf((was) => {
                  const next = { ...was };
                  if (v == null) delete next[l.id];
                  else next[l.id] = v;
                  return next;
                })}
              />
            ))}
          </div>
        </section>
      ))}
      {[...byCategoryOf(score.unweighted).entries()].map(([category, items]) => (
        <section class="section" key={`unweighted/${category}`}>
          <h2>{category || 'Other'}</h2>
          <PlainRows items={items} />
        </section>
      ))}
      {score.uncounted.length > 0 && (
        <section class="section">
          <h2>Not counted in the total</h2>
          <PlainRows items={score.uncounted} />
        </section>
      )}
    </>
  );
}

const hiddenWeights = "This total is eClass's. It doesn't publish every category's weight, so these marks can't be turned into points.";

function byCategoryOf(items: GradeItem[]): Map<string, GradeItem[]> {
  const by = new Map<string, GradeItem[]>();
  for (const i of items) by.set(i.category, [...(by.get(i.category) ?? []), i]);
  return by;
}

const noScoreReason = {
  gradebook: "eClass doesn't show weights for this course yet, so there is no score to add up.",
  activities: 'This course keeps its grades page closed. These marks come from its assignments and quizzes, without weights to add up.',
  none: 'This course keeps its grades page closed and has no assignments or quizzes in eClass.',
};

/** A course with no weights to add up: the marks as they are, and why. */
function Unweighted({ g }: { g: CourseGrades }) {
  return (
    <>
      <p class="t-bl" style={{ margin: '16px 0 0' }}>{noScoreReason[g.source]}</p>
      {[...byCategoryOf(g.items).entries()].map(([category, items]) => (
        <section class="section" key={category}>
          <h2>{category || 'Other'}</h2>
          <PlainRows items={items} />
        </section>
      ))}
    </>
  );
}

export function CourseScores({ snap, now, id }: { snap: Snapshot; now: number; id: number }) {
  const cached = snap.cache.courseGrades;
  const g = cached?.value.find((x) => x.course.id === id);
  const state = snap.state.eclass;
  const err = state?.error ?? state?.marksError;
  if (!g) {
    if (err) return <ErrorRow service="eclass" error={err} />;
    return cached ? <p class="empty">eClass has no marks for this course.</p> : <Skeleton lines={6} />;
  }
  const score = CourseScore.of(g);
  return (
    <div style={{ maxWidth: '760px' }}>
      {err && <ErrorRow service="eclass" error={err} />}
      {isStale(snap, 'eclass', cached!.fetchedAt, now) && <Stale at={cached!.fetchedAt} />}
      {score ? <Scored score={score} /> : <Unweighted g={g} />}
      <div style={{ marginTop: '8px' }}>
        <a class="btn" style={{ marginLeft: '-12px' }} href={g.source === 'gradebook' ? gradesUrl(id) : courseUrl(id)} target={eclassTarget}>
          <Icon name="open" /> Open in eClass
        </a>
      </div>
    </div>
  );
}
