import type { Service } from './models.ts';

export interface Credentials {
  username: string;
  password: string;
}

/** How a client gets its saved login. The worker passes the vault's reader (src/core/vault.ts); tests pass a stub. */
export type CredentialSource = (service: Service) => Promise<Credentials | null>;

/** Told when a service refuses a login, so nothing posts it again (a wrong password counts toward the domain's lockout). */
export type RejectionSink = (service: Service, login: Credentials) => unknown;

/** A one-way mark of a login: enough to tell the same one again, without keeping the password in memory. */
export async function loginMark(c: Credentials): Promise<string> {
  const digest = await crypto.subtle.digest('SHA-256', new TextEncoder().encode(`${c.username.trim()}\0${c.password}`));
  return btoa(String.fromCharCode(...new Uint8Array(digest)));
}
