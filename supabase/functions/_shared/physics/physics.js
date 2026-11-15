// The physics, vendored for the Edge Functions.
//
// The verifier has to replay a submitted run to know its real time, and the only
// way to be sure it agrees with the browser is to run the same code. The modules
// beside this file are copied verbatim from js/ by tools/sync-physics.mjs, which
// also fails a CI check if the copies drift.
//
// Do not edit the copies by hand. Edit js/ and re-run the sync.
export { CFG } from './config.js';
export { Track } from './track.js';
export { Car } from './car.js';
export { trackOpts, TRACK_COUNT } from './tracks.js';
export { mulberry32, angDiff, clamp } from './util.js';
export { replayRun, FIXED_DT, TICKS_PER_SECOND, MAX_STEPS } from './verify.js';
