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

/** The player's 1-based rank among the field, or null. */
export function playerRank(n, time) {
  if (!Number.isFinite(time)) return null;
  return ghostsBeaten(n, time) + 1;
}

/** How many racers the board holds. */
export const ghostCount = () => FIELD;

/** The page (1-based) a 1-based rank falls on. */
export const pageForRank = (rank, perPage = PER_PAGE) =>
  Math.max(1, Math.ceil(rank / perPage));

/** The world record: the fastest real run, and the way to watch it. */
export function worldRecord(n) {
  const head = REAL(n);
  if (!head.length) return null;
  return { rank: 1, name: head[0][2], time: head[0][0], ghostId: head[0][1], watchable: true };
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
 * One page of the board.
 *
 * `player` is `{ name, time }` when the signed-in account has a time on this
 * track, else null; the player is inserted into the ordering by time, so their
 * rank is real and their row appears on whichever page it belongs to.
 */
export function boardPage(n, page, { player = null, perPage = PER_PAGE } = {}) {
  const total = FIELD + (player ? 1 : 0);
  const pages = Math.max(1, Math.ceil(total / perPage));
  const p = Math.min(Math.max(1, Math.floor(page) || 1), pages);
  const playerPos = player ? ghostsBeaten(n, player.time) : -1;

  const start = (p - 1) * perPage;
  const out = [];
  for (let pos = start; pos < Math.min(start + perPage, total); pos++) {
    if (player && pos === playerPos) {
      out.push({ rank: pos + 1, name: player.name, time: player.time, you: true, ghostId: null, watchable: false });
    } else {
      const gi = player && pos > playerPos ? pos - 1 : pos;
      out.push({ rank: pos + 1, ...ghostAt(n, gi) });
    }
  }
  return { rows: out, page: p, pages, total, playerRank: player ? playerPos + 1 : null };
}
