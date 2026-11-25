extends Control
class_name PieceIcon

# A picture of a piece, for the editor's palette.
#
# The palette used to be a row of text buttons ("Straight", "Hairpin 180" ...),
# which told you the name of a piece but not its shape - so placing a track meant
# reading labels and guessing. This draws the road the piece produces and nothing
# else: the band, an arrow showing which way the car comes out, and the chequered
# line for the finish piece. No pillar marker - the tile is a picture of the road,
# not a diagram of the mechanic. Tap it to select that piece, then tap the grid.
#
# The art is generated from the same arc `Track.build_ops` lays down, rather than
# from hand-drawn shapes: the pivot is one radius to the side of the entry, the exit
# tangent is the entry rotated by `deg`, and `deg > 0` exits to +X (a right turn on
# screen). Drawing from the geometry is what keeps a 270 from being drawn as a 90,
# and a left turn from being drawn as a right one - the two bugs this tile had.
#
# Every tile is drawn in a fixed frame: the road enters at the middle of the bottom
# edge heading up the tile. A tile then shows its own bend, so a row of them reads
# as a menu of turns rather than a set of unrelated squiggles.

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

# The signed turn a tile places. Positive is a right turn on screen, matching
# `Track.build_ops` (positive `deg` exits to +X).
static func turn_deg(key: String) -> int:
	match key:
		"90", "reattach", "bend":
			return 90
		"-90", "reattach_l", "bend_l":
			return -90
		"180":
			return 180
		"270":
			return 270
		"-270":
			return -270
	return 0


# Is this palette key a turn with no pillar? A bend is drawn differently because it
# behaves differently: there is no pole to sling round, so the car steers through it.
static func is_bend(key: String) -> bool:
	return key == "bend" or key == "bend_l"


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
	var m := minf(w, h) * 0.16
	var line := road_color.lightened(0.55)

	if kind == "straight" or kind == "finish":
		var a := Vector2(w * 0.5, h - m)
		var b := Vector2(w * 0.5, m)
		_bar(a, b, band)
		if kind == "finish":
			_checkers(a, b, band, line)
		_arrow(a, b, band)
		return

	var deg := turn_deg(kind)
	if deg != 0:
		_turn(w, h, band, m, deg)


# The road a corner produces, in the tile's own frame.
#
# `Track.build_ops` puts the pivot one radius to the side of the entry and sweeps
# the entry tangent by `deg`; the exit leaves along that turned tangent. This
# reproduces that in miniature so the picture cannot disagree with the road.
func _turn(w: float, h: float, band: float, m: float, deg: int) -> void:
	var fr := arc_frame(deg, w, h, band, m)
	var pts: PackedVector2Array = fr["pts"]
	for i in range(pts.size() - 1):
		_bar(pts[i], pts[i + 1], band)
	_arrow(pts[pts.size() - 2], pts[pts.size() - 1], band)
	# A corner is a turn you sling round, so its pole is part of the picture. A bend has
	# no pole, and drawing one would promise a grab that is not there. This dot is the
	# only difference the two tiles need: the road shape is honestly the same, and what
	# changes is whether there is something at its centre to catch.
	if not is_bend(kind):
		draw_circle(fr["origin"], maxf(2.0, band * 0.34), road_color.darkened(0.45))


# The centreline in tile space plus the frame it was fitted in, so the pivot can be
# drawn where the arc actually orbits. Split out from `_turn` so the verifier can check
# the shape it draws rather than a copy of the arithmetic: the picture and the check
# have to be the same code.
static func arc_frame(deg: int, w: float, h: float, band: float, m: float) -> Dictionary:
	var th := deg_to_rad(float(deg))
	# The arc in units of its own radius. Which side the pivot sits on is what makes a
	# turn a left or a right: a right turn orbits a pivot to the right of the entry, a
	# left turn one to the left. Getting this from the sign of `deg` is the whole
	# point - a fixed side drew every left turn as a right one. Both cases start with
	# the car heading up the tile, and the sweep follows the sign of the angle, which
	# is what `Track.build_ops` does (a positive corner exits to +X).
	var a0 := PI if th > 0.0 else 0.0
	var steps := 48
	var unit := PackedVector2Array()
	for i in range(steps + 1):
		var a := a0 + th * (float(i) / float(steps))
		unit.append(Vector2(cos(a), sin(a)))
	# Fit the arc's bounding box in the tile. A 90 spans one radius each way, a 180
	# two by one and a 270 two by two, so one radius would push the longer turns off
	# the edge - which drew a 270 as a stubbier bend than a 90.
	var lo := unit[0]
	var hi := unit[0]
	for p in unit:
		lo = Vector2(minf(lo.x, p.x), minf(lo.y, p.y))
		hi = Vector2(maxf(hi.x, p.x), maxf(hi.y, p.y))
	var span := hi - lo
	var room := minf(w, h) - 2.0 * m - band
	var r := room / maxf(0.001, maxf(span.x, span.y))
	var origin := Vector2(w, h) * 0.5 - (lo + hi) * 0.5 * r
	var pts := PackedVector2Array()
	for p in unit:
		pts.append(origin + p * r)
	return {"pts": pts, "origin": origin, "r": r}


# The corner's centreline only. Kept because the verifier reads it directly.
static func arc_points(deg: int, w: float, h: float, band: float, m: float) -> PackedVector2Array:
	return arc_frame(deg, w, h, band, m)["pts"]


# A chevron at the exit, pointing the way the car leaves. Without it a 90 and a
# 270 both just look like "a bend", and the direction of a turn is invisible.
func _arrow(a: Vector2, b: Vector2, band: float) -> void:
	var d := b - a
	if d.length() < 0.01:
		return
	var dir := d.normalized()
	var n := Vector2(-dir.y, dir.x)
	var tip := b - dir * band * 0.15
	var back := tip - dir * band * 1.05
	var wing := band * 0.75
	var col := ground_color.darkened(0.55)
	draw_colored_polygon(PackedVector2Array([
		tip, back + n * wing, back - n * wing]), col)


func _checkers(a: Vector2, b: Vector2, band: float, line: Color) -> void:
	var dir := (b - a).normalized()
	var n := Vector2(-dir.y, dir.x)
	var rows := 2
	var cols := 4
	var sq := band / float(cols)
	var base := b - dir * (sq * 1.2)
	for r in range(rows):
		for c in range(cols):
			if (r + c) % 2 != 0:
				continue
			var o := base + n * (float(c) * sq - band * 0.5) + dir * (float(r) * sq)
			draw_colored_polygon(PackedVector2Array([
				o, o + n * sq, o + n * sq + dir * sq, o + dir * sq]), line)


# A band from a to b, drawn as a quad so the joins between segments overlap cleanly
# (a polyline stroke leaves notches at every bend).
func _bar(a: Vector2, b: Vector2, band: float) -> void:
	var d := b - a
	var l := d.length()
	if l <= 0.001:
		return
	var n := Vector2(-d.y / l, d.x / l) * band * 0.5
	draw_colored_polygon(PackedVector2Array([a + n, b + n, b - n, a - n]), road_color)
