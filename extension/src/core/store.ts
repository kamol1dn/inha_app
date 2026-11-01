// Everything the extension keeps, in chrome.storage.local: the student's
// settings, the last good fetch of each source (shown first, before any
// refresh), and each source's last error. The worker writes; pages and
// content scripts read and redraw on chrome.storage.onChanged.

import type { ErrorInfo } from './errors.ts';
import type {
  CourseAttendance,
  CourseGrades,
  Deadline,
  GradeReport,
  Lesson,
  MailFolder,
  MailFolderCount,
  MailHeader,
  Service,
} from './models.ts';
import type { EclassNotification } from '../services/eclass/parsers.ts';

export type NotifyChannel = 'deadlines' | 'vod' | 'attendance' | 'classes' | 'grades' | 'mail';

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
}

export const defaultSettings: Settings = {
  classGroup: '',
  excludedSubjects: [],
  absenceLimits: {},
  notify: { deadlines: true, vod: true, attendance: true, classes: false, grades: true, mail: true },
  quietHours: true,
  theme: 'system',
  takeover: true,
  showDone: true,
  examRooms: {},
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
}

const SETTINGS = 'settings';
const STATE = 'state';
const cacheKey = (k: CacheKey) => `cache.${k}`;

export async function readSettings(): Promise<Settings> {
  const raw = (await chrome.storage.local.get(SETTINGS))[SETTINGS] as Partial<Settings> | undefined;
  return { ...defaultSettings, ...raw, notify: { ...defaultSettings.notify, ...raw?.notify } };
}

export async function writeSettings(patch: Partial<Settings>): Promise<Settings> {
  const next = { ...(await readSettings()), ...patch };
  await chrome.storage.local.set({ [SETTINGS]: next });
  return next;
}

export async function readCache<K extends CacheKey>(k: K): Promise<Cached<CacheShape[K]> | undefined> {
  return (await chrome.storage.local.get(cacheKey(k)))[cacheKey(k)] as Cached<CacheShape[K]> | undefined;
}

export async function writeCache<K extends CacheKey>(k: K, value: CacheShape[K], fetchedAt = Date.now()): Promise<void> {
  await chrome.storage.local.set({ [cacheKey(k)]: { value, fetchedAt } satisfies Cached<CacheShape[K]> });
}

export async function clearCache(keys: CacheKey[]): Promise<void> {
  await chrome.storage.local.remove(keys.map(cacheKey));
}

export async function readState(): Promise<Partial<Record<Service, SourceState>>> {
  return ((await chrome.storage.local.get(STATE))[STATE] as Partial<Record<Service, SourceState>> | undefined) ?? {};
}

export async function writeState(service: Service, patch: Partial<SourceState>): Promise<void> {
  const all = await readState();
  all[service] = { error: null, at: 0, busy: false, ...all[service], ...patch };
  await chrome.storage.local.set({ [STATE]: all });
}

const cacheKeys: CacheKey[] = ['lessons', 'classGroups', 'deadlines', 'attendance', 'courseGrades', 'grades', 'notifications', 'mailUnread', 'mailCounts', 'inbox'];

export async function readSnapshot(): Promise<Snapshot> {
  const all = await chrome.storage.local.get(null);
  const cache: Snapshot['cache'] = {};
  for (const k of cacheKeys) if (all[cacheKey(k)]) (cache as Record<string, unknown>)[k] = all[cacheKey(k)];
  const vault = (all['vault.v1'] ?? {}) as Record<Service, { username: string }>;
  return {
    settings: { ...defaultSettings, ...all[SETTINGS], notify: { ...defaultSettings.notify, ...all[SETTINGS]?.notify } },
    cache,
    state: all[STATE] ?? {},
    logins: Object.fromEntries(Object.entries(vault).map(([s, v]) => [s, v.username])),
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
