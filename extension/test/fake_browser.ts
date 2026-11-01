// A stand-in for what the worker uses of the browser: chrome.storage,
// notifications, tabs, windows and alarms, the IndexedDB the vault keeps its key
// in, and fetch, routed to whatever a test answers with.

export interface FakeTab {
  id: number;
  url: string;
  windowId: number;
}

export interface Answer {
  status?: number;
  body?: string;
}

type Listener = (...args: never[]) => unknown;

function fakeStorage() {
  let data: Record<string, unknown> = {};
  return {
    get data() {
      return data;
    },
    reset() {
      data = {};
    },
    async get(k: string | string[] | null) {
      const copy = JSON.parse(JSON.stringify(data)) as Record<string, unknown>;
      if (k == null) return copy;
      return Object.fromEntries([k].flat().filter((x) => x in copy).map((x) => [x, copy[x]]));
    },
    async set(o: Record<string, unknown>) {
      Object.assign(data, JSON.parse(JSON.stringify(o)));
    },
    async remove(k: string | string[]) {
      for (const x of [k].flat()) delete data[x];
    },
  };
}

/** A request the fake fetch saw. */
export interface Seen {
  url: string;
  method: string;
  body: string;
  redirect: string;
}

export const browser = {
  local: fakeStorage(),
  session: fakeStorage(),
  shown: [] as { id: string; title: string; message: string }[],
  cleared: [] as string[],
  tabs: [] as FakeTab[],
  closedTabs: [] as number[],
  focused: [] as number[],
  newWindows: [] as string[],
  alarms: new Map<string, unknown>(),
  noWindow: false,
  notificationsFail: false,
  listeners: new Map<string, Listener[]>(),
  requests: [] as Seen[],
  /** Answers each fetch. Throw for a network failure. */
  route: (async () => ({ status: 404, body: '' })) as (r: Seen) => Promise<Answer>,

  reset() {
    this.local.reset();
    this.session.reset();
    this.shown.length = 0;
    this.cleared.length = 0;
    this.tabs.length = 0;
    this.closedTabs.length = 0;
    this.focused.length = 0;
    this.newWindows.length = 0;
    this.alarms.clear();
    this.noWindow = false;
    this.notificationsFail = false;
    this.requests.length = 0;
  },
};

const event = (name: string) => ({
  addListener: (l: Listener) => void browser.listeners.set(name, [...(browser.listeners.get(name) ?? []), l]),
  removeListener: () => {},
});

/** Calls an RPC the way a page does, through the worker's message listener. `sender` stands for where it came from. */
export function rpc<T = unknown>(method: string, args: unknown[] = [], sender: Partial<chrome.runtime.MessageSender> = {}): Promise<T> {
  return new Promise((resolve, reject) => {
    const listener = browser.listeners.get('runtime.onMessage')![0] as unknown as (m: unknown, s: unknown, r: (x: unknown) => void) => boolean;
    listener({ rpc: method, args }, sender, (reply) => {
      const r = reply as { ok: boolean; value?: T; error?: { name: string; message: string } };
      if (r.ok) resolve(r.value as T);
      else reject(Object.assign(new Error(r.error!.message), { name: r.error!.name, info: r.error }));
    });
  });
}

/** Lets anything left running after a test settle. */
export const settle = () => new Promise((resolve) => setTimeout(resolve, 5));

let nextTab = 1;

export function installFakeBrowser(): void {
  const g = globalThis as Record<string, unknown>;
  g.__DEV__ = false;
  g.chrome = {
    runtime: {
      getURL: (p: string) => `ext://${p}`,
      getPlatformInfo: async () => ({}),
      reload: () => {},
      onInstalled: event('runtime.onInstalled'),
      onStartup: event('runtime.onStartup'),
      onMessage: event('runtime.onMessage'),
    },
    storage: { local: browser.local, session: browser.session, onChanged: event('storage.onChanged') },
    notifications: {
      create: async (id: string, o: { title: string; message: string }) => {
        if (browser.notificationsFail) throw new Error('blocked');
        browser.shown.push({ id, title: o.title, message: o.message });
      },
      clear: (id: string) => void browser.cleared.push(id),
      getPermissionLevel: (cb: (l: string) => void) => cb('granted'),
      onClicked: event('notifications.onClicked'),
    },
    alarms: {
      create: async (name: string, o: unknown) => void browser.alarms.set(name, o),
      clear: async (name: string) => browser.alarms.delete(name),
      onAlarm: event('alarms.onAlarm'),
    },
    tabs: {
      create: async ({ url }: { url: string }) => {
        const tab = { id: nextTab++, url, windowId: 1 };
        browser.tabs.push(tab);
        return tab;
      },
      remove: async (id: number) => void browser.closedTabs.push(id),
    },
    windows: {
      getLastFocused: async () => {
        if (browser.noWindow) throw new Error('No last-focused window');
        return { id: 1 };
      },
      update: async (id: number) => void browser.focused.push(id),
      create: async ({ url }: { url: string }) => void browser.newWindows.push(url),
    },
  };

  // Just enough IndexedDB for the vault: one store, values kept as they are.
  const stored = new Map<string, unknown>();
  const done = <T>(run: () => T) => {
    const req: { result?: T; onsuccess?: () => void; onerror?: () => void; onupgradeneeded?: () => void } = {};
    queueMicrotask(() => {
      req.result = run();
      req.onsuccess?.();
    });
    return req;
  };
  const store = { get: (k: string) => done(() => stored.get(k)), put: (v: unknown, k: string) => done(() => void stored.set(k, v)) };
  g.indexedDB = { open: () => done(() => ({ transaction: () => ({ objectStore: () => store }) })) };

  g.fetch = async (input: string, init: RequestInit = {}) => {
    const seen: Seen = { url: String(input), method: init.method ?? 'GET', body: typeof init.body === 'string' ? init.body : '', redirect: init.redirect ?? 'follow' };
    browser.requests.push(seen);
    const a = await browser.route(seen);
    return new Response(a.body ?? '', { status: a.status ?? 200 });
  };
}
