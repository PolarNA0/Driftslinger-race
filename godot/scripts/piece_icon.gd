extends Control
class_name PieceIcon

# A picture of a piece, for the editor's palette.
#
# The palette used to be a row of text buttons ("Straight", "Hairpin 180" ...),
# which told you the name of a piece but not its shape - so placing a track meant
# reading labels and guessing. This draws the actual road: the band, its edges, the
# pillar at the pivot of a corner, and the finish line for the finish piece. Tap it
# to select that piece, then tap the grid to place it.
#
# Every shape is drawn from the same geometry `Track` builds: a straight is a band,
# a corner is a band turning about a pivot one radius to the side, which is why the
# pictures agree with the road the piece produces.

@export var kind := "straight":
	set(v):
		kind = v
		queue_redraw()

# The track's own colours, so a palette tile matches the road it will add.
@export var road_color := Color(0.29, 0.29, 0.29):
	set(v):
		road_color = v
		queue_redraw()

@export var ground_color := Color(0.28, 0.83, 0.31):
	set(v):
		ground_color = v
		queue_redraw()

@export var selected := false:
	set(v):
		selected = v
		queue_redraw()


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE


func _draw() -> void:
	var w := size.x
	var h := size.y
	if w <= 2.0 or h <= 2.0:
		return
	draw_rect(Rect2(Vector2.ZERO, size), ground_color)
	if selected:
		draw_rect(Rect2(Vector2.ZERO, size), Color(UiTheme.ACCENT, 0.22))

	var band := maxf(4.0, minf(w, h) * 0.20)
	var m := minf(w, h) * 0.18
	var pole := ground_color.darkened(0.45)
	var line := road_color.lightened(0.55)

	match kind:
		"straight", "finish":
			var a := Vector2(m, h * 0.5)
			var b := Vector2(w - m, h * 0.5)
			_bar(a, b, band)
			if kind == "finish":
				# The chequered line across the far end: two rows of alternating squares.
				var n := 4
				var sq := band / float(n)
				for r in range(2):
					for c in range(n):
						if (r + c) % 2 == 0:
							var p := b + Vector2(-sq * 0.9, -band * 0.5 + float(r) * sq)
							draw_rect(Rect2(p, Vector2(sq, sq)), line)
		"90":
			_turn(w, h, band, m, pole, deg_to_rad(90.0), 1.0, line)
		"180":
			_turn(w, h, band, m, pole, deg_to_rad(180.0), 1.0, line)
		"270":
			_turn(w, h, band, m, pole, deg_to_rad(270.0), 1.0, line)
		"pillar", "reattach":
			_turn(w, h, band, m, pole, deg_to_rad(90.0), 1.0, line)
			if kind == "reattach":
				# An amber ring round the pole: this one reopens if you let go early.
				draw_arc(_pivot(w, h, m), band * 1.15, 0.0, TAU, 24, UiTheme.ACCENT, 2.0, true)


# A corner: a quarter/half/three-quarter arc about a pivot one radius to the side,
# exactly as `Track.build_ops` places it, with the pole drawn at the pivot.
func _turn(w: float, h: float, band: float, m: float, pole: Color, phi: float, sign: float, line: Color) -> void:
	var r := minf(w, h) * 0.5 - m - band * 0.5
	var c := _pivot(w, h, m)
	# The arc starts on the left of the pivot and sweeps by `phi`. Drawing it as a
	# polyline keeps a 270 readable at 56px, where a 1px arc stroke would not be.
	var steps := 40
	var pts := PackedVector2Array()
	for i in range(steps + 1):
		var t := phi * float(i) / float(steps)
		pts.append(c + Vector2(-cos(t), sin(t)) * sign * r)
	for i in range(pts.size() - 1):
		_bar(pts[i], pts[i + 1], band)
	draw_circle(c, band * 0.62, pole)


func _pivot(w: float, h: float, m: float) -> Vector2:
	# A 90 turns up the right of its pivot and a 270 wraps round it, so the pivot
	# sits low-left for both: that is the room the arc needs.
	return Vector2(m + minf(w, h) * 0.30, h - m - minf(w, h) * 0.30)


# A band from a to b, drawn as a quad so the joins between segments overlap cleanly
# (a polyline stroke leaves notches at every bend).
func _bar(a: Vector2, b: Vector2, band: float) -> void:
	var d := b - a
	var l := d.length()
	if l <= 0.001:
		return
	var n := Vector2(-d.y / l, d.x / l) * band * 0.5
	draw_colored_polygon(PackedVector2Array([a + n, b + n, b - n, a - n]), road_color)
