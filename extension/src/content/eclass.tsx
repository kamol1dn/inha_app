// Runs on every eclass.inha.ac.kr page, from document_start.
//
// eClass keeps its own structure: header, left menu, course list, side
// blocks, every page and form. Under "New look on eClass" it is restyled in
// the paper look (moodle.css) and the extension's features go where they fit
// (parts.tsx); the sign-in page is the extension's own (signin.tsx).

import { render } from 'preact';
import { call } from '../core/rpc.ts';
import { readSettings, readSnapshot, writeSettings } from '../core/store.ts';
import { fontFaces } from '../ui/fonts.ts';
import themeCss from '../ui/theme.css';
import { darkRulesOf } from './darkrules.ts';
import moodleCss from './moodle.css';
import { isSignInPage, SIGN_IN_TRY } from './pages.ts';
import { decorate } from './parts.tsx';
import { hideMessageId, mountViews } from './view.tsx';
import { setPartsTheme, shadowHost } from './shared.tsx';
import { signInPage } from './signin.tsx';
import { documentTokens, isDark, type Theme } from './theme.ts';

declare const __DEV__: boolean;

const root = document.documentElement;
root.classList.add('iut-wait');
hideMessageId();

// Settings arrive a moment after the first paint can: the theme last used here keeps that moment from flashing white.
const REMEMBERED_THEME = 'iut.theme';
const remember = (theme: Theme) => {
  try {
    localStorage.setItem(REMEMBERED_THEME, theme);
  } catch {
    // Blocked site data: only the moment before the settings is affected.
  }
};
try {
  const known = localStorage.getItem(REMEMBERED_THEME);
  if (known === 'light' || known === 'dark') root.dataset.theme = known;
} catch {
  // As above.
}

const style = document.createElement('style');
style.textContent = `${fontFaces(chrome.runtime.getURL('fonts/'))}\n${documentTokens(themeCss)}\n${moodleCss}`;
root.append(style);

// Before moodle.css, whose rules win a tie. Filled once there are sheets to read, and only in the dark.
const darkStyle = document.createElement('style');
style.before(darkStyle);
let paintedSheets = 0;

/** Answers whatever eClass's sheets, as loaded so far, set for white paper. A sheet that can't be read is skipped. */
function paintDark(): void {
  // Reading some 10,000 rules takes a moment: only again when another sheet has arrived.
  if (!root.classList.contains('iut-paint') || document.styleSheets.length === paintedSheets) return;
  const rules: string[] = [];
  for (const sheet of Array.from(document.styleSheets)) {
    if (sheet.ownerNode === style || sheet.ownerNode === darkStyle) continue;
    try {
      rules.push(...darkRulesOf(sheet.cssRules));
    } catch {
      // Another site's sheet: nothing to read.
    }
  }
  darkStyle.textContent = rules.join('\n');
  paintedSheets = document.styleSheets.length;
}

const path = location.pathname.replace(/\/+$/, '') || '/';

/** Once the page is parsed: what it holds (the sign-in form, the menus) is known only then. */
const whenParsed = (run: () => void) =>
  document.readyState === 'loading' ? document.addEventListener('DOMContentLoaded', run, { once: true }) : run();

/**
 * The theme on eClass's document and every part on it, followed live: the
 * setting from any page of the extension, the system's preference from the OS.
 * html.iut-dark is for moodle.css's rules that exist only in the dark,
 * html.iut-glass for the transparent background, and html.iut-paint for the
 * answers to eClass's white paper, which either one needs.
 */
function followTheme(initial: { theme: Theme; glass: boolean }): void {
  const system = matchMedia('(prefers-color-scheme: dark)');
  let { theme, glass } = initial;
  const apply = () => {
    if (theme === 'system') delete root.dataset.theme;
    else root.dataset.theme = theme;
    const dark = isDark(theme, system.matches);
    root.classList.toggle('iut-dark', dark);
    root.classList.toggle('iut-glass', glass);
    root.classList.toggle('iut-paint', dark || glass);
    if (document.readyState !== 'loading') paintDark();
    setPartsTheme(theme, glass);
    remember(theme);
  };
  apply();
  system.addEventListener('change', apply);
  chrome.storage.onChanged.addListener((changes, area) => {
    const next = changes.settings?.newValue as { theme?: Theme; glass?: boolean } | undefined;
    if (area !== 'local' || !next) return;
    const nextTheme = next.theme ?? theme;
    const nextGlass = next.glass ?? false;
    if (nextTheme === theme && nextGlass === glass) return;
    theme = nextTheme;
    glass = nextGlass;
    apply();
  });
}

// A click on eClass's own Log out: nothing signs the browser back in until the student signs in again.
document.addEventListener('click', (e) => {
  if ((e.target as Element | null)?.closest?.('a[href*="/login/logout.php"]')) void call('eclassLoggedOut').catch(() => {});
}, true);

void (async () => {
  const settings = await readSettings();
  if (!settings.takeover) {
    // Classic eClass: the page as it is, with a way back to the new look.
    root.classList.remove('iut-wait');
    delete root.dataset.theme;
    remember('light');
    whenParsed(() =>
      render(
        <button class="classic-back" onClick={async () => (await writeSettings({ takeover: true }), location.reload())}>New look</button>,
        shadowHost('iut-classic', (el) => document.body.append(el)),
      ),
    );
    return;
  }

  root.classList.add('iut');
  followTheme(settings);
  addEventListener('load', paintDark, { once: true }); // the sheets eClass adds late
  whenParsed(() => {
    paintDark();
    if (isSignInPage(path, document)) {
      void signInPage().finally(() => root.classList.remove('iut-wait'));
      return;
    }
    try {
      sessionStorage.removeItem(SIGN_IN_TRY); // got past the sign-in page
    } catch {
      // Blocked site data: only the check for a sign-in that doesn't reach this tab is affected.
    }
    try {
      decorate(path);
      // The front page hosts the extension's views ('/#/grades'); a view-only link from elsewhere lands there.
      if (path === '/' || path === '/index.php') mountViews();
    } finally {
      root.classList.remove('iut-wait');
    }
  });
})();

// After the extension updates, this script can no longer reach it: the page
// keeps working as eClass, and a note offers the reload that brings IUT back.
const stale = setInterval(() => {
  if (chrome.runtime?.id) return;
  clearInterval(stale);
  const note = document.createElement('button');
  note.textContent = 'IUT for eClass was updated. Reload this page';
  Object.assign(note.style, {
    position: 'fixed', left: '50%', bottom: '24px', transform: 'translateX(-50%)', zIndex: '2147483000', border: '0', borderRadius: '8px',
    padding: '12px 16px', background: '#2E2C28', color: '#F2EEE4', font: '600 15px/20px system-ui, sans-serif', cursor: 'pointer',
  });
  note.onclick = () => location.reload();
  document.body.append(note);
}, 5000);

// Never leave a page hidden if something above failed.
setTimeout(() => root.classList.remove('iut-wait'), 2500);

// Development builds only: the test harness reloads the extension from the page.
// It can also call the worker and read storage, to see what a view would get.
if (__DEV__) {
  addEventListener('message', async (e) => {
    if (e.source !== window) return;
    if (e.data?.iut === 'dev-reload') void chrome.runtime.sendMessage({ devReload: true });
    if (e.data?.iut === 'dev-call') {
      const reply = await call(e.data.method, ...(e.data.args ?? [])).then((value) => ({ value }), (err) => ({ error: `${err.name}: ${err.message}` }));
      postMessage({ iut: 'dev-reply', id: e.data.id, reply: JSON.parse(JSON.stringify(reply)) }, '*');
    }
    if (e.data?.iut === 'dev-state') {
      const { state } = await readSnapshot();
      postMessage({ iut: 'dev-reply', id: e.data.id, reply: state }, '*');
    }
  });
}
