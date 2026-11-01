// The Mail view, drawn for real: mail.tsx is bundled as the build does and
// rendered into linkedom, with a fake location that fires hashchange the way a
// browser does (capture listeners first) and a fake worker behind `call`.

import { afterEach, beforeEach, test } from 'node:test';
import assert from 'node:assert/strict';
import { fileURLToPath } from 'node:url';
import * as esbuild from 'esbuild';
import { parseHTML } from 'linkedom';
import type { MailHeader, MailMessage } from '../src/core/models.ts';
import { maxAttachmentBytes } from '../src/services/mail/soap.ts';
import { addFiles, base64Of, composeFailure, draftFor, outgoing, recipientProblem, replyChoices, replyLines, textChanged } from '../src/ui/views/compose.ts';

const { window, document } = parseHTML('<!doctype html><html><head></head><body><div id="app"></div></body></html>');
const root = document.getElementById('app')!;

// Preact infers an event's casing from these being on the element.
for (const e of ['click', 'input', 'change', 'keydown', 'mousedown', 'focus', 'blur']) {
  (window.HTMLElement.prototype as unknown as Record<string, unknown>)[`on${e}`] = null;
}

type Listener = (e: unknown) => void;
const listeners: { type: string; fn: Listener; capture: boolean }[] = [];
let hash = '';
const url = () => `ext://app${hash}`;
const fire = (type: string, e: Record<string, unknown>) => {
  const all = listeners.filter((l) => l.type === type);
  for (const l of [...all.filter((x) => x.capture), ...all.filter((x) => !x.capture)]) l.fn(e);
};

const g = globalThis as unknown as Record<string, unknown>;
g.__DEV__ = false;
g.document = document;
g.requestAnimationFrame = (cb: () => void) => setTimeout(cb, 0);
g.cancelAnimationFrame = clearTimeout;
g.addEventListener = (type: string, fn: Listener, capture?: boolean) => void listeners.push({ type, fn, capture: !!capture });
g.removeEventListener = (type: string, fn: Listener) => {
  const at = listeners.findIndex((l) => l.type === type && l.fn === fn);
  if (at >= 0) listeners.splice(at, 1);
};
g.location = {
  host: 'ext',
  search: '',
  get hash() {
    return hash;
  },
  set hash(to: string) {
    const oldURL = url();
    hash = to === '' ? '' : to.startsWith('#') ? to : `#${to}`;
    // A browser fires it a task later, and not at all for the same hash.
    if (url() !== oldURL) setTimeout(() => fire('hashchange', { oldURL, newURL: url() }), 0);
  },
};
g.history = {
  state: null,
  replaceState: (_: unknown, __: string, to: string) => {
    hash = to.includes('#') ? to.slice(to.indexOf('#')) : '';
  },
};

// The fake worker. Each test sets `answer`; what it was asked is in `asked`.
type Asked = { rpc: string; args: unknown[] };
const asked: Asked[] = [];
let answer: (rpc: string, args: unknown[]) => unknown = () => [];
g.chrome = {
  runtime: {
    getURL: (p: string) => `ext://${p}`,
    sendMessage: async ({ rpc, args }: Asked) => {
      asked.push({ rpc, args });
      try {
        return { ok: true, value: (await answer(rpc, args)) ?? null };
      } catch (e) {
        const { name, message, status } = e as Error & { status?: number };
        return { ok: false, error: { name, message, status } };
      }
    },
  },
};

const bundle = await esbuild.build({
  stdin: {
    contents: `export { Mail } from './src/ui/views/mail.tsx'; export { useRoute } from './src/ui/common.tsx'; export { h, render } from 'preact';`,
    resolveDir: fileURLToPath(new URL('..', import.meta.url)),
    loader: 'ts',
  },
  bundle: true,
  write: false,
  format: 'esm',
  target: 'es2022',
  jsx: 'automatic',
  jsxImportSource: 'preact',
  loader: { '.css': 'text' },
  define: { __DEV__: 'false' },
  logLevel: 'silent',
});
interface View {
  Mail: (p: unknown) => unknown;
  useRoute: () => string[];
  h: (type: unknown, props?: unknown, ...children: unknown[]) => unknown;
  render: (vnode: unknown, at: Element) => void;
}
const view = (await import(`data:text/javascript;base64,${Buffer.from(bundle.outputFiles[0].text).toString('base64')}`)) as View;

const snap = { cache: {}, logins: { mail: 'u' }, state: {}, settings: {} };

function App() {
  const route = view.useRoute();
  return route[0] === 'mail' || route[0] === 'compose' ? view.h(view.Mail, { snap, now: 0, route }) : view.h('div', { id: 'elsewhere' });
}

/** Waits ms, then a few more turns of the event loop: a busy machine must not outrun what is chained on timers. */
async function settle(ms = 25) {
  await new Promise((resolve) => setTimeout(resolve, ms));
  for (let i = 0; i < 8; i++) await new Promise((resolve) => setTimeout(resolve, 2));
}

async function show(at: string) {
  hash = at;
  view.render(view.h(App), root);
  await settle();
}

const buttons = () => [...root.querySelectorAll('button')] as unknown as HTMLButtonElement[];
/** By its exact words or label, else the first with those words in it (a row, or a file with its size). */
const button = (text: string) =>
  buttons().find((b) => b.textContent!.trim() === text || b.getAttribute('aria-label') === text) ?? buttons().find((b) => b.textContent!.includes(text)) ?? null;
async function click(text: string) {
  const b = button(text);
  assert.ok(b, `no button "${text}" in: ${root.textContent}`);
  b.dispatchEvent(new window.Event('click'));
  await settle();
}
async function inDialog(text: string) {
  buttons().find((b) => b.closest('.dialog') && b.textContent === text)!.dispatchEvent(new window.Event('click'));
  await settle();
}
const input = (label: string) => root.querySelector(`[aria-label="${label}"]`) as unknown as HTMLInputElement | null;
function typeIn(label: string, value: string) {
  const el = input(label);
  assert.ok(el, `no field "${label}"`);
  el.value = value;
  el.dispatchEvent(new window.Event('input'));
}
function press(label: string, key: string) {
  const e = new window.Event('keydown');
  (e as unknown as { key: string }).key = key;
  input(label)!.dispatchEvent(e);
}
const sent = (rpc: string) => asked.filter((a) => a.rpc === rpc);

const header = (id: string, subject = `Subject ${id}`): MailHeader => ({ id, from: 'Sender', to: 'Me', subject, preview: '', received: 0, unread: false, hasAttachments: false });

const message = (o: Partial<MailMessage> = {}): MailMessage => ({
  id: 'm1',
  changeKey: 'ck1',
  from: 'Prof Example',
  fromAddress: 'prof@inha.uz',
  subject: 'Lab 5',
  received: 0,
  unread: false,
  body: 'Hello',
  attachments: [],
  to: [{ name: 'Me', address: 'me@student.inha.uz' }],
  cc: [],
  bcc: [],
  receivedBy: 'me@student.inha.uz',
  isDraft: false,
  ...o,
});

/** A worker with folders of one message each and `m` behind every id. */
const worker = (m: MailMessage = message()) => (rpc: string) => {
  if (rpc === 'mailFolder' || rpc === 'mailSearch') return [header('m1', m.subject), header('m2')];
  if (rpc === 'mailMessage') return m;
  return null;
};

beforeEach(() => {
  asked.length = 0;
  answer = worker();
});

afterEach(async () => {
  view.render(null, root);
  await settle(5);
});

// ---- Pure parts ----

test('a saved draft sends only what changed', () => {
  const start = draftFor('draft', message({ isDraft: true, to: [{ name: '', address: 'a@b.uz' }] }));
  assert.deepEqual(JSON.parse(JSON.stringify(outgoing(start, start))), { kind: 'draft', ref: { id: 'm1', changeKey: 'ck1' } });
  const edited = outgoing({ ...start, cc: 'c@d.uz', body: 'New' }, start);
  assert.deepEqual(edited.cc, ['c@d.uz']);
  assert.equal(edited.body, 'New');
  assert.equal(edited.to, undefined);
  assert.equal(edited.subject, undefined);
  // An emptied line is an empty list, which deletes it, not "unchanged".
  assert.deepEqual(outgoing({ ...start, to: '' }, start).to, []);
});

test('a reply carries only its text; a forward its recipients, never a subject', () => {
  const reply = draftFor('reply', message());
  const m = outgoing({ ...reply, to: 'ignored@x.uz', body: 'Thanks' }, reply);
  assert.deepEqual(JSON.parse(JSON.stringify(m)), { kind: 'reply', ref: { id: 'm1', changeKey: 'ck1' }, body: 'Thanks' });
  const fw = draftFor('forward', message());
  const f = outgoing({ ...fw, to: 'a@b.uz' }, fw);
  assert.deepEqual(f.to, ['a@b.uz']);
  assert.equal(f.subject, undefined);
});

test('reply lines are who Exchange sends it to', () => {
  const m = message({ to: [{ name: 'Me', address: 'me@student.inha.uz' }, { name: 'Bob', address: 'bob@x.uz' }], cc: [{ name: '', address: 'cc@x.uz' }] });
  assert.deepEqual(replyLines(draftFor('reply', m)), { to: 'Prof Example', cc: '' });
  assert.deepEqual(replyLines(draftFor('replyAll', m)), { to: 'Prof Example, Bob', cc: 'cc@x.uz' });
  assert.equal(replyLines(draftFor('forward', m)), null);
  assert.equal(replyLines(draftFor('fresh')), null);
});

test('reply choices: Sent gets only Forward, Reply all needs someone besides the sender', () => {
  assert.deepEqual(replyChoices(message(), 'sent'), { reply: false, replyAll: false });
  assert.deepEqual(replyChoices(message(), 'drafts'), { reply: false, replyAll: false });
  assert.deepEqual(replyChoices(message(), 'inbox'), { reply: true, replyAll: false });
  assert.deepEqual(replyChoices(message({ cc: [{ name: 'Bob', address: 'bob@x.uz' }] }), 'inbox'), { reply: true, replyAll: true });
});

test('recipients are checked on To, Cc and Bcc, not on a reply', () => {
  assert.equal(recipientProblem(draftFor('fresh')), 'Add someone to send it to.');
  assert.equal(recipientProblem({ ...draftFor('fresh'), bcc: 'a@b.uz' }), null);
  assert.equal(recipientProblem({ ...draftFor('fresh'), to: 'nobody' }), '"nobody" is not an email address.');
  assert.equal(recipientProblem(draftFor('reply', message())), null);
});

test('files: size is checked against what is on the message, repeats and empty files stay out', () => {
  const f = (name: string, size: number) => ({ name, size, lastModified: 1 });
  const big = maxAttachmentBytes - 10;
  const first = addFiles([], [f('a.pdf', big)]);
  assert.deepEqual(first.files.map((x) => x.name), ['a.pdf']);
  assert.equal(first.problem, null);
  const over = addFiles(first.files, [f('b.pdf', 11), f('c.pdf', 10)]);
  assert.deepEqual(over.files.map((x) => x.name), ['a.pdf', 'c.pdf']);
  assert.equal(over.problem, 'b.pdf is too big to add. A message can carry 25 MB of new files.');
  assert.equal(addFiles(first.files, [f('a.pdf', big)]).files.length, 1);
  assert.equal(addFiles([], [f('e.txt', 0)]).problem, 'e.txt is empty, so it was not added.');
});

test('base64 of a file larger than one piece joins up', () => {
  const bytes = Uint8Array.from({ length: 100_001 }, (_, i) => i % 251);
  assert.equal(base64Of(bytes), Buffer.from(bytes).toString('base64'));
  assert.equal(base64Of(new Uint8Array()), '');
});

test('a failed send with files says what may be left behind', () => {
  const e = new Error('x');
  assert.equal(composeFailure(e, true, 'fresh', false), "Mail didn't send it. Try again.");
  assert.equal(composeFailure(e, true, 'fresh', true), "Mail didn't send it. Try again. A copy may be in Drafts.");
  assert.equal(composeFailure(e, false, 'draft', true), "Mail didn't save the draft. Try again. Some of the files may already be on the draft.");
});

test('textChanged sees every field', () => {
  const s = draftFor('fresh');
  assert.equal(textChanged(s, s), false);
  for (const k of ['to', 'cc', 'bcc', 'subject', 'body'] as const) assert.equal(textChanged({ ...s, [k]: 'x' }, s), true, k);
});

// ---- Reader ----

test('F61: in Sent only Forward is offered', async () => {
  await show('#/mail/sent/m1');
  assert.ok(button('Forward'));
  assert.equal(button('Reply'), null);
});

test('F61: Reply all shows only when someone else got it', async () => {
  await show('#/mail/inbox/m1');
  assert.ok(button('Reply'));
  assert.equal(button('Reply all'), null);
  view.render(null, root);
  answer = worker(message({ cc: [{ name: 'Bob', address: 'bob@x.uz' }] }));
  await show('#/mail/inbox/m1');
  assert.ok(button('Reply all'));
});

test('F59: Deleted offers Move to Inbox instead of Delete', async () => {
  await show('#/mail/deleted/m1');
  assert.equal(button('Delete'), null);
  answer = (rpc) => (rpc === 'mailMove' ? 'new-id' : worker()(rpc));
  await click('Move to Inbox');
  assert.deepEqual(sent('mailMove')[0].args, ['m1', 'inbox']);
  assert.equal(hash, '#/mail/deleted');
  assert.match(root.textContent!, /Moved to Inbox/);
});

test('F60: a failed move says so, stays, and the buttons wait while it runs', async () => {
  await show('#/mail/inbox/m1');
  let refuse!: (e: Error) => void;
  answer = (rpc) => (rpc === 'mailMove' ? new Promise((_, no) => (refuse = no)) : worker()(rpc));
  await click('Delete');
  assert.equal(button('Delete')!.disabled, true);
  refuse(Object.assign(new Error('x'), { name: 'NetworkError', status: 503 }));
  await settle();
  assert.match(root.textContent!, /Couldn't move it to Deleted\./);
  assert.equal(button('Delete')!.disabled, false);
  assert.equal(hash, '#/mail/inbox/m1');
  assert.equal(sent('mailMove').length, 1);
});

test('F60: no connection names the connection', async () => {
  await show('#/mail/inbox/m1');
  answer = (rpc) => {
    if (rpc === 'mailMarkRead') throw Object.assign(new Error('x'), { name: 'NetworkError' });
    return worker()(rpc);
  };
  await click('Mark unread');
  assert.match(root.textContent!, /Couldn't reach Mail\. Check the connection\./);
});

test('F60: an unread message that fails to mark read goes back to unread in the list', async () => {
  answer = (rpc) => {
    if (rpc === 'mailMessage') return message({ unread: true });
    if (rpc === 'mailFolder') return [{ ...header('m1'), unread: true }];
    throw new Error('refused');
  };
  await show('#/mail/inbox/m1');
  assert.match(root.textContent!, /Couldn't mark it read in Mail\./);
  assert.ok(root.querySelector('.subject.unread'));
});

test('F60: an attachment shows it is downloading, and why it failed', async () => {
  let refuse!: (e: Error) => void;
  answer = (rpc) => {
    if (rpc === 'mailMessage') return message({ attachments: [{ id: 'a1', name: 'notes.pdf', size: 2048 }] });
    if (rpc === 'mailAttachment') return new Promise((_, no) => (refuse = no));
    return worker()(rpc);
  };
  await show('#/mail/inbox/m1');
  await click('notes.pdf');
  assert.match(button('notes.pdf')!.textContent!, /Downloading…/);
  refuse(Object.assign(new Error('x'), { name: 'ParseError' }));
  await settle();
  assert.match(root.textContent!, /Couldn't download notes\.pdf\. An attached message opens only in Outlook on the web\./);
  assert.doesNotMatch(button('notes.pdf')!.textContent!, /Downloading/);
});

test('F60: Older messages failing shows why beside the button', async () => {
  const page = Array.from({ length: 30 }, (_, i) => header(`h${i}`));
  answer = (rpc, args) => {
    if (rpc === 'mailFolder' && args[1] === 0) return page;
    throw Object.assign(new Error('x'), { name: 'NetworkError' });
  };
  await show('#/mail/inbox');
  await click('Older messages');
  assert.match(root.textContent!, /Couldn't reach Mail/);
  assert.ok(button('Older messages'));
  assert.equal(root.querySelectorAll('.row').length, 30);
});

test('F60: Undo that fails says so', async () => {
  await show('#/mail/inbox/m1');
  answer = (rpc, args) => {
    if (rpc === 'mailMove') {
      if (args[1] === 'deleted') return 'new-id';
      throw new Error('refused');
    }
    return worker()(rpc);
  };
  await click('Delete');
  await click('Undo');
  assert.match(root.textContent!, /Couldn't move it back to Inbox\./);
});

// ---- List ----

test('F58: a slow answer for the folder left behind is ignored', async () => {
  const pending: Record<string, (v: MailHeader[]) => void> = {};
  answer = (rpc, args) => (rpc === 'mailFolder' ? new Promise((yes) => (pending[args[0] as string] = yes)) : null);
  await show('#/mail/inbox');
  hash = '#/mail/sent';
  fire('hashchange', { oldURL: 'ext://app#/mail/inbox', newURL: url() });
  await settle();
  pending.sent([header('from-sent')]);
  await settle();
  pending.inbox([header('from-inbox')]);
  await settle();
  assert.match(root.textContent!, /Subject from-sent/);
  assert.doesNotMatch(root.textContent!, /from-inbox/);
});

test('F58: a reload from an older screen loads the folder on show', async () => {
  await show('#/mail/inbox/m1');
  answer = (rpc) => (rpc === 'mailMove' ? 'new-id' : worker()(rpc));
  await click('Delete');
  hash = '#/mail/sent';
  fire('hashchange', { oldURL: 'ext://app#/mail/inbox', newURL: url() });
  await settle();
  asked.length = 0;
  await click('Undo');
  assert.deepEqual(sent('mailMove')[0].args, ['new-id', 'inbox']);
  assert.deepEqual(sent('mailFolder').at(-1)!.args, ['sent', 0]);
});

// ---- Search ----

test('F165: Enter searches this folder, and the empty answer says what and where', async () => {
  await show('#/mail/inbox');
  answer = (rpc) => (rpc === 'mailSearch' ? [] : worker()(rpc));
  typeIn('Search Inbox', 'lab report');
  await settle();
  press('Search Inbox', 'Enter');
  await settle();
  assert.deepEqual(sent('mailSearch')[0].args, ['inbox', 'lab report', 0]);
  assert.match(root.textContent!, /No mail matches "lab report" in Inbox\./);
});

test('F165: typing searches after a pause, once; a single letter waits for Enter', async () => {
  await show('#/mail/inbox');
  typeIn('Search Inbox', 'l');
  await settle(400);
  assert.equal(sent('mailSearch').length, 0);
  typeIn('Search Inbox', 'la');
  typeIn('Search Inbox', 'lab');
  await settle(400);
  assert.deepEqual(sent('mailSearch').map((a) => a.args[1]), ['lab']);
});

test('F165: Clear search goes back to the folder', async () => {
  await show('#/mail/inbox');
  typeIn('Search Inbox', 'lab');
  await settle();
  press('Search Inbox', 'Enter');
  await settle();
  asked.length = 0;
  await click('Clear search');
  assert.deepEqual(sent('mailFolder')[0].args, ['inbox', 0]);
  assert.equal(input('Search Inbox')!.value, '');
});

test('F165: moving to another folder leaves the search behind, with no search of the new folder', async () => {
  await show('#/mail/inbox');
  typeIn('Search Inbox', 'lab');
  await settle();
  press('Search Inbox', 'Enter');
  await settle();
  asked.length = 0;
  hash = '#/mail/sent';
  fire('hashchange', { oldURL: 'ext://app#/mail/inbox', newURL: url() });
  await settle();
  assert.equal(sent('mailSearch').length, 0);
  assert.deepEqual(sent('mailFolder')[0].args, ['sent', 0]);
  assert.equal(input('Search Sent')!.value, '');
});

test('F165: an older search answering late is ignored', async () => {
  const pending: Record<string, (v: MailHeader[]) => void> = {};
  await show('#/mail/inbox');
  answer = (rpc, args) => (rpc === 'mailSearch' ? new Promise((yes) => (pending[args[1] as string] = yes)) : null);
  typeIn('Search Inbox', 'one');
  await settle();
  press('Search Inbox', 'Enter');
  await settle();
  typeIn('Search Inbox', 'two');
  await settle();
  press('Search Inbox', 'Enter');
  await settle();
  pending.two([header('second')]);
  await settle();
  pending.one([header('first')]);
  await settle();
  assert.match(root.textContent!, /Subject second/);
  assert.doesNotMatch(root.textContent!, /Subject first/);
});

// ---- Composer ----

test('F51: a reply shows fixed lines, with nothing to edit and no Cc and Bcc', async () => {
  answer = worker(message({ cc: [{ name: 'Bob', address: 'bob@x.uz' }] }));
  await show('#/mail/inbox/m1');
  await click('Reply all');
  assert.equal(input('To'), null);
  assert.equal(input('Cc'), null);
  assert.equal(input('Subject'), null);
  assert.equal(button('Cc and Bcc'), null);
  const lines = [...root.querySelectorAll('.compose .line .fixed')].map((e) => e.textContent);
  assert.deepEqual(lines, ['Prof Example', 'Bob', 'RE: Lab 5']);
  typeIn('Message', 'Thanks');
  await settle();
  await click('Send');
  assert.deepEqual(JSON.parse(JSON.stringify(sent('mailSend')[0].args[0])), { kind: 'replyAll', ref: { id: 'm1', changeKey: 'ck1' }, body: 'Thanks' });
});

test('F52: opening another message with something written asks first', async () => {
  await show('#/mail/inbox');
  await click('New');
  typeIn('Message', 'Half a thought');
  await settle();
  await click('Subject m2');
  assert.match(root.querySelector('.dialog')!.textContent!, /Keep this as a draft\?/);
  assert.equal(hash, '#/mail/inbox');
  assert.ok(input('Message'));
});

test('F52: Discard lets it go and goes on', async () => {
  await show('#/mail/inbox');
  await click('New');
  typeIn('Message', 'Half a thought');
  await settle();
  await click('Subject m2');
  await inDialog('Discard');
  assert.equal(root.querySelector('.dialog'), null);
  assert.equal(input('Message'), null);
  assert.equal(hash, '#/mail/inbox/m2');
  assert.equal(sent('mailSaveDraft').length, 0);
});

test('F52: Save draft saves, then goes on; a failed save stays with the text', async () => {
  await show('#/mail/inbox');
  await click('New');
  typeIn('Message', 'Half a thought');
  await settle();
  await click('Subject m2');
  answer = (rpc) => {
    if (rpc === 'mailSaveDraft') throw new Error('refused');
    return worker()(rpc);
  };
  await inDialog('Save draft');
  assert.equal(hash, '#/mail/inbox');
  assert.match(root.textContent!, /Mail didn't save the draft\. Try again\./);
  assert.ok(input('Message'));

  answer = worker();
  await click('Subject m2');
  await inDialog('Save draft');
  assert.equal(hash, '#/mail/inbox/m2');
  assert.equal(input('Message'), null);
  assert.match(root.textContent!, /Saved to Drafts/);
});

test('F52: an untouched composer closes without asking', async () => {
  await show('#/mail/inbox');
  await click('New');
  await click('Subject m2');
  assert.equal(root.querySelector('.dialog'), null);
  assert.equal(input('Message'), null);
  assert.equal(hash, '#/mail/inbox/m2');
});

test('F52: New while writing a reply asks; New on a new message keeps it', async () => {
  await show('#/mail/inbox/m1');
  await click('Reply');
  typeIn('Message', 'Thanks');
  await settle();
  await click('New');
  assert.ok(root.querySelector('.dialog'));
  fire('keydown', { key: 'Escape' });
  await settle();
  assert.equal(root.querySelector('.dialog'), null);
  assert.equal(input('Message')!.value, 'Thanks');
  await click('Discard');
  await inDialog('Discard');

  await click('New');
  typeIn('Message', 'Kept');
  await settle();
  await click('New');
  assert.equal(root.querySelector('.dialog'), null);
  assert.equal(input('Message')!.value, 'Kept');
});

test('F52: leaving Mail is held back until answered, and within Mail is not', async () => {
  await show('#/mail/inbox');
  await click('New');
  typeIn('Message', 'Half a thought');
  await settle();

  (g.location as { hash: string }).hash = '#/mail/sent';
  await settle();
  assert.equal(root.querySelector('.dialog'), null);
  assert.equal(hash, '#/mail/sent');
  assert.ok(input('Message'));

  (g.location as { hash: string }).hash = '#/grades';
  await settle();
  assert.equal(hash, '#/mail/sent');
  assert.ok(root.querySelector('.dialog'));
  assert.equal(root.querySelector('#elsewhere'), null);

  await inDialog('Discard');
  assert.equal(hash, '#/grades');
  assert.ok(root.querySelector('#elsewhere'));
});

test('F52: closing the page warns only with something unsaved', async () => {
  const unload = () => {
    let warned = false;
    fire('beforeunload', { preventDefault: () => (warned = true) });
    return warned;
  };
  await show('#/mail/inbox');
  await click('New');
  assert.equal(unload(), false);
  typeIn('Message', 'x');
  await settle();
  assert.equal(unload(), true);
});

test('F52: while it is sending, nothing leaves it', async () => {
  await show('#/mail/inbox');
  await click('New');
  typeIn('To', 'a@b.uz');
  await settle();
  let finish!: () => void;
  answer = (rpc) => (rpc === 'mailSend' ? new Promise<void>((yes) => (finish = yes)) : worker()(rpc));
  await click('Send');
  assert.ok(button('Sending…'));
  await click('Subject m2');
  assert.equal(hash, '#/mail/inbox');
  assert.equal(root.querySelector('.dialog'), null);
  assert.match(root.textContent!, /Still sending this message\./);
  finish();
  await settle();
  assert.equal(input('Message'), null);
  assert.match(root.textContent!, /Sent/);
});

test('F52: a saved draft has Close, not Discard, and it asks to save changes', async () => {
  answer = worker(message({ isDraft: true, to: [{ name: '', address: 'a@b.uz' }] }));
  await show('#/mail/drafts/m1');
  await click('Edit draft');
  assert.equal(button('Discard'), null);
  await click('Close');
  assert.equal(input('Message'), null);
  await click('Edit draft');
  typeIn('Message', 'Changed');
  await settle();
  await click('Close');
  assert.match(root.querySelector('.dialog')!.textContent!, /Save your changes\?/);
});

test('F157 and F63: sending a draft untouched writes nothing and goes back to the folder', async () => {
  answer = worker(message({ isDraft: true, to: [{ name: '', address: 'a@b.uz' }] }));
  await show('#/mail/drafts/m1');
  await click('Edit draft');
  asked.length = 0;
  await click('Send');
  assert.deepEqual(JSON.parse(JSON.stringify(sent('mailSend')[0].args[0])), { kind: 'draft', ref: { id: 'm1', changeKey: 'ck1' } });
  assert.equal(hash, '#/mail/drafts');
  assert.equal(sent('mailMessage').length, 0);
  assert.ok(sent('mailFolder').length > 0);
  assert.match(root.textContent!, /Sent/);
  assert.doesNotMatch(root.textContent!, /Couldn't/);
});

test('saving a draft keeps it open in the folder', async () => {
  answer = worker(message({ isDraft: true, to: [{ name: '', address: 'a@b.uz' }] }));
  await show('#/mail/drafts/m1');
  await click('Edit draft');
  await click('Save draft');
  assert.equal(hash, '#/mail/drafts/m1');
  assert.ok(button('Edit draft'));
});

test('sending checks every recipient line', async () => {
  await show('#/mail/inbox');
  await click('New');
  await click('Send');
  assert.match(root.textContent!, /Add someone to send it to\./);
  typeIn('To', 'nobody');
  await settle();
  await click('Send');
  assert.match(root.textContent!, /"nobody" is not an email address\./);
  assert.equal(sent('mailSend').length, 0);
});

// ---- Suggestions ----

test('F74: suggestions close on leaving the line, and a late answer does not reopen them', async () => {
  await show('#/mail/inbox');
  await click('New');
  const to = input('To')!;
  to.dispatchEvent(new window.Event('focus'));
  answer = (rpc) => (rpc === 'mailLookup' ? [{ name: 'Sarah Example', address: 's@x.uz' }] : worker()(rpc));
  typeIn('To', 'sar');
  await settle(300);
  assert.ok(root.querySelector('.suggest'));
  to.dispatchEvent(new window.Event('blur'));
  await settle();
  assert.equal(root.querySelector('.suggest'), null);

  let reply!: (v: unknown) => void;
  answer = (rpc) => (rpc === 'mailLookup' ? new Promise((yes) => (reply = yes)) : worker()(rpc));
  to.dispatchEvent(new window.Event('focus'));
  typeIn('To', 'sara');
  await settle(300);
  to.dispatchEvent(new window.Event('blur'));
  reply([{ name: 'Sarah Example', address: 's@x.uz' }]);
  await settle();
  assert.equal(root.querySelector('.suggest'), null);
});

test('F74: an answer to what is no longer typed is ignored', async () => {
  await show('#/mail/inbox');
  await click('New');
  const to = input('To')!;
  to.dispatchEvent(new window.Event('focus'));
  const replies: Record<string, (v: unknown) => void> = {};
  answer = (rpc, args) => (rpc === 'mailLookup' ? new Promise((yes) => (replies[args[0] as string] = yes)) : worker()(rpc));
  typeIn('To', 'sar');
  await settle(300);
  typeIn('To', 'a@b.uz, ');
  await settle(300);
  replies.sar([{ name: 'Sarah Example', address: 's@x.uz' }]);
  await settle();
  assert.equal(root.querySelector('.suggest'), null);
});

// ---- Files ----

function pick(files: unknown[]) {
  const el = input('Attach file')!;
  Object.defineProperty(el, 'files', { value: files, configurable: true });
  el.dispatchEvent(new window.Event('change'));
}

test('F166: picked files show as rows, can be removed, and go out as base64', async () => {
  await show('#/mail/inbox');
  await click('New');
  typeIn('To', 'a@b.uz');
  await settle();
  pick([new File(['hello'], 'a.txt', { type: 'text/plain' }), new File(['xy'], 'b.bin')]);
  await settle();
  const rows = [...root.querySelectorAll('.compose .file')].map((r) => r.textContent);
  assert.deepEqual(rows, ['a.txt5 B', 'b.bin2 B']);
  await click('Remove b.bin');
  assert.equal(root.querySelectorAll('.compose .file').length, 1);
  await click('Send');
  const m = sent('mailSend')[0].args[0] as { attachments: unknown };
  assert.deepEqual(m.attachments, [{ name: 'a.txt', contentType: 'text/plain', base64: 'aGVsbG8=' }]);
});

test('F166: a message with only a file is unsaved work', async () => {
  await show('#/mail/inbox');
  await click('New');
  pick([new File(['hello'], 'a.txt')]);
  await settle();
  await click('Subject m2');
  assert.ok(root.querySelector('.dialog'));
});

test('F166: a file over the limit is refused before any upload', async () => {
  await show('#/mail/inbox');
  await click('New');
  pick([{ name: 'huge.zip', size: maxAttachmentBytes + 1, lastModified: 1 }]);
  await settle();
  assert.equal(root.querySelectorAll('.compose .file').length, 0);
  assert.match(root.textContent!, /huge\.zip is too big to add\. A message can carry 25 MB of new files\./);
});

test('F166: files already on a draft are listed and stay, new ones join them', async () => {
  answer = worker(message({ isDraft: true, to: [{ name: '', address: 'a@b.uz' }], attachments: [{ id: 'a1', name: 'old.pdf', size: 1024 }] }));
  await show('#/mail/drafts/m1');
  await click('Edit draft');
  assert.match(root.querySelector('.compose .file')!.textContent!, /old\.pdf1 KB · On the draft/);
  assert.equal(root.querySelector('[aria-label="Remove old.pdf"]'), null);
  pick([new File(['hello'], 'new.txt')]);
  await settle();
  asked.length = 0;
  await click('Send');
  const m = sent('mailSend')[0].args[0] as { attachments: { name: string; contentType: string }[]; body?: string };
  assert.deepEqual(m.attachments.map((a) => a.name), ['new.txt']);
  assert.equal(m.attachments[0].contentType, 'application/octet-stream');
  assert.equal(m.body, undefined);
});

test('F166: a failed send with files keeps the composer and refreshes Drafts', async () => {
  await show('#/mail/drafts');
  await click('New');
  typeIn('To', 'a@b.uz');
  await settle();
  pick([new File(['hello'], 'a.txt')]);
  await settle();
  asked.length = 0;
  answer = (rpc) => {
    if (rpc === 'mailSend') throw new Error('refused');
    return worker()(rpc);
  };
  await click('Send');
  assert.match(root.textContent!, /Mail didn't send it\. Try again\. A copy may be in Drafts\./);
  assert.ok(input('Message'));
  assert.deepEqual(sent('mailFolder')[0].args, ['drafts', 0]);
});
