// Headless tests for the game's physics and the server's run verifier.
//
// The Godot build is the game, but the physics lives on in JavaScript for one
// job: the Supabase Edge Function replays every uploaded run through it to find
// out what the run was worth. The client sends button steps and never a time, so
// this is the code that decides the leaderboard. `tools/sync-physics.mjs` vendors
// these modules into the function, and `godot/tools/parity.gd` checks the Godot
// port against the numbers they produce.
//
// Three things together mean "the game works": the road is geometrically valid,
// a clean line survives, and every lazy policy dies. The last one is the point of
// the whole exercise - an earlier build let you beat a lap by mashing, and these
// tests are here so that cannot come back.
import { Track } from '../physics/track.js';
import { Car } from '../physics/car.js';
import { CFG } from '../physics/config.js';
import { TRACK_COUNT, PLAYABLE_TRACKS, isPlayableTrack, trackDef, trackOpts } from '../physics/tracks.js';
import { replayRun, FIXED_DT } from '../supabase/functions/_shared/physics/verify.js';

const DT = 1 / 60;
const seeds = [1, 2, 3, 7, 11, 42, 99, 123, 777, 2024];
const RUN = 120;   // corners a good run should manage

let pass = 0, fail = 0;
const ok = (cond, msg) => { if (cond) pass++; else { fail++; console.log('  FAIL:', msg); } };
const median = (a) => a.slice().sort((x, y) => x - y)[Math.floor(a.length / 2)];

function run(seed, policy, maxC = RUN) {
  const t = new Track(seed);
  const c = new Car();
  c.reset(t);
  let i = 0;
  while (c.alive && c.grabbed < maxC && i++ < 600000) c.step(DT, policy(c, i));
  return c;
}
const timing = (deg) => (c) => (c.attached
  ? c.remaining > (deg * Math.PI) / 180
  : Math.hypot(c.fillet.c.x - c.x, c.fillet.c.y - c.y) <= CFG.grabRange);

// A replay is just the button steps; the game re-simulates it. Kept here because
// the physics tests round-trip one, and the format is one bit per step.
const encodeSteps = (steps) => steps.map((h) => (h ? '1' : '0')).join('');
const decodeSteps = (str) => Array.from(String(str), (c) => c === '1');
const makeReplay = (track, steps, time) => ({ track, time, steps: encodeSteps(steps) });
console.log('the road is geometrically valid');
for (const seed of seeds) {
  const t = new Track(seed);
  let badJoin = 0;
  for (let i = 0; i + 1 < t.feats.length; i++) {
    const a = t.feats[i], b = t.feats[i + 1];
    const end = a.type === 'line' ? a.b : { x: a.c.x + Math.cos(a.a2) * a.r, y: a.c.y + Math.sin(a.a2) * a.r };
    const st = b.type === 'line' ? b.a : { x: b.c.x + Math.cos(b.a1) * b.r, y: b.c.y + Math.sin(b.a1) * b.r };
    if (Math.hypot(end.x - st.x, end.y - st.y) > 0.01) badJoin++;
    if (Math.abs(a.s1 - b.s0) > 0.01) badJoin++;
  }
  ok(badJoin === 0, `seed ${seed}: ${badJoin} broken feature joins`);
  let worstArc = 0, worstPole = 0;
  for (const f of t.fillets) {
    for (let k = 0; k <= 8; k++) {
      const ang = f.a1 + (f.a2 - f.a1) * (k / 8);
      const x = f.c.x + Math.cos(ang) * f.r, y = f.c.y + Math.sin(ang) * f.r;
      const idx = t.rs.findIndex((s) => s >= f.s0);
      worstArc = Math.max(worstArc, t.project(x, y, Math.max(0, idx - 2)).d);
    }
    worstPole = Math.max(worstPole, Math.abs(Math.hypot(f.t1.x - f.c.x, f.t1.y - f.c.y) - f.r));
  }
  ok(worstArc < 0.5, `seed ${seed}: corner arc strays ${worstArc.toFixed(2)}px off the road`);
  ok(worstPole < 0.01, `seed ${seed}: pole is ${worstPole.toFixed(3)}px off a radius`);
}

console.log('every turn is one 90-degree corner with one pole');
for (const seed of seeds) {
  const t = new Track(seed);
  let badTurn = 0, badAlt = 0, twoPoles = 0;
  for (let k = 0; k < t.fillets.length; k++) {
    const f = t.fillets[k];
    if (Math.abs(Math.abs(f.phi) - Math.PI / 2) > 1e-6) badTurn++;
    if (k > 0 && t.fillets[k - 1].sign === f.sign) badAlt++;
    if (k > 0) {
      const a = t.fillets[k - 1].c, b = f.c;
      if (Math.hypot(a.x - b.x, a.y - b.y) <= CFG.grabRange) twoPoles++;
    }
  }
  ok(badTurn === 0, `seed ${seed}: ${badTurn} corners are not a quarter turn`);
  ok(badAlt === 0, `seed ${seed}: ${badAlt} corners did not alternate direction`);
  // If two poles were ever within grabRange, a single visual turn could be
  // slung twice - exactly the "two slings on one turn" bug.
  ok(twoPoles === 0, `seed ${seed}: ${twoPoles} pole pairs are within grabRange`);
}

console.log('a clean line survives a long run');
for (const seed of seeds) {
  const c = run(seed, timing(0));
  ok(c.alive && c.grabbed >= RUN, `seed ${seed}: clean line managed only ${c.grabbed} corners`);
}

console.log('holding past the corner ends in the wall');
for (const seed of seeds) {
  const c = run(seed, () => true);
  ok(!c.alive, `seed ${seed}: holding forever never crashed`);
  ok(c.grabbed <= 2, `seed ${seed}: holding forever got ${c.grabbed} corners`);
}

console.log('mashing cannot beat the game');
for (const seed of seeds) {
  for (const [name, fn] of Object.entries({
    mash: (c, i) => i % 2 === 0,
    'mash 3on3off': (c, i) => i % 6 < 3,
    'mash 5on1off': (c, i) => i % 6 < 5,
  })) {
    const c = run(seed, fn, 40);
    ok(c.grabbed <= 3, `seed ${seed}: ${name} got ${c.grabbed} corners`);
  }
}

console.log('a spent pole cannot be re-grabbed');
{
  const c = run(1, timing(0), 20);
  ok(c.grabbed >= 20, 'clean line should re-grab a *different* pole each time');
  const c2 = run(1, () => false, 20);
  ok(c2.grabbed === 0, 'releasing immediately should never grab anything');
}

console.log('release timing is forgiving');
{
  // Releasing up to ~20 degrees early should still complete a run.
  for (const deg of [0, 5, 10, 15]) {
    const got = median(seeds.map((s) => run(s, timing(deg)).grabbed));
    ok(got >= RUN, `releasing ${deg}deg early only managed ${got} corners`);
  }
}

console.log('the car stays on the road when played cleanly');
for (const seed of seeds.slice(0, 4)) {
  const c = run(seed, timing(0));
  ok(c.maxOff < CFG.roadHalfWidth, `seed ${seed}: strayed ${c.maxOff.toFixed(1)}px off`);
}

console.log('the speedrun track is finite and finishable');
for (const seed of seeds) {
  const t = new Track(seed, { corners: CFG.speedrunCorners });
  ok(t.fillets.length === CFG.speedrunCorners, `seed ${seed}: built ${t.fillets.length} corners`);
  ok(Number.isFinite(t.finishS) && t.finishS > 0, `seed ${seed}: no finish line`);
  ok(t.road.length === t.rs.length, `seed ${seed}: road/arc-length arrays disagree`);
  // A clean line must reach the finish, not die on the wall.
  const c = new Car(); c.reset(t);
  let i = 0;
  while (c.alive && i++ < 200000) c.step(DT, timing(0)(c, i));
  ok(c.finished, `seed ${seed}: clean line never reached the finish`);
  ok(c.grabbed === CFG.speedrunCorners, `seed ${seed}: slung ${c.grabbed} of ${CFG.speedrunCorners} corners`);
  // The clock should land in the "about ten seconds" ballpark.
  const secs = c.time;
  ok(secs > 8 && secs < 13, `seed ${seed}: finish time ${secs.toFixed(2)}s is off target`);
}

console.log('a speedrun crash is a crash, not a finish');
for (const seed of seeds.slice(0, 4)) {
  const t = new Track(seed, { corners: CFG.speedrunCorners });
  const c = new Car(); c.reset(t);
  let i = 0;
  while (c.alive && i++ < 200000) c.step(DT, () => true);  // hold forever
  ok(!c.alive && !c.finished, `seed ${seed}: holding forever should crash before the line`);
}

console.log('grabbing wide is allowed and reels back to the road');
{
  // A grab taken off the road radius must not be snapped: the orbit keeps the
  // distance at first, then closes it on the road radius.
  const t = new Track(1, trackOpts(1));
  const c = new Car(); c.reset(t);
  // Fly up to the pole, then latch from as far out as the range allows.
  let i = 0;
  while (c.alive && i++ < 200000) {
    const d = Math.hypot(c.fillet.c.x - c.x, c.fillet.c.y - c.y);
    if (d <= CFG.grabRange) break;
    c.step(DT, false);
  }
  c.step(DT, true);
  ok(c.attached, 'should have latched on');
  const r0 = c.radius;
  ok(Math.abs(r0 - c.fillet.r) > 1, `grab radius ${r0.toFixed(1)} should differ from road ${c.fillet.r}`);
  // Hold and watch the radius move toward the road radius.
  for (let k = 0; k < 30; k++) c.step(DT, true);
  const r1 = c.radius;
  ok(Math.abs(r1 - c.fillet.r) < Math.abs(r0 - c.fillet.r),
    `radius should reel in: ${r0.toFixed(1)} -> ${r1.toFixed(1)} vs road ${c.fillet.r}`);
  // Grabbing from wide costs time, so it cannot be faster than a clean line.
  const wide = new Car(); wide.reset(new Track(1, trackOpts(1)));
  let j = 0;
  while (wide.alive && j++ < 200000) {
    const d = Math.hypot(wide.fillet.c.x - wide.x, wide.fillet.c.y - wide.y);
    wide.step(DT, d <= CFG.grabRange);   // latch as early as possible, from wide
  }
  const clean = new Car(); clean.reset(new Track(1, trackOpts(1)));
  let k2 = 0;
  while (clean.alive && k2++ < 200000) clean.step(DT, timing(0)(clean));
  ok(clean.finished, 'clean line should finish for comparison');
  if (wide.finished) ok(wide.time >= clean.time - 1e-9, 'a wide grab should not beat a clean line');
}

console.log('grabbing does not shove the car outward');
{
  // The grab must latch at the distance you already had, not snap to some clamped
  // radius. A snap shows up as a jump in position on the grab step, and as the car
  // being thrown further off the road than it started.
  const stepLen = CFG.speed * DT;
  for (const n of [1, 4, 21, 23]) {
    const t = new Track(n, trackOpts(n));
    const c = new Car(); c.reset(t);
    let i = 0;
    while (c.alive && i++ < 200000) {
      if (Math.hypot(c.fillet.c.x - c.x, c.fillet.c.y - c.y) <= CFG.grabRange) break;
      c.step(DT, false);
    }
    const dBefore = Math.hypot(c.fillet.c.x - c.x, c.fillet.c.y - c.y);
    const x0 = c.x, y0 = c.y;
    c.step(DT, true);                       // the grab step
    const jump = Math.hypot(c.x - x0, c.y - y0);
    ok(jump <= stepLen * 2, `track ${n}: grab jumped ${jump.toFixed(2)}px (a step is ${stepLen.toFixed(2)}px)`);
    // The whole point: the orbit starts at the distance you already had, so the
    // grab does not snap the car onto some clamped radius.
    // The grab step also reels in by up to one reel step, so allow exactly that
    // and no more: the orbit starts at the distance you had, it never snaps out.
    const reel = CFG.reelSpeed * DT * 1.05;
    ok(c.radius <= dBefore + 1e-6 && c.radius >= dBefore - reel,
      `track ${n}: grab changed the orbit radius ${dBefore.toFixed(1)} -> ${c.radius.toFixed(1)}`);
    // And while held the orbit may only reel in toward the road, never push out.
    const r0 = c.radius;
    let rMax = r0;
    for (let k = 0; k < 40 && c.alive; k++) { c.step(DT, true); rMax = Math.max(rMax, c.radius); }
    ok(rMax <= r0 + 1e-9, `track ${n}: holding pushed the radius out ${r0.toFixed(1)} -> ${rMax.toFixed(1)}`);
    ok(c.radius <= r0 + 1e-9, `track ${n}: radius should only reel in`);
  }
}

console.log('a sloppy release is nudged back to the centre, and costs time');
{
  // Release the last corner a few degrees late: without the centring nudge this
  // runs wide on the closing straight and hits the wall. With it the car curves
  // home. `centreRate` must be strong enough for that and no stronger.
  const releaseLast = (n, lateDeg) => {
    const t = new Track(n, trackOpts(n));
    const last = t.fillets.length - 1;
    const c = new Car(); c.reset(t);
    const late = (lateDeg * Math.PI) / 180;
    let i = 0;
    while (c.alive && i++ < 400000) {
      if (!c.attached) {
        c.step(DT, Math.hypot(c.fillet.c.x - c.x, c.fillet.c.y - c.y) <= CFG.grabRange);
      } else if (c.corner === last) {
        const f = c.fillet;
        c.step(DT, c.sign * (c.orbitAngle - f.a2) < late);
      } else {
        c.step(DT, c.remaining > 0);
      }
      if (c.finished) break;
    }
    return c;
  };
  for (const n of [1, 4, 21, 23, 25]) {
    const late = releaseLast(n, 12);
    ok(late.finished, `track ${n}: a 12-degree late release on the last corner should still finish`);
  }

  // Centring must not be free: a release that cuts the corner has to cost time
  // against the perfect line, or it would be farmed.
  const clean = releaseLast(1, 0);
  const late12 = releaseLast(1, 12);
  ok(clean.finished && late12.finished, 'both the clean and the late run should finish');
  ok(late12.time >= clean.time - 1e-9, `a late release should not beat the clean line (${late12.time.toFixed(3)} vs ${clean.time.toFixed(3)})`);

  // With the nudge off, that same late release must be punished - proof the
  // nudge is what is saving it.
  const saved = CFG.centreRate;
  CFG.centreRate = 0;
  const noNudge = releaseLast(1, 12);
  CFG.centreRate = saved;
  ok(!noNudge.finished, 'without the centring nudge a late release should crash');
}

console.log('the playable tracks are distinct and all finish near ten seconds');
{
  const shapes = new Set();
  for (const n of PLAYABLE_TRACKS) {
    const o = trackOpts(n);
    const t = new Track(n, o);
    const c = new Car(); c.reset(t);
    let i = 0;
    while (c.alive && i++ < 200000) c.step(DT, timing(0)(c));
    ok(c.finished, `track ${n}: clean line never finished`);
    ok(c.grabbed === o.corners, `track ${n}: slung ${c.grabbed} of ${o.corners}`);
    ok(c.time > 9.2 && c.time < 10.8, `track ${n}: time ${c.time.toFixed(3)}s off target`);
    ok(c.maxOff < CFG.roadHalfWidth, `track ${n}: strayed ${c.maxOff.toFixed(1)}px`);
    // A track's identity is the road it lays down, so fingerprint the actual
    // corner radii and straights - that is unique for staircase and op tracks
    // alike, which the old radius:rhythm key was not (op tracks have neither).
    shapes.add(t.feats.map((f) => (f.type === 'arc'
      ? `a${f.r.toFixed(0)}:${(f.a2 - f.a1).toFixed(2)}`
      : `l${f.len.toFixed(0)}`)).join('|'));
  }
  ok(shapes.size === PLAYABLE_TRACKS.length,
    `only ${shapes.size} of ${PLAYABLE_TRACKS.length} tracks have a unique shape`);
  ok(TRACK_COUNT === PLAYABLE_TRACKS.length, 'TRACK_COUNT should match the playable set');

  // Tracks 6-20 were removed, so the playable set is not a contiguous range. A
  // run on a removed track must be refused, and `track <= TRACK_COUNT` would not
  // do that: 6 is under the count but is not a track any more.
  for (const gone of [6, 10, 20]) {
    ok(!isPlayableTrack(gone), `track ${gone} should no longer be playable`);
  }
  ok(isPlayableTrack(21) && isPlayableTrack(5), 'the kept tracks should still be playable');
  ok(!isPlayableTrack(0) && !isPlayableTrack(26) && !isPlayableTrack(1.5),
    'out-of-range and fractional tracks must not be playable');

  // A track keeps its own road: track 21 is the same road it was before the gap,
  // so its shape is not a function of how many tracks happen to exist.
  ok(trackDef(21).id === 21 && trackDef(5).id === 5, 'a track def should carry its own number');
}

console.log('a replay reproduces its run exactly');
{
  for (const n of [1, 3, 21, 25]) {
    const t = new Track(n, trackOpts(n));
    const c = new Car(); c.reset(t);
    const steps = [];
    let i = 0, elapsed = 0;
    while (c.alive && i++ < 200000) {
      const h = timing(0)(c);
      steps.push(h);
      c.step(DT, h);
      if (c.alive) elapsed += DT;
    }
    ok(c.finished, `track ${n}: reference run should finish`);
    const rep = makeReplay(n, steps, elapsed);
    const t2 = new Track(n, trackOpts(n));
    const c2 = new Car(); c2.reset(t2);
    const dec = decodeSteps(rep.steps);
    let j = 0, e2 = 0;
    while (c2.alive && j++ < 200000) {
      const h = dec[j - 1] || false;
      c2.step(DT, h);
      if (c2.alive) e2 += DT;
    }
    ok(c2.finished === c.finished, `track ${n}: replay finish state differs`);
    ok(Math.abs(e2 - elapsed) < 1e-9, `track ${n}: replay time ${e2} != ${elapsed}`);
    ok(Math.abs(c2.x - c.x) < 1e-9 && Math.abs(c2.y - c.y) < 1e-9, `track ${n}: replay position differs`);
  }
}

console.log('the run clock is exactly the simulated time');
{
  // The HUD, the saved best and a ghost's time must all come off the same clock,
  // or a run and a ghost of that run would disagree by a step (8ms) - enough to
  // move the rank. Car.time is that clock, so it must equal steps * DT exactly,
  // including the step that crosses the finish line.
  for (const n of [1, 21, 25]) {
    const t = new Track(n, trackOpts(n));
    const c = new Car(); c.reset(t);
    let steps = 0;
    while (c.alive && steps++ < 200000) c.step(DT, timing(0)(c));
    ok(c.finished, `track ${n}: reference run should finish`);
    ok(Math.abs(c.time - steps * DT) < 1e-9,
      `track ${n}: car clock ${c.time} != ${steps} steps (${steps * DT})`);
  }
}
// --- server: the run verifier ------------------------------------------------
// This is the anti-cheat. A client uploads button steps, never a time, and the
// server replays them to find out what the run was worth. These tests run the
// same `replayRun` the Edge Function imports.
console.log('a submitted run is verified by re-simulation, never trusted');
{
  // A reference run on track 1: drive the clean line and keep the steps.
  const t = new Track(1, trackOpts(1));
  const c = new Car(); c.reset(t);
  const steps = [];
  let i = 0;
  while (c.alive && i++ < 200000) {
    const h = timing(0)(c);
    steps.push(h);
    c.step(FIXED_DT, h);
  }
  ok(c.finished, 'the reference run should finish');
  const encoded = encodeSteps(steps);

  const v = replayRun(1, encoded);
  ok(v.ok, 'a real finishing run should verify');
  ok(v.time === v.ticks / 120, 'the clock is whole ticks, not a float sum');
  ok(Math.abs(v.time - c.time) < 1e-9,
    `the server should reproduce the time, got ${v.time} vs ${c.time}`);
  ok(replayRun(1, encoded).time === v.time, 'verification must be deterministic');

  // The playable set is not a range (6-20 were removed), so a run on a removed
  // track must be refused even though it is under the old 1..25 ceiling.
  for (const gone of [6, 20, 26, 0, 1.5]) {
    ok(!replayRun(gone, encoded).ok, `a run on track ${gone} must be rejected`);
  }
  ok(!replayRun(1, 'nonsense').ok, 'non-binary steps must be rejected');
  ok(!replayRun(1, '').ok, 'an empty step string must be rejected');
  ok(!replayRun(1, '0'.repeat(2000)).ok, 'a run that never finishes must be rejected');
  ok(!replayRun(1, encoded.slice(0, 120)).ok, 'a truncated run must be rejected');

  // Flipping one step changes the run. If it still finishes it is a different
  // time, so a client cannot nudge a time without actually driving the line.
  const flipped = encoded.split('');
  const mid = Math.floor(flipped.length / 2);
  flipped[mid] = flipped[mid] === '1' ? '0' : '1';
  const fv = replayRun(1, flipped.join(''));
  ok(!fv.ok || fv.time !== v.time, 'a tampered step sequence must not reproduce the time');
}
  console.log(`\n${pass} passed, ${fail} failed`);

if (fail) process.exit(1);
