// Runs on ins.inha.uz. INS still serves a certificate that expired in 2024,
// so the browser refuses the worker's requests to it. A tab the student opened
// (and chose Proceed on once) can still talk to INS, so when the extension
// opens INS for a sync (#iut-sync), this script reads the grades from inside
// the tab, the same way the worker would, and hands them over.

import { errorInfo } from '../core/errors.ts';
import { call } from '../core/rpc.ts';
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
  const client = new InsClient(() => call('insLogin'), { base: location.origin });
  try {
    const report = await client.grades();
    await call('insReport', report, null);
    notice('Grades updated. You can close this tab.');
  } catch (e) {
    await call('insReport', null, errorInfo(e)).catch(() => {});
    notice((e as Error).name === 'LoginRequired' ? 'INS didn’t accept the saved login. Check it in IUT settings.' : 'Couldn’t read the grades from INS.');
  }
}

if (location.hash.includes('iut-sync')) {
  if (document.body) void sync();
  else document.addEventListener('DOMContentLoaded', () => void sync(), { once: true });
}
