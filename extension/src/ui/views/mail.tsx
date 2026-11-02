// Mail: folders, the message list and the open message side by side, with
// search, reply, reply all, forward, delete (with undo) and new mail with files.
// Everything goes through the worker, which holds the Exchange login.

import { useEffect, useRef, useState } from 'preact/hooks';
import { addressLabel, mailFolders, outgoingFolder, type ComposeKind, type MailFolder, type MailHeader, type MailMessage } from '../../core/models.ts';
import { describeError } from '../../core/errors.ts';
import { call } from '../../core/rpc.ts';
import type { Snapshot } from '../../core/store.ts';
import { dayDateTime, pastWhen } from '../../data/format.ts';
import { fileSize, findLinks } from '../../services/mail/soap.ts';
import { Dialog, ErrorRow, frame, go, Icon, isStale, Skeleton, Stale, StatusLine } from '../common.tsx';
import { addFiles, composeFailure, draftFor, outgoing, recipientProblem, replyChoices, replyLines, textChanged, toAttachment, type Draft } from './compose.ts';

const PAGE = 30;

interface Toast {
  text: string;
  undo?: () => void;
}

const folderLabel = (f: MailFolder) => mailFolders.find((x) => x.id === f)!.label;

/** Which sentence a failed action gets: no login or no connection say so, anything else what didn't happen. */
function actionError(e: unknown, fallback: string): string {
  const { name, status } = e as { name?: string; status?: number };
  return name === 'LoginRequired' || (name === 'NetworkError' && !status) ? describeError(e, 'mail') : fallback;
}

/**
 * A folder's list, or what a search of it found: the cached inbox first, then
 * what the worker fetches. Only the newest request's answer counts, so a slow
 * answer for another folder or an older search can't replace what is on show.
 */
function useFolder(snap: Snapshot, folder: MailFolder, query: string) {
  const account = snap.logins.mail ?? null;
  const cached = folder === 'inbox' && !query ? snap.cache.inbox?.value : undefined;
  const [list, setList] = useState<MailHeader[] | null>(cached ?? null);
  const [error, setError] = useState<unknown>(null);
  const [more, setMore] = useState(true);
  const [loading, setLoading] = useState(false);
  const asked = useRef(0);
  const showing = useRef({ folder, query });
  showing.current = { folder, query };
  const listedFor = useRef(account);

  const load = async (offset: number) => {
    const mine = ++asked.current;
    const { folder, query } = showing.current;
    setLoading(true);
    try {
      const page = await (query ? call('mailSearch', folder, query, offset) : call('mailFolder', folder, offset));
      if (mine !== asked.current) return;
      setMore(page.length >= PAGE);
      setList((before) => {
        if (offset === 0) return page;
        const known = new Set((before ?? []).map((m) => m.id));
        return [...(before ?? []), ...page.filter((m) => !known.has(m.id))];
      });
      setError(null);
    } catch (e) {
      if (mine === asked.current) setError(e);
    } finally {
      if (mine === asked.current) setLoading(false);
    }
  };

  useEffect(() => {
    // Signed out or another account: none of this is theirs, not even the cache, which goes a moment after the login.
    const sameAccount = listedFor.current === account;
    listedFor.current = account;
    setList(sameAccount ? (cached ?? null) : null);
    setError(null);
    setMore(true);
    if (account) {
      void load(0);
    } else {
      asked.current++; // an answer still on its way no longer counts
      setLoading(false);
    }
  }, [folder, query, account]);

  // The worker refreshed the inbox: take its first page.
  useEffect(() => {
    if (folder === 'inbox' && !query && snap.cache.inbox) setList((before) => (before && before.length > PAGE ? before : snap.cache.inbox!.value));
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
  const [busy, setBusy] = useState(false);
  const [fetching, setFetching] = useState<string | null>(null); // the attachment being downloaded
  const [trouble, setTrouble] = useState('');
  useEffect(() => {
    setM(null);
    setError(null);
    call('mailMessage', id).then(
      (msg) => {
        setM(msg);
        if (msg.unread) {
          onRead(true);
          call('mailMarkRead', id, true).catch((e) => {
            onRead(false);
            setTrouble(actionError(e, "Couldn't mark it read in Mail."));
          });
        }
      },
      setError,
    );
  }, [id]);

  if (error) return <div class="reader"><StatusLine status="danger">{describeError(error, 'mail')}</StatusLine></div>;
  if (!m) return <div class="reader"><Skeleton lines={8} /></div>;

  const download = async (att: { id: string; name: string }) => {
    setFetching(att.id);
    setTrouble('');
    try {
      const a = await call('mailAttachment', att.id);
      const bytes = Uint8Array.from(atob(a.base64), (c) => c.charCodeAt(0));
      const url = URL.createObjectURL(new Blob([bytes], { type: a.contentType || 'application/octet-stream' }));
      const link = Object.assign(document.createElement('a'), { href: url, download: a.name });
      link.click();
      setTimeout(() => URL.revokeObjectURL(url), 30_000);
    } catch (e) {
      // An attached message has no file to give; everything else that ends here is a failed request.
      const unreadable = (e as { name?: string }).name === 'ParseError';
      setTrouble(actionError(e, unreadable ? `Couldn't download ${att.name}. An attached message opens only in Outlook on the web.` : `Couldn't download ${att.name}.`));
    } finally {
      setFetching(null);
    }
  };
  const move = async (to: MailFolder) => {
    setBusy(true);
    setTrouble('');
    try {
      onMoved(to, await call('mailMove', m.id, to));
    } catch (e) {
      setTrouble(actionError(e, `Couldn't move it to ${folderLabel(to)}.`));
      setBusy(false);
    }
  };
  const markUnread = async () => {
    setBusy(true);
    setTrouble('');
    try {
      await call('mailMarkRead', m.id, false);
      onRead(false);
    } catch (e) {
      setTrouble(actionError(e, "Couldn't mark it unread in Mail."));
    } finally {
      setBusy(false);
    }
  };
  const people = (label: string, list: { name: string; address: string }[]) =>
    list.length > 0 && (
      <div class="t-bm muted">
        {label} {list.map((a) => addressLabel(a)).join(', ')}
      </div>
    );
  const can = replyChoices(m, folder);
  const restoreTo: MailFolder = m.isDraft ? 'drafts' : 'inbox';

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
          <button class="btn" disabled={busy} onClick={() => onCompose('draft', m)}><Icon name="edit" /> Edit draft</button>
        ) : (
          <>
            {can.reply && <button class="btn" disabled={busy} onClick={() => onCompose('reply', m)}><Icon name="reply" /> Reply</button>}
            {can.replyAll && <button class="btn" disabled={busy} onClick={() => onCompose('replyAll', m)}><Icon name="replyAll" /> Reply all</button>}
            <button class="btn" disabled={busy} onClick={() => onCompose('forward', m)}><Icon name="forward" /> Forward</button>
          </>
        )}
        {folder === 'deleted' ? (
          <button class="btn quiet" disabled={busy} onClick={() => move(restoreTo)}><Icon name={m.isDraft ? 'edit' : 'inbox'} /> Move to {folderLabel(restoreTo)}</button>
        ) : (
          <button class="btn quiet" disabled={busy} onClick={() => move('deleted')}><Icon name="delete" /> Delete</button>
        )}
        {folder === 'junk' ? (
          <button class="btn quiet" disabled={busy} onClick={() => move('inbox')}>Not junk</button>
        ) : (
          folder === 'inbox' && <button class="btn quiet" disabled={busy} onClick={() => move('junk')}><Icon name="junk" /> Junk</button>
        )}
        {!outgoingFolder(folder) && (
          <button class="btn quiet" disabled={busy} onClick={markUnread}>
            <Icon name="unread" /> Mark unread
          </button>
        )}
      </div>
      {trouble && <div class="trouble"><StatusLine status="danger">{trouble}</StatusLine></div>}
      {m.attachments.length > 0 && (
        <div class="attachments">
          {m.attachments.map((a) => (
            <button key={a.id} disabled={fetching === a.id} onClick={() => download(a)}>
              <Icon name="attach" /> {a.name} <span class="muted">{fetching === a.id ? 'Downloading…' : a.size ? fileSize(a.size) : ''}</span>
            </button>
          ))}
        </div>
      )}
      <Body text={m.body} />
    </article>
  );
}

/** A recipient line with directory suggestions for the word being typed, shown only while the line has focus. */
function RecipientInput({ label, value, onInput }: { label: string; value: string; onInput: (v: string) => void }) {
  const [hits, setHits] = useState<{ name: string; address: string }[]>([]);
  const [pick, setPick] = useState(0);
  const focused = useRef(false);
  const last = value.split(/[,;]/).pop()!.trim();
  useEffect(() => {
    if (last.length < 3 || last.includes('@')) {
      setHits([]);
      return;
    }
    let live = true; // an answer to what is no longer being typed is ignored
    const timer = setTimeout(() => {
      call('mailLookup', last).then(
        (r) => {
          if (!live || !focused.current) return;
          setHits(r.slice(0, 8));
          setPick(0);
        },
        () => live && setHits([]),
      );
    }, 250);
    return () => {
      live = false;
      clearTimeout(timer);
    };
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
        onFocus={() => {
          focused.current = true;
        }}
        onBlur={() => {
          focused.current = false;
          setHits([]);
        }}
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

const FixedLine = ({ label, text }: { label: string; text: string }) => (
  <div class="line">
    <span class="t-bm muted">{label}</span>
    <span class="fixed">{text}</span>
  </div>
);

/** What Mail asks of an open composer before leaving it. */
interface ComposerHandle {
  dirty: () => boolean;
  /** What it is doing right now, which can't be left. */
  busy: () => 'sending' | 'saving' | null;
  /** Saves it to Drafts. False when that failed; the composer says why and stays. */
  save: () => Promise<boolean>;
}

function Compose({ start, handle, onDone, onClose, onToTab, onSaveFailed }: { start: Draft; handle: { current: ComposerHandle | null }; onDone: (sent: boolean) => void; onClose: () => void; onToTab: () => void; onSaveFailed: () => void }) {
  const [d, setD] = useState(start);
  const [files, setFiles] = useState<File[]>([]);
  const [showCc, setShowCc] = useState(!!(start.cc || start.bcc));
  const [busy, setBusy] = useState<'sending' | 'saving' | null>(null);
  const [error, setError] = useState('');
  const picker = useRef<HTMLInputElement>(null);
  const set = (k: keyof Draft) => (v: string) => setD({ ...d, [k]: v });

  const send = async (sending: boolean): Promise<boolean> => {
    const problem = sending ? recipientProblem(d) : null;
    if (problem) {
      setError(problem);
      return false;
    }
    setBusy(sending ? 'sending' : 'saving');
    setError('');
    const attachments = [];
    for (const f of files) {
      try {
        attachments.push(await toAttachment(f));
      } catch {
        setBusy(null);
        setError(`Couldn't read ${f.name}. Remove it and attach it again.`);
        return false;
      }
    }
    try {
      await call(sending ? 'mailSend' : 'mailSaveDraft', { ...outgoing(d, start), ...(attachments.length ? { attachments } : {}) });
    } catch (e) {
      setBusy(null);
      setError(composeFailure(e, sending, d.kind, attachments.length > 0));
      // A failed step leaves what was written in Drafts.
      if (attachments.length) onSaveFailed();
      return false;
    }
    onDone(sending);
    return true;
  };

  handle.current = {
    dirty: () => files.length > 0 || textChanged(d, start),
    busy: () => busy,
    save: () => send(false),
  };

  const pickFiles = (e: Event) => {
    const input = e.target as HTMLInputElement;
    const { files: next, problem } = addFiles(files, [...(input.files ?? [])]);
    setFiles(next);
    setError(problem ?? '');
    input.value = ''; // so the same file can be picked again after removing it
  };

  const fixed = replyLines(d);
  const onDraft = d.kind === 'draft' ? (d.ref?.attachments ?? []) : [];
  return (
    <div class="reader compose">
      <h2>{{ fresh: 'New message', reply: 'Reply', replyAll: 'Reply all', forward: 'Forward', draft: 'Draft' }[d.kind]}</h2>
      {/* While it goes out, what is on screen is what is being sent. */}
      <fieldset disabled={!!busy}>
        {fixed ? (
          <>
            <FixedLine label="To" text={fixed.to} />
            {fixed.cc && <FixedLine label="Cc" text={fixed.cc} />}
          </>
        ) : (
          <>
            <RecipientInput label="To" value={d.to} onInput={set('to')} />
            {showCc ? (
              <>
                <RecipientInput label="Cc" value={d.cc} onInput={set('cc')} />
                <RecipientInput label="Bcc" value={d.bcc} onInput={set('bcc')} />
              </>
            ) : (
              <button class="btn quiet" style={{ marginLeft: '52px' }} onClick={() => setShowCc(true)}>Cc, Bcc</button>
            )}
          </>
        )}
        {d.kind === 'fresh' || d.kind === 'draft' ? (
          <div class="line">
            <label>Subject</label>
            <input value={d.subject} aria-label="Subject" onInput={(e) => set('subject')((e.target as HTMLInputElement).value)} />
          </div>
        ) : (
          <FixedLine label="Subject" text={d.subject} />
        )}
        {onDraft.length + files.length > 0 && (
          <div class="files rows">
            {onDraft.map((a) => (
              <div key={a.id} class="file">
                <Icon name="attach" />
                <span class="ellipsis">{a.name}</span>
                <span class="t-bs muted">{a.size ? `${fileSize(a.size)} · ` : ''}On the draft</span>
              </div>
            ))}
            {files.map((f, i) => (
              <div key={`${f.name}/${f.size}/${f.lastModified}`} class="file">
                <Icon name="attach" />
                <span class="ellipsis">{f.name}</span>
                <span class="t-bs muted">{fileSize(f.size)}</span>
                <button class="icon-btn" aria-label={`Remove ${f.name}`} title={`Remove ${f.name}`} onClick={() => setFiles(files.filter((_, at) => at !== i))}>
                  <Icon name="close" />
                </button>
              </div>
            ))}
          </div>
        )}
        <textarea value={d.body} aria-label="Message" placeholder="Write your message" onInput={(e) => set('body')((e.target as HTMLTextAreaElement).value)} />
        {d.kind === 'forward' && <p class="t-bm muted">The original message and its attachments go below what you write.</p>}
        {fixed && <p class="t-bm muted">The message you are replying to is quoted below what you write.</p>}
        {error && <div class="trouble"><StatusLine status="danger">{error}</StatusLine></div>}
        <div class="send-row">
          <button class="btn filled" onClick={() => send(true)}>{busy === 'sending' ? 'Sending…' : 'Send'}</button>
          <button class="btn" onClick={() => send(false)}>{busy === 'saving' ? 'Saving…' : 'Save draft'}</button>
          {/* A file dialog takes the focus, which closes the toolbar popup and what is written in it. So does the tab, so that way out asks first. */}
          {frame === 'popup' ? (
            <button class="btn quiet" onClick={onToTab}>Open Mail in a tab to attach files</button>
          ) : (
            <>
              <button class="btn quiet" onClick={() => picker.current?.click()}><Icon name="attach" /> Attach file</button>
              <input ref={picker} type="file" multiple hidden aria-label="Attach file" onChange={pickFiles} />
            </>
          )}
          {/* A saved draft stays in Drafts whatever happens here, so this only closes it. */}
          <button class="btn quiet" onClick={onClose}>{d.kind === 'draft' ? 'Close' : 'Discard'}</button>
        </div>
      </fieldset>
    </div>
  );
}

/** The search field above a folder's list. Searches a moment after typing stops; Enter searches now. */
function SearchBox({ label, onQuery }: { label: string; onQuery: (q: string) => void }) {
  const [typed, setTyped] = useState('');
  const timer = useRef<ReturnType<typeof setTimeout>>();
  useEffect(() => () => clearTimeout(timer.current), []);
  const typing = (text: string) => {
    setTyped(text);
    clearTimeout(timer.current);
    const q = text.trim();
    if (!q) onQuery('');
    else if (q.length >= 2) timer.current = setTimeout(() => onQuery(q), 350);
  };
  const now = () => {
    clearTimeout(timer.current);
    onQuery(typed.trim());
  };
  const clear = () => {
    clearTimeout(timer.current);
    setTyped('');
    onQuery('');
  };
  return (
    <div class="search" role="search">
      <input
        type="text"
        value={typed}
        placeholder={`Search ${label}`}
        aria-label={`Search ${label}`}
        onInput={(e) => typing((e.target as HTMLInputElement).value)}
        onKeyDown={(e) => {
          if (e.key === 'Enter') now();
          if (e.key === 'Escape') clear();
        }}
      />
      {typed && (
        <button class="icon-btn" aria-label="Clear search" title="Clear search" onClick={clear}>
          <Icon name="close" />
        </button>
      )}
    </div>
  );
}

export function Mail({ snap, now, route }: { snap: Snapshot; now: number; route: string[] }) {
  const folder = (mailFolders.some((f) => f.id === route[1]) ? route[1] : 'inbox') as MailFolder;
  const openId = route[2] ?? null;
  const label = folderLabel(folder);
  // A search belongs to the folder it was typed in; moving on shows the next folder whole.
  const [searched, setSearched] = useState({ folder, query: '' });
  const query = searched.folder === folder ? searched.query : '';
  const { list, setList, error, more, loading, loadMore, reload } = useFolder(snap, folder, query);
  const [compose, setCompose] = useState<Draft | null>(route[0] === 'compose' ? draftFor('fresh') : null);
  const [toast, setToast] = useState<Toast | null>(null);
  const [asking, setAsking] = useState<{ then: () => void } | null>(null); // leaving unsaved writing: keep it or not
  const composer = useRef<ComposerHandle | null>(null);
  const leftBehind = useRef<string | null>(null); // a sent draft or another account's message: its route is still on show until the hash change is heard
  const counts = snap.cache.mailCounts?.value ?? {};
  const mailErr = snap.state.mail?.error;

  const account = snap.logins.mail ?? null;
  const readingFor = useRef(account);
  if (readingFor.current !== account) {
    readingFor.current = account;
    leftBehind.current = openId;
  }
  if (openId !== leftBehind.current) leftBehind.current = null;

  useEffect(() => setSearched({ folder, query: '' }), [folder]);

  // Signed out, or another account now: what was open or being written goes, in every open tab.
  const settled = useRef(false);
  useEffect(() => {
    if (!settled.current) {
      settled.current = true;
      return;
    }
    closeComposer();
    setAsking(null);
    setToast(null);
    setSearched({ folder, query: '' });
    if (openId) go(`mail/${folder}`);
  }, [account]);

  useEffect(() => {
    if (!toast) return;
    const t = setTimeout(() => setToast(null), 6000);
    return () => clearTimeout(t);
  }, [toast]);

  const closeComposer = () => {
    composer.current = null;
    setCompose(null);
  };

  /** Does `then` once the composer is out of the way, asking first if that would lose what is written. */
  const leave = (then: () => void) => {
    const busy = composer.current?.busy();
    if (busy) setToast({ text: busy === 'sending' ? 'Still sending this message.' : 'Still saving this draft.' });
    else if (composer.current?.dirty()) setAsking({ then });
    else {
      closeComposer();
      then();
    }
  };

  // Leaving Mail itself. A hash change has already happened when it is heard, so
  // it is put back (before the listener in useRoute reads it: capture listeners
  // on the window run first) and made again once the student has answered.
  useEffect(() => {
    const onHash = (e: HashChangeEvent) => {
      const c = composer.current;
      if (!c || (!c.busy() && !c.dirty()) || /^#\/(mail|compose)(\/|\?|$)/.test(location.hash)) return;
      const to = location.hash;
      history.replaceState(history.state, '', e.oldURL);
      leave(() => {
        location.hash = to;
      });
    };
    const onUnload = (e: BeforeUnloadEvent) => {
      const c = composer.current;
      if (c && (c.busy() || c.dirty())) {
        e.preventDefault();
        e.returnValue = '';
      }
    };
    addEventListener('hashchange', onHash, true);
    addEventListener('beforeunload', onUnload);
    return () => {
      removeEventListener('hashchange', onHash, true);
      removeEventListener('beforeunload', onUnload);
    };
  }, []);

  if (!account) return <ErrorRow service="mail" error={{ name: 'LoginRequired', message: '' }} />;

  const open = (id: string) => leave(() => go(`mail/${folder}/${encodeURIComponent(id)}`));
  const markLocal = (id: string, unread: boolean) => setList((l) => l?.map((m) => (m.id === id ? { ...m, unread } : m)) ?? l);

  return (
    <div class="mail">
      <nav class="folders" aria-label="Folders">
        <div style={{ padding: '0 12px 12px' }}>
          <button
            class="btn filled"
            style={{ width: '100%' }}
            onClick={() => {
              if (compose?.kind !== 'fresh') leave(() => setCompose(draftFor('fresh')));
            }}
          >
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
        <SearchBox key={folder} label={label} onQuery={(q) => setSearched({ folder, query: q })} />
        {mailErr && folder === 'inbox' && <ErrorRow service="mail" error={mailErr} />}
        {folder === 'inbox' && !query && snap.cache.inbox && isStale(snap, 'mail', snap.cache.inbox.fetchedAt, now) && (
          <div style={{ padding: '8px 16px' }}><Stale at={snap.cache.inbox.fetchedAt} /></div>
        )}
        {error != null && !list?.length ? (
          <div style={{ padding: '16px' }}>
            <StatusLine status="danger">{describeError(error, 'mail')}</StatusLine>
            <button class="btn" onClick={reload}>Try again</button>
          </div>
        ) : !list ? (
          <div style={{ padding: '0 16px' }}><Skeleton lines={8} /></div>
        ) : !list.length ? (
          <p class="empty" style={{ padding: '16px' }}>{query ? `No mail matches "${query}" in ${label}.` : `Nothing in ${label}.`}</p>
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
            {(more || error != null) && (
              <div style={{ padding: '8px 16px' }}>
                {error != null && <div class="trouble"><StatusLine status="danger">{describeError(error, 'mail')}</StatusLine></div>}
                {more ? (
                  <button class="btn" disabled={loading} onClick={loadMore}>{loading ? 'Loading…' : 'Older messages'}</button>
                ) : (
                  <button class="btn" disabled={loading} onClick={reload}>Try again</button>
                )}
              </div>
            )}
          </div>
        )}
      </div>

      {compose ? (
        <Compose
          key={JSON.stringify([compose.kind, compose.ref?.id])}
          start={compose}
          handle={composer}
          onClose={() => leave(() => {})}
          onToTab={() => {
            // Anything written is on its way to Drafts, or let go, by the time the tab opens.
            const to = composer.current?.dirty() ? 'drafts' : folder;
            leave(() => void chrome.tabs.create({ url: chrome.runtime.getURL(`pages/app.html#/mail/${to}`) }));
          }}
          onSaveFailed={() => {
            if (folder === 'drafts') reload();
          }}
          onDone={(sent) => {
            closeComposer();
            setToast({ text: sent ? 'Sent' : 'Saved to Drafts' });
            // A sent draft has left Drafts: its id no longer opens anything.
            if (sent && compose.kind === 'draft') {
              leftBehind.current = compose.ref?.id ?? null;
              go(`mail/${folder}`);
            }
            if (folder === 'drafts' || folder === 'sent') reload();
          }}
        />
      ) : openId && openId !== leftBehind.current ? (
        <Reader
          key={openId}
          id={openId}
          folder={folder}
          onRead={(read) => markLocal(openId, !read)}
          onCompose={(kind, m) => setCompose(draftFor(kind, m))}
          onMoved={(to, newId) => {
            setList((l) => l?.filter((m) => m.id !== openId) ?? l);
            go(`mail/${folder}`);
            setToast({
              text: to === 'deleted' ? 'Deleted' : `Moved to ${folderLabel(to)}`,
              undo:
                newId
                  ? async () => {
                      try {
                        await call('mailMove', newId, folder);
                        reload();
                      } catch (e) {
                        setToast({ text: actionError(e, `Couldn't move it back to ${label}.`) });
                      }
                    }
                  : undefined,
            });
          }}
        />
      ) : (
        <div class="reader empty">Choose a message to read it.</div>
      )}

      {asking && (
        <Dialog title={compose?.kind === 'draft' ? 'Save your changes?' : 'Keep this as a draft?'} onClose={() => setAsking(null)}>
          <div class="actions">
            <button
              class="btn"
              onClick={() => {
                const { then } = asking;
                setAsking(null);
                closeComposer();
                then();
              }}
            >
              Discard
            </button>
            <button
              class="btn"
              onClick={async () => {
                const { then } = asking;
                setAsking(null);
                if (await composer.current?.save()) then();
              }}
            >
              Save draft
            </button>
          </div>
        </Dialog>
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
