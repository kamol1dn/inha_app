// Runs on ins.inha.uz. INS still serves a certificate that expired in 2024,
// so the browser refuses the worker's requests to it. A tab the student opened
// (and chose Proceed on once) can still talk to INS, so in a tab the extension
// opened for a sync, or one the student picks here, this script reads the grades
// from inside the tab, the same way the worker would, and hands them over.
//
// The saved password goes only to those tabs. The page's address (#iut-sync)
// proves nothing: with a certificate the student was told to click through, it
// could be anyone's page.

import { errorInfo, type LoginRequired } from '../core/errors.ts';
import { call } from '../core/rpc.ts';
import { readState } from '../core/store.ts';
import { InsClient } from '../services/ins/client.ts';

function notice(text: string): HTMLElement {
  const el = document.getElementById('iut-ins') ?? document.createElement('div');
  el.id = 'iut-ins';
  el.textContent = text;
  Object.assign(el.style, {
    position: 'fixed', left: '50%', bottom: '24px', transform: 'translateX(-50%)', zIndex: '2147483000',
    background: '#2E2C28', color: '#F2EEE4', padding: '12px 16px', borderRadius: '8px', font: '15px/20px system-ui, sans-serif',
  });
  document.body.append(el);
  return el;
}

async function sync() {
  notice('IUT for eClass is reading your grades…');
  const client = new InsClient(() => call('insLogin'), { base: location.origin, inTab: true });
  try {
    const report = await client.grades();
    await call('insReport', report, null);
    notice('Grades updated. You can close this tab.');
  } catch (e) {
    await call('insReport', null, errorInfo(e)).catch(() => {});
    if ((e as Error).name !== 'LoginRequired') notice('Couldn’t read the grades from INS.');
    else if ((e as LoginRequired).rejected) notice('INS didn’t accept the saved login. Check it in IUT settings.');
    else notice('No INS login to use. Add it in IUT settings.');
  }
}

/** The student came here by hand after being told about the certificate: one click, theirs, lets this tab read the grades. */
function offer() {
  const el = notice('The grades in IUT for eClass need updating. ');
  const button = document.createElement('button');
  button.textContent = 'Read my grades';
  Object.assign(button.style, { marginLeft: '12px', font: 'inherit', padding: '4px 12px', borderRadius: '6px', border: '1px solid currentColor', background: 'none', color: 'inherit', cursor: 'pointer' });
  button.addEventListener('click', (e) => {
    if (!e.isTrusted) return;
    void call('insAdoptTab').then(sync);
  }, { once: true });
  el.append(button);
}

async function start() {
  if (await call('insSyncAllowed')) {
    if (location.hash.includes('iut-sync')) await sync();
    return;
  }
  if ((await readState()).ins?.error?.certificate) offer();
}

if (document.body) void start();
else document.addEventListener('DOMContentLoaded', () => void start(), { once: true });
