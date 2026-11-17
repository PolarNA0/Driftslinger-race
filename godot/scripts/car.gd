extends RefCounted
class_name Car

# Port of the old js/car.js (removed with the JS client). One button: hold to latch onto the pole and drift around it,
# let go to fly straight off the tangent, then curve gently home.

var track: Track
var attached: bool
var corner: int
var orbit_angle: float
var sgn: float
var radius: float
var spent: int
var grabbed: int
var regrabs: int
var released_corner: int
var released_angle: float
var grabbed_corners: Dictionary
var reattach_attempt: bool
var speed_scale: float
var effect_timer: float
var alive: bool
var dead: Variant
var finished: bool
var max_off: float
var trail: Array
var time: float
var s: float
var hint: int
var off: float
var x: float
var y: float
var angle: float


func _init() -> void:
	reset(null)


func reset(p_track: Track) -> void:
	track = p_track
	attached = false
	corner = 0
	orbit_angle = 0.0
	sgn = 1.0
	radius = Cfg.DRIFT_RADIUS
	spent = -1
	grabbed = 0
	regrabs = 0
	released_corner = -1
	released_angle = 0.0
	grabbed_corners = {}
	reattach_attempt = false
	speed_scale = 1.0
	effect_timer = 0.0
	alive = true
	dead = null
	finished = false
	max_off = 0.0
	trail = []
	time = 0.0
	s = 0.0
	hint = 0
	off = 0.0
	x = 0.0
	y = 0.0
	angle = 0.0
	if track == null:
		return
	var f: Dictionary = track.feats[0]
	var a: Vector2 = f["a"]
	var b: Vector2 = f["b"]
	var p0 := a + (b - a) * 0.15
	x = p0.x
	y = p0.y
	angle = atan2(b.y - a.y, b.x - a.x)
	var p := track.project(x, y, 0)
	hint = p["i"]
	s = p["s"]
	corner = track.fillet_at(s)


func _fillet() -> Dictionary:
	return track.fillets[corner]


func step(dt: float, held: bool) -> void:
	if not alive or finished:
		return
	time += dt
	# A reattach boost/slow is brief: count it down so the next step is back to the
	# base speed unless another reattach lands.
	if effect_timer > 0.0:
		effect_timer = maxf(0.0, effect_timer - dt)
		if effect_timer == 0.0:
			speed_scale = 1.0

	if held:
		if not attached:
			try_grab()
		if attached:
			drift(dt)
		else:
			fly(dt)
	else:
		if attached:
			release(dt)
		fly(dt)

	track.extend_ahead(hint)
	var p := track.project(x, y, hint)
	hint = p["i"]
	off = p["d"]
	if attached:
		# Latched, our place on the road is exact, not a nearest-point guess: the
		# orbit angle *is* the angle along this arc, so it gives the road position
		# directly. Projecting the car's xy instead would be ambiguous wherever the
		# road crosses itself - a 270-degree corner passes back over its own entry,
		# and the nearest point can jump to the other branch mid-swing. Deriving s
		# from the arc keeps us on the branch we are actually driving.
		var f := _fillet()
		s = float(f["s0"]) + (orbit_angle - float(f["a1"])) * sgn * float(f["r"])
	else:
		s = p["s"]
	if off > max_off:
		max_off = off
	# Crossing the finish line ends the run cleanly, even mid-swing. Checked
	# before the wall so a win on the line is not a crash.
	if s >= track.finish_s:
		finished = true
		alive = false
		return
	if off > Cfg.ROAD_HALF_WIDTH:
		alive = false
		dead = "wall"
	# Only retarget while flying; while attached `corner` is the arc we are on.
	if not attached:
		corner = track.fillet_at(s)

	trail.append(Vector2(x, y))
	while trail.size() > Cfg.TRAIL_LEN:
		trail.pop_front()


func try_grab() -> bool:
	var f := _fillet()
	if corner == spent:
		return false
	var c: Vector2 = f["c"]
	var d := U.dist(c.x, c.y, x, y)
	if d > Cfg.GRAB_RANGE:
		return false
	attached = true
	sgn = f["sign"]
	radius = U.clampf(d, Cfg.MIN_GRAB_RADIUS, float(f["r"]) + Cfg.GRAB_RANGE)
	# Unwrap the orbit angle onto the arc. atan2 returns (-PI, PI], so a raw value
	# cannot represent a corner that turns 180 or 270 degrees - "distance left to
	# the end of the arc" would wrap and read as already done. Pick the
	# representative congruent to the reference angle (the arc start on a fresh
	# grab, the release angle on a re-grab); from there the drift accumulates
	# without wrapping, and `done` / `remaining` compare straight against `a2`
	# however far round the corner goes.
	var raw := atan2(y - c.y, x - c.x)
	# Normally unwrap onto the arc start: a fresh grab is made on the approach,
	# with the car sitting near the entry. A re-grab is different - the car flew
	# off partway round, so unwrap onto the angle it left from. Using the entry
	# there would drop the car back to the start and throw away its progress.
	var ref := released_angle if corner == released_corner else float(f["a1"])
	orbit_angle = raw + TAU * round((ref - raw) / TAU)
	var is_regrab := corner == released_corner and grabbed_corners.has(corner)
	if is_regrab:
		regrabs += 1
		# A reattach in progress: this pillar was bailed out of and is now caught
		# again, so a later release may pay off.
		reattach_attempt = true
	# Count the grabs per pillar: one reattach pays, a second on the same pillar does
	# not, and each pillar is counted on its own.
	grabbed_corners[corner] = int(grabbed_corners.get(corner, 0)) + 1
	grabbed += 1
	return true


func place() -> void:
	var f := _fillet()
	var c: Vector2 = f["c"]
	x = c.x + cos(orbit_angle) * radius
	y = c.y + sin(orbit_angle) * radius
	angle = orbit_angle + sgn * PI / 2.0


func drift(dt: float) -> void:
	var f := _fillet()
	var fr: float = f["r"]
	var dr := 0.0
	if radius != fr:
		var st := Cfg.REEL_SPEED * dt
		if abs(radius - fr) <= st:
			dr = fr - radius
		else:
			dr = sign(fr - radius) * st
	# One step's travel split between the tangential and radial directions, so the
	# total speed stays at SPEED while the radius reels in. Adding the two motions
	# instead would inject free tangential speed and make a wide grab fastest.
	var total := Cfg.SPEED * speed_scale * dt
	var tangential := sqrt(maxf(0.0, total * total - dr * dr))
	orbit_angle += sgn * tangential / radius
	radius += dr
	place()


func fly(dt: float) -> void:
	centre(dt)
	x += cos(angle) * Cfg.SPEED * speed_scale * dt
	y += sin(angle) * Cfg.SPEED * speed_scale * dt


# Steer gently back toward the centreline while flying (pure pursuit).
func centre(dt: float) -> void:
	if track == null or off < Cfg.CENTRE_DEAD:
		return
	var p := track.point_at(s + Cfg.CENTRE_LOOK)
	var want := atan2(float(p["y"]) - y, float(p["x"]) - x)
	var k := minf(1.0, Cfg.CENTRE_RATE * dt)
	angle += U.ang_diff(angle, want) * k


# Let go of the pole. A release within one frame of the arc's end is snapped onto
# the exit point, so a perfectly timed release does not leave on a sliver of angle.
func release(dt: float) -> void:
	var f := _fillet()
	var st := Cfg.SPEED / radius * dt
	var carried := done()
	if carried and sgn * (orbit_angle - float(f["a2"])) <= st:
		orbit_angle = f["a2"]
		radius = f["r"]
		place()
	attached = false
	released_corner = corner
	released_angle = orbit_angle
	# A plain pillar is spent the moment you let go. A reattachable pillar is
	# spent only by riding the arc to its end: bail out early and it stays open,
	# so the same pole can be caught again. An ordinary clean line rides every
	# arc out, so its behaviour is unchanged.
	# A reattach that is carried to the end of the arc pays off: the first one on a
	# pillar is a brief boost, and a second one on the same pillar is a slow-down
	# instead, so spamming it costs. It only counts as a reattach if this release is
	# near the end of the arc - bailing out early and flying on is just a bail, and
	# leaves the pillar open for the catch that does pay.
	var arc := absf(float(f["a2"]) - float(f["a1"]))
	if reattach_attempt and f.get("reattach", false) and remaining() <= Cfg.REATTACH_END_FRAC * arc:
		reattach_attempt = false
		var good := int(grabbed_corners.get(corner, 1)) <= 2
		speed_scale = Cfg.REATTACH_BOOST if good else Cfg.REATTACH_SLOW
		effect_timer = Cfg.REATTACH_EFFECT_TIME
	if carried or not f.get("reattach", false):
		spent = corner


# How far the orbit still has to turn before this corner is done.
#
# Plain subtraction, not `ang_diff`: `orbit_angle` is unwrapped onto the arc at
# grab time (see try_grab) and `a2` is `a1` plus the corner's deflection, so the
# two live on the same branch. Wrapping here would make a 180- or 270-degree
# corner read as already finished and the car would let go the moment it latched.
func remaining() -> float:
	var f := _fillet()
	return maxf(0.0, (float(f["a2"]) - orbit_angle) * sgn)


# True once the car has carried the corner round to the end of its arc.
func done() -> bool:
	var f := _fillet()
	return sgn * (orbit_angle - float(f["a2"])) >= 0.0


func distance() -> float:
	return time * Cfg.SPEED
