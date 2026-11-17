import { CFG } from './config.js';
import { angDiff, clamp, lerp } from './util.js';

const TAU = Math.PI * 2;

/**
 * The car. One button.
 *
 *   hold  -> latch onto the pole at the next corner and drift around it
 *   let go -> fly straight off along the tangent, then curve gently home
 *
 * The car is always moving at CFG.speed, so turning is the only thing the button
 * does. Distance is speed times time, so the fastest line is simply the one that
 * never wastes a corner.
 *
 * A corner's road is a circular arc of radius driftRadius and the pole is that
 * arc's centre. When you latch on you keep whatever distance you had, so a grab
 * from the inside or the outside is allowed - you are not snapped onto the arc.
 * The orbit radius then eases back toward driftRadius, which is the road itself,
 * so a sloppy grab reels you in and the reel costs you time without costing you
 * the run. That makes three clean outcomes:
 *
 *   hold the right amount -> you follow the road and rejoin the straight
 *   hold too long         -> you keep circling while the road goes straight, so
 *                            you swing wide and hit the wall
 *   let go early          -> you leave on a chord, cut across the corner, and
 *                            run out of road
 *
 * Speed is constant, so a wide grab means a wider arc at the same speed - you
 * cover more ground per second and lose time reeling back to the road. The skill
 * is still mostly in the release timing, which is what the game is about.
 *
 * While flying, the car steers gently back to the centreline (see `centre`). That
 * is the safety net: a sloppy release curves you home instead of dumping you on
 * the wall, but the curved path is longer, so it costs time.
 */
export class Car {
  constructor() { this.reset(null); }

  reset(track) {
    this.track = track;
    this.attached = false;
    this.corner = 0;       // corner we are on, or heading for
    this.orbitAngle = 0;
    this.sign = 1;
    this.radius = CFG.driftRadius;
    // Corners we have spent: a plain pillar is spent the moment it is let go, a
    // reattach pillar only when its arc is ridden to the end (see `release`).
    this.spentCorners = {};
    this.grabbedCorners = {};  // grabs per corner, so one reattach per pillar pays
    this.grabbed = 0;
    this.regrabs = 0;
    this.releasedCorner = -1;  // corner we last let go of
    this.releasedAngle = 0;    // the angle we left it from, for a re-grab's unwrap
    this.reattachAttempt = false;  // armed by bailing out of a live reattach pillar
    this.detourPx = 0;             // how far we have flown since that bail
    this.travelled = 0;            // distance actually covered (the endless score)
    this.speedScale = 1;           // the reattach slingshot, when one is running
    this.effectTimer = 0;          // how long it still lasts
    this.alive = true;
    this.dead = null;
    this.finished = false;
    this.maxOff = 0;
    this.trail = [];
    this.time = 0;
    this.s = 0;
    this.hint = 0;
    this.x = 0; this.y = 0; this.angle = 0;
    if (!track) return;
    const f = track.feats[0];
    this.x = f.a.x + (f.b.x - f.a.x) * 0.15;
    this.y = f.a.y + (f.b.y - f.a.y) * 0.15;
    this.angle = Math.atan2(f.b.y - f.a.y, f.b.x - f.a.x);
    const p = track.project(this.x, this.y, 0);
    this.hint = p.i;
    this.s = p.s;
    this.corner = track.filletAt(this.s);
  }

  get fillet() { return this.track.fillets[this.corner]; }

  /**
   * The car's speed right now: the base speed, and the reattach slingshot if one
   * is running. Kept in one place so drift, fly and the release snap can never
   * disagree about how fast the car is going.
   */
  speed() { return CFG.speed * this.speedScale; }

  step(dt, held) {
    if (!this.alive || this.finished) return this;
    this.time += dt;
    // A reattach boost is brief: count it down so the next step is back to the
    // base speed unless another reattach lands.
    if (this.effectTimer > 0) {
      this.effectTimer = Math.max(0, this.effectTimer - dt);
      if (this.effectTimer === 0) this.speedScale = 1;
    }

    if (held) {
      if (!this.attached) this.tryGrab();
      if (this.attached) this.drift(dt); else this.fly(dt);
    } else {
      if (this.attached) this.release(dt);
      this.fly(dt);
    }

    this.track.extendAhead(this.hint);
    const p = this.track.project(this.x, this.y, this.hint);
    this.hint = p.i;
    this.off = p.d;
    if (this.attached) {
      // Latched, our place on the road is exact, not a nearest-point guess: the
      // orbit angle *is* the angle along this arc, so it gives the road position
      // directly. Projecting the car's xy instead would be ambiguous wherever the
      // road crosses itself - a 270-degree corner passes back over its own entry,
      // and the nearest point can jump to the other branch mid-swing. Deriving s
      // from the arc keeps us on the branch we are actually driving.
      const f = this.fillet;
      this.s = f.s0 + (this.orbitAngle - f.a1) * this.sign * f.r;
    } else {
      this.s = p.s;
    }
    if (p.d > this.maxOff) this.maxOff = p.d;
    // While a reattach is armed and we are off the pole, accumulate how far we have
    // flown. That detour is what the slingshot is scaled by.
    if (this.reattachAttempt && !this.attached) this.detourPx += this.speed() * dt;
    // Crossing the finish line ends the run cleanly, even if the car is
    // mid-swing. Checked before the wall so a win on the line is not a crash.
    if (this.s >= this.track.finishS) {
      this.finished = true;
      this.alive = false;
      return this;
    }
    if (p.d > CFG.roadHalfWidth) { this.alive = false; this.dead = 'wall'; }
    // Only retarget while flying. While attached, `corner` is the arc we are on
    // and must not move, or the release logic reads the wrong arc.
    if (!this.attached) this.corner = this.track.filletAt(this.s);

    this.trail.push(this.x, this.y);
    while (this.trail.length > CFG.trailLen * 2) this.trail.splice(0, 2);
    return this;
  }

  /**
   * Latch onto the pole, if it is in reach.
   *
   * A pole you have already let go of is spent: you cannot grab it again. That
   * single rule is what stops the whole game being beaten by tapping twice per
   * corner. Without it you can re-grab the same pole over and over and ratchet
   * round a corner in a fraction of a second.
   *
   * The grab itself must not move the car. Grabbing wide used to clamp the orbit
   * radius up to `r * 1.6`, and because the car is placed on that circle the very
   * next step it was flung further out than it already was - the "the grapple
   * pushes me to the edge" complaint. The orbit now simply starts at the distance
   * you had, clamped only so it cannot start inside the road, and the reel closes
   * it on the road radius. Nothing teleports; the car only ever creeps inward.
   */
  tryGrab() {
    const f = this.fillet;
    if (this.spentCorners[this.corner]) return false;
    const d = Math.hypot(f.c.x - this.x, f.c.y - this.y);
    // Catching the same pole again after a bail reaches further than a fresh grab:
    // a committed detour takes the car away from the pole, and without the extra
    // reach there would be no room to fly and still come back.
    const isRegrab = this.corner === this.releasedCorner && this.grabbedCorners[this.corner] !== undefined;
    let reach = CFG.grabRange;
    if (isRegrab && f.reattach) reach = CFG.grabRange * CFG.reattachGrabMult;
    if (d > reach) return false;
    this.attached = true;
    this.sign = f.sign;
    this.radius = clamp(d, CFG.minGrabRadius, f.r + CFG.grabRange);
    // Unwrap the orbit angle onto the arc. atan2 returns (-PI, PI], so a raw
    // value cannot represent a corner that turns 180 or 270 degrees - the
    // "distance left to the end of the arc" would wrap and read as already done.
    // Normally we unwrap onto the arc start: a fresh grab is made on the approach,
    // with the car sitting near the entry. A re-grab is different - the car flew
    // off partway round, so unwrap onto the angle it left from. Using the entry
    // there would drop the car back to the start and throw away its progress.
    const raw = Math.atan2(this.y - f.c.y, this.x - f.c.x);
    const ref = this.corner === this.releasedCorner ? this.releasedAngle : f.a1;
    this.orbitAngle = raw + TAU * Math.round((ref - raw) / TAU);
    if (isRegrab) {
      this.regrabs++;
      // Catching a pole we bailed out of: the detour since the bail is the
      // slingshot. A quick release-and-recatch flew almost nowhere, so it earns
      // nothing; a long, committed detour earns the most. A pillar pays at most
      // once - a paying catch spends it - so grinding one pole cannot stack.
      if (this.reattachAttempt && f.reattach) {
        const t = clamp(
          (this.detourPx - CFG.reattachMinDetour) / (CFG.reattachRefDetour - CFG.reattachMinDetour),
          0, 1,
        );
        if (t > 0) {
          this.speedScale = lerp(1, CFG.reattachBoostMax, t);
          this.effectTimer = CFG.reattachEffectTime;
          this.spentCorners[this.corner] = true;
        }
      }
      this.reattachAttempt = false;
    }
    // Count the grabs per pillar: one reattach pays, a second on the same pillar
    // does not, and each pillar is counted on its own.
    this.grabbedCorners[this.corner] = (this.grabbedCorners[this.corner] ?? 0) + 1;
    this.grabbed++;
    return true;
  }

  place() {
    const f = this.fillet;
    this.x = f.c.x + Math.cos(this.orbitAngle) * this.radius;
    this.y = f.c.y + Math.sin(this.orbitAngle) * this.radius;
    this.angle = this.orbitAngle + (this.sign * Math.PI) / 2;
  }

  /**
   * Carve the corner arc. Holding past the end of the corner carries you on
   * round the circle while the road runs straight, so you swing wide into the
   * wall. Releasing early leaves you on a chord that cuts the corner.
   *
   * The orbit radius also eases back to the road radius, so a grab taken from
   * wide (or tight) is pulled onto the road. That is what makes "grapple
   * anywhere" fair: the reel costs time, not the run.
   *
   * The reel has to be paid for. Moving inward is motion, and the orbit advance
   * and the radius change are two components of one velocity, not two motions
   * stacked on top of each other. The old code added them, so reeling inward
   * *injected* tangential speed: the car swept the arc faster than `speed` while
   * its radius closed, and the wider the grab the more free speed it got. That
   * made the widest possible grab - which is what holding the button down before
   * the first pole arrives always produces - the fastest line on the track, the
   * exact opposite of what the mechanic is for. Splitting one step's travel
   * between the tangential and radial directions keeps the total speed at `speed`
   * whatever the radius is doing, so a wide grab is now slower, not faster.
   */
  drift(dt) {
    const f = this.fillet;
    let dR = 0;
    if (this.radius !== f.r) {
      const step = CFG.reelSpeed * dt;
      dR = Math.abs(this.radius - f.r) <= step
        ? f.r - this.radius
        : Math.sign(f.r - this.radius) * step;
    }
    const total = this.speed() * dt;
    const tangential = Math.sqrt(Math.max(0, total * total - dR * dR));
    this.orbitAngle += (this.sign * tangential) / this.radius;
    this.radius += dR;
    this.travelled += total;
    this.place();
  }

  fly(dt) {
    this.centre(dt);
    const d = this.speed() * dt;
    this.x += Math.cos(this.angle) * d;
    this.y += Math.sin(this.angle) * d;
    this.travelled += d;
  }

  /**
   * Steer gently back toward the centreline while flying.
   *
   * Pure pursuit: look at a point `centreLook` up the road and blend the heading
   * toward it. Off the centreline the aim point is off to one side, so the car
   * curves back over; on it, the aim point is dead ahead and nothing changes.
   *
   * This is the safety net for the long straight after the last corner. Without
   * it a release that is a hair late (or a grab taken wide) leaves the car angled
   * slightly off and it meets the wall at the end of the straight. With it the
   * car eases home, and because the recovery is a curve it is a longer path, so
   * it costs time rather than costing the run. `centreDead` keeps a clean line
   * exactly straight, so this cannot be farmed.
   */
  centre(dt) {
    if (!this.track || (this.off ?? 0) < CFG.centreDead) return;
    const p = this.track.pointAt(this.s + CFG.centreLook);
    const want = Math.atan2(p.y - this.y, p.x - this.x);
    const k = Math.min(1, CFG.centreRate * dt);
    this.angle += angDiff(this.angle, want) * k;
  }

  /**
   * Let go of the pole.
   *
   * A release that lands within one frame of the end of the arc is snapped onto
   * the arc's exit point. Without this the car leaves on a heading up to one
   * frame of rotation off the road - about 5 degrees at 60fps - and a long
   * straight then turns that sliver into a wall hit, so a perfectly timed
   * release would crash. Snapping only within a single frame keeps the mechanic
   * honest: let go much later and you really do swing wide into the wall.
   */
  release(dt) {
    const f = this.fillet;
    const step = (this.speed() / this.radius) * dt;
    const carried = this.done;
    if (carried && this.sign * (this.orbitAngle - f.a2) <= step) {
      this.orbitAngle = f.a2;
      this.radius = f.r;
      this.place();
    }
    this.attached = false;
    this.releasedCorner = this.corner;
    this.releasedAngle = this.orbitAngle;
    // A plain pillar is spent the moment you let go. A reattachable pillar is
    // spent only by riding the arc to its end: bail out early and it stays open,
    // so the same pole can be caught again. An ordinary clean line rides every
    // arc out, so its behaviour is unchanged.
    //
    // Bailing out of a live reattach pillar arms the slingshot: the detour from
    // here to the re-catch is what a later catch pays out on. Riding the arc out
    // does not arm it, and spends the pillar as before.
    if (!carried && f.reattach) {
      this.reattachAttempt = true;
      this.detourPx = 0;
    }
    if (carried || !f.reattach) this.spentCorners[this.corner] = true;
  }

  /**
   * How far the orbit still has to turn before this corner is done.
   *
   * Plain subtraction, not `angDiff`: `orbitAngle` is unwrapped onto the arc at
   * grab time (see `tryGrab`) and `a2` is `a1` plus the corner's deflection, so
   * the two live on the same branch. Wrapping here would make a 180- or 270-degree
   * corner read as already finished and the car would let go the moment it latched.
   */
  get remaining() {
    const f = this.fillet;
    return Math.max(0, (f.a2 - this.orbitAngle) * this.sign);
  }

  /** True once the car has carried the corner round to the end of its arc. */
  get done() {
    const f = this.fillet;
    return this.sign * (this.orbitAngle - f.a2) >= 0;
  }

  /**
   * Distance covered, in pixels. This is what was actually travelled, not time x
   * base speed: a reattach slingshot is faster than the base speed, so the two
   * would diverge. It is the endless score.
   */
  distance() { return this.travelled; }
}
