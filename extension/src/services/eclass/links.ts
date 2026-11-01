// Pages on eClass the extension links to. A port of eclass_links.dart; in the
// browser these open with the student's own eClass session.

import type { Deadline } from '../../core/models.ts';

export const eclassBase = 'https://eclass.inha.ac.kr';

/** A course's main page. */
export const courseUrl = (courseId: number) => `${eclassBase}/course/view.php?id=${courseId}`;

/** A course's grades page. A professor can close it (404). */
export const gradesUrl = (courseId: number) => `${eclassBase}/grade/report/user/index.php?id=${courseId}`;

/**
 * The activity behind a calendar event (`/mod/<type>/view.php?id=<moduleId>`),
 * or null for a course-level event that has none. Cached events without a
 * module type fall back on their kind.
 */
export function itemUrl(d: Deadline): string | null {
  if (d.moduleId == null) return null;
  const type =
    d.moduleType ??
    (d.kind === 'assignment' ? 'assign' : d.kind === 'quiz' ? 'quiz' : d.kind === 'vod' ? 'vod' : null);
  if (type == null) return null;
  return `${eclassBase}/mod/${type}/view.php?id=${d.moduleId}`;
}
