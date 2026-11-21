extends Control
class_name TrackEditor

# The track editor: a blank grid with a palette of pieces along the bottom.
#
# The model is `CustomTracks` (the same op list `Track.build_ops` walks) and the map
# is a `TrackPreview`, so what is edited is exactly the road the game drives. The
# editor owns only the editing session; `App` owns the list, the persistence and the
# launch into a run.
#
# The whole surface is the grid. Tap a piece in the bottom palette to arm it, then
# tap the grid and it is added. Nothing else is on screen: the selected piece's
# controls, the colours and the help live in a sheet that only opens when asked for.
#
# A tap cannot place a piece at an arbitrary spot. The road is an op list - each op is
# a length or a turn relative to where the last one ended - so the road is always one
# continuous ribbon and a piece is always appended to its end. The tapped cell
# therefore sets *how far* the next straight runs (its distance from the road's end);
# a turn is aimed at the cell. That is as close as a continuous road can honestly get
# to "put it there".

signal closed()
signal play_requested()
signal changed()

const UNDO_CAP := 40

var app = null                  # the App root; untyped to call its handlers
var id := 0
var track_name := ""

var ops: Array = []
var palette := {}               # {"road": "RRGGBB", "ground": "RRGGBB"}
var selected := -1
var _undo: Array = []
var _armed := ""                # the palette piece waiting for a grid tap

var preview: TrackPreview
var name_button: Button
var status_label: Label
var play_button: Button
var undo_button: Button
var grid_col: VBoxContainer
var palette_bar: GridContainer
var _palette_buttons := {}

# The sheet: colours, help, and the selected piece's controls. Hidden until asked.
var sheet: PanelContainer
var sheet_box: VBoxContainer
var sheet_title: Label
var sheet_scroll: ScrollContainer

# Look page live refs (so a slider drag never rebuilds the page under the finger).
var _swatch: ColorRect
var _road_sliders := []
var _road_labels := []
var _ground_sliders := []
var _ground_labels := []
var _road_hex: LineEdit
var _ground_hex: LineEdit
var _syncing := false


func open_for(p_app, p_id: int) -> void:
	app = p_app
	id = p_id
	var t: Variant = CustomTracks.get_track(id)
	if t == null:
		return
	track_name = str(t["name"])
	ops = (t["ops"] as Array).duplicate(true)
	palette = CustomTracks.theme_of(t)
	_undo = []
	selected = ops.size() - 1
	_armed = ""
	visible = true
	_close_sheet()
	_rebuild()
	_fit_soon()


func _ready() -> void:
	# `set_anchors_and_offsets_preset`, not `set_anchors_preset`: this node is already
	# in the tree, so the anchors-only call keeps the current (zero) rect and the whole
	# overlay collapses to 0x0 - which also collapses the map, so a drag misses it.
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_STOP
	visible = false

	var bg := ColorRect.new()
	bg.color = Color(0.03, 0.04, 0.08, 0.98)
	bg.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(bg)

	var margin := MarginContainer.new()
	margin.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	for side in ["left", "right", "top", "bottom"]:
		margin.add_theme_constant_override("margin_" + side, 10)
	add_child(margin)

	var col := VBoxContainer.new()
	col.add_theme_constant_override("separation", 8)
	margin.add_child(col)

	_build_header(col)

	status_label = Label.new()
	status_label.add_theme_font_size_override("font_size", 13)
	status_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	col.add_child(status_label)

	grid_col = VBoxContainer.new()
	grid_col.add_theme_constant_override("separation", 6)
	grid_col.size_flags_vertical = Control.SIZE_EXPAND_FILL
	col.add_child(grid_col)

	preview = TrackPreview.new()
	preview.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	preview.size_flags_vertical = Control.SIZE_EXPAND_FILL
	preview.show_grid = true
	preview.piece_picked.connect(_on_piece_picked)
	preview.cell_tapped.connect(_on_cell_tapped)
	grid_col.add_child(preview)
	grid_col.add_child(_build_camera_row())

	palette_bar = GridContainer.new()
	palette_bar.columns = 3
	palette_bar.add_theme_constant_override("h_separation", 6)
	palette_bar.add_theme_constant_override("v_separation", 6)
	col.add_child(palette_bar)
	_build_palette()

	_build_sheet()


func _build_header(col: VBoxContainer) -> void:
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 8)
	col.add_child(row)

	var back := Button.new()
	back.theme_type_variation = "IconButton"
	back.focus_mode = Control.FOCUS_NONE
	back.custom_minimum_size = Vector2(40, 40)
	back.pressed.connect(_on_close)
	_icon_into(back, "back", UiTheme.INK_DIM)
	row.add_child(back)

	# The name is the rename control: tap it, and App asks for a new one. One
	# control instead of a separate Rename button that has to be found.
	name_button = Button.new()
	name_button.text = track_name
	name_button.clip_text = true
	name_button.tooltip_text = "Rename this track"
	name_button.focus_mode = Control.FOCUS_NONE
	name_button.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	name_button.custom_minimum_size = Vector2(0, 40)
	name_button.add_theme_font_size_override("font_size", 18)
	name_button.pressed.connect(_rename)
	row.add_child(name_button)

	undo_button = Button.new()
	undo_button.theme_type_variation = "IconButton"
	undo_button.focus_mode = Control.FOCUS_NONE
	undo_button.custom_minimum_size = Vector2(40, 40)
	undo_button.tooltip_text = "Undo"
	undo_button.pressed.connect(_undo_last)
	_icon_into(undo_button, "undo", UiTheme.INK_DIM)
	row.add_child(undo_button)

	var look := Button.new()
	look.theme_type_variation = "IconButton"
	look.focus_mode = Control.FOCUS_NONE
	look.custom_minimum_size = Vector2(40, 40)
	look.tooltip_text = "Colours"
	look.pressed.connect(func(): _open_look())
	_icon_into(look, "settings", UiTheme.INK_DIM)
	row.add_child(look)

	play_button = Button.new()
	play_button.theme_type_variation = "PrimaryButton"
	play_button.text = "Play"
	play_button.focus_mode = Control.FOCUS_NONE
	play_button.custom_minimum_size = Vector2(80, 40)
	play_button.pressed.connect(func(): play_requested.emit())
	row.add_child(play_button)


func _build_camera_row() -> Control:
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 6)
	row.add_child(_mini_text("Fit", func(): preview.fit()))
	row.add_child(_mini_text("-", func(): preview.zoom_by(1.0 / 1.3)))
	row.add_child(_mini_text("+", func(): preview.zoom_by(1.3)))
	var hint := Label.new()
	hint.text = "Drag to pan \u00b7 pinch to zoom"
	hint.add_theme_font_size_override("font_size", 12)
	hint.add_theme_color_override("font_color", UiTheme.INK_MUTE)
	hint.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	hint.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	hint.clip_text = true
	row.add_child(hint)
	return row


# --- palette -----------------------------------------------------------------

# The pieces, in the order they read: a straight, the three turns, then the
# reattach turn. Every turn carries a pillar - the pole the car slings around sits
# at the centre of the arc - so a turn and a pillar are one piece, not two.
func _build_palette() -> void:
	for c in palette_bar.get_children():
		c.queue_free()
	_palette_buttons = {}
	# Each tile is a picture of the piece, not a word for it: the shape is what a
	# player is choosing. Left and right are separate tiles because they place
	# different roads, and the tile's art is generated from the signed angle, so what
	# is drawn is the way the piece will actually turn.
	#
	# There is no separate "pillar" tile. A pillar IS the turn: the pole the car
	# slings around sits at the centre of the arc. The old tile built the identical
	# op to "90", so choosing a curve and choosing a pillar did the same thing,
	# which read as both of them placing at once. The reattach turn is a real
	# difference - its pole stays live after an early release.
	var items := [
		["straight", "Straight"],
		["90", "Right 90\u00b0"],
		["-90", "Left 90\u00b0"],
		["180", "Hairpin 180\u00b0"],
		["270", "Right loop 270\u00b0"],
		["-270", "Left loop 270\u00b0"],
		["reattach", "Right reattach 90\u00b0"],
		["reattach_l", "Left reattach 90\u00b0"],
		["finish", "Finish line"],
	]
	for it in items:
		var key: String = it[0]
		var b := Button.new()
		b.toggle_mode = true
		b.focus_mode = Control.FOCUS_NONE
		b.tooltip_text = str(it[1])
		b.custom_minimum_size = Vector2(0, 56)
		b.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		b.button_pressed = key == _armed
		b.pressed.connect(func(): _arm(key))
		var icon := PieceIcon.new()
		icon.kind = key
		icon.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
		# Inset so the tile's own edge and pressed border stay visible round the art.
		icon.offset_left = 6
		icon.offset_top = 6
		icon.offset_right = -6
		icon.offset_bottom = -6
		b.add_child(icon)
		_palette_buttons[key] = b
		palette_bar.add_child(b)
	_paint_palette()


# Tint every tile with the track's own road/ground colours, and mark the armed one,
# so the palette reads as a preview of what will be added.
func _paint_palette() -> void:
	var colors := CustomTracks.theme_colors(_entry())
	for k in _palette_buttons.keys():
		var b := _palette_buttons[k] as Button
		b.button_pressed = k == _armed
		for c in b.get_children():
			var icon := c as PieceIcon
			if icon != null:
				icon.road_color = colors["road"]
				icon.ground_color = colors["ground"]
				icon.selected = k == _armed


func _arm(key: String) -> void:
	# Tapping the armed piece again disarms it, so the palette can be put down
	# without placing anything.
	_armed = "" if _armed == key else key
	_paint_palette()
	# The preview routes a tap to `cell_tapped` only while this is valid, which is how
	# "arm a piece, tap the grid" works. Leaving it unset made the palette inert.
	preview.armed = (func(): pass) if _armed != "" else Callable()
	if status_label != null:
		_refresh_status()


# A grid tap while a piece is armed appends that piece to the end of the road.
func _on_cell_tapped(cell: Vector2i) -> void:
	if _armed == "" or ops.size() >= CustomTracks.MAX_PIECES:
		return
	# The finish closes the track, so it can only be added once and only at the end.
	# Arming it again just moves the existing one, which is what a player expects from
	# tapping the finish tile and then a cell.
	var has_finish := CustomTracks.finish_index(ops) >= 0
	var w := preview.cell_to_world(cell)
	_push_undo()
	if _armed == "finish":
		# A finish replaces any earlier one and always sits last: the road ends there.
		var fi := CustomTracks.finish_index(ops)
		if has_finish:
			ops.remove_at(fi)
		var d := w.distance_to(preview.growth_point(ops.size()))
		ops.append(CustomTracks.make_finish(clampf(d, CustomTracks.MIN_LEN, CustomTracks.MAX_LEN)))
		selected = ops.size() - 1
		_armed = ""
		preview.armed = Callable()
		_commit()
		return
	var start := preview.growth_point(CustomTracks.finish_index(ops) if has_finish else ops.size())
	if has_finish:
		# A piece cannot go after the finish line, so it lands just before it.
		var fin: Dictionary = ops[CustomTracks.finish_index(ops)]
		ops.remove_at(CustomTracks.finish_index(ops))
		_place_armed(w, start)
		ops.append(fin)
	else:
		_place_armed(w, start)
	selected = ops.size() - 1
	# One piece per pick: the palette goes back to "nothing armed", so a stray grid
	# tap cannot add a piece the player did not ask for. Re-arm to place again.
	_armed = ""
	preview.armed = Callable()
	_commit()
	# Deliberately no `fit()` here. Re-framing the whole track after a placement
	# moves the view out from under the pointer, so the piece appears to snap to
	# somewhere other than where it was tapped. The camera stays where the player
	# put it; `Fit` is a button for when they do want the whole track in view.


func _place_armed(w: Vector2, start: Vector2) -> void:
	match _armed:
		"straight":
			# The tapped cell sets the length: the distance from where the road ends
			# now to the cell the player pointed at.
			var d := w.distance_to(start)
			ops.append(CustomTracks.make_straight(clampf(d, CustomTracks.MIN_LEN, CustomTracks.MAX_LEN)))
		_:
			# A turn is exactly the tile that was picked, including its direction. It
			# does not depend on where the grid was tapped: the player has already chosen
			# the piece, so the tap only says "put it on the road".
			var deg := PieceIcon.turn_deg(_armed)
			if deg == 0:
				return
			ops.append(CustomTracks.make_corner(deg, CustomTracks.DEFAULT_RADIUS,
					_armed.begins_with("reattach")))


# --- the sheet ---------------------------------------------------------------

func _build_sheet() -> void:
	sheet = PanelContainer.new()
	sheet.theme_type_variation = "SubCard"
	sheet.visible = false
	sheet.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	for side in ["left", "right", "top", "bottom"]:
		sheet.add_theme_constant_override("margin_" + side, 16)
	add_child(sheet)

	var col := VBoxContainer.new()
	col.add_theme_constant_override("separation", 8)
	sheet.add_child(col)

	var head := HBoxContainer.new()
	head.add_theme_constant_override("separation", 8)
	col.add_child(head)
	sheet_title = Label.new()
	sheet_title.add_theme_font_size_override("font_size", 18)
	sheet_title.add_theme_color_override("font_color", UiTheme.INK)
	sheet_title.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	head.add_child(sheet_title)
	var close := Button.new()
	close.theme_type_variation = "IconButton"
	close.focus_mode = Control.FOCUS_NONE
	close.custom_minimum_size = Vector2(40, 40)
	close.pressed.connect(_close_sheet)
	_icon_into(close, "close", UiTheme.INK_DIM)
	head.add_child(close)

	sheet_scroll = ScrollContainer.new()
	sheet_scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	sheet_scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	col.add_child(sheet_scroll)
	sheet_box = VBoxContainer.new()
	sheet_box.add_theme_constant_override("separation", 10)
	sheet_box.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	sheet_scroll.add_child(sheet_box)


func _open_sheet(title: String) -> void:
	for c in sheet_box.get_children():
		c.queue_free()
	sheet_title.text = title
	sheet.visible = true


func _close_sheet() -> void:
	if sheet != null:
		sheet.visible = false


func _open_look() -> void:
	_open_sheet("Colours")
	_build_look(sheet_box)
	_apply_theme_live()


func _open_piece(i: int) -> void:
	if i < 0 or i >= ops.size():
		return
	_open_sheet("Piece %d" % (i + 1))
	_build_inspect(sheet_box, i)


# --- selected piece ----------------------------------------------------------

func _build_inspect(target: VBoxContainer, i: int) -> void:
	var p: Dictionary = ops[i]
	target.add_child(_hint(CustomTracks.describe(p)))

	if CustomTracks.is_finish(p):
		# The finish is a straight with a line across its end, so the only thing to
		# adjust is how long the run-in to the line is.
		target.add_child(_slider_row("Length", float(p["len"]), CustomTracks.MIN_LEN,
			CustomTracks.MAX_LEN, CustomTracks.LEN_STEP, func(v): _set_len(i, v), []))
	elif CustomTracks.is_corner(p):
		var deg := absi(int(p["deg"]))
		var row := HBoxContainer.new()
		row.add_theme_constant_override("separation", 6)
		target.add_child(row)
		for a in CustomTracks.ANGLES:
			var ang: int = a
			var b := Button.new()
			b.toggle_mode = true
			b.theme_type_variation = "ToggleButton"
			b.button_pressed = deg == ang
			b.text = "%d\u00b0" % ang
			b.focus_mode = Control.FOCUS_NONE
			b.size_flags_horizontal = Control.SIZE_EXPAND_FILL
			b.custom_minimum_size = Vector2(0, 42)
			b.pressed.connect(func(): _set_deg(i, ang))
			row.add_child(b)

		target.add_child(_slider_row("Radius", float(p["r"]), CustomTracks.MIN_RADIUS,
			CustomTracks.MAX_RADIUS, CustomTracks.RADIUS_STEP, func(v): _set_radius(i, v), []))

		var dir_row := HBoxContainer.new()
		dir_row.add_theme_constant_override("separation", 6)
		target.add_child(dir_row)
		var left := Button.new()
		left.toggle_mode = true
		left.theme_type_variation = "ToggleButton"
		left.button_pressed = int(p["deg"]) < 0
		left.text = "Left"
		left.focus_mode = Control.FOCUS_NONE
		left.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		left.custom_minimum_size = Vector2(0, 42)
		left.pressed.connect(func():
			if int(ops[i]["deg"]) < 0:
				_flip_dir(i))
		dir_row.add_child(left)
		var right := Button.new()
		right.toggle_mode = true
		right.theme_type_variation = "ToggleButton"
		right.button_pressed = int(p["deg"]) > 0
		right.text = "Right"
		right.focus_mode = Control.FOCUS_NONE
		right.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		right.custom_minimum_size = Vector2(0, 42)
		right.pressed.connect(func():
			if int(ops[i]["deg"]) > 0:
				_flip_dir(i))
		dir_row.add_child(right)

		var re := Button.new()
		re.toggle_mode = true
		re.theme_type_variation = "ToggleButton"
		re.button_pressed = bool(p.get("reattach", false))
		re.text = "Reattach pillar"
		re.focus_mode = Control.FOCUS_NONE
		re.custom_minimum_size = Vector2(0, 42)
		re.pressed.connect(func(): _toggle_reattach(i))
		target.add_child(re)
	else:
		target.add_child(_slider_row("Length", float(p["len"]), CustomTracks.MIN_LEN,
			CustomTracks.MAX_LEN, CustomTracks.LEN_STEP, func(v): _set_len(i, v), []))

	var actions := HBoxContainer.new()
	actions.add_theme_constant_override("separation", 6)
	target.add_child(actions)
	actions.add_child(_action_button("copy", "Duplicate", func(): _duplicate(i)))
	actions.add_child(_action_button("trash", "Delete", func(): _remove_at(i)))


# --- piece editing -----------------------------------------------------------

func _on_piece_picked(i: int) -> void:
	selected = i
	_open_piece(i)
	if preview != null:
		preview.selected = selected
		preview.queue_redraw()


func _duplicate(i: int) -> void:
	if i < 0 or i >= ops.size() or ops.size() >= CustomTracks.MAX_PIECES:
		return
	_push_undo()
	ops.insert(i + 1, (ops[i] as Dictionary).duplicate(true))
	selected = i + 1
	_commit()
	_close_sheet()


func _remove_at(i: int) -> void:
	if i < 0 or i >= ops.size():
		return
	_push_undo()
	ops.remove_at(i)
	if selected >= ops.size():
		selected = ops.size() - 1
	_commit()
	_close_sheet()


func _set_radius(i: int, value: float) -> void:
	if i < 0 or i >= ops.size():
		return
	ops[i]["r"] = clampf(value, CustomTracks.MIN_RADIUS, CustomTracks.MAX_RADIUS)
	_apply_live(i)


func _set_len(i: int, value: float) -> void:
	if i < 0 or i >= ops.size():
		return
	ops[i]["len"] = clampf(value, CustomTracks.MIN_LEN, CustomTracks.MAX_LEN)
	_apply_live(i)


func _set_deg(i: int, value: int) -> void:
	if i < 0 or i >= ops.size():
		return
	_push_undo()
	ops[i]["deg"] = signi(int(ops[i]["deg"])) * value
	_commit()
	_open_piece(i)


func _flip_dir(i: int) -> void:
	if i < 0 or i >= ops.size() or not CustomTracks.is_corner(ops[i]):
		return
	_push_undo()
	ops[i]["deg"] = -int(ops[i]["deg"])
	_commit()
	_open_piece(i)


func _toggle_reattach(i: int) -> void:
	if i < 0 or i >= ops.size() or not CustomTracks.is_corner(ops[i]):
		return
	_push_undo()
	ops[i]["reattach"] = not bool(ops[i].get("reattach", false))
	_commit()
	_open_piece(i)


func _rename() -> void:
	if app == null:
		return
	app._ask_text("Rename track", track_name, func(value):
		CustomTracks.rename(id, value)
		var t: Variant = CustomTracks.get_track(id)
		if t != null:
			track_name = str(t["name"])
		if name_button != null:
			name_button.text = track_name
		changed.emit())


# --- undo --------------------------------------------------------------------

func _push_undo() -> void:
	_undo.append(ops.duplicate(true))
	if _undo.size() > UNDO_CAP:
		_undo.pop_front()
	if undo_button != null:
		undo_button.disabled = _undo.is_empty()


func _undo_last() -> void:
	if _undo.is_empty():
		return
	ops = _undo.pop_back()
	selected = clampi(selected, 0, ops.size() - 1)
	_commit()
	if undo_button != null:
		undo_button.disabled = _undo.is_empty()


# --- render ------------------------------------------------------------------

# A change that has to redraw the palette and the map (a piece added or removed).
func _commit() -> void:
	CustomTracks.update(id, ops)
	changed.emit()
	_rebuild()


# A change that only needs the model, the map and the readouts refreshed - used
# while a slider is being dragged, so the control under the finger is never
# destroyed and the drag keeps working.
func _apply_live(i: int) -> void:
	CustomTracks.update(id, ops)
	if preview != null:
		preview.rebuild(ops)
		preview.selected = selected
	_refresh_status()
	# Deliberately no `changed.emit()` here. It is emitted while a slider is being
	# dragged, and its listener rebuilds the menu's custom-track list - up to 100
	# buttons, each re-validated - which at 60fps made the editor seize. Nothing that
	# list shows (the name, the corner count) changes as a length slider moves, so the
	# list is refreshed on `_commit` instead, when the edit is finished.


func _refresh_status() -> void:
	var v := CustomTracks.validate(ops)
	var ok := bool(v["ok"])
	if play_button != null:
		play_button.disabled = not ok
	if status_label == null:
		return
	if _armed != "":
		status_label.text = "Tap the grid to place: %s" % _armed_name()
		status_label.add_theme_color_override("font_color", UiTheme.ACCENT)
	elif ok:
		status_label.text = "Ready \u00b7 %d corners \u00b7 %d pieces \u00b7 %.0f px" % [
			int(v["corners"]), ops.size(), float(v["length"])]
		status_label.add_theme_color_override("font_color", UiTheme.INK_DIM)
	elif ops.is_empty():
		# A new track is blank, not broken: an empty canvas is the starting state, so
		# it reads as a hint rather than the red error an invalid track gets.
		status_label.text = "Pick a piece below, then tap the grid to place it."
		status_label.add_theme_color_override("font_color", UiTheme.INK_MUTE)
	else:
		status_label.text = str(v["error"])
		status_label.add_theme_color_override("font_color", UiTheme.DANGER)


# The palette tile's tooltip is its name; the tile itself is a picture, so there is
# no text on the button to read back.
func _armed_name() -> String:
	var b: Variant = _palette_buttons.get(_armed)
	return (b as Button).tooltip_text if b != null else _armed


func _rebuild() -> void:
	if status_label == null:
		return
	if name_button != null:
		name_button.text = track_name
	_paint_palette()
	preview.palette = palette
	preview.selected = selected
	preview.rebuild(ops)
	_refresh_status()
	if undo_button != null:
		undo_button.disabled = _undo.is_empty()


func _fit_soon() -> void:
	await get_tree().process_frame
	if not is_instance_valid(preview):
		return
	# `rebuild` runs before the map has a size, so the empty-canvas centring is a
	# no-op there; do it now that the rect is real. A track with a road is fitted.
	if preview.ok:
		preview.fit()
	else:
		preview.centre_on_road_start()


func _entry() -> Dictionary:
	return {"road": str(palette.get("road", "")), "ground": str(palette.get("ground", ""))}


# --- colours (the Look sheet) ------------------------------------------------

func _build_look(target: VBoxContainer) -> void:
	var sw := PanelContainer.new()
	sw.theme_type_variation = "SubCard"
	var srow := HBoxContainer.new()
	srow.add_theme_constant_override("separation", 6)
	sw.add_child(srow)
	var ground := ColorRect.new()
	ground.color = Color(str(palette["ground"]))
	ground.custom_minimum_size = Vector2(0, 40)
	ground.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	ground.mouse_filter = Control.MOUSE_FILTER_IGNORE
	srow.add_child(ground)
	_swatch = ColorRect.new()
	_swatch.color = Color(str(palette["road"]))
	_swatch.custom_minimum_size = Vector2(0, 40)
	_swatch.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_swatch.mouse_filter = Control.MOUSE_FILTER_IGNORE
	srow.add_child(_swatch)
	target.add_child(sw)

	target.add_child(_section("Presets"))
	var grid := GridContainer.new()
	grid.columns = 2
	grid.add_theme_constant_override("h_separation", 6)
	grid.add_theme_constant_override("v_separation", 6)
	grid.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	target.add_child(grid)
	for preset in CustomTracks.THEME_PRESETS:
		grid.add_child(_preset_button(preset))

	target.add_child(_color_section("Road colour", "road"))
	target.add_child(_color_section("Background colour", "ground"))


func _color_section(title: String, key: String) -> Control:
	var card := PanelContainer.new()
	card.theme_type_variation = "SubCard"
	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 8)
	card.add_child(box)
	box.add_child(_section(title))

	var head := HBoxContainer.new()
	head.add_theme_constant_override("separation", 8)
	box.add_child(head)
	var hex := LineEdit.new()
	hex.text = str(palette[key])
	hex.max_length = 6
	hex.placeholder_text = "RRGGBB"
	hex.custom_minimum_size = Vector2(110, 40)
	hex.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	hex.text_submitted.connect(func(t): _set_hex(key, t))
	hex.focus_exited.connect(func(): _set_hex(key, hex.text))
	head.add_child(hex)
	if key == "road":
		_road_hex = hex
	else:
		_ground_hex = hex

	# The three channel sliders keep their refs so one drag can update the other two
	# and the hex box without rebuilding the page under the finger.
	var sliders: Array = []
	var labels: Array = []
	for idx in range(3):
		var i: int = idx
		var row := VBoxContainer.new()
		row.add_theme_constant_override("separation", 4)
		var rhead := HBoxContainer.new()
		rhead.add_theme_constant_override("separation", 8)
		row.add_child(rhead)
		var l := Label.new()
		l.text = ["R", "G", "B"][i]
		l.add_theme_font_size_override("font_size", 13)
		l.add_theme_color_override("font_color", UiTheme.INK_DIM)
		l.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		rhead.add_child(l)
		var val := Label.new()
		val.text = str(_channel(key, i))
		val.add_theme_font_size_override("font_size", 13)
		rhead.add_child(val)
		var slider := HSlider.new()
		slider.min_value = 0.0
		slider.max_value = 255.0
		slider.step = 1.0
		slider.value = float(_channel(key, i))
		slider.custom_minimum_size = Vector2(0, 34)
		slider.value_changed.connect(func(v): _set_channel(key, i, v))
		slider.drag_ended.connect(func(_changed): _persist_theme())
		row.add_child(slider)
		box.add_child(row)
		sliders.append(slider)
		labels.append(val)
	if key == "road":
		_road_sliders = sliders
		_road_labels = labels
	else:
		_ground_sliders = sliders
		_ground_labels = labels
	return card


func _channel(key: String, idx: int) -> int:
	var c := Color(str(palette[key]))
	return [roundi(c.r * 255.0), roundi(c.g * 255.0), roundi(c.b * 255.0)][idx]


func _set_channel(key: String, idx: int, value: float) -> void:
	if _syncing:
		return
	var c := Color(str(palette[key]))
	var v := clampf(value / 255.0, 0.0, 1.0)
	if idx == 0:
		c.r = v
	elif idx == 1:
		c.g = v
	else:
		c.b = v
	palette[key] = c.to_html(false).to_upper()
	_apply_theme_live()


func _set_hex(key: String, text: String) -> void:
	var v := text.strip_edges().lstrip("#")
	if v.length() != 6 or not _is_hex(v):
		return
	palette[key] = v.to_upper()
	_apply_theme_live()
	_persist_theme()


func _is_hex(v: String) -> bool:
	for i in range(v.length()):
		if not "0123456789abcdefABCDEF".contains(v[i]):
			return false
	return true


# Refresh every control and the map from `palette`, without touching storage - used
# on each slider tick, so a drag never writes the file per frame.
func _apply_theme_live() -> void:
	if preview != null:
		preview.palette = palette
		preview.queue_redraw()
	if _swatch != null:
		_swatch.color = Color(str(palette["road"]))
	_sync_color("road")
	_sync_color("ground")
	_refresh_status()
	changed.emit()


func _persist_theme() -> void:
	CustomTracks.set_theme(id, str(palette["road"]), str(palette["ground"]))


func _sync_color(key: String) -> void:
	_syncing = true
	var c := Color(str(palette[key]))
	var comps := [c.r, c.g, c.b]
	var sliders: Array = _road_sliders if key == "road" else _ground_sliders
	var labels: Array = _road_labels if key == "road" else _ground_labels
	for i in range(mini(3, sliders.size())):
		(sliders[i] as HSlider).value = comps[i] * 255.0
		(labels[i] as Label).text = str(roundi(comps[i] * 255.0))
	var hex: LineEdit = _road_hex if key == "road" else _ground_hex
	if hex != null and not hex.has_focus():
		hex.text = str(palette[key])
	_syncing = false


func _preset_button(preset: Dictionary) -> Button:
	var b := Button.new()
	b.custom_minimum_size = Vector2(0, 44)
	b.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	b.focus_mode = Control.FOCUS_NONE
	b.pressed.connect(func(): _apply_preset(preset))
	var box := HBoxContainer.new()
	box.alignment = BoxContainer.ALIGNMENT_CENTER
	box.add_theme_constant_override("separation", 8)
	box.set_anchors_preset(Control.PRESET_FULL_RECT)
	box.mouse_filter = Control.MOUSE_FILTER_IGNORE
	b.add_child(box)
	var dot := ColorRect.new()
	dot.color = Color(str(preset["ground"]))
	dot.custom_minimum_size = Vector2(20, 20)
	dot.mouse_filter = Control.MOUSE_FILTER_IGNORE
	box.add_child(dot)
	var l := Label.new()
	l.text = str(preset["name"])
	l.add_theme_font_size_override("font_size", 13)
	l.mouse_filter = Control.MOUSE_FILTER_IGNORE
	box.add_child(l)
	return b


func _apply_preset(preset: Dictionary) -> void:
	palette["road"] = str(preset["road"])
	palette["ground"] = str(preset["ground"])
	_apply_theme_live()
	_persist_theme()
	_open_look()


# --- small builders ----------------------------------------------------------

func _section(text: String) -> Label:
	var l := Label.new()
	l.text = text.to_upper()
	l.add_theme_font_size_override("font_size", 13)
	l.add_theme_color_override("font_color", UiTheme.ACCENT)
	return l


func _hint(text: String) -> Label:
	var l := Label.new()
	l.text = text
	l.add_theme_font_size_override("font_size", 12)
	l.add_theme_color_override("font_color", UiTheme.INK_MUTE)
	l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	return l


func _mini_text(text: String, cb: Callable) -> Button:
	var b := Button.new()
	b.text = text
	b.focus_mode = Control.FOCUS_NONE
	b.custom_minimum_size = Vector2(52, 36)
	b.pressed.connect(cb)
	return b


func _action_button(icon_kind: String, text: String, cb: Callable) -> Button:
	var b := Button.new()
	b.clip_text = true
	b.focus_mode = Control.FOCUS_NONE
	b.custom_minimum_size = Vector2(0, 46)
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
	ic.color = UiTheme.INK_DIM
	ic.thickness = 2.0
	ic.custom_minimum_size = Vector2(18, 18)
	ic.mouse_filter = Control.MOUSE_FILTER_IGNORE
	box.add_child(ic)
	var l := Label.new()
	l.text = text
	l.add_theme_font_size_override("font_size", 14)
	l.mouse_filter = Control.MOUSE_FILTER_IGNORE
	box.add_child(l)
	return b


func _icon_into(b: Button, icon_kind: String, color: Color) -> void:
	var ic := UiIcon.new()
	ic.kind = icon_kind
	ic.color = color
	ic.thickness = 2.0
	ic.set_anchors_preset(Control.PRESET_FULL_RECT)
	ic.offset_left = 8
	ic.offset_right = -8
	ic.offset_top = 8
	ic.offset_bottom = -8
	ic.mouse_filter = Control.MOUSE_FILTER_IGNORE
	b.add_child(ic)


func _slider_row(label: String, value: float, lo: float, hi: float, step: float, cb: Callable, out_vals: Array) -> Control:
	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 4)
	var head := HBoxContainer.new()
	head.add_theme_constant_override("separation", 8)
	box.add_child(head)
	var l := Label.new()
	l.text = label
	l.add_theme_font_size_override("font_size", 13)
	l.add_theme_color_override("font_color", UiTheme.INK_DIM)
	l.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	head.add_child(l)
	var val := Label.new()
	val.text = "%d" % roundi(value)
	val.add_theme_font_size_override("font_size", 13)
	head.add_child(val)
	if out_vals.is_empty():
		out_vals.append(val)
	else:
		out_vals[0] = val
	var slider := HSlider.new()
	slider.min_value = lo
	slider.max_value = hi
	slider.step = step
	slider.value = value
	slider.custom_minimum_size = Vector2(0, 34)
	slider.value_changed.connect(func(v):
		val.text = "%d" % roundi(v)
		cb.call(v))
	# The live callback only repaints (see `_apply_live`); the menu's list is refreshed
	# once here, when the finger lets go, so dragging a slider cannot rebuild it per frame.
	slider.drag_ended.connect(func(_changed: bool): changed.emit())
	box.add_child(slider)
	return box


func _on_close() -> void:
	CustomTracks.update(id, ops)
	CustomTracks.set_theme(id, str(palette.get("road", "")), str(palette.get("ground", "")))
	closed.emit()
