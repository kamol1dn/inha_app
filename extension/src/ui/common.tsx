// Building blocks every view uses: the snapshot of storage, the clock, the
// route, icons, and the status and error rows of DESIGN.md 3 and 7.

import type { ComponentChildren } from 'preact';
import { useEffect, useRef, useState } from 'preact/hooks';
import type { ErrorInfo } from '../core/errors.ts';
import type { Service } from '../core/models.ts';
import { call } from '../core/rpc.ts';
import { readSnapshot, watchSnapshot, type Snapshot } from '../core/store.ts';
import { dayDate, updatedAt } from '../data/format.ts';
import type { Status } from '../data/status.ts';
import { errorLine, isOffline, offlineCovers, oldestFetch } from './derive.ts';

export { Tally } from './tally.tsx';

// ---- Data ----

/** The storage snapshot, redrawn on every change the worker writes. Null until first read. */
export function useSnapshot(): Snapshot | null {
  const [snap, setSnap] = useState<Snapshot | null>(null);
  useEffect(() => {
    void readSnapshot().then(setSnap);
    return watchSnapshot(setSnap);
  }, []);
  return snap;
}

/** The current time, ticking on the minute. */
export function useNow(): number {
  const [now, setNow] = useState(Date.now());
  useEffect(() => {
    let t: ReturnType<typeof setTimeout>;
    const next = () => {
      t = setTimeout(() => {
        setNow(Date.now());
        next();
      }, 60_000 - (Date.now() % 60_000) + 50);
    };
    next();
    return () => clearTimeout(t);
  }, []);
  return now;
}

// ---- Routing ----

/** The hash route as path segments: '#/mail/inbox/abc' -> ['mail', 'inbox', 'abc']. */
export function useRoute(): string[] {
  // Only '#/…' is a route: eClass's own pages use other anchors ('#section-3').
  const read = () => (location.hash.startsWith('#/') ? location.hash.slice(2).split('?')[0].split('/').filter(Boolean).map(decodeURIComponent) : []);
  const [route, setRoute] = useState(read);
  useEffect(() => {
    const on = () => setRoute(read());
    addEventListener('hashchange', on);
    return () => removeEventListener('hashchange', on);
  }, []);
  return route;
}

export const go = (path: string) => {
  location.hash = `#/${path}`;
};

/** How the views are shown: in a frame inside eClass's own pages, in the toolbar popup, or in a tab of the extension. */
export const frame: 'inline' | 'popup' | 'tab' = ((f) => (f === 'inline' || f === 'popup' ? f : 'tab'))(new URLSearchParams(location.search).get('frame'));

/** Links to eClass pages: in place of the page around the frame inside eClass, a new tab from the extension's pages. */
export const eclassTarget = frame === 'inline' ? '_top' : '_blank';

// ---- Icons (Material Symbols paths, 24px grid) ----

const paths = {
  ok: 'M9 16.2 4.8 12l-1.4 1.4L9 19 21 7l-1.4-1.4L9 16.2z',
  warning: 'M1 21h22L12 2 1 21zm12-3h-2v-2h2v2zm0-4h-2v-4h2v4z',
  danger: 'M11 15h2v2h-2zm0-8h2v6h-2zm1-5C6.47 2 2 6.5 2 12a10 10 0 1 0 10-10zm0 18a8 8 0 1 1 0-16 8 8 0 0 1 0 16z',
  info: 'M11 7h2v2h-2zm0 4h2v6h-2zm1-9a10 10 0 1 0 0 20 10 10 0 0 0 0-20zm0 18a8 8 0 1 1 0-16 8 8 0 0 1 0 16z',
  sync: 'M12 4V1L8 5l4 4V6a6 6 0 0 1 6 6c0 1-.25 1.97-.7 2.8l1.46 1.46A7.93 7.93 0 0 0 20 12a8 8 0 0 0-8-8zm0 14a6 6 0 0 1-6-6c0-1 .25-1.97.7-2.8L5.24 7.74A7.93 7.93 0 0 0 4 12a8 8 0 0 0 8 8v3l4-4-4-4v3z',
  settings: 'M19.14 12.94a7.07 7.07 0 0 0 0-1.88l2.03-1.58a.49.49 0 0 0 .12-.61l-1.92-3.32a.49.49 0 0 0-.59-.22l-2.39.96a7 7 0 0 0-1.62-.94l-.36-2.54a.48.48 0 0 0-.48-.41h-3.84a.48.48 0 0 0-.47.41l-.36 2.54c-.59.24-1.13.57-1.62.94l-2.39-.96a.48.48 0 0 0-.59.22L2.74 8.87a.47.47 0 0 0 .12.61l2.03 1.58a7.4 7.4 0 0 0 0 1.88l-2.03 1.58a.49.49 0 0 0-.12.61l1.92 3.32c.12.22.37.29.59.22l2.39-.96c.5.38 1.03.7 1.62.94l.36 2.54c.05.24.24.41.48.41h3.84c.24 0 .44-.17.47-.41l.36-2.54a7 7 0 0 0 1.62-.94l2.39.96c.22.08.47 0 .59-.22l1.92-3.32a.47.47 0 0 0-.12-.61l-2.01-1.58zM12 15.6a3.6 3.6 0 1 1 0-7.2 3.6 3.6 0 0 1 0 7.2z',
  today: 'M19 3h-1V1h-2v2H8V1H6v2H5a2 2 0 0 0-2 2v14a2 2 0 0 0 2 2h14a2 2 0 0 0 2-2V5a2 2 0 0 0-2-2zm0 16H5V8h14v11zM7 10h5v5H7z',
  schedule: 'M14 10H2v2h12v-2zm0-4H2v2h12V6zM2 16h8v-2H2v2zm19.5-4.5L23 13l-6.99 7-4.51-4.5L13 14l3.01 3 5.49-5.5z',
  deadlines: 'M19 3h-4.18A3 3 0 0 0 12 1a3 3 0 0 0-2.82 2H5a2 2 0 0 0-2 2v14a2 2 0 0 0 2 2h14a2 2 0 0 0 2-2V5a2 2 0 0 0-2-2zm-7 0a1 1 0 1 1 0 2 1 1 0 0 1 0-2zm2 14H7v-2h7v2zm3-4H7v-2h10v2zm0-4H7V7h10v2z',
  courses: 'M5 13.18v4L12 21l7-3.82v-4L12 17l-7-3.82zM12 3 1 9l11 6 9-4.91V17h2V9L12 3z',
  grades: 'M19 3H5a2 2 0 0 0-2 2v14a2 2 0 0 0 2 2h14a2 2 0 0 0 2-2V5a2 2 0 0 0-2-2zM9 17H7v-7h2v7zm4 0h-2V7h2v10zm4 0h-2v-4h2v4z',
  mail: 'M20 4H4a2 2 0 0 0-2 2v12a2 2 0 0 0 2 2h16a2 2 0 0 0 2-2V6a2 2 0 0 0-2-2zm0 4-8 5-8-5V6l8 5 8-5v2z',
  exams: 'M14 2H6a2 2 0 0 0-2 2v16a2 2 0 0 0 2 2h12a2 2 0 0 0 2-2V8l-6-6zm2 16H8v-2h8v2zm0-4H8v-2h8v2zm-3-5V3.5L18.5 9H13z',
  open: 'M19 19H5V5h7V3H5a2 2 0 0 0-2 2v14a2 2 0 0 0 2 2h14c1.1 0 2-.9 2-2v-7h-2v7zM14 3v2h3.59l-9.83 9.83 1.41 1.41L19 6.41V10h2V3h-7z',
  back: 'M20 11H7.83l5.59-5.59L12 4l-8 8 8 8 1.41-1.41L7.83 13H20v-2z',
  reply: 'M10 9V5l-7 7 7 7v-4.1c5 0 8.5 1.6 11 5.1-1-5-4-10-11-11z',
  replyAll: 'M7 8V5l-7 7 7 7v-3l-4-4 4-4zm6 1V5l-7 7 7 7v-4.1c5 0 8.5 1.6 11 5.1-1-5-4-10-11-11z',
  forward: 'M14 9V5l7 7-7 7v-4.1c-5 0-8.5 1.6-11 5.1 1-5 4-10 11-11z',
  delete: 'M6 19a2 2 0 0 0 2 2h8a2 2 0 0 0 2-2V7H6v12zM19 4h-3.5l-1-1h-5l-1 1H5v2h14V4z',
  edit: 'M3 17.25V21h3.75L17.81 9.94l-3.75-3.75L3 17.25zM20.71 7.04a1 1 0 0 0 0-1.41l-2.34-2.34a1 1 0 0 0-1.41 0l-1.83 1.83 3.75 3.75 1.83-1.83z',
  attach: 'M16.5 6v11.5a4 4 0 1 1-8 0V5a2.5 2.5 0 0 1 5 0v10.5a1 1 0 1 1-2 0V6H10v9.5a2.5 2.5 0 0 0 5 0V5a4 4 0 0 0-8 0v12.5a5.5 5.5 0 0 0 11 0V6h-1.5z',
  unread: 'M22 8.98V18c0 1.1-.9 2-2 2H4a2 2 0 0 1-2-2V6c0-1.1.9-2 2-2h10.1c-.06.32-.1.66-.1 1 0 1.48.65 2.79 1.67 3.71L12 11 4 6v2l8 5 5.3-3.32c.54.2 1.1.32 1.7.32 1.13 0 2.16-.39 3-1.02zM16 5c0 1.66 1.34 3 3 3s3-1.34 3-3-1.34-3-3-3-3 1.34-3 3z',
  close: 'M19 6.41 17.59 5 12 10.59 6.41 5 5 6.41 10.59 12 5 17.59 6.41 19 12 13.41 17.59 19 19 17.59 13.41 12z',
  logout: 'M17 7l-1.41 1.41L18.17 11H8v2h10.17l-2.58 2.58L17 17l5-5zM4 5h8V3H4c-1.1 0-2 .9-2 2v14c0 1.1.9 2 2 2h8v-2H4V5z',
  bell: 'M12 22c1.1 0 2-.9 2-2h-4c0 1.1.89 2 2 2zm6-6v-5c0-3.07-1.64-5.64-4.5-6.32V4c0-.83-.67-1.5-1.5-1.5s-1.5.67-1.5 1.5v.68C7.63 5.36 6 7.92 6 11v5l-2 2v1h16v-1l-2-2z',
  junk: 'M12 2a10 10 0 1 0 0 20 10 10 0 0 0 0-20zM4 12c0-4.42 3.58-8 8-8 1.85 0 3.55.63 4.9 1.69L5.69 16.9A7.9 7.9 0 0 1 4 12zm8 8c-1.85 0-3.55-.63-4.9-1.69L18.31 7.1A7.9 7.9 0 0 1 20 12c0 4.42-3.58 8-8 8z',
  inbox: 'M19 3H5a2 2 0 0 0-2 2v14a2 2 0 0 0 2 2h14a2 2 0 0 0 2-2V5a2 2 0 0 0-2-2zm0 12h-4c0 1.66-1.35 3-3 3s-3-1.34-3-3H5V5h14v10z',
  classic: 'M3 13h8V3H3v10zm0 8h8v-6H3v6zm10 0h8V11h-8v10zm0-18v6h8V3h-8z',
  offline: 'M19.35 10.04A7.49 7.49 0 0 0 12 4c-1.48 0-2.85.43-4.01 1.17l1.46 1.46A5.47 5.47 0 0 1 12 6a5.5 5.5 0 0 1 5.5 5.5v.5H19a3 3 0 0 1 3 3c0 1.13-.64 2.11-1.56 2.62l1.45 1.45A4.98 4.98 0 0 0 24 15c0-2.64-2.05-4.78-4.65-4.96zM3 5.27l2.75 2.74A7.48 7.48 0 0 0 0 15a6 6 0 0 0 6 6h11.73l2 2L21 21.73 4.27 5 3 5.27zM7.73 10l8 8H6a4 4 0 0 1 0-8h1.73z',
  person: 'M12 12a4 4 0 1 0 0-8 4 4 0 0 0 0 8zm0 2c-2.67 0-8 1.34-8 4v2h16v-2c0-2.66-5.33-4-8-4z',
};

export type IconName = keyof typeof paths;

export const Icon = ({ name, title }: { name: IconName; title?: string }) => (
  <svg viewBox="0 0 24 24" fill="currentColor" aria-hidden={title ? undefined : 'true'} role={title ? 'img' : undefined}>
    {title && <title>{title}</title>}
    <path d={paths[name]} />
  </svg>
);

// ---- Status ----

/** A status is always an icon plus words, never color alone (DESIGN.md 3). */
export const StatusLine = ({ status, children }: { status: Status; children: ComponentChildren }) => (
  <span class={`status ${status}`}>
    <Icon name={status} />
    <span>{children}</span>
  </span>
);

// ---- Stale and failed data (DESIGN.md 7) ----

/** How old each source may get before it is marked stale. */
const staleAfter: Record<Service, number> = { edupage: 24 * 3600e3, eclass: 3 * 3600e3, mail: 30 * 60e3, ins: 24 * 3600e3 };

export function isStale(snap: Snapshot, service: Service, fetchedAt: number | undefined, now: number): boolean {
  if (fetchedAt == null) return false;
  return now - fetchedAt > staleAfter[service] || !!snap.state[service]?.error;
}

/** "as of Tue 18:04" in warning, for a section header. */
export const Stale = ({ at }: { at: number }) => (
  <span class="stale">
    <Icon name="sync" /> as of {dayDate(at)} {updatedAt(at).slice(-5)}
  </span>
);

/** Settings from here: a file dialog or a password manager would close the toolbar popup, so there it opens in a tab. */
const settingsLink = () => (frame === 'popup' ? { href: chrome.runtime.getURL('pages/app.html#/settings'), target: '_blank' } : { href: '#/settings' });

/** One error row for a failed service, with what is still on screen (`at`, when the cache has it) and the next step (DESIGN.md 10). */
export function ErrorRow({ service, error, at }: { service: Service; error: ErrorInfo; at?: number | null }) {
  const [busy, setBusy] = useState(false);
  const signIn = error.name === 'LoginRequired';
  const setup = error.name === 'SetupNeeded';
  const cert = !!error.certificate;
  const retry = async () => {
    setBusy(true);
    try {
      if (cert) await call('insOpenForSync');
      else await call('sync', service, true);
    } finally {
      setBusy(false);
    }
  };
  return (
    <div class="error-row" role="alert">
      <StatusLine status="danger">{errorLine(error, service, at)}</StatusLine>
      <span class="grow" />
      {signIn || setup ? (
        <a class="btn" {...settingsLink()}>{setup ? 'Settings' : 'Sign in'}</a>
      ) : (
        <button class="btn" disabled={busy} onClick={retry}>
          {cert ? 'Open INS' : 'Retry'}
        </button>
      )}
    </div>
  );
}

/** A service's error row, unless it is the network failure the offline row already reports. */
export function SourceError({ snap, service, at }: { snap: Snapshot; service: Service; at?: number | null }) {
  const error = snap.state[service]?.error;
  if (!error || offlineCovers(snap, error)) return null;
  return <ErrorRow service={service} error={error} at={at} />;
}

/** One row for the connection, in place of the services' own network rows (DESIGN.md 8, Offline). */
export function OfflineRow({ snap }: { snap: Snapshot }) {
  const [busy, setBusy] = useState(false);
  if (!isOffline(snap)) return null;
  const at = oldestFetch(snap);
  const retry = async () => {
    setBusy(true);
    try {
      await call('sync', 'all', true);
    } finally {
      setBusy(false);
    }
  };
  return (
    <div class="error-row offline" role="status">
      <span class="offline-icon"><Icon name="offline" /></span>
      <span>{at == null ? 'Offline.' : `Offline. Showing data from ${updatedAt(at)}.`}</span>
      <span class="grow" />
      <button class="btn" disabled={busy} onClick={retry}>Retry</button>
    </div>
  );
}

const signInNote: Partial<Record<Service, string>> = {
  eclass: 'Sign in to eClass to see deadlines and attendance.',
  ins: 'Sign in to INS to see your grades.',
};

/**
 * What a part shows with nothing cached: bars while it is on its way, the
 * failure's row, or, signed out, one sentence with "Sign in" in place of that
 * row (DESIGN.md 8, Empty states). Never bars with no refresh coming.
 */
export function NoData({ snap, service, lines = 6 }: { snap: Snapshot; service: Service; lines?: number }) {
  const st = snap.state[service];
  const signedOut = !snap.logins[service] && (st?.error ? st.error.name === 'LoginRequired' : !!st && !st.busy);
  if (signedOut && signInNote[service]) {
    return (
      <>
        <p class="t-bl" style={{ margin: '16px 0 8px' }}>{signInNote[service]}</p>
        <a class="btn" style={{ marginLeft: '-12px' }} {...settingsLink()}>Sign in</a>
      </>
    );
  }
  return st?.error ? <SourceError snap={snap} service={service} /> : <Skeleton lines={lines} />;
}

export const Skeleton = ({ lines = 3 }: { lines?: number }) => (
  <div aria-busy="true">
    {Array.from({ length: lines }, (_, i) => (
      <div key={i} class="skeleton" style={{ width: `${90 - i * 15}%` }} />
    ))}
  </div>
);

const focusables = 'a[href], button:not([disabled]), input:not([disabled]), select:not([disabled]), textarea:not([disabled])';

/** A modal sheet: focus moves in on opening, Tab stays inside, and focus goes back to what opened it. */
export function Dialog({ title, onClose, children }: { title: string; onClose: () => void; children: ComponentChildren }) {
  const box = useRef<HTMLDivElement>(null);
  const close = useRef(onClose);
  close.current = onClose;
  useEffect(() => {
    const el = box.current!;
    const root = el.getRootNode() as Document | ShadowRoot;
    const opener = root.activeElement as HTMLElement | null;
    const inside = () => [...el.querySelectorAll<HTMLElement>(focusables)];
    (inside()[0] ?? el).focus();
    const key = (e: KeyboardEvent) => {
      if (e.key === 'Escape') close.current();
      if (e.key !== 'Tab') return;
      const all = inside();
      const at = root.activeElement;
      const to = !all.length ? el : !el.contains(at) ? all[0] : e.shiftKey && at === all[0] ? all[all.length - 1] : !e.shiftKey && at === all[all.length - 1] ? all[0] : null;
      if (to) {
        e.preventDefault();
        to.focus();
      }
    };
    addEventListener('keydown', key);
    return () => {
      removeEventListener('keydown', key);
      opener?.focus?.();
    };
  }, []);
  return (
    <div class="scrim" onClick={(e) => e.target === e.currentTarget && onClose()}>
      <div class="dialog" ref={box} role="dialog" aria-modal="true" aria-label={title} tabIndex={-1}>
        <h2>{title}</h2>
        {children}
      </div>
    </div>
  );
}
