// Pieces every part the content script adds to eClass uses: a themed shadow
// root, the storage snapshot, icons, status lines and tallies.

import type { ComponentChildren } from 'preact';
import { useEffect, useState } from 'preact/hooks';
import { readSnapshot, watchSnapshot, type Snapshot } from '../core/store.ts';
import themeCss from '../ui/theme.css';
import shadowCss from './eclass.css';
import type { Theme } from './theme.ts';

// Light until the new look is on: classic eClass is a white page whatever the setting says.
let partsTheme: Theme = 'light';
const hosts = new Set<HTMLElement>();

function themeHost(host: HTMLElement) {
  if (partsTheme === 'system') delete host.dataset.theme;
  else host.dataset.theme = partsTheme;
}

/** Sets the theme of every part, those added already and those still to come. */
export function setPartsTheme(theme: Theme): void {
  partsTheme = theme;
  hosts.forEach(themeHost);
}

/**
 * A shadow root on a new element placed by `place`, with the theme and the
 * parts' CSS, and the element to render into (not the shadow root itself, so
 * Preact never touches the style sheet). Replaces one with the same id.
 * Closed: what a part shows, such as a mail's subject, is no business of the page's scripts.
 */
export function shadowHost(id: string, place: (el: HTMLElement) => void, css = shadowCss): HTMLElement {
  const old = document.getElementById(id);
  if (old) hosts.delete(old);
  old?.remove();
  const host = document.createElement('div');
  host.id = id;
  themeHost(host);
  hosts.add(host);
  place(host);
  const shadow = host.attachShadow({ mode: 'closed' });
  const mountPoint = document.createElement('div');
  mountPoint.style.display = 'contents';
  shadow.append(Object.assign(document.createElement('style'), { textContent: `${themeCss}
${css}` }), mountPoint);
  return mountPoint;
}

/** The storage snapshot, redrawn whenever the worker writes. */
export function useSnap(): Snapshot | null {
  const [snap, setSnap] = useState<Snapshot | null>(null);
  useEffect(() => {
    void readSnapshot().then(setSnap);
    return watchSnapshot(setSnap);
  }, []);
  return snap;
}

const icons = {
  mail: 'M20 4H4a2 2 0 0 0-2 2v12a2 2 0 0 0 2 2h16a2 2 0 0 0 2-2V6a2 2 0 0 0-2-2zm0 4-8 5-8-5V6l8 5 8-5v2z',
  today: 'M19 3h-1V1h-2v2H8V1H6v2H5a2 2 0 0 0-2 2v14a2 2 0 0 0 2 2h14a2 2 0 0 0 2-2V5a2 2 0 0 0-2-2zm0 16H5V8h14v11zM7 10h5v5H7z',
  schedule: 'M14 10H2v2h12v-2zm0-4H2v2h12V6zM2 16h8v-2H2v2zm19.5-4.5L23 13l-6.99 7-4.51-4.5L13 14l3.01 3 5.49-5.5z',
  deadlines: 'M19 3h-4.18A3 3 0 0 0 12 1a3 3 0 0 0-2.82 2H5a2 2 0 0 0-2 2v14a2 2 0 0 0 2 2h14a2 2 0 0 0 2-2V5a2 2 0 0 0-2-2zm-7 0a1 1 0 1 1 0 2 1 1 0 0 1 0-2zm2 14H7v-2h7v2zm3-4H7v-2h10v2zm0-4H7V7h10v2z',
  courses: 'M5 13.18v4L12 21l7-3.82v-4L12 17l-7-3.82zM12 3 1 9l11 6 9-4.91V17h2V9L12 3z',
  grades: 'M19 3H5a2 2 0 0 0-2 2v14a2 2 0 0 0 2 2h14a2 2 0 0 0 2-2V5a2 2 0 0 0-2-2zM9 17H7v-7h2v7zm4 0h-2V7h2v10zm4 0h-2v-4h2v4z',
  exams: 'M14 2H6a2 2 0 0 0-2 2v16a2 2 0 0 0 2 2h12a2 2 0 0 0 2-2V8l-6-6zm2 16H8v-2h8v2zm0-4H8v-2h8v2zm-3-5V3.5L18.5 9H13z',
  settings: 'M19.14 12.94a7.07 7.07 0 0 0 0-1.88l2.03-1.58a.49.49 0 0 0 .12-.61l-1.92-3.32a.49.49 0 0 0-.59-.22l-2.39.96a7 7 0 0 0-1.62-.94l-.36-2.54a.48.48 0 0 0-.48-.41h-3.84a.48.48 0 0 0-.47.41l-.36 2.54c-.59.24-1.13.57-1.62.94l-2.39-.96a.48.48 0 0 0-.59.22L2.74 8.87a.47.47 0 0 0 .12.61l2.03 1.58a7.4 7.4 0 0 0 0 1.88l-2.03 1.58a.49.49 0 0 0-.12.61l1.92 3.32c.12.22.37.29.59.22l2.39-.96c.5.38 1.03.7 1.62.94l.36 2.54c.05.24.24.41.48.41h3.84c.24 0 .44-.17.47-.41l.36-2.54a7 7 0 0 0 1.62-.94l2.39.96c.22.08.47 0 .59-.22l1.92-3.32a.47.47 0 0 0-.12-.61l-2.01-1.58zM12 15.6a3.6 3.6 0 1 1 0-7.2 3.6 3.6 0 0 1 0 7.2z',
  close: 'M19 6.41 17.59 5 12 10.59 6.41 5 5 6.41 10.59 12 5 17.59 6.41 19 12 13.41 17.59 19 19 17.59 13.41 12z',
  danger: 'M11 15h2v2h-2zm0-8h2v6h-2zm1-5C6.47 2 2 6.5 2 12a10 10 0 1 0 10-10zm0 18a8 8 0 1 1 0-16 8 8 0 0 1 0 16z',
  ok: 'M9 16.2 4.8 12l-1.4 1.4L9 19 21 7l-1.4-1.4L9 16.2z',
  warning: 'M1 21h22L12 2 1 21zm12-3h-2v-2h2v2zm0-4h-2v-4h2v4z',
  info: 'M11 7h2v2h-2zm0 4h2v6h-2zm1-9a10 10 0 1 0 0 20 10 10 0 0 0 0-20zm0 18a8 8 0 1 1 0-16 8 8 0 0 1 0 16z',
};

export type IconName = keyof typeof icons;

export const Icon = ({ name }: { name: IconName }) => (
  <svg viewBox="0 0 24 24" fill="currentColor" aria-hidden="true"><path d={icons[name]} /></svg>
);

export type Status = 'ok' | 'warning' | 'danger' | 'info';

export const StatusLine = ({ status, children }: { status: Status; children: ComponentChildren }) => (
  <div class={`status ${status}`} role={status === 'danger' ? 'alert' : undefined}><Icon name={status} /><span>{children}</span></div>
);

export { Tally } from '../ui/tally.tsx';

export { viewUrl } from './pages.ts';
