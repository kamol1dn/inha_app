// The script on INS's own pages, bundled as the build does and run over linkedom:
// what a tab does when it loads, which is all the student can ask of it by reloading.

import { beforeEach, test } from 'node:test';
import assert from 'node:assert/strict';
import { fileURLToPath } from 'node:url';
import * as esbuild from 'esbuild';
import { parseHTML } from 'linkedom';

const g = globalThis as unknown as Record<string, unknown>;
const place = { hash: '', origin: 'https://ins.inha.uz', host: 'ins.inha.uz' };
g.location = place;

// Nothing here leaves the machine: a read fails at its first request, and that is all these tests need of it.
const fetched: string[] = [];
g.fetch = async (url: string) => {
  fetched.push(url);
  throw new TypeError('Failed to fetch');
};

let page = parseHTML('<!doctype html><html><body></body></html>');
const asked: string[] = [];
let answers: Record<string, unknown> = {};
let certificate = false;
g.chrome = {
  runtime: {
    sendMessage: async ({ rpc }: { rpc: string }) => {
      asked.push(rpc);
      return { ok: true, value: answers[rpc] ?? null };
    },
  },
  storage: {
    local: { get: async () => ({ 'state.ins': { error: certificate ? { name: 'NetworkError', message: '', certificate: true } : null, at: 1, busy: false } }) },
  },
};

const bundle = await esbuild.build({
  entryPoints: [fileURLToPath(new URL('../src/content/ins.ts', import.meta.url))],
  bundle: true,
  write: false,
  format: 'esm',
  target: 'es2022',
  logLevel: 'silent',
});

let runs = 0;
/** The page loads: the script starts afresh, as it does on a reload. */
async function load() {
  page = parseHTML('<!doctype html><html><body></body></html>');
  g.document = page.document;
  const source = `${bundle.outputFiles[0].text}\n// load ${runs++}`;
  await import(`data:text/javascript;base64,${Buffer.from(source).toString('base64')}`);
  for (let i = 0; i < 6; i++) await new Promise((resolve) => setTimeout(resolve, 2));
}

const notice = () => page.document.getElementById('iut-ins');
const offered = () => notice()?.querySelector('button') ?? null;

beforeEach(() => {
  asked.length = 0;
  fetched.length = 0;
  answers = {};
  certificate = false;
  place.hash = '';
});

test('any other INS page is left alone', async () => {
  await load();
  assert.equal(notice(), null);
  assert.deepEqual(fetched, []);
});

test('told about the certificate, the student is offered the read, and nothing happens until they click', async () => {
  certificate = true;
  await load();
  assert.ok(offered());
  assert.ok(!asked.includes('insAdoptTab'));
  assert.deepEqual(fetched, []);
});

test('a picked tab whose read failed can try again after a reload, with no certificate error on file', async () => {
  answers = { insSyncAllowed: true };
  await load();
  assert.ok(offered(), 'the button is back');
  assert.deepEqual(fetched, [], 'and the read waits for the click');

  const click = new page.window.Event('click');
  Object.defineProperty(click, 'isTrusted', { value: true });
  offered()!.dispatchEvent(click);
  for (let i = 0; i < 6; i++) await new Promise((resolve) => setTimeout(resolve, 2));
  assert.ok(asked.includes('insAdoptTab'));
  assert.equal(asked.at(-1), 'insReport');
  assert.ok(fetched.length > 0);
});

test('a tab opened for the read reads at once', async () => {
  answers = { insSyncAllowed: true };
  place.hash = '#iut-sync';
  await load();
  assert.equal(offered(), null);
  assert.ok(fetched.length > 0);
  assert.ok(asked.includes('insReport'));
});
