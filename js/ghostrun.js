import { Track } from './track.js';
import { Car } from './car.js';
import { CFG } from './config.js';
import { trackOpts } from './tracks.js';
import { mulberry32 } from './util.js';
import { makeReplay } from './replay.js';

/**
 * Ghost runs.
 *
 * A ghost on the leaderboard is not a made-up time - it is a real run of the real
 * physics, produced by a simple release policy. That matters because the whole
 * point of a ghost is that you can *watch* it: a replay is just the button
 * sequence, and the game re-simulates it. A synthetic time would have no replay.
 *
 * So a ghost is defined by one integer id. `ghostPolicy(id)` turns that id into a
 * deterministic button policy, and `simulateGhost(n, id)` plays it out. The same
 * id gives the same run forever and on every device, so the leaderboard can be
 * shipped as nothing but a list of (time, id) pairs and still be watchable.
 *
 * The policy is deliberately crude - a fixed grab distance and a fixed release
 * angle, held for every corner - because the variety across ids is what fills the
 * board, and the timing skill the player has is what beats it.
 */

const DEG = Math.PI / 180;

const NAMES = [
  'Vex', 'Nyx_77', 'DriftKing', 'pls_no_wall', 'Kestrel', 'blip', 'Mako',
  'tuesday', 'RustyBolt', '0xGRAV', 'Pico', 'Havoc', 'slinky', 'Moth',
  'Quill', 'zed.', 'Bandit', 'OK_GO', 'Wisp', 'NineLives', 'jolt',
  'Marble', 'Sway', 'Tandem', 'Griffin', 'null_ptr', 'Yolk', 'Snap',
  'Dune', 'Vortex', 'Clover', 'Ash', 'Rumble', 'Fable', 'Krill', 'Onyx',
  'Flick', 'Rook', 'Sable', 'Tonic', 'Umber', 'Vane', 'Wren', 'Xeno',
  'Yara', 'Zephyr', 'Arc', 'Brisk', 'Cinder', 'Dash', 'Echo', 'Flint',
  'Grit', 'Halo', 'Iris', 'Jinx', 'Kite', 'Lumen', 'Mist', 'Nova',
];
const TAGS = ['', '', '', '', '_', '', '', '.', '', '', '_', '', '', '-', ''];

/** A stable display name for ghost `id`. */
export function ghostName(id) {
  const h = Math.imul(id + 1, 2654435761) >>> 0;
  return NAMES[h % NAMES.length] + TAGS[(h >>> 8) % TAGS.length] +
    (mulberry32(h)() < 0.2 ? String(1 + (h % 97)) : '');
}

/** The button policy for ghost `id`, as a function of the car state. */
export function ghostPolicy(id) {
  const rng = mulberry32((Math.imul(id + 1, 0x9e3779b9) ^ 0x85ebca6b) >>> 0);
  // Grab when the pole is this close, and release this many degrees before (-) or
  // after (+) the end of the arc. Both are spread wide so the field covers the
  // whole band of times that still finish - a tight policy would cluster every
  // ghost on the same few hundredths.
  const grab = 30 + rng() * 65;
  const release = -35 + rng() * 57;
  return (car) => {
    if (car.attached) return car.sign * (car.orbitAngle - car.fillet.a2) < release * DEG;
    const f = car.fillet;
    return Math.hypot(f.c.x - car.x, f.c.y - car.y) <= grab;
  };
}

/** Play ghost `id` on track `n`. Returns the finished car, or null if it crashed. */
export function simulateGhost(n, id) {
  const track = new Track(n, trackOpts(n));
  const car = new Car();
  car.reset(track);
  const policy = ghostPolicy(id);
  const steps = [];
  let i = 0;
  const DT = 1 / 120;
  while (car.alive && i++ < 200000) {
    const held = policy(car);
    steps.push(held);
    car.step(DT, held);
  }
  if (!car.finished) return null;
  return { time: car.time, steps, replay: makeReplay(n, steps, car.time) };
}
