// The service worker has no DOMParser; the parsers get linkedom's. Imported
// first by index.ts so it is in place before any parser runs.
import { DOMParser } from 'linkedom';

(globalThis as { DOMParser?: unknown }).DOMParser ??= DOMParser;
