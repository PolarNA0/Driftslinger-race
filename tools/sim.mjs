// Play the game headless. This is how the tuning gets decided: if the reference
// line cannot survive the road, nothing else matters.
import { Track } from '../js/track.js';
import { Car } from '../js/car.js';
import { CFG } from '../js/config.js';
import { TAU } from '../js/util.js';

const DT = 1 / 60;

/**
 * Reference line: hold from the moment the corner arc begins until it ends.
 * That is the line the road is built around, so it should never crash.
 */
function reference(seed, maxSeconds = 300) {
  const track = new Track(seed);
  const car = new Car();
  car.reset(track);
  let t = 0, frames = 0;
  while (car.alive && t < maxSeconds && frames++ < 200000) {
    const f = car.fillet;
    let held;
    if (car.attached) {
      // Hold until the orbit reaches the end of the corner arc, then let go.
      held = car.remaining > 0.02;
    } else {
      held = Math.hypot(f.c.x - car.x, f.c.y - car.y) <= CFG.grabRange;
    }
    car.step(DT, held);
    t += DT;
  }
  return { dist: car.distance, alive: car.alive, grabbed: car.grabbed, maxOff: car.maxOff };
}

/** Dumb policies. The road should punish all of them. */
function dumb(seed, policy, maxSeconds = 90) {
  const track = new Track(seed);
  const car = new Car();
  car.reset(track);
  let t = 0, frames = 0;
  while (car.alive && t < maxSeconds && frames++ < 200000) {
    const held = policy === 'always' ? true
      : policy === 'never' ? false
      : frames % 2 === 0;
    car.step(DT, held);
    t += DT;
  }
  return { dist: car.distance, alive: car.alive, grabbed: car.grabbed };
}

const seeds = [1, 2, 3, 7, 11, 42, 99, 123, 777, 2024];
console.log('=== reference line (hold through each corner arc) ===');
let ok = 0;
for (const s of seeds) {
  const r = reference(s);
  // Success is the reference line still being alive after a long run, not a
  // distance figure - the distance just tells us how far it got.
  const good = r.alive && r.grabbed >= 300;
  if (good) ok++;
  console.log(`seed ${String(s).padStart(4)}  ${(r.dist / 50).toFixed(0).padStart(6)}m  grabbed ${String(r.grabbed).padStart(3)}  maxOff ${r.maxOff.toFixed(0).padStart(4)}  ${good ? 'OK' : 'DIED'}`);
}
console.log(`reference survived ${ok}/${seeds.length} seeds`);

console.log('\n=== dumb policies (all should die) ===');
for (const p of ['always', 'never', 'mash']) {
  const rs = seeds.slice(0, 5).map((s) => dumb(s, p));
  const avg = rs.reduce((a, r) => a + r.dist, 0) / rs.length / 50;
  console.log(`${p.padEnd(7)} avg ${avg.toFixed(0).padStart(5)}m  survived ${rs.filter((r) => r.alive).length}/${rs.length}`);
}
