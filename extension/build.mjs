// Bundles the extension.
//   node build.mjs             dist/ for Chrome ("Load unpacked")
//   node build.mjs --firefox   dist-firefox/ for Firefox and Zen
//   node build.mjs --watch     rebuild on change
// IUT_VERSION in the environment (CI, from the release tag) replaces the manifest's version.
import * as esbuild from 'esbuild';
import { cpSync, mkdirSync, readFileSync, rmSync, writeFileSync } from 'node:fs';
import { manifestFor } from './manifest.ts';

const watch = process.argv.includes('--watch');
// --dev (and --watch) builds let the test harness reload the extension from an eClass page.
const dev = watch || process.argv.includes('--dev');
const firefox = process.argv.includes('--firefox');
const out = firefox ? 'dist-firefox' : 'dist';

rmSync(out, { recursive: true, force: true });
mkdirSync(out, { recursive: true });
cpSync('static', out, { recursive: true });

const manifest = manifestFor(JSON.parse(readFileSync('static/manifest.json', 'utf8')), { firefox, version: process.env.IUT_VERSION });
writeFileSync(`${out}/manifest.json`, `${JSON.stringify(manifest, null, 2)}
`);

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
