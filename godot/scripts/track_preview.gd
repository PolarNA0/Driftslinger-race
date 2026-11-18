extends Control
class_name TrackPreview

# A top-down map of a whole road, fitted to this control's rect. The track editor
# draws into one of these so the shape is visible while it is being built, without
# the chase camera - the editor cares about the plan, not the drive.
#
# It builds a real `Track` from the ops, so what is previewed is exactly the road
# the game will drive, including the lead-in and the closing straight.

var ops: Array = []
var ok := false
var error := ""

var _track: Track = null
var _road: Array = []
var _finish_s := 0.0


func rebuild(p_ops: Array) -> void:
	ops = p_ops.duplicate(true)
	var v := CustomTracks.validate(ops)
	ok = bool(v["ok"])
	error = str(v["error"])
	_track = null
	_road = []
	_finish_s = 0.0
	if ok:
		_track = Track.new(0, CustomTracks.opts(ops))
		_road = _track.road
		_finish_s = _track.finish_s
	queue_redraw()


func _draw() -> void:
	var w := size.x
	var h := size.y
	draw_rect(Rect2(Vector2.ZERO, size), Color(0.05, 0.07, 0.12, 1.0))
	if not ok or _road.size() < 2:
		var f := ThemeDB.fallback_font
		var msg := error if error != "" else "Nothing to preview yet."
		draw_string(f, Vector2(12, h * 0.5), msg, HORIZONTAL_ALIGNMENT_CENTER, w - 24, 13, UiTheme.INK_MUTE)
		return

	var minx := INF
	var miny := INF
	var maxx := -INF
	var maxy := -INF
	for p in _road:
		minx = minf(minx, p.x)
		miny = minf(miny, p.y)
		maxx = maxf(maxx, p.x)
		maxy = maxf(maxy, p.y)
	var pad := 18.0
	var spanx := maxf(1.0, maxx - minx)
	var spany := maxf(1.0, maxy - miny)
	var fit := minf((w - pad * 2.0) / spanx, (h - pad * 2.0) / spany)
	var ox := (w - spanx * fit) * 0.5 - minx * fit
	var oy := (h - spany * fit) * 0.5 - miny * fit
	var hw := maxf(2.0, Cfg.ROAD_HALF_WIDTH * fit)

	var pts := PackedVector2Array()
	for i in range(_road.size() - 1):
		var a: Vector2 = _road[i]
		var b: Vector2 = _road[i + 1]
		var dx := b.x - a.x
		var dy := b.y - a.y
		var l := sqrt(dx * dx + dy * dy)
		if l == 0.0:
			l = 1.0
		var nx := -dy / l * hw
		var ny := dx / l * hw
		var pa := Vector2(a.x * fit + ox, a.y * fit + oy)
		var pb := Vector2(b.x * fit + ox, b.y * fit + oy)
		pts.append(pa + Vector2(nx, ny))
		pts.append(pb + Vector2(nx, ny))
		pts.append(pb - Vector2(nx, ny))
		pts.append(pa + Vector2(nx, ny))
		pts.append(pb - Vector2(nx, ny))
		pts.append(pa - Vector2(nx, ny))
	var cols := PackedColorArray()
	cols.resize(pts.size())
	cols.fill(Color8(150, 150, 158))
	RenderingServer.canvas_item_add_triangle_array(get_canvas_item(), PackedInt32Array(), pts, cols)

	_mark(0.0, fit, ox, oy, Color8(90, 226, 120))
	_mark(_finish_s, fit, ox, oy, Color8(244, 244, 244))


func _mark(s: float, fit: float, ox: float, oy: float, c: Color) -> void:
	if _track == null:
		return
	var p := _track.point_at(s)
	draw_circle(Vector2(float(p["x"]) * fit + ox, float(p["y"]) * fit + oy), 5.0, c)
