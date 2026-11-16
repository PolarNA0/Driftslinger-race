extends Node2D
class_name Renderer2D

# Port of js/render.js: top-down orthographic view, no horizon. The camera
# heading points up the screen, the road is a band either side of the centreline,
# and the car is drawn rotated by its heading relative to the camera.

const ROAD_W_FRAC := 0.358
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

# The selectable cars. A model is either a flat vector body (drawn from the
# outline below) or a sprite drawn from `assets/cars/`. Sprite art is stored
# nose-up, so it lines up with the vector cars, which are drawn nose-first along
# -Y. The sprite is a CC0 top-down car; see `assets/cars/CREDITS.md`.
const CAR_MODELS := [
	{"kind": "vector", "name": "Sunbeam", "body": Color8(255, 209, 102), "dark": Color8(196, 150, 54), "glass": Color8(30, 38, 56)},
	{"kind": "vector", "name": "Ember", "body": Color8(238, 92, 66), "dark": Color8(170, 52, 36), "glass": Color8(40, 20, 18)},
	{"kind": "vector", "name": "Mint", "body": Color8(104, 219, 168), "dark": Color8(50, 158, 116), "glass": Color8(16, 46, 40)},
	{"kind": "vector", "name": "Cobalt", "body": Color8(92, 156, 255), "dark": Color8(46, 96, 186), "glass": Color8(16, 28, 54)},
	{"kind": "vector", "name": "Orchid", "body": Color8(206, 130, 255), "dark": Color8(140, 76, 186), "glass": Color8(34, 20, 50)},
	{"kind": "vector", "name": "Frost", "body": Color8(238, 242, 250), "dark": Color8(150, 160, 178), "glass": Color8(28, 34, 46)},
	{"kind": "vector", "name": "Graphite", "body": Color8(70, 74, 88), "dark": Color8(30, 32, 40), "glass": Color8(120, 190, 255)},
	{"kind": "vector", "name": "Coral", "body": Color8(255, 138, 92), "dark": Color8(188, 84, 48), "glass": Color8(46, 24, 20)},
	{"kind": "sprite", "name": "Roadster", "body": Color8(92, 156, 255), "dark": Color8(46, 96, 186), "glass": Color8(16, 28, 54), "tex": "res://assets/cars/topdown_car.png"},
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
	_scale = (_w * ROAD_W_FRAC) / (2.0 * Cfg.ROAD_HALF_WIDTH)

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


func _band(s: Array, hw: float, fill: Color) -> void:
	if s.size() < 2:
		return
	var pts := PackedVector2Array()
	for q in s:
		pts.append(q["p"] + Vector2(q["snx"], q["sny"]) * hw * _scale)
	for i in range(s.size() - 1, -1, -1):
		var q: Dictionary = s[i]
		pts.append(q["p"] - Vector2(q["snx"], q["sny"]) * hw * _scale)
	draw_colored_polygon(pts, fill)


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


func _car_body_points(len: float, wid: float) -> PackedVector2Array:
	# The JS car outline is a run of quadratic curves; sampled here so the shape
	# matches without a path API.
	var pts := PackedVector2Array()
	var segs := [
		[Vector2(-wid * 0.5, len * 0.5), Vector2(-wid * 0.62, 0), Vector2(-wid * 0.5, -len * 0.42)],
		[Vector2(-wid * 0.5, -len * 0.42), Vector2(0, -len * 0.62), Vector2(wid * 0.5, -len * 0.42)],
		[Vector2(wid * 0.5, -len * 0.42), Vector2(wid * 0.62, 0), Vector2(wid * 0.5, len * 0.5)],
		[Vector2(wid * 0.5, len * 0.5), Vector2(0, len * 0.66), Vector2(-wid * 0.5, len * 0.5)],
	]
	for seg in segs:
		var p0: Vector2 = seg[0]
		var p1: Vector2 = seg[1]
		var p2: Vector2 = seg[2]
		for i in range(6):
			var t := float(i) / 6.0
			var u := 1.0 - t
			pts.append(u * u * p0 + 2.0 * u * t * p1 + t * t * p2)
	return pts


func _draw_car() -> void:
	_draw_car_body(car_ref.x, car_ref.y, car_ref.angle, 1.0, false)


func _draw_ghost() -> void:
	if ghost_car == null or not ghost_visible:
		return
	_draw_car_body(ghost_car.x, ghost_car.y, ghost_car.angle, 0.42, true)


func _draw_car_body(cx: float, cy: float, cang: float, alpha: float, _is_ghost: bool) -> void:
	var skin: Dictionary = CAR_MODELS[((car_index % CAR_MODELS.size()) + CAR_MODELS.size()) % CAR_MODELS.size()]
	if skin.get("kind", "vector") == "sprite":
		_draw_car_sprite(cx, cy, cang, alpha, skin)
		return
	var len := 30.0 * _scale
	var wid := 16.0 * _scale
	var p := _to_screen(cx, cy)
	var rot := cang - cam_angle
	var local := _car_body_points(len, wid)
	var pts := PackedVector2Array()
	for q in local:
		pts.append(p + q.rotated(rot))
	var body: Color = skin["body"]
	var dark: Color = skin["dark"]
	var glass: Color = skin["glass"]
	if alpha < 1.0:
		body.a = alpha
		dark.a = alpha
		glass.a = alpha
	draw_colored_polygon(pts, body)
	# Outline, then the canopy.
	var outline := pts.duplicate()
	outline.append(pts[0])
	draw_polyline(outline, dark, 2.0, true)
	var glass_pts := PackedVector2Array()
	for i in range(16):
		var a := TAU * float(i) / 16.0
		glass_pts.append(p + Vector2(cos(a) * wid * 0.30, sin(a) * len * 0.17).rotated(rot) + Vector2(0, -len * 0.10).rotated(rot))
	draw_colored_polygon(glass_pts, glass)


# Draw a sprite car. The art is stored nose-up, so it needs one extra quarter
# turn to line up with the vector cars (which are built along -Y and rotated by
# heading). A ghost is drawn translucent and tinted, matching the vector ghost.
func _draw_car_sprite(cx: float, cy: float, cang: float, alpha: float, skin: Dictionary) -> void:
	var tex: Texture2D = _sprite(str(skin["tex"]))
	if tex == null:
		return
	var target_len := 34.0 * _scale
	var aspect := float(tex.get_height()) / float(tex.get_width())
	var size := Vector2(target_len / aspect, target_len)
	var p := _to_screen(cx, cy)
	# +PI/2 turns the nose-up art to match the vector cars' heading frame.
	var rot := cang - cam_angle + PI / 2.0
	# A ghost is washed toward its body colour so it reads as a translucent echo.
	var tint := Color(1, 1, 1, alpha)
	if alpha < 1.0:
		tint = Color(skin["body"].r, skin["body"].g, skin["body"].b, alpha)
	# Transform is in screen space, so the offset is the car's screen position.
	draw_set_transform(p, rot, Vector2.ONE)
	draw_texture_rect(tex, Rect2(-size / 2.0, size), false, tint)
	draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)
