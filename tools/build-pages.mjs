// Build a static copy of the game for GitHub Pages (or any static host).
//
// GitHub Pages serves files only - it cannot run the leaderboard API. So this
// copies the game and points it at an API somewhere else, via the
// <meta name="sling-api"> tag that js/api.js reads. With no URL given, the copy
// runs fully offline and the board falls back to the local one.
//
//   node tools/build-pages.mjs https://your-api.example.com
//
// The API's own /api prefix is added for you, so pass the host, not the full path.
import { cp, mkdir, rm, readFile, writeFile, stat } from 'node:fs/promises';
import { join, dirname } from 'node:path';
import { fileURLToPath } from 'node:url';

const ROOT = join(dirname(fileURLToPath(import.meta.url)), '..');
const OUT = join(ROOT, 'dist');
const arg = (process.argv[2] || '').replace(/\/$/, '');
// js/api.js appends "/run" and "/board" to this, so it must end at /api.
const api = arg ? `${arg.replace(/\/api$/, '')}/api` : '';

// Everything the browser needs. Not included: server/, tools/, android/, the
// APKs, or the docs - Pages should serve the game and nothing else.
const ITEMS = ['index.html', 'download.html', 'manifest.webmanifest', 'sw.js',
  'css', 'js', 'icons'];

await rm(OUT, { recursive: true, force: true });
await mkdir(OUT, { recursive: true });

for (const item of ITEMS) {
  const src = join(ROOT, item);
  try {
    await stat(src);
  } catch {
    console.warn(`skip ${item} (missing)`);
    continue;
  }
  await cp(src, join(OUT, item), { recursive: true });
}

// Point the copy at the API. An empty value leaves the game same-origin, which
// only works when the server also serves the files; on a static host it just
// means the board stays local.
const index = await readFile(join(OUT, 'index.html'), 'utf8');
const TAG = /<meta name="sling-api" content="[^"]*" \/>/;
// Test the pattern rather than comparing before and after: when the API is empty
// the replacement is identical to the original, which is not an error.
if (!TAG.test(index)) {
  console.error('could not find the sling-api meta tag in index.html');
  process.exit(1);
}
await writeFile(join(OUT, 'index.html'),
  index.replace(TAG, `<meta name="sling-api" content="${api}" />`));

// Pages runs Jekyll by default, which ignores files starting with an underscore.
await writeFile(join(OUT, '.nojekyll'), '');

console.log(`built dist/  (${api || 'no API: offline only'})`);
if (!api) {
  console.log('pass your API URL to enable the shared leaderboard, e.g.');
  console.log('  node tools/build-pages.mjs https://slingdrift-api.fly.dev');
}
