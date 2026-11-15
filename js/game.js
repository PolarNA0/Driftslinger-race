import { CFG } from './config.js';
import { Track } from './track.js';
import { Car } from './car.js';
import { Camera, Renderer } from './render.js';
import { trackOpts } from './tracks.js';
import {
  getRecord, saveRecord, getBestTime, saveBestTime,
  getReplay, saveReplay, addRun,
} from './storage.js';
import { makeReplay, decodeSteps } from './replay.js';
import { simulateGhost } from './ghostrun.js';

const FIXED_DT = 1 / 120;
const MAX_STEPS = 8;

/**
 * The game loop and input.
 *
 * One button: hold to hook the next pole and swing, let go to fly straight.
 * Leaving the road ends the run.
 *
 * Three modes:
 *   endless  - an infinite road, scored by distance. The original feel.
 *   speedrun - one of the twenty-five fixed tracks, scored by time.
 *   replay   - a saved speedrun re-simulated from its button steps, driven by
 *              the game rather than the player. Read-only.
 *
 * The simulation is fixed-step and deterministic: the same track plus the same
 * sequence of held/not-held values always produces the same run. That is what
 * lets a replay be nothing but the button steps, and what lets the same run be
 * reproduced exactly for the ghosts and the leaderboard.
 */
export class Game {
  constructor(canvas, hooks = {}, mode = 'endless') {
    this.canvas = canvas;
    this.hooks = hooks;
    this.renderer = new Renderer(canvas);
    this.camera = new Camera();
    this.held = false;
    this.acc = 0;
    this.last = 0;
    this.running = false;
    this.mode = mode;
    this.seed = 1;
    this.carSkin = 0;      // index into CAR_COLOURS; app.js owns the preference
    this.replaySteps = null;
    this.replayIndex = 0;
    // A pace ghost raced alongside the player (not a replay). See setGhostReplay.
    this.ghostCar = null;
    this.ghostSteps = null;
    this.ghostIndex = 0;
    this.ghostName = null;
    this.ghostTime = null;
    this.load(1);
  }

  load(seed, mode = this.mode) {
    this.mode = mode;
    this.seed = seed;
    this.track = mode === 'endless' ? new Track(seed) : new Track(seed, trackOpts(seed));
    this.car = new Car();
    this.car.reset(this.track);
    this.renderer.setSeed(seed);
    this.renderer.setCar(this.carSkin);
    this.camera.follow(this.car, 0, true);
    this.record = mode === 'endless' ? getRecord(seed) : { time: getBestTime(seed) };
    this.acc = 0;
    // The button log for this run. Only kept while actually playing.
    this.steps = [];
    this.clearGhost();
    this.state = 'ready';
    this.emit();
  }

  /** Set up a replay: re-simulate the stored button steps on this track. */
  loadReplay(seed) {
    const rep = getReplay(seed);
    if (!rep) return false;
    this.replaySteps = decodeSteps(rep.steps);
    this.replayIndex = 0;
    this.load(seed, 'replay');
    return true;
  }

  /**
   * Race a ghost alongside the player.
   *
   * The ghost is the world-record run (or the player's own best), re-simulated
   * step for step in lockstep with the player: same fixed step, same track, same
   * clock. It is not drawn for the player to control - it is a pace car.
   *
   * `ghostCar` is null when there is nothing to race.
   */
  setGhostReplay(seed, ghostId, name, time) {
    const run = simulateGhost(seed, ghostId);
    if (!run) return false;
    const track = new Track(seed, trackOpts(seed));
    const car = new Car();
    car.reset(track);
    this.ghostCar = car;
    this.ghostSteps = decodeSteps(run.replay.steps);
    this.ghostIndex = 0;
    this.ghostName = name;
    this.ghostTime = time;
    return true;
  }

  /**
   * Race a ghost that is a real run rather than a baked one.
   *
   * A real world record has no ghost id to regenerate it from, so its steps come
   * from the board. Everything else matches setGhostReplay: same lockstep clock.
   */
  setGhostSteps(seed, steps, name, time) {
    if (typeof steps !== 'string' || !steps) return false;
    const track = new Track(seed, trackOpts(seed));
    const car = new Car();
    car.reset(track);
    this.ghostCar = car;
    this.ghostSteps = decodeSteps(steps);
    this.ghostIndex = 0;
    this.ghostName = name;
    this.ghostTime = time;
    return true;
  }

  clearGhost() {
    this.ghostCar = null;
    this.ghostSteps = null;
    this.ghostIndex = 0;
    this.ghostName = null;
    this.ghostTime = null;
  }

  /** The ghost's own best, if one is stored, so you can race yourself. */
  setGhostSelf(seed) {
    const rep = getReplay(seed);
    if (!rep) return false;
    const track = new Track(seed, trackOpts(seed));
    const car = new Car();
    car.reset(track);
    this.ghostCar = car;
    this.ghostSteps = decodeSteps(rep.steps);
    this.ghostIndex = 0;
    this.ghostName = 'Your best';
    this.ghostTime = rep.time;
    return true;
  }

  /**
   * Watch a leaderboard ghost. The ghost's replay is not stored anywhere - it is
   * re-simulated from its id here, which is what keeps the field data tiny.
   */
  loadGhostReplay(seed, ghostId) {
    const run = simulateGhost(seed, ghostId);
    if (!run) return false;
    this.replaySteps = decodeSteps(run.replay.steps);
    this.replayIndex = 0;
    this.load(seed, 'replay');
    return true;
  }

  /**
   * Watch a real submitted run, replayed from its button steps.
   *
   * This is how a server-board ghost is watched: unlike a baked ghost there is no
   * id to regenerate it from, so the steps travel with the row.
   */
  loadStepsReplay(seed, steps) {
    if (typeof steps !== 'string' || !steps) return false;
    this.replaySteps = decodeSteps(steps);
    this.replayIndex = 0;
    this.load(seed, 'replay');
    return true;
  }

  start() {
    if (this.state !== 'ready') return;
    this.state = 'running';
    this.held = false;
    this.emit();
  }

  restart() { this.load(this.seed, this.mode === 'replay' ? 'speedrun' : this.mode); }

  /** Distance in metres, which is the endless score. */
  get metres() { return this.car.distance / CFG.pxPerMetre; }

  /**
   * Elapsed run time in seconds, which is the speedrun score.
   *
   * This is the car's own simulated clock, not a separate wall clock. The two used
   * to differ by one step: the loop only counted a step while the car was alive,
   * so the finishing step was never added. A ghost's time comes from its
   * simulation, so the discrepancy made every ghost look one step (8ms) slower
   * than an identical player run - enough to change the rank. Reading the car's
   * clock keeps a run and a ghost of that same run in exact agreement.
   */
  get time() { return this.car.time; }

  get isReplay() { return this.mode === 'replay'; }

  setHeld(v) {
    if (this.state !== 'running' || this.isReplay) return;
    this.held = v;
  }

  /** The button value to feed the next fixed step: replay steps, or the player. */
  inputForStep() {
    if (this.isReplay) {
      const v = this.replaySteps[this.replayIndex] || false;
      this.replayIndex++;
      return v;
    }
    return this.held;
  }

  die() {
    this.state = 'dead';
    if (this.isReplay) { this.emit({ died: true, replay: true }); return; }
    const prev = saveRecord(this.seed, this.metres, this.car.grabbed);
    this.camera.kick(18);
    this.emit({ died: true, prev });
  }

  finish() {
    this.state = 'finished';
    if (this.isReplay) { this.emit({ finished: true, replay: true }); return; }
    const time = this.car.time;
    const prev = saveBestTime(this.seed, time);
    // Every finish goes in the history, not just personal bests, so the player can
    // see how they have been doing on a track over time.
    addRun(this.seed, time);
    // A new best time gets its replay stored, so the board can show how it was
    // done. Only the steps are kept; the physics re-creates the run.
    if (prev === null || time < prev) {
      saveReplay(this.seed, makeReplay(this.seed, this.steps, time));
    }
    // Send the run to the leaderboard. Queued first, so a failure here (offline,
    // server down) cannot cost the player their run.
    this.camera.kick(10);
    this.emit({ finished: true, prev, submit: true });
  }

  emit(extra) { if (this.hooks.onChange) this.hooks.onChange(this, extra); }

  loop = (now) => {
    if (!this.running) return;
    const dt = Math.min(0.1, (now - this.last) / 1000 || 0);
    this.last = now;

    if (this.state === 'running') {
      this.acc += dt;
      let steps = 0;
      while (this.acc >= FIXED_DT && steps < MAX_STEPS) {
        const input = this.inputForStep();
        if (!this.isReplay) this.steps.push(input);
        this.car.step(FIXED_DT, input);
        // The pace ghost runs the same fixed steps on the same track, so its
        // position at any moment is directly comparable to the player's.
        if (this.ghostCar) {
          const gh = this.ghostSteps[this.ghostIndex++] || false;
          this.ghostCar.step(FIXED_DT, gh);
        }
        this.acc -= FIXED_DT;
        steps++;
        if (this.car.finished || !this.car.alive) break;
      }
      if (steps === MAX_STEPS) this.acc = 0;   // drop the backlog rather than spiral
      this.camera.follow(this.car, dt);
      // Report the step we just took *before* resolving the outcome. finish() and
      // die() move the state off 'running', and onTick only fires while running,
      // so resolving first would drop the final step's time and leave the HUD one
      // step (8ms) short of the time the run is actually scored at.
      if (this.state === 'running') this.hooks.onTick?.(this);
      if (this.car.finished) this.finish();
      else if (!this.car.alive) this.die();
    }

    this.camera.update(dt);
    this.renderer.draw(this.car, this.camera, this.track, this.ghostCar);
    requestAnimationFrame(this.loop);
  };

  run() {
    if (this.running) return;
    this.running = true;
    this.last = performance.now();
    requestAnimationFrame(this.loop);
  }

  stop() { this.running = false; }
}
