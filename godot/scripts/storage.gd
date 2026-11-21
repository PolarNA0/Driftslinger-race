extends RefCounted
class_name Storage

# Port of the old js/storage.js (removed with the JS client). Records, best times, replays and history are namespaced
# per signed-in account, so two people on one device do not overwrite each other.
# Signed out, everything falls back to a "guest" bucket. Preferences (the car
# skin) are global - they are about the device, not the person.
#
# Storage is a JSON file in user:// instead of localStorage.

const MAX_HISTORY := 50

static func _path(name: String) -> String:
	var account := Account.current_account()
	if account == "":
		account = "guest"
	return "user://slingdrift.%s.%s.json" % [account, name]


static func _read(name: String, fallback: Variant) -> Variant:
	var p := _path(name)
	if not FileAccess.file_exists(p):
		return fallback
	var f := FileAccess.open(p, FileAccess.READ)
	if f == null:
		return fallback
	var txt := f.get_as_text()
	f.close()
	var parsed: Variant = JSON.parse_string(txt)
	return fallback if parsed == null else parsed


static func _write(name: String, value: Variant) -> void:
	_write_text(_path(name), JSON.stringify(value))


# Write a sibling temp file, then rename it over the target. A crash mid-write
# then leaves the previous save intact instead of a truncated JSON file.
static func _write_text(path: String, text: String) -> void:
	var tmp := path + ".tmp"
	var f := FileAccess.open(tmp, FileAccess.WRITE)
	if f == null:
		return
	f.store_string(text)
	f.close()
	var dir := DirAccess.open("user://")
	if dir == null:
		return
	dir.rename(tmp.get_file(), path.get_file())


# --- endless: best distance per seed -----------------------------------------
static func get_record(seed: int) -> Dictionary:
	var all: Dictionary = _read("records.v1", {})
	return all.get(str(seed), {"dist": 0.0, "corners": 0})


static func save_record(seed: int, dist: float, corners: int) -> Dictionary:
	var all: Dictionary = _read("records.v1", {})
	var prev: Dictionary = all.get(str(seed), {"dist": 0.0, "corners": 0})
	if dist > float(prev.get("dist", 0.0)):
		all[str(seed)] = {"dist": dist, "corners": corners}
		_write("records.v1", all)
	return prev


static func best_distance() -> float:
	var all: Dictionary = _read("records.v1", {})
	var best := 0.0
	for r in all.values():
		best = maxf(best, float(r.get("dist", 0.0)))
	return best


# --- speedrun: best time per seed, in seconds. Lower is better ---------------
static func get_best_time(seed: int) -> Variant:
	var all: Dictionary = _read("times.v1", {})
	var t: Variant = all.get(str(seed))
	return float(t) if t != null else null


static func save_best_time(seed: int, time: float) -> Variant:
	var all: Dictionary = _read("times.v1", {})
	var raw: Variant = all.get(str(seed))
	var prev: Variant = float(raw) if raw != null else null
	if prev == null or time < float(prev):
		all[str(seed)] = time
		_write("times.v1", all)
	return prev


# --- replays: the button steps of the best run per track ---------------------
static func get_replay(seed: int) -> Variant:
	var all: Dictionary = _read("replays.v1", {})
	var r: Variant = all.get(str(seed))
	if r is Dictionary and r.has("steps") and r["steps"] is String:
		return r
	return null


static func save_replay(seed: int, replay: Dictionary) -> void:
	var all: Dictionary = _read("replays.v1", {})
	all[str(seed)] = replay
	_write("replays.v1", all)


# --- run history: every finished run, newest first ---------------------------
static func get_runs(seed: int) -> Array:
	var all: Dictionary = _read("runs.v1", {})
	var list: Variant = all.get(str(seed))
	return list if list is Array else []


static func all_runs() -> Array:
	var all: Dictionary = _read("runs.v1", {})
	var out := []
	for key in all.keys():
		var list: Variant = all[key]
		if list is Array:
			for r in list:
				var row: Dictionary = (r as Dictionary).duplicate()
				row["seed"] = int(key)
				out.append(row)
	out.sort_custom(func(a, b): return float(a["at"]) > float(b["at"]))
	return out


# Record a finished run. Returns its rank within this track's history (1 = PB).
static func add_run(seed: int, time: float, at: float = -1.0) -> int:
	if at < 0.0:
		at = float(Time.get_unix_time_from_system()) * 1000.0
	var all: Dictionary = _read("runs.v1", {})
	var list: Array = all.get(str(seed), [])
	list.append({"time": time, "at": at})
	list.sort_custom(func(a, b): return float(a["time"]) < float(b["time"]))
	all[str(seed)] = list.slice(0, MAX_HISTORY)
	_write("runs.v1", all)
	for i in range(list.size()):
		if float(list[i]["at"]) == at and float(list[i]["time"]) == time:
			return i + 1
	return 0


# --- custom tracks: player-authored roads, per account -----------------------
# The version suffix is the schema: bump it and old shapes are ignored rather
# than misread, which is why it is here.
const CUSTOM_NAME := "customtracks.v1"


static func get_custom_tracks() -> Array:
	var list: Variant = _read(CUSTOM_NAME, [])
	return list if list is Array else []


static func save_custom_tracks(list: Array) -> void:
	_write(CUSTOM_NAME, list)


# --- preferences: global, not per account ------------------------------------
const PREF_NAME := "prefs.v1"


static func get_pref(name: String, fallback: Variant = null) -> Variant:
	var all: Dictionary = _read(PREF_NAME, {})
	return all.get(name, fallback)


static func set_pref(name: String, value: Variant) -> void:
	var all: Dictionary = _read(PREF_NAME, {})
	all[name] = value
	_write(PREF_NAME, all)
