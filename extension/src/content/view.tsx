// The extension's views as eClass pages: '/#/mail/inbox', '/#/grades' and so
// on open in eClass's own content area, under its header and next to its left
// menu, the way Curriculum or Message do. The front page hosts them, so the
// back button, reloads and links all work like any other eClass page.

import { render } from 'preact';
import { useEffect } from 'preact/hooks';
import { call } from '../core/rpc.ts';
import appCss from '../ui/app.css';
import { Icon, useNow, useRoute, useSnapshot } from '../ui/common.tsx';
import { viewFor } from '../ui/views/index.tsx';
import { shadowHost } from './shared.tsx';
import viewCss from './view.css';

function InlineView() {
  const snap = useSnapshot();
  const now = useNow();
  const route = useRoute();
  const open = route.length > 0;

  useEffect(() => {
    document.documentElement.classList.toggle('iut-view', open);
    if (open) scrollTo(0, 0);
  }, [route.join('/')]);

  useEffect(() => {
    void call('sync', 'all').catch(() => {});
  }, []);

  if (!open || !snap) return null;
  const view = viewFor(route, snap, now);
  const busy = Object.values(snap.state).some((s) => s?.busy);
  document.title = `${view.title} · eClass`;
  return (
    <div class={`inline ${view.full ? 'full' : ''}`}>
      <header class="bar">
        {view.back && (
          <a class="icon-btn" href={view.back} aria-label="Back"><Icon name="back" /></a>
        )}
        <h1>{view.title}</h1>
        <span class="grow" />
        <button class="icon-btn" title="Refresh" aria-label="Refresh" disabled={busy} onClick={() => call('sync', 'all', true)} style={busy ? { opacity: 0.4 } : undefined}>
          <Icon name="sync" />
        </button>
      </header>
      {view.full ? view.body : <div class="page">{view.body}</div>}
    </div>
  );
}

/** Mounts the view host in eClass's content area. */
export function mountViews(): void {
  const main = document.getElementById('region-main');
  if (!main) return;
  const at = shadowHost('iut-view', (el) => main.prepend(el), `${appCss}\n${viewCss}`);
  render(<InlineView />, at);
}
