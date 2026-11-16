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

import { supabaseUrl, supabaseAnonKey, authToken, currentUserId } from './account.js';

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

/**
 * The signed-in player's own best runs, keyed by track, or null when offline.
 *
 * A player's times live on the server, but the game reads its records from
 * localStorage. On a device that never made the run - a reinstall, a second
 * phone, a cleared cache - signing in would otherwise show nothing even though
 * the account holds the times. This pulls them back down so the account is the
 * source of truth, not the device.
 *
 * Reads the `runs` table directly with the caller's token. RLS allows any reader
 * to see any run, so this filters to this user explicitly; that is a query
 * narrowing, not a security boundary.
 */
export async function fetchMyRuns() {
  const me = currentUserId();
  if (!me) return null;

  const ctl = new AbortController();
  const timer = setTimeout(() => ctl.abort(), TIMEOUT);
  try {
    const token = await authToken();
    if (!token) return null;
    const res = await fetch(
      `${supabaseUrl()}/rest/v1/runs?user_id=eq.${me}&select=track,ticks,steps`,
      {
        headers: { apikey: supabaseAnonKey(), authorization: `Bearer ${token}` },
        signal: ctl.signal,
      },
    );
    if (!res.ok) return null;
    const rows = await res.json();
    if (!Array.isArray(rows)) return null;
    // One row per track, so this is the player's best by construction: the table
    // keeps a single row per user per track and only ever lowers it.
    return rows.map((r) => ({ track: r.track, time: r.ticks / 120, steps: r.steps ?? null }));
  } catch {
    return null;
  } finally {
    clearTimeout(timer);
  }
}

/**
 * Save the tracker settings the server posts with.
 *
 * The webhook and the two message templates are read by the `run` function when
 * it announces a record, so they have to live on the server, not on the admin's
 * device. They are written straight to `tracker_config` with the admin's token:
 * RLS lets a signed-in player update that row but not read `webhook_url` back, so
 * the credential goes up and never comes down. Returns true when the row took it.
 *
 * A guest, or a device with no Supabase configured, returns false - the settings
 * still save locally, so the admin UI keeps working, but the server will not
 * announce until an admin signs in and saves again.
 */
export async function saveTrackerConfig({ webhook, wrMessage, posMessage }) {
  const token = await authToken();
  if (!token) return false;

  const body = {};
  if (webhook !== undefined) body.webhook_url = String(webhook).trim();
  if (wrMessage !== undefined) body.wr_message = String(wrMessage).trim();
  if (posMessage !== undefined) body.pos_message = String(posMessage).trim();
  if (!Object.keys(body).length) return true;

  const ctl = new AbortController();
  const timer = setTimeout(() => ctl.abort(), TIMEOUT);
  try {
    const res = await fetch(`${supabaseUrl()}/rest/v1/tracker_config?id=eq.1`, {
      method: 'PATCH',
      headers: {
        apikey: supabaseAnonKey(),
        authorization: `Bearer ${token}`,
        'content-type': 'application/json',
        prefer: 'return=minimal',
      },
      body: JSON.stringify(body),
      signal: ctl.signal,
    });
    return res.ok;
  } catch {
    return false;                        // offline, DNS, timeout
  } finally {
    clearTimeout(timer);
  }
}

/**
 * The real runs on a track, or null when offline.
 *
 * This is not a page of a board: it is every real run on the track, for the game
 * to merge into its own ghost field. The field supplies the depth, so there is
 * nothing to paginate here.
 */
export async function fetchBoard(track) {
  const ctl = new AbortController();
  const timer = setTimeout(() => ctl.abort(), TIMEOUT);
  try {
    const token = await authToken();
    const res = await fetch(`${endpoint('board')}?track=${track}`, {
      headers: {
        apikey: supabaseAnonKey(),
        ...(token ? { authorization: `Bearer ${token}` } : {}),
      },
      signal: ctl.signal,
    });
    if (!res.ok) return null;
    const body = await res.json();
    return Array.isArray(body?.rows) ? body.rows : null;
  } catch {
    return null;
  } finally {
    clearTimeout(timer);
  }
}
