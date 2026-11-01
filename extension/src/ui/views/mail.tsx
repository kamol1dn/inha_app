// Mail: folders, the message list and the open message side by side, with
// reply, reply all, forward, delete (with undo) and new mail. Everything goes
// through the worker, which holds the Exchange login.

import { useEffect, useRef, useState } from 'preact/hooks';
import { addressLabel, mailFolders, outgoingFolder, type ComposeKind, type MailFolder, type MailHeader, type MailMessage } from '../../core/models.ts';
import { describeError } from '../../core/errors.ts';
import { call } from '../../core/rpc.ts';
import type { Snapshot } from '../../core/store.ts';
import { dayDateTime, pastWhen } from '../../data/format.ts';
import { composeError, fileSize, findLinks, parseRecipients, replyAllRecipients } from '../../services/mail/soap.ts';
import { ErrorRow, go, Icon, isStale, Skeleton, Stale, StatusLine } from '../common.tsx';

const PAGE = 30;

interface Toast {
  text: string;
  undo?: () => void;
}

/** A folder's list: the cached inbox first, then what the worker fetches. */
function useFolder(snap: Snapshot, folder: MailFolder) {
  const cached = folder === 'inbox' ? snap.cache.inbox?.value : undefined;
  const [list, setList] = useState<MailHeader[] | null>(cached ?? null);
  const [error, setError] = useState<unknown>(null);
  const [more, setMore] = useState(true);
  const [loading, setLoading] = useState(false);

  const load = async (offset: number) => {
    setLoading(true);
    try {
      const page = await call('mailFolder', folder, offset);
      setMore(page.length >= PAGE);
      setList((before) => {
        if (offset === 0) return page;
        const known = new Set((before ?? []).map((m) => m.id));
        return [...(before ?? []), ...page.filter((m) => !known.has(m.id))];
      });
      setError(null);
    } catch (e) {
      setError(e);
    } finally {
      setLoading(false);
    }
  };

  useEffect(() => {
    setList(folder === 'inbox' ? snap.cache.inbox?.value ?? null : null);
    void load(0);
  }, [folder]);

  // The worker refreshed the inbox: take its first page.
  useEffect(() => {
    if (folder === 'inbox' && snap.cache.inbox) setList((before) => (before && before.length > PAGE ? before : snap.cache.inbox!.value));
  }, [snap.cache.inbox?.fetchedAt]);

  return { list, setList, error, more, loading, loadMore: () => load(list?.length ?? 0), reload: () => load(0) };
}

/** A plain-text body with its links made clickable. */
function Body({ text }: { text: string }) {
  const parts = [];
  let at = 0;
  for (const l of findLinks(text)) {
    if (l.start > at) parts.push(text.slice(at, l.start));
    parts.push(
      <a key={l.start} href={l.url} target="_blank" rel="noopener noreferrer">
        {l.label}
      </a>,
    );
    at = l.end;
  }
  parts.push(text.slice(at));
  return <div class="body">{parts}</div>;
}

function Reader({ id, folder, onCompose, onMoved, onRead }: { id: string; folder: MailFolder; onCompose: (kind: ComposeKind, m: MailMessage) => void; onMoved: (to: MailFolder, newId: string | null) => void; onRead: (read: boolean) => void }) {
  const [m, setM] = useState<MailMessage | null>(null);
  const [error, setError] = useState<unknown>(null);
  useEffect(() => {
    setM(null);
    setError(null);
    call('mailMessage', id).then(
      (msg) => {
        setM(msg);
        if (msg.unread) {
          void call('mailMarkRead', id, true);
          onRead(true);
        }
      },
      setError,
    );
  }, [id]);

  if (error) return <div class="reader"><StatusLine status="danger">{describeError(error, 'mail')}</StatusLine></div>;
  if (!m) return <div class="reader"><Skeleton lines={8} /></div>;

  const download = async (attId: string) => {
    const a = await call('mailAttachment', attId);
    const bytes = Uint8Array.from(atob(a.base64), (c) => c.charCodeAt(0));
    const url = URL.createObjectURL(new Blob([bytes], { type: a.contentType || 'application/octet-stream' }));
    const link = Object.assign(document.createElement('a'), { href: url, download: a.name });
    link.click();
    setTimeout(() => URL.revokeObjectURL(url), 30_000);
  };
  const move = async (to: MailFolder) => onMoved(to, await call('mailMove', m.id, to));
  const people = (label: string, list: { name: string; address: string }[]) =>
    list.length > 0 && (
      <div class="t-bm muted">
        {label} {list.map((a) => addressLabel(a)).join(', ')}
      </div>
    );

  return (
    <article class="reader">
      <h2>{m.subject || '(no subject)'}</h2>
      <div class="t-ts">
        {m.from} {m.fromAddress && m.fromAddress !== m.from && <span class="t-bm muted">&lt;{m.fromAddress}&gt;</span>}
      </div>
      {people('To', m.to)}
      {people('Cc', m.cc)}
      <div class="t-bs muted">{dayDateTime(m.received)}</div>
      <div class="actions">
        {m.isDraft ? (
          <button class="btn" onClick={() => onCompose('draft', m)}><Icon name="edit" /> Edit draft</button>
        ) : (
          <>
            <button class="btn" onClick={() => onCompose('reply', m)}><Icon name="reply" /> Reply</button>
            <button class="btn" onClick={() => onCompose('replyAll', m)}><Icon name="replyAll" /> Reply all</button>
            <button class="btn" onClick={() => onCompose('forward', m)}><Icon name="forward" /> Forward</button>
          </>
        )}
        {folder !== 'deleted' && <button class="btn quiet" onClick={() => move('deleted')}><Icon name="delete" /> Delete</button>}
        {folder === 'junk' ? (
          <button class="btn quiet" onClick={() => move('inbox')}>Not junk</button>
        ) : (
          folder === 'inbox' && <button class="btn quiet" onClick={() => move('junk')}><Icon name="junk" /> Junk</button>
        )}
        {!outgoingFolder(folder) && (
          <button class="btn quiet" onClick={() => { void call('mailMarkRead', m.id, false); onRead(false); }}>
            <Icon name="unread" /> Mark unread
          </button>
        )}
      </div>
      {m.attachments.length > 0 && (
        <div class="attachments">
          {m.attachments.map((a) => (
            <button key={a.id} onClick={() => download(a.id)}>
              <Icon name="attach" /> {a.name} <span class="muted">{a.size ? fileSize(a.size) : ''}</span>
            </button>
          ))}
        </div>
      )}
      <Body text={m.body} />
    </article>
  );
}

interface Draft {
  kind: ComposeKind;
  ref?: MailMessage;
  to: string;
  cc: string;
  bcc: string;
  subject: string;
  body: string;
}

function draftFor(kind: ComposeKind, m?: MailMessage): Draft {
  const join = (l: { name: string; address: string }[]) => l.map((a) => a.address).join(', ');
  if (!m) return { kind, to: '', cc: '', bcc: '', subject: '', body: '' };
  if (kind === 'draft') return { kind, ref: m, to: join(m.to), cc: join(m.cc), bcc: join(m.bcc), subject: m.subject, body: m.body };
  if (kind === 'replyAll') {
    const r = replyAllRecipients(m);
    return { kind, ref: m, to: join(r.to), cc: join(r.cc), bcc: '', subject: `RE: ${m.subject}`, body: '' };
  }
  if (kind === 'reply') return { kind, ref: m, to: m.fromAddress, cc: '', bcc: '', subject: `RE: ${m.subject}`, body: '' };
  return { kind, ref: m, to: '', cc: '', bcc: '', subject: `FW: ${m.subject}`, body: '' };
}

/** A recipient line with directory suggestions for the word being typed. */
function RecipientInput({ label, value, onInput }: { label: string; value: string; onInput: (v: string) => void }) {
  const [hits, setHits] = useState<{ name: string; address: string }[]>([]);
  const [pick, setPick] = useState(0);
  const timer = useRef<ReturnType<typeof setTimeout>>();
  const last = value.split(/[,;]/).pop()!.trim();
  useEffect(() => {
    clearTimeout(timer.current);
    if (last.length < 2 || last.includes('@')) return setHits([]);
    timer.current = setTimeout(() => call('mailLookup', last).then((r) => (setHits(r.slice(0, 8)), setPick(0)), () => setHits([])), 250);
  }, [last]);
  const choose = (a: { address: string }) => {
    const parts = value.split(/[,;]/);
    parts[parts.length - 1] = ` ${a.address}`;
    onInput(`${parts.join(',').trim()}, `);
    setHits([]);
  };
  return (
    <div class="line" style={{ position: 'relative' }}>
      <label>{label}</label>
      <input
        value={value}
        aria-label={label}
        onInput={(e) => onInput((e.target as HTMLInputElement).value)}
        onKeyDown={(e) => {
          if (!hits.length) return;
          if (e.key === 'ArrowDown') (setPick((pick + 1) % hits.length), e.preventDefault());
          if (e.key === 'ArrowUp') (setPick((pick - 1 + hits.length) % hits.length), e.preventDefault());
          if (e.key === 'Enter' || e.key === 'Tab') (choose(hits[pick]), e.preventDefault());
          if (e.key === 'Escape') setHits([]);
        }}
      />
      {hits.length > 0 && (
        <div class="suggest" style={{ top: '44px', left: '64px' }}>
          {hits.map((h, i) => (
            <button key={h.address} class={i === pick ? 'on' : ''} onMouseDown={(e) => (e.preventDefault(), choose(h))}>
              <div class="t-ts">{h.name || h.address}</div>
              <div class="t-bs muted">{h.address}</div>
            </button>
          ))}
        </div>
      )}
    </div>
  );
}

function Compose({ start, onDone }: { start: Draft; onDone: (sent: boolean, text: string) => void }) {
  const [d, setD] = useState(start);
  const [showCc, setShowCc] = useState(!!(start.cc || start.bcc));
  const [busy, setBusy] = useState(false);
  const [error, setError] = useState('');
  const set = (k: keyof Draft) => (v: string) => setD({ ...d, [k]: v });
  const outgoing = () => ({
    kind: d.kind,
    ref: d.ref ? { id: d.ref.id, changeKey: d.ref.changeKey } : undefined,
    to: parseRecipients(d.to),
    cc: parseRecipients(d.cc),
    bcc: parseRecipients(d.bcc),
    subject: d.kind === 'reply' || d.kind === 'replyAll' || d.kind === 'forward' ? undefined : d.subject,
    body: d.body,
  });
  const send = async (sending: boolean) => {
    if (sending && d.kind !== 'reply' && d.kind !== 'replyAll' && !parseRecipients(d.to).length) return setError('Add someone to send it to.');
    setBusy(true);
    setError('');
    try {
      await call(sending ? 'mailSend' : 'mailSaveDraft', outgoing());
      onDone(true, sending ? 'Sent' : 'Saved to Drafts');
    } catch (e) {
      setError(composeError(e, sending));
    } finally {
      setBusy(false);
    }
  };
  const replying = d.kind === 'reply' || d.kind === 'replyAll';
  return (
    <div class="reader compose">
      <h2>{{ fresh: 'New message', reply: 'Reply', replyAll: 'Reply all', forward: 'Forward', draft: 'Draft' }[d.kind]}</h2>
      <RecipientInput label="To" value={d.to} onInput={set('to')} />
      {showCc ? (
        <>
          <RecipientInput label="Cc" value={d.cc} onInput={set('cc')} />
          <RecipientInput label="Bcc" value={d.bcc} onInput={set('bcc')} />
        </>
      ) : (
        <button class="btn quiet" style={{ marginLeft: '52px' }} onClick={() => setShowCc(true)}>Cc and Bcc</button>
      )}
      {!replying && d.kind !== 'forward' && (
        <div class="line">
          <label>Subject</label>
          <input value={d.subject} aria-label="Subject" onInput={(e) => set('subject')((e.target as HTMLInputElement).value)} />
        </div>
      )}
      {(replying || d.kind === 'forward') && <p class="t-bm muted">{d.subject} · Exchange adds the original below your text.</p>}
      <textarea value={d.body} aria-label="Message" placeholder="Write your message" onInput={(e) => set('body')((e.target as HTMLTextAreaElement).value)} />
      {error && <StatusLine status="danger">{error}</StatusLine>}
      <div style={{ display: 'flex', gap: '8px', marginTop: '12px' }}>
        <button class="btn filled" disabled={busy} onClick={() => send(true)}>{busy ? 'Sending…' : 'Send'}</button>
        <button class="btn" disabled={busy} onClick={() => send(false)}>Save draft</button>
        <button class="btn quiet" disabled={busy} onClick={() => onDone(false, '')}>Discard</button>
      </div>
    </div>
  );
}

export function Mail({ snap, now, route }: { snap: Snapshot; now: number; route: string[] }) {
  const folder = (mailFolders.some((f) => f.id === route[1]) ? route[1] : 'inbox') as MailFolder;
  const openId = route[2] ?? null;
  const { list, setList, error, more, loading, loadMore, reload } = useFolder(snap, folder);
  const [compose, setCompose] = useState<Draft | null>(route[0] === 'compose' ? draftFor('fresh') : null);
  const [toast, setToast] = useState<Toast | null>(null);
  const counts = snap.cache.mailCounts?.value ?? {};
  const mailErr = snap.state.mail?.error;

  useEffect(() => {
    if (!toast) return;
    const t = setTimeout(() => setToast(null), 6000);
    return () => clearTimeout(t);
  }, [toast]);

  if (!snap.logins.mail && !list) {
    return mailErr ? <ErrorRow service="mail" error={mailErr} /> : <ErrorRow service="mail" error={{ name: 'LoginRequired', message: '' }} />;
  }

  const open = (id: string) => {
    setCompose(null);
    go(`mail/${folder}/${encodeURIComponent(id)}`);
  };
  const markLocal = (id: string, unread: boolean) => setList((l) => l?.map((m) => (m.id === id ? { ...m, unread } : m)) ?? l);

  return (
    <div class="mail">
      <nav class="folders" aria-label="Folders">
        <div style={{ padding: '0 12px 12px' }}>
          <button class="btn filled" style={{ width: '100%' }} onClick={() => setCompose(draftFor('fresh'))}>
            <Icon name="edit" /> New
          </button>
        </div>
        {mailFolders.map((f) => (
          <a key={f.id} href={`#/mail/${f.id}`} class={f.id === folder ? 'on' : ''}>
            <span>{f.label}</span>
            <span class="tnum">{f.id === 'drafts' ? counts[f.id]?.total || '' : counts[f.id]?.unread || ''}</span>
          </a>
        ))}
      </nav>

      <div class="list">
        {mailErr && folder === 'inbox' && <ErrorRow service="mail" error={mailErr} />}
        {folder === 'inbox' && snap.cache.inbox && isStale(snap, 'mail', snap.cache.inbox.fetchedAt, now) && (
          <div style={{ padding: '8px 16px' }}><Stale at={snap.cache.inbox.fetchedAt} /></div>
        )}
        {error != null && !list ? (
          <div style={{ padding: '16px' }}>
            <StatusLine status="danger">{describeError(error, 'mail')}</StatusLine>
            <button class="btn" onClick={reload}>Try again</button>
          </div>
        ) : !list ? (
          <div style={{ padding: '0 16px' }}><Skeleton lines={8} /></div>
        ) : !list.length ? (
          <p class="empty" style={{ padding: '16px' }}>Nothing in {mailFolders.find((f) => f.id === folder)!.label}.</p>
        ) : (
          <div class="rows">
            {list.map((m) => (
              <button key={m.id} class={`row ${m.id === openId ? 'on' : ''}`} onClick={() => open(m.id)}>
                <div class="main">
                  <span class={`t-bm ellipsis ${m.unread ? '' : 'muted'}`} style={m.unread ? { fontWeight: 600 } : undefined}>
                    {outgoingFolder(folder) ? `To ${m.to || '(no recipients)'}` : m.from}
                  </span>
                  <span class={`subject ellipsis ${m.unread ? 'unread t-ts' : 't-bl'}`}>{m.subject || '(no subject)'}</span>
                  {m.preview && <span class="t-bs muted ellipsis">{m.preview}</span>}
                </div>
                <div class="side t-bs muted">
                  <span>{pastWhen(m.received)}</span>
                  {m.hasAttachments && <span style={{ width: '16px' }}><Icon name="attach" title="Attachment" /></span>}
                </div>
              </button>
            ))}
            {more && (
              <div style={{ padding: '8px 16px' }}>
                <button class="btn" disabled={loading} onClick={loadMore}>{loading ? 'Loading…' : 'Older messages'}</button>
              </div>
            )}
          </div>
        )}
      </div>

      {compose ? (
        <Compose
          key={JSON.stringify([compose.kind, compose.ref?.id])}
          start={compose}
          onDone={(_, text) => {
            setCompose(null);
            if (text) {
              setToast({ text });
              if (folder === 'drafts' || folder === 'sent') reload();
            }
          }}
        />
      ) : openId ? (
        <Reader
          key={openId}
          id={openId}
          folder={folder}
          onRead={(read) => markLocal(openId, !read)}
          onCompose={(kind, m) => setCompose(draftFor(kind, m))}
          onMoved={(to, newId) => {
            const gone = list?.find((m) => m.id === openId);
            setList((l) => l?.filter((m) => m.id !== openId) ?? l);
            go(`mail/${folder}`);
            setToast({
              text: to === 'deleted' ? 'Deleted' : to === 'junk' ? 'Moved to Junk' : 'Moved to Inbox',
              undo:
                newId && gone
                  ? async () => {
                      await call('mailMove', newId, folder);
                      reload();
                    }
                  : undefined,
            });
          }}
        />
      ) : (
        <div class="reader empty">Choose a message to read it.</div>
      )}

      {toast && (
        <div class="toast" role="status">
          {toast.text}
          {toast.undo && (
            <button class="btn" onClick={() => (toast.undo!(), setToast(null))}>Undo</button>
          )}
        </div>
      )}
    </div>
  );
}
