extends RefCounted
class_name Tracks

# Port of the old js/tracks.js (removed with the JS client). The time-attack tracks, each a fixed road derived from its
# number, so a track is the same road on every device. Three more tracks (26-28)
# showcase the reattachable pillar; see REATTACH_TRACKS below.

# Tracks 6-20 were removed: the same staircase with the radius and rhythm cycled,
# so they added menu length without adding a shape. The numbers are kept as they
# were (21-25 are still the advanced tracks), so a leaderboard entry or a replay
# for track 1 is still track 1. The gaps are deliberate: replacements will be
# dropped into the empty numbers later.
#
# The set is *derived* from the track tables (ADVANCED, REATTACH_TRACKS below), so
# adding a track is one entry in one table and nothing else: it joins the menu, the
# verifier and the upload path at once, and cannot be forgotten in one of them and
# shipped as "cannot be uploaded". This mirrors the JS physics (physics/tracks.js),
# which derives its playable set the same way.
static func _track_numbers() -> Array:
	var nums := [1, 2, 3, 4, 5]
	for k in ADVANCED.keys():
		nums.append(int(k))
	for k in REATTACH_TRACKS.keys():
		nums.append(int(k))
	nums.sort()
	return nums

static var PLAYABLE_TRACKS := _track_numbers()

# Is `n` a track the game plays? The set has gaps, so a range check would accept a
# removed track; membership is the honest test.
static func is_playable_track(n: int) -> bool:
	return PLAYABLE_TRACKS.has(n)

const RHYTHMS := [
	[1, 1, 1, 1],
	[1, 2, 1, 2],
	[2, 1, 1, 2, 1, 1],
	[1, 1, 2, 2],
	[2, 1, 1, 1, 2, 1],
	[1, 2, 2, 1, 1, 2],
]
const MAX_VISIBLE_STRAIGHT := 150.0

# The five advanced tracks (21-25). These are not staircases: each is built from
# an explicit op list, which lets a corner turn more than a quarter - a hairpin is
# a 180 and a loop is a 270. A single arc of more than a half turn always folds
# the road onto itself (its exit straight recrosses the entry at exactly the
# corner radius, inside the grab range), so the loops here are built the way real
# tracks are: a widening spiral of shorter arcs, or a hairpin plus a quarter. The
# car tracks its own branch while latched (see Car.step), so even a road that
# crosses itself drives cleanly.
const ADVANCED := {
	21: {
		"lead_in": 620.0, "target_time": 10.3,
		"defs": [
			{"deg": 90}, {"deg": -90}, {"deg": 180}, {"deg": -90},
			{"deg": 90}, {"deg": -90}, {"deg": 90},
		],
	},
	22: {
		"lead_in": 620.0, "target_time": 10.3,
		"defs": [
			{"deg": 90}, {"deg": 180}, {"deg": -90}, {"deg": 90},
			{"deg": -180}, {"deg": 90},
		],
	},
	23: {
		"lead_in": 620.0, "target_time": 10.3,
		"defs": [
			{"deg": 270}, {"deg": -90}, {"deg": 90}, {"deg": -90},
		],
	},
	24: {
		"lead_in": 620.0, "target_time": 10.3,
		"defs": [
			{"deg": 270}, {"deg": -270}, {"deg": 90},
		],
	},
	25: {
		"lead_in": 620.0, "target_time": 10.3,
		"defs": [
			{"deg": 180}, {"deg": 270}, {"deg": -90}, {"deg": 90},
		],
	},
}

# The three reattach showcase tracks (26-28). Same op-list builder as the advanced
# tracks, but their corners carry `reattach: true`, so letting go before an arc is
# finished leaves that pillar live and it can be caught again. Each opens with a
# long, wide corner so there is room to bail out, fly, and come back round.
const REATTACH_TRACKS := {
	26: {
		"lead_in": 640.0, "target_time": 10.4,
		"defs": [
			{"deg": 90, "r": 86, "reattach": true, "gap": 150},
			{"deg": -90, "r": 74, "reattach": true, "gap": 150},
			{"deg": 90, "r": 86, "reattach": true, "gap": 150},
			{"deg": -90, "r": 74},
			{"deg": 90, "r": 62},
		],
	},
	27: {
		"lead_in": 660.0, "target_time": 10.5,
		"defs": [
			{"deg": 180, "r": 88, "reattach": true, "gap": 170},
			{"deg": -90, "r": 74, "reattach": true, "gap": 150},
			{"deg": 90, "r": 74, "reattach": true, "gap": 150},
			{"deg": -90, "r": 62},
		],
	},
	28: {
		"lead_in": 640.0, "target_time": 10.6,
		"defs": [
			{"deg": 90, "r": 88, "reattach": true, "gap": 160},
			{"deg": 90, "r": 78, "reattach": true, "gap": 160},
			{"deg": -90, "r": 70, "reattach": true, "gap": 150},
			{"deg": -90, "r": 62},
			{"deg": 90, "r": 62},
		],
	},
}

# Every track number the game shows, in menu order: the ported time-attack tracks
# first, then the reattach showcase tracks. The numbers are their own, not their
# menu position, so removing tracks 6-20 leaves the kept tracks unshifted. Derived
# from the same tables as PLAYABLE_TRACKS, so the menu and the upload path cannot
# disagree about which tracks exist.
const FIRST_REATTACH_TRACK := 26
static var MENU_TRACKS := PLAYABLE_TRACKS

# Is `n` a track the menu offers? Guards the menu seed the same way the playable
# set guards the verifier.
static func is_menu_track(n: int) -> bool:
	return MENU_TRACKS.has(n)


# Turn an advanced track's defs into an op list, scaling the straights to time.
static func _advanced_ops(spec: Dictionary, radius: float) -> Array:
	var defs: Array = spec["defs"]
	var arc_len := 0.0
	var fixed_gaps := 0.0
	var weight_sum := 0.0
	for d in defs:
		arc_len += float(d.get("r", radius)) * abs(float(d["deg"])) * (PI / 180.0)
		fixed_gaps += float(d.get("gap", 0.0))
		weight_sum += float(d.get("scale", 1.0))
	var want := float(spec["target_time"]) * Cfg.SPEED + Cfg.SPEEDRUN_START_FRAC * float(spec["lead_in"])
	var fixed := float(spec["lead_in"]) + arc_len + fixed_gaps + 460.0
	var per := (want - fixed) / weight_sum if weight_sum > 0.0 else 0.0
	var ops := []
	for d in defs:
		var g := float(d.get("gap", 0.0)) + float(d.get("scale", 1.0)) * per
		if g > 1.0:
			ops.append({"t": "L", "len": g})
		ops.append({
			"t": "A", "deg": d["deg"], "r": float(d.get("r", radius)),
			"reattach": bool(d.get("reattach", false)),
		})
	return ops


static func _shape(n: int) -> Dictionary:
	var radius := 50.0 + float(n % 5) * 4.0
	var corners := 10
	var lead_in := 520.0 + float(n % 4) * 60.0
	var rhythm: Array = RHYTHMS[(n - 1) % RHYTHMS.size()]
	var target_time := 9.6 + float((n * 7) % 9) * 0.1
	return {
		"radius": radius, "corners": corners, "lead_in": lead_in,
		"rhythm": rhythm, "target_time": target_time,
	}


static func track_def(n: int) -> Dictionary:
	var sh := _shape(n)
	var radius: float = sh["radius"]
	var corners: int = sh["corners"]
	var lead_in: float = sh["lead_in"]
	var rhythm: Array = sh["rhythm"]
	var target_time: float = sh["target_time"]

	var arc := Cfg.TURN  # a quarter turn: r * PI/2, arc length uses abs(phi)
	var sum := 0
	for i in range(corners):
		sum += int(rhythm[i % rhythm.size()])

	var min_seg := 2.0 * radius + Cfg.MIN_STRAIGHT
	var max_seg := 2.0 * radius + MAX_VISIBLE_STRAIGHT
	var target_len := target_time * Cfg.SPEED + Cfg.SPEEDRUN_START_FRAC * lead_in
	var finish_len := 460.0
	var seg_sum := target_len - (lead_in - radius) - float(corners) * arc * radius - finish_len + 2.0 * radius * float(corners)
	var base := minf(maxf(seg_sum / float(sum), min_seg), max_seg)

	var seg_lens := []
	for i in range(corners):
		var val := base * float(rhythm[i % rhythm.size()])
		seg_lens.append(minf(maxf(val, min_seg), max_seg))

	return {
		"id": n, "seed": n, "radius": radius, "corners": corners,
		"lead_in": lead_in, "finish_len": finish_len, "seg_lens": seg_lens,
		"target_time": target_time,
	}


static func track_opts(n: int) -> Dictionary:
	var num := n
	if REATTACH_TRACKS.has(num):
		var spec: Dictionary = REATTACH_TRACKS[num]
		var radius := 70.0
		return {
			"corners": spec["defs"].size(),
			"radius": radius,
			"lead_in": spec["lead_in"],
			"finish_len": 460.0,
			"target_time": spec["target_time"],
			"ops": _advanced_ops(spec, radius),
		}
	if ADVANCED.has(num):
		var spec: Dictionary = ADVANCED[num]
		var radius := 62.0
		return {
			"corners": spec["defs"].size(),
			"radius": radius,
			"lead_in": spec["lead_in"],
			"finish_len": 460.0,
			"target_time": spec["target_time"],
			"ops": _advanced_ops(spec, radius),
		}
	var d := track_def(num)
	return {
		"corners": d["corners"],
		"radius": d["radius"],
		"lead_in": d["lead_in"],
		"finish_len": d["finish_len"],
		"seg_lens": d["seg_lens"],
		"target_time": d["target_time"],
	}
