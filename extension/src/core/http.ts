import { NetworkError } from './errors.ts';

export interface HttpResponse {
  status: number;
  url: string; // where it ended up, after redirects
  redirected: boolean;
  headers: Headers;
  bytes: Uint8Array;
  /** The body decoded as UTF-8 unless the caller asks for another encoding. */
  text(encoding?: string): string;
}

export interface HttpRequest {
  method?: 'GET' | 'POST';
  headers?: Record<string, string>;
  /** A string is sent as is; an object as application/x-www-form-urlencoded. */
  body?: string | Record<string, string>;
  /** 'include' sends and stores the browser's own cookies for that site (eClass, INS); mail uses 'omit'. */
  credentials?: RequestCredentials;
  /** Covers the whole exchange, body included. */
  timeoutMs?: number;
  /** Hand 5xx answers to the caller: Exchange sends its SOAP faults as HTTP 500. */
  allow5xx?: boolean;
}

/**
 * fetch with a timeout, and every failure without an answer as a NetworkError.
 * Redirects are followed by the browser, which also keeps the cookies they set,
 * so callers look at `url` to see where a request landed. A 5xx is an error
 * unless the caller allows it; 4xx answers come back for the caller to judge.
 */
export async function request(url: string, req: HttpRequest = {}): Promise<HttpResponse> {
  const headers: Record<string, string> = { ...req.headers };
  let body: string | undefined;
  if (typeof req.body === 'string') {
    body = req.body;
  } else if (req.body) {
    body = new URLSearchParams(req.body).toString();
    headers['Content-Type'] ??= 'application/x-www-form-urlencoded';
  }

  const ctl = new AbortController();
  const timer = setTimeout(() => ctl.abort(), req.timeoutMs ?? 30_000);
  let res: Response;
  let bytes: Uint8Array;
  try {
    res = await fetch(url, {
      method: req.method ?? (body == null ? 'GET' : 'POST'),
      headers,
      body,
      credentials: req.credentials ?? 'include',
      redirect: 'follow',
      cache: 'no-store',
      signal: ctl.signal,
    });
    // Still inside the timeout: a connection can stall or drop in mid-body too.
    bytes = new Uint8Array(await res.arrayBuffer());
  } catch (e) {
    const host = safeHost(url);
    if (ctl.signal.aborted) throw new NetworkError(`${host} timed out`);
    throw new NetworkError(`${host} unreachable: ${(e as Error).message}`, 0, await certificateRefused(url, host));
  } finally {
    clearTimeout(timer);
  }

  if (res.status >= 500 && !req.allow5xx) throw new NetworkError(`${safeHost(url)} answered ${res.status}`, res.status);
  return {
    status: res.status,
    url: res.url || url,
    redirected: res.redirected,
    headers: res.headers,
    bytes,
    text: (encoding = 'utf-8') => new TextDecoder(encoding).decode(bytes),
  };
}

/**
 * fetch says only "Failed to fetch". Online, from the worker, for INS the cause
 * is almost always its expired certificate, but the failure can also be a
 * redirect to its internal host (docs/ENDPOINTS.md), so a request that stops at
 * the first answer has to fail too. In an INS tab the certificate was already
 * accepted, so it is never the cause there.
 */
async function certificateRefused(url: string, host: string): Promise<boolean> {
  if (host !== 'ins.inha.uz') return false;
  if (typeof navigator !== 'undefined' && navigator.onLine === false) return false;
  if (typeof location !== 'undefined' && location.host === host) return false;
  try {
    await fetch(url, { redirect: 'manual', credentials: 'omit', cache: 'no-store', signal: AbortSignal.timeout(10_000) });
    return false;
  } catch {
    return true;
  }
}

function safeHost(url: string): string {
  try {
    return new URL(url).host;
  } catch {
    return 'server';
  }
}
