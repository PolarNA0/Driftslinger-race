extends Control
class_name TrackEditor

# The track editor: a full-screen overlay that authors a custom track's op list.
#
# The model is `CustomTracks` (the same op list `Track.build_ops` walks), and the
# preview is a `TrackPreview`, so what is edited is exactly the road the game
# drives. The editor owns only the editing session; `App` owns the list, the
# persistence and the launch into a run.
#
# Layout: the road map on top (it wants the space), then the piece palette, the
# list of the track's pieces with the selected one's controls, and the actions.
# Everything scrolls, because on a phone the map plus the controls are taller than
# the screen - the same rule the menu overlays follow.

signal closed()
signal play_requested()
signal changed()

const UNDO_CAP := 40

var app = null                  # the App root; untyped to call its handlers
var id := 0
var track_name := ""

var ops: Array = []
var selected := -1
var _undo: Array = []

var preview: TrackPreview
var name_label: Label
var status_label: Label
var piece_list: VBoxContainer
var piece_scroll: ScrollContainer
var inspect_box: VBoxContainer
var empty_label: Label
var play_button: Button
var undo_button: Button

var _card: VBoxContainer


func open_for(p_app, p_id: int) -> void:
	app = p_app
	id = p_id
	var t: Variant = CustomTracks.get_track(id)
	if t == null:
		return
	track_name = str(t["name"])
	ops = (t["ops"] as Array).duplicate(true)
	_undo = []
	selected = ops.size() - 1
	visible = true
	_rebuild()


func _ready() -> void:
	set_anchors_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_STOP
	visible = false

	var bg := ColorRect.new()
	bg.color = Color(0.03, 0.04, 0.08, 0.98)
	bg.set_anchors_preset(Control.PRESET_FULL_RECT)
	add_child(bg)

	var margin := MarginContainer.new()
	margin.set_anchors_preset(Control.PRESET_FULL_RECT)
	for side in ["left", "right", "top", "bottom"]:
		margin.add_theme_constant_override("margin_" + side, 10)
	add_child(margin)

	# The map and the palette stay put; only the piece list scrolls. On a phone the
	# whole editor is taller than the screen, so the parts a player reaches for most
	# (the map, the palette, Play) are pinned and the long list is the one that moves.
	var col := VBoxContainer.new()
	col.add_theme_constant_override("separation", 8)
	margin.add_child(col)
	_card = col

	_build_header(col)
	_build_preview(col)
	_build_palette(col)
	_build_pieces(col)
	_build_actions(col)


func _build_header(col: VBoxContainer) -> void:
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 8)
	col.add_child(row)

	var back := Button.new()
	back.theme_type_variation = "IconButton"
	back.focus_mode = Control.FOCUS_NONE
	back.custom_minimum_size = Vector2(40, 40)
	back.pressed.connect(_on_close)
	var bic := UiIcon.new()
	bic.kind = "back"
	bic.color = UiTheme.INK_DIM
	bic.thickness = 2.0
	bic.set_anchors_preset(Control.PRESET_FULL_RECT)
	bic.offset_left = 9
	bic.offset_right = -9
	bic.offset_top = 9
	bic.offset_bottom = -9
	bic.mouse_filter = Control.MOUSE_FILTER_IGNORE
	back.add_child(bic)
	row.add_child(back)

	name_label = Label.new()
	name_label.add_theme_font_size_override("font_size", 22)
	name_label.add_theme_color_override("font_color", UiTheme.ACCENT)
	name_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	name_label.clip_text = true
	name_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	row.add_child(name_label)

	undo_button = Button.new()
	undo_button.theme_type_variation = "IconButton"
	undo_button.focus_mode = Control.FOCUS_NONE
	undo_button.custom_minimum_size = Vector2(40, 40)
	undo_button.tooltip_text = "Undo"
	undo_button.pressed.connect(_undo_last)
	var uic := UiIcon.new()
	uic.kind = "undo"
	uic.color = UiTheme.INK_DIM
	uic.thickness = 2.0
	uic.set_anchors_preset(Control.PRESET_FULL_RECT)
	uic.offset_left = 9
	uic.offset_right = -9
	uic.offset_top = 9
	uic.offset_bottom = -9
	uic.mouse_filter = Control.MOUSE_FILTER_IGNORE
	undo_button.add_child(uic)
	row.add_child(undo_button)

	play_button = Button.new()
	play_button.theme_type_variation = "PrimaryButton"
	play_button.text = "Play"
	play_button.focus_mode = Control.FOCUS_NONE
	play_button.custom_minimum_size = Vector2(96, 40)
	play_button.pressed.connect(func(): play_requested.emit())
	row.add_child(play_button)

	status_label = Label.new()
	status_label.add_theme_font_size_override("font_size", 13)
	status_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	col.add_child(status_label)


func _build_preview(col: VBoxContainer) -> void:
	preview = TrackPreview.new()
	preview.custom_minimum_size = Vector2(0, 240)
	preview.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	col.add_child(preview)


func _build_palette(col: VBoxContainer) -> void:
	col.add_child(_section("Add a piece"))
	var card := PanelContainer.new()
	card.theme_type_variation = "SubCard"
	col.add_child(card)
	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 8)
	card.add_child(box)

	# A straight first: the road needs one between corners, and it is the piece a
	# player adds most.
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 6)
	box.add_child(row)
	row.add_child(_piece_button("Straight", func(): _add(CustomTracks.make_straight())))

	var corners := HBoxContainer.new()
	corners.add_theme_constant_override("separation", 6)
	box.add_child(corners)
	for deg in CustomTracks.ANGLES:
		var d: int = deg
		corners.add_child(_piece_button("%d\u00b0" % d, func(): _add(CustomTracks.next_corner(ops, d))))

	# A reattach pillar: the pillar stays live if you bail out early, so it can be
	# caught again. It is a per-corner flag, so the button adds one as a corner.
	var re_row := HBoxContainer.new()
	re_row.add_theme_constant_override("separation", 6)
	box.add_child(re_row)
	re_row.add_child(_piece_button("Reattach corner", _add_reattach))


func _build_pieces(col: VBoxContainer) -> void:
	var head := HBoxContainer.new()
	head.add_theme_constant_override("separation", 8)
	col.add_child(head)
	var s := _section("Pieces")
	s.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	head.add_child(s)

	# The piece list is the one part that grows without bound, so it is the part that
	# scrolls. It takes whatever height is left after the map, the palette and the
	# actions, so the editor fits a phone with no page scroll of its own.
	piece_scroll = ScrollContainer.new()
	piece_scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	piece_scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	piece_scroll.custom_minimum_size = Vector2(0, 120)
	col.add_child(piece_scroll)

	var stack := VBoxContainer.new()
	stack.add_theme_constant_override("separation", 6)
	stack.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	piece_scroll.add_child(stack)

	piece_list = VBoxContainer.new()
	piece_list.add_theme_constant_override("separation", 6)
	piece_list.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	stack.add_child(piece_list)

	empty_label = Label.new()
	empty_label.text = "No pieces yet. Add a straight or a corner above."
	empty_label.add_theme_font_size_override("font_size", 13)
	empty_label.add_theme_color_override("font_color", UiTheme.INK_MUTE)
	empty_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	stack.add_child(empty_label)

	inspect_box = VBoxContainer.new()
	inspect_box.add_theme_constant_override("separation", 8)
	inspect_box.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	stack.add_child(inspect_box)


func _build_actions(col: VBoxContainer) -> void:
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 6)
	col.add_child(row)
	row.add_child(_action_button("flip", "Mirror", func(): _transform(CustomTracks.mirror)))
	row.add_child(_action_button("undo", "Reverse", func(): _transform(CustomTracks.reverse)))
	row.add_child(_action_button("trash", "Clear", _clear))


# --- pieces ------------------------------------------------------------------

func _piece_button(text: String, cb: Callable) -> Button:
	var b := Button.new()
	b.text = text
	b.clip_text = true
	b.custom_minimum_size = Vector2(0, 46)
	b.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	b.pressed.connect(cb)
	return b


func _action_button(icon_kind: String, text: String, cb: Callable) -> Button:
	var b := Button.new()
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


func _section(text: String) -> Label:
	var l := Label.new()
	l.text = text.to_upper()
	l.add_theme_font_size_override("font_size", 13)
	l.add_theme_color_override("font_color", UiTheme.ACCENT)
	return l


func _add(piece: Dictionary) -> void:
	if ops.size() >= CustomTracks.MAX_PIECES:
		return
	_push_undo()
	ops.append(piece)
	selected = ops.size() - 1
	_commit()


func _add_reattach() -> void:
	if ops.size() >= CustomTracks.MAX_PIECES:
		return
	_push_undo()
	var c := CustomTracks.next_corner(ops, 90)
	c["reattach"] = true
	ops.append(c)
	selected = ops.size() - 1
	_commit()


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
	_push_undo()
	ops[i]["r"] = clampf(value, CustomTracks.MIN_RADIUS, CustomTracks.MAX_RADIUS)
	_commit()


func _set_len(i: int, value: float) -> void:
	if i < 0 or i >= ops.size():
		return
	_push_undo()
	ops[i]["len"] = clampf(value, CustomTracks.MIN_LEN, CustomTracks.MAX_LEN)
	_commit()


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

func _commit() -> void:
	CustomTracks.update(id, ops)
	changed.emit()
	_rebuild()


func _rebuild() -> void:
	if name_label == null:
		return
	name_label.text = track_name
	preview.rebuild(ops)

	var v := CustomTracks.validate(ops)
	var ok := bool(v["ok"])
	play_button.disabled = not ok
	if ok:
		status_label.text = "%d corners \u00b7 %d pieces \u00b7 %.0f px" % [int(v["corners"]), ops.size(), float(v["length"])]
		status_label.add_theme_color_override("font_color", UiTheme.INK_DIM)
	else:
		status_label.text = str(v["error"])
		status_label.add_theme_color_override("font_color", UiTheme.DANGER)

	empty_label.visible = ops.size() == 0
	for c in piece_list.get_children():
		c.queue_free()
	for i in range(ops.size()):
		piece_list.add_child(_piece_row(i))

	for c in inspect_box.get_children():
		c.queue_free()
	if selected >= 0 and selected < ops.size():
		inspect_box.add_child(_inspect(selected))


func _piece_row(i: int) -> Control:
	var p: Dictionary = ops[i]
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
	pick.custom_minimum_size = Vector2(0, 40)
	pick.text = "%d. %s" % [i + 1, CustomTracks.describe(p)]
	pick.pressed.connect(func():
		selected = i
		_rebuild())
	row.add_child(pick)

	var up := _mini_button("up", func(): _move(i, -1))
	var down := _mini_button("down", func(): _move(i, 1))
	var del := _mini_button("trash", func(): _remove_at(i))
	row.add_child(up)
	row.add_child(down)
	row.add_child(del)
	return card


func _mini_button(icon_kind: String, cb: Callable) -> Button:
	var b := Button.new()
	b.theme_type_variation = "IconButton"
	b.focus_mode = Control.FOCUS_NONE
	b.custom_minimum_size = Vector2(36, 40)
	b.pressed.connect(cb)
	var ic := UiIcon.new()
	ic.kind = icon_kind
	ic.color = UiTheme.INK_DIM
	ic.thickness = 2.0
	ic.set_anchors_preset(Control.PRESET_FULL_RECT)
	ic.offset_left = 8
	ic.offset_right = -8
	ic.offset_top = 8
	ic.offset_bottom = -8
	ic.mouse_filter = Control.MOUSE_FILTER_IGNORE
	b.add_child(ic)
	return b


func _inspect(i: int) -> Control:
	var p: Dictionary = ops[i]
	var card := PanelContainer.new()
	card.theme_type_variation = "SubCard"
	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 8)
	card.add_child(box)

	box.add_child(_section("Edit piece %d" % (i + 1)))

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

		box.add_child(_slider_row("Radius", float(p["r"]), CustomTracks.MIN_RADIUS, CustomTracks.MAX_RADIUS, CustomTracks.RADIUS_STEP, func(v): _set_radius(i, v)))

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
		var note := Label.new()
		note.text = "Bail out early and you can catch this pole again for a slingshot."
		note.add_theme_font_size_override("font_size", 12)
		note.add_theme_color_override("font_color", UiTheme.INK_MUTE)
		note.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		box.add_child(note)
	else:
		box.add_child(_slider_row("Length", float(p["len"]), CustomTracks.MIN_LEN, CustomTracks.MAX_LEN, CustomTracks.LEN_STEP, func(v): _set_len(i, v)))

	var del := Button.new()
	del.text = "Delete this piece"
	del.custom_minimum_size = Vector2(0, 44)
	del.pressed.connect(func(): _remove_at(i))
	box.add_child(del)
	return card


func _slider_row(label: String, value: float, lo: float, hi: float, step: float, cb: Callable) -> Control:
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
	var slider := HSlider.new()
	slider.min_value = lo
	slider.max_value = hi
	slider.step = step
	slider.value = value
	slider.custom_minimum_size = Vector2(0, 30)
	slider.value_changed.connect(func(v):
		val.text = "%d" % roundi(v)
		cb.call(v))
	box.add_child(slider)
	return box


func _on_close() -> void:
	CustomTracks.update(id, ops)
	closed.emit()
