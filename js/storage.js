import { currentAccount } from './account.js';

/**
 * Per-account storage.
 *
 * Records, best times and replays are namespaced by the signed-in account, so two
 * people on one device do not overwrite each other. Signed out, everything falls
 * back to a single "guest" bucket, so the game works fine with no account at all.
 * Preferences (the car skin) are deliberately global - they are about the device,
 * not the person.
 *
 * Everything lives in localStorage: the game is offline and needs no server.
 */
const account = () => currentAccount() || 'guest';
const key = (name) => `slingdrift.${account()}.${name}`;

function read(keyName, fallback) {
  try {
    return JSON.parse(localStorage.getItem(keyName)) || fallback;
  } catch {
    return fallback;
  }
}
function write(keyName, value) {
  try { localStorage.setItem(keyName, JSON.stringify(value)); } catch { /* private mode or full */ }
}

// --- endless: best distance per seed -----------------------------------------
export function getRecord(seed) {
  const all = read(key('records.v1'), {});
  return all[seed] || { dist: 0, corners: 0 };
}

/** Save a run if it beat the record. Returns the previous best. */
export function saveRecord(seed, dist, corners) {
  const all = read(key('records.v1'), {});
  const prev = all[seed] || { dist: 0, corners: 0 };
  if (dist > prev.dist) {
    all[seed] = { dist, corners };
    write(key('records.v1'), all);
  }
  return prev;
}

export function bestDistance() {
  const all = read(key('records.v1'), {});
  return Object.values(all).reduce((m, r) => Math.max(m, r.dist || 0), 0);
}

// --- speedrun: best time per seed, in seconds. Lower is better ---------------
export function getBestTime(seed) {
  const all = read(key('times.v1'), {});
  const t = all[seed];
  return Number.isFinite(t) ? t : null;
}

/** Save a finish if it beat the best. Returns the previous best (or null). */
export function saveBestTime(seed, time) {
  const all = read(key('times.v1'), {});
  const prev = Number.isFinite(all[seed]) ? all[seed] : null;
  if (prev === null || time < prev) {
    all[seed] = time;
    write(key('times.v1'), all);
  }
  return prev;
}

/**
 * Fold the server's copy of a player's times into the local records.
 *
 * The server holds the player's real bests; localStorage holds whatever this
 * device happens to have seen. They can disagree in both directions - a fresh
 * install has nothing, and an offline run may not have uploaded yet - so this
 * takes the faster of the two per track rather than overwriting either way.
 *
 * Replays are filled in only where the device has none, so a locally watched
 * ghost is never replaced by one fetched over the wire.
 *
 * Returns how many tracks changed, so the caller can skip a repaint when nothing
 * moved.
 */
export function mergeServerTimes(runs) {
  if (!Array.isArray(runs) || !runs.length) return 0;
  const times = read(key('times.v1'), {});
  const replays = read(key('replays.v1'), {});
  let changed = 0;

  for (const run of runs) {
    if (!Number.isFinite(run?.time) || !Number.isFinite(run?.track)) continue;
    const prev = times[run.track];
    if (!Number.isFinite(prev) || run.time < prev) {
      times[run.track] = run.time;
      changed++;
    }
    if (run.steps && !replays[run.track]) {
      replays[run.track] = { track: run.track, time: run.time, steps: run.steps };
    }
  }

  if (changed) write(key('times.v1'), times);
  write(key('replays.v1'), replays);
  return changed;
}

// --- replays: the button steps of the best run per track ---------------------
export function getReplay(seed) {
  const r = read(key('replays.v1'), {})[seed];
  return r && typeof r.steps === 'string' ? r : null;
}

export function saveReplay(seed, replay) {
  const all = read(key('replays.v1'), {});
  all[seed] = replay;
  write(key('replays.v1'), all);
}

// --- run history: every finished run, newest first ---------------------------
const MAX_HISTORY = 50;

/** A signed-in player's finished runs on a track, newest first. */
export function getRuns(seed) {
  const all = read(key('runs.v1'), {});
  return Array.isArray(all[seed]) ? all[seed] : [];
}

/** Every finished run across all tracks, newest first. */
export function allRuns() {
  const all = read(key('runs.v1'), {});
  const out = [];
  for (const [seed, list] of Object.entries(all)) {
    if (Array.isArray(list)) for (const r of list) out.push({ ...r, seed: Number(seed) });
  }
  return out.sort((a, b) => b.at - a.at);
}

/**
 * Record a finished run. Returns the run's rank within this track's history
 * (1 = personal best) so the UI can flag a PB.
 */
export function addRun(seed, time, at = Date.now()) {
  const all = read(key('runs.v1'), {});
  const list = Array.isArray(all[seed]) ? all[seed] : [];
  list.push({ time, at });
  list.sort((a, b) => a.time - b.time);          // fastest first
  all[seed] = list.slice(0, MAX_HISTORY);
  write(key('runs.v1'), all);
  return list.findIndex((r) => r.at === at && r.time === time) + 1;
}

// --- preferences: global, not per account ------------------------------------
const PREF_KEY = 'slingdrift.prefs.v1';

export function getPref(name, fallback = null) {
  const v = read(PREF_KEY, {})[name];
  return v === undefined ? fallback : v;
}

export function setPref(name, value) {
  const all = read(PREF_KEY, {});
  all[name] = value;
  write(PREF_KEY, all);
}
