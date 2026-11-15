/**
 * Replays.
 *
 * The physics is a fixed-step simulation: given the same track and the same
 * sequence of "is the button held" values, one step at a time, the car ends up
 * in exactly the same place every time. So a replay is not a recording of
 * positions - it is just the button sequence, and the game re-simulates it.
 *
 * That keeps replays tiny (one bit per step) and perfectly faithful: they can
 * never drift out of sync with the physics, because they *are* the physics.
 *
 * Steps are stored as a string of '0'/'1' characters. A ten-second run at 120Hz
 * is 1200 characters, a couple of kilobytes, which localStorage holds happily.
 */

/** Pack an array of booleans (or 0/1) into the storage string. */
export const encodeSteps = (steps) => steps.map((h) => (h ? '1' : '0')).join('');

/** Unpack the storage string back into an array of booleans. */
export const decodeSteps = (str) => Array.from(String(str), (c) => c === '1');

/** A replay is a track number, the button steps, and the time it produced. */
export const makeReplay = (track, steps, time) => ({
  track,
  time,
  steps: encodeSteps(steps),
});
