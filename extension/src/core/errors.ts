import { serviceLabel, type Service } from './models.ts';

/** A service rejected the saved login, or none is saved. */
export class LoginRequired extends Error {
  readonly service: Service;
  constructor(service: Service, message = 'Login needed') {
    super(`${serviceLabel[service]}: ${message}`);
    this.name = 'LoginRequired';
    this.service = service;
  }
}

/** A page loaded but did not look as expected, which usually means the site changed. Never carries page content. */
export class ParseError extends Error {
  readonly what: string;
  constructor(what: string) {
    super(`Could not read ${what}`);
    this.name = 'ParseError';
    this.what = what;
  }
}

/** The request never got a usable answer: offline, timed out, a 5xx, or a certificate the browser refuses. */
export class NetworkError extends Error {
  readonly status: number; // 0 when there was no response
  readonly certificate: boolean; // the browser refused the TLS certificate (INS)
  constructor(message: string, status = 0, certificate = false) {
    super(message);
    this.name = 'NetworkError';
    this.status = status;
    this.certificate = certificate;
  }
}

/** One plain sentence naming the service and what happened (DESIGN.md 10). Raw exception text never reaches the screen. */
export function describeError(e: unknown, service: Service): string {
  const name = serviceLabel[service];
  const kind = (e as { name?: string } | null)?.name;
  if (kind === 'LoginRequired') return `${name} sign-in needed.`;
  if (kind === 'ParseError') return `Couldn't read the ${name} page; it may have changed.`;
  if (kind === 'NetworkError') {
    if ((e as NetworkError).certificate) return `${name}'s certificate has expired, so the browser refuses it. Open ${name} once and choose Proceed.`;
    return `Couldn't reach ${name}. Check the connection.`;
  }
  return `Couldn't load from ${name}.`;
}

/** Errors cross the worker/page boundary as plain objects; this keeps the parts describeError reads. */
export interface ErrorInfo {
  name: string;
  message: string;
  certificate?: boolean;
}

export const errorInfo = (e: unknown): ErrorInfo => ({
  name: (e as Error)?.name ?? 'Error',
  message: (e as Error)?.message ?? String(e),
  certificate: (e as NetworkError)?.certificate || undefined,
});
