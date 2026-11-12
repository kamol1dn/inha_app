// The extension's own page: the toolbar popup (frame=popup), a tab of its own
// (settings, the welcome on install), and the frame in eClass's content area
// (frame=inline, content/view.tsx). One hash route per view.

import { render } from 'preact';
import { useEffect, useRef } from 'preact/hooks';
import { followEclass, reportTitle } from '../content/framed.ts';
import viewCss from '../content/view.css';
import { call } from '../core/rpc.ts';
import type { Snapshot } from '../core/store.ts';
import { AbsenceState, needsAttention } from '../data/status.ts';
import { courseUrl } from '../services/eclass/links.ts';
import appCss from './app.css';
import { eclassTarget, frame, Icon, useNow, useRoute, useSnapshot, type IconName } from './common.tsx';
import { examMatch } from './derive.ts';
import { fontFaces } from './fonts.ts';
import themeCss from './theme.css';
import { viewFor } from './views/index.tsx';
import { Settings } from './views/settings.tsx';

document.head.append(Object.assign(document.createElement('style'), { textContent: `${fontFaces('../fonts/')}\n${themeCss}\n${appCss}\n${frame === 'inline' ? viewCss : ''}` }));
if (frame === 'popup') document.body.classList.add('popup');
if (frame === 'inline') {
  document.body.classList.add('inline');
  followEclass();
}

/** Tells eClass around the frame what's on show. */
function ReportTitle({ title }: { title: string }) {
  useEffect(() => reportTitle(title), [title]);
  return null;
}

function Nav({ snap, now, route }: { snap: Snapshot; now: number; route: string[] }) {
  const att = snap.cache.attendance?.value ?? [];
  const due = needsAttention(snap.cache.deadlines?.value ?? [], att, now, snap.settings.dismissed).length;
  const trouble = att.some((c) => AbsenceState.of(c, snap.settings.absenceLimits).status === 'danger');
  const unread = snap.cache.mailUnread?.value ?? 0;
  const exams = examMatch(snap, now);
  const items: [string, string, IconName, preact.ComponentChildren?][] = [
    ['today', 'Today', 'today'],
    ['schedule', 'Schedule', 'schedule'],
    ['deadlines', 'Deadlines', 'deadlines', due ? <span class="count">{due}</span> : null],
    ['courses', 'Attendance', 'courses', trouble ? <span class="count alert">!</span> : null],
    ['grades', 'Grades', 'grades'],
    ['mail', 'Mail', 'mail', unread ? <span class="count">{unread}</span> : null],
    // Even with no exam matched: "Show every exam" is how to check the matching by hand.
    ...(exams ? [['exams', 'Exams', 'exams'] as [string, string, IconName]] : []),
  ];
  const here = route[0] ?? 'today';
  return (
    <nav class="nav" aria-label="IUT">
      <div class="brand">
        <b>IUT</b>
        <span>eClass</span>
      </div>
      {items.map(([path, label, icon, badge]) => (
        <a key={path} class={`item ${here === path ? 'on' : ''}`} href={`#/${path}`} aria-current={here === path ? 'page' : undefined}>
          <span style={{ width: '20px', height: '20px', display: 'inline-flex' }}><Icon name={icon} /></span>
          {label}
          {badge}
        </a>
      ))}
      {att.length > 0 && <div class="group">Courses on eClass</div>}
      {att.map((c) => (
        <a key={c.course.id} class="course" href={courseUrl(c.course.id)} target={eclassTarget} title={c.course.name}>
          {c.course.name}
        </a>
      ))}
      <div class="spacer" />
      <div class="foot">
        <a href="#/settings" class={here === 'settings' ? 'fg-primary' : ''}>Settings</a>
      </div>
    </nav>
  );
}

function App() {
  const snap = useSnapshot();
  const now = useNow();
  const route = useRoute();
  const scroller = useRef<HTMLElement>(null);

  // <main> stays mounted across routes: each view starts at its top.
  useEffect(() => {
    if (scroller.current) scroller.current.scrollTop = 0;
  }, [route.join('/')]);

  // A visit is a good moment to refresh what is old; the worker skips what is fresh.
  useEffect(() => {
    void call('sync', 'all').catch(() => {});
  }, []);

  useEffect(() => {
    const t = snap?.settings.theme;
    if (t && t !== 'system') document.documentElement.dataset.theme = t;
    else delete document.documentElement.dataset.theme;
  }, [snap?.settings.theme]);

  // Transparent only as the frame in eClass, where the window shows through the page around it.
  useEffect(() => {
    document.documentElement.classList.toggle('iut-glass', frame === 'inline' && !!snap?.settings.glass);
  }, [snap?.settings.glass]);

  if (!snap) return null;
  if (route[0] === 'welcome') return <Settings snap={snap} welcome />;
  const view = viewFor(route, snap, now);
  const busy = Object.values(snap.state).some((s) => s?.busy);

  return (
    <div class="shell">
      {frame === 'inline' && <ReportTitle title={view.title} />}
      <Nav snap={snap} now={now} route={route} />
      <main ref={scroller}>
        <header class="bar">
          {view.back && (
            <a class="icon-btn" href={view.back} aria-label="Back"><Icon name="back" /></a>
          )}
          <h1 title={view.title}>{view.title}</h1>
          <span class="grow" />
          {frame === 'popup' && (
            <a class="icon-btn" href="https://eclass.inha.ac.kr/" target="_blank" title="Open eClass" aria-label="Open eClass"><Icon name="open" /></a>
          )}
          <button class="icon-btn" title="Refresh" aria-label="Refresh" disabled={busy} onClick={() => call('sync', 'all', true)} style={busy ? { opacity: 0.4 } : undefined}>
            <Icon name="sync" />
          </button>
          {frame === 'popup' && (
            <a class="icon-btn" href={chrome.runtime.getURL('pages/app.html#/settings')} target="_blank" title="Settings" aria-label="Settings"><Icon name="settings" /></a>
          )}
        </header>
        {view.full ? view.body : <div class="page">{view.body}</div>}
      </main>
    </div>
  );
}

render(<App />, document.getElementById('app')!);
