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

	# Every text field must sit in a ScrollContainer that follows focus. When the
	# Android keyboard raises it shrinks the viewport; without follow_focus the
	# focused LineEdit keeps its old position and ends up behind the keyboard, which
	# players report as "the keyboard does not show up". Checked across the whole
	# tree so a new form cannot reintroduce it.
	_check_text_fields_follow_focus(app, vp)

	# Endless has no track to pick, so the chooser must be hidden in that mode.
	shell.select("play")
	app._set_mode("speedrun")
	await process_frame
	if not app.track_section.visible:
		_fail("track chooser hidden in speedrun")
	if not app.daily_section.visible:
		_fail("daily card hidden in speedrun")
	if not _in_view(app.daily_button, vp):
		_fail("daily button out of view at %s" % app.daily_button.get_global_rect())
	if not app.daily_title.text.contains("Track"):
		_fail("daily card did not name its track (got '%s')" % app.daily_title.text)
	# Every track card carries a real mini-map and its number + best. Both labels
	# are `clip_text`, so a card narrower than its content silently drops the last
	# digit; seed a realistic time first or the check only sees "--".
	var seed_track: int = Tracks.MENU_TRACKS[0]
	var snapshot: Variant = Storage._read("times.v1", {})
	Storage.save_best_time(seed_track, 10.1416)
	app._refresh_track_list()
	await process_frame
	for b in app.track_buttons:
		if not b.is_visible_in_tree():
			continue
		if _find_child(b, TrackMap) == null:
			_fail("track card '%s' has no mini-map" % b.get_meta("track"))
		var sb: StyleBox = b.get_theme_stylebox("normal")
		var avail: float = b.size.x - float(sb.content_margin_left) - float(sb.content_margin_right)
		for lbl in _labels(b):
			var fs: int = lbl.get_theme_font_size("font_size")
			var f: Font = lbl.get_theme_font("font")
			var tw := f.get_string_size(lbl.text, HORIZONTAL_ALIGNMENT_LEFT, -1, fs).x
			if tw > avail + 0.5:
				_fail("track card '%s' clips '%s': text %.1f > %.1f avail" % [
					b.get_meta("track"), lbl.text, tw, avail])
	# The Race action is a sticky footer above the tab bar, so a long track grid
	# cannot bury the one button the tab exists for.
	if app.play_cta_label == null:
		_fail("Play tab has no Race footer")
	elif app.play_cta_label.text == "":
		_fail("Race footer did not name the selected track")
	else:
		var cta: Control = app.play_cta_label.get_parent().get_parent()
		if not _in_view(cta, vp):
			_fail("Race footer out of view at %s" % cta.get_global_rect())
		if cta.get_global_rect().end.y > shell.content.get_global_rect().end.y + 1.0:
			_fail("Race footer overlaps the tab bar")
	# The seeded time must actually have reached the card, or the check above proves
	# nothing about a real PB.
	var seeded: Label = app.track_pb_labels[seed_track]
	if not seeded.text.contains("10.14"):
		_fail("track card did not show the seeded best (got '%s')" % seeded.text)
	# The selected card is a charcoal card with a 2px accent border, and its labels
	# stay ink on the card. Check both the border and the contrast, because a child
	# Label does not inherit the button's font_pressed_color.
	var selected: Button = null
	for b in app.track_buttons:
		if b.button_pressed:
			selected = b
			break
	if selected == null:
		_fail("no track card is selected")
	else:
		var spb := selected.get_theme_stylebox("pressed") as StyleBoxFlat
		if spb == null or spb.border_width_left < 2 or spb.border_color != UiTheme.ACCENT:
			_fail("selected track card has no 2px accent border")
		for sl in _labels(selected):
			var sc: Color = sl.get_theme_color("font_color")
			sc.a = 1.0
			var cr := _contrast(sc, spb.bg_color if spb != null else UiTheme.SURFACE)
			if cr < 4.5:
				_fail("selected track card label '%s' is %.2f:1 on the card" % [sl.text, cr])
	Storage._write("times.v1", snapshot)
	app._refresh_track_list()
	await process_frame
	app._set_mode("endless")
	await process_frame
	if app.track_section.visible:
		_fail("track chooser still shown in endless")
	if app.daily_section.visible:
		_fail("daily card still shown in endless")
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

	# The first-run tutorial is a tall card on a phone, so it has to scroll and
	# every button has to stay reachable.
	app._show_tutorial()
	await process_frame
	var tutorial: Control = app.overlays["tutorial"]
	if not tutorial.visible:
		_fail("tutorial overlay did not open")
	else:
		_check_page("tutorial", tutorial, vp)
	app._tutorial_back()
	await process_frame
	if tutorial.visible:
		_fail("tutorial overlay did not close")

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

	# The Editor tab opens the track editor, a full-screen overlay: a blank grid with
	# the piece palette pinned along the bottom. Everything that places a piece is
	# always on screen - there are no pages to dig through any more - so every palette
	# button is measured, not just the header.
	shell.select("editor")
	await process_frame
	app._new_custom_track()
	await process_frame
	if not app.editor.visible:
		_fail("editor did not open for a new track")
	else:
		# The overlay must fill the viewport. `set_anchors_preset` on an already-parented
		# node keeps the current (zero) rect, which collapsed the whole editor - and with
		# it the map - so this is the regression that matters.
		if app.editor.size.x < vp.x - 2 or app.editor.size.y < vp.y - 2:
			_fail("editor overlay is %s, want about %s" % [app.editor.size, vp])
		if app.editor.preview.size.x < 80.0 or app.editor.preview.size.y < 80.0:
			_fail("editor map is %s, too small to use" % app.editor.preview.size)
		# A drag on the map must actually move the camera.
		_drag_pans(app.editor.preview)
		if not _drag_panned:
			_fail("editor map: a drag did not pan the camera")
		if not app.editor.preview.show_grid:
			_fail("editor map is not showing its grid")
		# Every palette piece is on screen and reachable: that is the whole point of the
		# new layout, so a palette button below the fold is the bug coming back.
		for b in app.editor._palette_buttons.values():
			if not _in_view(b, vp):
				_fail("editor palette: '%s' out of view at %s" % [_label_of(b), b.get_global_rect()])
		for b in _pinned_buttons(app.editor):
			if not _in_view(b, vp):
				_fail("editor: '%s' out of view at %s" % [_label_of(b), b.get_global_rect()])
		if not _in_view(app.editor.play_button, vp):
			_fail("editor: Play button out of view at %s" % app.editor.play_button.get_global_rect())
		# A new track is an empty canvas: no pieces, and so no road drawn yet. The map
		# must still be a usable surface - ground, grid, camera - because that is what
		# the player places their first piece onto.
		var pv = app.editor.preview
		if not app.editor.ops.is_empty():
			_fail("a new track is not empty: %d pieces" % app.editor.ops.size())
		if pv._road.size() >= 2:
			_fail("an empty track still draws a road")

		# The core interaction: arm a piece, tap the grid, and the piece is added. Every
		# palette entry is exercised, because a dead button is silent.
		for key in ["straight", "90", "-90", "180", "270", "-270", "reattach", "reattach_l", "finish"]:
			var before: int = app.editor.ops.size()
			var had_finish := CustomTracks.finish_index(app.editor.ops) >= 0
			app.editor._arm(key)
			if app.editor._armed != key:
				_fail("editor: arming '%s' did not stick" % key)
			# Drive the real path: a tap on the map, not a direct call to the handler.
			# Calling the handler directly hid a real bug where `_arm` never set
			# `preview.armed`, so the palette was inert and a real tap did nothing.
			_tap_cell(app.editor.preview, Vector2i(3, 2))
			await process_frame
			# The finish closes the track, so re-placing it moves the existing one rather
			# than adding a second; every other piece adds one in front of it.
			var want := before
			if key != "finish" or not had_finish:
				want = before + 1
			if app.editor.ops.size() != want:
				_fail("editor: tapping the grid with '%s' armed gave %d pieces, want %d"
					% [key, app.editor.ops.size(), want])
			else:
				# The added piece is the one before the finish, not the last element,
				# because the finish always closes the road.
				var idx: int = app.editor.ops.size() - 1
				if key != "finish" and CustomTracks.finish_index(app.editor.ops) >= 0:
					idx = CustomTracks.finish_index(app.editor.ops) - 1
				var added: Dictionary = app.editor.ops[idx]
				if key == "finish":
					if not CustomTracks.is_finish(added):
						_fail("editor: the finish palette did not add a finish")
				elif key == "straight" and CustomTracks.is_corner(added):
					_fail("editor: the straight palette added a corner")
				elif key.begins_with("reattach") and not bool(added.get("reattach", false)):
					_fail("editor: the reattach palette added a normal turn")
				elif not key.begins_with("reattach") and bool(added.get("reattach", false)):
					_fail("editor: the '%s' palette added a reattach turn" % key)
				elif key != "straight" and not CustomTracks.is_corner(added):
					_fail("editor: the '%s' palette added a straight" % key)
				elif CustomTracks.is_corner(added) and int(added["deg"]) != PieceIcon.turn_deg(key):
					# The tile is a picture of a turn: it must place that turn, not its mirror.
					_fail("editor: '%s' placed deg=%d, want %d" % [key, int(added["deg"]), PieceIcon.turn_deg(key)])
				elif CustomTracks.is_corner(added) and PieceIcon.is_bend(key) == CustomTracks.has_pillar(added):
					# The bend tiles are the pillarless ones: a tile that says "no pillar"
					# must place a turn with no pole, and a corner tile must bring the
					# pole it is slung round.
					_fail("editor: '%s' placed a piece with pillar=%s" % [key, str(CustomTracks.has_pillar(added))])
			app.editor._arm(key)
		# Exactly one finish, ever, and it is last: that is what makes the road finite.
		var fins := 0
		for p in app.editor.ops:
			if CustomTracks.is_finish(p):
				fins += 1
		if fins != 1:
			_fail("editor: %d finish lines, want exactly 1" % fins)
		elif not CustomTracks.is_finish(app.editor.ops[app.editor.ops.size() - 1]):
			_fail("editor: the finish line is not last")
		# With a real road built, Fit must bring it into the map. The empty canvas has
		# nothing to fit, so this check moves here instead of being dropped.
		if not pv.ok or pv._road.size() < 2:
			_fail("editor map has no road after the palette built one")
		else:
			pv.fit()
			var mid: Vector2 = pv.world_to_screen(pv._road[pv._road.size() / 2])
			if mid.x < -1.0 or mid.x > pv.size.x + 1.0 or mid.y < -1.0 or mid.y > pv.size.y + 1.0:
				_fail("editor camera: Fit did not bring the road into the map (%s)" % mid)
		# Tapping an armed piece again puts the palette down.
		app.editor._arm("90")
		app.editor._arm("90")
		if app.editor._armed != "":
			_fail("editor: tapping an armed palette piece again did not disarm it")

		# Pinch zooms. Driven through the real two-touch path, because the gesture event
		# the old code relied on is never emitted on a phone.
		var z0: float = app.editor.preview._zoom
		var o0: Vector2 = app.editor.preview._origin
		# The pinch midpoint is the anchor: the world point under it must stay under it.
		# That tells a real anchored zoom from one that also pans. The origin always moves
		# when zooming about an anchor, so the origin is not the thing to check.
		var anchor: Vector2 = app.editor.preview.size * 0.5
		var world_before: Vector2 = app.editor.preview.screen_to_world(anchor)
		_two_finger_pinch(app.editor.preview, 1.8)
		if app.editor.preview._zoom <= z0:
			_fail("editor map: a two-finger pinch did not zoom in (%.3f -> %.3f)" % [z0, app.editor.preview._zoom])
		var world_after: Vector2 = app.editor.preview.screen_to_world(anchor)
		if world_before.distance_to(world_after) > 2.0:
			_fail("editor map: a pinch slid the map instead of zooming about the fingers")
		app.editor.preview._zoom = z0
		app.editor.preview._origin = o0

		# The colour sheet opens, its controls fit, and it closes again.
		app.editor._open_look()
		await process_frame
		if not app.editor.sheet.visible:
			_fail("editor: the colours sheet did not open")
		for b in _buttons(app.editor.sheet):
			if not _fits_width(b, vp):
				_fail("editor colours: '%s' too wide at %s" % [_label_of(b), b.get_global_rect()])
		app.editor._close_sheet()
		await process_frame
		if app.editor.sheet.visible:
			_fail("editor: the colours sheet did not close")

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

	# A daily challenge is a real speedrun on a modified track, and it is
	# local-only: no board, no world record, no medal. Drive one to the finish.
	var times_snapshot: Variant = Storage._read("times.v1", {})
	var replays_snapshot: Variant = Storage._read("replays.v1", {})
	var runs_snapshot: Variant = Storage._read("runs.v1", {})
	var tries_snapshot: Variant = Storage._read("attempts.v1", {})
	app._set_mode("speedrun")
	app._refresh_daily()
	await process_frame
	var daily_seed := int(app.daily_challenge["seed"])
	var tries_before := Storage.get_attempts(daily_seed)
	app._play_daily()
	await process_frame
	if not Daily.is_daily(app.game.seed_num):
		_fail("daily button did not start a daily seed")
	if app.game.mode != "speedrun":
		_fail("daily challenge loaded outside speedrun")
	if Storage.get_attempts(daily_seed) != tries_before + 1:
		_fail("daily attempt was not counted")
	if app.game.track != null:
		var dt: Track = app.game.track
		var di := 0
		while app.game.car.alive and not app.game.car.finished and di < 200000:
			di += 1
			var dheld := false
			if app.game.car.attached:
				dheld = app.game.car.remaining() > 0.0
			else:
				var df: Dictionary = dt.fillets[app.game.car.corner]
				var dc: Vector2 = df["c"]
				dheld = U.dist(dc.x, dc.y, app.game.car.x, app.game.car.y) <= Cfg.GRAB_RANGE
			app.game.set_held(dheld)
			app.game._physics_process(1.0 / 120.0)
		await process_frame
		if not app.game.car.finished:
			_fail("a clean line did not finish the daily")
		if app.btn_finish_lb.visible:
			_fail("finish card offers a leaderboard for a daily")
		if app.btn_finish_wr.visible:
			_fail("finish card offers a world record for a daily")
		if app.finish_medal.visible:
			_fail("finish card awards a built-in medal for a daily")
		if not app.finish_rank.text.begins_with("Daily"):
			_fail("daily finish card did not say Daily (got '%s')" % app.finish_rank.text)
	app._to_menu()
	await process_frame
	Storage._write("times.v1", times_snapshot)
	Storage._write("replays.v1", replays_snapshot)
	Storage._write("runs.v1", runs_snapshot)
	Storage._write("attempts.v1", tries_snapshot)

	sub.queue_free()
	await process_frame


var _drag_panned := false


# Drive a real drag through the map's own input handling and report whether the
# camera moved. Uses the touch path (what a phone sends) and the mouse path (a
# desktop), since the map handles both.
func _drag_pans(pv: Node) -> void:
	_drag_panned = false
	var c: Vector2 = pv.get_global_rect().get_center()
	var before: Vector2 = pv._origin
	var press := InputEventScreenTouch.new()
	press.index = 0
	press.pressed = true
	press.position = c
	pv._gui_input(press)
	for i in range(5):
		var d := InputEventScreenDrag.new()
		d.index = 0
		d.position = c + Vector2(15.0 * (i + 1), 0.0)
		d.relative = Vector2(15.0, 0.0)
		pv._gui_input(d)
	var up := InputEventScreenTouch.new()
	up.index = 0
	up.pressed = false
	up.position = c + Vector2(75.0, 0.0)
	pv._gui_input(up)
	if pv._origin != before:
		_drag_panned = true
	pv.pan_by(before - pv._origin)


# Two fingers down, then apart: the real pinch path, because `InputEventMagnifyGesture`
# is never emitted unless `enable_pan_and_scale_gestures` is on (it is off) and never on
# the web at all. Both touches start together and separate by `factor`.
# Tap a grid cell through the map's own input handling, so the test exercises the
# arm-then-tap path a player uses rather than the handler behind it.
func _tap_cell(pv: Node, cell: Vector2i) -> void:
	var pos: Vector2 = pv.world_to_screen(pv.cell_to_world(cell) + Vector2(pv.CELL, pv.CELL) * 0.5)
	var down := InputEventScreenTouch.new()
	down.index = 0
	down.pressed = true
	down.position = pos
	pv._gui_input(down)
	var up := InputEventScreenTouch.new()
	up.index = 0
	up.pressed = false
	up.position = pos
	pv._gui_input(up)


func _two_finger_pinch(pv: Node, factor: float) -> void:
	var c: Vector2 = pv.size * 0.5
	var half := 40.0
	var a := InputEventScreenTouch.new()
	a.index = 0
	a.pressed = true
	a.position = c - Vector2(half, 0.0)
	pv._gui_input(a)
	var b := InputEventScreenTouch.new()
	b.index = 1
	b.pressed = true
	b.position = c + Vector2(half, 0.0)
	pv._gui_input(b)
	for i in range(4):
		var t := float(i + 1) / 4.0
		var d := half * lerpf(1.0, factor, t)
		var da := InputEventScreenDrag.new()
		da.index = 0
		da.position = c - Vector2(d, 0.0)
		da.relative = Vector2(-(d - half) / 4.0, 0.0)
		pv._gui_input(da)
		var db := InputEventScreenDrag.new()
		db.index = 1
		db.position = c + Vector2(d, 0.0)
		db.relative = Vector2((d - half) / 4.0, 0.0)
		pv._gui_input(db)
	for idx in [0, 1]:
		var up := InputEventScreenTouch.new()
		up.index = idx
		up.pressed = false
		up.position = c
		pv._gui_input(up)


# A tab page scrolls vertically (its ScrollContainer disables horizontal scroll),
# so a control below the fold is reachable by scrolling but a control wider than the
# viewport is not. That is the bug the old menu had, so width is what is checked.
func _labels(n: Node) -> Array:
	var out: Array = []
	for c in n.get_children():
		if c is Label:
			out.append(c)
		out.append_array(_labels(c))
	return out


func _find_child(n: Node, type: Variant) -> Node:
	for c in n.get_children():
		if is_instance_of(c, type):
			return c
		var found := _find_child(c, type)
		if found != null:
			return found
	return null


func _check_page(name: String, page: Control, vp: Vector2i) -> void:
	var n := 0
	for b in _buttons(page):
		n += 1
		if not _fits_width(b, vp):
			_fail("%s: '%s' too wide at %s" % [name, _label_of(b), b.get_global_rect()])
	if n == 0:
		_fail("%s: no buttons found" % name)


# Every LineEdit must be inside a ScrollContainer with `follow_focus` set. Godot
# raises the soft keyboard by focusing a hidden EditText, and the window shrinks to
# make room for it; a scroll container that does not follow focus leaves the field
# where it was, under the keyboard. Also requires the field itself to be focusable,
# since a `mouse_filter` or focus-mode mistake makes the tap do nothing at all.
func _check_text_fields_follow_focus(n: Node, vp: Vector2i) -> void:
	for c in n.get_children():
		_check_text_fields_follow_focus(c, vp)
	if not (n is LineEdit):
		return
	var field := n as LineEdit
	if field.focus_mode == Control.FOCUS_NONE:
		_fail("text field '%s' is not focusable, so the keyboard can never open" % field.placeholder_text)
	var scroll := field.get_parent()
	while scroll != null and not (scroll is ScrollContainer):
		scroll = scroll.get_parent()
	if scroll == null:
		_fail("text field '%s' is not in a ScrollContainer" % field.placeholder_text)
	elif not (scroll as ScrollContainer).follow_focus:
		_fail("text field '%s' sits in a ScrollContainer without follow_focus" % field.placeholder_text)


# Every button in the editor that is not inside the sheet (the colours / piece panel).
# The sheet is an overlay that scrolls, so its buttons may sit below the fold; the
# header, the camera row and the palette are always on screen and are what the in-view
# check measures.
func _pinned_buttons(editor: Node) -> Array:
	var out: Array = []
	var skip: Node = editor.sheet
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


# WCAG relative luminance and contrast ratio, for text on a painted chip.
func _luminance(c: Color) -> float:
	var lin := func(x: float) -> float:
		return x / 12.92 if x <= 0.03928 else pow((x + 0.055) / 1.055, 2.4)
	return 0.2126 * lin.call(c.r) + 0.7152 * lin.call(c.g) + 0.0722 * lin.call(c.b)


func _contrast(a: Color, b: Color) -> float:
	var la := _luminance(a)
	var lb := _luminance(b)
	return (maxf(la, lb) + 0.05) / (minf(la, lb) + 0.05)


func _fits_width(c: Control, vp: Vector2i) -> bool:
	var r := c.get_global_rect()
	return r.position.x >= -1.0 and r.end.x <= vp.x + 1.0


func _label_of(b: Button) -> String:
	if b.text != "":
		return b.text.replace("\n", " / ")
	for c in b.get_children():
		if c is Label:
			return (c as Label).text
	# A picture tile has no text at all: its tooltip is the only name it carries.
	if b.tooltip_text != "":
		return b.tooltip_text
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
