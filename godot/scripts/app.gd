extends Control

# Port of js/app.js: the shell around the game. Menu, mode and track pickers,
# car skins, the leaderboard with watchable ghosts, run history, accounts, and
# the overlays for pause / crash / finish / replay-done.
#
# The simulation lives in Game (a Node2D) which draws itself through Renderer2D;
# this Control sits above it and owns only the interface. Background taps that
# miss a button reach _unhandled_input and drive the one-button mechanic, so the
# buttons never accidentally swing the car.

var game: Game

var menu_seed := 1
var menu_mode := "speedrun"
var ghost_mode := "off"
var car_skin := 0

var board_seed := 1
var board_page_no := 1
var watching: Variant = null   # {kind, seed, ghost_id, name, time, label, tag, sub}

var acct_mode := "login"
var overlay := ""              # the modal overlay currently shown, "" for none

var layer: CanvasLayer
var ui_root: Control

# --- nodes -------------------------------------------------------------------
var hud_dist: Label
var hud_sub: Label
var hint_label: Label
var btn_pause: Button
var btn_restart_round: Button
var watch_badge: PanelContainer
var watch_label: Label

var overlays := {}             # name -> Control (full-rect root)
var mode_buttons := {}         # "speedrun"/"endless" -> Button
var ghost_buttons := {}        # "off"/"wr"/"self" -> Button
var track_buttons := []        # one per track, in order
var car_buttons := []
var acct_bar: VBoxContainer
var lb_title: Label
var lb_note: Label
var lb_rows: VBoxContainer
var lb_page_label: Label
var lb_prev: Button
var lb_next: Button
var hist_sub: Label
var hist_rows: VBoxContainer
var acct_title: Label
var acct_user: LineEdit
var acct_pass: LineEdit
var acct_error: Label
var acct_submit: Button
var acct_toggle: Button
var dead_tag: Label
var dead_dist: Label
var dead_sub: Label
var finish_tag: Label
var finish_time: Label
var finish_sub: Label
var finish_rank: Label
var btn_watch: Button
var btn_finish_wr: Button
var replay_tag: Label
var replay_sub: Label


func _ready() -> void:
	menu_seed = int(Storage.get_pref("track", 1))
	if not Tracks.is_menu_track(menu_seed):
		menu_seed = 1
	menu_mode = str(Storage.get_pref("mode", "speedrun"))
	if menu_mode != "endless":
		menu_mode = "speedrun"
	ghost_mode = str(Storage.get_pref("ghostMode", "off"))
	if not ["off", "wr", "self"].has(ghost_mode):
		ghost_mode = "off"
	car_skin = int(Storage.get_pref("carSkin", 0))
	if car_skin < 0 or car_skin >= Renderer2D.CAR_MODELS.size():
		car_skin = 0

	game = Game.new()
	add_child(game)
	game.changed.connect(_on_game_change)
	game.ticked.connect(_on_tick)
	game.car_skin = car_skin

	layer = CanvasLayer.new()
	add_child(layer)
	ui_root = Control.new()
	ui_root.set_anchors_preset(Control.PRESET_FULL_RECT)
	ui_root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	layer.add_child(ui_root)

	_build_hud()
	_build_menu()
	_build_board()
	_build_history()
	_build_account()
	_build_dead()
	_build_finish()
	_build_replay_done()
	_build_pause()

	_to_menu()

	# A screenshot hook for headless visual checks: `--shot <path> [--shot-menu]`
	# saves one frame and quits. Default shows a run in progress; `--shot-menu`
	# shows the menu instead.
	if OS.get_cmdline_user_args().has("--shot"):
		_capture_after(1.0)


func _capture_after(secs: float) -> void:
	var args := OS.get_cmdline_user_args()
	if not args.has("--shot-menu"):
		_start_run(menu_seed)
	await get_tree().create_timer(secs).timeout
	var img := get_viewport().get_texture().get_image()
	var path: String = args[args.find("--shot") + 1] if args.size() > args.find("--shot") + 1 else "user://shot.png"
	img.save_png(path)
	print("saved ", path, " ", img.get_width(), "x", img.get_height())
	get_tree().quit()


# =============================================================================
# Small helpers
# =============================================================================

func _label(text: String, size: int) -> Label:
	var l := Label.new()
	l.text = text
	l.add_theme_font_size_override("font_size", size)
	return l


func _button(text: String, cb: Callable) -> Button:
	var b := Button.new()
	b.text = text
	b.pressed.connect(cb)
	return b


func _row(sep: int = 8) -> HBoxContainer:
	var h := HBoxContainer.new()
	h.add_theme_constant_override("separation", sep)
	return h


func _col(sep: int = 10) -> VBoxContainer:
	var v := VBoxContainer.new()
	v.add_theme_constant_override("separation", sep)
	return v


# A modal overlay: dim background, a centred card, and a returned column to fill.
func _new_overlay(name: String) -> VBoxContainer:
	var root := Control.new()
	root.set_anchors_preset(Control.PRESET_FULL_RECT)
	root.visible = false
	ui_root.add_child(root)
	overlays[name] = root

	var bg := ColorRect.new()
	bg.color = Color(0, 0, 0, 0.62)
	bg.set_anchors_preset(Control.PRESET_FULL_RECT)
	root.add_child(bg)

	var centre := CenterContainer.new()
	centre.set_anchors_preset(Control.PRESET_FULL_RECT)
	root.add_child(centre)

	var panel := PanelContainer.new()
	centre.add_child(panel)
	var margin := MarginContainer.new()
	for side in ["left", "right", "top", "bottom"]:
		margin.add_theme_constant_override("margin_" + side, 24)
	panel.add_child(margin)
	var col := _col(12)
	col.custom_minimum_size = Vector2(360, 0)
	margin.add_child(col)
	return col


func _show_only(name: String) -> void:
	for key in overlays:
		overlays[key].visible = (key == name)
	overlay = name


func _hide_overlays() -> void:
	for key in overlays:
		overlays[key].visible = false
	overlay = ""


func _show_round_button(on: bool) -> void:
	btn_restart_round.visible = on


func _show_watch_badge(text: String) -> void:
	watch_label.text = text
	watch_badge.visible = true


func _hide_watch_badge() -> void:
	watch_badge.visible = false


func _player_name() -> String:
	var who := Account.current_account()
	return who if who != "" else "You"


# =============================================================================
# HUD
# =============================================================================

func _build_hud() -> void:
	var top := _col(2)
	top.set_anchors_preset(Control.PRESET_TOP_WIDE)
	top.offset_left = 18
	top.offset_right = -96
	top.offset_top = 14
	top.mouse_filter = Control.MOUSE_FILTER_IGNORE
	ui_root.add_child(top)

	hud_dist = _label("0.000s", 44)
	hud_dist.mouse_filter = Control.MOUSE_FILTER_IGNORE
	top.add_child(hud_dist)

	hud_sub = _label("best --", 20)
	hud_sub.add_theme_color_override("font_color", Color(1, 1, 1, 0.75))
	hud_sub.mouse_filter = Control.MOUSE_FILTER_IGNORE
	top.add_child(hud_sub)

	hint_label = _label("Hold anywhere to swing", 22)
	hint_label.add_theme_color_override("font_color", Color(1, 1, 1, 0.9))
	hint_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	hint_label.set_anchors_preset(Control.PRESET_CENTER)
	hint_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	ui_root.add_child(hint_label)

	btn_pause = _button("II", _on_pause)
	_anchor(btn_pause, Control.PRESET_TOP_RIGHT, 18, 64)
	btn_restart_round = _button("\u21bb", func(): _start_run(game.seed_num))
	_anchor(btn_restart_round, Control.PRESET_TOP_LEFT, 18, 64)
	btn_restart_round.visible = false

	watch_badge = PanelContainer.new()
	watch_badge.set_anchors_preset(Control.PRESET_BOTTOM_WIDE)
	watch_badge.offset_left = 14
	watch_badge.offset_right = -14
	watch_badge.offset_bottom = -22
	watch_badge.visible = false
	ui_root.add_child(watch_badge)
	var wb := _row(8)
	watch_badge.add_child(wb)
	watch_label = _label("", 16)
	watch_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	wb.add_child(watch_label)
	wb.add_child(_button("Exit", _to_menu))
	wb.add_child(_button("\u00d7", func(): watch_badge.visible = false))


# Pin a square button to a top corner. `inset` is the gap from the corner; on the
# right the offsets are measured inward from the right edge, so both are negative.
func _anchor(b: Button, preset: int, inset: float, size: float) -> void:
	b.custom_minimum_size = Vector2(size, size)
	b.set_anchors_preset(preset)
	if preset == Control.PRESET_TOP_RIGHT:
		b.offset_right = -inset
		b.offset_left = -inset - size
	else:
		b.offset_left = inset
		b.offset_right = inset + size
	b.offset_top = inset
	b.offset_bottom = inset + size
	ui_root.add_child(b)


# =============================================================================
# Menu
# =============================================================================

func _build_menu() -> void:
	var col := _new_overlay("menu")
	col.add_child(_label("SLINGDRIFT", 40))
	col.add_child(_label("Hold to swing round the poles. Let go to fly.\nDon't leave the road.", 15))

	col.add_child(_section("Mode"))
	var mode_row := _row(8)
	col.add_child(mode_row)
	mode_buttons["speedrun"] = _mode_button(mode_row, "Speedrun", "~10s track, beat the clock",
		func(): _set_mode("speedrun"))
	mode_buttons["endless"] = _mode_button(mode_row, "Endless", "survive as long as you can",
		func(): _set_mode("endless"))

	col.add_child(_section("Ghost"))
	var ghost_row := _row(8)
	col.add_child(ghost_row)
	ghost_buttons["off"] = _mode_button(ghost_row, "Off", "just you and the clock",
		func(): _set_ghost("off"))
	ghost_buttons["wr"] = _mode_button(ghost_row, "World record", "race the fastest ghost",
		func(): _set_ghost("wr"))
	ghost_buttons["self"] = _mode_button(ghost_row, "Your best", "race your own ghost",
		func(): _set_ghost("self"))

	col.add_child(_section("Your car"))
	var car_row := _row(8)
	col.add_child(car_row)
	_build_car_list(car_row)

	col.add_child(_section("Pick a track"))
	var track_scroll := ScrollContainer.new()
	track_scroll.custom_minimum_size = Vector2(0, 190)
	col.add_child(track_scroll)
	var track_grid := GridContainer.new()
	track_grid.columns = 5
	track_grid.add_theme_constant_override("h_separation", 6)
	track_grid.add_theme_constant_override("v_separation", 6)
	track_scroll.add_child(track_grid)
	_build_track_list(track_grid)

	var actions := _row(8)
	col.add_child(actions)
	actions.add_child(_button("Play", func(): _start_run(menu_seed)))
	actions.add_child(_button("Leaderboard", func(): _show_leaderboard(menu_seed)))
	actions.add_child(_button("History", _show_history))

	acct_bar = _col(6)
	col.add_child(acct_bar)

	col.add_child(_label("Offline \u00b7 no ads \u00b7 your scores stay on this device", 12))


func _section(text: String) -> Label:
	var l := _label(text, 18)
	l.add_theme_color_override("font_color", Color(1, 1, 1, 0.6))
	return l


func _mode_button(parent: Node, title: String, sub: String, cb: Callable) -> Button:
	var b := Button.new()
	b.text = title + "\n" + sub
	b.toggle_mode = true
	b.custom_minimum_size = Vector2(0, 58)
	b.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	b.pressed.connect(cb)
	parent.add_child(b)
	return b


func _build_car_list(parent: Node) -> void:
	car_buttons.clear()
	for i in range(Renderer2D.CAR_MODELS.size()):
		var idx := i
		var b := Button.new()
		b.toggle_mode = true
		b.custom_minimum_size = Vector2(40, 40)
		var sw := ColorRect.new()
		sw.color = Renderer2D.CAR_MODELS[i]["body"]
		sw.set_anchors_preset(Control.PRESET_FULL_RECT)
		sw.offset_left = 8
		sw.offset_top = 8
		sw.offset_right = -8
		sw.offset_bottom = -8
		sw.mouse_filter = Control.MOUSE_FILTER_IGNORE
		b.add_child(sw)
		b.pressed.connect(func():
			car_skin = idx
			Storage.set_pref("carSkin", idx)
			game.car_skin = idx
			game.renderer.car_index = idx
			_refresh_car_list())
		parent.add_child(b)
		car_buttons.append(b)


func _refresh_car_list() -> void:
	for i in range(car_buttons.size()):
		car_buttons[i].button_pressed = (i == car_skin)


func _build_track_list(parent: Node) -> void:
	track_buttons.clear()
	for s in Tracks.MENU_TRACKS:
		var b := Button.new()
		b.toggle_mode = true
		b.custom_minimum_size = Vector2(62, 54)
		b.text = "Track %d\n--" % s
		# The button carries its own track number: the list has gaps now, so the
		# number is not the button's position and cannot be read back off the index.
		b.set_meta("track", s)
		b.pressed.connect(func():
			menu_seed = s
			Storage.set_pref("track", s)
			_refresh_track_list())
		parent.add_child(b)
		track_buttons.append(b)


func _refresh_track_list() -> void:
	for b in track_buttons:
		var s: int = b.get_meta("track")
		var best: Variant = Storage.get_best_time(s) if menu_mode == "speedrun" else null
		var rec := Storage.get_record(s)
		var sub := "--"
		if menu_mode == "speedrun":
			sub = "--" if best == null else _fmt_time(float(best))
		else:
			sub = _fmt_dist(float(rec["dist"])) if float(rec["dist"]) > 0.0 else "--"
		b.text = "Track %d\n%s" % [s, sub]
		b.button_pressed = (s == menu_seed)


func _refresh_mode_list() -> void:
	for key in mode_buttons:
		mode_buttons[key].button_pressed = (key == menu_mode)
	for key in ghost_buttons:
		ghost_buttons[key].button_pressed = (key == ghost_mode)
	_refresh_car_list()


func _set_mode(m: String) -> void:
	menu_mode = m
	Storage.set_pref("mode", m)
	_refresh_mode_list()
	_refresh_track_list()


func _set_ghost(g: String) -> void:
	ghost_mode = g
	Storage.set_pref("ghostMode", g)
	_refresh_mode_list()


func _refresh_account_bar() -> void:
	for c in acct_bar.get_children():
		c.queue_free()
	var who := Account.current_account()
	var label := _label("Signed in as %s" % who if who != "" else "Playing as guest", 15)
	label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	acct_bar.add_child(label)
	var row := _row(6)
	acct_bar.add_child(row)
	row.add_child(_button("Switch" if who != "" else "Sign in",
		func(): _open_account("switch" if who != "" else "login")))
	if who != "":
		row.add_child(_button("Sign out", func():
			Account.logout()
			_refresh_account_bar()
			_refresh_track_list()))


# =============================================================================
# Leaderboard
# =============================================================================

func _build_board() -> void:
	var col := _new_overlay("board")
	col.add_child(_label("Leaderboard", 24))
	lb_title = _label("Track 1", 20)
	col.add_child(lb_title)
	lb_note = _label("", 14)
	col.add_child(lb_note)

	var scroll := ScrollContainer.new()
	scroll.custom_minimum_size = Vector2(0, 300)
	col.add_child(scroll)
	lb_rows = _col(2)
	lb_rows.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll.add_child(lb_rows)

	var pager := _row(8)
	col.add_child(pager)
	lb_prev = _button("Prev", func():
		board_page_no -= 1
		_render_board())
	pager.add_child(lb_prev)
	lb_page_label = _label("1 / 1", 16)
	lb_page_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	lb_page_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	pager.add_child(lb_page_label)
	lb_next = _button("Next", func():
		board_page_no += 1
		_render_board())
	pager.add_child(lb_next)

	col.add_child(_button("Back", func(): _show_only("menu")))


func _render_board() -> void:
	var seed := board_seed
	var best: Variant = Storage.get_best_time(seed)
	var me: Variant = null
	if best != null:
		me = {"name": _player_name(), "time": float(best)}
	var page := Leaderboard.board_page(seed, board_page_no, me)
	board_page_no = int(page["page"])

	lb_title.text = "Track %d" % seed
	if int(page["player_rank"]) > 0:
		lb_note.text = "You are #%d of %d" % [int(page["player_rank"]), int(page["total"])]
	else:
		lb_note.text = "%d racers \u00b7 set a time to join" % int(page["total"])

	for c in lb_rows.get_children():
		c.queue_free()
	for r in page["rows"]:
		var can_watch: bool = bool(r["you"]) or bool(r["watchable"])
		var text := "%d   %s   %s" % [int(r["rank"]), str(r["name"]), _fmt_time(float(r["time"]))]
		if can_watch:
			var action := "Replay" if bool(r["you"]) else "Watch"
			var row: Dictionary = r
			var b := _button(text + "   " + action, func():
				if bool(row["you"]):
					_watch_own_replay(seed)
				else:
					_watch_ghost(seed, int(row["ghost_id"]), str(row["name"]), float(row["time"])))
			lb_rows.add_child(b)
		else:
			lb_rows.add_child(_label(text, 14))

	lb_page_label.text = "%d / %d" % [int(page["page"]), int(page["pages"])]
	lb_prev.disabled = int(page["page"]) <= 1
	lb_next.disabled = int(page["page"]) >= int(page["pages"])


func _show_leaderboard(seed: int) -> void:
	board_seed = seed
	var best: Variant = Storage.get_best_time(seed)
	board_page_no = 1 if best == null else Leaderboard.page_for_rank(Leaderboard.player_rank(seed, float(best)))
	_render_board()
	_show_only("board")


# =============================================================================
# History
# =============================================================================

func _build_history() -> void:
	var col := _new_overlay("history")
	col.add_child(_label("History", 24))
	hist_sub = _label("", 14)
	col.add_child(hist_sub)
	var scroll := ScrollContainer.new()
	scroll.custom_minimum_size = Vector2(0, 320)
	col.add_child(scroll)
	hist_rows = _col(2)
	hist_rows.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll.add_child(hist_rows)
	col.add_child(_button("Back", func(): _show_only("menu")))


func _show_history() -> void:
	var runs := Storage.all_runs()
	var who := Account.current_account()
	if runs.size() > 0:
		hist_sub.text = "%s \u00b7 %d finished runs" % [who if who != "" else "Guest", runs.size()]
	else:
		hist_sub.text = "No finished runs yet."
	for c in hist_rows.get_children():
		c.queue_free()
	for i in range(mini(runs.size(), 60)):
		var r: Dictionary = runs[i]
		var seed := int(r["seed"])
		var best: Variant = Storage.get_best_time(seed)
		var pb := best != null and absf(float(r["time"]) - float(best)) < 1e-9
		hist_rows.add_child(_label("Track %d   %s   %s   %s" % [
			seed, "Personal best" if pb else "Finished",
			_fmt_time(float(r["time"])), _ago(float(r["at"]))], 14))
	_show_only("history")


# =============================================================================
# Accounts
# =============================================================================

func _build_account() -> void:
	var col := _new_overlay("account")
	acct_title = _label("Sign in", 24)
	col.add_child(acct_title)
	acct_user = LineEdit.new()
	acct_user.placeholder_text = "Username"
	col.add_child(acct_user)
	acct_pass = LineEdit.new()
	acct_pass.placeholder_text = "Password"
	acct_pass.secret = true
	col.add_child(acct_pass)
	acct_error = _label("", 14)
	acct_error.add_theme_color_override("font_color", Color(1, 0.4, 0.4))
	col.add_child(acct_error)
	acct_submit = _button("Sign in", _submit_account)
	col.add_child(acct_submit)
	acct_toggle = _button("Create an account", func():
		_open_account("login" if acct_mode == "register" else "register"))
	col.add_child(acct_toggle)
	col.add_child(_button("Back", func(): _show_only("menu")))


func _open_account(mode: String) -> void:
	acct_mode = "register" if mode == "register" else "login"
	acct_title.text = "Create an account" if acct_mode == "register" else "Sign in"
	acct_submit.text = "Create account" if acct_mode == "register" else "Sign in"
	acct_toggle.text = "I already have an account" if acct_mode == "register" else "Create an account"
	acct_error.text = ""
	acct_pass.text = ""
	var known := Account.list_accounts()
	acct_user.placeholder_text = "e.g. %s" % known[0] if known.size() > 0 else "Username"
	_show_only("account")


func _submit_account() -> void:
	var res := Account.register(acct_user.text, acct_pass.text) if acct_mode == "register" \
		else Account.login(acct_user.text, acct_pass.text)
	if not bool(res["ok"]):
		acct_error.text = str(res["error"])
		return
	_refresh_account_bar()
	_refresh_track_list()
	_show_only("menu")


# =============================================================================
# Run-end overlays
# =============================================================================

func _build_dead() -> void:
	var col := _new_overlay("dead")
	dead_tag = _label("Crashed", 26)
	col.add_child(dead_tag)
	dead_dist = _label("", 30)
	col.add_child(dead_dist)
	dead_sub = _label("", 16)
	col.add_child(dead_sub)
	col.add_child(_button("Try again", func(): _start_run(game.seed_num)))
	col.add_child(_button("Main menu", _to_menu))


func _build_finish() -> void:
	var col := _new_overlay("finish")
	finish_tag = _label("Finished", 26)
	col.add_child(finish_tag)
	finish_time = _label("", 30)
	col.add_child(finish_time)
	finish_sub = _label("", 16)
	col.add_child(finish_sub)
	finish_rank = _label("", 16)
	col.add_child(finish_rank)
	var row := _row(8)
	col.add_child(row)
	btn_watch = _button("Watch my replay", func(): _watch_own_replay(game.seed_num))
	row.add_child(btn_watch)
	btn_finish_wr = _button("Watch world record", func():
		var wr = Leaderboard.world_record(game.seed_num)
		if wr != null:
			_watch_ghost(game.seed_num, int(wr["ghost_id"]), str(wr["name"]), float(wr["time"])))
	row.add_child(btn_finish_wr)
	col.add_child(_button("Leaderboard", func(): _show_leaderboard(game.seed_num)))
	col.add_child(_button("Run it again", func(): _start_run(game.seed_num)))
	col.add_child(_button("Main menu", _to_menu))


func _build_replay_done() -> void:
	var col := _new_overlay("replay_done")
	replay_tag = _label("Replay", 26)
	col.add_child(replay_tag)
	replay_sub = _label("", 16)
	col.add_child(replay_sub)
	col.add_child(_button("Watch again", func():
		if watching == null:
			return
		if watching["kind"] == "self":
			_watch_own_replay(int(watching["seed"]))
		else:
			_watch_ghost(int(watching["seed"]), int(watching["ghost_id"]),
				str(watching["name"]), float(watching["time"]))))
	col.add_child(_button("Leaderboard", func(): _show_leaderboard(game.seed_num)))
	col.add_child(_button("Main menu", _to_menu))


func _build_pause() -> void:
	var col := _new_overlay("pause")
	col.add_child(_label("Paused", 26))
	col.add_child(_button("Resume", func():
		_hide_overlays()
		game.state = "running"
		_show_round_button(not game.is_replay())))
	col.add_child(_button("Restart run", func(): _start_run(game.seed_num)))
	col.add_child(_button("Main menu", _to_menu))


# =============================================================================
# Flow
# =============================================================================

func _to_menu() -> void:
	_end_watching()
	game.set_physics_process(false)
	game.load_track(menu_seed, menu_mode)
	_refresh_mode_list()
	_refresh_account_bar()
	_refresh_track_list()
	_show_round_button(false)
	hint_label.visible = false
	_show_only("menu")


func _start_run(seed: int) -> void:
	_end_watching()
	_hide_overlays()
	game.load_track(seed, menu_mode)
	_apply_ghost(seed)
	_hud_reset()
	hint_label.visible = true
	_show_round_button(true)
	game.start()


func _apply_ghost(seed: int) -> void:
	if menu_mode != "speedrun" or ghost_mode == "off":
		return
	if ghost_mode == "self":
		game.set_ghost_self(seed)
		return
	var wr = Leaderboard.world_record(seed)
	if wr != null:
		game.set_ghost_replay(seed, int(wr["ghost_id"]), str(wr["name"]), float(wr["time"]))


func _watch_own_replay(seed: int) -> void:
	if Storage.get_replay(seed) == null:
		return
	var best: Variant = Storage.get_best_time(seed)
	watching = {
		"kind": "self", "seed": seed, "ghost_id": null, "name": null, "time": float(best),
		"label": "%s's best" % _player_name(), "tag": "Your best run",
		"sub": "Track %d \u00b7 %s" % [seed, _fmt_time(float(best))],
	}
	_hide_overlays()
	if not game.load_replay(seed):
		_end_watching()
		return
	_hud_reset()
	hint_label.visible = false
	_show_round_button(false)
	_show_watch_badge("Watching your best \u00b7 %s" % _fmt_time(float(best)))
	game.start()


func _watch_ghost(seed: int, ghost_id: int, name: String, time: float) -> void:
	watching = {
		"kind": "ghost", "seed": seed, "ghost_id": ghost_id, "name": name, "time": time,
		"label": "%s's ghost" % name, "tag": "Ghost run",
		"sub": "%s \u00b7 Track %d \u00b7 %s" % [name, seed, _fmt_time(time)],
	}
	_hide_overlays()
	if not game.load_ghost_replay(seed, ghost_id):
		_end_watching()
		_to_menu()
		return
	_hud_reset()
	hint_label.visible = false
	_show_round_button(false)
	_show_watch_badge("Watching %s \u00b7 %s" % [name, _fmt_time(time)])
	game.start()


func _end_watching() -> void:
	watching = null
	_hide_watch_badge()


# =============================================================================
# Game callbacks
# =============================================================================

func _on_game_change(extra: Dictionary) -> void:
	if game.is_replay():
		if bool(extra.get("died", false)):
			_end_watching()
			_to_menu()
			return
		if bool(extra.get("finished", false)):
			replay_tag.text = str(watching["tag"]) if watching != null else "Replay"
			replay_sub.text = str(watching["sub"]) if watching != null else "That run, replayed."
			_hide_watch_badge()
			_show_only("replay_done")
		return

	if bool(extra.get("died", false)):
		if game.mode == "speedrun":
			dead_tag.text = "Crashed"
			dead_dist.text = _fmt_time(game.run_time())
			var best: Variant = game.record_time()
			dead_sub.text = "best --" if best == null else "best %s" % _fmt_time(float(best))
		else:
			var prev: Dictionary = extra["prev"]
			var beat := game.metres() > float(prev["dist"])
			dead_tag.text = "New best" if beat else "Crashed"
			dead_dist.text = _fmt_dist(game.metres())
			var best := maxf(float(prev["dist"]), game.metres())
			dead_sub.text = "best %s \u00b7 %d corners" % [_fmt_dist(best), game.car.grabbed]
		_show_only("dead")
		hint_label.visible = false
		_show_round_button(false)

	if bool(extra.get("finished", false)):
		var prev2: Variant = extra["prev"]
		var beat2 := prev2 == null or game.run_time() < float(prev2)
		finish_tag.text = "New best time" if beat2 else "Finished"
		finish_time.text = _fmt_time(game.run_time())
		var best2 := game.run_time() if prev2 == null else minf(float(prev2), game.run_time())
		finish_sub.text = "best %s" % _fmt_time(best2)
		var rank := Leaderboard.player_rank(game.seed_num, best2)
		finish_rank.text = "#%d on Track %d" % [rank, game.seed_num] if rank > 0 else ""
		btn_watch.visible = Storage.get_replay(game.seed_num) != null
		btn_finish_wr.visible = Leaderboard.world_record(game.seed_num) != null
		_show_only("finish")
		hint_label.visible = false
		_show_round_button(false)


func _on_tick() -> void:
	if game.is_replay():
		hud_dist.text = _fmt_time(game.run_time())
		hud_sub.text = "%s \u00b7 Track %d" % [str(watching["label"]), game.seed_num] \
			if watching != null else "replay \u00b7 Track %d" % game.seed_num
		return
	if game.mode == "speedrun":
		hud_dist.text = _fmt_time(game.run_time())
		var best: Variant = game.record_time()
		hud_sub.text = "best --" if best == null else "best %s" % _fmt_time(float(best))
	else:
		hud_dist.text = _fmt_dist(game.metres())
		hud_sub.text = "best %s" % _fmt_dist(maxf(float(game.record_dist()), game.metres()))
	if game.car.grabbed > 0 or game.car.time > 1.2:
		hint_label.visible = false


func _hud_reset() -> void:
	if game.is_replay():
		hud_dist.text = "0.000s"
		hud_sub.text = "%s \u00b7 Track %d" % [str(watching["label"]), game.seed_num] \
			if watching != null else "replay \u00b7 Track %d" % game.seed_num
	elif game.mode == "speedrun":
		hud_dist.text = "0.000s"
		var best: Variant = Storage.get_best_time(game.seed_num)
		hud_sub.text = "best --" if best == null else "best %s" % _fmt_time(float(best))
	else:
		hud_dist.text = "0 m"
		hud_sub.text = "best %s" % _fmt_dist(float(Storage.get_record(game.seed_num)["dist"]))


func _on_pause() -> void:
	if game.state == "running":
		game.state = "paused"
		_show_only("pause")
		_show_round_button(false)


# =============================================================================
# Input: one button, anywhere that is not a control
# =============================================================================

func _unhandled_input(event: InputEvent) -> void:
	var down := false
	var up := false
	if event is InputEventScreenTouch:
		down = event.pressed
		up = not event.pressed
	elif event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT:
		down = event.pressed
		up = not event.pressed
	elif event is InputEventKey and (event.keycode == KEY_SPACE or event.keycode == KEY_UP):
		down = event.pressed
		up = not event.pressed
	if not down and not up:
		return
	if overlay != "" or game.is_replay():
		return
	if game.state == "dead" or game.state == "finished":
		return
	if game.state == "ready":
		_start_run(game.seed_num)
	if down:
		game.set_held(true)
	elif up:
		game.set_held(false)


# =============================================================================
# Formatting
# =============================================================================

func _fmt_time(s: float) -> String:
	return "%.3fs" % s


func _fmt_dist(metres: float) -> String:
	return "%d m" % roundi(metres)


func _ago(at_ms: float) -> String:
	var s := maxf(0.0, (float(Time.get_unix_time_from_system()) * 1000.0 - at_ms) / 1000.0)
	if s < 60.0:
		return "just now"
	if s < 3600.0:
		return "%dm ago" % int(s / 60.0)
	if s < 86400.0:
		return "%dh ago" % int(s / 3600.0)
	return "%dd ago" % int(s / 86400.0)
