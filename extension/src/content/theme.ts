// The theme on eClass's own document, which the setting and the system's
// preference reach only through here. Pure, so the tests can read it.

import type { Settings } from '../core/store.ts';

export type Theme = Settings['theme'];

/**
 * theme.css's token blocks for eClass's document: every `:root`/`:host`
 * selector scoped to html.iut (and html.iut-wait, the moments before the
 * settings are read), and the glass blocks to html.iut.iut-glass. The type
 * scale stays out of eClass's pages.
 */
export function documentTokens(themeCss: string): string {
  const scoped = (when: string) => `html.iut${when}, html.iut-wait${when}`;
  return themeCss
    .split('/* Type scale')[0]
    .replace(':root:not([data-theme="light"]), :host(:not([data-theme="light"]))', scoped(':not([data-theme="light"])'))
    .replace(':root[data-theme="dark"], :host([data-theme="dark"])', scoped('[data-theme="dark"]'))
    .replace(':root, :host', scoped(''))
    .replace(/:root(\.iut-glass[^,{]*), :host\(\.iut-glass[^{]*\)/g, 'html.iut$1');
}

/** Whether a theme setting comes out dark, given the system's preference. */
export const isDark = (theme: Theme, systemDark: boolean) => theme === 'dark' || (theme === 'system' && systemDark);
