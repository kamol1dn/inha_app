// Everything eClass's bell menu lists, with its text: Today shows only the
// newest unread ones. A row opens its link when that stays on eClass.

import type { Snapshot } from '../../core/store.ts';
import { pastWhen } from '../../data/format.ts';
import { eclassTarget, isStale, NoData, OfflineRow, SourceError, Stale } from '../common.tsx';
import { noticeUrl } from '../derive.ts';

export function Notifications({ snap, now }: { snap: Snapshot; now: number }) {
  const cached = snap.cache.notifications;
  if (!cached) {
    return (
      <>
        <OfflineRow snap={snap} />
        <NoData snap={snap} service="eclass" />
      </>
    );
  }
  return (
    <div style={{ maxWidth: '760px' }}>
      <OfflineRow snap={snap} />
      <SourceError snap={snap} service="eclass" at={cached.fetchedAt} />
      {isStale(snap, 'eclass', cached.fetchedAt, now) && <Stale at={cached.fetchedAt} />}
      {!cached.value.length && <p class="t-bl" style={{ margin: '16px 0' }}>No notifications from eClass.</p>}
      <div class="rows">
        {cached.value.map((n) => {
          const url = noticeUrl(n);
          const body = (
            <>
              <div class="main">
                <span class={`wrap ${n.read ? 't-bl' : 't-ts'}`}>{n.subject}</span>
                {n.text && n.text !== n.subject && <span class="t-bm muted wrap">{n.text}</span>}
              </div>
              <span class="side t-bs muted tnum">{pastWhen(n.time, new Date(now))}</span>
            </>
          );
          return url ? (
            <a key={n.id} class="row" href={url} target={eclassTarget}>{body}</a>
          ) : (
            <div key={n.id} class="row">{body}</div>
          );
        })}
      </div>
    </div>
  );
}
