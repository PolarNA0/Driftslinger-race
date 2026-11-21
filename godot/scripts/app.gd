extends Control

# Shown on the Settings screen so a player can tell which build they are running
# (and a bug report can name it). Keep in step with the release tag.
const VERSION := "1.6"

# The shell around the game: a full-screen, tabbed menu (Play / Garage / Editor /
# Account, with Settings in the top bar), the track editor, the leaderboard, run
# history, accounts, and the overlays for pause / crash / finish / replay-done.
#
# The simulation lives in Game (a Node2D) which draws itself through Renderer2D;
# this Control sits above it and owns only the interface. Background taps that
# miss a button reach _unhandled_input and drive the one-button mechanic, so the
# buttons never accidentally swing the car.

var game: Game

var shell: MenuShell                 # the full-screen frame (top bar, tabs, content)
var tab_pages := {}                  # tab name -> Control
var tab_cols := []                   # the scroll columns inside tab pages, for resize
var mode_bar: HBoxContainer
var play_track_label: Label
var play_best_label: Label
var track_section: VBoxContainer     # the track chooser, hidden in endless
var car_preview: TextureRect
var car_name_label: Label
var acct_overview: VBoxContainer     # the account tab's summary, rebuilt on sign in/out
var acct_form: VBoxContainer         # the sign-in form, shown on demand
var settings_col: VBoxContainer
var key_buttons := {}                # "play"/"reset"/"pause" -> the rebind button
var key_capturing := ""              # which binding a key press will capture, "" for none
var input_key := KEY_SPACE           # the bound play key on a desktop keyboard
var reset_key := KEY_R               # restarts the current run
var pause_key := KEY_ESCAPE          # pauses and resumes the current run

var menu_seed := 1
var menu_mode := "speedrun"
var ghost_mode := "off"
var car_skin := 0

var editor: TrackEditor           # the full-screen track editor overlay
var editor_list: VBoxContainer    # the Editor tab's track rows
var custom_section: VBoxContainer # "My tracks" on the Play tab
var custom_list: VBoxContainer    # the custom-track rows on the Play tab

var dlg_root: Control             # the shared prompt/confirm dialog
var dlg_title: Label
var dlg_body: Label
var dlg_input: LineEdit
var dlg_ok: Button
var dlg_cancel: Button
var dlg_accept: Callable = Callable()

var board_seed := 1
var board_mode := "speedrun"   # "speedrun" ranks times, "endless" ranks distances
var board_page_no := 1
var board_reals := []          # real runs on board_seed, as the server last returned
var board_reals_seed := 0
var board_reals_mode := ""     # the mode board_reals belongs to, so seed 7 speedrun
                               # and seed 7 endless are never confused
var watching: Variant = null   # {kind, seed, name, time, label, tag, sub}

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
var ghost_buttons := {}        # "off"/"self" -> Button
var track_buttons := []        # one per track, in order
var track_pb_labels := {}      # track number -> the Label under it showing the best
var car_buttons := []
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
var acct_email: LineEdit
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
var btn_finish_lb: Button
var replay_tag: Label
var replay_sub: Label


func _ready() -> void:
	menu_seed = int(Storage.get_pref("track", 1))
	# A built-in track number, or one of the player's own tracks. A custom id whose
	# track has been deleted falls back to track 1 rather than loading nothing.
	if not Tracks.is_menu_track(menu_seed) and not CustomTracks.has(menu_seed):
		menu_seed = 1
	menu_mode = str(Storage.get_pref("mode", "speedrun"))
	if menu_mode != "endless":
		menu_mode = "speedrun"
	ghost_mode = str(Storage.get_pref("ghostMode", "off"))
	# The baked-record ghost is gone; an old preference for it falls back to off.
	if not ["off", "self"].has(ghost_mode):
		ghost_mode = "off"
	car_skin = int(Storage.get_pref("carSkin", 0))
	if car_skin < 0 or car_skin >= Renderer2D.CAR_MODELS.size():
		car_skin = 0
	# The desktop keys, rebindable in Settings. Space to play, R to reset, Esc to
	# pause. The defaults live here so a fresh install has them without a pref write.
	input_key = int(Storage.get_pref("inputKey", KEY_SPACE))
	reset_key = int(Storage.get_pref("resetKey", KEY_R))
	pause_key = int(Storage.get_pref("pauseKey", KEY_ESCAPE))

	game = Game.new()
	add_child(game)
	game.changed.connect(_on_game_change)
	game.ticked.connect(_on_tick)
	game.car_skin = car_skin
	# A custom track id resolves to its op list; a built-in track needs no provider.
	game.opts_provider = func(seed: int) -> Dictionary: return CustomTracks.opts_for_id(seed)

	layer = CanvasLayer.new()
	add_child(layer)
	ui_root = Control.new()
	ui_root.set_anchors_preset(Control.PRESET_FULL_RECT)
	ui_root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	ui_root.theme = UiTheme.build()
	layer.add_child(ui_root)

	_build_hud()
	_build_shell()
	_build_dialog()
	_build_board()
	_build_history()
	_build_dead()
	_build_finish()
	_build_replay_done()
	_build_pause()

	_to_menu()
	_boot_account()

	# A screenshot hook for headless visual checks: `--shot <path> [--shot-menu]`
	# saves one frame and quits. Default shows a run in progress; `--shot-menu`
	# shows the menu instead. `--shot-tab <garage|play|account|settings>` opens a tab.
	get_viewport().size_changed.connect(_layout_cards)
	_layout_cards()

	if OS.get_cmdline_user_args().has("--shot"):
		_capture_after(1.0)


func _capture_after(secs: float) -> void:
	var args := OS.get_cmdline_user_args()
	if args.has("--shot-tab"):
		var which: String = args[args.find("--shot-tab") + 1]
		match which:
			"garage", "play", "account", "editor":
				_to_menu()
				shell.select(which)
			"settings":
				_to_menu()
				_open_settings()
			_: _to_menu()
	elif args.has("--shot-overlay"):
		var which: String = args[args.find("--shot-overlay") + 1]
		match which:
			"tracks": _show_tracks()
			"board": _show_leaderboard(menu_seed)
			"history": _show_history()
			"account": _to_menu(); shell.select("account")
			"editor":
				# The editor is the one screen whose whole point is how it looks, so it
				# needs a headless shot like the menu has. A new track has no pieces,
				# which is exactly the empty canvas a player first sees.
				var t: Variant = CustomTracks.new_track()
				if t != null:
					_open_editor(int(t["id"]))
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


# The round restart button: a ghost chip at the bottom centre carrying a drawn
# retry icon. The icon is geometry rather than a character because the theme font
# has no rotation arrow (see retry_icon.gd), and a missing glyph reads as a box.
func _round_icon_button(cb: Callable) -> Button:
	var size := 52.0
	var b := Button.new()
	b.theme_type_variation = "GhostButton"
	b.focus_mode = Control.FOCUS_NONE
	b.custom_minimum_size = Vector2(size, size)
	b.set_anchors_preset(Control.PRESET_CENTER_BOTTOM)
	b.offset_left = -size / 2.0
	b.offset_right = size / 2.0
	b.offset_top = -size - 22.0
	b.offset_bottom = -22.0
	b.pressed.connect(cb)
	var icon := RetryIcon.new()
	icon.color = UiTheme.INK
	icon.mouse_filter = Control.MOUSE_FILTER_IGNORE
	icon.set_anchors_preset(Control.PRESET_FULL_RECT)
	icon.offset_left = 13
	icon.offset_top = 13
	icon.offset_right = -13
	icon.offset_bottom = -13
	b.add_child(icon)
	ui_root.add_child(b)
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
	# When the Android keyboard raises it shrinks the viewport, and without this the
	# focused LineEdit stays where it was and ends up behind the keyboard - which
	# reads as "the keyboard does not show up". See "The on-screen keyboard".
	scroll.follow_focus = true
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
	# Modal cards keep a phone-ish width so a dialog reads as a dialog.
	var w := clampf(vw * 0.46, 320.0, 520.0)
	for c in overlay_cards:
		c.custom_minimum_size = Vector2(w, 0)
	# Tab content is a full-width column on a phone and a capped centred column on a
	# desktop, so a wide window does not stretch controls edge to edge.
	var tw := clampf(vw - 28.0, 320.0, 720.0)
	for c in tab_cols:
		c.custom_minimum_size = Vector2(tw, 0)


# The heading of an overlay card: accent, a touch larger, and separated from the
# body so a card reads as a titled panel rather than a stack of rows.
func _card_title(text: String) -> Label:
	return _style_title(_label(text, 26))


# --- Prompt / confirm dialog -------------------------------------------------
# One modal serves both renaming (a text field) and deleting (a yes/no). It sits
# above everything, including the track editor, so a rename from the Editor tab
# works whether the editor is open or not.

func _build_dialog() -> void:
	dlg_root = Control.new()
	dlg_root.set_anchors_preset(Control.PRESET_FULL_RECT)
	dlg_root.visible = false
	dlg_root.mouse_filter = Control.MOUSE_FILTER_STOP
	ui_root.add_child(dlg_root)

	var bg := ColorRect.new()
	bg.color = Color(0, 0, 0, 0.66)
	bg.set_anchors_preset(Control.PRESET_FULL_RECT)
	dlg_root.add_child(bg)

	var scroll := ScrollContainer.new()
	scroll.set_anchors_preset(Control.PRESET_FULL_RECT)
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	# The dialog's LineEdit is in here, so it needs the same follow_focus as the
	# overlays; see the note in `_new_overlay`.
	scroll.follow_focus = true
	dlg_root.add_child(scroll)

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
	col.custom_minimum_size = Vector2(300, 0)
	margin.add_child(col)

	dlg_title = _style_title(_label("", 22))
	col.add_child(dlg_title)
	dlg_body = _label("", 14)
	dlg_body.add_theme_color_override("font_color", UiTheme.INK_DIM)
	dlg_body.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	col.add_child(dlg_body)
	dlg_input = LineEdit.new()
	dlg_input.max_length = CustomTracks.MAX_NAME
	col.add_child(dlg_input)
	var row := _row(8)
	col.add_child(row)
	dlg_cancel = _button("Cancel", _close_dialog)
	dlg_cancel.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.add_child(dlg_cancel)
	dlg_ok = _primary_button("OK", _accept_dialog)
	dlg_ok.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.add_child(dlg_ok)
	dlg_input.text_submitted.connect(func(_t): _accept_dialog())


func _ask_text(title: String, value: String, cb: Callable) -> void:
	dlg_title.text = title
	dlg_body.visible = false
	dlg_input.visible = true
	dlg_input.text = value
	dlg_input.grab_focus()
	dlg_input.select_all()
	dlg_ok.text = "Save"
	dlg_accept = cb
	dlg_root.visible = true


func _confirm(title: String, body: String, cb: Callable, ok_label: String = "Delete") -> void:
	dlg_title.text = title
	dlg_body.text = body
	dlg_body.visible = true
	dlg_input.visible = false
	dlg_ok.text = ok_label
	dlg_accept = cb
	dlg_root.visible = true


func _accept_dialog() -> void:
	var cb := dlg_accept
	_close_dialog()
	if cb.is_valid():
		if dlg_input.visible:
			cb.call(dlg_input.text)
		else:
			cb.call()


func _close_dialog() -> void:
	dlg_root.visible = false
	dlg_accept = Callable()


# Accent-colour a heading label (used for the cards whose heading text changes at
# runtime: the account card and the run-end tags).
func _style_title(l: Label) -> Label:
	l.add_theme_color_override("font_color", UiTheme.ACCENT)
	l.custom_minimum_size = Vector2(0, 36)
	return l


func _show_only(name: String) -> void:
	for key in overlays:
		overlays[key].visible = (key == name)
	# "menu" is not a card any more: it is the full-screen shell, shown whenever no
	# modal overlay is up.
	if shell != null:
		shell.visible = (name == "menu")
	overlay = name


func _hide_overlays() -> void:
	for key in overlays:
		overlays[key].visible = false
	if shell != null:
		shell.visible = false
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
	btn_restart_round = _round_icon_button(_on_restart_round)
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
# Menu: the full-screen tabbed shell
# =============================================================================

func _build_shell() -> void:
	shell = MenuShell.new()
	ui_root.add_child(shell)
	shell.tab_changed.connect(_on_tab)
	shell.settings_pressed.connect(_open_settings)
	shell.visible = false
	# add_child runs MenuShell._ready synchronously, so content exists here.
	_build_play_tab()
	_build_garage_tab()
	_build_editor_tab()
	_build_account_tab()
	_build_settings_page()
	shell.select("play")

	# The track editor is a full-screen overlay over the shell, not a tab page: it
	# wants the whole window while it is open. App owns it so a run can launch from
	# it and come back to it.
	editor = TrackEditor.new()
	editor.app = self
	editor.closed.connect(_on_editor_closed)
	editor.play_requested.connect(_on_editor_play)
	editor.changed.connect(_refresh_custom_list)
	ui_root.add_child(editor)


# A tab page: a full-rect scroll area with a centred, width-capped column, so the
# content reads as a phone app on a phone and as a centred column on a desktop
# instead of controls stretched edge to edge.
func _new_tab(name: String) -> VBoxContainer:
	var page := Control.new()
	page.set_anchors_preset(Control.PRESET_FULL_RECT)
	page.mouse_filter = Control.MOUSE_FILTER_IGNORE
	shell.content.add_child(page)
	tab_pages[name] = page

	var scroll := ScrollContainer.new()
	scroll.set_anchors_preset(Control.PRESET_FULL_RECT)
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	# The account tab's LineEdits live in here; see the note in `_new_overlay`.
	scroll.follow_focus = true
	page.add_child(scroll)

	# A centred band whose single column is capped at a phone-ish width: content
	# reads from the top of the sheet and stays a column on a wide desktop rather
	# than stretching edge to edge.
	var band := HBoxContainer.new()
	band.alignment = BoxContainer.ALIGNMENT_CENTER
	band.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll.add_child(band)
	var col := _col(12)
	col.custom_minimum_size = Vector2(320, 0)
	col.size_flags_horizontal = Control.SIZE_FILL
	band.add_child(col)
	tab_cols.append(col)
	return col


func _on_tab(name: String) -> void:
	for key in tab_pages:
		tab_pages[key].visible = (key == name)
	match name:
		"play":
			shell.set_title("Play", "Pick a track and go")
			_refresh_custom_list()
		"garage":
			shell.set_title("Garage", "Choose your car")
		"editor":
			shell.set_title("Editor", "Build your own tracks")
			_refresh_editor_list()
		"account":
			shell.set_title("Account", "Your name, your times")
			_refresh_account_page()


# --- Play tab ---------------------------------------------------------------

func _build_play_tab() -> void:
	var col := _new_tab("play")

	# Mode lives at the very top: endless is a different game from a track run.
	mode_bar = _row(8)
	col.add_child(mode_bar)
	mode_buttons["speedrun"] = _segment(mode_bar, "clock", "Tracks", func(): _set_mode("speedrun"))
	mode_buttons["endless"] = _segment(mode_bar, "infinity", "Endless", func(): _set_mode("endless"))

	# The track chooser only applies to a time attack: endless is one open road,
	# so the whole section is hidden in that mode rather than shown and ignored.
	track_section = _col(6)
	col.add_child(track_section)
	track_section.add_child(_section("Track"))
	var track_card := PanelContainer.new()
	track_card.theme_type_variation = "SubCard"
	track_section.add_child(track_card)
	var tc := _col(4)
	track_card.add_child(tc)
	play_track_label = _label("Track 1", 20)
	tc.add_child(play_track_label)
	play_best_label = _label("best --", 13)
	play_best_label.add_theme_color_override("font_color", UiTheme.INK_DIM)
	tc.add_child(play_best_label)
	var tgrid := _col(4)
	tc.add_child(tgrid)
	_build_track_list(tgrid)

	col.add_child(_primary_button("Play", func(): _start_run(menu_seed)))

	# The ghost picker is two chips, so it lives inline on the Play tab.
	col.add_child(_section("Ghost"))
	var gbar := _row(6)
	col.add_child(gbar)
	ghost_buttons["off"] = _segment(gbar, "ghost", "Off", func(): _set_ghost("off"))
	ghost_buttons["self"] = _segment(gbar, "clock", "Your best", func(): _set_ghost("self"))

	var more := _row(8)
	col.add_child(more)
	more.add_child(_action_button("trophy", "Leaderboard", func(): _show_leaderboard(menu_seed)))
	more.add_child(_action_button("clock", "Replays", _show_history))

	# Custom tracks live under the built-in grid: the same picker, one row per track.
	custom_section = _col(6)
	col.add_child(custom_section)
	custom_section.add_child(_section("My tracks"))
	custom_list = _col(6)
	custom_section.add_child(custom_list)
	_refresh_custom_list()


# --- Editor tab -------------------------------------------------------------

func _build_editor_tab() -> void:
	var col := _new_tab("editor")
	var intro := _label("Build your own roads. Tap one to edit it, or start a new one.", 13)
	intro.add_theme_color_override("font_color", UiTheme.INK_MUTE)
	intro.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	col.add_child(intro)
	col.add_child(_primary_button("New track", _new_custom_track))
	editor_list = _col(6)
	col.add_child(editor_list)
	_refresh_editor_list()


# The list of custom tracks: one card per track, with rename / duplicate / delete.
# Tapping the card itself opens the editor for that track.
func _refresh_editor_list() -> void:
	if editor_list == null:
		return
	for c in editor_list.get_children():
		c.queue_free()
	var tracks := CustomTracks.list()
	if tracks.is_empty():
		var empty := _label("No tracks yet. Tap New track to make one.", 13)
		empty.add_theme_color_override("font_color", UiTheme.INK_MUTE)
		empty.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		editor_list.add_child(empty)
		return
	for t in tracks:
		var row: Dictionary = t
		editor_list.add_child(_custom_row(row))


func _custom_row(t: Dictionary) -> Control:
	var id := int(t["id"])
	var card := PanelContainer.new()
	card.theme_type_variation = "SubCard"
	var col := _col(6)
	card.add_child(col)

	var top := _row(6)
	col.add_child(top)
	var open := Button.new()
	open.text = str(t["name"])
	open.clip_text = true
	open.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	open.custom_minimum_size = Vector2(0, 44)
	open.pressed.connect(func(): _open_editor(id))
	top.add_child(open)

	var v := CustomTracks.validate(t["ops"] as Array)
	var info := _label("%d corners \u00b7 %s" % [int(v["corners"]), "ready" if bool(v["ok"]) else str(v["error"])], 12)
	info.add_theme_color_override("font_color", UiTheme.INK_MUTE if bool(v["ok"]) else UiTheme.DANGER)
	info.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	col.add_child(info)

	# A swatch of the track's own colours, so the list reads as the roads it holds.
	var swatches := _row(6)
	col.add_child(swatches)
	var colors := CustomTracks.theme_colors(t)
	for c in [colors["ground"], colors["road"]]:
		var dot := ColorRect.new()
		dot.color = c
		dot.custom_minimum_size = Vector2(28, 16)
		dot.mouse_filter = Control.MOUSE_FILTER_IGNORE
		swatches.add_child(dot)

	var actions := _row(6)
	col.add_child(actions)
	actions.add_child(_row_action("pencil", "Rename", func(): _rename_custom(id, t["name"])))
	actions.add_child(_row_action("copy", "Copy", func():
		CustomTracks.duplicate_track(id)
		_refresh_editor_list()
		_refresh_custom_list()))
	actions.add_child(_row_action("trash", "Delete", func(): _confirm_delete_custom(id, str(t["name"]))))
	return card


func _row_action(icon_kind: String, text: String, cb: Callable) -> Button:
	var b := Button.new()
	b.clip_text = true
	b.custom_minimum_size = Vector2(0, 40)
	b.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	b.pressed.connect(cb)
	var box := HBoxContainer.new()
	box.alignment = BoxContainer.ALIGNMENT_CENTER
	box.add_theme_constant_override("separation", 4)
	box.set_anchors_preset(Control.PRESET_FULL_RECT)
	box.mouse_filter = Control.MOUSE_FILTER_IGNORE
	b.add_child(box)
	var ic := UiIcon.new()
	ic.kind = icon_kind
	ic.color = UiTheme.INK_DIM
	ic.thickness = 2.0
	ic.custom_minimum_size = Vector2(16, 16)
	ic.mouse_filter = Control.MOUSE_FILTER_IGNORE
	box.add_child(ic)
	var l := _label(text, 13)
	l.mouse_filter = Control.MOUSE_FILTER_IGNORE
	box.add_child(l)
	return b


func _new_custom_track() -> void:
	var t := CustomTracks.new_track()
	if t.is_empty():
		_confirm("Track limit reached", "You can keep up to %d tracks. Delete one to make room." % CustomTracks.MAX_TRACKS, func(): pass, "OK")
		return
	_refresh_editor_list()
	_refresh_custom_list()
	_open_editor(int(t["id"]))


func _open_editor(id: int) -> void:
	editor.open_for(self, id)
	_show_only("")


func _on_editor_closed() -> void:
	editor.visible = false
	_refresh_editor_list()
	_refresh_custom_list()
	_to_menu()
	shell.select("editor")


func _on_editor_play() -> void:
	var opts := CustomTracks.opts_for_id(editor.id)
	var v := CustomTracks.validate(editor.ops)
	if not bool(v["ok"]) or opts.is_empty():
		return
	editor.visible = false
	_start_run(editor.id)


func _rename_custom(id: int, current: String) -> void:
	_ask_text("Rename track", current, func(value):
		CustomTracks.rename(id, value)
		_refresh_editor_list()
		_refresh_custom_list())


func _confirm_delete_custom(id: int, name: String) -> void:
	_confirm("Delete track?", "Delete \u201c%s\u201d? This cannot be undone." % name, func():
		CustomTracks.erase(id)
		if menu_seed == id:
			menu_seed = 1
			Storage.set_pref("track", 1)
		_refresh_editor_list()
		_refresh_custom_list())


# --- Custom tracks on the Play tab ------------------------------------------

func _refresh_custom_list() -> void:
	if custom_list == null:
		return
	for c in custom_list.get_children():
		c.queue_free()
	var tracks := CustomTracks.list()
	if tracks.is_empty():
		var empty := _label("No custom tracks yet. Make one in the Editor tab.", 12)
		empty.add_theme_color_override("font_color", UiTheme.INK_MUTE)
		empty.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		custom_list.add_child(empty)
		return
	for t in tracks:
		var row: Dictionary = t
		var id := int(t["id"])
		var v := CustomTracks.validate(row["ops"] as Array)
		var b := Button.new()
		b.toggle_mode = true
		b.theme_type_variation = "ToggleButton"
		b.clip_text = true
		b.custom_minimum_size = Vector2(0, 44)
		b.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		b.text = "%s  \u00b7  %d corners" % [str(row["name"]), int(v["corners"])]
		b.button_pressed = menu_seed == id
		b.disabled = not bool(v["ok"])
		b.pressed.connect(func():
			menu_seed = id
			Storage.set_pref("track", id)
			_refresh_track_list())
		custom_list.add_child(b)



# --- Garage tab -------------------------------------------------------------

func _build_garage_tab() -> void:
	var col := _new_tab("garage")
	var preview := PanelContainer.new()
	preview.theme_type_variation = "SubCard"
	col.add_child(preview)
	var pc := _col(8)
	preview.add_child(pc)
	car_preview = TextureRect.new()
	car_preview.custom_minimum_size = Vector2(0, 130)
	car_preview.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	car_preview.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	pc.add_child(car_preview)
	car_name_label = _label("", 20)
	car_name_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	pc.add_child(car_name_label)
	var note := _label("Every car drives the same - pick the one you like.", 12)
	note.add_theme_color_override("font_color", UiTheme.INK_MUTE)
	note.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	note.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	pc.add_child(note)

	col.add_child(_section("Your cars"))
	var car_row := _row(6)
	col.add_child(car_row)
	_build_car_list(car_row)
	_refresh_car_preview()


# --- Account tab ------------------------------------------------------------

func _build_account_tab() -> void:
	var col := _new_tab("account")
	acct_overview = _col(10)
	col.add_child(acct_overview)
	acct_form = _col(10)
	acct_form.visible = false
	col.add_child(acct_form)
	_build_account()


# The account tab, rebuilt from the session each time it is opened: signed out it
# offers create/sign in, signed in it shows who you are and how to leave.
func _refresh_account_page() -> void:
	if acct_overview == null:
		return
	for c in acct_overview.get_children():
		c.queue_free()
	acct_overview.visible = true
	acct_form.visible = false
	var who := Account.current_account()
	var card := PanelContainer.new()
	card.theme_type_variation = "SubCard"
	acct_overview.add_child(card)
	var c2 := _col(8)
	card.add_child(c2)
	if who != "":
		var row := _row(10)
		c2.add_child(row)
		var ic := UiIcon.new()
		ic.kind = "account"
		ic.color = UiTheme.ACCENT
		ic.custom_minimum_size = Vector2(34, 34)
		row.add_child(ic)
		var names := _col(0)
		row.add_child(names)
		var t := _label(who, 20)
		names.add_child(t)
		var s := _label("Signed in", 12)
		s.add_theme_color_override("font_color", UiTheme.INK_MUTE)
		names.add_child(s)
		c2.add_child(_button("Sign out", func():
			Account.logout()
			_refresh_account_page()
			_refresh_track_list()))
	else:
		var t := _label("You are playing as a guest.", 16)
		c2.add_child(t)
		var s := _label("Sign in to put your times on the board.", 13)
		s.add_theme_color_override("font_color", UiTheme.INK_DIM)
		s.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		c2.add_child(s)
		c2.add_child(_primary_button("Sign in", func(): _open_account("login")))
		c2.add_child(_button("Create an account", func(): _open_account("register")))

	var hist := PanelContainer.new()
	hist.theme_type_variation = "SubCard"
	acct_overview.add_child(hist)
	var hc := _col(6)
	hist.add_child(hc)
	hc.add_child(_section("Your runs"))
	var runs := Storage.all_runs()
	if runs.size() == 0:
		hc.add_child(_label("No finished runs yet.", 14))
	else:
		hc.add_child(_label("%d finished runs" % runs.size(), 14))
		hc.add_child(_button("Open history", _show_history))


# --- Settings ---------------------------------------------------------------

func _build_settings_page() -> void:
	settings_col = _new_overlay("settings", "Settings")
	var card := PanelContainer.new()
	card.theme_type_variation = "SubCard"
	settings_col.add_child(card)
	var c := _col(8)
	card.add_child(c)
	_settings_controls(c)
	settings_col.add_child(_button("Done", _to_menu))
	# The build version, so a bug report can name the build.
	var ver := _label("Sling Drift  v%s" % VERSION, 12)
	ver.add_theme_color_override("font_color", UiTheme.INK_MUTE)
	ver.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	settings_col.add_child(ver)


# The Settings "Controls" block. The key bindings are always built, touchscreen
# or not: a tablet with a keyboard attached still reports a touchscreen, and
# gating the rows on `is_touchscreen_available` left Settings showing the
# "Controls" heading with nothing under it to change. The tap hint sits alongside
# the bindings when a touchscreen is present, not instead of them.
func _settings_controls(c: VBoxContainer) -> void:
	c.add_child(_section("Controls"))
	if DisplayServer.is_touchscreen_available():
		var t := _label("Tap and hold anywhere to swing. A keyboard works too - rebind its keys below.", 14)
		t.add_theme_color_override("font_color", UiTheme.INK_DIM)
		t.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		c.add_child(t)
	_key_row(c, "Play", "play", "Hold this key to swing.", input_key)
	_key_row(c, "Reset", "reset", "Press this key to restart the current run.", reset_key)
	_key_row(c, "Pause", "pause", "Press this key to pause and resume.", pause_key)


func _open_settings() -> void:
	_show_only("settings")


# One rebindable key: a label, the current key as a button, and a one-line hint.
# Clicking the button arms capture; the next key press becomes the binding.
func _key_row(parent: Node, label: String, name: String, hint: String, code: int) -> void:
	var row := _row(10)
	parent.add_child(row)
	var ic := UiIcon.new()
	ic.kind = "key"
	ic.color = UiTheme.INK_DIM
	ic.custom_minimum_size = Vector2(26, 26)
	row.add_child(ic)
	var lbl := _label(label, 16)
	lbl.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.add_child(lbl)
	var b := _button(_key_name(code), func(): _begin_capture(name))
	b.custom_minimum_size = Vector2(120, 0)
	row.add_child(b)
	key_buttons[name] = b
	var h := _label(hint, 12)
	h.add_theme_color_override("font_color", UiTheme.INK_MUTE)
	h.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	parent.add_child(h)


func _begin_capture(name: String) -> void:
	key_capturing = name
	key_buttons[name].text = "Press a key..."


func _key_name(code: int) -> String:
	match code:
		KEY_ESCAPE: return "Esc"
		KEY_SPACE: return "Space"
		KEY_ENTER: return "Enter"
		KEY_SHIFT: return "Shift"
		KEY_CTRL: return "Ctrl"
		KEY_UP: return "Up"
		KEY_DOWN: return "Down"
		KEY_LEFT: return "Left"
		KEY_RIGHT: return "Right"
	return OS.get_keycode_string(code) if OS.get_keycode_string(code) != "" else "Key %d" % code


# The three rebindable keys, by name. One place so `_bind_key` and the collision
# check cannot disagree about which key is which.
func _binding(name: String) -> int:
	match name:
		"play": return input_key
		"reset": return reset_key
		"pause": return pause_key
	return 0


func _set_binding(name: String, code: int) -> void:
	match name:
		"play":
			input_key = code
			Storage.set_pref("inputKey", code)
		"reset":
			reset_key = code
			Storage.set_pref("resetKey", code)
		"pause":
			pause_key = code
			Storage.set_pref("pauseKey", code)


# Bind the captured key. No two bindings may collide, so a key already in use is
# refused rather than silently shadowing the other action. Esc always cancels a
# capture, so it is never offered as a binding itself.
func _bind_key(code: int) -> void:
	var which := key_capturing
	key_capturing = ""
	if code == KEY_ESCAPE:
		key_buttons[which].text = _key_name(_binding(which))
		return
	for name in key_buttons:
		if name != which and _binding(name) == code:
			key_buttons[which].text = "Already used"
			return
	_set_binding(which, code)
	key_buttons[which].text = _key_name(code)


# --- The ghost picker -------------------------------------------------------

func _refresh_ghost_overlay() -> void:
	for key in ghost_buttons:
		ghost_buttons[key].button_pressed = (key == ghost_mode)


func _segment(parent: Node, icon_kind: String, text: String, cb: Callable) -> Button:
	var b := Button.new()
	b.toggle_mode = true
	b.theme_type_variation = "ToggleButton"
	b.clip_text = true
	b.custom_minimum_size = Vector2(0, 48)
	b.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	b.pressed.connect(cb)
	var box := HBoxContainer.new()
	box.alignment = BoxContainer.ALIGNMENT_CENTER
	box.add_theme_constant_override("separation", 6)
	box.set_anchors_preset(Control.PRESET_FULL_RECT)
	box.mouse_filter = Control.MOUSE_FILTER_IGNORE
	b.add_child(box)
	var ic := UiIcon.new()
	ic.kind = icon_kind
	ic.color = UiTheme.INK
	ic.thickness = 2.0
	ic.custom_minimum_size = Vector2(20, 20)
	ic.mouse_filter = Control.MOUSE_FILTER_IGNORE
	box.add_child(ic)
	var l := _label(text, 15)
	l.mouse_filter = Control.MOUSE_FILTER_IGNORE
	box.add_child(l)
	parent.add_child(b)
	return b


func _action_button(icon_kind: String, text: String, cb: Callable) -> Button:
	var b := Button.new()
	b.clip_text = true
	b.custom_minimum_size = Vector2(0, 50)
	b.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	b.pressed.connect(cb)
	var box := HBoxContainer.new()
	box.alignment = BoxContainer.ALIGNMENT_CENTER
	box.add_theme_constant_override("separation", 8)
	box.set_anchors_preset(Control.PRESET_FULL_RECT)
	box.mouse_filter = Control.MOUSE_FILTER_IGNORE
	b.add_child(box)
	var ic := UiIcon.new()
	ic.kind = icon_kind
	ic.color = UiTheme.INK_DIM
	ic.thickness = 2.0
	ic.custom_minimum_size = Vector2(20, 20)
	ic.mouse_filter = Control.MOUSE_FILTER_IGNORE
	box.add_child(ic)
	var l := _label(text, 15)
	l.mouse_filter = Control.MOUSE_FILTER_IGNORE
	box.add_child(l)
	return b


func _section(text: String) -> Label:
	var l := _label(text.to_upper(), 13)
	l.add_theme_color_override("font_color", UiTheme.ACCENT)
	return l


func _build_car_list(parent: Node) -> void:
	car_buttons.clear()
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
			_refresh_car_list()
			_refresh_car_preview())
		grid.add_child(b)
		car_buttons.append(b)


func _refresh_car_list() -> void:
	for i in range(car_buttons.size()):
		car_buttons[i].button_pressed = (i == car_skin)


func _refresh_car_preview() -> void:
	if car_preview == null:
		return
	var model: Dictionary = Renderer2D.CAR_MODELS[car_skin]
	car_preview.texture = load(str(model["tex"]))
	car_name_label.text = str(model["name"])


# A grid of track chips: the number with the player's best time under it, the way
# the old JS client's `Track 3<small>10.14</small>` read. Five columns rather than
# seven because a chip has to fit both a two-digit number and a "10.142" best - at
# seven columns a chip has 28px of content and the time needs 32px, so it clipped.
# Thirteen tracks over five columns is three rows, which still fits the tab.
func _build_track_list(parent: Node) -> void:
	track_buttons.clear()
	track_pb_labels.clear()
	var grid := GridContainer.new()
	grid.columns = 5
	grid.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	grid.add_theme_constant_override("h_separation", 6)
	grid.add_theme_constant_override("v_separation", 6)
	parent.add_child(grid)
	for s in Tracks.MENU_TRACKS:
		var b := Button.new()
		b.toggle_mode = true
		b.theme_type_variation = "GridChip"
		b.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		b.custom_minimum_size = Vector2(0, 54)
		b.set_meta("track", s)
		b.pressed.connect(func():
			menu_seed = s
			Storage.set_pref("track", s)
			_refresh_track_list())
		# A Button draws no text of its own here; the number and the best are child
		# Labels so they can differ in size and colour. IGNORE keeps the taps going to
		# the button underneath.
		var box := _col(0)
		box.set_anchors_preset(Control.PRESET_FULL_RECT)
		box.alignment = BoxContainer.ALIGNMENT_CENTER
		box.mouse_filter = Control.MOUSE_FILTER_IGNORE
		b.add_child(box)
		var num := _label(str(s), 16)
		num.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		num.clip_text = true
		num.mouse_filter = Control.MOUSE_FILTER_IGNORE
		box.add_child(num)
		var pb := _label("--", 10)
		pb.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		pb.clip_text = true
		pb.add_theme_color_override("font_color", UiTheme.INK_DIM)
		pb.mouse_filter = Control.MOUSE_FILTER_IGNORE
		box.add_child(pb)
		grid.add_child(b)
		track_buttons.append(b)
		track_pb_labels[s] = pb


# The per-track best under each chip, so the grid answers "which have I run?"
# without opening every track. Only the built-in chips are in the grid; custom
# tracks have their own list.
#
# The colours follow the chip's own state. The theme paints a selected chip in the
# gold accent and swaps the button's text to ACCENT_TEXT for contrast, but a child
# Label does not inherit that: left alone, the number stayed near-white and the
# best stayed INK_DIM, both about 1.4:1 against gold - invisible.
func _refresh_track_bests() -> void:
	for b in track_buttons:
		var s := int(b.get_meta("track"))
		var pb: Label = track_pb_labels.get(s)
		if pb == null:
			continue
		var best: Variant = Storage.get_best_time(s)
		pb.text = "--" if best == null else _fmt_time(float(best))
		_paint_chip(b, pb)


func _paint_chip(b: Button, pb: Label) -> void:
	var num: Label = pb.get_parent().get_child(0)
	var on := b.button_pressed
	num.add_theme_color_override("font_color", UiTheme.ACCENT_TEXT if on else UiTheme.INK)
	pb.add_theme_color_override("font_color",
		Color(UiTheme.ACCENT_TEXT, 0.8) if on else UiTheme.INK_DIM)


func _show_tracks() -> void:
	shell.select("play")


func _refresh_track_list() -> void:
	_refresh_track_visibility()
	for b in track_buttons:
		b.button_pressed = (int(b.get_meta("track")) == menu_seed)
	_refresh_track_bests()
	if play_track_label == null:
		return
	if CustomTracks.has(menu_seed):
		play_track_label.text = CustomTracks.display_name(menu_seed)
	else:
		play_track_label.text = "Track %d" % menu_seed
	if menu_mode == "speedrun":
		var best: Variant = Storage.get_best_time(menu_seed)
		play_best_label.text = "best --" if best == null else "best %s" % _fmt_time(float(best))
	else:
		# Endless is one shared road, so the record is this player's best distance on it.
		var best_d := float(Storage.get_record(Game.ENDLESS_SEED)["dist"])
		play_best_label.text = "best --" if best_d <= 0.0 else "best %s" % _fmt_dist(best_d)
	_refresh_custom_list()


# Endless has no track to pick, so the chooser is hidden rather than shown and
# ignored. Speedrun is where a track means anything - and the same goes for the
# custom-track picker underneath it.
func _refresh_track_visibility() -> void:
	if track_section != null:
		track_section.visible = (menu_mode != "endless")
	if custom_section != null:
		custom_section.visible = (menu_mode != "endless")


func _refresh_mode_list() -> void:
	for key in mode_buttons:
		mode_buttons[key].button_pressed = (key == menu_mode)
	_refresh_ghost_overlay()
	_refresh_car_list()


func _set_mode(m: String) -> void:
	menu_mode = m
	Storage.set_pref("mode", m)
	# A custom track is a finite, timed road, so it is a speedrun course. Selecting
	# endless would leave the custom picker hidden with a dead selection behind it.
	if m == "endless" and CustomTracks.has(menu_seed):
		menu_seed = Tracks.MENU_TRACKS[0]
		Storage.set_pref("track", menu_seed)
	_refresh_mode_list()
	_refresh_track_list()


func _set_ghost(g: String) -> void:
	ghost_mode = g
	Storage.set_pref("ghostMode", g)
	_refresh_ghost_overlay()





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

	col.add_child(_button("Back", func(): _to_menu()))


func _render_board() -> void:
	if board_mode == "endless":
		_render_endless_board()
		return
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
	var page := Leaderboard.board_page(board_page_no, null if listed else me, Leaderboard.PER_PAGE, reals)
	board_page_no = int(page["page"])

	lb_title.text = "Track %d" % seed
	if int(page["total"]) == 0:
		lb_note.text = "No runs yet \u00b7 be the first"
	elif int(page["player_rank"]) > 0:
		lb_note.text = "You are #%d of %d" % [int(page["player_rank"]), int(page["total"])]
	else:
		lb_note.text = "%d racers \u00b7 set a time to join" % int(page["total"])

	for c in lb_rows.get_children():
		c.queue_free()
	for r in page["rows"]:
		var text := "%d   %s   %s" % [int(r["rank"]), str(r["name"]), _fmt_time(float(r["time"]))]
		var steps: Variant = r.get("steps")
		if steps != null and str(steps) != "":
			# Every real run carries its own steps, so every row can be watched.
			var row: Dictionary = r
			var action := "Replay" if bool(row["you"]) else "Watch"
			var b := _button(text + "   " + action, func():
				_watch_steps(seed, str(row["steps"]), str(row["name"]), float(row["time"])))
			lb_rows.add_child(b)
		else:
			lb_rows.add_child(_label(text, 14))

	lb_page_label.text = "%d / %d" % [int(page["page"]), int(page["pages"])]
	lb_prev.disabled = int(page["page"]) <= 1
	lb_next.disabled = int(page["page"]) >= int(page["pages"])


# The endless board is player + distance, furthest first. It is short - one row
# per player - so it is shown whole, with no paging. The server ranks it; the
# client only draws it.
func _render_endless_board() -> void:
	var reals := _reals_for(board_seed, "endless")
	var mine := float(Storage.get_record(Game.ENDLESS_SEED)["dist"])
	lb_title.text = "Endless"
	if reals.is_empty() and mine <= 0.0:
		lb_note.text = "No runs yet \u00b7 be the first"
	else:
		lb_note.text = "%d racers \u00b7 furthest wins" % reals.size()

	for c in lb_rows.get_children():
		c.queue_free()
	var shown_you := false
	for r in reals:
		var row: Dictionary = r
		if bool(row.get("you", false)):
			shown_you = true
		lb_rows.add_child(_label("%d   %s   %s" % [int(row.get("rank", 0)), str(row.get("name", "")), _fmt_dist(float(row.get("dist", 0.0)))], 14))
	# A local best the server has not listed yet, so the player still sees their own
	# distance while the upload lands.
	if not shown_you and mine > 0.0:
		lb_rows.add_child(_label("\u00b7   %s   %s (not uploaded)" % [_player_name(), _fmt_dist(mine)], 14))
	lb_page_label.text = "1 / 1"
	lb_prev.disabled = true
	lb_next.disabled = true


func _show_leaderboard(seed: int) -> void:
	# The board follows the menu mode: endless ranks distances, speedrun ranks times.
	# Endless is one shared road, so its board is keyed by the shared seed, not by
	# whatever track the menu happens to be showing.
	board_mode = menu_mode
	board_seed = Game.ENDLESS_SEED if board_mode == "endless" else seed
	board_page_no = 1
	if board_mode == "speedrun":
		# The page the player belongs on comes from their rank in the merged board, so
		# the real runs have to be counted. Before they load this is a first guess and
		# the board corrects it once they are in.
		var best: Variant = Storage.get_best_time(seed)
		var reals := _reals_for(seed)
		board_page_no = 1 if best == null else Leaderboard.page_for_rank(Leaderboard.player_rank(float(best), reals))
	_render_board()
	_show_only("board")
	# Then fetch the real runs and re-render with them merged in. The local board is
	# drawn first so it is never blank while that loads.
	_load_reals(board_seed, board_mode)


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
	col.add_child(_button("Back", func(): _to_menu()))


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
		var label := CustomTracks.display_name(seed) if CustomTracks.has(seed) else "Track %d" % seed
		hist_rows.add_child(_label("%s   %s   %s   %s" % [
			label, "Personal best" if pb else "Finished",
			_fmt_time(float(r["time"])), _ago(float(r["at"]))], 14))
	_show_only("history")


# =============================================================================
# Accounts
# =============================================================================

func _build_account() -> void:
	var card := PanelContainer.new()
	card.theme_type_variation = "SubCard"
	acct_form.add_child(card)
	var col := _col(8)
	card.add_child(col)
	acct_title = _style_title(_label("Sign in", 22))
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
	acct_error.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
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
	col.add_child(_button("Back", _refresh_account_page))


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
	# select() refreshes the tab, which resets to the overview; show the form after it.
	shell.select("account")
	acct_overview.visible = false
	acct_form.visible = true


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
	_to_menu()
	shell.select("account")


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
	_to_menu()


# Everything that has to happen once a player is signed in: the bar and the track
# list change, their times come back from the server, and the guest queue can go.
func _after_sign_in() -> void:
	_refresh_account_page()
	# Pull the account's runs down before rebuilding the chips: `_sync_my_runs` writes
	# the server bests into the local store, so refreshing first would draw the chips
	# with the previous account's (or guest) times and they would not update again
	# until something else triggered a redraw.
	await _sync_my_runs()
	_refresh_track_list()
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
	_refresh_account_page()
	await _sync_my_runs()


# Pull the signed-in player's best times back from the server.
#
# The account is the source of truth, not the device: on a fresh install the local
# records are empty even though the account holds times. Merging is a lower-only
# write, so a better local time is never lost to a worse server one.
func _sync_my_runs() -> void:
	var runs: Variant = await Api.fetch_my_runs()
	if runs != null:
		_merge_my_runs(runs)
	# Endless distances come down too: the account is the source of truth, so a fresh
	# device pulls its endless bests back rather than showing nothing.
	var endless: Variant = await Api.fetch_my_endless()
	if endless != null:
		_merge_my_endless(endless)
	_refresh_track_list()


# Fold the server's own runs into the local store. Split out from the fetch so the
# merge can be tested without a network.
func _merge_my_runs(runs: Array) -> void:
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


func _merge_my_endless(rows: Array) -> void:
	for e in rows:
		var erow: Dictionary = e
		var eseed := int(erow["seed"])
		var emetres := float(erow["metres"])
		var eprev: Dictionary = Storage.get_record(eseed)
		if emetres > float(eprev.get("dist", 0.0)):
			Storage.save_record(eseed, emetres, int(eprev.get("corners", 0)))


# Send anything the queue is holding. A guest's runs wait here until they sign in.
func _flush_queue() -> void:
	if Api.queue_length() == 0:
		return
	var sent: Variant = await Api.flush()
	if sent == null:
		return
	var d: Dictionary = sent
	var mode := str(d.get("mode", "speedrun"))
	if mode == "speedrun":
		await _load_reals(int(d.get("track", board_seed)), "speedrun")
	_refresh_track_list()


# The real runs for a track, as the server last returned them, mapped to the shape
# the board merge wants. Empty when the server has not answered for this track.
func _reals_for(seed: int, mode: String = "speedrun") -> Array:
	if board_reals_seed != seed or board_reals_mode != mode:
		return []
	var out := []
	for r in board_reals:
		var row: Dictionary = r
		out.append({
			"name": str(row.get("name", "")),
			"time": float(row.get("time", 0.0)),
			"dist": float(row.get("dist", 0.0)),
			"rank": int(row.get("rank", 0)),
			"steps": row.get("steps"),
			"you": bool(row.get("you", false)),
		})
	return out


# Fetch a track's real runs and re-render whatever is showing them. Called after a
# run is uploaded and whenever the board is opened.
func _load_reals(seed: int, mode: String = "speedrun") -> void:
	var rows: Variant = await Api.fetch_board(seed, mode)
	if rows == null:
		return
	board_reals = rows
	board_reals_seed = seed
	board_reals_mode = mode
	# The player may have moved on while that was in flight, in which case there is
	# nothing on screen to re-render.
	if overlay == "board" and board_seed == seed and board_mode == mode:
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
	col.add_child(_button("Try again", func(): _start_run(game.seed_num)))
	col.add_child(_button("Leaderboard", func(): _show_leaderboard(game.seed_num)))
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
	btn_finish_wr = _button("Watch record", func():
		var wr = Leaderboard.world_record(_reals_for(game.seed_num))
		if wr != null:
			_watch_wr(game.seed_num, wr))
	row.add_child(btn_finish_wr)
	btn_finish_lb = _button("Leaderboard", func(): _show_leaderboard(game.seed_num))
	col.add_child(btn_finish_lb)
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
		else:
			_watch_steps(seed, str(watching["steps"]), str(watching["name"]), float(watching["time"]))))
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
	_refresh_account_page()
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
	# The only ghost is your own best run: it is a replay you own, so it needs no
	# server and no invented racer.
	if menu_mode != "speedrun" or ghost_mode != "self":
		return
	game.set_ghost_self(seed)


func _watch_own_replay(seed: int) -> void:
	if Storage.get_replay(seed) == null:
		return
	var best: Variant = Storage.get_best_time(seed)
	watching = {
		"kind": "self", "seed": seed, "name": null, "time": float(best),
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


# Watch the world record: a real run replays from the steps that travelled with it.
func _watch_wr(seed: int, wr: Dictionary) -> void:
	var steps: Variant = wr.get("steps")
	if steps != null and str(steps) != "":
		_watch_steps(seed, str(steps), str(wr["name"]), float(wr["time"]))


# Watch a run given as raw button steps.
func _watch_steps(seed: int, steps: String, name: String, time: float) -> void:
	watching = {
		"kind": "steps", "seed": seed, "name": name, "time": time,
		"steps": steps,
                "label": "%s's run" % name, "tag": "Replay",
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
			# Endless runs are not replayed server-side: the score is the distance, so
			# the client reports it. Best-effort, exactly like a speedrun upload.
			var seed_done := game.seed_num
			Api.enqueue_endless(seed_done, game.metres(), _player_name())
			_submit_endless(seed_done)
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
		var custom := CustomTracks.has(game.seed_num)
		var rank := 0 if custom else Leaderboard.player_rank(best2, _reals_for(game.seed_num))
		finish_rank.text = "#%d on Track %d" % [rank, game.seed_num] if rank > 0 else ""
		btn_watch.visible = Storage.get_replay(game.seed_num) != null
		btn_finish_wr.visible = not custom and Leaderboard.world_record(_reals_for(game.seed_num)) != null
		btn_finish_lb.visible = not custom
		_show_only("finish")
		hint_label.visible = false
		_show_round_button(false)
		# A custom track is local-only: the server has never heard of its id and its
		# shape is the player's own, so there is no board to upload to. The run is
		# already saved locally (the time, the history and the replay), which is all a
		# custom track needs.
		if not custom:
			var seed_done := game.seed_num
			Api.enqueue(seed_done, Replay.encode_steps(game.steps), _player_name())
			_submit_queued(seed_done)


# Send queued endless runs. There is no finish card to refresh - endless ends in a
# crash - so this only flushes the queue and updates the local readouts.
func _submit_endless(seed: int) -> void:
	await Api.flush()
	_refresh_track_list()


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
	var page := Leaderboard.board_page(1, me, Leaderboard.PER_PAGE, reals)
	var rank := int(page["player_rank"])
	finish_rank.text = "#%d on Track %d" % [rank, seed] if rank > 0 else ""
	btn_finish_wr.visible = Leaderboard.world_record(reals) != null


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


# The pause key is a toggle: pause a running run, resume a paused one.
func _toggle_pause() -> void:
	if overlay == "" and game.state == "running":
		_on_pause()
	elif overlay == "pause":
		_hide_overlays()
		game.state = "running"
		_show_round_button(not game.is_replay())


func _on_restart_round() -> void:
	if game.is_replay():
		return
	_start_run(game.seed_num)


# =============================================================================
# Input: one button, anywhere that is not a control
# =============================================================================

func _unhandled_input(event: InputEvent) -> void:
	# The track editor and the prompt dialog are modal: while either is up, a tap or a
	# key must not reach the one-button mechanic behind them.
	if (editor != null and editor.visible) or (dlg_root != null and dlg_root.visible):
		return
	# A key press while rebinding becomes the new binding, and is swallowed.
	if key_capturing != "" and event is InputEventKey and event.pressed and not event.echo:
		_bind_key(event.keycode)
		get_viewport().set_input_as_handled()
		return
	# The reset key restarts the run in progress. It only fires with no overlay up and
	# not on a replay, so a crash/finish card (which has its own button) is not
	# yanked away. Keyboard-only: on a phone the round restart button does this.
	if event is InputEventKey and event.pressed and not event.echo and event.keycode == reset_key:
		if overlay == "" and game.state == "running" and not game.is_replay():
			_start_run(game.seed_num)
		get_viewport().set_input_as_handled()
		return
	# The pause key toggles the pause card: it pauses a run in progress, and resumes
	# one that is paused. It is inert everywhere else, so it cannot yank away a
	# crash/finish card.
	if event is InputEventKey and event.pressed and not event.echo and event.keycode == pause_key:
		_toggle_pause()
		get_viewport().set_input_as_handled()
		return
	var down := false
	var up := false
	if event is InputEventScreenTouch:
		down = event.pressed
		up = not event.pressed
	elif event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT:
		down = event.pressed
		up = not event.pressed
	elif event is InputEventKey and (event.keycode == input_key or event.keycode == KEY_UP):
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
