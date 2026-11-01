// Shows what planNotifications (src/data/rules.ts) calls for, as the app's
// notifier does (docs/NOTIFICATIONS.md): the same rules, switches, quiet hours
// and stable keys, sent once each. Each pass posts what is due and sets one
// alarm for the next reminder, so reminders go out on time while the browser
// runs; with it closed, the most urgent missed one goes out when it opens.
// New-mail notifications are an addition the app doesn't have (switchable).

import { isMarked, type CourseGrades, type MailHeader } from '../core/models.ts';
import { readCache, readSettings } from '../core/store.ts';
import { classFreeDays } from '../data/exams.ts';
import { gradeCourseId, gradeKey, planNotifications, sentKeyRetention } from '../data/rules.ts';
import { courseUrl, itemUrl } from '../services/eclass/links.ts';

const SENT = 'notify.sent'; // key -> when it was sent
const SEEN_MAIL = 'notify.seenMail'; // inbox ids already announced, or known when mail was first set up
const TARGETS = 'notify.targets'; // notification id -> what a click opens
const SEEN_COURSES = 'notify.seenCourses'; // courses whose attendance was seen with sessions in it
const SEEN_GRADES = 'notify.seenGrades'; // course id -> item key -> the last mark announced
export const REMINDER_ALARM = 'reminder';

type Target = { url: string } | { app: string };

async function getMap<T>(key: string): Promise<Record<string, T>> {
  return ((await chrome.storage.local.get(key))[key] as Record<string, T> | undefined) ?? {};
}

async function show(id: string, title: string, message: string, silent: boolean, target: Target | null): Promise<void> {
  const basic = { type: 'basic' as const, iconUrl: chrome.runtime.getURL('icons/icon.png'), title, message };
  try {
    await chrome.notifications.create(id, { ...basic, silent, priority: 1 });
  } catch {
    // Firefox and Zen take only the basic options (no silent, no priority).
    await chrome.notifications.create(id, basic);
  }
  if (target) {
    const targets = await getMap<Target>(TARGETS);
    targets[id] = target;
    // Keep the last 100; older notifications are long gone from the tray.
    const ids = Object.keys(targets);
    for (const old of ids.slice(0, Math.max(0, ids.length - 100))) delete targets[old];
    await chrome.storage.local.set({ [TARGETS]: targets });
  }
}

/** Posts every reminder that is due now and was not sent before. */
export async function postDueReminders(now = Date.now()): Promise<void> {
  const settings = await readSettings();
  const [deadlines, attendance, lessons, courseGrades] = await Promise.all([readCache('deadlines'), readCache('attendance'), readCache('lessons'), readCache('courseGrades')]);
  const sent = await getMap<number>(SENT);
  const seenGrades = await getMap<Record<string, string>>(SEEN_GRADES);

  // No first-run flood: the first time a course's attendance is seen with
  // sessions in it (a first install, a new semester), its absences count as
  // sent without a notification. Only absences that appear after that are announced.
  const seenCourses = new Set(((await chrome.storage.local.get(SEEN_COURSES))[SEEN_COURSES] as number[] | undefined) ?? []);
  const firstSight = new Set<number>();
  for (const a of attendance?.value ?? []) {
    if (a.classes.length && !seenCourses.has(a.course.id)) {
      firstSight.add(a.course.id);
      seenCourses.add(a.course.id);
    }
  }
  await chrome.storage.local.set({ [SEEN_COURSES]: [...seenCourses] });

  const planned = planNotifications({
    now,
    deadlines: deadlines?.value,
    attendance: attendance?.value,
    lessons: lessons?.value,
    courseGrades: courseGrades?.value,
    seenGrades,
    sentKeys: new Set(Object.keys(sent)),
    quiet: settings.quietHours,
    absenceLimits: settings.absenceLimits,
    classFree: classFreeDays(),
    itemUrl,
    courseUrl,
  });
  const blocked = !(await allowed());
  let next: number | null = null;
  for (const n of planned) {
    const course = absenceCourse(n.key);
    if (course != null && firstSight.has(course)) {
      sent[n.key] = now; // even one quiet hours pushed to the morning
      continue;
    }
    // Marks of a course seen for the first time are a baseline, and with Grades
    // off they are recorded too, so turning it on doesn't announce old ones.
    const graded = gradeCourseId(n.key);
    if (graded != null && (!settings.notify.grades || !seenGrades[graded])) {
      sent[n.key] = now;
      continue;
    }
    if (n.when > now) {
      // A scheduled reminder only counts as sent once its time has come, so
      // each pass re-plans it with fresh text, or drops it (watched, moved).
      if (settings.notify[n.channel]) next ??= n.when;
      continue;
    }
    // Switched off: remembered anyway, so turning it on doesn't announce old ones.
    if (!settings.notify[n.channel]) {
      sent[n.key] = now;
      continue;
    }
    if (graded != null && blocked) continue; // stays new until it can go out
    try {
      await show(n.key, n.title, n.body, n.quiet, target(n.key, n.url));
      sent[n.key] = now;
    } catch (e) {
      // Not recorded, so the next pass tries again; the others still go out.
      console.warn(`IUT: couldn't show ${n.key}`, e);
    }
  }
  for (const [k, at] of Object.entries(sent)) if (now - at > sentKeyRetention) delete sent[k];
  await chrome.storage.local.set({ [SENT]: sent });
  if (courseGrades) await advanceSeenGrades(courseGrades.value, seenGrades, sent);

  // chrome.alarms fires no sooner than 30 s ahead; a slightly late reminder is fine.
  if (next != null) await chrome.alarms.create(REMINDER_ALARM, { when: Math.max(next, now + 30_000) });
  else await chrome.alarms.clear(REMINDER_ALARM);
}

/**
 * Moves on to the marks that went out or were recorded. A mark that could not
 * be delivered, or is waiting out the night, stays new for the next pass.
 * Marks stay here when a page stops showing them (a course's grades page
 * closing again), so they aren't news when it comes back. A course with nothing
 * marked gets its entry too: a mark appearing there later is news, not a baseline.
 */
async function advanceSeenGrades(courses: CourseGrades[], seen: Record<string, Record<string, string>>, sent: Record<string, number>): Promise<void> {
  for (const g of courses) {
    const marks = (seen[g.course.id] ??= {});
    for (const item of g.items) {
      if (isMarked(item) && gradeKey(g.course.id, item, marks[item.key]) in sent) marks[item.key] = item.mark;
    }
  }
  await chrome.storage.local.set({ [SEEN_GRADES]: seen });
}

/** Signing out of eClass forgets what was announced, along with the marks. */
export const forgetSeenGrades = () => chrome.storage.local.remove(SEEN_GRADES);

/** False when the browser blocks this extension's notifications. Firefox and Zen can't say, so they count as allowed. */
async function allowed(): Promise<boolean> {
  if (!('getPermissionLevel' in chrome.notifications)) return true;
  return new Promise((resolve) => chrome.notifications.getPermissionLevel((level) => resolve(level !== 'denied')));
}

/** The eClass course id in an absence key, or null for another key. */
function absenceCourse(key: string): number | null {
  if (!key.startsWith('absent:')) return null;
  const id = Number(key.slice('absent:'.length).split('|')[0]);
  return Number.isFinite(id) ? id : null;
}

/**
 * What a click opens, as on the phone: a deadline or VOD its eClass page (else
 * Deadlines), an absence its course, a mark the course's scores, a class
 * Schedule on that day.
 */
function target(key: string, url: string | null): Target {
  const course = absenceCourse(key);
  if (course != null) return { app: `courses/${course}` };
  const graded = gradeCourseId(key);
  if (graded != null) return { app: `grades/${graded}` };
  if (key.startsWith('class:')) return { app: `schedule/${key.slice('class:'.length).split('|')[0]}` };
  return url ? { url } : { app: 'deadlines' };
}

/** Announces unread inbox mail that arrived since the last look. The first sync only learns what is there. */
export async function announceNewMail(inbox: MailHeader[]): Promise<void> {
  const settings = await readSettings();
  const stored = (await chrome.storage.local.get(SEEN_MAIL))[SEEN_MAIL] as string[] | undefined;
  const seen = new Set(stored ?? []);
  const fresh = stored ? inbox.filter((m) => m.unread && !seen.has(m.id)) : [];
  await chrome.storage.local.set({ [SEEN_MAIL]: [...new Set([...inbox.map((m) => m.id), ...seen])].slice(0, 300) });
  if (!settings.notify.mail || !fresh.length) return;
  if (fresh.length === 1) {
    const m = fresh[0];
    await show(`mail:${m.id}`, m.from || 'New mail', m.subject || '(no subject)', false, { app: `mail/inbox/${encodeURIComponent(m.id)}` });
  } else {
    await show(
      `mail:${fresh[0].id}`,
      `${fresh.length} new messages`,
      fresh.slice(0, 3).map((m) => `${m.from}: ${m.subject}`).join('\n'),
      false,
      { app: 'mail/inbox' },
    );
  }
}

/** A click opens the item: an eClass page in a tab, or a view of the app. */
export async function onNotificationClick(id: string): Promise<void> {
  const target = (await getMap<Target>(TARGETS))[id];
  chrome.notifications.clear(id);
  if (!target) return;
  const url = 'url' in target ? target.url : `https://eclass.inha.ac.kr/#/${target.app}`;
  const win = await chrome.windows.getLastFocused().catch(() => null);
  await chrome.tabs.create({ url, windowId: win?.id });
}
