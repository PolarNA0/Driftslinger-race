extends Node2D
class_name Game

# Port of the old js/game.js (removed with the JS client): the loop, the three modes, records, replays and ghosts.
#
# One button: hold to hook the next pole and swing, let go to fly straight.
# Leaving the road ends the run.
#
#   endless  - an infinite road, scored by distance.
#   speedrun - one of the twenty fixed tracks, scored by time.
#   replay   - a saved speedrun re-simulated from its button steps, read-only.
#
# The simulation is fixed-step and deterministic, so a replay is just the button
# steps and the same run can be reproduced exactly for ghosts and the board.

const FIXED_DT := 1.0 / 120.0
const MAX_STEPS := 8
const LEAD := 90.0

signal changed(extra: Dictionary)
signal ticked()

var renderer: Renderer2D
var track: Track
var car: Car
var cam_x := 0.0
var cam_y := 0.0
var cam_angle := 0.0
var shake := 0.0

var mode := "endless"
var seed_num := 1
var car_skin := 0
var held := false
var acc := 0.0
var state := "ready"
var steps := []

var replay_steps: Variant = null
var replay_index := 0

var ghost_car: Car = null
var ghost_steps: Variant = null
var ghost_index := 0


func _ready() -> void:
	renderer = Renderer2D.new()
	add_child(renderer)
	set_physics_process(false)


func load_track(p_seed: int, p_mode: String = "") -> void:
	if p_mode != "":
		mode = p_mode
	seed_num = p_seed
	track = Track.new(seed_num) if mode == "endless" else Track.new(seed_num, Tracks.track_opts(seed_num))
	car = Car.new()
	car.reset(track)
	renderer.track = track
	renderer.car_ref = car
	renderer.seed_num = seed_num
	renderer.car_index = car_skin
	renderer.ghost_car = null
	renderer.ghost_visible = false
	cam_x = car.x
	cam_y = car.y
	cam_angle = car.angle
	acc = 0.0
	steps = []
	clear_ghost()
	state = "ready"
	changed.emit({})


# Set up a replay: re-simulate the stored button steps on this track.
func load_replay(p_seed: int) -> bool:
	var rep = Storage.get_replay(p_seed)
	if rep == null:
		return false
	replay_steps = Replay.decode_steps(rep["steps"])
	replay_index = 0
	load_track(p_seed, "replay")
	return true


func set_ghost_self(p_seed: int) -> bool:
	var rep = Storage.get_replay(p_seed)
	if rep == null:
		return false
	var gt := Track.new(p_seed, Tracks.track_opts(p_seed))
	var gc := Car.new()
	gc.reset(gt)
	ghost_car = gc
	ghost_steps = Replay.decode_steps(rep["steps"])
	ghost_index = 0
	renderer.ghost_car = gc
	renderer.ghost_visible = true
	return true


func clear_ghost() -> void:
	ghost_car = null
	ghost_steps = null
	ghost_index = 0
	if renderer != null:
		renderer.ghost_car = null
		renderer.ghost_visible = false


func start() -> void:
	if state != "ready":
		return
	state = "running"
	held = false
	acc = 0.0
	set_physics_process(true)
	changed.emit({})


func restart() -> void:
	load_track(seed_num, "speedrun" if mode == "replay" else mode)
	start()


func is_replay() -> bool:
	return mode == "replay"


# Best time on this track so far, or null. Used by the HUD and the finish card.
func record_time() -> Variant:
	return Storage.get_best_time(seed_num)


# Best distance on this track so far, the endless score.
func record_dist() -> float:
	return float(Storage.get_record(seed_num)["dist"])


# Distance in metres, which is the endless score.
func metres() -> float:
	return car.distance() / Cfg.PX_PER_METRE


# Elapsed run time in seconds, the speedrun score. The car's own clock, not a
# separate wall clock, so a run and a ghost of that run agree exactly.
func run_time() -> float:
	return car.time


func set_held(v: bool) -> void:
	if state != "running" or is_replay():
		return
	held = v


# The button value to feed the next fixed step: replay steps, or the player.
func _input_for_step() -> bool:
	if is_replay():
		var v: bool = replay_steps[replay_index] if replay_index < replay_steps.size() else false
		replay_index += 1
		return v
	return held


func _physics_process(delta: float) -> void:
	if state != "running":
		return
	acc += delta
	var n := 0
	while acc >= FIXED_DT and n < MAX_STEPS:
		var input := _input_for_step()
		if not is_replay():
			steps.append(input)
		car.step(FIXED_DT, input)
		if ghost_car != null:
			var gh: bool = ghost_steps[ghost_index] if ghost_index < ghost_steps.size() else false
			ghost_index += 1
			ghost_car.step(FIXED_DT, gh)
		acc -= FIXED_DT
		n += 1
		if car.finished or not car.alive:
			break
	if n == MAX_STEPS:
		acc = 0.0
	_follow(delta)
	if state == "running":
		ticked.emit()
	if car.finished:
		_finish()
	elif not car.alive:
		_die()


func _follow(delta: float) -> void:
	var tx := car.x + cos(car.angle) * LEAD
	var ty := car.y + sin(car.angle) * LEAD
	cam_angle += U.ang_diff(cam_angle, car.angle) * minf(1.0, 6.0 * delta)
	cam_x += (tx - cam_x) * minf(1.0, 12.0 * delta)
	cam_y += (ty - cam_y) * minf(1.0, 12.0 * delta)
	if shake > 0.0:
		shake = maxf(0.0, shake - delta * 60.0)
	renderer.cam_x = cam_x
	renderer.cam_y = cam_y
	renderer.cam_angle = cam_angle
	renderer.shake = shake


func kick(amount: float) -> void:
	shake = maxf(shake, amount)


func _die() -> void:
	state = "dead"
	set_physics_process(false)
	if is_replay():
		changed.emit({"died": true, "replay": true})
		return
	var prev := Storage.save_record(seed_num, metres(), car.grabbed)
	kick(18.0)
	changed.emit({"died": true, "prev": prev})


func _finish() -> void:
	state = "finished"
	set_physics_process(false)
	if is_replay():
		changed.emit({"finished": true, "replay": true})
		return
	var time := car.time
	var prev = Storage.save_best_time(seed_num, time)
	# Every finish goes in the history, not just personal bests.
	Storage.add_run(seed_num, time)
	# A new best gets its replay stored, so the board can show how it was done.
	if prev == null or time < float(prev):
		Storage.save_replay(seed_num, Replay.make_replay(seed_num, steps, time))
	kick(10.0)
	changed.emit({"finished": true, "prev": prev})
