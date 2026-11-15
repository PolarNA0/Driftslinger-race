extends RefCounted
class_name Car

# Port of js/car.js. One button: hold to latch onto the pole and drift around it,
# let go to fly straight off the tangent, then curve gently home.

var track: Track
var attached: bool
var corner: int
var orbit_angle: float
var sgn: float
var radius: float
var spent: int
var grabbed: int
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
	# representative congruent to the angle nearest the arc's start; from there the
	# drift accumulates without wrapping, and `done` / `remaining` compare straight
	# against `a2` however far round the corner goes.
	var raw := atan2(y - c.y, x - c.x)
	var a1 := float(f["a1"])
	orbit_angle = raw + TAU * round((a1 - raw) / TAU)
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
	var total := Cfg.SPEED * dt
	var tangential := sqrt(maxf(0.0, total * total - dr * dr))
	orbit_angle += sgn * tangential / radius
	radius += dr
	place()


func fly(dt: float) -> void:
	centre(dt)
	x += cos(angle) * Cfg.SPEED * dt
	y += sin(angle) * Cfg.SPEED * dt


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
	if done() and sgn * (orbit_angle - float(f["a2"])) <= st:
		orbit_angle = f["a2"]
		radius = f["r"]
		place()
	attached = false
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
