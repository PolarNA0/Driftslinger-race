extends SceneTree

# The menu is a full-screen shell with a bottom tab bar. This guards the two things
# that broke the old menu: a control wider or taller than the viewport (unreachable
# on a phone), and a tab whose page does not actually come up. It presses the real
# buttons and measures the real rects, at phone size and at a wide desktop size.
#
# The App is built inside a SubViewport of the size under test, so the logical
# viewport is that size even in headless - which cannot resize the OS window.

const SIZES := [Vector2i(420, 820), Vector2i(1024, 768)]

var failures := 0


func _initialize() -> void:
	for vp in SIZES:
		await _check_size(vp)
	if failures == 0:
		print("UI PASS")
	else:
		print("UI FAIL: %d problem(s)" % failures)
	quit(1 if failures > 0 else 0)


func _fail(msg: String) -> void:
	failures += 1
	print("  FAIL ", msg)


func _check_size(vp: Vector2i) -> void:
	var sub := SubViewport.new()
	sub.size = vp
	sub.disable_3d = true
	get_root().add_child(sub)

	var scene: PackedScene = load("res://scenes/main.tscn")
	var app := scene.instantiate()
	sub.add_child(app)
	for i in range(3):
		await process_frame

	print("== viewport %dx%d ==" % [vp.x, vp.y])
	var shell: Node = _find_shell(app)
	if shell == null:
		_fail("no MenuShell in the tree")
		sub.queue_free()
		return

	# The shell itself fills the window.
	if shell.size.x < vp.x - 2 or shell.size.y < vp.y - 2:
		_fail("shell is %s, want about %s" % [shell.size, vp])

	# The three tabs are all reachable, and switching to each one raises its page.
	for name in ["play", "garage", "account"]:
		if not shell.tabs.has(name):
			_fail("tab '%s' missing" % name)
			continue
		var tab: Button = shell.tabs[name]
		if not _in_view(tab, vp):
			_fail("tab '%s' out of view at %s" % [name, tab.get_global_rect()])
		shell.select(name)
		await process_frame
		var page: Control = app.tab_pages[name]
		if not page.visible:
			_fail("tab '%s' page did not become visible" % name)
		for other in app.tab_pages:
			if other != name and app.tab_pages[other].visible:
				_fail("tab '%s' page visible while '%s' is selected" % [other, name])
		_check_page(name, page, vp)

	# Endless has no track to pick, so the chooser must be hidden in that mode.
	shell.select("play")
	app._set_mode("speedrun")
	await process_frame
	if not app.track_section.visible:
		_fail("track chooser hidden in speedrun")
	app._set_mode("endless")
	await process_frame
	if app.track_section.visible:
		_fail("track chooser still shown in endless")
	for b in app.track_buttons:
		if b.is_visible_in_tree() and _in_view(b, vp):
			_fail("track button reachable in endless")
	app._set_mode("speedrun")
	await process_frame

	# The gear opens Settings as a modal card, and it fits.
	shell.settings_pressed.emit()
	await process_frame
	var settings: Control = app.overlays["settings"]
	if not settings.visible:
		_fail("settings overlay did not open")
	else:
		_check_page("settings", settings, vp)
		# The rebind rows must be present even where a touchscreen is reported
		# (an iPad with a keyboard attached) - that is exactly what hid them.
		for name in ["play", "reset", "pause"]:
			if not app.key_buttons.has(name):
				_fail("settings: no %s key row" % name)
			elif not _in_view(app.key_buttons[name], vp):
				_fail("settings: %s key row out of view" % name)
	app._to_menu()
	await process_frame
	if settings.visible:
		_fail("settings overlay did not close")

	# The leaderboard opens in both modes and every row fits. Endless is the new
	# board, so it is checked explicitly: a row wider than the card would be the
	# phone-fit bug back on a new screen.
	for mode in ["speedrun", "endless"]:
		app._set_mode(mode)
		await process_frame
		app._show_leaderboard(1)
		await process_frame
		var board: Control = app.overlays["board"]
		if not board.visible:
			_fail("board overlay did not open in %s" % mode)
		elif app.board_mode != mode:
			_fail("board_mode is %s, want %s" % [app.board_mode, mode])
		else:
			_check_page("board-%s" % mode, board, vp)
			for b in app.lb_rows.get_children():
				if b is Control and not _in_view(b, vp):
					_fail("board-%s: row out of view at %s" % [mode, (b as Control).get_global_rect()])
		app._to_menu()
		await process_frame
	app._set_mode("speedrun")
	await process_frame

	# The flow: the shell is up at the menu, hidden during a run, and back after.
	if not shell.visible:
		_fail("shell hidden at boot")
	if app.btn_restart_round.visible:
		_fail("restart button visible at the menu")
	app._start_run(1)
	await process_frame
	if shell.visible:
		_fail("shell still visible during a run")
	if not app.btn_restart_round.visible:
		_fail("restart button hidden during a run")
	elif not _in_view(app.btn_restart_round, vp):
		_fail("restart button out of view at %s" % app.btn_restart_round.get_global_rect())
	app._to_menu()
	await process_frame
	if not shell.visible:
		_fail("shell not restored by returning to the menu")
	if app.btn_restart_round.visible:
		_fail("restart button still visible at the menu")

	sub.queue_free()
	await process_frame


func _check_page(name: String, page: Control, vp: Vector2i) -> void:
	var n := 0
	for b in _buttons(page):
		n += 1
		if not _in_view(b, vp):
			_fail("%s: '%s' out of view at %s" % [name, _label_of(b), b.get_global_rect()])
	if n == 0:
		_fail("%s: no buttons found" % name)


func _in_view(c: Control, vp: Vector2i) -> bool:
	var r := c.get_global_rect()
	return r.position.x >= -1.0 and r.position.y >= -1.0 and r.end.x <= vp.x + 1.0 and r.end.y <= vp.y + 1.0


func _label_of(b: Button) -> String:
	if b.text != "":
		return b.text.replace("\n", " / ")
	for c in b.get_children():
		if c is Label:
			return (c as Label).text
	return b.name


func _buttons(n: Node) -> Array:
	var out: Array = []
	for c in n.get_children():
		if c is Button and c.visible:
			out.append(c)
		if c is Node:
			out.append_array(_buttons(c))
	return out


func _find_shell(n: Node) -> Node:
	if n.get_script() != null and str(n.get_script().resource_path).ends_with("menu_shell.gd"):
		return n
	for c in n.get_children():
		var r := _find_shell(c)
		if r != null:
			return r
	return null
