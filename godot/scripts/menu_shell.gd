extends Control
class_name MenuShell

# The full-screen app shell behind the menu.
#
# The old menu was one card floating over the road: everything the game could do
# was stacked in a single scroll, so it read as a settings dialog rather than an
# app, and on a phone the card was taller than the screen. This replaces it with
# the shape a phone app actually has - a top bar, a content area, and a bottom tab
# bar - and fills the whole window on every screen size.
#
# It owns no game state. It builds the frame and the tab buttons, and calls back
# into App to populate each tab, so the layout and the logic stay apart.

signal tab_changed(name: String)
signal settings_pressed()

const TAB_BAR_H := 62.0
const TOP_BAR_H := 56.0

var top_bar: PanelContainer
var content: Control          # the sheet the active tab draws into
var tab_bar: PanelContainer
var tabs := {}                # name -> Button
var tab_icons := {}           # name -> UiIcon
var _title: Label
var _subtitle: Label
var _top_left: HBoxContainer
var _top_right: HBoxContainer
var _active := ""
var _max_content_w := 560.0

# Wide windows get a centred column rather than controls stretched edge to edge -
# the same rule the old cards used, now applied to the whole sheet.
var _center: CenterContainer


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_build_bg()
	_build_top()
	_build_content()
	_build_tab_bar()
	get_viewport().size_changed.connect(_on_resize)
	# The parent may not be laid out yet on the frame this is added (App builds the
	# whole UI in one _ready), so size to the viewport directly and again once the
	# first layout pass has run.
	_on_resize()


func _build_bg() -> void:
	var bg := Panel.new()
	bg.theme_type_variation = "ShellBg"
	bg.set_anchors_preset(Control.PRESET_FULL_RECT)
	# STOP, not IGNORE: the shell is opaque, so it must also absorb input. An
	# IGNORE background would let a click in an empty spot fall through to the
	# HUD controls underneath (the pause button) while the menu is up.
	bg.mouse_filter = Control.MOUSE_FILTER_STOP
	add_child(bg)


func _build_top() -> void:
	top_bar = PanelContainer.new()
	top_bar.theme_type_variation = "TopBar"
	top_bar.mouse_filter = Control.MOUSE_FILTER_PASS
	top_bar.anchor_left = 0.0
	top_bar.anchor_right = 1.0
	top_bar.offset_bottom = TOP_BAR_H
	add_child(top_bar)

	var margin := MarginContainer.new()
	for side in ["left", "right"]:
		margin.add_theme_constant_override("margin_" + side, 14)
	top_bar.add_child(margin)

	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 10)
	margin.add_child(row)

	_top_left = HBoxContainer.new()
	_top_left.add_theme_constant_override("separation", 10)
	row.add_child(_top_left)

	var titles := VBoxContainer.new()
	titles.add_theme_constant_override("separation", 0)
	titles.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	titles.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	row.add_child(titles)
	_title = Label.new()
	_title.add_theme_font_size_override("font_size", 19)
	_title.add_theme_color_override("font_color", UiTheme.INK)
	titles.add_child(_title)
	_subtitle = Label.new()
	_subtitle.add_theme_font_size_override("font_size", 12)
	_subtitle.add_theme_color_override("font_color", UiTheme.INK_MUTE)
	titles.add_child(_subtitle)

	_top_right = HBoxContainer.new()
	_top_right.add_theme_constant_override("separation", 6)
	row.add_child(_top_right)

	var gear := icon_button("settings", func(): settings_pressed.emit())
	_top_right.add_child(gear)


# The content area: everything between the rails, filled by the active tab.
func _build_content() -> void:
	content = Control.new()
	content.name = "Content"
	content.set_anchors_preset(Control.PRESET_FULL_RECT)
	content.offset_top = TOP_BAR_H
	content.offset_bottom = -TAB_BAR_H
	content.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(content)


func _build_tab_bar() -> void:
	tab_bar = PanelContainer.new()
	tab_bar.theme_type_variation = "BottomBar"
	tab_bar.mouse_filter = Control.MOUSE_FILTER_PASS
	tab_bar.anchor_top = 1.0
	tab_bar.anchor_bottom = 1.0
	tab_bar.anchor_left = 0.0
	tab_bar.anchor_right = 1.0
	tab_bar.offset_top = -TAB_BAR_H
	tab_bar.offset_bottom = 0.0
	add_child(tab_bar)

	var margin := MarginContainer.new()
	margin.add_theme_constant_override("margin_left", 8)
	margin.add_theme_constant_override("margin_right", 8)
	margin.add_theme_constant_override("margin_top", 6)
	margin.add_theme_constant_override("margin_bottom", 6)
	tab_bar.add_child(margin)

	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 4)
	margin.add_child(row)

	# Garage on the left, Play in the middle, Account on the right - the order a
	# player expects, with the primary tab where the thumb rests. The Editor sits
	# between Garage and Play: it is a making-things tab, next to the car picker.
	for spec in [["garage", "garage", "Garage"], ["editor", "editor", "Editor"], ["play", "play", "Play"], ["account", "account", "Account"]]:
		var name: String = spec[0]
		var b := _tab_button(spec[1], spec[2], func(): select(name))
		row.add_child(b)
		tabs[name] = b


func _tab_button(icon_kind: String, label: String, cb: Callable) -> Button:
	var b := Button.new()
	b.theme_type_variation = "TabButton"
	b.toggle_mode = true
	b.focus_mode = Control.FOCUS_NONE
	b.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	b.custom_minimum_size = Vector2(0, TAB_BAR_H - 12)
	b.pressed.connect(cb)
	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 2)
	box.alignment = BoxContainer.ALIGNMENT_CENTER
	box.set_anchors_preset(Control.PRESET_FULL_RECT)
	box.mouse_filter = Control.MOUSE_FILTER_IGNORE
	b.add_child(box)
	var ic := UiIcon.new()
	ic.kind = icon_kind
	ic.color = UiTheme.TAB_IDLE
	ic.thickness = 2.0
	ic.custom_minimum_size = Vector2(24, 24)
	ic.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	ic.mouse_filter = Control.MOUSE_FILTER_IGNORE
	box.add_child(ic)
	var l := Label.new()
	l.text = label
	l.add_theme_font_size_override("font_size", 12)
	l.add_theme_color_override("font_color", UiTheme.TAB_IDLE)
	l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	l.mouse_filter = Control.MOUSE_FILTER_IGNORE
	box.add_child(l)
	tab_icons[_icon_key(label)] = ic
	return b


func _icon_key(label: String) -> String:
	return label.to_lower()


func icon_button(icon_kind: String, cb: Callable) -> Button:
	var b := Button.new()
	b.theme_type_variation = "IconButton"
	b.focus_mode = Control.FOCUS_NONE
	b.custom_minimum_size = Vector2(40, 40)
	b.pressed.connect(cb)
	var ic := UiIcon.new()
	ic.kind = icon_kind
	ic.color = UiTheme.INK_DIM
	ic.thickness = 2.0
	ic.set_anchors_preset(Control.PRESET_FULL_RECT)
	ic.offset_left = 9
	ic.offset_right = -9
	ic.offset_top = 9
	ic.offset_bottom = -9
	ic.mouse_filter = Control.MOUSE_FILTER_IGNORE
	b.add_child(ic)
	return b


func select(name: String) -> void:
	if not tabs.has(name):
		return
	_active = name
	for key in tabs:
		var on: bool = key == name
		tabs[key].button_pressed = on
		var ic: UiIcon = tab_icons[key]
		ic.color = UiTheme.ACCENT if on else UiTheme.TAB_IDLE
		var l: Label = tabs[key].get_child(0).get_child(1)
		l.add_theme_color_override("font_color", UiTheme.ACCENT if on else UiTheme.TAB_IDLE)
	tab_changed.emit(name)


func active() -> String:
	return _active


func set_title(text: String, sub: String = "") -> void:
	_title.text = text
	_subtitle.text = sub
	_subtitle.visible = sub != ""


# A place for the active tab to put a back button or an action in the top-left.
func top_left() -> HBoxContainer:
	return _top_left


func top_right() -> HBoxContainer:
	return _top_right


func clear_top_left() -> void:
	for c in _top_left.get_children():
		c.queue_free()


func _on_resize() -> void:
	_max_content_w = clampf(get_viewport_rect().size.x - 24.0, 320.0, 720.0)
