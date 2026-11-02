// The extension's views as eClass pages: '/#/mail/inbox', '/#/grades' and so
// on open in eClass's own content area, under its header and next to its left
// menu, the way Curriculum or Message do. The front page hosts them, so the
// back button, reloads and links all work like any other eClass page.
//
// The views themselves run in the extension's own page, in a frame here: mail
// bodies and the password fields of Settings hold what eClass's scripts (Google's
// tag among them) must not read, and no script on this page can reach into that
// frame. It only ever tells this page its route, without a message's id, and its title.

import { render } from 'preact';
import { call } from '../core/rpc.ts';
import { isRoute, publicRoute, routeOfHash } from './pages.ts';
import { shadowHost, StatusLine } from './shared.tsx';

/** A route the address may not show, waiting for the frame: a message's id. */
let held: string | null = null;

/** Opens a route in the frame. Null until the views are mounted, on the pages that host them. */
let openRoute: ((route: string) => void) | null = null;

/**
 * Takes a mail message's id out of the address the moment the page starts,
 * before eClass's scripts run and read it (a notification opens such a link).
 */
export function hideMessageId(): void {
  const route = routeOfHash(location.hash);
  if (!route || publicRoute(route) === route) return;
  held = route;
  history.replaceState(history.state, '', `#/${publicRoute(route)}`);
}

/** Opens a view in place, with the whole route kept out of the address. False on a page that doesn't host the views. */
export function openView(route: string): boolean {
  if (!openRoute) return false;
  openRoute(route);
  return true;
}

const FrameFailed = ({ route }: { route: string }) => (
  <div class="frame-failed">
    <StatusLine status="danger">Couldn't open this view inside eClass.</StatusLine>
    <a class="btn" href={chrome.runtime.getURL(`pages/app.html#/${publicRoute(route)}`)} target="_blank">Open in a tab</a>
  </div>
);

/** How long the frame gets to say it is there before the way out appears. */
const FRAME_WAIT = 10_000;

/** Mounts the view host in eClass's content area. The frame itself loads the first time a view opens. */
export function mountViews(): void {
  const main = document.getElementById('region-main');
  if (!main) return;
  const root = document.documentElement;
  const origin = new URL(chrome.runtime.getURL('')).origin;
  const pageTitle = document.title;
  let frame: HTMLIFrameElement | null = null;
  let slot: HTMLElement | null = null;
  let ready = false;
  let waiting: string | null = null; // asked for while the frame was still loading

  const send = (route: string) => frame?.contentWindow?.postMessage({ iutRoute: route }, origin);

  const load = (route: string) => {
    const at = shadowHost('iut-view', (el) => main.prepend(el));
    const f = Object.assign(document.createElement('iframe'), { title: 'IUT', src: chrome.runtime.getURL(`pages/app.html?frame=inline#/${route}`) });
    slot = document.createElement('div');
    at.append(f, slot);
    frame = f;
    setTimeout(() => {
      if (ready || !slot) return;
      f.style.display = 'none';
      render(<FrameFailed route={route} />, slot);
    }, FRAME_WAIT);
  };

  /** The address changed: a menu link, the back button, or the frame's own report. */
  const follow = () => {
    const outer = routeOfHash(location.hash);
    root.classList.toggle('iut-view', !!outer);
    if (!outer) {
      document.title = pageTitle;
      return;
    }
    const route = held && publicRoute(held) === outer ? held : outer;
    held = null;
    scrollTo(0, 0);
    if (!frame) {
      // The address of a frame shows in the page's own performance records, so a message's id comes after.
      load(publicRoute(route));
      if (route !== publicRoute(route)) waiting = route;
    } else if (ready) send(route);
    else waiting = route;
  };

  addEventListener('message', (e) => {
    // Only the extension's page has that origin, whatever a script here posts.
    if (e.origin !== origin) return;
    if (e.data?.iutReload) location.reload();
    if (!isRoute(e.data?.iutView)) return;
    if (!ready) {
      ready = true;
      if (frame) frame.style.display = '';
      if (slot) render(null, slot);
    }
    if (waiting) {
      send(waiting);
      waiting = null;
      return;
    }
    if (!routeOfHash(location.hash)) return; // the student left the view; the frame is only hidden
    const hash = `#/${e.data.iutView}`;
    if (location.hash !== hash) {
      // In place: the frame's own move already made the entry the back button uses.
      history.replaceState(history.state, '', hash);
      dispatchEvent(new HashChangeEvent('hashchange')); // the left menu marks the view it's on
    }
    if (typeof e.data.title === 'string') document.title = `${e.data.title} · eClass`;
  });

  addEventListener('hashchange', follow);
  openRoute = (route) => {
    held = route;
    if (location.hash === `#/${publicRoute(route)}`) follow();
    else location.hash = `#/${publicRoute(route)}`;
  };
  follow();
  void call('sync', 'all').catch(() => {});
}
