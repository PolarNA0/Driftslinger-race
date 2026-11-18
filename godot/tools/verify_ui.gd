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

	# Every tab is reachable, and switching to each one raises its page.
	for name in ["play", "garage", "editor", "account"]:
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

	# The Editor tab opens the track editor, a full-screen overlay. The header and
	# the camera row are pinned and must fit the viewport; the Build / Look / Help
	# pages live in a scroll area, so only their width is guaranteed.
	shell.select("editor")
	await process_frame
	app._new_custom_track()
	await process_frame
	if not app.editor.visible:
		_fail("editor did not open for a new track")
	else:
		for b in _pinned_buttons(app.editor):
			if not _in_view(b, vp):
				_fail("editor: '%s' out of view at %s" % [_label_of(b), b.get_global_rect()])
		if not _in_view(app.editor.play_button, vp):
			_fail("editor: Play button out of view at %s" % app.editor.play_button.get_global_rect())
		# The map has a real road and a working camera.
		var pv = app.editor.preview
		if not pv.ok or pv._road.size() < 2:
			_fail("editor map has no road to show")
		else:
			pv.fit()
			var mid: Vector2 = pv.world_to_screen(pv._road[pv._road.size() / 2])
			if not _in_view(app.editor.preview, vp):
				_fail("editor map out of view")
			elif mid.x < -1.0 or mid.x > pv.size.x + 1.0 or mid.y < -1.0 or mid.y > pv.size.y + 1.0:
				_fail("editor camera: Fit did not bring the road into the map (%s)" % mid)
		# Each page comes up, and its controls fit the width of the scroll area.
		for page in ["look", "help", "build"]:
			app.editor._switch_page(page)
			await process_frame
			for b in _buttons(app.editor.page_box):
				if not _fits_width(b, vp):
					_fail("editor %s page: '%s' too wide at %s" % [page, _label_of(b), b.get_global_rect()])
	# Close and delete the track the check made, leaving the store as it started.
	var made_id: int = app.editor.id
	app.editor._on_close()
	await process_frame
	if app.editor.visible:
		_fail("editor did not close")

	# A custom track is a real course: it loads into the game with the ops the editor
	# built, and it is local-only - a run on it never uploads and shows no board.
	app._open_editor(made_id)
	await process_frame
	var want_corners: int = CustomTracks.corner_count(app.editor.ops)
	if want_corners <= 0:
		_fail("editor had no corners to load")
	# Give the track a distinctive look, then check the run paints it: the theme the
	# editor sets has to reach the renderer, or a custom track plays in the wrong colours.
	CustomTracks.set_theme(app.editor.id, "ff0000", "00ff00")
	app._on_editor_play()
	await process_frame
	if app.game.track == null:
		_fail("custom track did not load into the game")
	else:
		if app.game.track.fillets.size() != want_corners:
			_fail("custom track has %d corners, editor built %d" % [app.game.track.fillets.size(), want_corners])
		if app.game.mode != "speedrun":
			_fail("custom track loaded outside speedrun")
		# The custom theme reaches the renderer (a built-in track leaves it empty).
		var ov: Dictionary = app.game.renderer.theme_override
		if ov.is_empty() or ov["road"] != Color("ff0000") or ov["ground"] != Color("00ff00"):
			_fail("custom track theme did not reach the renderer: %s" % ov)
	# Drive the custom track to its finish through the real game loop, with the same
	# clean line verify_tracks uses, so the finish card is built the way a player's
	# run builds it. Then check it is local-only: no leaderboard, no world record.
	if app.game.track != null:
		var t: Track = app.game.track
		var i := 0
		while app.game.car.alive and not app.game.car.finished and i < 200000:
			i += 1
			var held := false
			if app.game.car.attached:
				held = app.game.car.remaining() > 0.0
			else:
				var f: Dictionary = t.fillets[app.game.car.corner]
				var c: Vector2 = f["c"]
				held = U.dist(c.x, c.y, app.game.car.x, app.game.car.y) <= Cfg.GRAB_RANGE
			app.game.set_held(held)
			app.game._physics_process(1.0 / 120.0)
		await process_frame
		if not app.game.car.finished:
			_fail("a clean line did not finish the custom track")
		if app.btn_finish_lb.visible:
			_fail("finish card offers a leaderboard for a custom track")
		if app.btn_finish_wr.visible:
			_fail("finish card offers a world record for a custom track")

	app._to_menu()
	await process_frame
	CustomTracks.erase(made_id)
	app._refresh_editor_list()
	app._refresh_custom_list()

	sub.queue_free()
	await process_frame


# A tab page scrolls vertically (its ScrollContainer disables horizontal scroll),
# so a control below the fold is reachable by scrolling but a control wider than the
# viewport is not. That is the bug the old menu had, so width is what is checked.
func _check_page(name: String, page: Control, vp: Vector2i) -> void:
	var n := 0
	for b in _buttons(page):
		n += 1
		if not _fits_width(b, vp):
			_fail("%s: '%s' too wide at %s" % [name, _label_of(b), b.get_global_rect()])
	if n == 0:
		_fail("%s: no buttons found" % name)


# Every button in the editor that is not inside the scrolling control area. Those are
# the ones that must always be reachable (the header and the camera row), so they are
# what the in-view check measures; the page controls may sit below the fold.
func _pinned_buttons(editor: Node) -> Array:
	var out: Array = []
	var skip: Node = editor.control_scroll
	for b in _buttons(editor):
		if not _in_subtree(b, skip):
			out.append(b)
	return out


func _in_subtree(n: Node, root: Node) -> bool:
	var p := n
	while p != null:
		if p == root:
			return true
		p = p.get_parent()
	return false


func _in_view(c: Control, vp: Vector2i) -> bool:
	var r := c.get_global_rect()
	return r.position.x >= -1.0 and r.position.y >= -1.0 and r.end.x <= vp.x + 1.0 and r.end.y <= vp.y + 1.0


func _fits_width(c: Control, vp: Vector2i) -> bool:
	var r := c.get_global_rect()
	return r.position.x >= -1.0 and r.end.x <= vp.x + 1.0


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
