// Headless tests for the core. Three things together mean "the game works":
// the road is geometrically valid, a clean line survives, and every lazy policy
// dies. The last one is the point of the whole exercise - an earlier build let
// you beat a lap by mashing, and the tests are here so that cannot come back.
import { Track } from '../js/track.js';
import { Car } from '../js/car.js';
import { CFG } from '../js/config.js';
import { TRACK_COUNT, trackDef, trackOpts } from '../js/tracks.js';
import {
  boardPage, pageForRank, playerRank, worldRecord, ghostCount, PER_PAGE,
} from '../js/leaderboard.js';
import { simulateGhost, ghostPolicy } from '../js/ghostrun.js';
import { makeReplay, decodeSteps } from '../js/replay.js';
import { hexToRgb, rgbToHex, MIN_ZOOM, MAX_ZOOM } from '../js/render.js';
import { isAdminCode, clampZoom, validWebhook, loadSettings } from '../js/settings.js';

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
  for (const n of [1, 4, 9, 15]) {
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
  for (const n of [1, 4, 9, 15, 20]) {
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

console.log('the twenty-five tracks are distinct and all finish near ten seconds');
{
  const shapes = new Set();
  for (let n = 1; n <= TRACK_COUNT; n++) {
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
  ok(shapes.size === TRACK_COUNT, `only ${shapes.size} of ${TRACK_COUNT} tracks have a unique shape`);
  // trackDef must wrap, so track 26 is track 1 again.
  ok(trackDef(TRACK_COUNT + 1).radius === trackDef(1).radius, 'trackDef should wrap around');
}

console.log('a replay reproduces its run exactly');
{
  for (const n of [1, 7, 13, 20]) {
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
  for (const n of [1, 9, 20]) {
    const t = new Track(n, trackOpts(n));
    const c = new Car(); c.reset(t);
    let steps = 0;
    while (c.alive && steps++ < 200000) c.step(DT, timing(0)(c));
    ok(c.finished, `track ${n}: reference run should finish`);
    ok(Math.abs(c.time - steps * DT) < 1e-9,
      `track ${n}: car clock ${c.time} != ${steps} steps (${steps * DT})`);
  }
}

console.log('the watchable head of the board is real runs');
{
  ok(ghostCount(1) > 1000, `the board should be deep, got ${ghostCount(1)}`);
  // The head is baked from real simulations: each of the top rows must carry a
  // ghost id whose re-simulation reproduces the time on the board exactly. Those
  // are the rows that can be watched, so they are the rows that must be honest.
  for (const n of [1, 9, 20]) {
    const rows = boardPage(n, 1, { perPage: PER_PAGE }).rows;
    const watchable = rows.filter((r) => r.watchable);
    ok(watchable.length >= 5, `track ${n}: expected a watchable head, got ${watchable.length}`);
    for (const r of watchable) {
      const run = simulateGhost(n, r.ghostId);
      ok(run && Math.abs(run.time - r.time) < 5e-4,
        `track ${n} rank ${r.rank}: ghost ${r.ghostId} claimed ${r.time}, simulates to ${run && run.time}`);
    }
    // The head must be sorted, and the generated tail must not claim to be watchable.
    for (let i = 1; i < watchable.length; i++) {
      ok(watchable[i].time >= watchable[i - 1].time, `track ${n}: watchable head not sorted`);
    }
    ok(watchable.every((r) => r.ghostId !== null), `track ${n}: watchable row with no ghost id`);
    const gen = boardPage(n, 20, { perPage: PER_PAGE }).rows;
    ok(gen.every((r) => !r.watchable), `track ${n}: generated tail should not be watchable`);
  }
  // The world record is the fastest watchable run, and it is watchable.
  const wr = worldRecord(1);
  ok(wr && wr.watchable && wr.ghostId !== null, 'the world record should be watchable');
  const run = simulateGhost(1, wr.ghostId);
  ok(run && Math.abs(run.time - wr.time) < 5e-4, 'the world record must reproduce its run');
}

console.log('the leaderboard pages and ranks correctly');
{
  for (const n of [1, 9, 20]) {
    const total = ghostCount(n);
    const pages = Math.ceil(total / PER_PAGE);
    // Page 1 is the fastest, ranks are 1..PER_PAGE and ascending.
    const p1 = boardPage(n, 1, { perPage: PER_PAGE });
    ok(p1.rows[0].rank === 1, `track ${n}: first row should be rank 1`);
    for (let i = 1; i < p1.rows.length; i++) {
      ok(p1.rows[i].time >= p1.rows[i - 1].time, `track ${n}: page 1 not sorted`);
    }
    // A deep page works, and page numbers are clamped into range.
    const deep = boardPage(n, 27, { perPage: PER_PAGE });
    ok(deep.page === Math.min(27, pages), `track ${n}: page 27 clamped to ${deep.page}`);
    ok(deep.rows.every((r) => r.rank > (deep.page - 1) * PER_PAGE), `track ${n}: page 27 ranks out of range`);
    const past = boardPage(n, 100000, { perPage: PER_PAGE });
    ok(past.page === pages, `track ${n}: past-the-end page should clamp to ${pages}, got ${past.page}`);
    const zero = boardPage(n, 0, { perPage: PER_PAGE });
    ok(zero.page === 1, `track ${n}: page 0 should clamp to 1`);
  }

  // The player is slotted in by time, and their rank is real.
  const total = ghostCount(1);
  const slowest = boardPage(1, 1, { perPage: PER_PAGE }).rows[0];
  const wr = worldRecord(1);
  ok(wr && wr.rank === 1, 'there should be a world record at rank 1');
  ok(wr.time <= slowest.time, 'the world record should be the fastest time');

  const fast = { name: 'Me', time: wr.time - 0.001 };
  ok(playerRank(1, fast.time) === 1, 'a time under the WR should rank 1');
  const slow = { name: 'Me', time: wr.time + 100 };
  ok(playerRank(1, slow.time) === total + 1, 'a very slow time should rank last');
  const mid = { name: 'Me', time: (wr.time + slowest.time) / 2 };
  const midRank = playerRank(1, mid.time);
  ok(midRank > 1 && midRank < total, `a middling time should rank inside the field, got ${midRank}`);

  // The page the player lands on shows their row, marked, exactly once.
  const page = pageForRank(midRank);
  const shown = boardPage(1, page, { player: mid, perPage: PER_PAGE });
  ok(shown.playerRank === midRank, 'boardPage should report the player rank');
  const mine = shown.rows.filter((r) => r.you);
  ok(mine.length === 1, 'the player should appear exactly once on their page');
  ok(mine[0].rank === midRank, 'the player row should carry their real rank');
  // And the row ordering around the player is still by time.
  for (let i = 1; i < shown.rows.length; i++) {
    ok(shown.rows[i].time >= shown.rows[i - 1].time, 'player page is not sorted by time');
  }
}

// --- server: replay verification and the store --------------------------------
// A submitted run must be checked by re-simulating it, so a forged time cannot
// enter the board. These are the rules the server enforces.
{
  const { verifyRun } = await import('../server/verify.mjs');
  const { Store } = await import('../server/store.mjs');

  const good = simulateGhost(1, 1);
  ok(good, 'ghost 1 on track 1 should finish, or the fixtures are wrong');

  // A genuine run re-simulates to exactly the time the client would claim.
  const v = verifyRun(1, good.replay.steps);
  ok(v.ok, 'a real finishing run should verify');
  ok(Math.abs(v.time - good.time) < 1e-9,
    `the server should reproduce the time exactly, got ${v.time} vs ${good.time}`);

  // Tampering is rejected, or silently corrected by recomputation.
  // Note: the same steps may well finish a different track - the tracks are
  // similar enough. That is not a hole, because the server never trusts a claimed
  // time: it recomputes for whatever track was named, so the recorded time is
  // always honest for that track. What a client cannot do is pick a time.
  const cross = verifyRun(2, good.replay.steps);
  ok(!cross.ok || Math.abs(cross.time - v.time) > 1e-9,
    'a run must not carry its time over to another track unchanged');
  ok(!verifyRun(1, 'nonsense').ok, 'non-binary steps must be rejected');
  ok(!verifyRun(1, '0'.repeat(2000)).ok, 'a run that never finishes must be rejected');
  ok(!verifyRun(1, good.replay.steps.slice(0, 120)).ok, 'a truncated run must be rejected');
  ok(!verifyRun(99, good.replay.steps).ok, 'a track outside 1..25 must be rejected');
  ok(verifyRun(1, good.replay.steps).time === v.time, 'verification must be deterministic');

  // Flipping one step changes the run; if it still finishes it is a different time,
  // so a client cannot nudge a time without driving the line.
  const flipped = good.replay.steps.split('');
  const mid = Math.floor(flipped.length / 2);
  flipped[mid] = flipped[mid] === '1' ? '0' : '1';
  const fv = verifyRun(1, flipped.join(''));
  ok(!fv.ok || Math.abs(fv.time - v.time) > 1e-9,
    'a tampered step sequence must not reproduce the same time');

  // The store ranks by time, keeps one row per client, and pages correctly.
  const s = new Store('/tmp/slingdrift-test-board.json');
  const runA = simulateGhost(1, 1), runB = simulateGhost(1, 2);
  const a = s.add(1, { time: runA.time, name: 'A', steps: runA.replay.steps, clientId: 'a' });
  ok(a.rank === 1, 'the first entry should rank 1');
  const b = s.add(1, { time: runB.time, name: 'B', steps: runB.replay.steps, clientId: 'b' });
  const list = s.list(1);
  ok(list[0].time <= list[1].time, 'the board must be sorted by time');
  ok(b.rank === (runB.time < runA.time ? 1 : 2), 'a new run should be slotted by time');

  // The same player posting a slower time does not get a second row.
  const worse = s.add(1, { time: runA.time + 5, name: 'A', steps: '10'.repeat(50), clientId: 'a' });
  ok(!worse.improved, 'a slower run from the same player must not improve their row');
  ok(s.list(1).filter((e) => e.clientId === 'a').length === 1, 'one row per player per track');

  // The same button sequence is not stored twice, whoever sends it.
  const dupe = s.add(1, { time: runB.time, name: 'Copy', steps: runB.replay.steps, clientId: 'c' });
  ok(!dupe.improved, 'an identical run must not be stored twice');

  const page = s.page(1, 1, 50);
  ok(page.rows.length === 2, `the page should hold both real runs, got ${page.rows.length}`);
  ok(page.rows[0].rank === 1 && page.rows[1].rank === 2, 'ranks should be 1-based and ordered');
  ok(page.rows.every((r) => r.watchable), 'stored runs should be watchable');
  ok(s.rankOf(1, 'a') !== null, 'the store should find a player by client id');
  ok(s.rankOf(1, 'nobody') === null, 'an unknown client id should have no rank');
}


console.log('real runs merge into the ghost field as one board');
{
  const wr = worldRecord(1, []);
  const real = (name, time, steps = '01'.repeat(20)) => ({ name, time, steps });

  // A run under the record takes rank 1, is flagged real, and the ghost that was
  // the record is still there right behind it - the field is not replaced.
  const fast = real('Real', wr.time - 0.05);
  const p = boardPage(1, 1, { reals: [fast] });
  ok(p.rows[0].rank === 1 && p.rows[0].name === 'Real', 'a real run under the WR should top the board');
  ok(p.rows[0].real === true, 'the real row should be flagged real');
  ok(p.rows[0].watchable === true, 'a real run with steps should be watchable');
  ok(p.rows[1].real !== true, 'the ghost field should still be under it');
  ok(p.total === ghostCount(1) + 1, 'the field should grow by one, not shrink to one');

  // The merged board is sorted, whatever order the runs arrive in.
  const mid = real('Mid', wr.time + 0.4);
  const slow = real('Slow', wr.time + 2);
  const many = boardPage(1, 1, { reals: [slow, mid, fast] });
  for (let i = 1; i < many.rows.length; i++) {
    ok(many.rows[i].time >= many.rows[i - 1].time, `merged board not sorted at ${i}`);
  }

  // A run slower than the entire field lands after it, not partway up. This is
  // the bug the old merge had: it placed by ghost count and ignored the tail.
  const turtle = real('Turtle', 9999);
  const all = boardPage(1, 1, { reals: [turtle] });
  const last = boardPage(1, all.pages, { reals: [turtle] });
  const found = last.rows.find((r) => r.real);
  ok(found && found.rank === all.total, `a run past the field should rank last, got ${found && found.rank}`);
  ok(found && found.rank === last.rows[last.rows.length - 1].rank, 'and it should be the final row');

  // Two runs on the same time both appear, with distinct ranks. They tie the same
  // ghost, so they sit adjacent to it rather than on top of each other.
  const a = real('A', wr.time + 1), b = real('B', wr.time + 1);
  const tiePage = pageForRank(playerRank(1, a.time));
  const seenReal = new Map();
  for (let pg = tiePage - 1; pg <= tiePage + 1; pg++) {
    if (pg < 1) continue;
    for (const r of boardPage(1, pg, { reals: [a, b] }).rows) {
      if (r.real) seenReal.set(r.name, r.rank);
    }
  }
  ok(seenReal.has('A') && seenReal.has('B'), `both tied runs should be shown, saw ${[...seenReal.keys()]}`);
  ok(seenReal.get('A') !== seenReal.get('B'), 'tied runs should have distinct ranks');

  // The rank boardPage reports is the rank the player's own row carries, and their
  // row appears on exactly the page that rank falls on.
  const mine = { ...real('Me', wr.time + 0.5), you: true };
  const anyPage = boardPage(1, 1, { reals: [mine] });
  ok(anyPage.playerRank !== null, 'a signed-in player with a time should have a rank');
  const minePage = boardPage(1, pageForRank(anyPage.playerRank), { reals: [mine] });
  const myRow = minePage.rows.find((r) => r.you);
  ok(!!myRow, 'the signed-in player should appear on their own page');
  ok(myRow && myRow.rank === anyPage.playerRank,
    `their row should carry rank ${anyPage.playerRank}, got ${myRow && myRow.rank}`);
  ok(minePage.rows.filter((r) => r.you).length === 1, 'they should appear exactly once');

  // The world record follows the real runs, and a real record is watchable by
  // steps rather than by a ghost id.
  const rw = worldRecord(1, [fast]);
  ok(rw.real === true && rw.name === 'Real', 'the WR should be the real run');
  ok(rw.steps === fast.steps && rw.watchable, 'a real WR should replay from its steps');
  ok(worldRecord(1, []).real === false, 'with no real runs the WR is the baked ghost');
}

console.log('a replay of a real run reproduces its time');
{
  // The board hands the game a real run's steps; replaying them must land on the
  // time shown. This is what "watch" relies on, and what broke when a real row
  // was watched as a baked ghost.
  const run = simulateGhost(1, 746);
  ok(!!run, 'the reference ghost should simulate');
  const fromSteps = new Car();
  fromSteps.reset(new Track(1, trackOpts(1)));
  const steps = decodeSteps(run.replay.steps);
  let i = 0;
  while (fromSteps.alive && i < steps.length) fromSteps.step(1 / 120, steps[i++]);
  ok(fromSteps.finished, 'replaying stored steps should finish');
  ok(Math.abs(fromSteps.time - run.time) < 1e-9,
    `replayed time ${fromSteps.time} should equal ${run.time}`);
}

console.log('settings: the admin code, zoom and webhook checks hold');
{
  // The admin code is compared as a string, so the leading zero is not lost.
  ok(isAdminCode('0404'), 'the admin code should be accepted');
  ok(isAdminCode(' 0404 '), 'surrounding space should be forgiven');
  ok(!isAdminCode('404'), 'a numeric reading of the code must not work');
  ok(!isAdminCode(404), 'nor a number with no leading zero');
  ok(!isAdminCode(''), 'an empty code must not work');
  ok(!isAdminCode('04040'), 'a longer code must not work');

  // Zoom is clamped to what the renderer can actually draw.
  ok(clampZoom(1) === 1, 'zoom 1 is the default and must be unchanged');
  ok(clampZoom(0.1) === MIN_ZOOM, 'zoom below the floor should clamp up');
  ok(clampZoom(9) === MAX_ZOOM, 'zoom above the ceiling should clamp down');
  ok(clampZoom('0.5') === MIN_ZOOM, 'a numeric string should be read as a number');
  ok(clampZoom('nonsense') === 1, 'a non-number should fall back to 1');
  ok(clampZoom(NaN) === 1, 'NaN should fall back to 1');

  // A webhook URL is only a Discord webhook if it is https on discord.com's
  // webhook path. This is what stops a typo pointing the sender at another host.
  const good = 'https://discord.com/api/webhooks/123456789012345678/abcdefghijklmnop';
  ok(validWebhook(good), 'a real-shaped Discord webhook should be accepted');
  ok(validWebhook('https://discord.com/api/v10/webhooks/1/abc'), 'a versioned path should be accepted');
  ok(validWebhook('https://discordapp.com/api/webhooks/1/abc'), 'the legacy host should be accepted');
  ok(!validWebhook('http://discord.com/api/webhooks/1/abc'), 'plain http must be rejected');
  ok(!validWebhook('https://evil.com/api/webhooks/1/abc'), 'another host must be rejected');
  ok(!validWebhook('https://discord.com.evil.com/api/webhooks/1/abc'), 'a lookalike host must be rejected');
  ok(!validWebhook('https://discord.com/api/webhooks/1'), 'a missing token must be rejected');
  ok(!validWebhook('https://discord.com/'), 'the bare host must be rejected');
  ok(!validWebhook('not a url'), 'garbage must be rejected');
  ok(!validWebhook(''), 'empty must be rejected');
}

console.log('settings: colours round-trip, and malformed values are repaired');
{
  // The colour picker deals in hex; the renderer deals in channels. Both ways
  // must agree or the hook is drawn a different colour from the one chosen.
  ok(hexToRgb('#ffffff').join(',') === '255,255,255', 'white should parse');
  ok(hexToRgb('#000000').join(',') === '0,0,0', 'black should parse');
  ok(hexToRgb('38d96b').join(',') === '56,217,107', 'a bare hex should parse');
  ok(hexToRgb('not a colour').join(',') === '255,255,255', 'a bad value should fall back to white');
  ok(hexToRgb('#fff').join(',') === '255,255,255', 'a short hex should fall back to white');
  for (const hex of ['#ffffff', '#000000', '#38d96b', '#123456', '#aabbcc']) {
    ok(rgbToHex(hexToRgb(hex)) === hex, `${hex} should survive a round trip`);
  }

  // A device with nothing saved gets sane defaults rather than undefined.
  const s = loadSettings();
  ok(s.zoom === 1, 'the default zoom should be 1');
  ok(s.rope === '#ffffff', 'the default hook colour should be white');
  ok(s.ropeRgb.join(',') === '255,255,255', 'and it should be handed to the renderer as white');
  ok(s.admin === false, 'nobody is an admin by default');
  ok(s.webhook === '', 'and there is no webhook by default');
}

console.log(`\n${pass} passed, ${fail} failed`);
process.exit(fail ? 1 : 0);