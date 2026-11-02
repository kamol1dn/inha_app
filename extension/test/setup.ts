// Shared by every test: linkedom's DOMParser in place of the browser's, and
// the app's anonymized fixtures (../test/fixtures in the Flutter repo).
import { readFileSync } from 'node:fs';
import { DOMParser } from 'linkedom';

(globalThis as { DOMParser?: unknown }).DOMParser ??= DOMParser;

const fixtures = new URL('../../test/fixtures/', import.meta.url);

export const fixture = (name: string): string => readFileSync(new URL(name, fixtures), 'utf8');
export const fixtureBytes = (name: string): Uint8Array => readFileSync(new URL(name, fixtures));
