// The extension's page when it is the frame inside eClass (content/view.tsx):
// a menu link there moves the view here, and a move here shows in eClass's
// address and title. What crosses is a route without a message's id, and a title.

import { isRoute, publicRoute, routeOfHash } from './pages.ts';

const eclass = 'https://eclass.inha.ac.kr';

let title = '';

const report = () => parent.postMessage({ iutView: publicRoute(routeOfHash(location.hash) ?? 'today'), title }, eclass);

/** Starts listening. Called before anything renders, so no route eClass sends is missed. */
export function followEclass(): void {
  addEventListener('hashchange', report);
  addEventListener('message', (e) => {
    if (e.source !== parent || !isRoute(e.data?.iutRoute)) return;
    // Already there, or on a message in the folder eClass's address names.
    if (publicRoute(routeOfHash(location.hash) ?? '') !== e.data.iutRoute) location.replace(`#/${e.data.iutRoute}`);
  });
}

/** The view on show has this title. The first call also tells eClass the frame is ready. */
export function reportTitle(next: string): void {
  title = next;
  report();
}

/** Reloads eClass's page around the frame, which a frame on another origin can't do itself. */
export const reloadEclass = () => parent.postMessage({ iutReload: true }, eclass);
