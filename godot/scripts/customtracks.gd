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
const MAX_CORNERS := 24
const MAX_NAME := 24

# Corner angles the builder handles cleanly. A single arc over a half turn would
# fold the road onto itself, so the editor offers 90 / 180 / 270 and lets the
# player stack them - a 270 is one pole (see the track-shape notes in AGENTS.md).
const ANGLES := [90, 180, 270]

# The widest corner a player can build is bounded by how far a pole can be caught:
# `Car.try_grab` refuses a pole further than `Cfg.GRAB_RANGE` (95px) from the car,
# so a corner whose arc radius is at or past that is literally impossible - the car
# flies straight past the pole and hits the wall. This cap is that limit with a
# little margin, so every corner the editor offers is catchable.
const MAX_RADIUS := 92.0
const MIN_RADIUS := 40.0
const RADIUS_STEP := 4.0
const MIN_LEN := 60.0
const MAX_LEN := 600.0
const LEN_STEP := 10.0
const LEAD_IN := 720.0
const FINISH_LEN := 460.0
const DEFAULT_RADIUS := 62.0
const DEFAULT_LEN := 230.0

# --- colours -----------------------------------------------------------------
# A custom track carries its own look: a road colour and a ground (background)
# colour. The stripe and the pillars are derived from those two, so a player picks
# two colours and gets a consistent road rather than four that can clash. Stored as
# hex strings so the whole track stays plain JSON.

const THEME_PRESETS := [
	{"name": "Classic", "road": "494949", "ground": "48d350"},
	{"name": "Night", "road": "c8c8c8", "ground": "113a56"},
	{"name": "Sunset", "road": "4b4b4b", "ground": "fea92e"},
	{"name": "Candy", "road": "4a4a4a", "ground": "dc2051"},
	{"name": "Sky", "road": "4a4a4a", "ground": "59c4ff"},
	{"name": "Wine", "road": "cbcbcb", "ground": "4d1023"},
	{"name": "Mint", "road": "3a3a3a", "ground": "7ef2b0"},
	{"name": "Grape", "road": "e2e2e2", "ground": "6a3fd6"},
]

const DEFAULT_THEME := {"road": "4a4a4a", "ground": "48d350"}

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
		make_finish(),
	]


static func new_track() -> Dictionary:
	var list := _store()
	if list.size() >= MAX_TRACKS:
		return {}
	var preset: Dictionary = THEME_PRESETS[list.size() % THEME_PRESETS.size()]
	var entry := {
		"id": _next_id(list),
		"name": _unique_name(list, NAME_POOL[list.size() % NAME_POOL.size()]),
		"ops": default_ops(),
		"road": str(preset["road"]),
		"ground": str(preset["ground"]),
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
	var palette := theme_of(src)
	var copy := {
		"id": _next_id(list),
		"name": _unique_name(list, "%s copy" % str(src["name"])),
		"ops": (src["ops"] as Array).duplicate(true),
		"road": palette["road"],
		"ground": palette["ground"],
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


# The finish line is a straight that ends the track: the car crosses its far end and
# the run is over. It is an ordinary piece you place on the grid, because that is what
# it is on the road - a stretch of tarmac with a line across it. Placing it also closes
# the track, so it is always the last piece and there is exactly one.
static func make_finish(len: float = FINISH_LEN) -> Dictionary:
	return {"t": "F", "len": clampf(len, MIN_LEN, MAX_LEN)}


static func make_corner(deg: int, radius: float = DEFAULT_RADIUS, reattach: bool = false) -> Dictionary:
	return {"t": "A", "deg": deg, "r": clampf(radius, MIN_RADIUS, MAX_RADIUS), "reattach": reattach}


static func is_corner(p: Dictionary) -> bool:
	return str(p.get("t", "L")) == "A"


# A finish is not a corner and not an ordinary straight: `Track.build_ops` closes the
# road with it instead of running it as another leg.
static func is_finish(p: Dictionary) -> bool:
	return str(p.get("t", "L")) == "F"


static func finish_index(ops: Array) -> int:
	for i in range(ops.size()):
		if is_finish(ops[i]):
			return i
	return -1


static func corner_count(ops: Array) -> int:
	var n := 0
	for p in ops:
		if is_corner(p):
			n += 1
	return n


static func describe(p: Dictionary) -> String:
	if is_finish(p):
		return "Finish line \u00b7 %d" % int(p.get("len", FINISH_LEN))
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


# --- theme -------------------------------------------------------------------

# The colours for a stored track, always complete: a track saved before colours
# existed (or one with a missing/short value) falls back to the default, so the
# renderer never has to guard against a half-set theme.
static func theme_of(entry: Variant) -> Dictionary:
	if entry == null or not (entry is Dictionary):
		return DEFAULT_THEME.duplicate()
	var road := _hex(str(entry.get("road", "")), str(DEFAULT_THEME["road"]))
	var ground := _hex(str(entry.get("ground", "")), str(DEFAULT_THEME["ground"]))
	return {"road": road, "ground": ground}


static func _hex(value: String, fallback: String) -> String:
	var v := value.strip_edges().lstrip("#")
	if v.length() != 6 or not _is_hex(v):
		return fallback
	return v.to_upper()


static func _is_hex(v: String) -> bool:
	for i in range(v.length()):
		var c := v[i]
		if not ("0123456789abcdefABCDEF".contains(c)):
			return false
	return true


static func theme_for_id(id: int) -> Dictionary:
	return theme_of(get_track(id))


static func set_theme(id: int, road: String, ground: String) -> void:
	var list := _store()
	for e in list:
		if int(e["id"]) == id:
			e["road"] = _hex(road, str(DEFAULT_THEME["road"]))
			e["ground"] = _hex(ground, str(DEFAULT_THEME["ground"]))
	_save(list)


# The stripe and the pillars are derived from the two colours the player picks, so
# the road reads as one palette instead of four colours that can clash. `stripe` is
# a touch lighter than the road; `pole` is a darkened ground, which keeps the poles
# distinct from the road without inventing a fifth colour.
static func theme_colors(entry: Variant) -> Dictionary:
	var t := theme_of(entry)
	var road := Color(t["road"])
	var ground := Color(t["ground"])
	return {
		"road": road,
		"ground": ground,
		"stripe": road.lightened(0.10),
		"pole": ground.darkened(0.45),
	}


# --- validation --------------------------------------------------------------

# A track the game can actually drive. Returns {ok, error, corners, length}.
static func validate(ops: Array) -> Dictionary:
	if ops.size() == 0:
		return {"ok": false, "error": "Add a piece to start.", "corners": 0, "length": 0.0}
	if ops.size() > MAX_PIECES:
		return {"ok": false, "error": "Too many pieces (max %d)." % MAX_PIECES, "corners": 0, "length": 0.0}
	var corners := 0
	var length := LEAD_IN
	var finish_at := -1
	for i in range(ops.size()):
		var p: Dictionary = ops[i]
		if is_finish(p):
			# The finish closes the road, so nothing may follow it: a piece after it
			# would be drawn past the finish line and never driven.
			if finish_at >= 0:
				return {"ok": false, "error": "A track has one finish line.", "corners": corners, "length": length}
			if i != ops.size() - 1:
				return {"ok": false, "error": "The finish line goes last.", "corners": corners, "length": length}
			finish_at = i
			var fl := float(p.get("len", FINISH_LEN))
			if fl < MIN_LEN or fl > MAX_LEN:
				return {"ok": false, "error": "The finish straight must be %d-%d long." % [int(MIN_LEN), int(MAX_LEN)], "corners": corners, "length": length}
			length += fl
		elif is_corner(p):
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
	if corners < 2:
		return {"ok": false, "error": "A track needs at least 2 corners.", "corners": corners, "length": length}
	if corners > MAX_CORNERS:
		return {"ok": false, "error": "Too many corners (max %d)." % MAX_CORNERS, "corners": corners, "length": length}
	if finish_at < 0:
		return {"ok": false, "error": "Add a finish line to end the track.", "corners": corners, "length": length}
	return {"ok": true, "error": "", "corners": corners, "length": length}


# --- transforms --------------------------------------------------------------

# Mirror: flip every corner's direction, so the road turns the other way.
static func mirror(ops: Array) -> Array:
	var out := []
	for p in ops:
		if is_finish(p):
			out.append(make_finish(float(p["len"])))
		elif is_corner(p):
			out.append(make_corner(-int(p["deg"]), float(p["r"]), bool(p.get("reattach", false))))
		else:
			out.append(make_straight(float(p["len"])))
	return out


# Reverse: drive the road the other way. Walk the list backwards and flip each
# corner, which is the exact inverse of the built road. The finish comes back to the
# end, where it has to be.
static func reverse(ops: Array) -> Array:
	var out := []
	var fin := 0.0
	for i in range(ops.size() - 1, -1, -1):
		var p: Dictionary = ops[i]
		if is_finish(p):
			# Reversing puts the finish first, but a road ends at its finish line, so
			# it is held back and appended last instead of being emitted here.
			fin = float(p["len"])
		elif is_corner(p):
			out.append(make_corner(-int(p["deg"]), float(p["r"]), bool(p.get("reattach", false))))
		else:
			out.append(make_straight(float(p["len"])))
	if fin > 0.0:
		out.append(make_finish(fin))
	return out


# --- build -------------------------------------------------------------------

# The `opts` dictionary `Track.new` wants. Radius is the default; each corner
# carries its own, so a mixed-radius track builds correctly.
static func opts(ops: Array, entry: Variant = null) -> Dictionary:
	return {
		"corners": corner_count(ops),
		"radius": DEFAULT_RADIUS,
		"lead_in": LEAD_IN,
		# The finish piece is the closing straight, so its own length is what the
		# builder uses; FINISH_LEN is only the default a new piece starts at.
		"finish_len": finish_len_of(ops),
		"ops": ops.duplicate(true),
		"theme": theme_of(entry),
	}


# The length of the track's finish straight, or the default when it has none (an
# old saved track, which `validate` will report as unfinished).
static func finish_len_of(ops: Array) -> float:
	var i := finish_index(ops)
	if i < 0:
		return FINISH_LEN
	return float((ops[i] as Dictionary).get("len", FINISH_LEN))


# opts for a stored track id, or an empty dictionary if it is gone.
static func opts_for_id(id: int) -> Dictionary:
	var t: Variant = get_track(id)
	if t == null:
		return {}
	return opts(t["ops"], t)


static func display_name(id: int) -> String:
	var t: Variant = get_track(id)
	return str(t["name"]) if t != null else "Custom track"
