#!/usr/bin/env node
// Replay a stored board row on the current physics.
//
// The physics is the leaderboard's contract, so a physics change is only
// compatible if the rows already on the board still reproduce. This is the
// command that says whether they do. See PHYSICS.md.
//
//   node tools/replay-row.mjs --track 28 --steps 0011... --ticks 1191
//   node tools/replay-row.mjs --file row.json      # { track, steps, ticks }
//   curl -s '.../board?track=1' | node tools/replay-row.mjs --file -
//
// Exits 1 if the run does not finish, or if --ticks is given and the replay
// produces a different number. Prints the ticks either way.

import { readFileSync } from 'node:fs';
import { replayRun } from '../supabase/functions/_shared/physics/verify.js';

function usage() {
  console.error('usage: node tools/replay-row.mjs --track N --steps 0101... [--ticks N]');
  console.error('       node tools/replay-row.mjs --file row.json|--');
  process.exit(2);
}

const args = process.argv.slice(2);
const opt = {};
for (let i = 0; i < args.length; i++) {
  const key = args[i];
  if (!key.startsWith('--')) usage();
  const value = args[i + 1];
  if (value === undefined) usage();
  opt[key.slice(2)] = value;
  i++;
}

let row = {};
if (opt.file) {
  const text = opt.file === '-' ? readFileSync(0, 'utf8') : readFileSync(opt.file, 'utf8');
  row = JSON.parse(text);
}

const track = Number(opt.track ?? row.track);
const steps = opt.steps ?? row.steps;
const expected = opt.ticks !== undefined ? Number(opt.ticks) : row.ticks;

if (!Number.isInteger(track) || typeof steps !== 'string') usage();

const result = replayRun(track, steps);
if (!result.ok) {
  console.log(`track ${track}: ${result.reason} after ${result.ticks ?? 0} ticks`);
  process.exit(1);
}

const expectedText = expected === undefined ? '' : ` (stored ${expected})`;
console.log(`track ${track}: ${result.ticks} ticks = ${result.time.toFixed(3)}s${expectedText}`);

if (expected !== undefined && Number(expected) !== result.ticks) {
  console.log('DIFFERENT: this run does not reproduce on the current physics');
  process.exit(1);
}
console.log('reproduces');
