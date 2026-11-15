// How many degrees of early release still survive a long run, per straight
// length. Wider is friendlier. With quarter-turn corners the fillets eat exactly
// 2*driftRadius of each segLen, so segLen must clear 2*r + minStraight.
import { Track } from '../js/track.js';
import { Car } from '../js/car.js';
import { CFG } from '../js/config.js';
const DT = 1 / 120;
const seeds = [1, 2, 3, 7, 11, 42, 99, 123, 777, 2024];
const median = (a) => a.slice().sort((x, y) => x - y)[Math.floor(a.length / 2)];
function run(seed, deg, maxC = 150) {
  const t = new Track(seed);
  const c = new Car();
  c.reset(t);
  let i = 0;
  while (c.alive && c.grabbed < maxC && i++ < 600000) {
    const held = c.attached
      ? c.remaining > (deg * Math.PI) / 180
      : Math.hypot(c.fillet.c.x - c.x, c.fillet.c.y - c.y) <= CFG.grabRange;
    c.step(DT, held);
  }
  return c.grabbed;
}
console.log('segLen | straight px | widest early-release (deg) | window ms');
const floor = 2 * CFG.driftRadius + CFG.minStraight;
for (const seg of [200, 230, 260, 300, 350, 400]) {
  if (seg < floor) continue;
  CFG.segLen = seg;
  let widest = 0;
  for (let d = 0; d <= 40; d += 1) {
    if (median(seeds.map((s) => run(s, d))) >= 150) widest = d; else break;
  }
  const windowMs = (widest * Math.PI / 180) / (CFG.speed / CFG.driftRadius) * 1000;
  const cornerMs = (CFG.driftRadius * (Math.PI / 2) / CFG.speed) * 1000;
  console.log(`${String(seg).padStart(6)} | ${String(seg - 2 * CFG.driftRadius).padStart(11)} | ${String(widest).padStart(3)}deg${' '.repeat(24)} | ${windowMs.toFixed(0)}ms of a ${cornerMs.toFixed(0)}ms corner`);
}
