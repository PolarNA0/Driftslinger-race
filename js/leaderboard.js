import { GHOSTS } from './ghostdata.js';
import { ghostName } from './ghostrun.js';
import { mulberry32 } from './util.js';

/**
 * The leaderboard.
 *
 * The head of the board is real: js/ghostdata.js holds the fastest few runs of
 * each track as [time, ghostId, name], baked by tools/bake-ghosts.mjs. Those runs
 * can be *watched* - a ghost's replay is re-simulated from its id on demand.
 *
 * The rest of the field is generated from a formula, and is not watchable. That is
 * a deliberate trade: a watchable ghost needs a real simulation behind it, and
 * simulating a whole 50,000-run field is slow to build and large to ship, while
 * only the world record (and the handful of runs right behind it) is ever actually
 * watched. So the top of the board is honest and the tail is a backdrop to rank
 * against, which is what a leaderboard is for.
 *
 * The player is a real entry slotted in by time, so a good run lands high and a
 * bad one lands low, and both are honest.
 */

export const PER_PAGE = 50;
const FIELD = 50000;                       // real head + generated tail
const REAL = (n) => GHOSTS[n] || [];       // the watchable head
const GEN = (n) => FIELD - REAL(n).length; // generated rows behind the head

// --- generated tail ----------------------------------------------------------
const tailSpan = (n) => {
  const head = REAL(n);
  if (!head.length) return 1;
  const wr = head[0][0];
  return Math.max(1.6, wr * 0.2);          // a long, slow tail under the head
};

/**
 * Time of generated row `i` (0-based) on track `n`.
 *
 * The curve starts where the real head ends and rises monotonically, so the whole
 * board stays sorted by construction and a rank found by binary search is exactly
 * the rank a player sees. The exponent pushes most of the field up near the head,
 * leaving a thin tail - the shape a real board has.
 */
function genTime(n, i) {
  const head = REAL(n);
  const base = head.length ? head[head.length - 1][0] : 10;
  const span = tailSpan(n);
  const frac = (i + 1) / GEN(n);
  return base + span * Math.pow(frac, 1.35);
}

/** A stable display name for generated row `i` of track `n`. */
function genName(n, i) {
  const h = Math.imul(i + 7919, 2654435761) >>> 0;
  const g = Math.imul(n + 13, 0x9e3779b1) >>> 0;
  const rng = mulberry32((h ^ g) >>> 0);
  void rng;
  return ghostName((h ^ g) >>> 0);
}

/** Racers on track `n` no slower than `time` (ties included). */
export function ghostsBeaten(n, time) {
  if (!Number.isFinite(time)) return 0;
  const head = REAL(n);
  if (!head.length || time <= head[head.length - 1][0]) {
    let lo = 0, hi = head.length;
    while (lo < hi) { const m = (lo + hi) >> 1; if (head[m][0] <= time) lo = m + 1; else hi = m; }
    return lo;
  }
  // Past the head, so every real row counts and the tail is a binary search.
  let lo = 0, hi = GEN(n);
  while (lo < hi) {
    const m = (lo + hi) >> 1;
    if (genTime(n, m) <= time) lo = m + 1; else hi = m;
  }
  return head.length + lo;
}

/**
 * The player's 1-based rank among the field, or null.
 *
 * `reals` are the other real runs on the track. They must be counted: the ghost
 * field is only the backdrop, and a real run slots into it by time, so ignoring
 * them ranks a player among the baked ghosts alone and reports a place they do
 * not hold. This matches `boardPage`, which ranks the same merged board, so the
 * number here and the row the board draws never disagree.
 */
export function playerRank(n, time, reals = []) {
  if (!Number.isFinite(time)) return null;
  const ahead = reals.filter((r) => Number.isFinite(r?.time) && r.time < time).length;
  return ghostsBeaten(n, time) + ahead + 1;
}

/** How many racers the board holds. */
export const ghostCount = () => FIELD;

/** The page (1-based) a 1-based rank falls on. */
export const pageForRank = (rank, perPage = PER_PAGE) =>
  Math.max(1, Math.ceil(rank / perPage));

/**
 * The world record: the fastest run on the track.
 *
 * A real submitted run beats a baked ghost, so the board's record follows the
 * players as soon as one goes faster. The record can then be watched from its
 * stored steps rather than a ghost id, which is why it carries `steps`.
 */
export function worldRecord(n, reals = []) {
  const real = reals.slice().sort((a, b) => a.time - b.time);
  if (real.length) {
    const r = real[0];
    return { rank: 1, name: r.name, time: r.time, ghostId: null,
      steps: r.steps ?? null, real: true, watchable: !!r.steps };
  }
  const head = REAL(n);
  if (!head.length) return null;
  return { rank: 1, name: head[0][2], time: head[0][0], ghostId: head[0][1],
    steps: null, real: false, watchable: true };
}

/** The ghost at ghost-index `gi` (0-based, head first then generated). */
function ghostAt(n, gi) {
  const head = REAL(n);
  if (gi < head.length) {
    const [time, id, name] = head[gi];
    return { name, time, ghostId: id, watchable: true };
  }
  const i = gi - head.length;
  return { name: genName(n, i), time: genTime(n, i), ghostId: null, watchable: false };
}

/**
 * One page of the board, with real runs merged into the ghost field.
 *
 * There is one board, not two. The ghost field is the backdrop and a real
 * submitted run is slotted into it by time, so a fast real run lands high and a
 * slow one lands deep - both against the same field, and both ranked honestly.
 * A real row carries `real: true`, which is what the UI turns into the green
 * dot; the ghost rows around it are untouched.
 *
 * `reals` are the real runs on this track as `{ name, time, steps, you }` in any
 * order; they are sorted here. `player` is `{ name, time }` for the signed-in
 * account, used only when the server has not listed them, so their rank and page
 * are still right.
 *
 * This is a merge of two sorted lists, and the merge has to be exact: a real run
 * displaces the ghosts it beats, so a run slower than the whole field lands after
 * all of them rather than partway up it. Ranks are merged positions, so a rank on
 * the board is the rank the player sees. A real run tying a ghost sorts after it.
 */
export function boardPage(n, page, { player = null, reals = [], perPage = PER_PAGE } = {}) {
  // The signed-in player is just another real run, so a local best that has not
  // uploaded yet merges by time like everything else rather than being special-cased.
  const all = reals.slice();
  if (player && !all.some((r) => r.you)) all.push({ ...player, you: true, steps: null });
  all.sort((a, b) => a.time - b.time);

  const total = FIELD + all.length;
  const pages = Math.max(1, Math.ceil(total / perPage));
  const p = Math.min(Math.max(1, Math.floor(page) || 1), pages);

  // Ghosts each real run beats or ties, in real-run order. Non-decreasing because
  // `all` is sorted by time, and left unadjusted: two runs on the same time simply
  // take the two adjacent slots. A real run ties *after* the ghosts it matches, so
  // this is the same count `playerRank` uses and the two never disagree.
  const beaten = all.map((r) => ghostsBeaten(n, r.time));

  // Real run k sits after the ghosts it beat *and* the k real runs already placed.
  const realAt = new Map();
  for (let k = 0; k < all.length; k++) realAt.set(beaten[k] + k, all[k]);

  // Ghost `gi` is pushed down by every real run inserted at or before it. A run
  // slower than the whole field is inserted past it, so it pushes nothing.
  const pushedBy = (gi) => {
    let lo = 0, hi = beaten.length;
    while (lo < hi) { const m = (lo + hi) >> 1; if (beaten[m] <= gi) lo = m + 1; else hi = m; }
    return lo;
  };

  const myIndex = all.findIndex((r) => r.you);
  const playerRankHere = myIndex < 0 ? null : beaten[myIndex] + myIndex + 1;

  const start = (p - 1) * perPage;
  const out = [];
  for (let pos = start; pos < Math.min(start + perPage, total); pos++) {
    const r = realAt.get(pos);
    if (r) {
      out.push({ rank: pos + 1, name: r.name, time: r.time, real: true, you: !!r.you,
        steps: r.steps ?? null, ghostId: null, watchable: !!r.steps });
      continue;
    }
    // Ghost index: gi + pushedBy(gi) == pos, and that is strictly increasing in
    // gi, so it inverts with a binary search.
    let lo = 0, hi = FIELD;
    while (lo < hi) { const m = (lo + hi) >> 1; if (m + pushedBy(m) < pos) lo = m + 1; else hi = m; }
    out.push({ rank: pos + 1, ...ghostAt(n, lo) });
  }
  return { rows: out, page: p, pages, total, playerRank: playerRankHere, realCount: all.length };
}
