// Calls from pages and content scripts to the service worker, which is the
// only place that holds passwords and talks to the services.

import type { ErrorInfo } from './errors.ts';
import type {
  GradeReport,
  MailAddress,
  MailFolder,
  MailHeader,
  MailMessage,
  OutgoingMail,
  Service,
} from './models.ts';
import type { Credentials } from './credentials.ts';

export interface Api {
  /** Refreshes one source, or all of them; `force` ignores how fresh the cache is. */
  sync(source: Service | 'all', force?: boolean): void;
  /**
   * Saves a login and always tries it, even with a live browser session. Returns
   * why it isn't confirmed, or null. A refused login is not kept and the one
   * before it stays (name 'LoginRequired'); for an unreachable service
   * ('NetworkError') or one with no way to test it now ('LoginUntested') it is
   * saved, untested.
   */
  saveLogin(service: Service, username: string, password: string): ErrorInfo | null;
  clearLogin(service: Service): void;
  /** EduPage's class groups, for the picker. */
  classGroups(): string[];

  mailFolder(folder: MailFolder, offset: number): MailHeader[];
  /** One page of what Exchange finds for query in folder, newest first. Not cached. */
  mailSearch(folder: MailFolder, query: string, offset: number): MailHeader[];
  mailMessage(id: string): MailMessage;
  mailMarkRead(id: string, read: boolean): void;
  mailSend(m: OutgoingMail): void;
  mailSaveDraft(m: OutgoingMail): void;
  mailMove(id: string, to: MailFolder): string | null;
  mailLookup(query: string): MailAddress[];
  mailAttachment(id: string): { name: string; contentType: string; base64: string };

  /** From eClass's login page: signs the browser in with the saved login. False when none is saved. */
  eclassAutoLogin(): boolean;
  /** From an eClass page: the student clicked Log out, so nothing signs the browser back in until they sign in again. */
  eclassLoggedOut(): void;

  /** From the INS content script: whether this tab is one the extension opened or the student chose to read grades in. */
  insSyncAllowed(): boolean;
  /** From the INS content script, on the student's click: lets this tab read the grades. */
  insAdoptTab(): void;
  /** From the INS content script: the INS login, only ever answered to a tab allowed to read the grades. */
  insLogin(): Credentials | null;
  /** From the INS content script: grades it read through the open INS tab. Only from a tab allowed to read them. */
  insReport(report: GradeReport | null, error: ErrorInfo | null): void;
  /** Opens INS in a tab so its content script can read the grades past the expired certificate. */
  insOpenForSync(): void;
}

export type Method = keyof Api;

interface Request {
  rpc: Method;
  args: unknown[];
}

type Reply = { ok: true; value: unknown } | { ok: false; error: ErrorInfo };

/** Rebuilds the worker's error on this side, keeping the name describeError reads. */
export class RemoteError extends Error {
  readonly certificate?: boolean;
  readonly status?: number;
  constructor(info: ErrorInfo) {
    super(info.message);
    this.name = info.name;
    this.certificate = info.certificate;
    this.status = info.status;
  }
}

export async function call<M extends Method>(method: M, ...args: Parameters<Api[M]>): Promise<ReturnType<Api[M]>> {
  const reply = (await chrome.runtime.sendMessage({ rpc: method, args } satisfies Request)) as Reply | undefined;
  if (!reply) throw new RemoteError({ name: 'Error', message: 'The extension did not answer' });
  if (!reply.ok) throw new RemoteError(reply.error);
  return reply.value as ReturnType<Api[M]>;
}

export type Handlers = {
  [M in Method]: (sender: chrome.runtime.MessageSender, ...args: Parameters<Api[M]>) => Promise<ReturnType<Api[M]>> | ReturnType<Api[M]>;
};

/** In the worker: answers `call`s with `handlers`. */
export function serve(handlers: Handlers, toInfo: (e: unknown) => ErrorInfo): void {
  chrome.runtime.onMessage.addListener((msg: Request, sender, respond) => {
    if (!msg || typeof msg.rpc !== 'string' || !(msg.rpc in handlers)) return false;
    const handler = handlers[msg.rpc] as (s: chrome.runtime.MessageSender, ...a: unknown[]) => unknown;
    Promise.resolve()
      .then(() => handler(sender, ...msg.args))
      .then(
        (value) => respond({ ok: true, value: value ?? null } satisfies Reply),
        (e) => respond({ ok: false, error: toInfo(e) } satisfies Reply),
      );
    return true; // answering asynchronously
  });
}
