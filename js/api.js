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
 *
 * An upload needs a signed-in player, because a run belongs to an account. A
 * guest's runs still queue, and are sent once they sign in.
 */

import { supabaseUrl, supabaseAnonKey, authToken } from './account.js';

const QUEUE_KEY = 'slingdrift.queue.v2';
const CLIENT_KEY = 'slingdrift.clientId.v1';
const TIMEOUT = 8000;

/** A stable per-device id, kept so a guest's queue survives a reload. */
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
  q.push({ track, steps, name, at: Date.now() });
  writeQueue(q);
  return q.length;
}

export const queueLength = () => readQueue().length;

const endpoint = (fn) => `${supabaseUrl()}/functions/v1/${fn}`;

async function post(entry) {
  const token = await authToken();
  // A guest cannot upload: the run has no account to belong to. Keep it queued
  // rather than dropping it, so signing in later sends it.
  if (!token) return { retry: true };

  const ctl = new AbortController();
  const timer = setTimeout(() => ctl.abort(), TIMEOUT);
  try {
    const res = await fetch(endpoint('run'), {
      method: 'POST',
      headers: {
        apikey: supabaseAnonKey(),
        authorization: `Bearer ${token}`,
        'content-type': 'application/json',
      },
      body: JSON.stringify({ track: entry.track, steps: entry.steps }),
      signal: ctl.signal,
    });
    // 422: the server replayed the run and it was not a finish. Re-sending it
    // cannot change that, so drop it instead of retrying forever.
    if (res.status === 422) return { drop: true };
    // 401: the token went stale mid-queue. Retry, and the next flush refreshes.
    if (res.status === 401) return { retry: true };
    // 409: signed in but with no username yet. Retry once a name exists.
    if (res.status === 409) return { retry: true };
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
    const token = await authToken();
    const res = await fetch(`${endpoint('board')}?track=${track}&page=${page}`, {
      headers: {
        apikey: supabaseAnonKey(),
        ...(token ? { authorization: `Bearer ${token}` } : {}),
      },
      signal: ctl.signal,
    });
    if (!res.ok) return null;
    return await res.json();
  } catch {
    return null;
  } finally {
    clearTimeout(timer);
  }
}
