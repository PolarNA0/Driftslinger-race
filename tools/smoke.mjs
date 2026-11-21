#!/usr/bin/env node
// Post-deploy smoke test.
//
// A deploy is only green if the thing it shipped actually answers. These are the
// failures that have bitten this project or would take a player out silently:
//
//   web    GET /           200 and the game's title in the HTML
//          GET /index.wasm 200, application/wasm, and a real wasm header. The
//                          wasm is stored gzipped to fit Cloudflare's 25 MiB
//                          asset cap; a wrong Content-Encoding hands the browser
//                          a gzip blob it cannot compile, and the site still
//                          returns 200, so check the bytes.
//          GET /android    302 to the rolling APK release
//   board  GET board?track=1                    200 JSON with a rows array
//          GET board?track=1&mode=endless       200 JSON with a rows array
//                          The wrong select list on the leaderboard view took
//                          the whole board down with a 500.
//
//   node tools/smoke.mjs web [base]
//   node tools/smoke.mjs board
//   node tools/smoke.mjs          # both

import { readFileSync } from 'node:fs';
import { fileURLToPath } from 'node:url';
import { dirname, join } from 'node:path';

const root = join(dirname(fileURLToPath(import.meta.url)), '..');
const WEB = process.env.SMOKE_WEB ?? 'https://driftslinger-race.exopolar1.workers.dev';

let failures = 0;
function check(label, cond, detail = '') {
  console.log(`${cond ? 'ok  ' : 'FAIL'}  ${label}${detail ? `  (${detail})` : ''}`);
  if (!cond) failures++;
}

function netConfig() {
  const src = readFileSync(join(root, 'godot', 'scripts', 'netconfig.gd'), 'utf8');
  const url = src.match(/DEFAULT_URL\s*:=\s*"([^"]+)"/)?.[1];
  const key = src.match(/DEFAULT_KEY\s*:=\s*"([^"]+)"/)?.[1];
  if (!url || !key) throw new Error('cannot read the project URL and anon key from netconfig.gd');
  return { url: url.replace(/\/$/, ''), key };
}

async function web(base = WEB) {
  console.log(`-- web ${base} --`);

  const home = await fetch(`${base}/`);
  const html = await home.text();
  check('GET / is 200', home.status === 200, String(home.status));
  check('the page names the game', /Sling Drift/i.test(html));

  const wasm = await fetch(`${base}/index.wasm`);
  const type = wasm.headers.get('content-type') ?? '';
  const bytes = new Uint8Array((await wasm.arrayBuffer()).slice(0, 4));
  const magic = [...bytes].map((b) => b.toString(16).padStart(2, '0')).join(' ');
  check('GET /index.wasm is 200', wasm.status === 200, String(wasm.status));
  check('it is served as wasm', type.includes('application/wasm'), type);
  check('it starts with the wasm magic', magic === '00 61 73 6d', magic);

  const android = await fetch(`${base}/android`, { redirect: 'manual' });
  const location = android.headers.get('location') ?? '';
  check('GET /android redirects', [301, 302, 307, 308].includes(android.status), String(android.status));
  check('it points at the rolling APK release', location.includes('android-latest'), location);
}

async function board() {
  const { url, key } = netConfig();
  console.log(`-- board ${url} --`);
  const headers = { apikey: key };

  for (const [label, query] of [
    ['speedrun', 'track=1'],
    ['endless', 'track=1&mode=endless'],
  ]) {
    const res = await fetch(`${url}/functions/v1/board?${query}`, { headers });
    let body = null;
    try {
      body = await res.json();
    } catch {
      /* a non-JSON body is reported below */
    }
    check(`${label} board is 200`, res.status === 200, String(res.status));
    check(`${label} board returns rows`, Array.isArray(body?.rows), JSON.stringify(body).slice(0, 80));
  }
}

const mode = process.argv[2] ?? 'all';
try {
  if (mode === 'web' || mode === 'all') await web(process.argv[3]);
  if (mode === 'board' || mode === 'all') await board();
  if (!['web', 'board', 'all'].includes(mode)) {
    console.error(`unknown mode ${mode}; use web, board or all`);
    process.exit(2);
  }
} catch (err) {
  console.error(`FAIL  ${err.message}`);
  process.exit(1);
}

console.log(failures === 0 ? 'SMOKE PASS' : `SMOKE FAIL (${failures})`);
process.exit(failures === 0 ? 0 : 1);
