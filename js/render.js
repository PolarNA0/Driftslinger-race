import { CFG } from './config.js';

const TAU = Math.PI * 2;
const clamp = (v, a, b) => (v < a ? a : v > b ? b : v);
const rgb = (c) => `rgb(${c[0]},${c[1]},${c[2]})`;
const shade = (c, k) => [c[0] * k, c[1] * k, c[2] * k].map((v) => Math.round(clamp(v, 0, 255)));

/**
 * Top-down orthographic camera.
 *
 * Sling Drift is a flat, overhead game, not a 3D one. The reference frames say
 * so plainly: the road band is the same width at the top of the screen and the
 * bottom (449px of 1242 in one capture, 414px in another), which a perspective
 * camera could never do. So there is no horizon, no fog and no vanishing point -
 * just a rectangle of world drawn straight down, rotated so the car's heading
 * points up the screen.
 */
const ROAD_W_FRAC = 0.358;   // the road band fills this much of the screen width.
                             // Measured off the official App Store screenshots:
                             // 445px of 1242, constant top-to-bottom.
const CAR_ANCHOR = 0.55;     // car sits this far down the screen, so you see ahead

/**
 * One theme per road, the way the real game tints each level. Palettes are read
 * straight off the official App Store screenshots: a saturated flat ground with a
 * dark neutral tarmac on top of it. The road is always DARKER than the ground -
 * getting that the wrong way round makes the ribbon vanish into the background -
 * and the centre line is only a few shades lighter than the road itself, not a
 * painted white stripe.
 */
export const THEMES = [
  { ground: [72, 211, 80],  road: [73, 73, 73],    stripe: [84, 84, 84],    pole: [40, 44, 40] },
  { ground: [17, 58, 86],   road: [200, 200, 200], stripe: [222, 222, 222], pole: [10, 34, 52] },
  { ground: [254, 169, 46], road: [75, 75, 75],    stripe: [92, 92, 92],    pole: [150, 96, 20] },
  { ground: [220, 32, 81],  road: [74, 74, 74],    stripe: [90, 90, 90],    pole: [130, 16, 46] },
  { ground: [89, 196, 255], road: [74, 74, 74],    stripe: [90, 90, 90],    pole: [30, 96, 140] },
  { ground: [77, 16, 35],   road: [203, 203, 203], stripe: [222, 222, 222], pole: [40, 8, 18] },
];

export const themeFor = (seed) => THEMES[(((seed | 0) - 1) % THEMES.length + THEMES.length) % THEMES.length];

const ROPE = [255, 255, 255];
const POLE_NEXT = [255, 255, 255];

/**
 * The car skins. Kept to a handful of flat colours that all read clearly against
 * every road theme - the body must stay brighter than the darkest tarmac and
 * darker than the lightest one, or the car vanishes into the road on some tracks.
 * `dark` is the outline, `glass` the canopy.
 */
export const CAR_COLOURS = [
  { name: 'Sunbeam', body: [255, 209, 102], dark: [196, 150, 54], glass: [30, 38, 56] },
  { name: 'Ember',   body: [238, 92, 66],   dark: [170, 52, 36],  glass: [40, 20, 18] },
  { name: 'Mint',    body: [104, 219, 168], dark: [50, 158, 116], glass: [16, 46, 40] },
  { name: 'Cobalt',  body: [92, 156, 255],  dark: [46, 96, 186],  glass: [16, 28, 54] },
  { name: 'Orchid',  body: [206, 130, 255], dark: [140, 76, 186], glass: [34, 20, 50] },
  { name: 'Frost',   body: [238, 242, 250], dark: [150, 160, 178], glass: [28, 34, 46] },
  { name: 'Ink',     body: [70, 74, 88],    dark: [30, 32, 40],   glass: [120, 190, 255] },
  { name: 'Sunset',  body: [255, 138, 92],  dark: [188, 84, 48],  glass: [46, 24, 20] },
];

export class Camera {
  constructor() {
    this.x = 0; this.y = 0; this.angle = 0;
    this.shake = 0;
    this.lead = 90;          // look this far ahead of the car, in world px
  }

  follow(car, dt, snap = false) {
    const tx = car.x + Math.cos(car.angle) * this.lead;
    const ty = car.y + Math.sin(car.angle) * this.lead;
    if (snap) {
      this.x = tx; this.y = ty; this.angle = car.angle;
      return;
    }
    // The camera lags the car, which is what makes a swing read as a swing: the
    // car leans out ahead of the camera through a corner.
    let d = car.angle - this.angle;
    while (d > Math.PI) d -= TAU;
    while (d < -Math.PI) d += TAU;
    this.angle += d * Math.min(1, 6 * dt);
    this.x += (tx - this.x) * Math.min(1, 12 * dt);
    this.y += (ty - this.y) * Math.min(1, 12 * dt);
  }

  kick(amount) { this.shake = Math.max(this.shake, amount); }
  update(dt) { if (this.shake > 0) this.shake = Math.max(0, this.shake - dt * 60); }
}

export class Renderer {
  constructor(canvas, seed = 1) {
    this.canvas = canvas;
    this.ctx = canvas.getContext('2d');
    this.theme = themeFor(seed);
    this.car = CAR_COLOURS[0];
    this.resize();
  }

  setSeed(seed) { this.theme = themeFor(seed); }

  /** Pick the car skin by index into CAR_COLOURS, wrapping safely. */
  setCar(index) {
    const n = CAR_COLOURS.length;
    this.car = CAR_COLOURS[(((index | 0) % n) + n) % n];
  }

  resize() {
    const dpr = Math.min(2, window.devicePixelRatio || 1);
    const rect = this.canvas.getBoundingClientRect();
    this.w = rect.width || this.canvas.width || 420;
    this.h = rect.height || this.canvas.height || 700;
    this.canvas.width = Math.round(this.w * dpr);
    this.canvas.height = Math.round(this.h * dpr);
    this.dpr = dpr;
    this.anchorY = this.h * CAR_ANCHOR;
    // Derive the zoom from the screen width so the road keeps the same share of
    // the frame on any device, which is what the real game does.
    this.scale = (this.w * ROAD_W_FRAC) / (2 * CFG.roadHalfWidth);
  }

  /**
   * The canvas often has no size yet when the renderer is constructed - the
   * WebView lays the page out after the module runs - so the zoom worked out at
   * construction time is wrong until something forces a resize. Re-check here so
   * the framing is right on the first frame as well as after a real resize.
   */
  syncSize() {
    const rect = this.canvas.getBoundingClientRect();
    if (Math.abs(rect.width - this.w) > 0.5 || Math.abs(rect.height - this.h) > 0.5) this.resize();
  }

  /** World point -> screen. The camera's heading points up the screen. */
  toScreen(cam, wx, wy) {
    const th = -Math.PI / 2 - cam.angle;
    const c = Math.cos(th), s = Math.sin(th);
    const dx = wx - cam.x, dy = wy - cam.y;
    const k = this.scale;
    return {
      x: this.w / 2 + (dx * c - dy * s) * k,
      y: this.anchorY + (dx * s + dy * c) * k,
    };
  }

  draw(car, camera, track, ghost = null) {
    const { ctx } = this;
    this.syncSize();
    ctx.setTransform(this.dpr, 0, 0, this.dpr, 0, 0);
    const k = camera.shake;
    ctx.save();
    if (k) ctx.translate((Math.random() - 0.5) * k, (Math.random() - 0.5) * k);
    ctx.fillStyle = rgb(this.theme.ground);
    ctx.fillRect(-40, -40, this.w + 80, this.h + 80);
    this.drawRoad(track, car, camera);
    this.drawFinish(track, car, camera);
    this.drawPoles(track, car, camera);
    this.drawGhost(ghost, camera);
    this.drawRope(car, camera);
    this.drawCar(car, camera);
    ctx.restore();
  }

  /**
   * The finish line: a checkered bar across the road at track.finishS, drawn in
   * the road's own plane so it stays put as the camera swings. It only exists on
   * a finite track, so endless play is untouched.
   */
  drawFinish(track, car, cam) {
    if (!track.finish) return;
    const { ctx } = this;
    const s = track.finishS;
    // Only bother once it is anywhere near the car.
    if (s - car.s > 900 || car.s - s > 400) return;
    const p = track.pointAt(s);
    const nx = -Math.sin(p.heading), ny = Math.cos(p.heading);
    const hw = CFG.roadHalfWidth;
    const A = this.toScreen(cam, p.x + nx * hw, p.y + ny * hw);
    const B = this.toScreen(cam, p.x - nx * hw, p.y - ny * hw);
    ctx.save();
    ctx.lineCap = 'butt';
    // base bar
    ctx.strokeStyle = '#f4f4f4';
    ctx.lineWidth = 12 * this.scale;
    ctx.beginPath();
    ctx.moveTo(A.x, A.y);
    ctx.lineTo(B.x, B.y);
    ctx.stroke();
    // checker squares along the bar
    const cells = 8;
    ctx.strokeStyle = '#141414';
    ctx.lineWidth = 12 * this.scale;
    for (let i = 0; i < cells; i += 2) {
      const t0 = i / cells, t1 = (i + 1) / cells;
      ctx.beginPath();
      ctx.moveTo(A.x + (B.x - A.x) * t0, A.y + (B.y - A.y) * t0);
      ctx.lineTo(A.x + (B.x - A.x) * t1, A.y + (B.y - A.y) * t1);
      ctx.stroke();
    }
    ctx.restore();
  }

  /** The visible slice of the centreline, plus each sample's screen offset. */
  samples(track, car, cam) {
    const road = track.road;
    const out = [];
    const lo = Math.max(0, car.hint - 120);
    const hi = Math.min(road.length - 1, car.hint + 220);
    // The normal has to be rotated by the same amount as the points, or the band
    // is offset along the world axis instead of the screen one and the road comes
    // out skewed and the wrong width whenever it is not axis-aligned.
    const th = -Math.PI / 2 - cam.angle;
    const c = Math.cos(th), s = Math.sin(th);
    for (let i = lo; i <= hi; i++) {
      const a = road[i];
      const b = road[Math.min(road.length - 1, i + 1)];
      const d = road[Math.max(0, i - 1)];
      let dx = b.x - d.x, dy = b.y - d.y;
      const L = Math.hypot(dx, dy) || 1;
      const nx = -dy / L, ny = dx / L;
      out.push({
        wx: a.x, wy: a.y,
        snx: nx * c - ny * s,
        sny: nx * s + ny * c,
        p: this.toScreen(cam, a.x, a.y),
      });
    }
    return out;
  }

  /** Fill a band of half-width `hw` either side of the centreline. */
  band(ctx, s, hw, fill) {
    if (s.length < 2) return;
    ctx.beginPath();
    for (let i = 0; i < s.length; i++) {
      const q = s[i];
      const x = q.p.x + q.snx * hw * this.scale;
      const y = q.p.y + q.sny * hw * this.scale;
      i ? ctx.lineTo(x, y) : ctx.moveTo(x, y);
    }
    for (let i = s.length - 1; i >= 0; i--) {
      const q = s[i];
      ctx.lineTo(q.p.x - q.snx * hw * this.scale, q.p.y - q.sny * hw * this.scale);
    }
    ctx.closePath();
    ctx.fillStyle = fill;
    ctx.fill();
  }

  drawRoad(track, car, cam) {
    const { ctx } = this;
    const s = this.samples(track, car, cam);
    if (s.length < 2) return;
    const t = this.theme;
    // The real road reads as one dark slab with a faint lighter centre and a
    // barely-there edge, so these are all close in tone rather than painted lines.
    this.band(ctx, s, CFG.roadHalfWidth + 4, rgb(shade(t.road, 0.86)));
    this.band(ctx, s, CFG.roadHalfWidth, rgb(t.road));
    this.band(ctx, s, CFG.roadHalfWidth * 0.42, rgb(t.stripe));
  }

  drawPoles(track, car, cam) {
    const { ctx } = this;
    const lo = Math.max(0, car.corner - 1);
    const hi = Math.min(track.fillets.length - 1, car.corner + 16);
    const items = [];
    for (let k = lo; k <= hi; k++) {
      const f = track.fillets[k];
      const p = this.toScreen(cam, f.c.x, f.c.y);
      if (p.x < -80 || p.x > this.w + 80 || p.y < -80 || p.y > this.h + 80) continue;
      items.push({ k, p });
    }
    items.sort((a, b) => a.p.y - b.p.y);
    for (const it of items) {
      const { p, k } = it;
      const r = 13 * this.scale;
      const isNext = k === car.corner && !car.attached;
      ctx.beginPath();
      ctx.arc(p.x, p.y, r, 0, TAU);
      ctx.fillStyle = isNext ? rgb(POLE_NEXT) : rgb(this.theme.pole);
      ctx.fill();
    }
  }

  drawRope(car, cam) {
    if (!car.attached) return;
    const { ctx } = this;
    const a = this.toScreen(cam, car.x, car.y);
    const b = this.toScreen(cam, car.fillet.c.x, car.fillet.c.y);
    ctx.strokeStyle = rgb(ROPE);
    ctx.lineWidth = 2.5;
    ctx.beginPath();
    ctx.moveTo(a.x, a.y);
    ctx.lineTo(b.x, b.y);
    ctx.stroke();
  }

  drawCar(car, cam) {
    this.drawCarBody(car.x, car.y, car.angle, cam, this.car, 1);
  }

  /** The ghost of another run: the same car, drawn translucent and unlit. */
  drawGhost(ghost, cam) {
    if (!ghost) return;
    this.drawCarBody(ghost.x, ghost.y, ghost.angle, cam, this.car, 0.42);
  }

  drawCarBody(x, y, angle, cam, skin, alpha) {
    const { ctx } = this;
    const p = this.toScreen(cam, x, y);
    const len = 30 * this.scale;
    const wid = 16 * this.scale;
    ctx.save();
    ctx.globalAlpha = alpha;
    ctx.translate(p.x, p.y);
    // The camera has already rotated the world so the car's heading points up
    // the screen, so the car must be rotated by its heading *relative to the
    // camera* - not by its absolute world angle. Rotating by the world angle
    // leaves the car slanting whenever it is not pointing along baseHeading.
    ctx.rotate(angle - cam.angle);
    ctx.beginPath();
    ctx.moveTo(-wid * 0.5, len * 0.5);
    ctx.quadraticCurveTo(-wid * 0.62, 0, -wid * 0.5, -len * 0.42);
    ctx.quadraticCurveTo(0, -len * 0.62, wid * 0.5, -len * 0.42);
    ctx.quadraticCurveTo(wid * 0.62, 0, wid * 0.5, len * 0.5);
    ctx.quadraticCurveTo(0, len * 0.66, -wid * 0.5, len * 0.5);
    ctx.closePath();
    ctx.fillStyle = rgb(skin.body);
    ctx.fill();
    ctx.strokeStyle = rgb(skin.dark);
    ctx.lineWidth = 2;
    ctx.stroke();
    ctx.beginPath();
    ctx.ellipse(0, -len * 0.10, wid * 0.30, len * 0.17, 0, 0, TAU);
    ctx.fillStyle = rgb(skin.glass);
    ctx.fill();
    ctx.restore();
  }
}
