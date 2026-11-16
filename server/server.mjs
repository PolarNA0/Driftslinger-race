// The game server: static files plus the leaderboard API, on one origin.
//
// One process serves both, so the client never needs CORS and the whole thing is
// one command to run locally and one small service to host. The physics modules
// it verifies with are the game's own, imported unchanged.
import { createServer } from 'node:http';
import { readFile } from 'node:fs/promises';
import { extname, join, normalize } from 'node:path';
import { fileURLToPath } from 'node:url';
import { dirname } from 'node:path';
import { verifyRun } from './verify.mjs';
import { Store } from './store.mjs';
import { isPlayableTrack } from '../js/tracks.js';

const HERE = dirname(fileURLToPath(import.meta.url));
const ROOT = join(HERE, '..');
const PORT = Number(process.env.PORT) || 12000;
const PER_PAGE = 50;

const TYPES = {
  '.html': 'text/html; charset=utf-8',
  '.js': 'text/javascript; charset=utf-8',
  '.mjs': 'text/javascript; charset=utf-8',
  '.css': 'text/css; charset=utf-8',
  '.json': 'application/json; charset=utf-8',
  '.webmanifest': 'application/manifest+json; charset=utf-8',
  '.png': 'image/png',
  '.svg': 'image/svg+xml',
  '.apk': 'application/vnd.android.package-archive',
};

const store = await new Store().load();

const json = (res, code, body) => {
  res.writeHead(code, {
    'content-type': 'application/json; charset=utf-8',
    'cache-control': 'no-store',
    'access-control-allow-origin': '*',
  });
  res.end(JSON.stringify(body));
};

// The board is public data and there are no cookies or credentials, so a
// permissive CORS policy is safe here: it only lets a page on another host read
// public scores. It is what allows the game on GitHub Pages to use this API.
const corsPreflight = (res) => {
  res.writeHead(204, {
    'access-control-allow-origin': '*',
    'access-control-allow-methods': 'GET, POST, OPTIONS',
    'access-control-allow-headers': 'content-type',
    'access-control-max-age': '86400',
  });
  res.end();
};

const readBody = async (req, limit = 64 * 1024) => {
  const chunks = [];
  let n = 0;
  for await (const c of req) {
    n += c.length;
    if (n > limit) throw new Error('too large');
    chunks.push(c);
  }
  return Buffer.concat(chunks).toString('utf8');
};

async function handleApi(req, res, url) {
  if (url.pathname === '/api/health') {
    return json(res, 200, { ok: true, tracks: Object.keys(store.tracks).length });
  }

  if (url.pathname === '/api/board' && req.method === 'GET') {
    const track = Number(url.searchParams.get('track'));
    if (!isPlayableTrack(track)) return json(res, 400, { error: 'bad track' });
    const page = Number(url.searchParams.get('page')) || 1;
    const clientId = url.searchParams.get('clientId') || '';
    const out = store.page(track, page, PER_PAGE);
    out.you = store.rankOf(track, clientId);
    return json(res, 200, out);
  }

  if (url.pathname === '/api/run' && req.method === 'POST') {
    let body;
    try {
      body = JSON.parse(await readBody(req));
    } catch {
      return json(res, 400, { error: 'bad json' });
    }
    const { track, steps, name, clientId } = body ?? {};
    // The submitted time is deliberately ignored: the server recomputes it from
    // the steps, so a forged time cannot enter the board.
    const verdict = verifyRun(track, steps);
    if (!verdict.ok) return json(res, 422, { error: verdict.reason });
    const out = store.add(track, {
      time: verdict.time,
      name,
      steps,
      clientId: String(clientId ?? '').slice(0, 64),
    });
    return json(res, 200, {
      ok: true,
      time: verdict.time,
      rank: out.rank,
      total: store.list(track).length,
      improved: out.improved,
    });
  }

  return json(res, 404, { error: 'no such endpoint' });
}

async function serveStatic(res, pathname) {
  let path = decodeURIComponent(pathname.split('?')[0]);
  if (path.endsWith('/')) path += 'index.html';
  const file = normalize(join(ROOT, path));
  if (!file.startsWith(ROOT)) { res.writeHead(403).end('forbidden'); return; }
  const body = await readFile(file);
  res.writeHead(200, {
    'content-type': TYPES[extname(file)] || 'application/octet-stream',
    'cache-control': 'no-store',
  });
  res.end(body);
}

createServer(async (req, res) => {
  const url = new URL(req.url, 'http://localhost');
  try {
    if (url.pathname.startsWith('/api/')) {
      if (req.method === 'OPTIONS') return corsPreflight(res);
      return await handleApi(req, res, url);
    }
    await serveStatic(res, url.pathname);
  } catch (err) {
    if (err && err.code === 'ENOENT') { res.writeHead(404).end('not found'); return; }
    res.writeHead(500).end('server error');
  }
}).listen(PORT, () => {
  console.log(`Sling Drift on http://localhost:${PORT}  (API at /api/board)`);
});
