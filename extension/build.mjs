// Bundles the extension.
//   node build.mjs             dist/ for Chrome ("Load unpacked")
//   node build.mjs --firefox   dist-firefox/ for Firefox and Zen
//   node build.mjs --watch     rebuild on change
import * as esbuild from 'esbuild';
import { cpSync, mkdirSync, readFileSync, rmSync, writeFileSync } from 'node:fs';

const watch = process.argv.includes('--watch');
// --dev (and --watch) builds let the test harness reload the extension from an eClass page.
const dev = watch || process.argv.includes('--dev');
const firefox = process.argv.includes('--firefox');
const out = firefox ? 'dist-firefox' : 'dist';

rmSync(out, { recursive: true, force: true });
mkdirSync(out, { recursive: true });
cpSync('static', out, { recursive: true });

// Firefox (and Zen, which is built on it) runs the worker's code as a
// background script rather than a service worker, and needs a fixed add-on ID.
if (firefox) {
  const manifest = JSON.parse(readFileSync('static/manifest.json', 'utf8'));
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
  writeFileSync(`${out}/manifest.json`, `${JSON.stringify(manifest, null, 2)}
`);
}

const common = {
  outdir: out,
  bundle: true,
  target: firefox ? 'firefox128' : 'chrome120',
  jsx: 'automatic',
  jsxImportSource: 'preact',
  loader: { '.css': 'text' },
  sourcemap: watch ? 'inline' : false,
  minify: !watch,
  logLevel: 'info',
  define: { __DEV__: String(dev) },
};

// The worker and the extension pages are ES modules; content scripts can't be.
const builds = [
  {
    ...common,
    format: 'esm',
    entryPoints: {
      background: 'src/background/index.ts',
      'pages/app': 'src/ui/main.tsx',
    },
  },
  {
    ...common,
    format: 'iife',
    entryPoints: {
      'content/eclass': 'src/content/eclass.tsx',
      'content/ins': 'src/content/ins.ts',
    },
  },
];

if (watch) {
  for (const b of builds) await (await esbuild.context(b)).watch();
} else {
  await Promise.all(builds.map((b) => esbuild.build(b)));
}
