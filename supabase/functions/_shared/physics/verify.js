// Replay a submitted run and report what the physics actually produces.
//
// This is the whole anti-cheat: the client sends button steps, never a time, and
// the server derives the time by replaying those steps through the same physics
// the game runs. A forged time has nothing to attach to, because the time is
// not an input.
//
// The same module is used by the Edge Function and by tools/test.mjs, so what the
// tests prove is what the function does.

import { Track } from './track.js';
import { Car } from './car.js';
import { CFG } from './config.js';
import { trackOpts, isPlayableTrack } from './tracks.js';

/** The simulation advances in fixed steps, and the run clock counts them. */
export const FIXED_DT = 1 / 120;
export const TICKS_PER_SECOND = 120;

// A finished run is about 1200 steps. The cap only bounds a malicious payload,
// so it is generous: 60s of held play.
export const MAX_STEPS = 120 * 60;

/**
 * Replay `steps` on `track`.
 *
 * Returns `{ ok, ticks, time, finished, reason }`. `ticks` is how many steps the
 * car survived, which is the same number the run clock is built from, so the
 * stored time is exact rather than rounded.
 */
export function replayRun(track, steps) {
  // The playable set, not a range: tracks 6-20 were removed and there are gaps,
  // so `track <= TRACK_COUNT` would accept a run on a road the game does not show.
  if (!isPlayableTrack(track)) {
    return { ok: false, reason: 'bad track' };
  }
  if (typeof steps !== 'string' || !/^[01]*$/.test(steps)) {
    return { ok: false, reason: 'bad steps' };
  }
  if (steps.length === 0) return { ok: false, reason: 'empty steps' };
  if (steps.length > MAX_STEPS) return { ok: false, reason: 'too many steps' };

  const t = new Track(track, trackOpts(track));
  const car = new Car();
  car.reset(t);

  let i = 0;
  while (i < steps.length) {
    car.step(FIXED_DT, steps[i] === '1');
    i++;
    if (car.finished || !car.alive) break;
  }

  if (!car.finished) {
    return { ok: false, reason: car.alive ? 'never finished' : 'crashed', ticks: i };
  }
  return { ok: true, finished: true, ticks: i, time: i / TICKS_PER_SECOND };
}

/**
 * The endless road is one road, so every endless run is verified on the same
 * seed. The seed only mirrors the staircase (it picks which way the first corner
 * turns), so it changes nothing a player can feel - and pinning it here is what
 * lets the server replay a run without being told which road it was driven on.
 */
export const ENDLESS_SEED = 1;

// Endless is a distance board, so a good run can last minutes. The cap bounds a
// malicious payload, not honest play: 5 minutes at 120 steps/s.
export const MAX_ENDLESS_STEPS = 120 * 300;

/**
 * Replay an endless run and report how far it got.
 *
 * Endless has no finish line - the run ends when the car leaves the road - so a
 * submitted sequence must end in a crash. That is the honest shape of an endless
 * run, and it stops a sequence that simply never dies (a scripted perfect line)
 * from claiming an unbounded distance: the physics has to actually kill it.
 *
 * Returns `{ ok, ticks, metres, reason }`. `ticks` is how many steps the car
 * survived, which is the score the board ranks by; metres is that distance
 * converted for display, and both derive from the same count so they never
 * disagree.
 */
export function replayEndless(steps) {
  if (typeof steps !== 'string' || !/^[01]*$/.test(steps)) {
    return { ok: false, reason: 'bad steps' };
  }
  if (steps.length === 0) return { ok: false, reason: 'empty steps' };
  if (steps.length > MAX_ENDLESS_STEPS) return { ok: false, reason: 'too many steps' };

  const t = new Track(ENDLESS_SEED);
  const car = new Car();
  car.reset(t);

  let i = 0;
  while (i < steps.length) {
    car.step(FIXED_DT, steps[i] === '1');
    i++;
    if (!car.alive) break;
  }

  if (car.alive) {
    return { ok: false, reason: 'never crashed', ticks: i };
  }
  const metres = (i * FIXED_DT * CFG.speed) / CFG.pxPerMetre;
  return { ok: true, ticks: i, metres };
}
