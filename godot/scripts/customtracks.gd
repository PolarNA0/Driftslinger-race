extends RefCounted
class_name CustomTracks

# Player-authored tracks: the model behind the Editor tab.
#
# A custom track is an ordered op list, the same shape `Track.build_ops` already
# walks for the advanced tracks (21-25) and the reattach showcase (26-28):
#
#   {"t": "L", "len": 230.0}                                  a straight
#   {"t": "A", "deg": 90, "r": 62.0, "reattach": false}      a signed corner
#
# Nothing here invents geometry. The editor only authors that list; `Track` turns
# it into a road, so a hand-built track drives exactly like a shipped one.
#
# Ids start at ID_BASE so a custom track can never collide with a built-in track
# number in the record, time and replay stores (those are keyed by the number).

const ID_BASE := 1000
const MAX_TRACKS := 100
const MAX_PIECES := 48
const MAX_NAME := 24

# Corner angles the builder handles cleanly. A single arc over a half turn would
# fold the road onto itself, so the editor offers 90 / 180 / 270 and lets the
# player stack them - a 270 is one pole (see the track-shape notes in AGENTS.md).
const ANGLES := [90, 180, 270]
const MIN_RADIUS := 40.0
const MAX_RADIUS := 120.0
const RADIUS_STEP := 4.0
const MIN_LEN := 60.0
const MAX_LEN := 600.0
const LEN_STEP := 10.0
const LEAD_IN := 720.0
const FINISH_LEN := 460.0
const DEFAULT_RADIUS := 62.0
const DEFAULT_LEN := 230.0

const NAME_POOL := [
	"Neon Loop", "Sunset Run", "Tight Squeeze", "Long Way", "Switchback",
	"Coil", "Detour", "Slingshot", "Hairpin City", "The Serpent",
]


static func _store() -> Array:
	var list: Array = Storage.get_custom_tracks()
	var out := []
	for e in list:
		if e is Dictionary and e.has("ops"):
			out.append(e)
	return out


static func list() -> Array:
	return _store()


static func count() -> int:
	return _store().size()


static func get_track(id: int) -> Variant:
	for e in _store():
		if int(e["id"]) == id:
			return e
	return null


static func has(id: int) -> bool:
	return get_track(id) != null


static func _save(list: Array) -> void:
	Storage.save_custom_tracks(list)


static func _next_id(list: Array) -> int:
	var top := ID_BASE
	for e in list:
		top = maxi(top, int(e["id"]))
	return top + 1


static func _unique_name(list: Array, base: String) -> String:
	var used := {}
	for e in list:
		used[str(e["name"])] = true
	if not used.has(base):
		return base
	var n := 2
	while used.has("%s %d" % [base, n]):
		n += 1
	return "%s %d" % [base, n]


# A short, playable starter road, so a new track is never an empty page.
static func default_ops() -> Array:
	return [
		{"t": "L", "len": DEFAULT_LEN},
		{"t": "A", "deg": 90, "r": DEFAULT_RADIUS, "reattach": false},
		{"t": "L", "len": DEFAULT_LEN},
		{"t": "A", "deg": -90, "r": DEFAULT_RADIUS, "reattach": false},
		{"t": "L", "len": DEFAULT_LEN},
		{"t": "A", "deg": 90, "r": DEFAULT_RADIUS, "reattach": false},
	]


static func new_track() -> Dictionary:
	var list := _store()
	if list.size() >= MAX_TRACKS:
		return {}
	var entry := {
		"id": _next_id(list),
		"name": _unique_name(list, NAME_POOL[list.size() % NAME_POOL.size()]),
		"ops": default_ops(),
	}
	list.append(entry)
	_save(list)
	return entry


static func update(id: int, ops: Array) -> void:
	var list := _store()
	for e in list:
		if int(e["id"]) == id:
			e["ops"] = ops
	_save(list)


static func rename(id: int, name: String) -> void:
	var clean := sanitize_name(name)
	var list := _store()
	for e in list:
		if int(e["id"]) == id:
			e["name"] = _unique_name_excluding(list, clean, id)
	_save(list)


static func _unique_name_excluding(list: Array, base: String, skip: int) -> String:
	var used := {}
	for e in list:
		if int(e["id"]) != skip:
			used[str(e["name"])] = true
	if not used.has(base):
		return base
	var n := 2
	while used.has("%s %d" % [base, n]):
		n += 1
	return "%s %d" % [base, n]


static func duplicate_track(id: int) -> Variant:
	var src: Variant = get_track(id)
	if src == null:
		return null
	var list := _store()
	var copy := {
		"id": _next_id(list),
		"name": _unique_name(list, "%s copy" % str(src["name"])),
		"ops": (src["ops"] as Array).duplicate(true),
	}
	list.append(copy)
	_save(list)
	return copy


static func erase(id: int) -> void:
	var list := _store()
	var kept := []
	for e in list:
		if int(e["id"]) != id:
			kept.append(e)
	_save(kept)


static func sanitize_name(name: String) -> String:
	var s := name.strip_edges()
	if s == "":
		s = "Untitled"
	if s.length() > MAX_NAME:
		s = s.substr(0, MAX_NAME).strip_edges()
	return s


# --- pieces ------------------------------------------------------------------

static func make_straight(len: float = DEFAULT_LEN) -> Dictionary:
	return {"t": "L", "len": clampf(len, MIN_LEN, MAX_LEN)}


static func make_corner(deg: int, radius: float = DEFAULT_RADIUS, reattach: bool = false) -> Dictionary:
	return {"t": "A", "deg": deg, "r": clampf(radius, MIN_RADIUS, MAX_RADIUS), "reattach": reattach}


static func is_corner(p: Dictionary) -> bool:
	return str(p.get("t", "L")) == "A"


static func corner_count(ops: Array) -> int:
	var n := 0
	for p in ops:
		if is_corner(p):
			n += 1
	return n


static func describe(p: Dictionary) -> String:
	if is_corner(p):
		var deg := int(p.get("deg", 90))
		var way := "Left" if deg > 0 else "Right"
		var tag := " \u00b7 reattach" if bool(p.get("reattach", false)) else ""
		return "%s %d\u00b0 \u00b7 r%d%s" % [way, absi(deg), int(p.get("r", DEFAULT_RADIUS)), tag]
	return "Straight %d" % int(p.get("len", DEFAULT_LEN))


# The piece to append after `ops`: a corner that keeps the road from folding.
# Two corners the same way in a row would point the road back over itself, so the
# default direction is always the opposite of the last corner.
static func next_corner(ops: Array, deg: int = 90) -> Dictionary:
	var last_dir := -1
	for i in range(ops.size() - 1, -1, -1):
		if is_corner(ops[i]):
			last_dir = 1 if int(ops[i]["deg"]) > 0 else -1
			break
	return make_corner(signi(-last_dir) * absi(deg))


# --- validation --------------------------------------------------------------

# A track the game can actually drive. Returns {ok, error, corners, length}.
static func validate(ops: Array) -> Dictionary:
	if ops.size() == 0:
		return {"ok": false, "error": "Add a piece to start.", "corners": 0, "length": 0.0}
	if ops.size() > MAX_PIECES:
		return {"ok": false, "error": "Too many pieces (max %d)." % MAX_PIECES, "corners": 0, "length": 0.0}
	var corners := 0
	var length := LEAD_IN
	for p in ops:
		if is_corner(p):
			var deg := int(p.get("deg", 0))
			if absi(deg) not in ANGLES:
				return {"ok": false, "error": "A corner must be 90, 180 or 270 degrees.", "corners": corners, "length": length}
			var r := float(p.get("r", DEFAULT_RADIUS))
			if r < MIN_RADIUS or r > MAX_RADIUS:
				return {"ok": false, "error": "Corner radius must be %d-%d." % [int(MIN_RADIUS), int(MAX_RADIUS)], "corners": corners, "length": length}
			corners += 1
			length += r * absf(deg_to_rad(float(deg)))
		else:
			var ln := float(p.get("len", DEFAULT_LEN))
			if ln < MIN_LEN or ln > MAX_LEN:
				return {"ok": false, "error": "A straight must be %d-%d long." % [int(MIN_LEN), int(MAX_LEN)], "corners": corners, "length": length}
			length += ln
	length += FINISH_LEN
	if corners < 2:
		return {"ok": false, "error": "A track needs at least 2 corners.", "corners": corners, "length": length}
	return {"ok": true, "error": "", "corners": corners, "length": length}


# --- transforms --------------------------------------------------------------

# Mirror: flip every corner's direction, so the road turns the other way.
static func mirror(ops: Array) -> Array:
	var out := []
	for p in ops:
		if is_corner(p):
			out.append(make_corner(-int(p["deg"]), float(p["r"]), bool(p.get("reattach", false))))
		else:
			out.append(make_straight(float(p["len"])))
	return out


# Reverse: drive the road the other way. Walk the list backwards and flip each
# corner, which is the exact inverse of the built road.
static func reverse(ops: Array) -> Array:
	var out := []
	for i in range(ops.size() - 1, -1, -1):
		var p: Dictionary = ops[i]
		if is_corner(p):
			out.append(make_corner(-int(p["deg"]), float(p["r"]), bool(p.get("reattach", false))))
		else:
			out.append(make_straight(float(p["len"])))
	return out


# --- build -------------------------------------------------------------------

# The `opts` dictionary `Track.new` wants. Radius is the default; each corner
# carries its own, so a mixed-radius track builds correctly.
static func opts(ops: Array) -> Dictionary:
	return {
		"corners": corner_count(ops),
		"radius": DEFAULT_RADIUS,
		"lead_in": LEAD_IN,
		"finish_len": FINISH_LEN,
		"ops": ops.duplicate(true),
	}


# opts for a stored track id, or an empty dictionary if it is gone.
static func opts_for_id(id: int) -> Dictionary:
	var t: Variant = get_track(id)
	if t == null:
		return {}
	return opts(t["ops"])


static func display_name(id: int) -> String:
	var t: Variant = get_track(id)
	return str(t["name"]) if t != null else "Custom track"
