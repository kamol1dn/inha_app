// Everything the extension keeps, in chrome.storage.local: the student's
// settings, the last good fetch of each source (shown first, before any
// refresh), and each source's last error. The worker writes; pages and
// content scripts read and redraw on chrome.storage.onChanged.
//
// Each source's state has its own key, so sources finishing together don't
// overwrite each other. A cached value without the fields of its shape reads
// as no cache, as in the app's JsonCache: the next refresh fills it.

import type { ErrorInfo } from './errors.ts';
import { serial } from './serial.ts';
import { stillRefused } from './vault.ts';
import type {
  CourseAttendance,
  CourseGrades,
  Deadline,
  DeadlineKind,
  GradeReport,
  Lesson,
  MailFolder,
  MailFolderCount,
  MailHeader,
  Service,
} from './models.ts';
import type { EclassNotification } from '../services/eclass/parsers.ts';

export type NotifyChannel = 'deadlines' | 'vod' | 'attendance' | 'classes' | 'exams' | 'grades' | 'mail' | 'notices';

export interface Settings {
  classGroup: string;
  /** Subjects the student dropped but EduPage still lists for the group. */
  excludedSubjects: string[];
  /** Allowed absences per eClass course id, as the student set them. Never guessed. */
  absenceLimits: Record<string, number>;
  notify: Record<NotifyChannel, boolean>;
  /** 23:00 to 07:30, as on the phone. */
  quietHours: boolean;
  theme: 'system' | 'light' | 'dark';
  /** Replace eClass's own pages with the new layout. Off = classic eClass, with only the top bar. */
  takeover: boolean;
  /** Show submitted assignments, attempted quizzes and watched VODs on Deadlines. */
  showDone: boolean;
  /** Exam rooms the student set, by exam key. */
  examRooms: Record<string, string>;
  /** What the student marked as done by hand (reminderStem), for work eClass can't track: a paper hand-in, an 'other' event. */
  dismissed: string[];
  /** Deadlines' filters, kept between visits: the kinds on, and one course's name ('' = all). */
  deadlineKinds: DeadlineKind[];
  deadlineCourse: string;
}

/** Everything that is something due. Class periods only on request. */
export const defaultDeadlineKinds: DeadlineKind[] = ['assignment', 'quiz', 'vod', 'other'];

export const defaultSettings: Settings = {
  classGroup: '',
  excludedSubjects: [],
  absenceLimits: {},
  notify: { deadlines: true, vod: true, attendance: true, classes: false, exams: true, grades: true, mail: true, notices: true },
  quietHours: true,
  theme: 'system',
  takeover: true,
  showDone: true,
  examRooms: {},
  dismissed: [],
  deadlineKinds: defaultDeadlineKinds,
  deadlineCourse: '',
};

export interface Cached<T> {
  value: T;
  fetchedAt: number;
}

/** What each cache key holds. */
export interface CacheShape {
  lessons: Lesson[];
  /** Every class group on the timetable, for the picker. */
  classGroups: string[];
  deadlines: Deadline[];
  attendance: CourseAttendance[];
  /** Each course's marks from eClass. `grades` below is the INS letter. */
  courseGrades: CourseGrades[];
  grades: GradeReport;
  notifications: EclassNotification[];
  mailUnread: number;
  mailCounts: Partial<Record<MailFolder, MailFolderCount>>;
  inbox: MailHeader[];
}

export type CacheKey = keyof CacheShape;

/** Which service fills each cache key, for errors and sign-out. */
export const cacheService: Record<CacheKey, Service> = {
  lessons: 'edupage',
  classGroups: 'edupage',
  deadlines: 'eclass',
  attendance: 'eclass',
  courseGrades: 'eclass',
  notifications: 'eclass',
  grades: 'ins',
  mailUnread: 'mail',
  mailCounts: 'mail',
  inbox: 'mail',
};

export interface SourceState {
  error: ErrorInfo | null;
  /** When the last attempt ended, good or bad. */
  at: number;
  /** A refresh is running now. */
  busy: boolean;
  /** eClass only: why some course's marks didn't refresh, while the rest of eClass did. */
  marksError?: ErrorInfo | null;
}

/** Everything in storage the UI reads, as one object. */
export interface Snapshot {
  settings: Settings;
  cache: { [K in CacheKey]?: Cached<CacheShape[K]> };
  state: Partial<Record<Service, SourceState>>;
  /** Services with a saved login, and its username. */
  logins: Partial<Record<Service, string>>;
  /** Saved logins the service refused. Nothing posts them again for a day, unless the student saves a login or retries that service. */
  rejectedLogins: Service[];
}

const SETTINGS = 'settings';
const SCHEMA = 'cache.schema';
const services: Service[] = ['eclass', 'edupage', 'ins', 'mail'];
const stateKey = (s: Service) => `state.${s}`;
const cacheKey = (k: CacheKey) => `cache.${k}`;

/** Bump when a cached shape changes in a way the checks below can't see. */
const cacheSchema = 1;

/** On install and update: a cache written by another version is dropped, so nothing reads an old shape. */
export async function ensureCacheSchema(): Promise<void> {
  const all = await chrome.storage.local.get(null);
  if (all[SCHEMA] === cacheSchema) return;
  await chrome.storage.local.remove(Object.keys(all).filter((k) => k.startsWith('cache.') || k === 'state'));
  await chrome.storage.local.set({ [SCHEMA]: cacheSchema });
}

type Fields = Record<string, unknown>;
const list = (check: (x: Fields) => boolean) => (v: unknown) => Array.isArray(v) && v.every((x) => x != null && check(x as Fields));
const hasCourse = (x: Fields) => typeof (x.course as Fields | null)?.id === 'number';

/** The fields readers rely on, per cache key. */
const shapeOk: Record<CacheKey, (v: unknown) => boolean> = {
  lessons: list((l) => typeof l.weekday === 'number' && typeof l.start === 'string' && typeof l.subject === 'string'),
  classGroups: (v) => Array.isArray(v) && v.every((g) => typeof g === 'string'),
  deadlines: list((d) => typeof d.title === 'string' && typeof d.courseName === 'string' && typeof d.end === 'number' && typeof d.kind === 'string'),
  attendance: list((a) => hasCourse(a) && Array.isArray(a.classes) && Array.isArray(a.vods)),
  courseGrades: list((g) => hasCourse(g) && Array.isArray(g.items) && Array.isArray(g.categories)),
  grades: (v) => Array.isArray((v as Fields | null)?.records),
  notifications: list((n) => typeof n.id === 'number' && typeof n.subject === 'string'),
  mailUnread: (v) => typeof v === 'number',
  mailCounts: (v) => v != null && typeof v === 'object',
  inbox: list((m) => typeof m.id === 'string' && typeof m.subject === 'string'),
};

function cached<K extends CacheKey>(k: K, raw: unknown): Cached<CacheShape[K]> | undefined {
  const c = raw as Cached<CacheShape[K]> | undefined;
  return c != null && typeof c === 'object' && typeof c.fetchedAt === 'number' && shapeOk[k](c.value) ? c : undefined;
}

const settingsWrites = serial();
const stateWrites = serial();

export async function readSettings(): Promise<Settings> {
  const raw = (await chrome.storage.local.get(SETTINGS))[SETTINGS] as Partial<Settings> | undefined;
  return { ...defaultSettings, ...raw, notify: { ...defaultSettings.notify, ...raw?.notify } };
}

export function writeSettings(patch: Partial<Settings>): Promise<Settings> {
  return settingsWrites(async () => {
    const next = { ...(await readSettings()), ...patch };
    await chrome.storage.local.set({ [SETTINGS]: next });
    return next;
  });
}

export async function readCache<K extends CacheKey>(k: K): Promise<Cached<CacheShape[K]> | undefined> {
  return cached(k, (await chrome.storage.local.get(cacheKey(k)))[cacheKey(k)]);
}

export async function writeCache<K extends CacheKey>(k: K, value: CacheShape[K], fetchedAt = Date.now()): Promise<void> {
  await chrome.storage.local.set({ [cacheKey(k)]: { value, fetchedAt } satisfies Cached<CacheShape[K]> });
}

export async function clearCache(keys: CacheKey[]): Promise<void> {
  await chrome.storage.local.remove(keys.map(cacheKey));
}

const stateOf = (all: Record<string, unknown>) =>
  Object.fromEntries(services.filter((s) => all[stateKey(s)]).map((s) => [s, all[stateKey(s)] as SourceState])) as Partial<Record<Service, SourceState>>;

export async function readState(): Promise<Partial<Record<Service, SourceState>>> {
  return stateOf(await chrome.storage.local.get(services.map(stateKey)));
}

export function writeState(service: Service, patch: Partial<SourceState>): Promise<void> {
  return stateWrites(async () => {
    const key = stateKey(service);
    const before = (await chrome.storage.local.get(key))[key] as SourceState | undefined;
    await chrome.storage.local.set({ [key]: { error: null, at: 0, busy: false, ...before, ...patch } });
  });
}

/**
 * When the worker wakes nothing of its own is running, so a busy flag in storage
 * was left by a worker that died or a browser that closed in mid-refresh.
 */
export async function clearStaleBusy(): Promise<void> {
  const state = await readState();
  await Promise.all(services.filter((s) => state[s]?.busy).map((s) => writeState(s, { busy: false })));
}

const cacheKeys: CacheKey[] = ['lessons', 'classGroups', 'deadlines', 'attendance', 'courseGrades', 'grades', 'notifications', 'mailUnread', 'mailCounts', 'inbox'];

export async function readSnapshot(): Promise<Snapshot> {
  const all = await chrome.storage.local.get(null);
  const cache: Snapshot['cache'] = {};
  for (const k of cacheKeys) {
    const c = cached(k, all[cacheKey(k)]);
    if (c) (cache as Record<string, unknown>)[k] = c;
  }
  const vault = (all['vault.v1'] ?? {}) as Record<Service, { username: string; rejected?: number }>;
  return {
    settings: { ...defaultSettings, ...all[SETTINGS], notify: { ...defaultSettings.notify, ...all[SETTINGS]?.notify } },
    cache,
    state: stateOf(all),
    logins: Object.fromEntries(Object.entries(vault).map(([s, v]) => [s, v.username])),
    rejectedLogins: services.filter((s) => stillRefused(vault[s]?.rejected)),
  };
}

/** Calls `onChange` with a fresh snapshot whenever storage changes. Returns the unsubscribe. */
export function watchSnapshot(onChange: (s: Snapshot) => void): () => void {
  let queued = false;
  const listener = (_: unknown, area: string) => {
    if (area !== 'local' || queued) return;
    queued = true;
    // Several keys change together during a sync; redraw once.
    setTimeout(async () => {
      queued = false;
      onChange(await readSnapshot());
    }, 50);
  };
  chrome.storage.onChanged.addListener(listener);
  return () => chrome.storage.onChanged.removeListener(listener);
}
