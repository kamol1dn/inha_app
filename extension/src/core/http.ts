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
  timeoutMs?: number;
}

/**
 * fetch with a timeout, and every failure without an answer as a NetworkError.
 * Redirects are followed by the browser, which also keeps the cookies they set,
 * so callers look at `url` to see where a request landed. A 5xx is an error;
 * 4xx answers come back for the caller to judge.
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
  } catch (e) {
    const host = safeHost(url);
    if (ctl.signal.aborted) throw new NetworkError(`${host} timed out`);
    // fetch says only "Failed to fetch". Online, for INS the cause is almost
    // always its expired certificate; offline it is just the connection.
    const online = typeof navigator === 'undefined' || navigator.onLine !== false;
    throw new NetworkError(`${host} unreachable: ${(e as Error).message}`, 0, online && host === 'ins.inha.uz');
  } finally {
    clearTimeout(timer);
  }

  const bytes = new Uint8Array(await res.arrayBuffer());
  if (res.status >= 500) throw new NetworkError(`${safeHost(url)} answered ${res.status}`, res.status);
  return {
    status: res.status,
    url: res.url || url,
    redirected: res.redirected,
    headers: res.headers,
    bytes,
    text: (encoding = 'utf-8') => new TextDecoder(encoding).decode(bytes),
  };
}

function safeHost(url: string): string {
  try {
    return new URL(url).host;
  } catch {
    return 'server';
  }
}
