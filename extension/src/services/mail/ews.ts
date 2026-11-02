// University mail over Exchange Web Services with Basic auth over HTTPS
// (docs/ENDPOINTS.md, Mail). A port of lib/services/mail/ews_client.dart.
//
// It runs in the extension's service worker, whose host permission for
// mail.inha.uz lets it POST there without CORS. The saved login is read for
// every call. The password and the Authorization header never go into an
// error: SOAP errors become ParseError/EwsError carrying only Exchange's
// ResponseCode, and network errors are http.ts's NetworkError, which names
// only the host.
//
// A rejected password counts toward the domain's lockout, and a locked account
// blocks OWA too. So a login is tried by one call at a time until the server
// has answered it once, and a login it refused is never posted again.

import { loginMark, type CredentialSource, type Credentials, type RejectionSink } from '../../core/credentials.ts';
import { LoginRequired, NetworkError, ParseError } from '../../core/errors.ts';
import { request, type HttpResponse } from '../../core/http.ts';
import type { MailAddress, MailFolder, MailFolderCount, MailHeader, MailMessage, OutgoingAttachment, OutgoingMail } from '../../core/models.ts';
import {
  EwsError,
  createAttachmentEnvelope,
  createItemEnvelope,
  draftChanges,
  ewsFault,
  findItemsEnvelope,
  getAttachmentEnvelope,
  getFolderCountsEnvelope,
  getInboxFolderEnvelope,
  getItemEnvelope,
  moveItemEnvelope,
  parseAttachment,
  parseCreateAttachment,
  parseFindItem,
  parseFolderCounts,
  parseGetFolder,
  parseItemId,
  parseMessage,
  parseResolveNames,
  parseSendItem,
  parseUpdateItem,
  previewRejectionCodes,
  resolveNamesEnvelope,
  sendItemEnvelope,
  setReadEnvelope,
  updateDraftEnvelope,
} from './soap.ts';

export const defaultEndpoint = 'https://mail.inha.uz/EWS/Exchange.asmx';

/** An attachment can take a while to travel on a slow link, in either direction. */
const transferTimeoutMs = 3 * 60_000;

/** NetBIOS domain of the IUT mail server, from its NTLM challenge (INHA / INHA.local). OWA's form login adds it for you; EWS Basic auth does not. */
export const windowsDomain = 'INHA';

/**
 * The username to send. Students save their bare ID, which becomes INHA\<id>;
 * anything already qualified (DOMAIN\user, user@domain) is sent as is. Only
 * one form is ever tried, so a wrong password costs one failed logon against
 * the domain's lockout counter, not several.
 */
export function loginCandidates(saved: string): string[] {
  const user = saved.trim();
  if (user === '') return [];
  if (user.includes('\\') || user.includes('@')) return [user];
  return [`${windowsDomain}\\${user}`];
}

/** Basic auth value for login:password, UTF-8 encoded as Exchange expects. */
export function basicAuth(login: string, password: string): string {
  const bytes = new TextEncoder().encode(`${login}:${password}`);
  let binary = '';
  for (const b of bytes) binary += String.fromCharCode(b);
  return `Basic ${btoa(binary)}`;
}

export class EwsClient {
  private readonly creds: CredentialSource;
  private readonly http: typeof request;
  private readonly endpoint: string;

  private readonly onRejected: RejectionSink;

  private accepted: string | null = null; // the mark of the login the server last took
  private rejected: string | null = null; // the mark of the login it last refused
  private trying: Promise<unknown> | null = null; // the one call trying a login not yet answered
  private preview = true; // false once the server turned down item:Preview

  constructor(creds: CredentialSource, http: typeof request = request, endpoint = defaultEndpoint, onRejected: RejectionSink = () => {}) {
    this.creds = creds;
    this.http = http;
    this.endpoint = endpoint;
    this.onRejected = onRejected;
  }

  /** The student asked to try the saved login again. */
  forgetRejected(): void {
    this.rejected = null;
  }

  /** One page of folder f, newest first. Throws LoginRequired on 401. */
  folder(f: MailFolder, limit = 30, offset = 0): Promise<MailHeader[]> {
    return this.findItems({ folder: f, limit, offset });
  }

  /** One page of what Exchange's search finds for query in folder f, newest first. */
  search(f: MailFolder, query: string, limit = 30, offset = 0): Promise<MailHeader[]> {
    return this.findItems({ folder: f, limit, offset, queryString: query.trim() });
  }

  private async findItems(page: { folder: MailFolder; limit: number; offset: number; queryString?: string }): Promise<MailHeader[]> {
    if (this.preview) {
      try {
        return parseFindItem(await this.call(findItemsEnvelope(page)));
      } catch (e) {
        // Exchange before 2013 turns item:Preview down, as a schema fault (HTTP 500) or a per-message error.
        if (!(e instanceof EwsError && previewRejectionCodes.has(e.code))) throw e;
      }
    }
    const headers = parseFindItem(await this.call(findItemsEnvelope({ ...page, withPreview: false })));
    this.preview = false; // worked without item:Preview: stop asking for it
    return headers;
  }

  /** One message with its plain-text body, recipients and attachment list. Does not change its read state. */
  async message(id: string): Promise<MailMessage> {
    return parseMessage(await this.call(getItemEnvelope(id)));
  }

  /** Sets the message's read flag (no read receipt is sent). */
  async markRead(id: string, read = true): Promise<void> {
    parseUpdateItem(await this.call(setReadEnvelope(id, read)));
  }

  /** The inbox's unread count. */
  async unreadCount(): Promise<number> {
    return parseGetFolder(await this.call(getInboxFolderEnvelope()));
  }

  /** Unread and total counts of every mail folder the mailbox has. */
  async folderCounts(): Promise<Partial<Record<MailFolder, MailFolderCount>>> {
    return parseFolderCounts(await this.call(getFolderCountsEnvelope()));
  }

  /**
   * Sends m; a copy goes to Sent. A saved draft is sent as it is, after writing
   * what changed. With files, m is saved first and sent from Drafts, so if a step
   * fails what was written stays there.
   */
  async send(m: OutgoingMail): Promise<void> {
    const files = m.attachments ?? [];
    if (m.kind !== 'draft') {
      if (!files.length) {
        parseItemId(await this.call(createItemEnvelope(m, true)), 'CreateItem');
        return;
      }
      const saved = parseItemId(await this.call(createItemEnvelope(m, false)), 'CreateItem');
      if (!saved) throw new ParseError('mail (CreateItem)');
      const { id, changeKey } = await this.attach(saved, files);
      parseSendItem(await this.call(sendItemEnvelope(id, changeKey)));
      return;
    }
    if (!m.ref) throw new Error('Sending a draft needs the saved draft');
    // Sending needs the draft's current change key, which an update or an attachment moves on.
    let { id, changeKey } = m.ref;
    if (draftChanges(m)) {
      ({ id, changeKey } = parseItemId(await this.call(updateDraftEnvelope(m)), 'UpdateItem') ?? { id, changeKey });
    }
    ({ id, changeKey } = await this.attach({ id, changeKey }, files));
    parseSendItem(await this.call(sendItemEnvelope(id, changeKey)));
  }

  /** Saves m to Drafts, or writes the changes to a saved draft. */
  async saveDraft(m: OutgoingMail): Promise<void> {
    const files = m.attachments ?? [];
    if (m.kind !== 'draft') {
      const saved = parseItemId(await this.call(createItemEnvelope(m, false)), 'CreateItem');
      if (files.length) {
        if (!saved) throw new ParseError('mail (CreateItem)');
        await this.attach(saved, files);
      }
      return;
    }
    let ref = m.ref;
    if (draftChanges(m)) ref = parseItemId(await this.call(updateDraftEnvelope(m)), 'UpdateItem') ?? ref;
    if (files.length) {
      if (!ref) throw new Error('A draft update needs the saved draft');
      await this.attach(ref, files);
    }
  }

  /** Adds files to a saved message, one request each. Returns it at its newest change key. */
  private async attach(parent: { id: string; changeKey: string }, files: OutgoingAttachment[]): Promise<{ id: string; changeKey: string }> {
    let at = parent;
    for (const file of files) {
      at = parseCreateAttachment(await this.call(createAttachmentEnvelope(at, file), transferTimeoutMs)) ?? at;
    }
    return at;
  }

  /** Moves a message to `to`; deleting is a move to 'deleted'. Returns its id in the new folder, or null when Exchange didn't say. */
  async move(id: string, to: MailFolder): Promise<string | null> {
    return parseItemId(await this.call(moveItemEnvelope(id, to)), 'MoveItem')?.id ?? null;
  }

  /** People and lists whose name or address starts with query. */
  async lookup(query: string): Promise<MailAddress[]> {
    return parseResolveNames(await this.call(resolveNamesEnvelope(query)));
  }

  /** One attachment's file, base64 as Exchange sends it, for a download. */
  async attachment(id: string): Promise<{ name: string; contentType: string; base64: string }> {
    return parseAttachment(await this.call(getAttachmentEnvelope(id), transferTimeoutMs));
  }

  /** POSTs envelope and returns the SOAP response text. */
  private async call(envelope: string, timeoutMs?: number): Promise<string> {
    const saved = await this.creds('mail');
    const user = saved?.username.trim() ?? '';
    if (!saved || user === '' || saved.password === '') throw new LoginRequired('mail', 'No mail login saved');
    const login = loginCandidates(user)[0];
    const mark = await loginMark(saved);
    while (mark !== this.accepted) {
      if (mark === this.rejected) throw new LoginRequired('mail', 'Wrong username or password', true);
      if (!this.trying) {
        // Not answered yet: this call tries it, the others wait for the verdict.
        const attempt = this.exchange(envelope, login, saved, mark, timeoutMs).finally(() => {
          this.trying = null;
        });
        this.trying = attempt.catch(() => {});
        return attempt;
      }
      await this.trying;
    }
    return this.exchange(envelope, login, saved, mark, timeoutMs);
  }

  private async exchange(envelope: string, login: string, saved: Credentials, mark: string, timeoutMs?: number): Promise<string> {
    const res = await this.post(envelope, login, saved.password, timeoutMs);
    if (res.status === 401) {
      this.accepted = null;
      this.rejected = mark;
      await this.onRejected('mail', saved);
      throw new LoginRequired('mail', 'Wrong username or password', true);
    }
    const text = res.text();
    if (res.status === 200) {
      this.accepted = mark;
      return text;
    }
    if (res.status === 500) this.accepted = mark; // SOAP faults come after authentication
    const fault = ewsFault(text);
    if (fault) throw fault;
    if (res.status >= 500) throw new NetworkError(`mail.inha.uz answered ${res.status}`, res.status);
    throw new ParseError(`mail (HTTP ${res.status})`);
  }

  private post(envelope: string, login: string, password: string, timeoutMs?: number): Promise<HttpResponse> {
    return this.http(this.endpoint, {
      method: 'POST',
      headers: {
        Accept: 'text/xml',
        'Content-Type': 'text/xml; charset=utf-8',
        Authorization: basicAuth(login, password),
      },
      body: envelope,
      credentials: 'omit',
      allow5xx: true,
      timeoutMs,
    });
  }
}
