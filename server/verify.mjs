// Verify a submitted run by re-simulating it.
//
// A replay is just the button steps, so the server does not have to trust the
// submitted time: it replays the steps through the same physics the browser runs
// and accepts the run only if the simulation agrees. This module imports the
// game's own modules unchanged, so the server and the client can never drift.
import { Track } from '../js/track.js';
import { Car } from '../js/car.js';
import { trackOpts, isPlayableTrack } from '../js/tracks.js';

const FIXED_DT = 1 / 120;

// A finished run is 1200-ish steps; the cap only exists to bound a malicious
// payload, so it is generous (60s of play).
const MAX_STEPS = 120 * 60;

/**
 * Replay `steps` on `track` and report what the physics actually produces.
 *
 * Returns { ok, time, finished, reason }. `ok` is true only when the car crosses
 * the finish line with the steps given.
 */
export function verifyRun(track, steps) {
  // The playable set, not a numeric range: tracks 6-20 were removed and there are
  // gaps, so `track <= 25` would accept a run on a road the game does not show.
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
    return { ok: false, reason: car.alive ? 'never finished' : 'crashed', time: car.time };
  }
  return { ok: true, time: car.time, finished: true };
}
