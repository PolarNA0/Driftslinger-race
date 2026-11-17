// The physics, vendored for the Edge Functions.
//
// The verifier has to replay a submitted run to know its real time, and the only
// way to be sure it agrees with the game is to run the same code. The modules
// beside this file are copied verbatim from `physics/` by tools/sync-physics.mjs,
// which also fails a CI check if the copies drift.
//
// Do not edit the copies by hand. Edit `physics/` and re-run the sync.
export { CFG } from './config.js';
export { Track } from './track.js';
export { Car } from './car.js';
export { trackOpts, TRACK_COUNT, PLAYABLE_TRACKS, isPlayableTrack } from './tracks.js';
export { mulberry32, angDiff, clamp } from './util.js';
export { replayRun, replayEndless, FIXED_DT, TICKS_PER_SECOND, MAX_STEPS,
         MAX_ENDLESS_STEPS, ENDLESS_SEED } from './verify.js';
