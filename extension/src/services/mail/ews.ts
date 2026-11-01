// University mail over Exchange Web Services with Basic auth over HTTPS
// (docs/ENDPOINTS.md, Mail). A port of lib/services/mail/ews_client.dart.
//
// It runs in the extension's service worker, whose host permission for
// mail.inha.uz lets it POST there without CORS. The saved login is read for
// every call. The password and the Authorization header never go into an
// error: SOAP errors become ParseError/EwsError carrying only Exchange's
// ResponseCode, and network errors are http.ts's NetworkError, which names
// only the host.

import type { CredentialSource } from '../../core/credentials.ts';
import { LoginRequired, NetworkError, ParseError } from '../../core/errors.ts';
import { request, type HttpResponse } from '../../core/http.ts';
import type { MailAddress, MailFolder, MailFolderCount, MailHeader, MailMessage, OutgoingMail } from '../../core/models.ts';
import {
  EwsError,
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

  private savedUser: string | null = null; // the saved username `login` was worked out for
  private login: string | null = null; // the form of it the server accepted, so later calls try only that
  private preview = true; // false once the server turned down item:Preview

  constructor(creds: CredentialSource, http: typeof request = request, endpoint = defaultEndpoint) {
    this.creds = creds;
    this.http = http;
    this.endpoint = endpoint;
  }

  /** One page of folder f, newest first. Throws LoginRequired on 401. */
  async folder(f: MailFolder, limit = 30, offset = 0): Promise<MailHeader[]> {
    if (this.preview) {
      try {
        return parseFindItem(await this.call(findItemsEnvelope({ folder: f, limit, offset })));
      } catch (e) {
        // Exchange before 2013 turns item:Preview down, as a schema fault (HTTP 500) or a per-message error.
        const rejected =
          (e instanceof EwsError && previewRejectionCodes.has(e.code)) || (e instanceof NetworkError && e.status === 500);
        if (!rejected) throw e;
      }
    }
    const headers = parseFindItem(await this.call(findItemsEnvelope({ folder: f, limit, offset, withPreview: false })));
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

  /** Sends m; a copy goes to Sent. A saved draft is sent as it is, after writing what changed. */
  async send(m: OutgoingMail): Promise<void> {
    if (m.kind !== 'draft') {
      parseItemId(await this.call(createItemEnvelope(m, true)), 'CreateItem');
      return;
    }
    if (!m.ref) throw new Error('Sending a draft needs the saved draft');
    // Sending needs the draft's current change key, which an update moves on.
    let { id, changeKey } = m.ref;
    if (draftChanges(m)) {
      ({ id, changeKey } = parseItemId(await this.call(updateDraftEnvelope(m)), 'UpdateItem') ?? { id, changeKey });
    }
    parseSendItem(await this.call(sendItemEnvelope(id, changeKey)));
  }

  /** Saves m to Drafts, or writes the changes to a saved draft. */
  async saveDraft(m: OutgoingMail): Promise<void> {
    if (m.kind !== 'draft') {
      parseItemId(await this.call(createItemEnvelope(m, false)), 'CreateItem');
    } else if (draftChanges(m)) {
      parseItemId(await this.call(updateDraftEnvelope(m)), 'UpdateItem');
    }
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
    return parseAttachment(await this.call(getAttachmentEnvelope(id)));
  }

  /** POSTs envelope and returns the SOAP response text. */
  private async call(envelope: string): Promise<string> {
    const saved = await this.creds('mail');
    const user = saved?.username.trim() ?? '';
    if (!saved || user === '' || saved.password === '') throw new LoginRequired('mail', 'No mail login saved');
    if (user !== this.savedUser) {
      this.savedUser = user;
      this.login = null;
    }
    const known = this.login;
    for (const login of known != null ? [known] : loginCandidates(user)) {
      let res: HttpResponse;
      try {
        res = await this.post(envelope, login, saved.password);
      } catch (e) {
        if (e instanceof NetworkError && e.status === 500) this.login = login; // SOAP faults come after authentication
        throw e;
      }
      if (res.status === 401) continue;
      const text = res.text();
      if (res.status === 200) {
        this.login = login;
        return text;
      }
      if (res.status === 500) this.login = login;
      throw ewsFault(text) ?? new ParseError(`mail (HTTP ${res.status})`);
    }
    this.login = null;
    throw new LoginRequired('mail', 'Wrong username or password');
  }

  private post(envelope: string, login: string, password: string): Promise<HttpResponse> {
    return this.http(this.endpoint, {
      method: 'POST',
      headers: {
        Accept: 'text/xml',
        'Content-Type': 'text/xml; charset=utf-8',
        Authorization: basicAuth(login, password),
      },
      body: envelope,
      credentials: 'omit',
    });
  }
}
