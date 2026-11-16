import { CFG } from './config.js';

/**
 * The time-attack tracks.
 *
 * Each track is a fixed road: its straight-length rhythm (the "winds"), its
 * corner radius (how wide the wiggles are), how many corners it has and how long
 * it is. Every one is calibrated to land near ten seconds, so the leaderboard
 * compares like with like, but the shape you drive is different on each.
 *
 * Everything is derived from the track number, so a track is the same road on
 * every device, forever. A leaderboard and a replay are both meaningless
 * otherwise.
 *
 * Straights are capped (see MAX_VISIBLE_STRAIGHT). A straight much longer than
 * the corner radius is not just dull - it is where a run falls apart, because
 * the car flies the whole length and any small error in the release angle
 * accumulates into a wall hit by the far end. Capping keeps every straight
 * short enough that the release you make is the line you get.
 */

// Relative straight lengths, cycled. These give a track its rhythm: a metronome
// of equal gaps reads very differently from two-longs-then-short.
const RHYTHMS = [
  [1, 1, 1, 1],           // metronome
  [1, 2, 1, 2],           // breathing
  [2, 1, 1, 2, 1, 1],     // long, short, short
  [1, 1, 2, 2],           // pairs
  [2, 1, 1, 1, 2, 1],     // long opener then tight
  [1, 2, 2, 1, 1, 2],     // lurching
];

const ARC = (CFG.turn / 2) * 2;       // a quarter turn subtends r * PI/2
const START_FRAC = CFG.speedrunStartFrac;
const MAX_VISIBLE_STRAIGHT = 150;     // px of straight between two corners, cap

/** The shape knobs for track number `n`. */
function shape(n) {
  const radius = 50 + (n % 5) * 4;                 // 50, 54, 58, 62, 66
  const corners = 10;
  const leadIn = 520 + (n % 4) * 60;               // 520 .. 700
  const rhythm = RHYTHMS[(n - 1) % RHYTHMS.length];
  const targetTime = 9.6 + ((n * 7) % 9) * 0.1;    // 9.6 .. 10.4 s
  return { radius, corners, leadIn, rhythm, targetTime };
}

/** Build the definition (geometry, not the road itself) for track number `n`. */
function def(n) {
  const { radius, corners, leadIn, rhythm, targetTime } = shape(n);

  let sum = 0;
  for (let i = 0; i < corners; i++) sum += rhythm[i % rhythm.length];

  const minSeg = 2 * radius + CFG.minStraight;
  const maxSeg = 2 * radius + MAX_VISIBLE_STRAIGHT;
  // Time is (finishS - start) / speed and a clean line drives the road exactly,
  // so the road length that hits the target is distance = speed * time.
  const targetLen = targetTime * CFG.speed + START_FRAC * leadIn;
  // Road length = (leadIn - r) + sum(seg - 2r) + corners*arc + finishLen.
  // Solve for the unit straight, then clamp it into [minSeg, maxSeg]. Any length
  // the clamp gives back is absorbed by the closing straight in Track.buildFinish,
  // so the track still lands on its target time.
  const finishLen = 460;
  const segSum = targetLen - (leadIn - radius) - corners * ARC * radius - finishLen
                 + 2 * radius * corners;
  const base = Math.min(Math.max(segSum / sum, minSeg), maxSeg);

  const segLens = [];
  for (let i = 0; i < corners; i++) {
    const v = base * rhythm[i % rhythm.length];
    segLens.push(Math.min(Math.max(v, minSeg), maxSeg));
  }

  return {
    id: n,
    seed: n,
    radius,
    corners,
    leadIn,
    finishLen,
    segLens,
    targetTime,
    rhythm: rhythm.join(''),
  };
}

/**
 * The tracks the game ships, in menu order.
 *
 * Tracks 6-20 were removed: they were the same staircase with the radius and
 * rhythm cycled, so they added menu length without adding a shape. The remaining
 * numbers are kept exactly as they were - 21-25 are still the advanced tracks -
 * so a leaderboard entry or a replay for track 1 is still track 1. That leaves
 * gaps, which is deliberate: replacement tracks will be dropped into the empty
 * numbers later, and they will be new roads rather than another cycling of these.
 *
 * A track number outside this list is not playable, and the verifier refuses it,
 * so no run can be posted to a road the game does not show.
 */
export const PLAYABLE_TRACKS = [1, 2, 3, 4, 5, 21, 22, 23, 24, 25];

/** How many tracks ship. Prefer this to a literal in loops and menus. */
export const TRACK_COUNT = PLAYABLE_TRACKS.length;

/** Is `n` a track the game plays? Guards the verifier and the board alike. */
export const isPlayableTrack = (n) => Number.isInteger(n) && PLAYABLE_TRACKS.includes(n);

/**
 * The advanced tracks (21-25).
 *
 * These are not staircases. Each is built from an explicit op list, which lets a
 * corner turn more than a quarter: a hairpin is a 180, and a loop is a single
 * 270-degree arc round one pivot.
 *
 * A single arc of more than a half turn folds the road back over itself: its
 * exit straight recrosses its entry. That is exactly the point - it is where the
 * interesting lines live - and it drives cleanly because the car tracks its own
 * branch while latched (see Car.step) and Track.project keeps the near branch at
 * the crossing (see the branch tie-break there).
 */
const ADVANCED = {
  // 21: a 180 hairpin dropped into an otherwise ordinary staircase.
  21: {
    leadIn: 620,
    targetTime: 10.3,
    defs: [
      { deg: 90 }, { deg: -90 }, { deg: 180 }, { deg: -90 },
      { deg: 90 }, { deg: -90 }, { deg: 90 },
    ],
  },
  // 22: a switchback - two opposite hairpins with a straight between them.
  22: {
    leadIn: 620,
    targetTime: 10.3,
    defs: [
      { deg: 90 }, { deg: 180 }, { deg: -90 }, { deg: 90 },
      { deg: -180 }, { deg: 90 },
    ],
  },
  // 23: a full 270-degree loop round a single pivot.
  23: {
    leadIn: 620,
    targetTime: 10.3,
    defs: [
      { deg: 270 }, { deg: -90 }, { deg: 90 }, { deg: -90 },
    ],
  },
  // 24: two loops, one each way, each a single pivot.
  24: {
    leadIn: 620,
    targetTime: 10.3,
    defs: [
      { deg: 270 }, { deg: -270 }, { deg: 90 },
    ],
  },
  // 25: hairpin, loop, then home - the three shapes in one run.
  25: {
    leadIn: 620,
    targetTime: 10.3,
    defs: [
      { deg: 180 }, { deg: 270 }, { deg: -90 }, { deg: 90 },
    ],
  },
};

/** Turn an advanced track's defs into an op list, scaling the straights to time. */
function advancedOps(spec, radius) {
  const defs = spec.defs;
  const arcLen = defs.reduce((a, d) => a + (d.r ?? radius) * Math.abs(d.deg) * (Math.PI / 180), 0);
  const fixedGaps = defs.reduce((a, d) => a + (d.gap ?? 0), 0);
  const weightSum = defs.reduce((a, d) => a + (d.scale ?? 1), 0);
  const want = spec.targetTime * CFG.speed + START_FRAC * spec.leadIn;
  const fixed = spec.leadIn + arcLen + fixedGaps + 460;
  const per = weightSum > 0 ? (want - fixed) / weightSum : 0;
  const ops = [];
  for (const d of defs) {
    const g = (d.gap ?? 0) + (d.scale ?? 1) * per;
    if (g > 1) ops.push({ t: 'L', len: g });
    ops.push({ t: 'A', deg: d.deg, r: d.r ?? radius });
  }
  return ops;
}

/**
 * The definition (geometry, not the road itself) for track number `n`.
 *
 * `n` is used directly rather than wrapped: a track's road is a function of its
 * own number, so track 21 keeps the shape it always had even now that 6-20 are
 * gone. Wrapping would silently renumber every road past the gap.
 */
export const trackDef = (n) => def(n);

/** The options object a Track wants for track number `n`. */
export function trackOpts(n) {
  const adv = ADVANCED[n];
  if (adv) {
    const radius = 62;
    return {
      corners: adv.defs.length,
      radius,
      leadIn: adv.leadIn,
      finishLen: 460,
      targetTime: adv.targetTime,
      ops: advancedOps(adv, radius),
    };
  }
  const d = def(n);
  return {
    corners: d.corners,
    radius: d.radius,
    leadIn: d.leadIn,
    finishLen: d.finishLen,
    segLens: d.segLens,
    targetTime: d.targetTime,
  };
}
