// What the views compute from the snapshot: a day's classes or exams.

import type { Lesson } from '../core/models.ts';
import type { Snapshot } from '../core/store.ts';
import { classFreeDays, currentPeriod, matchExams, studentCourses, type ExamMatch, type MyExam } from '../data/exams.ts';
import { atTime, dayKey, isoWeekday } from '../data/format.ts';

const classFree = classFreeDays();

/** The student's exams in the period on show at `now`, or null outside every period. */
export function examMatch(snap: Snapshot, now: number): ExamMatch | null {
  const period = currentPeriod(now);
  if (!period) return null;
  const courses = studentCourses(snap.cache.lessons?.value ?? [], snap.cache.attendance?.value ?? []);
  return matchExams(period, courses, snap.settings.classGroup, snap.settings.examRooms);
}

export interface DayClass {
  start: number;
  end: number;
  lesson: Lesson;
}

/** The timetable's classes on `day`, in time order. None in an exam week, whatever the timetable says. */
export function classesOn(day: Date, lessons: Lesson[]): DayClass[] {
  if (classFree.has(dayKey(day))) return [];
  const wd = isoWeekday(day);
  return lessons
    .filter((l) => l.weekday === wd)
    .flatMap((lesson) => {
      const start = atTime(day, lesson.start), end = atTime(day, lesson.end);
      return start && end ? [{ start: start.getTime(), end: end.getTime(), lesson }] : [];
    })
    .sort((a, b) => a.start - b.start);
}

export const isClassFree = (day: Date) => classFree.has(dayKey(day));

/** The student's exams on `day`, in time order. */
export const examsOn = (day: Date, match: ExamMatch | null): MyExam[] =>
  (match?.exams ?? []).filter((e) => dayKey(e.exam.start) === dayKey(day)).sort((a, b) => a.exam.start - b.exam.start);
