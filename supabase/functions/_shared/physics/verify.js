// Replay a submitted run and report what the physics actually produces.
//
// This is the whole anti-cheat: the client sends button steps, never a time, and
// the server derives the time by replaying those steps through the same physics
// the browser runs. A forged time has nothing to attach to, because the time is
// not an input.
//
// The same module is used by the Edge Function and by tools/test.mjs, so what the
// tests prove is what the function does.

import { Track } from './track.js';
import { Car } from './car.js';
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
