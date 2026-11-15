/**
 * Talking to the leaderboard server.
 *
 * The game is offline-first, so nothing here is allowed to block play: a run is
 * always saved locally first, and the upload is best-effort. If there is no
 * network the submission goes into a queue and is retried later, so a run made in
 * a tunnel still counts when the phone gets signal back.
 *
 * The submitted time is not sent: the server recomputes it from the button steps.
 * Sending it would only invite the server to disagree with the client.
 */

const API = (() => {
  // Same origin by default, which is what the bundled server does. When the game
  // is hosted somewhere static (GitHub Pages, itch.io) and the API lives on
  // another host, point at it with <meta name="sling-api" content="https://...">.
  const meta = typeof document !== 'undefined'
    && document.querySelector('meta[name="sling-api"]');
  const native = typeof window !== 'undefined' && window.SlingDriftNative
    && window.SlingDriftNative.apiBase && window.SlingDriftNative.apiBase();
  const base = (meta && meta.content) || native
    || (typeof window !== 'undefined' && window.SLING_API_BASE);
  return base ? String(base).replace(/\/$/, '') : './api';
})();
const QUEUE_KEY = 'slingdrift.queue.v1';
const CLIENT_KEY = 'slingdrift.clientId.v1';
const TIMEOUT = 8000;

/** A stable per-device id, so the board can show one row per player per track. */
export function clientId() {
  try {
    let id = localStorage.getItem(CLIENT_KEY);
    if (!id) {
      id = (crypto.randomUUID ? crypto.randomUUID() : String(Math.random()).slice(2)).slice(0, 32);
      localStorage.setItem(CLIENT_KEY, id);
    }
    return id;
  } catch {
    return 'anon';
  }
}

function readQueue() {
  try { return JSON.parse(localStorage.getItem(QUEUE_KEY)) || []; } catch { return []; }
}
function writeQueue(q) {
  try { localStorage.setItem(QUEUE_KEY, JSON.stringify(q.slice(-50))); } catch { /* full or private */ }
}

/** Queue a finished run. Always succeeds - uploading is not the player's problem. */
export function enqueue({ track, steps, name }) {
  const q = readQueue().filter((e) => !(e.track === track && e.steps === steps));
  q.push({ track, steps, name, clientId: clientId(), at: Date.now() });
  writeQueue(q);
  return q.length;
}

export const queueLength = () => readQueue().length;

async function post(entry) {
  const ctl = new AbortController();
  const timer = setTimeout(() => ctl.abort(), TIMEOUT);
  try {
    const res = await fetch(`${API}/run`, {
      method: 'POST',
      headers: { 'content-type': 'application/json' },
      body: JSON.stringify(entry),
      signal: ctl.signal,
    });
    if (res.status === 422) return { drop: true };   // server proved it invalid
    if (!res.ok) return { retry: true };
    return { ok: true, body: await res.json() };
  } catch {
    return { retry: true };                          // offline, DNS, timeout
  } finally {
    clearTimeout(timer);
  }
}

/**
 * Try to send everything queued. Returns the last successful result, so the
 * caller can show "you are #12" once the run lands. Runs are sent oldest first.
 */
export async function flush() {
  const q = readQueue();
  if (!q.length) return null;
  const keep = [];
  let last = null;
  for (const entry of q) {
    const r = await post(entry);
    if (r.drop) continue;              // invalid: do not keep retrying it
    if (r.retry) { keep.push(entry); continue; }
    last = { ...r.body, track: entry.track };
  }
  writeQueue(keep);
  return last;
}

/** Fetch one page of a track's board, or null when offline. */
export async function fetchBoard(track, page = 1) {
  const ctl = new AbortController();
  const timer = setTimeout(() => ctl.abort(), TIMEOUT);
  try {
    const q = `track=${track}&page=${page}&clientId=${encodeURIComponent(clientId())}`;
    const res = await fetch(`${API}/board?${q}`, { signal: ctl.signal });
    if (!res.ok) return null;
    return await res.json();
  } catch {
    return null;
  } finally {
    clearTimeout(timer);
  }
}
