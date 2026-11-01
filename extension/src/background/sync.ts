// Refreshing each source into the cache. A port of AppData's refreshes
// (lib/data/app_data.dart): each source fails on its own and keeps its last
// good data, so one service being down never blanks the others.

import type { Credentials } from '../core/credentials.ts';
import { errorInfo } from '../core/errors.ts';
import type { Course, Deadline, Service } from '../core/models.ts';
import { readCache, readSettings, readState, writeCache, writeState, type CacheKey } from '../core/store.ts';
import { readLogin } from '../core/vault.ts';
import { EclassClient } from '../services/eclass/client.ts';
import { EdupageClient } from '../services/edupage/client.ts';
import { InsClient } from '../services/ins/client.ts';
import { EwsClient } from '../services/mail/ews.ts';
import { DAY, HOUR, MIN } from '../data/format.ts';
import { announceNewMail } from './notify.ts';

const creds = (s: Service): Promise<Credentials | null> => readLogin(s);

export const eclass = new EclassClient(creds);
export const edupage = new EdupageClient();
export const ins = new InsClient(creds);
export const mail = new EwsClient(creds);

/** How old each source may get before the alarm refreshes it. */
export const refreshEvery: Record<Service, number> = {
  mail: 5 * MIN,
  eclass: 30 * MIN,
  ins: 12 * HOUR,
  edupage: DAY,
};

/** The mail page shown first and cached. */
export const mailPageSize = 30;

/** Thrown when a source can't run until the student sets something up. */
export class SetupNeeded extends Error {
  constructor(message: string) {
    super(message);
    this.name = 'SetupNeeded';
  }
}

const running = new Map<Service, Promise<void>>();

/** Runs one source's refresh, recording busy/error state. A refresh already running is shared. */
export function refresh(service: Service): Promise<void> {
  const existing = running.get(service);
  if (existing) return existing;
  const run = (async () => {
    await writeState(service, { busy: true });
    try {
      await fetchers[service]();
      await writeState(service, { busy: false, error: null, at: Date.now() });
    } catch (e) {
      await writeState(service, { busy: false, error: errorInfo(e), at: Date.now() });
    }
  })().finally(() => running.delete(service));
  running.set(service, run);
  return run;
}

/** Refreshes the sources whose cache is older than refreshEvery (all of them with force). */
export async function refreshDue(force = false): Promise<void> {
  const state = await readState();
  const now = Date.now();
  const due = (Object.keys(refreshEvery) as Service[]).filter((s) => {
    if (force) return true;
    const last = state[s]?.at ?? 0;
    // A failed source retries at the mail pace, so a blip doesn't hide eClass for half an hour.
    const every = state[s]?.error ? Math.min(refreshEvery[s], 10 * MIN) : refreshEvery[s];
    return now - last >= every;
  });
  await Promise.all(due.map(refresh));
}

const fetchers: Record<Service, () => Promise<void>> = {
  async edupage() {
    const settings = await readSettings();
    const { lessons, groups } = await edupage.lessonsAndGroups(settings.classGroup, settings.excludedSubjects);
    await writeCache('classGroups', groups);
    if (!settings.classGroup) throw new SetupNeeded('Choose your class group in Settings.');
    await writeCache('lessons', lessons);
  },

  async eclass() {
    // Deadlines and attendance share one login, so they refresh together.
    const [deadlines, courses] = await Promise.all([eclass.upcoming(), eclass.courses()]);
    const [withDone, attendance] = await Promise.all([
      withSubmissions(deadlines),
      Promise.all(courses.map((c) => eclass.attendance(c))),
    ]);
    await writeCache('deadlines', withDone);
    await writeCache('attendance', attendance);
    await refreshMarks(courses);
    try {
      await writeCache('notifications', await eclass.notifications());
    } catch {
      // The popup notifications are a nicety; deadlines and attendance already landed.
    }
  },

  // The browser may refuse INS's expired certificate here (a NetworkError
  // with `certificate`); then an INS tab, once the student chose Proceed, can
  // still read the grades (content/ins.ts reports them through insReport).
  async ins() {
    await writeCache('grades', await ins.grades());
  },

  async mail() {
    const [unread, counts, inbox] = await Promise.all([
      mail.unreadCount(),
      mail.folderCounts().catch(() => null),
      mail.folder('inbox', mailPageSize, 0),
    ]);
    await writeCache('mailUnread', unread);
    if (counts) await writeCache('mailCounts', counts);
    await writeCache('inbox', inbox);
    await announceNewMail(inbox);
  },
};

/**
 * Every course's marks. A course whose pages fail keeps what the cache knew,
 * and the failure is kept apart from eClass's own state: deadlines and
 * attendance have landed by now, and only Scores has something to say about it.
 */
async function refreshMarks(courses: Course[]): Promise<void> {
  const known = new Map((await readCache('courseGrades'))?.value.map((g) => [g.course.id, g]) ?? []);
  let failed: unknown = null;
  const marks = await Promise.all(
    courses.map((c) =>
      eclass.courseGrades(c).catch((e) => {
        failed ??= e;
        return known.get(c.id) ?? null;
      }),
    ),
  );
  await writeCache('courseGrades', marks.filter((g) => g != null));
  await writeState('eclass', { marksError: failed ? errorInfo(failed) : null });
}

/**
 * Marks each assignment and quiz handed in or not, from its own page. A page
 * that fails keeps what the cache knew about that item, so a network blip
 * never brings back reminders for submitted work.
 */
async function withSubmissions(fresh: Deadline[]): Promise<Deadline[]> {
  const known = new Map((await readCache('deadlines'))?.value.filter((d) => d.moduleId != null).map((d) => [d.moduleId!, d]) ?? []);
  return Promise.all(
    fresh.map(async (d) => {
      if (d.kind !== 'assignment' && d.kind !== 'quiz') return d;
      try {
        const s = await eclass.submission(d);
        return s ? { ...d, done: s.done, doneAt: s.done ? s.at : null } : d;
      } catch {
        const before = d.moduleId == null ? undefined : known.get(d.moduleId);
        return before ? { ...d, done: before.done, doneAt: before.doneAt } : d;
      }
    }),
  );
}

/** Cache keys per service, dropped on sign-out so nothing from that account stays. */
export const serviceCache: Record<Service, CacheKey[]> = {
  eclass: ['deadlines', 'attendance', 'courseGrades', 'notifications'],
  ins: ['grades'],
  mail: ['mailUnread', 'mailCounts', 'inbox'],
  edupage: ['lessons', 'classGroups'],
};
