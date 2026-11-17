extends Node2D
class_name Renderer2D

# Port of the old js/render.js (removed with the JS client): top-down orthographic view, no horizon. The camera
# heading points up the screen, the road is a band either side of the centreline,
# and the car is drawn rotated by its heading relative to the camera.

const ROAD_W_FRAC := 0.358
# On a phone-portrait window the road fills ROAD_W_FRAC of the width. On a wider
# or shorter window that same formula would zoom the road up until you can only
# see a few car lengths ahead, so the zoom is also capped so the screen always
# shows at least MIN_WORLD_H of the world vertically. The two agree at the phone
# size, which is why the phone look is unchanged; on a desktop window the road
# stays a sane size instead of filling a 1280px-wide screen with tarmac.
const MIN_WORLD_H := 460.0
const CAR_ANCHOR := 0.55

# One theme per road. Road is always darker than the ground, or the ribbon
# vanishes into the background.
const THEMES := [
	{"ground": Color8(72, 211, 80), "road": Color8(73, 73, 73), "stripe": Color8(84, 84, 84), "pole": Color8(40, 44, 40)},
	{"ground": Color8(17, 58, 86), "road": Color8(200, 200, 200), "stripe": Color8(222, 222, 222), "pole": Color8(10, 34, 52)},
	{"ground": Color8(254, 169, 46), "road": Color8(75, 75, 75), "stripe": Color8(92, 92, 92), "pole": Color8(150, 96, 20)},
	{"ground": Color8(220, 32, 81), "road": Color8(74, 74, 74), "stripe": Color8(90, 90, 90), "pole": Color8(130, 16, 46)},
	{"ground": Color8(89, 196, 255), "road": Color8(74, 74, 74), "stripe": Color8(90, 90, 90), "pole": Color8(30, 96, 140)},
	{"ground": Color8(77, 16, 35), "road": Color8(203, 203, 203), "stripe": Color8(222, 222, 222), "pole": Color8(40, 8, 18)},
]

# The selectable cars. Every one is a real top-down sprite from `assets/cars/`
# (free CC0 art; see `assets/cars/CREDITS.md`), stored nose-up so it shares the
# car's -Y nose frame. The flat vector bodies the port shipped with were drawn in
# code and read as placeholders, so they are gone; `body` is kept per model only
# so the menu swatch and the ghost tint have a colour to work from.
const CAR_MODELS := [
	{"name": "Roadster", "body": Color8(92, 156, 255), "dark": Color8(46, 96, 186), "glass": Color8(16, 28, 54), "tex": "res://assets/cars/topdown_car.png"},
	{"name": "Redline", "body": Color8(214, 60, 40), "dark": Color8(120, 28, 20), "glass": Color8(28, 32, 40), "tex": "res://assets/cars/topdown_car_red.png"},
	{"name": "Viper", "body": Color8(34, 38, 48), "dark": Color8(14, 16, 22), "glass": Color8(120, 190, 255), "tex": "res://assets/cars/topdown_car_viper.png"},
	{"name": "Cab", "body": Color8(224, 192, 64), "dark": Color8(150, 120, 20), "glass": Color8(30, 34, 44), "tex": "res://assets/cars/topdown_car_taxi.png"},
	{"name": "Hauler", "body": Color8(140, 150, 170), "dark": Color8(80, 88, 104), "glass": Color8(40, 48, 62), "tex": "res://assets/cars/topdown_car_truck.png"},
]

# Reattach pillars read differently from ordinary ones: live (you may still catch
# it) versus spent (this arc is done). Live is a warm amber, spent a dull bronze.
const REATTACH_FILL := Color8(255, 196, 0)
const REATTACH_SPENT_FILL := Color8(150, 112, 0)

var track: Track
var car_ref: Car
var ghost_car: Car = null
var ghost_visible := false
var cam_x := 0.0
var cam_y := 0.0
var cam_angle := 0.0
var shake := 0.0
var car_index := 0
var seed_num := 1

var _w := 420.0
var _h := 820.0
var _anchor_y := 451.0
var _scale := 1.6

var _sprites := {}


func _sprite(path: String) -> Texture2D:
	if not _sprites.has(path):
		_sprites[path] = load(path)
	return _sprites[path]


func theme() -> Dictionary:
	return THEMES[((seed_num - 1) % THEMES.size() + THEMES.size()) % THEMES.size()]


func _to_screen(wx: float, wy: float) -> Vector2:
	var th := -PI / 2.0 - cam_angle
	var c := cos(th)
	var s := sin(th)
	var dx := wx - cam_x
	var dy := wy - cam_y
	return Vector2(_w / 2.0 + (dx * c - dy * s) * _scale, _anchor_y + (dx * s + dy * c) * _scale)


func _ready() -> void:
	# Re-draw every frame; the scene is cheap and always moving.
	set_process(true)


func _process(_delta: float) -> void:
	queue_redraw()


func _draw() -> void:
	if track == null or car_ref == null:
		return
	var vp := get_viewport_rect().size
	_w = vp.x
	_h = vp.y
	_anchor_y = _h * CAR_ANCHOR
	# Zoom the road to ROAD_W_FRAC of the width, but never so far that the visible
	# world is shorter than MIN_WORLD_H - on a wide or short window that cap is what
	# keeps enough road ahead of the car to play, instead of a screen full of tarmac.
	_scale = minf((_w * ROAD_W_FRAC) / (2.0 * Cfg.ROAD_HALF_WIDTH), _h / MIN_WORLD_H)

	var t := theme()
	draw_rect(Rect2(Vector2(-40, -40), Vector2(_w + 80, _h + 80)), t["ground"])
	_draw_road(t)
	_draw_finish()
	_draw_poles(t)
	_draw_ghost()
	_draw_rope()
	_draw_car()


func _samples() -> Array:
	var road: Array = track.road
	var out := []
	var lo: int = maxi(0, car_ref.hint - 120)
	var hi: int = mini(road.size() - 1, car_ref.hint + 220)
	var th := -PI / 2.0 - cam_angle
	var c := cos(th)
	var s := sin(th)
	for i in range(lo, hi + 1):
		var a: Vector2 = road[i]
		var b: Vector2 = road[mini(road.size() - 1, i + 1)]
		var d: Vector2 = road[maxi(0, i - 1)]
		var dx := b.x - d.x
		var dy := b.y - d.y
		var l := sqrt(dx * dx + dy * dy)
		if l == 0.0:
			l = 1.0
		var nx := -dy / l
		var ny := dx / l
		out.append({
			"p": _to_screen(a.x, a.y),
			"snx": nx * c - ny * s,
			"sny": nx * s + ny * c,
		})
	return out


# Fill a band of half-width `hw` either side of the centreline.
#
# Emitted as an explicit triangle list rather than one filled polygon. A road that
# crosses itself (the hairpin/loop tracks 21-25) makes the single-outline band
# self-intersecting, and Godot's ear-clip triangulation rejects that outright
# ("Invalid polygon data, triangulation failed"), dropping the whole band for that
# frame - the road visibly flashes as the car crosses its own path. Canvas fill()
# in the JS build uses nonzero winding and never had the problem. Building the
# quads ourselves skips triangulation entirely, so the overlap just overdraws.
func _band(s: Array, hw: float, fill: Color) -> void:
	if s.size() < 2:
		return
	var pts := PackedVector2Array()
	for i in range(s.size() - 1):
		var q0: Dictionary = s[i]
		var q1: Dictionary = s[i + 1]
		var n0 := Vector2(q0["snx"], q0["sny"]) * hw * _scale
		var n1 := Vector2(q1["snx"], q1["sny"]) * hw * _scale
		var a: Vector2 = q0["p"] + n0
		var b: Vector2 = q1["p"] + n1
		var c: Vector2 = q1["p"] - n1
		var d: Vector2 = q0["p"] - n0
		pts.append(a)
		pts.append(b)
		pts.append(c)
		pts.append(a)
		pts.append(c)
		pts.append(d)
	var cols := PackedColorArray()
	cols.resize(pts.size())
	cols.fill(fill)
	RenderingServer.canvas_item_add_triangle_array(get_canvas_item(), PackedInt32Array(), pts, cols)


func _draw_road(t: Dictionary) -> void:
	var s := _samples()
	if s.size() < 2:
		return
	# One dark slab with a faint lighter centre and a barely-there edge.
	_band(s, Cfg.ROAD_HALF_WIDTH + 4.0, t["road"].darkened(0.14))
	_band(s, Cfg.ROAD_HALF_WIDTH, t["road"])
	_band(s, Cfg.ROAD_HALF_WIDTH * 0.42, t["stripe"])


func _draw_finish() -> void:
	if track.finish == null:
		return
	var s: float = track.finish_s
	if s - car_ref.s > 900.0 or car_ref.s - s > 400.0:
		return
	var p := track.point_at(s)
	var nx := -sin(float(p["heading"]))
	var ny := cos(float(p["heading"]))
	var hw := Cfg.ROAD_HALF_WIDTH
	var a := _to_screen(float(p["x"]) + nx * hw, float(p["y"]) + ny * hw)
	var b := _to_screen(float(p["x"]) - nx * hw, float(p["y"]) - ny * hw)
	draw_line(a, b, Color8(244, 244, 244), 12.0 * _scale, true)
	var cells := 8
	for i in range(0, cells, 2):
		var t0 := float(i) / float(cells)
		var t1 := float(i + 1) / float(cells)
		draw_line(a.lerp(b, t0), a.lerp(b, t1), Color8(20, 20, 20), 12.0 * _scale, true)


func _draw_poles(t: Dictionary) -> void:
	var lo: int = maxi(0, car_ref.corner - 1)
	var hi: int = mini(track.fillets.size() - 1, car_ref.corner + 16)
	var items := []
	for k in range(lo, hi + 1):
		var f: Dictionary = track.fillets[k]
		var c: Vector2 = f["c"]
		var p := _to_screen(c.x, c.y)
		if p.x < -80.0 or p.x > _w + 80.0 or p.y < -80.0 or p.y > _h + 80.0:
			continue
		items.append({"k": k, "p": p})
	items.sort_custom(func(a, b): return a["p"].y < b["p"].y)
	var r := 13.0 * _scale
	for it in items:
		var f: Dictionary = track.fillets[it["k"]]
		var is_next: bool = it["k"] == car_ref.corner and not car_ref.attached
		if f.get("reattach", false):
			# A reattach pillar keeps its own colour until it is spent, so the
			# player can see at a glance that it is still catchable.
			var spent: bool = it["k"] == car_ref.spent
			draw_circle(it["p"], r, REATTACH_SPENT_FILL if spent else REATTACH_FILL)
			if is_next and not spent:
				draw_arc(it["p"], r * 1.35, 0.0, TAU, 48, Color8(255, 255, 255), 2.0, true)
			continue
		draw_circle(it["p"], r, Color8(255, 255, 255) if is_next else t["pole"])


func _draw_rope() -> void:
	if not car_ref.attached:
		return
	var f: Dictionary = track.fillets[car_ref.corner]
	var c: Vector2 = f["c"]
	var a := _to_screen(car_ref.x, car_ref.y)
	var b := _to_screen(c.x, c.y)
	draw_line(a, b, Color8(255, 255, 255), 2.5, true)


func _draw_car() -> void:
	_draw_car_body(car_ref.x, car_ref.y, car_ref.angle, 1.0)


func _draw_ghost() -> void:
	if ghost_car == null or not ghost_visible:
		return
	_draw_car_body(ghost_car.x, ghost_car.y, ghost_car.angle, 0.42)


func _skin() -> Dictionary:
	return CAR_MODELS[((car_index % CAR_MODELS.size()) + CAR_MODELS.size()) % CAR_MODELS.size()]


func _draw_car_body(cx: float, cy: float, cang: float, alpha: float) -> void:
	_draw_car_sprite(cx, cy, cang, alpha, _skin())


# Draw a sprite car. The art is stored nose-up, which is the car's own frame (the
# body points along -Y and is rotated by its heading), so the sprite takes exactly
# the same `cang - cam_angle` rotation the road band does. A ghost is drawn
# translucent and washed toward its body colour so it reads as an echo.
func _draw_car_sprite(cx: float, cy: float, cang: float, alpha: float, skin: Dictionary) -> void:
	var tex: Texture2D = _sprite(str(skin["tex"]))
	if tex == null:
		return
	var target_len := 34.0 * _scale
	var aspect := float(tex.get_height()) / float(tex.get_width())
	var size := Vector2(target_len / aspect, target_len)
	var p := _to_screen(cx, cy)
	# Adding a quarter turn here (as an earlier version did) left every sprite car
	# broadside to its direction of travel; the art is already nose-up.
	var rot := cang - cam_angle
	var tint := Color(1, 1, 1, alpha)
	if alpha < 1.0:
		tint = Color(skin["body"].r, skin["body"].g, skin["body"].b, alpha)
	# Transform is in screen space, so the offset is the car's screen position.
	draw_set_transform(p, rot, Vector2.ONE)
	draw_texture_rect(tex, Rect2(-size / 2.0, size), false, tint)
	draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)
