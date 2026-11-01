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

/**
 * A course's score so far: eClass's own course total where it gives one, else
 * what the lines add up to. Null from `of` when there is neither.
 *
 * Only a published weight makes a line. A category weight of "-" can't be read
 * back from its marks: the contribution column treats such a category as the
 * whole course, so 81 of 100 "contributes" 81 whatever the category is worth.
 */
export class CourseScore {
  readonly lines: ScoreLine[];
  readonly accumulated: number;
  /** What the score is out of: 100, or what the weights add up to where a course has no total and its weights pass 100. */
  readonly outOf: number;
  /** Items with a weight of 0: shown, but they add nothing. */
  readonly uncounted: GradeItem[];
  /** Items eClass publishes no weight for: they may count, but by how much isn't known. */
  readonly unweighted: GradeItem[];

  private constructor(lines: ScoreLine[], accumulated: number, outOf: number, uncounted: GradeItem[], unweighted: GradeItem[]) {
    this.lines = lines;
    this.accumulated = accumulated;
    this.outOf = outOf;
    this.uncounted = uncounted;
    this.unweighted = unweighted;
  }

  static of(g: CourseGrades): CourseScore | null {
    if (g.source !== 'gradebook') return null;

    const lines: ScoreLine[] = [];
    const uncounted: GradeItem[] = [];
    const unweighted: GradeItem[] = [];
    for (const i of g.items) {
      if (i.weight === 0) uncounted.push(i);
      else if (i.weight == null || i.categoryWeight == null) unweighted.push(i);
      else lines.push(new ScoreLine(i.key, i.name, i.category, (i.weight * i.categoryWeight) / 100, i));
    }
    for (const c of g.categories) {
      const weight = c.weight ?? 0;
      if (weight <= 0 || g.items.some((i) => i.category === c.name)) continue;
      lines.push(new ScoreLine(`category:${c.name}`, c.name, c.name, weight));
    }
    const percent = g.percent ?? null;
    if (percent == null && !lines.length) return null;

    const worth = lines.reduce((s, l) => s + l.worth, 0);
    const accumulated = percent ?? lines.reduce((s, l) => s + l.earned, 0);
    return new CourseScore(lines, accumulated, percent == null && worth > 100 + agree ? worth : 100, uncounted, unweighted);
  }

  /** Whether the weights account for the whole course, so "still open" and "best possible" mean something. */
  get complete(): boolean {
    return Math.abs(this.lines.reduce((s, l) => s + l.worth, 0) - this.outOf) <= 0.5;
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
