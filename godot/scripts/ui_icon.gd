extends Control
class_name UiIcon

# Icons drawn as geometry, not text.
#
# The UI theme uses the engine's default font (Open Sans SemiBold), which carries
# no icon glyphs - a tab bar full of "⚙" and "▶" would render as a row of empty
# boxes, exactly the bug the restart button hit with U+21BB. Drawing the icons
# keeps them correct on every platform without shipping an icon font.
#
# Each icon is authored on a 24x24 grid and scaled to the control's square. Set
# `kind` before adding to the tree; a change to `kind`/`color` triggers a redraw.

@export var kind := "play":
	set(v):
		kind = v
		queue_redraw()

@export var color := Color.WHITE:
	set(v):
		color = v
		queue_redraw()

@export var thickness := 2.0:
	set(v):
		thickness = v
		queue_redraw()

# An optional second colour, used for the few icons that read better with a
# knocked-out detail (the ghost's eyes, the gear's hub).
@export var accent := Color(0, 0, 0, 0.0):
	set(v):
		accent = v
		queue_redraw()


func _draw() -> void:
	var s := minf(size.x, size.y)
	if s <= 0.0:
		return
	var o := (size - Vector2(s, s)) * 0.5
	var k := s / 24.0
	var w := maxf(1.4, thickness * k)
	var c := color

	match kind:
		"play":
			_tri(o, k, c, [Vector2(8, 5), Vector2(19, 12), Vector2(8, 19)])
		"garage":
			_car(o, k, c, w)
		"account":
			_person(o, k, c, w)
		"settings":
			_gear(o, k, c, w)
		"trophy":
			_trophy(o, k, c, w)
		"ghost":
			_ghost(o, k, c, w)
		"clock":
			_clock(o, k, c, w)
		"back":
			_chevron(o, k, c, w, true)
		"forward":
			_chevron(o, k, c, w, false)
		"close":
			_cross(o, k, c, w)
		"key":
			_key(o, k, c, w)
		"flag":
			_flag(o, k, c, w)
		"infinity":
			_infinity(o, k, c, w)
		"editor":
			_editor(o, k, c, w)
		"plus":
			_plus(o, k, c, w)
		"copy":
			_copy(o, k, c, w)
		"trash":
			_trash(o, k, c, w)
		"pencil":
			_pencil(o, k, c, w)
		"undo":
			_undo(o, k, c, w)
		"flip":
			_flip(o, k, c, w)
		"up":
			_chevron(o, k, c, w, true, true)
		"down":
			_chevron(o, k, c, w, false, true)


func _tri(o: Vector2, k: float, c: Color, pts: Array) -> void:
	var v := PackedVector2Array()
	for p in pts:
		v.append(o + p * k)
	draw_colored_polygon(v, c)


# A side-view car: a low body, a cabin, and two wheels hanging below the sills.
func _car(o: Vector2, k: float, c: Color, w: float) -> void:
	var body := PackedVector2Array([
		o + Vector2(2, 12) * k, o + Vector2(22, 12) * k,
		o + Vector2(22, 15.5) * k, o + Vector2(2, 15.5) * k,
	])
	draw_colored_polygon(body, c)
	var cabin := PackedVector2Array([
		o + Vector2(7, 12) * k, o + Vector2(9, 7) * k,
		o + Vector2(15, 7) * k, o + Vector2(17, 12) * k,
	])
	draw_colored_polygon(cabin, c)
	for cx in [6.5, 17.5]:
		draw_circle(o + Vector2(cx, 16.5) * k, 2.3 * k, c)


# Head plus a shoulder arc - the universal account mark.
func _person(o: Vector2, k: float, c: Color, w: float) -> void:
	draw_circle(o + Vector2(12, 8) * k, 3.8 * k, c)
	draw_arc(o + Vector2(12, 21) * k, 7.0 * k, PI, TAU, 32, c, w * 1.4, true)


# A ring with eight teeth and a hub.
func _gear(o: Vector2, k: float, c: Color, w: float) -> void:
	var centre := o + Vector2(12, 12) * k
	draw_arc(centre, 6.2 * k, 0.0, TAU, 40, c, w, true)
	for i in range(8):
		var a := TAU * float(i) / 8.0
		var d := Vector2(cos(a), sin(a))
		draw_line(centre + d * 6.2 * k, centre + d * 9.2 * k, c, w, true)
	draw_circle(centre, 2.4 * k, c)


# A cup with two handles, a stem and a base.
func _trophy(o: Vector2, k: float, c: Color, w: float) -> void:
	var cup := PackedVector2Array([
		o + Vector2(7, 4) * k, o + Vector2(17, 4) * k,
		o + Vector2(16, 11) * k, o + Vector2(12, 14) * k,
		o + Vector2(8, 11) * k,
	])
	draw_colored_polygon(cup, c)
	draw_arc(o + Vector2(6.5, 7) * k, 2.6 * k, PI * 0.5, PI * 1.5, 20, c, w, true)
	draw_arc(o + Vector2(17.5, 7) * k, 2.6 * k, -PI * 0.5, PI * 0.5, 20, c, w, true)
	draw_line(o + Vector2(12, 14) * k, o + Vector2(12, 18) * k, c, w, true)
	draw_line(o + Vector2(8, 19) * k, o + Vector2(16, 19) * k, c, w * 1.2, true)


# A dome with a wavy hem and two eyes.
func _ghost(o: Vector2, k: float, c: Color, w: float) -> void:
	var centre := o + Vector2(12, 12) * k
	draw_arc(centre, 6.5 * k, PI, TAU, 28, c, w, true)
	var hem := PackedVector2Array()
	var xs := [5.5, 8.0, 10.5, 13.0, 15.5, 18.5]
	var ys := [12.0, 15.5, 12.0, 15.5, 12.0, 15.0]
	for i in range(xs.size()):
		hem.append(o + Vector2(xs[i], ys[i]) * k)
	for i in range(hem.size() - 1):
		draw_line(hem[i], hem[i + 1], c, w, true)
	draw_line(o + Vector2(5.5, 12) * k, o + Vector2(5.5, 15.0) * k, c, w, true)
	draw_line(o + Vector2(18.5, 12) * k, o + Vector2(18.5, 15.0) * k, c, w, true)
	if accent.a > 0.0:
		draw_circle(o + Vector2(9.6, 10) * k, 1.5 * k, accent)
		draw_circle(o + Vector2(14.4, 10) * k, 1.5 * k, accent)


# A clock face with two hands.
func _clock(o: Vector2, k: float, c: Color, w: float) -> void:
	var centre := o + Vector2(12, 12) * k
	draw_arc(centre, 8.0 * k, 0.0, TAU, 40, c, w, true)
	draw_line(centre, centre + Vector2(0, -5.0) * k, c, w, true)
	draw_line(centre, centre + Vector2(4.0, 1.5) * k, c, w, true)


func _chevron(o: Vector2, k: float, c: Color, w: float, left: bool, vertical: bool = false) -> void:
	if vertical:
		var tip_y := 9.5 if left else 14.5
		var far_y := 14.5 if left else 9.5
		draw_line(o + Vector2(5.5, far_y) * k, o + Vector2(12, tip_y) * k, c, w, true)
		draw_line(o + Vector2(12, tip_y) * k, o + Vector2(18.5, far_y) * k, c, w, true)
		return
	var tip_x := 9.5 if left else 14.5
	var far_x := 14.5 if left else 9.5
	draw_line(o + Vector2(far_x, 5.5) * k, o + Vector2(tip_x, 12) * k, c, w, true)
	draw_line(o + Vector2(tip_x, 12) * k, o + Vector2(far_x, 18.5) * k, c, w, true)


func _cross(o: Vector2, k: float, c: Color, w: float) -> void:
	draw_line(o + Vector2(6.5, 6.5) * k, o + Vector2(17.5, 17.5) * k, c, w, true)
	draw_line(o + Vector2(17.5, 6.5) * k, o + Vector2(6.5, 17.5) * k, c, w, true)


# A key cap: a rounded outline with a notch on the underside.
func _key(o: Vector2, k: float, c: Color, w: float) -> void:
	draw_arc(o + Vector2(12, 6.5) * k, 4.0 * k, PI, TAU, 20, c, w, true)
	draw_line(o + Vector2(8, 6.5) * k, o + Vector2(8, 16.0) * k, c, w, true)
	draw_line(o + Vector2(16, 6.5) * k, o + Vector2(16, 16.0) * k, c, w, true)
	draw_line(o + Vector2(8, 16.0) * k, o + Vector2(16, 16.0) * k, c, w, true)
	draw_line(o + Vector2(12, 16.0) * k, o + Vector2(12, 12.5) * k, c, w, true)


func _flag(o: Vector2, k: float, c: Color, w: float) -> void:
	draw_line(o + Vector2(6.5, 4) * k, o + Vector2(6.5, 20) * k, c, w, true)
	_tri(o, k, c, [Vector2(7.5, 4.5), Vector2(18, 8), Vector2(7.5, 11.5)])


# Two lobes read as an endless road.
func _infinity(o: Vector2, k: float, c: Color, w: float) -> void:
	draw_arc(o + Vector2(8, 12) * k, 3.6 * k, 0.0, TAU, 28, c, w, true)
	draw_arc(o + Vector2(16, 12) * k, 3.6 * k, 0.0, TAU, 28, c, w, true)


# A pencil drawing a curve: the editor mark.
func _editor(o: Vector2, k: float, c: Color, w: float) -> void:
	draw_line(o + Vector2(5, 17) * k, o + Vector2(12.5, 9.5) * k, c, w * 1.6, true)
	_tri(o, k, c, [Vector2(11.5, 8.5), Vector2(13.6, 10.6), Vector2(16, 8.2)])
	draw_line(o + Vector2(16.5, 5) * k, o + Vector2(19, 7.5) * k, c, w, true)


func _plus(o: Vector2, k: float, c: Color, w: float) -> void:
	draw_line(o + Vector2(12, 6) * k, o + Vector2(12, 18) * k, c, w, true)
	draw_line(o + Vector2(6, 12) * k, o + Vector2(18, 12) * k, c, w, true)


func _copy(o: Vector2, k: float, c: Color, w: float) -> void:
	draw_rect(Rect2(o + Vector2(8, 5) * k, Vector2(11, 13) * k), c, false, w)
	draw_rect(Rect2(o + Vector2(5, 8) * k, Vector2(11, 13) * k), c, false, w)


func _trash(o: Vector2, k: float, c: Color, w: float) -> void:
	draw_line(o + Vector2(6, 7) * k, o + Vector2(18, 7) * k, c, w, true)
	draw_line(o + Vector2(10, 4.5) * k, o + Vector2(14, 4.5) * k, c, w, true)
	draw_line(o + Vector2(7.5, 7) * k, o + Vector2(8.5, 19) * k, c, w, true)
	draw_line(o + Vector2(16.5, 7) * k, o + Vector2(15.5, 19) * k, c, w, true)
	draw_line(o + Vector2(8.5, 19) * k, o + Vector2(15.5, 19) * k, c, w, true)


func _pencil(o: Vector2, k: float, c: Color, w: float) -> void:
	draw_line(o + Vector2(6, 18) * k, o + Vector2(15, 9) * k, c, w * 1.6, true)
	_tri(o, k, c, [Vector2(14, 8), Vector2(16, 10), Vector2(18, 6)])


func _undo(o: Vector2, k: float, c: Color, w: float) -> void:
	draw_arc(o + Vector2(12, 13) * k, 6.0 * k, PI, TAU * 0.92, 28, c, w, true)
	_tri(o, k, c, [Vector2(4, 12.5), Vector2(9, 10.5), Vector2(9, 15.5)])


func _flip(o: Vector2, k: float, c: Color, w: float) -> void:
	draw_line(o + Vector2(12, 4) * k, o + Vector2(12, 20) * k, c, w, true)
	_tri(o, k, c, [Vector2(10, 8), Vector2(5, 12), Vector2(10, 16)])
	_tri(o, k, c, [Vector2(14, 8), Vector2(19, 12), Vector2(14, 16)])
