import type { Service } from './models.ts';

export interface Credentials {
  username: string;
  password: string;
}

/** How a client gets its saved login. The worker passes the vault's reader (src/core/vault.ts); tests pass a stub. */
export type CredentialSource = (service: Service) => Promise<Credentials | null>;
