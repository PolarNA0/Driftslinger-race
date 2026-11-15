// Sweep straight length and grab range together and report how forgiving the
// release timing is. Short straights mean a forgiving game, but with quarter-turn
// corners segLen can never go below 2*driftRadius + minStraight or the road folds.
import { Track } from '../js/track.js';
import { Car } from '../js/car.js';
import { CFG } from '../js/config.js';
const DT = 1 / 60;
const seeds = [1, 2, 3, 7, 11, 42, 99, 123, 777, 2024];
const median = (a) => a.slice().sort((x, y) => x - y)[Math.floor(a.length / 2)];
function run(seed, policy, maxC = 150) {
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
const cols = [0, 10, 20, 30, 40];
console.log('seg | grab | ' + cols.map((c) => (c + 'deg').padStart(6)).join('') + ' | ok');
for (const seg of [200, 230, 260, 300, 350]) {
  for (const gr of [80, 95, 110]) {
    CFG.segLen = seg; CFG.grabRange = gr;
    const med = cols.map((c) => median(seeds.map((s) => run(s, timing(c)).grabbed)));
    const win = cols.filter((c, i) => med[i] >= 150).length;
    console.log(`${String(seg).padStart(3)} | ${String(gr).padStart(4)} |${med.map((m) => String(m).padStart(6)).join('')} | ${win}/${cols.length}`);
  }
}
