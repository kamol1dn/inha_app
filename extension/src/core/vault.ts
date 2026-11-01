// Saved logins. The username is kept as it is (Settings shows it); the
// password is encrypted with AES-GCM under a key that is generated once in
// this browser profile, marked non-extractable, and kept in the extension's
// own IndexedDB. So:
//
// - the stored blob is useless anywhere else: another profile, another
//   computer, a copied storage folder, or Chrome sync (logins are never synced);
// - content scripts and web pages can't decrypt it: they don't share the
//   extension origin's IndexedDB, and the key can't be exported even here;
// - only the service worker and the extension's own pages read passwords,
//   and each one is sent only to the service it belongs to.
//
// What it does not protect against is malware running as the student on the
// same computer, which could drive the browser itself. Android's Keystore has
// the same limit; there is no OS keychain API for extensions.

import type { Credentials } from './credentials.ts';
import type { Service } from './models.ts';

const DB = 'iut-vault';
const STORE = 'keys';
const KEY_ID = 'logins-v1';
const STORAGE_KEY = 'vault.v1';

interface Sealed {
  username: string;
  iv: string; // base64
  data: string; // base64 AES-GCM ciphertext of the password
}

type Vault = Partial<Record<Service, Sealed>>;

function openDb(): Promise<IDBDatabase> {
  return new Promise((resolve, reject) => {
    const req = indexedDB.open(DB, 1);
    req.onupgradeneeded = () => req.result.createObjectStore(STORE);
    req.onsuccess = () => resolve(req.result);
    req.onerror = () => reject(req.error);
  });
}

function idb<T>(db: IDBDatabase, mode: IDBTransactionMode, run: (s: IDBObjectStore) => IDBRequest): Promise<T> {
  return new Promise((resolve, reject) => {
    const req = run(db.transaction(STORE, mode).objectStore(STORE));
    req.onsuccess = () => resolve(req.result as T);
    req.onerror = () => reject(req.error);
  });
}

let keyPromise: Promise<CryptoKey> | null = null;

/** The profile's key, made on first use. */
function key(): Promise<CryptoKey> {
  keyPromise ??= (async () => {
    const db = await openDb();
    const existing = await idb<CryptoKey | undefined>(db, 'readonly', (s) => s.get(KEY_ID));
    if (existing) return existing;
    const made = await crypto.subtle.generateKey({ name: 'AES-GCM', length: 256 }, false, ['encrypt', 'decrypt']);
    await idb(db, 'readwrite', (s) => s.put(made, KEY_ID));
    return made;
  })();
  keyPromise.catch(() => (keyPromise = null));
  return keyPromise;
}

const b64 = (bytes: Uint8Array) => btoa(String.fromCharCode(...bytes));
const unb64 = (s: string) => Uint8Array.from(atob(s), (c) => c.charCodeAt(0));

async function readVault(): Promise<Vault> {
  return ((await chrome.storage.local.get(STORAGE_KEY))[STORAGE_KEY] as Vault | undefined) ?? {};
}

export async function saveLogin(service: Service, login: Credentials): Promise<void> {
  const iv = crypto.getRandomValues(new Uint8Array(12));
  const data = new Uint8Array(
    await crypto.subtle.encrypt({ name: 'AES-GCM', iv }, await key(), new TextEncoder().encode(login.password)),
  );
  const vault = await readVault();
  vault[service] = { username: login.username.trim(), iv: b64(iv), data: b64(data) };
  await chrome.storage.local.set({ [STORAGE_KEY]: vault });
}

/** The saved login, or null. A blob the key can't open (the key was lost) counts as none. */
export async function readLogin(service: Service): Promise<Credentials | null> {
  const sealed = (await readVault())[service];
  if (!sealed) return null;
  try {
    const plain = await crypto.subtle.decrypt({ name: 'AES-GCM', iv: unb64(sealed.iv) }, await key(), unb64(sealed.data));
    return { username: sealed.username, password: new TextDecoder().decode(plain) };
  } catch {
    return null;
  }
}

export async function clearLogin(service: Service): Promise<void> {
  const vault = await readVault();
  delete vault[service];
  await chrome.storage.local.set({ [STORAGE_KEY]: vault });
}

/** The saved usernames, for Settings. Never the passwords. */
export async function savedUsernames(): Promise<Partial<Record<Service, string>>> {
  const vault = await readVault();
  return Object.fromEntries(Object.entries(vault).map(([s, v]) => [s, v!.username]));
}
