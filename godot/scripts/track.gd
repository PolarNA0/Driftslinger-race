extends RefCounted
class_name Track

# Port of js/track.js. The road is a staircase of straight legs joined by
# quarter-turn arcs of radius `radius`, and the pole you sling around is the
# centre of the arc. A track may instead supply an explicit op list for corners
# that are not quarter turns - hairpins (180) and loops (270). See the JS source
# for the full reasoning.

# `project` tie-break. `PROJECT_BRANCH` is the index gap that means "a different
# branch of the road"; `PROJECT_TIE` is how close in space two branches must be
# to count as crossing.
const PROJECT_BRANCH := 40
const PROJECT_TIE := 0.05

var seed: int
var rng: Callable
var finite: bool
var corner_limit: int
var finish_len: float
var seg_lens: Array
var lead_in: float
var radius: float
var target_time: float
var seg_index: int = 0
var ops: Variant = null

var finish_s: float = INF
var finish: Variant = null

var v: Array = []
var dir: Array = []
var heading: float
var turn_sign: int

var fillets: Array = []
var feats: Array = []
var road: Array = []
var rs: Array = []
var length: float = 0.0
var cur: Vector2


func _init(p_seed: int = 1, opts: Dictionary = {}) -> void:
	seed = p_seed
	rng = U.mulberry32(seed)
	finite = opts.has("corners") and int(opts["corners"]) > 0
	corner_limit = int(opts["corners"]) if finite else 1000000
	finish_len = float(opts.get("finish_len", Cfg.SPEEDRUN_FINISH))
	seg_lens = opts.get("seg_lens", [])
	lead_in = float(opts.get("lead_in", Cfg.LEAD_IN))
	radius = float(opts.get("radius", Cfg.DRIFT_RADIUS))
	target_time = float(opts["target_time"]) if opts.has("target_time") else NAN
	heading = Cfg.BASE_HEADING
	v = [Vector2.ZERO]
	cur = v[0]
	# Alternate turn direction; pick the first one from the seed so different
	# roads are not all mirror images of each other.
	turn_sign = -1 if rng.call() < 0.5 else 1
	# A track can instead be given an explicit op list: straights and signed arcs,
	# walked in order. That is what the hairpin and loop tracks (21-25) need,
	# because their corners are not quarter turns and the staircase builder only
	# ever emits a fixed 90 degrees. Both builders share every primitive below, so
	# a road built either way is the same kind of object.
	ops = opts.get("ops", null)
	if ops != null:
		build_ops()
	else:
		ensure(corner_limit if finite else 240)
		if finite:
			build_finish()


# Build a road from an explicit op list: {"t":"L","len"} for a straight and
# {"t":"A","deg"} for a signed arc (positive is left of the current heading).
# The opening straight is `lead_in`, and the closing straight is sized to hit
# `target_time` exactly as `build_finish` does for a staircase track.
func build_ops() -> void:
	var b := cur + Vector2(cos(heading), sin(heading)) * lead_in
	push_line(cur, b, lead_in)
	cur = b
	for op in ops:
		if op["t"] == "A":
			var th := deg_to_rad(float(op["deg"]))
			var s: float = sign(th)
			if s == 0.0:
				s = 1.0
			# A corner may carry its own radius. A run of corners that all turn the
			# same way and widen as they go is a spiral: it winds round without the
			# road crossing back over itself, which a single arc of more than a half
			# turn cannot do (its exit tangent always recrosses its entry).
			var r := float(op.get("r", radius))
			# The centre sits one radius to the side of the current heading, so the
			# arc starts tangent to the road. Recompute per corner: the heading has
			# turned, and a stale perpendicular would kink the road at every join.
			var nl := Vector2(cos(heading + PI / 2.0), sin(heading + PI / 2.0))
			var c: Vector2 = cur + nl * s * r
			var a1 := atan2(cur.y - c.y, cur.x - c.x)
			var a2 := a1 + th
			var fil := {
				"k": fillets.size(), "c": c, "r": r, "sign": s, "a1": a1, "a2": a2,
				"phi": th, "t1": cur, "t2": c + Vector2(cos(a2), sin(a2)) * r,
				"s0": length, "s1": length + r * abs(th),
			}
			fillets.append(fil)
			push_arc(fil)
			cur = fil["t2"]
			heading += th
		else:
			var ln := float(op["len"])
			if ln > 0.01:
				# The staircase's min-straight rule keeps neighbouring fillets from
				# overlapping on a road that alternates 90s. An op track is authored
				# by hand and may deliberately tuck corners closer (a hairpin's
				# connector), so it may be shorter - but never negative.
				b = cur + Vector2(cos(heading), sin(heading)) * ln
				push_line(cur, b, ln)
				cur = b
	# Nothing to grow: the road is complete. `extend_ahead` sees the limit.
	corner_limit = fillets.size()
	build_finish(heading)


func _assert_straight(len: float, vertex: int) -> void:
	if not (len >= Cfg.MIN_STRAIGHT):
		push_error("track geometry broken at vertex %d: straight %.1f < %.1f" % [vertex, len, Cfg.MIN_STRAIGHT])


# Close a finite track: a straight on from the last corner's exit, with the
# finish line at its end.
func build_finish(heading_override: Variant = null) -> void:
	var last: Dictionary = fillets[fillets.size() - 1]
	var a2: float = last["a2"]
	var last_sign: float = last["sign"]
	var h := atan2(last_sign * cos(a2), last_sign * -sin(a2)) if heading_override == null else float(heading_override)
	var a := cur
	var len := finish_len
	if not is_nan(target_time):
		var start_s := Cfg.SPEEDRUN_START_FRAC * lead_in
		var want := target_time * Cfg.SPEED + start_s - length
		if want > 120.0:
			len = want
	var b := a + Vector2(cos(h), sin(h)) * len
	push_line(a, b, len)
	cur = b
	finish_s = length
	finish = {"a": a, "b": b, "heading": h}


func step_heading() -> void:
	heading += float(turn_sign) * Cfg.TURN
	turn_sign = -turn_sign


func add_vertex() -> void:
	var last_v: Vector2 = v[v.size() - 1]
	step_heading()
	var len := lead_in if v.size() == 1 else Cfg.SEG_LEN
	if seg_lens.size() > 0 and v.size() > 1:
		len = float(seg_lens[seg_index % seg_lens.size()])
		seg_index += 1
	var nv := last_v + Vector2(cos(heading), sin(heading)) * len
	dir.append(heading)
	v.append(nv)
	if v.size() >= 3:
		finalize_corner(v.size() - 2)


func finalize_corner(k: int) -> void:
	var r := radius
	var d_in: float = dir[k - 1]
	var d_out: float = dir[k]
	var phi := U.ang_diff(d_in, d_out)
	var l := r * tan(abs(phi) / 2.0)
	var vk: Vector2 = v[k]
	var t1 := vk - Vector2(cos(d_in), sin(d_in)) * l
	var t2 := vk + Vector2(cos(d_out), sin(d_out)) * l
	var sgn: float = sign(phi)
	if sgn == 0.0:
		sgn = 1.0
	var nl := Vector2(-sin(d_in), cos(d_in))
	var c := t1 + nl * sgn * r

	var straight_len := (t1 - cur).length()
	_assert_straight(straight_len, k)
	push_line(cur, t1, straight_len)

	var a1: float = atan2(t1.y - c.y, t1.x - c.x)
	var a2: float = a1 + sgn * abs(phi)
	var fil := {
		"k": k, "c": c, "r": r, "sign": sgn, "a1": a1, "a2": a2, "phi": phi,
		"t1": t1, "t2": t2, "s0": length, "s1": length + r * abs(phi),
	}
	fillets.append(fil)
	push_arc(fil)
	cur = t2


func push_line(a: Vector2, b: Vector2, len: float) -> void:
	feats.append({"type": "line", "a": a, "b": b, "len": len, "s0": length, "s1": length + len})
	# Sample straights as finely as arcs, so the ribbon reaches the screen edge.
	var n := maxi(1, int(ceil(len / 12.0)))
	for k in range(n + 1):
		var t := float(k) / float(n)
		road.append(a.lerp(b, t))
		rs.append(length + len * t)
	length += len


func push_arc(f: Dictionary) -> void:
	var len: float = float(f["s1"]) - float(f["s0"])
	var c: Vector2 = f["c"]
	var r: float = f["r"]
	var a1: float = f["a1"]
	var a2: float = f["a2"]
	feats.append({
		"type": "arc", "c": c, "r": r, "a1": a1, "a2": a2,
		"sign": f["sign"], "len": len, "fil": f, "s0": f["s0"], "s1": f["s1"],
	})
	var n := maxi(2, int(ceil(len / 5.0)))
	for k in range(n + 1):
		var a := a1 + (a2 - a1) * (float(k) / float(n))
		road.append(c + Vector2(cos(a), sin(a)) * r)
		rs.append(float(f["s0"]) + len * (float(k) / float(n)))
	length = float(f["s1"])


func ensure(n: int) -> void:
	var target := mini(n, corner_limit)
	while fillets.size() < target:
		add_vertex()


func extend_ahead(road_index: int) -> void:
	while road.size() - road_index < 400:
		var next := mini(fillets.size() + 4, corner_limit)
		if next == fillets.size():
			break
		ensure(next)


# Nearest point on the centreline to (x, y). `hint` keeps this cheap on a long road.
func project(x: float, y: float, hint: int = 0) -> Dictionary:
	var lo := maxi(0, hint - 60)
	var hi := mini(road.size() - 1, hint + 140)
	var best: Variant = null
	for i in range(lo, hi):
		var a: Vector2 = road[i]
		var b: Vector2 = road[i + 1]
		var dx := b.x - a.x
		var dy := b.y - a.y
		var l := dx * dx + dy * dy
		var t := 0.0
		if l != 0.0:
			t = ((x - a.x) * dx + (y - a.y) * dy) / l
		t = U.clampf(t, 0.0, 1.0)
		var px := a.x + t * dx
		var py := a.y + t * dy
		var d := sqrt((x - px) * (x - px) + (y - py) * (y - py))
		var cand := {
			"d": d,
			"s": float(rs[i]) + (float(rs[i + 1]) - float(rs[i])) * t,
			"i": i, "x": px, "y": py,
		}
		if best == null:
			best = cand
			continue
		# A tie only matters when the two samples are on *different branches* of the
		# road (far apart in index) yet equally close in space. On an ordinary road
		# the nearest sample is unique, so this never fires and the behaviour is
		# exactly "first strictly-nearest wins". But a 270-degree corner doubles back
		# over its own entry, and at that crossing two branches are the same point in
		# space: both are correct, and the only sensible choice is to stay on the
		# branch we were already following. Without it the road position hops to the
		# far branch and jumps backwards.
		if absi(int(cand["i"]) - int(best["i"])) > PROJECT_BRANCH and absf(float(cand["d"]) - float(best["d"])) < PROJECT_TIE:
			if absi(int(cand["i"]) - hint) < absi(int(best["i"]) - hint):
				best = cand
		elif float(cand["d"]) < float(best["d"]):
			best = cand
	return best


# The first corner whose arc has not finished by road position s.
func fillet_at(s: float) -> int:
	for k in range(fillets.size()):
		if float(fillets[k]["s1"]) > s:
			return k
	return fillets.size() - 1


# Centreline point and heading at road position s.
func point_at(s: float) -> Dictionary:
	var lo := 0
	var hi := rs.size() - 1
	while lo < hi:
		var mid := (lo + hi) >> 1
		if float(rs[mid]) < s:
			lo = mid + 1
		else:
			hi = mid
	var i := clampi(lo - 1, 0, rs.size() - 2)
	var a: Vector2 = road[i]
	var b: Vector2 = road[i + 1]
	var span := float(rs[i + 1]) - float(rs[i])
	if span == 0.0:
		span = 1.0
	var t := U.clampf((s - float(rs[i])) / span, 0.0, 1.0)
	return {
		"x": a.x + (b.x - a.x) * t,
		"y": a.y + (b.y - a.y) * t,
		"heading": atan2(b.y - a.y, b.x - a.x),
	}
