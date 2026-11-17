extends Control

# Shown in the menu footer so a player can tell which build they are running
# (and a bug report can name it). Keep in step with the release tag.
const VERSION := "1.3"

# Port of the old js/app.js (removed with the JS client): the shell around the game. Menu, mode and track pickers,
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
var board_reals := []          # real runs on board_seed, as the server last returned
var board_reals_seed := 0
var endless_reals := []        # real endless runs, furthest first, as the server returned
var endless_loaded := false    # whether the server has answered for the endless board
var endless_page_no := 1
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
var overlay_cards := []        # the card columns, so a resize can re-widen them
var mode_buttons := {}         # "speedrun"/"endless" -> Button
var ghost_buttons := {}        # "off"/"wr"/"self" -> Button
var track_buttons := []        # one per track, in order
var car_buttons := []
var menu_track_button: Button
var tracks_sub: Label
var acct_bar: VBoxContainer
var lb_title: Label
var lb_note: Label
var lb_rows: VBoxContainer
var lb_page_label: Label
var lb_prev: Button
var lb_next: Button
var elb_title: Label
var elb_note: Label
var elb_rows: VBoxContainer
var elb_page_label: Label
var elb_prev: Button
var elb_next: Button
var btn_dead_board: Button
var btn_dead_watch: Button
var hist_sub: Label
var hist_rows: VBoxContainer
var acct_title: Label
var acct_user: LineEdit
var acct_email: LineEdit
var acct_pass: LineEdit
var acct_error: Label
var acct_submit: Button
var acct_toggle: Button
var dead_tag: Label
var dead_dist: Label
var dead_sub: Label
var dead_rank: Label
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
	ui_root.theme = UiTheme.build()
	layer.add_child(ui_root)

	_build_hud()
	_build_menu()
	_build_tracks()
	_build_board()
	_build_endless_board()
	_build_history()
	_build_account()
	_build_dead()
	_build_finish()
	_build_replay_done()
	_build_pause()

	_to_menu()
	_boot_account()

	# A screenshot hook for headless visual checks: `--shot <path> [--shot-menu]`
	# saves one frame and quits. Default shows a run in progress; `--shot-menu`
	# shows the menu instead.
	get_viewport().size_changed.connect(_layout_cards)
	_layout_cards()

	if OS.get_cmdline_user_args().has("--shot"):
		_capture_after(1.0)


func _capture_after(secs: float) -> void:
	var args := OS.get_cmdline_user_args()
	# `--shot-overlay <name>` opens one of the menu overlays for a headless layout
	# check; without it the shot is a run in progress (or the menu with --shot-menu).
	if args.has("--shot-overlay"):
		var which: String = args[args.find("--shot-overlay") + 1]
		match which:
			"tracks": _show_tracks()
			"board": _show_leaderboard(menu_seed)
			"endless": _show_endless_board()
			"history": _show_history()
			"account": _open_account("register")
			_: _to_menu()
	elif not args.has("--shot-menu"):
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


# A primary action (Play, Try again): drawn in the warm accent, so the thing a
# player most likely wants is the thing that stands out.
func _primary_button(text: String, cb: Callable) -> Button:
	var b := _button(text, cb)
	b.theme_type_variation = "PrimaryButton"
	return b


# A quiet secondary action (Back, Exit, the top-corner icons).
func _ghost_button(text: String, cb: Callable) -> Button:
	var b := _button(text, cb)
	b.theme_type_variation = "GhostButton"
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
#
# The card sits in a ScrollContainer, so an overlay taller than a short screen
# scrolls instead of running its bottom controls off the display where they cannot
# be pressed. That was the bug with the old menu: the card wanted 851px on an
# 820px-tall viewport and the account buttons below the fold were unreachable.
func _new_overlay(name: String, title: String = "") -> VBoxContainer:
	var root := Control.new()
	root.set_anchors_preset(Control.PRESET_FULL_RECT)
	root.visible = false
	ui_root.add_child(root)
	overlays[name] = root

	var bg := ColorRect.new()
	bg.color = Color(0, 0, 0, 0.62)
	bg.set_anchors_preset(Control.PRESET_FULL_RECT)
	root.add_child(bg)

	var scroll := ScrollContainer.new()
	scroll.set_anchors_preset(Control.PRESET_FULL_RECT)
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	root.add_child(scroll)

	var centre := CenterContainer.new()
	centre.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	centre.size_flags_vertical = Control.SIZE_EXPAND_FILL
	scroll.add_child(centre)

	var panel := PanelContainer.new()
	centre.add_child(panel)
	var margin := MarginContainer.new()
	for side in ["left", "right", "top", "bottom"]:
		margin.add_theme_constant_override("margin_" + side, 16)
	panel.add_child(margin)
	var col := _col(10)
	col.custom_minimum_size = Vector2(320, 0)
	margin.add_child(col)
	overlay_cards.append(col)
	if title != "":
		col.add_child(_card_title(title))
	return col


# Cards are sized for a phone portrait window by default, but on a wide desktop
# window the 420px logical card would float in a sea of background, so the width
# tracks the viewport between a floor (never narrower than a phone card) and a
# ceiling (never a full-width slab on an ultrawide monitor).
func _layout_cards() -> void:
	var vw := get_viewport_rect().size.x
	var w := clampf(vw * 0.46, 320.0, 520.0)
	for c in overlay_cards:
		c.custom_minimum_size = Vector2(w, 0)


# The heading of an overlay card: accent, a touch larger, and separated from the
# body so a card reads as a titled panel rather than a stack of rows.
func _card_title(text: String) -> Label:
	return _style_title(_label(text, 26))


# Accent-colour a heading label (used for the cards whose heading text changes at
# runtime: the account card and the run-end tags).
func _style_title(l: Label) -> Label:
	l.add_theme_color_override("font_color", UiTheme.ACCENT)
	l.custom_minimum_size = Vector2(0, 36)
	return l


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
	hud_dist.add_theme_constant_override("outline_size", 6)
	hud_dist.add_theme_color_override("font_outline_color", Color(0, 0, 0, 0.65))
	top.add_child(hud_dist)

	hud_sub = _label("best --", 20)
	hud_sub.add_theme_color_override("font_color", Color(1, 1, 1, 0.82))
	hud_sub.add_theme_constant_override("outline_size", 5)
	hud_sub.add_theme_color_override("font_outline_color", Color(0, 0, 0, 0.6))
	hud_sub.mouse_filter = Control.MOUSE_FILTER_IGNORE
	top.add_child(hud_sub)

	# Name the input the player actually has: a phone taps the screen, a desktop
	# holds the mouse or Space. A touch-first hint on a laptop reads as "I need a
	# touchscreen".
	var hint_text := "Hold anywhere to swing" if DisplayServer.is_touchscreen_available() else "Hold click or Space to swing"
	hint_label = _label(hint_text, 22)
	hint_label.add_theme_color_override("font_color", Color(1, 1, 1, 0.95))
	hint_label.add_theme_constant_override("outline_size", 6)
	hint_label.add_theme_color_override("font_outline_color", Color(0, 0, 0, 0.6))
	hint_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	hint_label.set_anchors_preset(Control.PRESET_CENTER)
	hint_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	ui_root.add_child(hint_label)

	btn_pause = _ghost_button("II", _on_pause)
	_anchor(btn_pause, Control.PRESET_TOP_RIGHT, 18, 64)
	btn_restart_round = _ghost_button("\u21bb", func(): _start_run(game.seed_num))
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
	var col := _new_overlay("menu", "SLINGDRIFT")
	var blurb := _label("Hold to swing round the poles. Let go to fly.\nDon't leave the road.", 14)
	blurb.add_theme_color_override("font_color", UiTheme.INK_DIM)
	col.add_child(blurb)

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
	var car_row := _row(6)
	col.add_child(car_row)
	_build_car_list(car_row)

	# Tracks live behind their own button now: a 13-cell grid made the menu taller
	# than the screen and buried the account controls below the fold.
	menu_track_button = _button("Tracks", _show_tracks)
	menu_track_button.custom_minimum_size = Vector2(0, 46)
	col.add_child(menu_track_button)
	tracks_sub = _label("", 13)
	tracks_sub.add_theme_color_override("font_color", UiTheme.INK_DIM)
	col.add_child(tracks_sub)

	var actions := _row(8)
	col.add_child(actions)
	actions.add_child(_primary_button("Play", func(): _start_run(menu_seed)))
	actions.add_child(_button("Leaderboard", _open_leaderboard))
	actions.add_child(_button("History", _show_history))

	acct_bar = _col(6)
	col.add_child(acct_bar)

	var foot := _label("Offline \u00b7 no ads \u00b7 your scores stay on this device", 11)
	foot.add_theme_color_override("font_color", UiTheme.INK_MUTE)
	col.add_child(foot)
	var ver := _label("v%s" % VERSION, 11)
	ver.add_theme_color_override("font_color", UiTheme.INK_MUTE)
	col.add_child(ver)


func _section(text: String) -> Label:
	var l := _label(text.to_upper(), 14)
	l.add_theme_color_override("font_color", UiTheme.ACCENT)
	return l


func _mode_button(parent: Node, title: String, sub: String, cb: Callable) -> Button:
	var b := Button.new()
	b.text = title + "\n" + sub
	b.toggle_mode = true
	b.theme_type_variation = "ToggleButton"
	b.custom_minimum_size = Vector2(0, 58)
	b.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	# Wrap rather than widen: three option buttons in a row are only as wide as their
	# longest word, so the menu card stays inside a phone-width viewport.
	b.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	b.pressed.connect(cb)
	parent.add_child(b)
	return b


func _build_car_list(parent: Node) -> void:
	car_buttons.clear()
	# A grid, not one long row: the picker stays inside a phone-width card. Each
	# cell shows the actual car sprite, so the choice is what you see, not a swatch.
	var grid := GridContainer.new()
	grid.columns = Renderer2D.CAR_MODELS.size()
	grid.add_theme_constant_override("h_separation", 6)
	grid.add_theme_constant_override("v_separation", 6)
	parent.add_child(grid)
	for i in range(Renderer2D.CAR_MODELS.size()):
		var idx := i
		var model: Dictionary = Renderer2D.CAR_MODELS[i]
		var b := Button.new()
		b.toggle_mode = true
		b.theme_type_variation = "ToggleButton"
		b.custom_minimum_size = Vector2(46, 58)
		b.tooltip_text = str(model["name"])
		var tex := TextureRect.new()
		tex.texture = load(str(model["tex"]))
		tex.set_anchors_preset(Control.PRESET_FULL_RECT)
		tex.offset_left = 9
		tex.offset_right = -9
		tex.offset_top = 9
		tex.offset_bottom = -9
		tex.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		tex.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
		tex.mouse_filter = Control.MOUSE_FILTER_IGNORE
		b.add_child(tex)
		b.pressed.connect(func():
			car_skin = idx
			Storage.set_pref("carSkin", idx)
			game.car_skin = idx
			game.renderer.car_index = idx
			_refresh_car_list())
		grid.add_child(b)
		car_buttons.append(b)


func _refresh_car_list() -> void:
	for i in range(car_buttons.size()):
		car_buttons[i].button_pressed = (i == car_skin)


func _build_track_list(parent: Node) -> void:
	track_buttons.clear()
	# Two columns: thirteen full-width rows is a long scroll, and a narrow grid cell
	# clipped a best time. Two is the compromise that keeps every label readable.
	var grid := GridContainer.new()
	grid.columns = 2
	grid.add_theme_constant_override("h_separation", 8)
	grid.add_theme_constant_override("v_separation", 8)
	parent.add_child(grid)
	for s in Tracks.MENU_TRACKS:
		var b := Button.new()
		b.toggle_mode = true
		b.custom_minimum_size = Vector2(0, 52)
		b.text = "Track %d\n--" % s
		# The button carries its own track number: the list has gaps now, so the
		# number is not the button's position and cannot be read back off the index.
		b.set_meta("track", s)
		b.pressed.connect(func():
			menu_seed = s
			Storage.set_pref("track", s)
			_refresh_track_list())
		grid.add_child(b)
		track_buttons.append(b)


# The Tracks overlay: its own card, so the menu does not have to carry thirteen
# buttons at once.
func _build_tracks() -> void:
	var col := _new_overlay("tracks", "Tracks")
	var hint := _label("Pick a track, then Play.", 13)
	hint.add_theme_color_override("font_color", UiTheme.INK_DIM)
	col.add_child(hint)
	var list := _col(6)
	col.add_child(list)
	_build_track_list(list)
	col.add_child(_button("Play this track", func():
		_start_run(menu_seed)))
	col.add_child(_button("Back", func(): _show_only("menu")))


func _show_tracks() -> void:
	_refresh_track_list()
	_show_only("tracks")


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
	if menu_track_button != null:
		menu_track_button.text = "Tracks  \u00b7  Track %d" % menu_seed
		var mode_word := "speedrun" if menu_mode == "speedrun" else "endless"
		tracks_sub.text = "Selected: Track %d \u00b7 %s" % [menu_seed, mode_word]


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
	var col := _new_overlay("board", "Leaderboard")
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
	# The server's real runs, when they are for this track. A local best is only
	# handed in when the server has not already listed the player, so they are not
	# drawn twice.
	var reals := _reals_for(seed)
	var listed := false
	for r in reals:
		if bool(r["you"]):
			listed = true
			break
	var page := Leaderboard.board_page(seed, board_page_no, null if listed else me, Leaderboard.PER_PAGE, reals)
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
				elif str(row.get("steps", "")) != "":
					# A real submitted run: no ghost id, it replays from its own steps.
					_watch_steps(seed, str(row["steps"]), str(row["name"]), float(row["time"]))
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
	# The page the player belongs on comes from their rank in the merged board, so
	# the real runs have to be counted. Before they load this is a first guess and
	# the board corrects it once they are in.
	var best: Variant = Storage.get_best_time(seed)
	var reals := _reals_for(seed)
	board_page_no = 1 if best == null else Leaderboard.page_for_rank(Leaderboard.player_rank(seed, float(best), reals))
	_render_board()
	_show_only("board")
	# Then fetch the real runs and re-render with them merged in. The local board is
	# drawn first so it is never blank while that loads.
	_load_reals(seed)

# =============================================================================
# Endless leaderboard
# =============================================================================
#
# One board, furthest distance wins. It reads the same way as a track board, but
# there is no track: the road is always the same one, so every run is comparable
# and the player has a single endless best.


func _build_endless_board() -> void:
	var col := _new_overlay("endless", "Endless leaderboard")
	elb_title = _label("Furthest distance", 20)
	col.add_child(elb_title)
	elb_note = _label("", 14)
	col.add_child(elb_note)

	var scroll := ScrollContainer.new()
	scroll.custom_minimum_size = Vector2(0, 300)
	col.add_child(scroll)
	elb_rows = _col(2)
	elb_rows.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll.add_child(elb_rows)

	var pager := _row(8)
	col.add_child(pager)
	elb_prev = _button("Prev", func():
		endless_page_no -= 1
		_render_endless_board())
	pager.add_child(elb_prev)
	elb_page_label = _label("1 / 1", 16)
	elb_page_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	elb_page_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	pager.add_child(elb_page_label)
	elb_next = _button("Next", func():
		endless_page_no += 1
		_render_endless_board())
	pager.add_child(elb_next)

	col.add_child(_button("Back", func(): _show_only("menu")))


func _render_endless_board() -> void:
	var best := float(Storage.get_endless().get("dist", 0.0))
	var me: Variant = null
	if best > 0.0:
		me = {"name": _player_name(), "dist": best}
	var listed := false
	for r in endless_reals:
		if bool((r as Dictionary).get("you", false)):
			listed = true
			break
	var page := Leaderboard.endless_page(endless_page_no, null if listed else me,
			Leaderboard.PER_PAGE, endless_reals)
	endless_page_no = int(page["page"])

	elb_title.text = "Furthest distance"
	if int(page["player_rank"]) > 0:
		elb_note.text = "You are #%d of %d" % [int(page["player_rank"]), int(page["total"])]
	elif not endless_loaded:
		elb_note.text = "Loading the board\u2026"
	else:
		elb_note.text = "%d racers \u00b7 set a distance to join" % int(page["total"])

	for c in elb_rows.get_children():
		c.queue_free()
	for r in page["rows"]:
		var text := "%d   %s   %s" % [int(r["rank"]), str(r["name"]), _fmt_dist(float(r["dist"]))]
		if bool(r["real"]) and bool(r["watchable"]):
			var row: Dictionary = r
			var b := _button(text + "   Watch", func():
				_watch_endless(str(row["steps"]), str(row["name"]), float(row["dist"])))
			elb_rows.add_child(b)
		elif bool(r["you"]):
			var row2: Dictionary = r
			var own: Variant = Storage.get_endless()
			if own.has("steps") and str(own["steps"]) != "":
				var b2 := _button(text + "   Replay", func():
					_watch_endless(str(own["steps"]), _player_name(), float(row2["dist"])))
				elb_rows.add_child(b2)
			else:
				elb_rows.add_child(_label(text + "   you", 14))
		else:
			elb_rows.add_child(_label(text, 14))

	elb_page_label.text = "%d / %d" % [int(page["page"]), int(page["pages"])]
	elb_prev.disabled = int(page["page"]) <= 1
	elb_next.disabled = int(page["page"]) >= int(page["pages"])


# The menu has one board button, and it opens the board for the selected mode.
# A separate endless button made the action row wider than a phone card.
func _open_leaderboard() -> void:
	if menu_mode == "endless":
		_show_endless_board()
	else:
		_show_leaderboard(menu_seed)


func _show_endless_board() -> void:
	var best := float(Storage.get_endless().get("dist", 0.0))
	endless_page_no = 1 if best <= 0.0 else Leaderboard.page_for_rank(
		Leaderboard.endless_rank(best, endless_reals))
	_render_endless_board()
	_show_only("endless")
	# Then fetch the real runs and re-render merged. The local board is drawn first
	# so it is never blank while that loads.
	_load_endless_reals()


# Fetch the real endless runs and re-render the endless board if it is showing.
func _load_endless_reals() -> void:
	var rows: Variant = await Api.fetch_endless_board()
	if rows == null:
		return
	var out := []
	for r in rows:
		var row: Dictionary = r
		out.append({
			"name": str(row.get("name", "")),
			"dist": float(row.get("metres", 0.0)),
			"ticks": int(row.get("ticks", 0)),
			"steps": row.get("steps"),
			"you": bool(row.get("you", false)),
		})
	endless_reals = out
	endless_loaded = true
	if overlay == "endless":
		_render_endless_board()


# Watch an endless run from its button steps. It replays on the endless road and
# ends where the car left it, exactly as the live run did.
func _watch_endless(steps: String, name: String, dist: float) -> void:
	watching = {
		"kind": "endless", "seed": 1, "ghost_id": null, "name": name, "time": dist,
		"steps": steps,
		"label": "%s's endless run" % name, "tag": "Endless run",
		"sub": "%s \u00b7 %s" % [name, _fmt_dist(dist)],
	}
	_hide_overlays()
	if not game.load_endless_replay(Replay.decode_steps(steps)):
		_end_watching()
		_to_menu()
		return
	_hud_reset()
	hint_label.visible = false
	_show_round_button(false)
	_show_watch_badge("Watching %s \u00b7 %s" % [name, _fmt_dist(dist)])
	game.start()




# =============================================================================
# History
# =============================================================================

func _build_history() -> void:
	var col := _new_overlay("history", "History")
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
	acct_title = _style_title(_label("Sign in", 26))
	col.add_child(acct_title)
	acct_user = LineEdit.new()
	acct_user.placeholder_text = "Username"
	col.add_child(acct_user)
	acct_email = LineEdit.new()
	acct_email.placeholder_text = "Email"
	col.add_child(acct_email)
	acct_pass = LineEdit.new()
	acct_pass.placeholder_text = "Password"
	acct_pass.secret = true
	col.add_child(acct_pass)
	acct_error = _label("", 14)
	acct_error.add_theme_color_override("font_color", UiTheme.DANGER)
	col.add_child(acct_error)
	acct_submit = _button("Sign in", func():
		if acct_mode == "name":
			_submit_name()
		else:
			_submit_account())
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
	acct_toggle.visible = true
	acct_error.text = ""
	acct_pass.text = ""
	# The username field is only for registering; signing in uses the email.
	acct_user.visible = acct_mode == "register"
	acct_email.visible = true
	var known := Account.list_accounts()
	acct_user.placeholder_text = "e.g. %s" % known[0] if known.size() > 0 else "Username"
	_show_only("account")


func _submit_account() -> void:
	acct_submit.disabled = true
	acct_error.text = ""
	var res: Dictionary
	if acct_mode == "register":
		res = await Account.register(acct_user.text, acct_email.text, acct_pass.text)
	else:
		res = await Account.login(acct_email.text, acct_pass.text)
	acct_submit.disabled = false
	if not bool(res.get("ok", false)):
		acct_error.text = str(res.get("error", "Could not sign in."))
		return
	# Confirmation is on: there is no session yet, so say so rather than pretending.
	if bool(res.get("pending", false)):
		acct_error.text = "Check your email to confirm, then sign in."
		return
	# Signed in, but the account has no public name yet. Ask for one.
	if bool(res.get("needs_name", false)):
		acct_error.text = "Pick a username to finish."
		acct_mode = "name"
		acct_title.text = "Choose a username"
		acct_submit.text = "Save name"
		acct_toggle.visible = false
		return
	await _after_sign_in()
	_show_only("menu")


# Pick the public name for an account that signed in without one.
func _submit_name() -> void:
	acct_submit.disabled = true
	acct_error.text = ""
	var made: Dictionary = await Account.ensure_profile(acct_user.text)
	acct_submit.disabled = false
	if not bool(made.get("ok", false)):
		acct_error.text = str(made.get("error", "Could not save that name."))
		return
	acct_toggle.visible = true
	await _after_sign_in()
	_show_only("menu")


# Everything that has to happen once a player is signed in: the bar and the track
# list change, their times come back from the server, and the guest queue can go.
func _after_sign_in() -> void:
	_refresh_account_bar()
	_refresh_track_list()
	await _sync_my_runs()
	await _flush_queue()


# Heal the account at boot, then pull its runs down.
#
# A session can come back without its username (a token refresh drops it, or the
# install predates the id -> name map). Records are keyed by that name, so without
# it the player would be shown the guest bucket and their best times would look
# gone, and a run set on another device would have no replay to watch. Resolve the
# name in the background and hydrate, exactly as the JS build does at boot. Boot
# never waits on the network and never throws.
func _boot_account() -> void:
	if not Account.signed_in():
		return
	var name := await Account.resolve_account()
	if name == "" and not Account.signed_in():
		return
	_refresh_account_bar()
	await _sync_my_runs()


# Pull the signed-in player's best times back from the server.
#
# The account is the source of truth, not the device: on a fresh install the local
# records are empty even though the account holds times. Merging is a lower-only
# write, so a better local time is never lost to a worse server one.
func _sync_my_runs() -> void:
	var runs: Variant = await Api.fetch_my_runs()
	if runs == null:
		return
	for r in runs:
		var row: Dictionary = r
		var seed := int(row["track"])
		var time := float(row["time"])
		var prev: Variant = Storage.get_best_time(seed)
		if prev == null or time < float(prev):
			Storage.save_best_time(seed, time)
		var steps: Variant = row.get("steps")
		if steps == null or str(steps) == "":
			continue
		# Store the replay whenever this device has none, not only when the server
		# time is the current best. A run set on another device has no local replay,
		# and without one the board cannot play it back.
		if Storage.get_replay(seed) == null:
			Storage.save_replay(seed, Replay.make_replay(seed, Replay.decode_steps(str(steps)), time))
	# The endless best lives on the server too. Pull it so a fresh install shows
	# the account's real distance, and keep the steps so it can be watched.
	var endless: Variant = await Api.fetch_my_endless()
	if endless is Dictionary:
		var ticks := int((endless as Dictionary)["ticks"])
		var dist := float(ticks) / 120.0 * Cfg.SPEED / Cfg.PX_PER_METRE
		var prev := float(Storage.get_endless().get("dist", 0.0))
		if dist > prev:
			Storage.save_endless(ticks, dist, 0, str((endless as Dictionary).get("steps", "")))
	_refresh_track_list()


# Send anything the queue is holding. A guest's runs wait here until they sign in.
func _flush_queue() -> void:
	if Api.queue_length() == 0:
		return
	var sent: Variant = await Api.flush()
	if sent == null:
		return
	var d: Dictionary = sent
	await _load_reals(int(d.get("track", board_seed)))
	_refresh_track_list()


# The real runs for a track, as the server last returned them, mapped to the shape
# the board merge wants. Empty when the server has not answered for this track.
func _reals_for(seed: int) -> Array:
	if board_reals_seed != seed:
		return []
	var out := []
	for r in board_reals:
		var row: Dictionary = r
		out.append({
			"name": str(row.get("name", "")),
			"time": float(row.get("time", 0.0)),
			"steps": row.get("steps"),
			"you": bool(row.get("you", false)),
		})
	return out


# Fetch a track's real runs and re-render whatever is showing them. Called after a
# run is uploaded and whenever the board is opened.
func _load_reals(seed: int) -> void:
	var rows: Variant = await Api.fetch_board(seed)
	if rows == null:
		return
	board_reals = rows
	board_reals_seed = seed
	# The player may have moved on while that was in flight, in which case there is
	# nothing on screen to re-render.
	if overlay == "board" and board_seed == seed:
		_render_board()


# =============================================================================
# Run-end overlays
# =============================================================================

func _build_dead() -> void:
	var col := _new_overlay("dead")
	dead_tag = _style_title(_label("Crashed", 26))
	col.add_child(dead_tag)
	dead_dist = _label("", 30)
	col.add_child(dead_dist)
	dead_sub = _label("", 16)
	col.add_child(dead_sub)
	dead_rank = _label("", 16)
	col.add_child(dead_rank)
	btn_dead_watch = _button("Watch my run", func():
		var own: Variant = Storage.get_endless()
		if own.has("steps") and str(own["steps"]) != "":
			_watch_endless(str(own["steps"]), _player_name(), float(own.get("dist", 0.0))))
	col.add_child(btn_dead_watch)
	btn_dead_board = _button("Leaderboard", func():
		if game.mode == "speedrun":
			_show_leaderboard(game.seed_num)
		else:
			_show_endless_board())
	col.add_child(btn_dead_board)
	col.add_child(_button("Try again", func(): _start_run(game.seed_num)))
	col.add_child(_button("Main menu", _to_menu))


func _build_finish() -> void:
	var col := _new_overlay("finish")
	finish_tag = _style_title(_label("Finished", 26))
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
		var wr = Leaderboard.world_record(game.seed_num, _reals_for(game.seed_num))
		if wr != null:
			_watch_wr(game.seed_num, wr))
	row.add_child(btn_finish_wr)
	col.add_child(_button("Leaderboard", func(): _show_leaderboard(game.seed_num)))
	col.add_child(_button("Run it again", func(): _start_run(game.seed_num)))
	col.add_child(_button("Main menu", _to_menu))


func _build_replay_done() -> void:
	var col := _new_overlay("replay_done")
	replay_tag = _style_title(_label("Replay", 26))
	col.add_child(replay_tag)
	replay_sub = _label("", 16)
	col.add_child(replay_sub)
	col.add_child(_button("Watch again", func():
		if watching == null:
			return
		var seed := int(watching["seed"])
		if watching["kind"] == "self":
			_watch_own_replay(seed)
		elif watching["kind"] == "steps":
			_watch_steps(seed, str(watching["steps"]), str(watching["name"]), float(watching["time"]))
		else:
			_watch_ghost(seed, int(watching["ghost_id"]),
				str(watching["name"]), float(watching["time"]))))
	col.add_child(_button("Leaderboard", func(): _show_leaderboard(game.seed_num)))
	col.add_child(_button("Main menu", _to_menu))


func _build_pause() -> void:
	var col := _new_overlay("pause", "Paused")
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
	var wr = Leaderboard.world_record(seed, _reals_for(seed))
	if wr == null:
		return
	# A real record has no ghost id; it replays from its stored steps instead.
	var steps: Variant = wr.get("steps")
	if steps != null and str(steps) != "":
		game.set_ghost_steps(seed, Replay.decode_steps(str(steps)), str(wr["name"]), float(wr["time"]))
	else:
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


# Watch the world record, whichever kind it is: a baked ghost regenerates from its
# id, a real one replays from the steps that travelled with it.
func _watch_wr(seed: int, wr: Dictionary) -> void:
	var steps: Variant = wr.get("steps")
	if steps != null and str(steps) != "":
		_watch_steps(seed, str(steps), str(wr["name"]), float(wr["time"]))
	else:
		_watch_ghost(seed, int(wr["ghost_id"]), str(wr["name"]), float(wr["time"]))


# Watch a run given as raw button steps.
func _watch_steps(seed: int, steps: String, name: String, time: float) -> void:
	watching = {
		"kind": "steps", "seed": seed, "ghost_id": null, "name": name, "time": time,
		"steps": steps,
		"label": "%s's ghost" % name, "tag": "Ghost run",
		"sub": "%s \u00b7 Track %d \u00b7 %s" % [name, seed, _fmt_time(time)],
	}
	_hide_overlays()
	game.replay_steps = Replay.decode_steps(steps)
	game.replay_index = 0
	game.load_track(seed, "replay")
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
		dead_rank.text = ""
		if game.mode == "speedrun":
			dead_tag.text = "Crashed"
			dead_dist.text = _fmt_time(game.run_time())
			var best: Variant = game.record_time()
			dead_sub.text = "best --" if best == null else "best %s" % _fmt_time(float(best))
			btn_dead_watch.visible = false
		else:
			var prev: Dictionary = extra["prev"]
			var beat := game.metres() > float(prev["dist"])
			dead_tag.text = "New best" if beat else "Crashed"
			dead_dist.text = _fmt_dist(game.metres())
			var best := maxf(float(prev["dist"]), game.metres())
			dead_sub.text = "best %s \u00b7 %d corners" % [_fmt_dist(best), game.car.grabbed]
			btn_dead_watch.visible = Storage.get_endless().has("steps")
			# Queue the endless run, then try to send it. Like a speedrun, nothing
			# here blocks play: the run is saved locally first.
			Api.enqueue(0, Replay.encode_steps(game.steps), _player_name(), "endless")
			_submit_endless_queued()
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
		var rank := Leaderboard.player_rank(game.seed_num, best2, _reals_for(game.seed_num))
		finish_rank.text = "#%d on Track %d" % [rank, game.seed_num] if rank > 0 else ""
		btn_watch.visible = Storage.get_replay(game.seed_num) != null
		btn_finish_wr.visible = Leaderboard.world_record(game.seed_num, _reals_for(game.seed_num)) != null
		_show_only("finish")
		hint_label.visible = false
		_show_round_button(false)
		# Queue the run, then try to send it. Nothing here blocks play: the run is
		# already saved locally, so a failure just leaves it queued.
		var seed_done := game.seed_num
		Api.enqueue(seed_done, Replay.encode_steps(game.steps), _player_name())
		_submit_queued(seed_done)


# Send queued runs, then refresh the finish card and the board against the merged
# board. The rank shown is the server's, not a local estimate.
func _submit_queued(seed: int) -> void:
	await Api.flush()
	await _load_reals(seed)
	if overlay != "finish" or game.seed_num != seed:
		return
	var best: Variant = Storage.get_best_time(seed)
	if best == null:
		return
	var reals := _reals_for(seed)
	var listed := false
	for r in reals:
		if bool(r["you"]):
			listed = true
			break
	var me: Variant = null if listed else {"name": _player_name(), "time": float(best)}
	var page := Leaderboard.board_page(seed, 1, me, Leaderboard.PER_PAGE, reals)
	var rank := int(page["player_rank"])
	finish_rank.text = "#%d on Track %d" % [rank, seed] if rank > 0 else ""
	btn_finish_wr.visible = Leaderboard.world_record(seed, reals) != null


# Send queued runs, then refresh the endless death card against the server board.
# The rank shown is the server's, not a local estimate.
func _submit_endless_queued() -> void:
	await Api.flush()
	await _load_endless_reals()
	if overlay != "dead" or game.mode != "endless":
		return
	var dist := game.metres()
	var rank := Leaderboard.endless_rank(dist, endless_reals)
	dead_rank.text = "#%d of %d" % [rank, int(Leaderboard.endless_page(1, null, Leaderboard.PER_PAGE, endless_reals)["total"])] if rank > 0 else ""


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
