// Refreshing each source into the cache. A port of AppData's refreshes
// (lib/data/app_data.dart): each source fails on its own and keeps its last
// good data, so one service being down never blanks the others.

import type { Credentials } from '../core/credentials.ts';
import { errorInfo, LoginRequired, NetworkError, OtherAccount } from '../core/errors.ts';
import { request } from '../core/http.ts';
import { serviceLabel, type Course, type CourseAttendance, type Deadline, type Service } from '../core/models.ts';
import { missingHosts } from '../core/permissions.ts';
import { clearCache, readCache, readSettings, readState, writeCache, writeState, type CacheKey, type CacheShape } from '../core/store.ts';
import { clearLoginRejected, loginRejected, markLoginRejected, readLogin } from '../core/vault.ts';
import { EclassClient, withKnownUpcoming } from '../services/eclass/client.ts';
import { EdupageClient } from '../services/edupage/client.ts';
import { InsClient } from '../services/ins/client.ts';
import { defaultEndpoint, EwsClient } from '../services/mail/ews.ts';
import { DAY, HOUR, MIN } from '../data/format.ts';
import { announceNewMail, announceNotices, forgetNotified } from './notify.ts';

const ECLASS_STOP = 'eclass.stopped'; // set while nothing may sign the browser in to eClass
const ECLASS_OWNER = 'eclass.owner'; // the Moodle user id the cached eClass data belongs to

/**
 * 'logout': sign-out here hasn't reached eClass yet (offline), so the session is
 * still to be ended before anything is read. 'out': the session is over, by
 * sign-out here or the student's own click on Log out. Either way the saved
 * login isn't used; seeing a live session again means they signed in themselves.
 */
type EclassStop = 'logout' | 'out';

export const eclassStop = async (): Promise<EclassStop | null> =>
  ((await chrome.storage.local.get(ECLASS_STOP))[ECLASS_STOP] as EclassStop | undefined) ?? null;

export const setEclassStop = async (stop: EclassStop | null): Promise<void> => {
  if (stop) await chrome.storage.local.set({ [ECLASS_STOP]: stop });
  else await chrome.storage.local.remove(ECLASS_STOP);
};

/** The next session seen on eClass starts the cache afresh. */
export const forgetEclassOwner = () => chrome.storage.local.remove(ECLASS_OWNER);

/** The login clients may post: none when the service refused it, or while eClass is stopped. */
export async function usableLogin(s: Service): Promise<Credentials | null> {
  if (await loginRejected(s)) return null;
  if (s === 'eclass' && (await eclassStop())) return null;
  return readLogin(s);
}

export const eclass = new EclassClient(usableLogin, request, markLoginRejected);
export const edupage = new EdupageClient();
export const ins = new InsClient(usableLogin, { onRejected: markLoginRejected });
export const mail = new EwsClient(usableLogin, request, defaultEndpoint, markLoginRejected);

/** How old each source may get before the alarm refreshes it. */
export const refreshEvery: Record<Service, number> = {
  mail: 5 * MIN,
  eclass: 30 * MIN,
  ins: 12 * HOUR,
  edupage: DAY,
};

const services = Object.keys(refreshEvery) as Service[];

/** The alarm fires every 5 minutes, but `at` is when the last attempt ended, so a source due every 5 needs this much slack not to run on every other tick. */
const tickSlack = MIN;

/** The mail page shown first and cached. */
export const mailPageSize = 30;

/** Thrown when a source can't run until the student sets something up. */
export class SetupNeeded extends Error {
  constructor(message: string) {
    super(message);
    this.name = 'SetupNeeded';
  }
}

/** A refresh overtaken by a sign-out or a new login: what it fetched must not land. */
class Overtaken extends Error {}

interface Run {
  readonly live: boolean;
  check(): void;
  write<K extends CacheKey>(k: K, value: CacheShape[K]): Promise<void>;
}

const generations: Record<Service, number> = { eclass: 0, edupage: 0, ins: 0, mail: 0 };

function startRun(service: Service): Run {
  const generation = generations[service];
  const run: Run = {
    get live() {
      return generation === generations[service];
    },
    check() {
      if (!run.live) throw new Overtaken();
    },
    async write(k, value) {
      run.check();
      await writeCache(k, value);
    },
  };
  return run;
}

const running = new Map<Service, Promise<void>>();
const queued = new Map<Service, Promise<void>>();

/**
 * Drops any refresh of this service still in flight: it keeps going, but nothing
 * it found gets written, and the next refresh starts fresh rather than sharing it.
 */
export async function startOver(service: Service): Promise<void> {
  generations[service]++;
  running.delete(service);
  queued.delete(service);
  await writeState(service, { busy: false });
}

/**
 * Chrome ends a worker 30 s after its last extension API call, and a fetch
 * doesn't count, so a slow refresh started by an alarm would die halfway.
 */
function keepAlive(): () => void {
  const timer = setInterval(() => void chrome.runtime.getPlatformInfo?.().catch(() => {}), 20_000);
  return () => clearInterval(timer);
}

/** Runs work the worker has to live through, such as an attachment on a slow link. */
export async function keptAlive<T>(work: () => Promise<T>): Promise<T> {
  const stopKeepingAlive = keepAlive();
  try {
    return await work();
  } finally {
    stopKeepingAlive();
  }
}

/**
 * Runs one source's refresh, recording busy/error state. A refresh already
 * running is shared. With `again`, the caller has changed something that run
 * already read (a class group, a deleted message), so one more run follows it.
 */
export function refresh(service: Service, again = false): Promise<void> {
  const existing = running.get(service);
  if (existing) {
    if (!again) return existing;
    let next = queued.get(service);
    if (!next) {
      const generation = generations[service];
      next = existing.then(() => {
        if (generation !== generations[service]) return;
        queued.delete(service);
        return refresh(service);
      });
      queued.set(service, next);
    }
    return next;
  }
  const run = startRun(service);
  const stopKeepingAlive = keepAlive();
  const job: Promise<void> = (async () => {
    await writeState(service, { busy: true });
    try {
      await fetchers[service](run);
      if (run.live) await writeState(service, { busy: false, error: null, at: Date.now() });
    } catch (e) {
      const info = errorInfo(await explained(e, service));
      if (run.live) await writeState(service, { busy: false, error: info, at: Date.now() });
    }
  })().finally(() => {
    stopKeepingAlive();
    if (running.get(service) === job) running.delete(service);
  });
  running.set(service, job);
  return job;
}

const hostOf: Record<Service, string> = { eclass: 'eclass.inha.ac.kr', edupage: 'iut.edupage.org', ins: 'ins.inha.uz', mail: 'mail.inha.uz' };

/** Without its host permission (Firefox can leave it off) every request fails as if offline, or for INS as if the certificate were at fault. */
async function explained(e: unknown, service: Service): Promise<unknown> {
  if (!(e instanceof NetworkError) || e.status) return e;
  const missing = await missingHosts().catch(() => []);
  return missing.some((o) => o.includes(hostOf[service])) ? new SetupNeeded(`Allow this extension to reach ${serviceLabel[service]} in Settings.`) : e;
}

/** The student asked for this service again: a login it refused gets one more try. */
export async function retryLogin(service: Service): Promise<void> {
  await clearLoginRejected(service);
  if (service === 'eclass') eclass.forgetRejected();
  if (service === 'ins') ins.forgetRejected();
  if (service === 'mail') mail.forgetRejected();
}

/** Refreshes the sources whose cache is older than refreshEvery (all of them with force). */
export async function refreshDue(force = false): Promise<void> {
  const state = await readState();
  const refused = new Set<Service>();
  for (const s of services) if (await loginRejected(s)) refused.add(s);
  const now = Date.now();
  const due = services.filter((s) => {
    if (force) return true;
    // A refused login stays unposted anyway. eClass still looks: a session the student opened themselves needs no password.
    if (refused.has(s) && s !== 'eclass') return false;
    const last = state[s]?.at ?? 0;
    // A failed source retries at the mail pace, so a blip doesn't hide eClass for half an hour.
    const failed = state[s]?.error != null && state[s]?.error?.name !== 'SetupNeeded';
    const every = failed ? Math.min(refreshEvery[s], 10 * MIN) : refreshEvery[s];
    return now - last >= every - tickSlack;
  });
  await Promise.all(due.map((s) => refresh(s, force)));
}

const fetchers: Record<Service, (run: Run) => Promise<void>> = {
  async edupage(run) {
    const settings = await readSettings();
    const { lessons, groups, unknownGroup } = await edupage.lessonsAndGroups(settings.classGroup, settings.excludedSubjects);
    await run.write('classGroups', groups);
    if (!settings.classGroup) throw new SetupNeeded('Choose your class group in Settings.');
    if (unknownGroup) {
      // Last term's lessons: no rooms or reminders from them.
      run.check();
      await clearCache(['lessons']);
      throw new SetupNeeded("Your class group isn't on the timetable. Choose it in Settings.");
    }
    await run.write('lessons', lessons);
  },

  // Each part lands as soon as it is fetched and fails on its own, as AppData's
  // separate runs do; the first error is reported after everything else landed.
  async eclass(run) {
    const stop = await eclassStop();
    if (stop === 'logout') {
      await eclass.logout();
      await setEclassStop('out');
    }

    let failed: unknown = null;
    let courses: Course[] | null = null;
    try {
      courses = await eclass.courses();
    } catch (e) {
      if (e instanceof LoginRequired) throw e;
      failed = e;
    }
    if (courses) {
      run.check();
      await checkSessionOwner();
      if (stop) await setEclassStop(null); // a live session: they signed in again
    }

    try {
      const known = (await readCache('deadlines'))?.value ?? [];
      const found = await eclass.allUpcoming(courses ?? []);
      // A page that failed keeps what it last showed, until it answers again.
      await run.write('deadlines', await withSubmissions(withKnownUpcoming(found, known, courses, Date.now())));
      failed ??= found.failed;
    } catch (e) {
      if (e instanceof LoginRequired || e instanceof Overtaken) throw e;
      failed ??= e;
    }

    if (courses) {
      const known = new Map((await readCache('attendance'))?.value.map((a) => [a.course.id, a]) ?? []);
      const results = await Promise.allSettled(courses.map((c) => eclass.attendance(c)));
      const attendance = results.flatMap((r, i): CourseAttendance[] => {
        if (r.status === 'fulfilled') return [r.value];
        failed ??= r.reason;
        const before = known.get(courses![i].id);
        return before ? [before] : [];
      });
      await run.write('attendance', attendance);
      await refreshMarks(run, courses);
    }

    try {
      const notices = await eclass.notifications();
      await run.write('notifications', notices);
      await announceNotices(notices);
    } catch (e) {
      if (e instanceof Overtaken) throw e;
      // The popup notifications are a nicety; the rest already landed.
    }
    if (failed != null) throw failed;
  },

  // The browser may refuse INS's expired certificate here (a NetworkError
  // with `certificate`); then an INS tab, once the student chose Proceed, can
  // still read the grades (content/ins.ts reports them through insReport).
  async ins(run) {
    try {
      await run.write('grades', await ins.grades());
    } catch (e) {
      // With no login saved, the certificate isn't what stands in the way.
      if (e instanceof NetworkError && e.certificate && !(await readLogin('ins'))) throw new LoginRequired('ins', 'No INS login saved');
      throw e;
    }
  },

  async mail(run) {
    // Alone first: with a stale password this is the one failed logon the refresh costs.
    const unread = await mail.unreadCount();
    const [counts, inbox] = await Promise.all([mail.folderCounts().catch(() => null), mail.folder('inbox', mailPageSize, 0)]);
    await run.write('mailUnread', unread);
    if (counts) await run.write('mailCounts', counts);
    await run.write('inbox', inbox);
    await announceNewMail(inbox);
  },
};

/**
 * The cached eClass data belongs to one person. A browser now signed in as
 * someone else, with a login saved, isn't read: that session isn't the student's.
 * With none saved, the browser's session is all there is, so its owner takes the
 * cache over and the last one's data goes. A page that doesn't name its user
 * changes nothing.
 */
async function checkSessionOwner(): Promise<void> {
  const user = eclass.sessionUser;
  if (user == null) return;
  const owner = (await chrome.storage.local.get(ECLASS_OWNER))[ECLASS_OWNER] as number | undefined;
  if (owner === user) return;
  if (owner != null) {
    if (await readLogin('eclass')) throw new OtherAccount();
    await clearCache(serviceCache.eclass);
    await forgetNotified('eclass');
  }
  await chrome.storage.local.set({ [ECLASS_OWNER]: user });
}

/**
 * Every course's marks. A course whose pages fail keeps what the cache knew,
 * and the failure is kept apart from eClass's own state: deadlines and
 * attendance have landed by now, and only Scores has something to say about it.
 */
async function refreshMarks(run: Run, courses: Course[]): Promise<void> {
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
  await run.write('courseGrades', marks.filter((g) => g != null));
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
