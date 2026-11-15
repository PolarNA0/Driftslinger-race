// Offline shell. Precache the whole game on install so it plays with no
// network, but serve network-first while online: a cache-first shell would pin
// the player to whatever build was cached first, so edits would never show up.

const VERSION = 'slingdrift-v17';
const SHELL = [
  './',
  'index.html',
  'manifest.webmanifest',
  'css/style.css',
  'js/app.js',
  'js/game.js',
  'js/car.js',
  'js/track.js',
  'js/tracks.js',
  'js/render.js',
  'js/config.js',
  'js/storage.js',
  'js/account.js',
  'js/ghostrun.js',
  'js/ghostdata.js',
  'js/leaderboard.js',
  'js/replay.js',
  'js/api.js',
  'js/util.js',
  'icons/icon-192.png',
  'icons/icon-512.png',
  'icons/maskable-512.png',
  'icons/apple-touch-icon.png',
];

self.addEventListener('install', (event) => {
  event.waitUntil(
    caches.open(VERSION)
      .then((cache) => Promise.allSettled(SHELL.map((u) => cache.add(new Request(u, { cache: 'reload' })))))
      .then(() => self.skipWaiting()),
  );
});

self.addEventListener('activate', (event) => {
  event.waitUntil(
    caches.keys()
      .then((keys) => Promise.all(keys.filter((k) => k !== VERSION).map((k) => caches.delete(k))))
      .then(() => self.clients.claim()),
  );
});

function fetchAndCache(request) {
  return fetch(request).then((res) => {
    if (res && res.status === 200 && res.type === 'basic') {
      const copy = res.clone();
      caches.open(VERSION).then((c) => c.put(request, copy)).catch(() => {});
    }
    return res;
  });
}

self.addEventListener('fetch', (event) => {
  const { request } = event;
  if (request.method !== 'GET') return;
  const url = new URL(request.url);
  if (url.origin !== self.location.origin) return;

  // Icons never change, so serve them from cache first. Everything else - the
  // page and every script - goes to the network first, because a cache-first
  // shell silently pins the player to an old build: you edit a file, reload, and
  // still get the previous version. The cache is only the offline fallback.
  const isIcon = url.pathname.includes('/icons/');

  if (request.mode === 'navigate') {
    event.respondWith(
      fetch(request).then((res) => {
        const copy = res.clone();
        caches.open(VERSION).then((c) => c.put('index.html', copy)).catch(() => {});
        return res;
      }).catch(() => caches.match('index.html').then((r) => r || caches.match('./'))),
    );
    return;
  }

  event.respondWith(
    (isIcon
      ? caches.match(request).then((c) => c || fetchAndCache(request))
      : fetchAndCache(request).catch(() => caches.match(request))
    ).then((r) => r || Response.error()),
  );
});
