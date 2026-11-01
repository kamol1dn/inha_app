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
import { serial } from './serial.ts';

const DB = 'iut-vault';
const STORE = 'keys';
const KEY_ID = 'logins-v1';
const STORAGE_KEY = 'vault.v1';

interface Sealed {
  username: string;
  iv: string; // base64
  data: string; // base64 AES-GCM ciphertext of the password
  rejected?: number; // when the service refused this login: see refusalHolds
}

/**
 * How long a refused login stays unposted unless the student acts. A wrong
 * password counts toward the domain's lockout; a passing server fault taken for
 * a refusal mends itself at one failed logon a day.
 */
export const refusalHolds = 24 * 3600e3;

export const stillRefused = (rejected: number | undefined, now = Date.now()) => rejected != null && now - rejected < refusalHolds;

/** A saved login as it is stored, to put back if a new one turns out wrong. */
export type SealedLogin = Sealed;

type Vault = Partial<Record<Service, Sealed>>;

const writes = serial();

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

/** One read-modify-write of the vault, in turn with the others. `change` returns false to leave it as it was. */
function updateVault(change: (vault: Vault) => boolean | void | Promise<boolean | void>): Promise<void> {
  return writes(async () => {
    const vault = await readVault();
    if ((await change(vault)) !== false) await chrome.storage.local.set({ [STORAGE_KEY]: vault });
  });
}

/** Saves a login. A new one has not been refused by anyone, so that mark goes with the old one. */
export async function saveLogin(service: Service, login: Credentials): Promise<void> {
  const iv = crypto.getRandomValues(new Uint8Array(12));
  const data = new Uint8Array(
    await crypto.subtle.encrypt({ name: 'AES-GCM', iv }, await key(), new TextEncoder().encode(login.password)),
  );
  await updateVault((vault) => {
    vault[service] = { username: login.username.trim(), iv: b64(iv), data: b64(data) };
  });
}

async function unseal(sealed: Sealed): Promise<Credentials | null> {
  try {
    const plain = await crypto.subtle.decrypt({ name: 'AES-GCM', iv: unb64(sealed.iv) }, await key(), unb64(sealed.data));
    return { username: sealed.username, password: new TextDecoder().decode(plain) };
  } catch {
    return null;
  }
}

/** The saved login, or null. A blob the key can't open (the key was lost) counts as none. */
export async function readLogin(service: Service): Promise<Credentials | null> {
  const sealed = (await readVault())[service];
  return sealed ? unseal(sealed) : null;
}

/** The saved login as stored, for restoreLogin. */
export const readSealedLogin = async (service: Service): Promise<SealedLogin | undefined> => (await readVault())[service];

/** Puts back what readSealedLogin returned, which may be nothing. */
export function restoreLogin(service: Service, sealed: SealedLogin | undefined): Promise<void> {
  return updateVault((vault) => {
    if (sealed) vault[service] = sealed;
    else delete vault[service];
  });
}

/** Marks the saved login as refused, if it is still the one that was tried: a newer one hasn't been. */
export function markLoginRejected(service: Service, tried: Credentials): Promise<void> {
  return updateVault(async (vault) => {
    const sealed = vault[service];
    const current = sealed ? await unseal(sealed) : null;
    if (!sealed || current?.username !== tried.username.trim() || current.password !== tried.password) return false;
    sealed.rejected = Date.now();
  });
}

/** Allows one more try of a refused login: the student asked for it. */
export function clearLoginRejected(service: Service): Promise<void> {
  return updateVault((vault) => {
    if (!vault[service]?.rejected) return false;
    delete vault[service]!.rejected;
  });
}

export const loginRejected = async (service: Service): Promise<boolean> => stillRefused((await readVault())[service]?.rejected);

export function clearLogin(service: Service): Promise<void> {
  return updateVault((vault) => {
    delete vault[service];
  });
}

/** The saved usernames, for Settings. Never the passwords. */
export async function savedUsernames(): Promise<Partial<Record<Service, string>>> {
  const vault = await readVault();
  return Object.fromEntries(Object.entries(vault).map(([s, v]) => [s, v!.username]));
}
