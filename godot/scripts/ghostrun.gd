extends RefCounted
class_name GhostRun

# Port of js/ghostrun.js. A ghost is defined by one integer id: the id turns into
# a deterministic button policy, and the policy is played out on the real physics.
# The same id gives the same run forever, on every device, so the board ships as
# nothing but (time, id) pairs and is still watchable.

const NAMES := [
	"Vex", "Nyx_77", "DriftKing", "pls_no_wall", "Kestrel", "blip", "Mako",
	"tuesday", "RustyBolt", "0xGRAV", "Pico", "Havoc", "slinky", "Moth",
	"Quill", "zed.", "Bandit", "OK_GO", "Wisp", "NineLives", "jolt",
	"Marble", "Sway", "Tandem", "Griffin", "null_ptr", "Yolk", "Snap",
	"Dune", "Vortex", "Clover", "Ash", "Rumble", "Fable", "Krill", "Onyx",
	"Flick", "Rook", "Sable", "Tonic", "Umber", "Vane", "Wren", "Xeno",
	"Yara", "Zephyr", "Arc", "Brisk", "Cinder", "Dash", "Echo", "Flint",
	"Grit", "Halo", "Iris", "Jinx", "Kite", "Lumen", "Mist", "Nova",
]
const TAGS := ["", "", "", "", "_", "", "", ".", "", "", "_", "", "", "-", ""]


static func ghost_name(id: int) -> String:
	var h := U.imul32(id + 1, 2654435761) & 0xFFFFFFFF
	var tag: String = TAGS[(h >> 8) % TAGS.size()]
	var suffix := ""
	if float(U.mulberry32(h).call()) < 0.2:
		suffix = str(1 + (h % 97))
	return NAMES[h % NAMES.size()] + tag + suffix


# The button policy for ghost `id`, as a function of the car state.
static func ghost_policy(id: int) -> Callable:
	var rng := U.mulberry32((U.imul32(id + 1, 0x9e3779b9) ^ 0x85ebca6b) & 0xFFFFFFFF)
	# Grab when the pole is this close, release this many degrees before (-) or
	# after (+) the end of the arc. Spread wide so the field covers the whole band
	# of times that still finish.
	var grab: float = 30.0 + float(rng.call()) * 65.0
	var release: float = -35.0 + float(rng.call()) * 57.0
	var deg := PI / 180.0
	return func(car: Car) -> bool:
		if car.attached:
			var f: Dictionary = car.track.fillets[car.corner]
			return car.sgn * (car.orbit_angle - float(f["a2"])) < release * deg
		var f2: Dictionary = car.track.fillets[car.corner]
		var c: Vector2 = f2["c"]
		return U.dist(c.x, c.y, car.x, car.y) <= grab


# Play ghost `id` on track `n`. Returns {time, steps, replay} or null if it crashed.
static func simulate_ghost(n: int, id: int) -> Variant:
	var track := Track.new(n, Tracks.track_opts(n))
	var car := Car.new()
	car.reset(track)
	var policy := ghost_policy(id)
	var steps := []
	var i := 0
	var dt := 1.0 / 120.0
	while car.alive and i < 200000:
		i += 1
		var held: bool = policy.call(car)
		steps.append(held)
		car.step(dt, held)
	if not car.finished:
		return null
	return {"time": car.time, "steps": steps, "replay": Replay.make_replay(n, steps, car.time)}
