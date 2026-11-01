// The accumulated score and the what-if calculator, from a course's grades
// page. A port of lib/data/scores.dart: pure, no I/O and no clock.

import { isMarked, plainNumber, type CourseGrades, type GradeItem } from '../core/models.ts';

/** How far apart two figures can be and still be the same one: eClass rounds to two places. */
const agree = 0.05;

/** Something that counts toward the course total: an item, or a category with nothing posted in it yet. */
export class ScoreLine {
  readonly id: string;
  readonly name: string;
  readonly category: string;
  readonly item: GradeItem | null; // null: a category with nothing posted yet
  readonly worth: number; // points out of the course's 100

  constructor(id: string, name: string, category: string, worth: number, item: GradeItem | null = null) {
    this.id = id;
    this.name = name;
    this.category = category;
    this.worth = worth;
    this.item = item;
  }

  get marked(): boolean {
    return this.item != null && isMarked(this.item);
  }

  /** What a score is out of. A category with nothing posted is taken as a %. */
  get max(): number {
    return (this.item?.max ?? 0) > 0 ? this.item!.max! : 100;
  }

  /**
   * The points this line has earned: its share of what it is worth. eClass's
   * own figure is used only where it agrees: on some courses that column holds
   * the raw mark, which is on another scale.
   */
  get earned(): number {
    const i = this.item;
    if (i == null || !isMarked(i)) return 0;
    const share = i.grade == null ? null : (i.grade / this.max) * this.worth;
    const own = i.contribution;
    if (share == null) return own == null ? 0 : Math.min(own, this.worth);
    return own != null && Math.abs(own - share) <= agree ? own : share;
  }
}

/** A course's score so far. Null from `of` when eClass publishes no weights. */
export class CourseScore {
  readonly lines: ScoreLine[];
  readonly accumulated: number;
  /** What the score is out of: 100, or what the weights really add up to where a course's add up to more. */
  readonly outOf: number;
  /** Items with no known weight or a weight of 0: shown, but they add nothing. */
  readonly uncounted: GradeItem[];

  private constructor(lines: ScoreLine[], accumulated: number, outOf: number, uncounted: GradeItem[]) {
    this.lines = lines;
    this.accumulated = accumulated;
    this.outOf = outOf;
    this.uncounted = uncounted;
  }

  static of(g: CourseGrades): CourseScore | null {
    if (g.source !== 'gradebook') return null;

    // A category weight of "-" can still be read back from a marked item:
    // contribution = mark / max × item weight × category weight.
    const inferred = new Map<string, number>();
    for (const i of g.items) {
      const { grade, max, weight, contribution: points } = i;
      if (i.categoryWeight != null || grade == null || max == null || weight == null || points == null) continue;
      if (grade <= 0 || max <= 0 || weight <= 0 || points <= 0) continue;
      const read = points / (((grade / max) * weight) / 100);
      if (read <= 100 + agree && !inferred.has(i.category)) inferred.set(i.category, read); // over 100: a raw mark, not points
    }

    const lines: ScoreLine[] = [];
    const uncounted: GradeItem[] = [];
    for (const i of g.items) {
      const categoryWeight = i.categoryWeight ?? inferred.get(i.category) ?? null;
      const worth = i.weight == null || categoryWeight == null ? 0 : (i.weight * categoryWeight) / 100;
      if (worth > 0) lines.push(new ScoreLine(i.key, i.name, i.category, worth, i));
      else uncounted.push(i);
    }
    for (const c of g.categories) {
      const weight = c.weight ?? 0;
      if (weight <= 0 || g.items.some((i) => i.category === c.name)) continue;
      lines.push(new ScoreLine(`category:${c.name}`, c.name, c.name, weight));
    }
    if (!lines.length) return null;

    // The sum of what is shown, not the total row: on some courses that row adds up the raw marks.
    const sum = lines.reduce((s, l) => s + l.earned, 0);
    const worth = lines.reduce((s, l) => s + l.worth, 0);
    const total = g.total != null && Math.abs(g.total - sum) <= agree ? g.total : sum;
    return new CourseScore(lines, total, worth > 100 + agree ? worth : 100, uncounted);
  }

  /** "28.5 of 100". */
  get line(): string {
    return this.of(this.accumulated);
  }

  /** A score with this one's denominator: "48.5 of 100". */
  of(value: number): string {
    return `${plainNumber(value)} of ${plainNumber(this.outOf)}`;
  }

  /** The points of the course that have been marked so far. */
  get markedWorth(): number {
    return this.lines.filter((l) => l.marked).reduce((s, l) => s + l.worth, 0);
  }

  /** The points still to come: everything unmarked, whole. */
  get openWorth(): number {
    return this.lines.filter((l) => !l.marked).reduce((s, l) => s + l.worth, 0);
  }

  /** The score if everything still open went perfectly. */
  get best(): number {
    return this.accumulated + this.openWorth;
  }

  /** The score with these what-if scores, by ScoreLine id, on lines still open. A score is capped at what its line is out of. */
  withScores(scores: Record<string, number>): number {
    let total = this.accumulated;
    for (const l of this.lines) {
      const s = scores[l.id];
      if (s == null || l.marked) continue;
      total += (Math.min(Math.max(s, 0), l.max) / l.max) * l.worth;
    }
    return total;
  }
}

/**
 * eClass's own course total, in its own range: "Course total on eClass: 157.25 of 300".
 * Null where there is none, or where it says the same as the score already shown.
 */
export function eclassTotalLine(g: CourseGrades, score: CourseScore | null): string | null {
  const { gradeTotal: total, gradeTotalMax: max } = g;
  if (total == null || (score != null && Math.abs(total - score.accumulated) <= agree)) return null;
  return `Course total on eClass: ${plainNumber(total)}${max == null ? '' : ` of ${plainNumber(max)}`}`;
}

/** One line for a course's marks, for the rows that lead to them: "2 of 8 marked". */
export function markedLine(g: CourseGrades): string {
  const marked = g.items.filter(isMarked).length;
  return marked === 0 ? 'Nothing marked yet' : `${marked} of ${g.items.length} marked`;
}

const attendance = /attendance|출석/i;

/**
 * Attendance marks tick over after every class and the Attendance channel
 * already covers absences, so they are shown but never announced.
 */
export const isAttendanceMark = (i: GradeItem) => attendance.test(i.name) || attendance.test(i.category);
