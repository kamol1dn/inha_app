// What the mail composer works out, apart from drawing it: what a message starts
// as, what the student changed, whether it can go, and the files on it. A port
// of the logic in lib/features/compose_screen.dart.

import { addressLabel, type ComposeKind, type MailAddress, type MailFolder, type MailMessage, type OutgoingAttachment, type OutgoingMail, outgoingFolder } from '../../core/models.ts';
import { composeError, fileSize, isEmailAddress, maxAttachmentBytes, parseRecipients, replyAllRecipients } from '../../services/mail/soap.ts';

export interface Draft {
  kind: ComposeKind;
  ref?: MailMessage;
  to: string;
  cc: string;
  bcc: string;
  subject: string;
  body: string;
}

const isReply = (kind: ComposeKind) => kind === 'reply' || kind === 'replyAll';

export function draftFor(kind: ComposeKind, m?: MailMessage): Draft {
  const join = (l: MailAddress[]) => l.map((a) => a.address).filter(Boolean).join(', ');
  if (!m) return { kind, to: '', cc: '', bcc: '', subject: '', body: '' };
  if (kind === 'draft') return { kind, ref: m, to: join(m.to), cc: join(m.cc), bcc: join(m.bcc), subject: m.subject, body: m.body };
  return { kind, ref: m, to: '', cc: '', bcc: '', subject: `${isReply(kind) ? 'RE' : 'FW'}: ${m.subject}`, body: '' };
}

/** Who a reply goes to, as fixed lines: Exchange sets them, so they can't be edited. Null for anything but a reply. */
export function replyLines(d: Draft): { to: string; cc: string } | null {
  if (!d.ref || !isReply(d.kind)) return null;
  const line = (l: MailAddress[]) => l.map(addressLabel).join(', ');
  if (d.kind === 'reply') return { to: addressLabel({ name: d.ref.from, address: d.ref.fromAddress }), cc: '' };
  const r = replyAllRecipients(d.ref);
  return { to: line(r.to), cc: line(r.cc) };
}

/** Which of Reply and Reply all an opened message offers: neither on mail the student sent, and Reply all only when someone besides the sender got it. */
export function replyChoices(m: MailMessage, folder: MailFolder): { reply: boolean; replyAll: boolean } {
  if (outgoingFolder(folder)) return { reply: false, replyAll: false };
  const r = replyAllRecipients(m);
  return { reply: true, replyAll: r.to.length + r.cc.length > 1 };
}

export const textChanged = (d: Draft, start: Draft): boolean =>
  d.to !== start.to || d.cc !== start.cc || d.bcc !== start.bcc || d.subject !== start.subject || d.body !== start.body;

/** The message as it stands. A saved draft carries only what changed, so sending one as it was leaves its quoted original alone. */
export function outgoing(d: Draft, start: Draft): OutgoingMail {
  const ref = d.ref ? { id: d.ref.id, changeKey: d.ref.changeKey } : undefined;
  const line = (k: 'to' | 'cc' | 'bcc') => (d.kind === 'draft' && d[k] === start[k] ? undefined : parseRecipients(d[k]));
  const text = (k: 'subject' | 'body') => (d.kind === 'draft' && d[k] === start[k] ? undefined : d[k]);
  if (isReply(d.kind)) return { kind: d.kind, ref, body: d.body };
  return { kind: d.kind, ref, to: line('to'), cc: line('cc'), bcc: line('bcc'), subject: d.kind === 'forward' ? undefined : text('subject'), body: text('body') };
}

/** The first problem with the recipients, or null when it can go. A reply's are Exchange's. */
export function recipientProblem(d: Draft): string | null {
  if (isReply(d.kind)) return null;
  const all = [d.to, d.cc, d.bcc].flatMap(parseRecipients);
  if (!all.length) return 'Add someone to send it to.';
  const bad = all.find((a) => !isEmailAddress(a));
  return bad ? `"${bad}" is not an email address.` : null;
}

/** What is enough of a file to add it: a File is one of these. */
export interface PickedFile {
  name: string;
  size: number;
  lastModified: number;
}

/**
 * The files on the message after picking more: picked again is ignored, and an
 * empty file or one that goes over the limit is left out, with why.
 */
export function addFiles<F extends PickedFile>(have: F[], picked: F[]): { files: F[]; problem: string | null } {
  const files = [...have];
  let problem: string | null = null;
  let total = have.reduce((n, f) => n + f.size, 0);
  for (const f of picked) {
    if (files.some((o) => o.name === f.name && o.size === f.size && o.lastModified === f.lastModified)) continue;
    if (f.size === 0) {
      problem ??= `${f.name} is empty, so it was not added.`;
    } else if (total + f.size > maxAttachmentBytes) {
      problem ??= `${f.name} is too big to add. A message can carry ${fileSize(maxAttachmentBytes)} of new files.`;
    } else {
      files.push(f);
      total += f.size;
    }
  }
  return { files, problem };
}

/** Bytes to base64, in pieces of a multiple of 3 so they join up, and so a big file doesn't overflow the call stack. */
export function base64Of(bytes: Uint8Array): string {
  const piece = 3 * 0x2000;
  let out = '';
  for (let i = 0; i < bytes.length; i += piece) out += btoa(String.fromCharCode(...bytes.subarray(i, i + piece)));
  return out;
}

/** A picked file as the worker takes it. */
export const toAttachment = async (f: File): Promise<OutgoingAttachment> => ({
  name: f.name,
  contentType: f.type || 'application/octet-stream',
  base64: base64Of(new Uint8Array(await f.arrayBuffer())),
});

/**
 * What went wrong sending or saving. A message with files is saved first, so a
 * failure partway leaves something behind, and trying again adds to it.
 */
export function composeFailure(e: unknown, sending: boolean, kind: ComposeKind, withFiles: boolean): string {
  const said = composeError(e, sending);
  if (!withFiles) return said;
  return `${said} ${kind === 'draft' ? 'Some of the files may already be on the draft.' : 'A copy may be in Drafts.'}`;
}
