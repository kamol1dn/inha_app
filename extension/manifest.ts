// The manifest each browser gets, from static/manifest.json. CI passes the
// version from the release tag, so a tag never has to match a number in the repo.

type Manifest = Record<string, unknown> & { options_page?: string };

/** What a tag like v1.4.0 gives as a manifest version, or null when it has no numeric form the browsers accept. */
export function versionOfTag(tag: string): string | null {
  const version = tag.replace(/^v/, '').split(/[-+]/)[0];
  return /^\d+(\.\d+){0,3}$/.test(version) ? version : null;
}

export function manifestFor(base: Manifest, { firefox, version }: { firefox: boolean; version?: string }): Manifest {
  const manifest: Manifest = { ...base };
  if (version) manifest.version = version;
  if (!firefox) return manifest;

  // Firefox (and Zen, which is built on it) runs the worker's code as a
  // background script rather than a service worker, and needs a fixed add-on ID.
  // That ID does what "key" does for Chrome's unpacked install, and Firefox has no use for the key.
  delete manifest.key;
  manifest.background = { scripts: ['background.js'], type: 'module' };
  manifest.options_ui = { page: manifest.options_page, open_in_tab: true };
  delete manifest.options_page;
  manifest.browser_specific_settings = {
    gecko: {
      id: 'iut-eclass@kamol1dn.github.io',
      strict_min_version: '128.0',
      // It talks only to the university's own services, as the student; nothing goes to us or anyone else.
      data_collection_permissions: { required: ['none'] },
    },
  };
  return manifest;
}
