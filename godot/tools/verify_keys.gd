extends SceneTree

# Headless check of the rebindable keys. R restarts the run in progress, Space is
# the play button, and both can be rebound in Settings. The App is built inside a
# SubViewport so the logical viewport is a known size in headless.

var failures := 0


func _fail(msg: String) -> void:
	failures += 1
	print("  FAIL ", msg)


func _check(label: String, cond: bool) -> void:
	print("  %-44s %s" % [label, "ok " if cond else "FAIL"])
	if not cond:
		failures += 1


func _key(code: int, pressed: bool) -> InputEventKey:
	var e := InputEventKey.new()
	e.keycode = code
	e.pressed = pressed
	return e


func _initialize() -> void:
	var sub := SubViewport.new()
	sub.size = Vector2i(420, 820)
	sub.disable_3d = true
	get_root().add_child(sub)

	var scene: PackedScene = load("res://scenes/main.tscn")
	var app := scene.instantiate()
	sub.add_child(app)
	for i in range(3):
		await process_frame

	_check("default play key is Space", app.input_key == KEY_SPACE)
	_check("default reset key is R", app.reset_key == KEY_R)

	# Start a run, advance it, then press R: the run must be back at the start.
	app._start_run(1)
	await process_frame
	for i in range(30):
		app.game._physics_process(1.0 / 60.0)
	_check("run has advanced", app.game.car.time > 0.0)
	app._unhandled_input(_key(KEY_R, true))
	_check("R restarts the run", app.game.car.time == 0.0)
	_check("R leaves the run running", app.game.state == "running")

	# R must not restart a replay: the reset key is for a run in progress.
	app._start_run(1)
	await process_frame
	for i in range(30):
		app.game._physics_process(1.0 / 60.0)
	app.game.mode = "replay"
	var before: float = app.game.car.time
	app._unhandled_input(_key(KEY_R, true))
	_check("R does not touch a replay", app.game.car.time == before)
	app.game.mode = "speedrun"

	# Rebinding: capture a new reset key, then check it works and R does not.
	app._begin_capture("reset")
	app._bind_key(KEY_Q)
	_check("reset key rebound to Q", app.reset_key == KEY_Q)
	app._start_run(1)
	await process_frame
	for i in range(30):
		app.game._physics_process(1.0 / 60.0)
	app._unhandled_input(_key(KEY_R, true))
	_check("old key no longer resets", app.game.car.time > 0.0)
	app._unhandled_input(_key(KEY_Q, true))
	_check("new key resets", app.game.car.time == 0.0)

	# The two bindings must not collide.
	app._begin_capture("reset")
	app._bind_key(KEY_SPACE)
	_check("collision with play key refused", app.reset_key == KEY_Q)
	app._begin_capture("reset")
	app._bind_key(KEY_ESCAPE)
	_check("escape cancels the capture", app.reset_key == KEY_Q)

	# Put the defaults back so a headless run does not change the local prefs.
	app._begin_capture("reset")
	app._bind_key(KEY_R)
	_check("restored reset key is R", app.reset_key == KEY_R)

	sub.queue_free()
	await process_frame

	if failures == 0:
		print("KEYS PASS")
	else:
		print("KEYS FAIL: %d problem(s)" % failures)
	quit(1 if failures > 0 else 0)
