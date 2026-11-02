// What the content script decides from the page and its address. Pure, so the
// tests can read it.

import type { Deadline } from '../core/models.ts';
import { dayHeader, HOUR, relative } from '../data/format.ts';
import { courseUrl, itemUrl } from '../services/eclass/links.ts';

/** The eClass address of one of the extension's views ('mail/inbox', 'grades', ...): a page of the front page. */
export const viewUrl = (route: string) => `/#/${route}`;

// ---- Routes ----

/** The route in a hash, as it stands: '#/mail/inbox/abc' -> 'mail/inbox/abc'. Only '#/…' is a route: eClass's own pages use other anchors. */
export function routeOfHash(hash: string): string | null {
  if (!hash.startsWith('#/')) return null;
  return hash.slice(2).split('?')[0] || null;
}

const routeShape = /^[\w%.~!*'()-]+(?:\/[\w%.~!*'()-]*)*$/; // what encodeURIComponent leaves, and the slashes

/** Whether a message between eClass and the views' frame really holds a route. */
export const isRoute = (r: unknown): r is string => typeof r === 'string' && routeShape.test(r);

/**
 * What of a route may show in eClass's address, where the page's own scripts
 * (Google's tag among them) read it: everything but the id of a mail message.
 */
export function publicRoute(route: string): string {
  const [view, folder] = route.split('/');
  return view === 'mail' && folder ? `mail/${folder}` : route;
}

// ---- Which page this is ----

/**
 * eClass's sign-in page: a password form on the sign-in address, or that page
 * under another one. A signed-in student on the address gets no form (stock
 * Moodle asks whether to log out first), so that page stays eClass's own.
 */
export function isSignInPage(path: string, doc: Pick<Document, 'body' | 'querySelector'>): boolean {
  if (path.startsWith('/login/index.php')) return !!doc.querySelector('input[name="password"]');
  return doc.body?.id === 'page-login-index' && !!doc.querySelector('form[action*="/login/index.php"] input[name="password"]');
}

/** The form that holds the page's sign-in fields, or null when it didn't load. */
export const signInForm = (doc: Pick<Document, 'querySelector'>): HTMLFormElement | null =>
  doc.querySelector<HTMLFormElement>('form[action*="/login/index.php"]') ?? doc.querySelector<HTMLInputElement>('input[name="password"]')?.form ?? null;

/** The course list in the page's content. The header's course menu on every signed-in page has the same class, so it needs the place too. */
export const courseListSelector = '#region-main .my-course-lists';

/** Where a due item's link goes: its activity, else its course, else the Deadlines view. */
export const dueHref = (d: Deadline): string => itemUrl(d) ?? (d.courseId != null ? courseUrl(d.courseId) : viewUrl('deadlines'));

/** A due item's day beside its clock on the row: past a day relative() gives the day and clock again, so only the day. */
export function dueWhen(end: number, now: number): string {
  if (end < now) return relative(end, now);
  const day = dayHeader(end, new Date(now));
  return end - now < 24 * HOUR ? `${day} · ${relative(end, now)}` : day;
}

// ---- Signing in ----

/** Where to go once signed in: what the address asked for, and the view a link wanted, kept in the hash. */
export function afterSignIn(search: string, hash: string): string {
  const wants = new URLSearchParams(search).get('wantsurl');
  const to = wants?.startsWith('https://eclass.inha.ac.kr/') ? wants : '/';
  return hash.startsWith('#/') && !to.includes('#') ? `${to}${hash}` : to;
}

/** The tab's record of when this page last signed the browser in and moved on. Not a secret: only a time. */
export const SIGN_IN_TRY = 'iut.signInTry';

/**
 * Back on the sign-in page within a minute of signing in: the worker's session
 * didn't reach this tab. A container tab or a private window keeps its own
 * cookies, where the worker's sign-in can't reach, so trying again would loop.
 */
export function signInLooped(tried: string | null, now: number): boolean {
  const at = Number(tried);
  return at > 0 && now >= at && now - at < 60_000;
}
