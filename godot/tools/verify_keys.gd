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
	_check("default pause key is Esc", app.pause_key == KEY_ESCAPE)

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

	# R retries from the crash and finish cards: the key does what the card's
	# "Run it again" button does. A menu overlay is still refused.
	app._start_run(1)
	await process_frame
	app._show_only("dead")
	app._unhandled_input(_key(KEY_R, true))
	_check("R restarts from the crash card", app.game.car.time == 0.0 and app.overlay == "")
	app._start_run(1)
	await process_frame
	app._show_only("finish")
	app._unhandled_input(_key(KEY_R, true))
	_check("R restarts from the finish card", app.game.car.time == 0.0 and app.overlay == "")
	app._start_run(1)
	await process_frame
	for i in range(30):
		app.game._physics_process(1.0 / 60.0)
	app._show_only("settings")
	var menu_time: float = app.game.car.time
	app._unhandled_input(_key(KEY_R, true))
	_check("R does not restart from Settings", app.game.car.time == menu_time)
	app._hide_overlays()

	# Esc toggles pause: pauses a running run, resumes a paused one.
	app._start_run(1)
	await process_frame
	app._unhandled_input(_key(KEY_ESCAPE, true))
	_check("Esc pauses the run", app.game.state == "paused" and app.overlay == "pause")
	app._unhandled_input(_key(KEY_ESCAPE, true))
	_check("Esc resumes the run", app.game.state == "running" and app.overlay == "")
	# It must not touch a run that is already over.
	app.game.state = "dead"
	app._unhandled_input(_key(KEY_ESCAPE, true))
	_check("Esc inert when the run is over", app.game.state == "dead")
	app.game.state = "running"

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

	# Rebinding the pause key works the same way.
	app._begin_capture("pause")
	app._bind_key(KEY_P)
	_check("pause key rebound to P", app.pause_key == KEY_P)
	app._start_run(1)
	await process_frame
	app._unhandled_input(_key(KEY_ESCAPE, true))
	_check("old pause key no longer pauses", app.game.state == "running")
	app._unhandled_input(_key(KEY_P, true))
	_check("new pause key pauses", app.game.state == "paused")
	app._unhandled_input(_key(KEY_P, true))

	# The two bindings must not collide.
	app._begin_capture("reset")
	app._bind_key(KEY_SPACE)
	_check("collision with play key refused", app.reset_key == KEY_Q)
	app._begin_capture("pause")
	app._bind_key(KEY_Q)
	_check("collision with reset key refused", app.pause_key == KEY_P)
	app._begin_capture("pause")
	app._bind_key(KEY_ESCAPE)
	_check("escape cancels the capture", app.pause_key == KEY_P)

	# Put the defaults back so a headless run does not change the local prefs.
	app._begin_capture("reset")
	app._bind_key(KEY_R)
	_check("restored reset key is R", app.reset_key == KEY_R)
	# Esc cancels a capture, so the default is restored through the setter.
	app._set_binding("pause", KEY_ESCAPE)
	_check("restored pause key is Esc", app.pause_key == KEY_ESCAPE)

	# The Settings "Controls" block must always offer the rebind rows. Gating them
	# on a touchscreen hid them on an iPad with a keyboard attached, which left the
	# page saying nothing but "Controls". Checked last, because it replaces the
	# button map the checks above drive.
	app.key_buttons.clear()
	var box := VBoxContainer.new()
	app._settings_controls(box)
	_check("settings offers a Play key row", app.key_buttons.has("play"))
	_check("settings offers a Reset key row", app.key_buttons.has("reset"))
	_check("settings offers a Pause key row", app.key_buttons.has("pause"))
	box.free()

	sub.queue_free()
	await process_frame

	if failures == 0:
		print("KEYS PASS")
	else:
		print("KEYS FAIL: %d problem(s)" % failures)
	quit(1 if failures > 0 else 0)
