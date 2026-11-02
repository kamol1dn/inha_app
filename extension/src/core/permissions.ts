// The sites the worker talks to. Chrome grants them at install. Firefox and Zen
// can leave them off (always for a temporary add-on), and then every request
// fails as if the connection were down, so Welcome and Settings ask for them.

export const hostOrigins = [
  'https://eclass.inha.ac.kr/*',
  'https://ins.inha.uz/*',
  'https://mail.inha.uz/*',
  'https://iut.edupage.org/*',
];

/** The sites not granted right now. None where the browser can't say. */
export async function missingHosts(): Promise<string[]> {
  if (!chrome.permissions?.contains) return [];
  const held = await Promise.all(hostOrigins.map((o) => chrome.permissions.contains({ origins: [o] }).catch(() => true)));
  return hostOrigins.filter((_, i) => !held[i]);
}

/** Asks the browser for every site. Only works inside a click. True when granted. */
export const requestHosts = (): Promise<boolean> => chrome.permissions.request({ origins: hostOrigins });
