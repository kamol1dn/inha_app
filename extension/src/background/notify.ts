// Shows what planNotifications (src/data/rules.ts) calls for, as the app's
// notifier does (docs/NOTIFICATIONS.md): the same rules, switches, quiet hours
// and stable keys, sent once each. Each pass posts what is due and sets one
// alarm for the next reminder, so reminders go out on time while the browser
// runs; with it closed, the most urgent missed one goes out when it opens.
// New-mail and eClass notifications are additions the app doesn't have (switchable).
//
// Passes come from the alarm, a page's sync and a saved login at once. They run
// one at a time: two overlapping ones can each find an absence unsent and a
// course already known, and announce a semester of old absences.

import { isMarked, type CourseGrades, type GradeSource, type MailHeader, type Service } from '../core/models.ts';
import { serial } from '../core/serial.ts';
import { readCache, readSettings, writeSettings, type NotifyChannel } from '../core/store.ts';
import { classFreeDays, currentPeriod, matchExams, studentCourses } from '../data/exams.ts';
import { gradeCourseId, gradeKey, inQuiet, notificationId, planNotifications, sentKeyRetention, withdrawable } from '../data/rules.ts';
import { courseUrl, eclassBase, itemUrl } from '../services/eclass/links.ts';
import type { EclassNotification } from '../services/eclass/parsers.ts';

const SENT = 'notify.sent'; // key -> when it was sent
const SEEN_MAIL = 'notify.seenMail'; // inbox ids already announced, or known when mail was first set up
const SEEN_NOTICES = 'notify.seenNotices'; // eClass notification ids, the same way
const TARGETS = 'notify.targets'; // notification id -> what a click opens
const SHOWN = 'notify.shown'; // reminder ids in the tray, to withdraw when their item goes away
const SEEN_COURSES = 'notify.seenCourses'; // courses whose attendance was seen with sessions in it
const SEEN_GRADES = 'notify.seenGrades'; // course id -> item key -> the last mark announced
const SEEN_SOURCES = 'notify.seenSources'; // course id -> where its marks last came from
export const REMINDER_ALARM = 'reminder';

/** An eClass notification older than this isn't news, as with absences. */
const noticeLookback = 21 * 24 * 3600e3;

const turns = serial();

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
export const postDueReminders = (now = Date.now()): Promise<void> => turns(() => postDue(now));

async function postDue(now: number): Promise<void> {
  const settings = await readSettings();
  const [deadlines, attendance, lessons, courseGrades] = await Promise.all([readCache('deadlines'), readCache('attendance'), readCache('lessons'), readCache('courseGrades')]);
  const sent = await getMap<number>(SENT);
  const seenGrades = await getMap<Record<string, string>>(SEEN_GRADES);
  const shown = await getMap<boolean>(SHOWN);

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

  const seenSources = await getMap<GradeSource>(SEEN_SOURCES);
  rebaselineMovedSources(courseGrades?.value ?? [], seenGrades, seenSources);

  const period = currentPeriod(now);
  const input = {
    now,
    deadlines: deadlines?.value,
    attendance: attendance?.value,
    lessons: lessons?.value,
    courseGrades: courseGrades?.value,
    seenGrades,
    quiet: settings.quietHours,
    absenceLimits: settings.absenceLimits,
    classFree: classFreeDays(),
    exams: period ? matchExams(period, studentCourses(lessons?.value ?? [], attendance?.value ?? []), settings.classGroup, settings.examRooms) : null,
    dismissed: settings.dismissed,
    itemUrl,
    courseUrl,
  };
  const planned = planNotifications({ ...input, sentKeys: new Set(Object.keys(sent)) });
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
      // The id is the item's, so the 3 h reminder replaces the 24 h one in the tray.
      const id = notificationId(n.key);
      await show(id, n.title, n.body, n.quiet, target(n.key, n.url));
      sent[n.key] = now;
      if (withdrawable(id)) shown[id] = true;
    } catch (e) {
      // Not recorded, so the next pass tries again; the others still go out.
      console.warn(`IUT: couldn't show ${n.key}`, e);
    }
  }

  // Work handed in or a VOD watched elsewhere: its reminder leaves the tray too.
  const live = new Set(planNotifications(input).map((n) => notificationId(n.key)));
  for (const id of Object.keys(shown)) {
    if (live.has(id)) continue;
    chrome.notifications.clear(id);
    delete shown[id];
  }

  for (const [k, at] of Object.entries(sent)) if (now - at > sentKeyRetention) delete sent[k];
  // Together, so a course never counts as known with its old absences still unsent.
  await chrome.storage.local.set({ [SENT]: sent, [SEEN_COURSES]: [...seenCourses], [SEEN_SOURCES]: seenSources, [SHOWN]: shown });
  if (courseGrades) await advanceSeenGrades(courseGrades.value, seenGrades, sent);

  // chrome.alarms fires no sooner than 30 s ahead; a slightly late reminder is fine.
  if (next != null) await chrome.alarms.create(REMINDER_ALARM, { when: Math.max(next, now + 30_000) });
  else await chrome.alarms.clear(REMINDER_ALARM);
}

/**
 * The grades page and the quiz list write one mark differently ("0.37" and
 * "37.00/100.00") under one key, and no sum links the two. When a course moves
 * from one to the other (a professor opened or closed its page), its marks are
 * taken as they stand: nothing changed but the page they were read from.
 */
function rebaselineMovedSources(courses: CourseGrades[], seen: Record<string, Record<string, string>>, sources: Record<string, GradeSource>): void {
  for (const g of courses) {
    if (g.source === 'none') continue;
    const was = sources[g.course.id];
    sources[g.course.id] = g.source;
    if (!was || was === g.source || !seen[g.course.id]) continue;
    for (const item of g.items) if (isMarked(item)) seen[g.course.id][item.key] = item.mark;
  }
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

/**
 * Signing out forgets what that account was told and marked done, along with its
 * data, so the next account on this browser starts from a baseline, not a flood.
 */
export function forgetNotified(service: Service): Promise<void> {
  return turns(async () => {
    if (service === 'mail') await chrome.storage.local.remove(SEEN_MAIL);
    if (service !== 'eclass') return;
    await chrome.storage.local.remove([SEEN_GRADES, SEEN_COURSES, SEEN_NOTICES, SEEN_SOURCES]);
    await writeSettings({ dismissed: [] });
    const sent = await getMap<number>(SENT);
    for (const k of Object.keys(sent)) if (/^(absent|grade|due|vod|exam):/.test(k)) delete sent[k];
    await chrome.storage.local.set({ [SENT]: sent });
  });
}

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
 * Schedule on that day, an exam Exams.
 */
function target(key: string, url: string | null): Target {
  const course = absenceCourse(key);
  if (course != null) return { app: `courses/${course}` };
  const graded = gradeCourseId(key);
  if (graded != null) return { app: `grades/${graded}` };
  if (key.startsWith('class:')) return { app: `schedule/${key.slice('class:'.length).split('|')[0]}` };
  if (key.startsWith('exam:')) return { app: 'exams' };
  return url ? { url } : { app: 'deadlines' };
}

/**
 * Announces what `fresh` picks from items since the last look. The first look
 * only learns what is there. Found in quiet hours it waits: those ids stay
 * unseen, so the first look after 07:30 announces them. One that can't be shown
 * stays unseen too.
 */
async function announce<T>(
  channel: NotifyChannel,
  key: string,
  items: T[],
  idOf: (item: T) => string,
  isNew: (item: T) => boolean,
  post: (fresh: T[]) => Promise<void>,
  now: number,
): Promise<void> {
  const settings = await readSettings();
  const stored = (await chrome.storage.local.get(key))[key] as string[] | undefined;
  const seen = new Set(stored ?? []);
  const fresh = stored ? items.filter((m) => isNew(m) && !seen.has(idOf(m))) : [];
  const on = settings.notify[channel];
  const waiting = on && settings.quietHours && inQuiet(now) ? new Set(fresh.map(idOf)) : new Set<string>();
  if (on && fresh.length && !waiting.size) {
    try {
      await post(fresh);
    } catch (e) {
      console.warn(`IUT: couldn't announce ${channel}`, e);
      return;
    }
  }
  const known = items.map(idOf).filter((id) => !waiting.has(id));
  await chrome.storage.local.set({ [key]: [...new Set([...known, ...seen])].slice(0, 300) });
}

/** Announces unread inbox mail that arrived since the last look. */
export function announceNewMail(inbox: MailHeader[], now = Date.now()): Promise<void> {
  return turns(() =>
    announce(
      'mail',
      SEEN_MAIL,
      inbox,
      (m) => m.id,
      (m) => m.unread,
      (fresh) => {
        const m = fresh[0];
        return fresh.length === 1
          ? show(`mail:${m.id}`, m.from || 'New mail', m.subject || '(no subject)', false, { app: `mail/inbox/${encodeURIComponent(m.id)}` })
          : show(`mail:${m.id}`, `${fresh.length} new messages`, fresh.slice(0, 3).map((x) => `${x.from}: ${x.subject}`).join('\n'), false, { app: 'mail/inbox' });
      },
      now,
    ),
  );
}

/** Announces eClass's own notifications (a professor's announcement, feedback) that appeared since the last look. */
export function announceNotices(notices: EclassNotification[], now = Date.now()): Promise<void> {
  return turns(() =>
    announce(
      'notices',
      SEEN_NOTICES,
      notices,
      (n) => String(n.id),
      (n) => !n.read && now - n.time <= noticeLookback,
      (fresh) => {
        const n = fresh[0];
        // Only ever to eClass: the link comes from a message's content.
        const open: Target = n.url?.startsWith(`${eclassBase}/`) ? { url: n.url } : { app: 'today' };
        return fresh.length === 1
          ? show(`notice:${n.id}`, n.subject || 'eClass', n.text, false, open)
          : show(`notice:${n.id}`, `${fresh.length} new eClass notifications`, fresh.slice(0, 3).map((x) => x.subject).join('\n'), false, { app: 'today' });
      },
      now,
    ),
  );
}

/**
 * A click opens the item: an eClass page in a tab, or a view of the app, inside
 * eClass or (with New look off, where eClass stays classic) on its own page. The
 * browser comes to the front, and with no window open it gets one.
 */
export async function onNotificationClick(id: string): Promise<void> {
  const target = (await getMap<Target>(TARGETS))[id];
  chrome.notifications.clear(id);
  if (!target) return;
  const { takeover } = await readSettings();
  const url = 'url' in target ? target.url : takeover ? `${eclassBase}/#/${target.app}` : chrome.runtime.getURL(`pages/app.html#/${target.app}`);
  const win = await chrome.windows.getLastFocused().catch(() => null);
  if (win?.id == null) {
    await chrome.windows.create({ url, focused: true });
    return;
  }
  const tab = await chrome.tabs.create({ url, windowId: win.id });
  await chrome.windows.update(tab.windowId ?? win.id, { focused: true });
}
