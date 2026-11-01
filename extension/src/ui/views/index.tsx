// Which view a route shows, and its title, for the extension's own page
// (main.tsx), which is also the frame the views open in inside eClass (content/view.tsx).

import type { ComponentChildren } from 'preact';
import type { Snapshot } from '../../core/store.ts';
import { AbsenceLimits, CourseDetail, Courses } from './courses.tsx';
import { Deadlines } from './deadlines.tsx';
import { Exams } from './exams.tsx';
import { Grades } from './grades.tsx';
import { Mail } from './mail.tsx';
import { Notifications } from './notifications.tsx';
import { Schedule } from './schedule.tsx';
import { CourseScores } from './scores.tsx';
import { Settings } from './settings.tsx';
import { Today, todayTitle } from './today.tsx';

const titles: Record<string, string> = {
  schedule: 'Schedule',
  deadlines: 'Deadlines',
  courses: 'Attendance',
  grades: 'Grades',
  mail: 'Mail',
  compose: 'Mail',
  exams: 'Exams',
  notifications: 'From eClass',
  settings: 'Settings',
};

export interface View {
  title: string;
  /** Back to the list this view belongs to, for a detail. */
  back: string | null;
  /** Mail lays out its own columns at full height; the rest sit on a padded page. */
  full: boolean;
  body: ComponentChildren;
}

/** The view for a route; unknown routes show Today. */
export function viewFor(route: string[], snap: Snapshot, now: number): View {
  const view = titles[route[0]] || route[0] === 'today' ? route[0] : 'today';
  // 'courses/limits' is every course's absence limit; any other 'courses/<id>' is one course.
  const limits = view === 'courses' && route[1] === 'limits';
  const course = view === 'courses' && route[1] && !limits ? snap.cache.attendance?.value.find((c) => c.course.id === Number(route[1])) : undefined;
  // 'grades/<course>' is one course's marks from eClass.
  const scoresOf = view === 'grades' && route[1] ? Number(route[1]) : null;
  const scoresName = scoresOf == null ? null : (snap.cache.courseGrades?.value.find((g) => g.course.id === scoresOf)?.course.name ?? snap.cache.attendance?.value.find((c) => c.course.id === scoresOf)?.course.name);
  const title = view === 'today' ? todayTitle(now) : limits ? 'Absence limits' : course ? course.course.name : (scoresName ?? titles[view]);
  let body: ComponentChildren;
  switch (view) {
    case 'schedule': body = <Schedule snap={snap} now={now} day={route[1]} />; break;
    case 'deadlines': body = <Deadlines snap={snap} now={now} />; break;
    case 'courses': body = limits ? <AbsenceLimits snap={snap} /> : route[1] ? <CourseDetail snap={snap} now={now} id={Number(route[1])} /> : <Courses snap={snap} now={now} />; break;
    case 'grades': body = scoresOf != null ? <CourseScores key={scoresOf} snap={snap} now={now} id={scoresOf} /> : <Grades snap={snap} now={now} />; break;
    case 'exams': body = <Exams snap={snap} now={now} />; break;
    case 'notifications': body = <Notifications snap={snap} now={now} />; break;
    case 'settings': body = <Settings snap={snap} welcome={false} />; break;
    case 'mail':
    case 'compose': body = <Mail snap={snap} now={now} route={route} />; break;
    default: body = <Today snap={snap} now={now} />;
  }
  // Also for a course no longer listed, and for an open message: narrow, Mail shows it in the list's place.
  const back = view === 'courses' && route[1] ? '#/courses' : scoresOf != null ? '#/grades' : view === 'mail' && route[2] ? `#/mail/${route[1]}` : view === 'notifications' ? '#/today' : null;
  return { title, back, full: view === 'mail' || view === 'compose', body };
}
