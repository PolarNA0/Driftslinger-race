// Tiny static server for local play and testing. Sends no-store so an edited
// module is never served from the browser's cache mid-session.
import { createServer } from 'node:http';
import { readFile, writeFile } from 'node:fs/promises';
import { extname, join, normalize } from 'node:path';

const ROOT = new URL('..', import.meta.url).pathname;
const PORT = Number(process.argv[2]) || 12000;
const TYPES = {
  '.html': 'text/html; charset=utf-8',
  '.js': 'text/javascript; charset=utf-8',
  '.css': 'text/css; charset=utf-8',
  '.json': 'application/json; charset=utf-8',
  '.png': 'image/png',
  '.svg': 'image/svg+xml',
  '.apk': 'application/vnd.android.package-archive',
};

createServer(async (req, res) => {
  try {
    // Test hook: POST a canvas PNG here so headless checks can inspect a frame.
    if (req.method === 'POST' && req.url.startsWith('/__shot')) {
      const chunks = [];
      for await (const c of req) chunks.push(c);
      await writeFile('/tmp/shot.png', Buffer.concat(chunks));
      res.writeHead(200, { 'cache-control': 'no-store' }).end('ok');
      return;
    }
    let path = decodeURIComponent(req.url.split('?')[0]);
    if (path.endsWith('/')) path += 'index.html';
    const file = normalize(join(ROOT, path));
    if (!file.startsWith(ROOT)) { res.writeHead(403).end('forbidden'); return; }
    const body = await readFile(file);
    res.writeHead(200, {
      'content-type': TYPES[extname(file)] || 'application/octet-stream',
      'cache-control': 'no-store',
    });
    res.end(body);
  } catch {
    res.writeHead(404, { 'cache-control': 'no-store' }).end('not found');
  }
}).listen(PORT, () => console.log(`slingdrift on http://localhost:${PORT}`));
