extends Control
class_name TrackEditor

# The track editor: a full-screen overlay that authors a custom track's op list.
#
# The model is `CustomTracks` (the same op list `Track.build_ops` walks) and the map
# is a `TrackPreview`, so what is edited is exactly the road the game drives. The
# editor owns only the editing session; `App` owns the list, the persistence and the
# launch into a run.
#
# Layout is responsive. On a phone the map is pinned on top and the controls scroll
# beneath it; on a wide window the map takes the left half and the controls the
# right. The split is decided in `_apply_layout` from the editor's own size, so one
# build reads correctly on a phone, a tablet and a desktop. The two panels live in a
# single BoxContainer whose orientation flips, so a resize never re-parents them and
# the map's camera and the scroll position survive.
#
# The controls are three pages behind a segmented switch - Build, Look, Help - so no
# page is a wall of controls. Build authors the pieces and edits the selected one;
# Look picks the road and background colours; Help explains the game and the editor.

signal closed()
signal play_requested()
signal changed()

const UNDO_CAP := 40
const WIDE_MIN := 700.0

var app = null                  # the App root; untyped to call its handlers
var id := 0
var track_name := ""

var ops: Array = []
var palette := {}               # {"road": "RRGGBB", "ground": "RRGGBB"}
var selected := -1
var _undo: Array = []

var _page := "build"
var _wide := false

var preview: TrackPreview
var name_button: Button
var status_label: Label
var play_button: Button
var undo_button: Button
var body: BoxContainer
var map_panel: VBoxContainer
var control_scroll: ScrollContainer
var control_box: VBoxContainer
var page_box: VBoxContainer
var _page_buttons := {}
var _row_buttons := {}

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
	_page = "build"
	visible = true
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

	body = BoxContainer.new()
	body.add_theme_constant_override("separation", 10)
	body.size_flags_vertical = Control.SIZE_EXPAND_FILL
	col.add_child(body)

	map_panel = VBoxContainer.new()
	map_panel.add_theme_constant_override("separation", 6)
	body.add_child(map_panel)

	preview = TrackPreview.new()
	preview.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	preview.size_flags_vertical = Control.SIZE_EXPAND_FILL
	preview.piece_picked.connect(_on_piece_picked)
	map_panel.add_child(preview)
	map_panel.add_child(_build_camera_row())

	control_scroll = ScrollContainer.new()
	control_scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	control_box = VBoxContainer.new()
	control_box.add_theme_constant_override("separation", 10)
	control_box.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	control_scroll.add_child(control_box)
	body.add_child(control_scroll)

	control_box.add_child(_build_segments())
	page_box = VBoxContainer.new()
	page_box.add_theme_constant_override("separation", 10)
	page_box.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	control_box.add_child(page_box)

	resized.connect(_on_resized)
	_apply_layout()


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

	play_button = Button.new()
	play_button.theme_type_variation = "PrimaryButton"
	play_button.text = "Play"
	play_button.focus_mode = Control.FOCUS_NONE
	play_button.custom_minimum_size = Vector2(88, 40)
	play_button.pressed.connect(func(): play_requested.emit())
	row.add_child(play_button)


func _build_camera_row() -> Control:
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 6)
	row.add_child(_mini_text("Fit", func(): preview.fit()))
	row.add_child(_mini_text("-", func(): preview.zoom_by(1.0 / 1.3)))
	row.add_child(_mini_text("+", func(): preview.zoom_by(1.3)))
	var hint := Label.new()
	hint.text = "Drag to pan \u00b7 tap a piece to select"
	hint.add_theme_font_size_override("font_size", 12)
	hint.add_theme_color_override("font_color", UiTheme.INK_MUTE)
	hint.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	hint.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	hint.clip_text = true
	row.add_child(hint)
	return row


func _build_segments() -> Control:
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 6)
	var group := ButtonGroup.new()
	for page in ["build", "look", "help"]:
		var p: String = page
		var b := Button.new()
		b.toggle_mode = true
		b.theme_type_variation = "ToggleButton"
		b.button_group = group
		b.text = p.capitalize()
		b.focus_mode = Control.FOCUS_NONE
		b.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		b.custom_minimum_size = Vector2(0, 40)
		b.button_pressed = p == _page
		b.pressed.connect(func(): _switch_page(p))
		_page_buttons[p] = b
		row.add_child(b)
	return row


func _on_resized() -> void:
	_apply_layout()


func _apply_layout() -> void:
	if body == null:
		return
	var want_wide := size.x >= WIDE_MIN or size.x > size.y * 1.15
	var flipped := want_wide != _wide
	_wide = want_wide
	# A BoxContainer flips orientation in place, so the two panels are never
	# re-parented and their state (scroll position, camera) survives a resize.
	body.vertical = not want_wide
	if want_wide:
		map_panel.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		map_panel.size_flags_vertical = Control.SIZE_EXPAND_FILL
		map_panel.custom_minimum_size = Vector2(0, 0)
		control_scroll.size_flags_horizontal = Control.SIZE_FILL
		control_scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
		control_scroll.custom_minimum_size = Vector2(380, 0)
	else:
		map_panel.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		map_panel.size_flags_vertical = Control.SIZE_FILL
		map_panel.custom_minimum_size = Vector2(0, clampf(size.y * 0.34, 190.0, 330.0))
		control_scroll.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		control_scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
		control_scroll.custom_minimum_size = Vector2(0, 0)
	if flipped:
		_fit_soon()


func _fit_soon() -> void:
	await get_tree().process_frame
	if is_instance_valid(preview) and preview.ok:
		preview.fit()


# --- pages -------------------------------------------------------------------

func _switch_page(page: String) -> void:
	if _page == page:
		return
	_page = page
	for k in _page_buttons.keys():
		(_page_buttons[k] as Button).button_pressed = k == page
	_build_page()


func _build_page() -> void:
	for c in page_box.get_children():
		c.queue_free()
	_row_buttons = {}
	_swatch = null
	_road_sliders = []
	_road_labels = []
	_ground_sliders = []
	_ground_labels = []
	_road_hex = null
	_ground_hex = null
	match _page:
		"look":
			_build_look()
		"help":
			_build_help()
		_:
			_build_build()


# --- Build page --------------------------------------------------------------

func _build_build() -> void:
	page_box.add_child(_section("Add a piece"))
	var card := PanelContainer.new()
	card.theme_type_variation = "SubCard"
	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 8)
	card.add_child(box)
	page_box.add_child(card)

	box.add_child(_piece_button("Straight", func(): _add(CustomTracks.make_straight())))
	var corners := HBoxContainer.new()
	corners.add_theme_constant_override("separation", 6)
	box.add_child(corners)
	for deg in CustomTracks.ANGLES:
		var d: int = deg
		corners.add_child(_piece_button("%d\u00b0" % d, func(): _add(CustomTracks.next_corner(ops, d))))
	box.add_child(_piece_button("Reattach corner", _add_reattach))
	box.add_child(_hint("New pieces go on the end. Corners alternate left and right automatically; tap a piece below to change it."))

	var head := HBoxContainer.new()
	head.add_theme_constant_override("separation", 8)
	page_box.add_child(head)
	var s := _section("Pieces")
	s.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	head.add_child(s)
	var count := Label.new()
	count.text = "%d / %d" % [ops.size(), CustomTracks.MAX_PIECES]
	count.add_theme_font_size_override("font_size", 13)
	count.add_theme_color_override("font_color", UiTheme.INK_MUTE)
	head.add_child(count)

	var stack := VBoxContainer.new()
	stack.add_theme_constant_override("separation", 6)
	stack.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	page_box.add_child(stack)

	if ops.is_empty():
		stack.add_child(_hint("No pieces yet. Add a straight or a corner above."))
	for i in range(ops.size()):
		stack.add_child(_piece_row(i))

	if selected >= 0 and selected < ops.size():
		page_box.add_child(_inspect(selected))


# --- Look page ---------------------------------------------------------------

func _build_look() -> void:
	page_box.add_child(_section("Preview"))
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
	page_box.add_child(sw)

	page_box.add_child(_section("Presets"))
	var grid := GridContainer.new()
	grid.columns = 2
	grid.add_theme_constant_override("h_separation", 6)
	grid.add_theme_constant_override("v_separation", 6)
	grid.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	page_box.add_child(grid)
	for preset in CustomTracks.THEME_PRESETS:
		grid.add_child(_preset_button(preset))

	page_box.add_child(_color_section("Road colour", "road"))
	page_box.add_child(_color_section("Background colour", "ground"))


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
	_rebuild()


# --- Help page ---------------------------------------------------------------

func _build_help() -> void:
	var card := PanelContainer.new()
	card.theme_type_variation = "SubCard"
	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 8)
	card.add_child(box)
	page_box.add_child(card)
	box.add_child(_section("How to drive"))
	box.add_child(_hint("Hold the button to sling the car around a pole. Let go to fly straight to the next one. Leave the road and the run is over."))
	box.add_child(_hint("Tap Play to try the track at any time. The run is saved on this device - custom tracks are not uploaded."))
	box.add_child(_section("How to build"))
	box.add_child(_hint("Add a piece: a Straight, or a corner of 90\u00b0, 180\u00b0 or 270\u00b0. Corners alternate left and right so the road does not fold back on itself."))
	box.add_child(_hint("Tap a piece in the list - or on the map - to select it, then change its length, angle, radius or direction. Use the arrows to move it, the bin to delete it."))
	box.add_child(_hint("The map is a camera: drag to pan, pinch or the + / - buttons to zoom, Fit to see the whole road."))
	box.add_child(_section("Rules"))
	box.add_child(_hint("A track needs at least 2 corners and the road must be drivable: corners must be at least 40 wide and no more than 92 (a wider pole cannot be reached). Play stays disabled while something is wrong, and the reason is shown at the top."))


# --- pieces ------------------------------------------------------------------

func _piece_row(i: int) -> Control:
	var card := PanelContainer.new()
	card.theme_type_variation = "SubCard"
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 6)
	card.add_child(row)

	var pick := Button.new()
	pick.toggle_mode = true
	pick.theme_type_variation = "ToggleButton"
	pick.button_pressed = i == selected
	pick.clip_text = true
	pick.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	pick.custom_minimum_size = Vector2(0, 42)
	pick.text = "%d. %s" % [i + 1, CustomTracks.describe(ops[i])]
	pick.pressed.connect(func(): _select(i))
	row.add_child(pick)
	_row_buttons[i] = pick

	row.add_child(_mini_button("up", func(): _move(i, -1)))
	row.add_child(_mini_button("down", func(): _move(i, 1)))
	row.add_child(_mini_button("trash", func(): _remove_at(i)))
	return card


func _inspect(i: int) -> Control:
	var p: Dictionary = ops[i]
	var card := PanelContainer.new()
	card.theme_type_variation = "SubCard"
	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 8)
	card.add_child(box)

	box.add_child(_section("Edit \u00b7 %d. %s" % [i + 1, CustomTracks.describe(p)]))

	if CustomTracks.is_corner(p):
		var deg := absi(int(p["deg"]))
		var row := HBoxContainer.new()
		row.add_theme_constant_override("separation", 6)
		box.add_child(row)
		for a in CustomTracks.ANGLES:
			var ang: int = a
			var b := Button.new()
			b.toggle_mode = true
			b.theme_type_variation = "ToggleButton"
			b.button_pressed = deg == ang
			b.text = "%d\u00b0" % ang
			b.size_flags_horizontal = Control.SIZE_EXPAND_FILL
			b.custom_minimum_size = Vector2(0, 42)
			b.pressed.connect(func(): _set_deg(i, ang))
			row.add_child(b)

		box.add_child(_slider_row("Radius", float(p["r"]), CustomTracks.MIN_RADIUS, CustomTracks.MAX_RADIUS, CustomTracks.RADIUS_STEP, func(v): _set_radius(i, v), []))

		var dir_row := HBoxContainer.new()
		dir_row.add_theme_constant_override("separation", 6)
		box.add_child(dir_row)
		var left := Button.new()
		left.toggle_mode = true
		left.theme_type_variation = "ToggleButton"
		left.button_pressed = int(p["deg"]) > 0
		left.text = "Left"
		left.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		left.custom_minimum_size = Vector2(0, 42)
		left.pressed.connect(func():
			if int(ops[i]["deg"]) < 0:
				_flip_dir(i))
		dir_row.add_child(left)
		var right := Button.new()
		right.toggle_mode = true
		right.theme_type_variation = "ToggleButton"
		right.button_pressed = int(p["deg"]) < 0
		right.text = "Right"
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
		re.custom_minimum_size = Vector2(0, 42)
		re.pressed.connect(func(): _toggle_reattach(i))
		box.add_child(re)
		box.add_child(_hint("Bail out early and you can catch this pole again for a slingshot."))
	else:
		box.add_child(_slider_row("Length", float(p["len"]), CustomTracks.MIN_LEN, CustomTracks.MAX_LEN, CustomTracks.LEN_STEP, func(v): _set_len(i, v), []))

	var actions := HBoxContainer.new()
	actions.add_theme_constant_override("separation", 6)
	box.add_child(actions)
	actions.add_child(_action_button("copy", "Duplicate", func(): _duplicate(i)))
	actions.add_child(_action_button("trash", "Delete", func(): _remove_at(i)))
	return card


# --- piece editing -----------------------------------------------------------

func _select(i: int) -> void:
	selected = i
	_rebuild()


func _on_piece_picked(i: int) -> void:
	selected = i
	if _page != "build":
		_page = "build"
		for k in _page_buttons.keys():
			(_page_buttons[k] as Button).button_pressed = k == _page
	_rebuild()
	_scroll_to(i)


func _add(piece: Dictionary) -> void:
	if ops.size() >= CustomTracks.MAX_PIECES:
		return
	_push_undo()
	ops.append(piece)
	selected = ops.size() - 1
	_commit()
	_scroll_to(selected)


func _add_reattach() -> void:
	if ops.size() >= CustomTracks.MAX_PIECES:
		return
	_push_undo()
	var c := CustomTracks.next_corner(ops, 90)
	c["reattach"] = true
	ops.append(c)
	selected = ops.size() - 1
	_commit()
	_scroll_to(selected)


func _duplicate(i: int) -> void:
	if i < 0 or i >= ops.size() or ops.size() >= CustomTracks.MAX_PIECES:
		return
	_push_undo()
	ops.insert(i + 1, (ops[i] as Dictionary).duplicate(true))
	selected = i + 1
	_commit()
	_scroll_to(selected)


func _remove_at(i: int) -> void:
	if i < 0 or i >= ops.size():
		return
	_push_undo()
	ops.remove_at(i)
	if selected >= ops.size():
		selected = ops.size() - 1
	_commit()


func _move(i: int, delta: int) -> void:
	var j := i + delta
	if i < 0 or i >= ops.size() or j < 0 or j >= ops.size():
		return
	_push_undo()
	var tmp = ops[i]
	ops[i] = ops[j]
	ops[j] = tmp
	selected = j
	_commit()
	_scroll_to(j)


func _transform(fn: Callable) -> void:
	if ops.size() == 0:
		return
	_push_undo()
	ops = fn.call(ops)
	selected = clampi(selected, 0, ops.size() - 1)
	_commit()


func _clear() -> void:
	if ops.size() == 0:
		return
	_push_undo()
	ops = []
	selected = -1
	_commit()


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


func _flip_dir(i: int) -> void:
	if i < 0 or i >= ops.size() or not CustomTracks.is_corner(ops[i]):
		return
	_push_undo()
	ops[i]["deg"] = -int(ops[i]["deg"])
	_commit()


func _toggle_reattach(i: int) -> void:
	if i < 0 or i >= ops.size() or not CustomTracks.is_corner(ops[i]):
		return
	_push_undo()
	ops[i]["reattach"] = not bool(ops[i].get("reattach", false))
	_commit()


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

# A change that has to redraw the whole page (a piece added, moved or removed).
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
	if _row_buttons.has(i) and i >= 0 and i < ops.size():
		(_row_buttons[i] as Button).text = "%d. %s" % [i + 1, CustomTracks.describe(ops[i])]
	_refresh_status()
	changed.emit()


func _refresh_status() -> void:
	var v := CustomTracks.validate(ops)
	var ok := bool(v["ok"])
	if play_button != null:
		play_button.disabled = not ok
	if status_label == null:
		return
	if ok:
		status_label.text = "Ready \u00b7 %d corners \u00b7 %d pieces \u00b7 %.0f px" % [int(v["corners"]), ops.size(), float(v["length"])]
		status_label.add_theme_color_override("font_color", UiTheme.INK_DIM)
	else:
		status_label.text = str(v["error"])
		status_label.add_theme_color_override("font_color", UiTheme.DANGER)


func _rebuild() -> void:
	if status_label == null:
		return
	if name_button != null:
		name_button.text = track_name
	for k in _page_buttons.keys():
		(_page_buttons[k] as Button).button_pressed = k == _page
	preview.palette = palette
	preview.selected = selected
	preview.rebuild(ops)
	_refresh_status()
	if undo_button != null:
		undo_button.disabled = _undo.is_empty()
	_build_page()


func _scroll_to(i: int) -> void:
	if not _row_buttons.has(i) or control_scroll == null:
		return
	control_scroll.ensure_control_visible(_row_buttons[i])


func _entry() -> Dictionary:
	return {"road": str(palette.get("road", "")), "ground": str(palette.get("ground", ""))}


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


func _piece_button(text: String, cb: Callable) -> Button:
	var b := Button.new()
	b.text = text
	b.clip_text = true
	b.focus_mode = Control.FOCUS_NONE
	b.custom_minimum_size = Vector2(0, 46)
	b.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	b.pressed.connect(cb)
	return b


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


func _mini_button(icon_kind: String, cb: Callable) -> Button:
	var b := Button.new()
	b.theme_type_variation = "IconButton"
	b.focus_mode = Control.FOCUS_NONE
	b.custom_minimum_size = Vector2(38, 42)
	b.pressed.connect(cb)
	_icon_into(b, icon_kind, UiTheme.INK_DIM)
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
	box.add_child(slider)
	return box


func _on_close() -> void:
	CustomTracks.update(id, ops)
	CustomTracks.set_theme(id, str(palette.get("road", "")), str(palette.get("ground", "")))
	closed.emit()
