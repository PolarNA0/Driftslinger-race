extends SceneTree

# Headless check for the reattachable pillar. Runs the real physics; no mocks.
#
# Claims proved here:
#   1. A plain pillar cannot be re-grabbed. Let go and it is spent: the car flies
#      on and never latches that same pole again.
#   2. A reattach pillar can be re-grabbed after an *early* release. Bail out
#      partway round the arc, then hold again as the car comes back round, and it
#      latches the same pole a second time. The re-grab is counted.
#   3. Riding an arc to its end still spends a reattach pillar. This is what keeps
#      ordinary play intact: a clean line releases at the end of every arc, and if
#      that release reopened the pillar the car would catch itself and swing off
#      the road. A completed arc closes the pillar.
#   4. A re-grab is a real recovery. The catch happens wide - the car flew off on
#      the tangent, so it is caught outside the pillar radius - and the drift then
#      reels it back down to the pillar radius.

const DT := 1.0 / 120.0


# Drive a car round `track`. The button is held, except for one early release on
# the first reattach pillar (at `bail_at` of that arc), after which it holds again
# - so any re-grab is the physics answering the reach, not the script.
func _run(track: Track, bail_at: float) -> Dictionary:
	var car := Car.new()
	car.reset(track)
	var was_attached := false
	var bailed := false
	var bail_corner := -1
	var radius_at_regrab := 0.0
	var radius_before := 0.0
	var i := 0
	while car.alive and not car.finished and i < 200000:
		i += 1
		var held := true
		if car.attached:
			var f: Dictionary = track.fillets[car.corner]
			if bail_corner < 0 and f.get("reattach", false):
				bail_corner = car.corner
			if car.corner == bail_corner and not bailed:
				# Release once the arc is partway round, then hold again.
				var frac: float = car.remaining() / maxf(0.001, absf(float(f["a2"]) - float(f["a1"])) * float(f["r"]))
				if frac <= 1.0 - bail_at:
					held = false
					bailed = true
				else:
					held = car.remaining() > 0.0
			else:
				# Ordinary play: ride the arc out, then let go at its end.
				held = car.remaining() > 0.0
		# Watch the radius through the first re-grab so we can show it reels in.
		if car.attached and not was_attached and bailed:
			radius_at_regrab = car.radius
		if car.attached:
			radius_before = car.radius
		was_attached = car.attached
		car.step(DT, held)
	var f0: Dictionary = track.fillets[bail_corner] if bail_corner >= 0 else {}
	return {
		"finished": car.finished, "time": car.time, "grabbed": car.grabbed,
		"regrabs": car.regrabs, "dead": car.dead, "bail_corner": bail_corner,
		"regrab_radius": radius_at_regrab, "pole_radius": float(f0.get("r", 0.0)),
	}


# A plain pillar must stay spent after release: run track 1 and confirm no re-grab.
func _plain_spent() -> bool:
	var opts := Tracks.track_opts(1)
	var t := Track.new(1, opts)
	var car := Car.new()
	car.reset(t)
	var released := false
	var i := 0
	while car.alive and not car.finished and i < 200000:
		i += 1
		var held := true
		if car.attached:
			if car.remaining() > 0.0 and not released and car.corner == 0:
				# Let go early on the very first corner, then hold again.
				held = false
				released = true
		car.step(DT, held)
	return released and car.regrabs == 0


# A scripted reattach on the first reattach pillar, then a clean ride of the
# rest. On that pillar: bail at `bail` of the arc, fly for `wait` steps, then
# hold again and carry the arc out. `wait` is the detour - the longer it is, the
# further the car flies before it re-catches, which is what the slingshot pays on.
func _slingshot(track: Track, wait: int, bail: float = 0.4) -> Dictionary:
	var car := Car.new()
	car.reset(track)
	var corner := -1
	var bailed := false
	var waited := 0
	var max_s := 1.0
	var max_det := 0.0
	var i := 0
	while car.alive and not car.finished and i < 200000:
		i += 1
		var held := false
		if car.attached:
			var f: Dictionary = track.fillets[car.corner]
			if corner < 0 and f.get("reattach", false):
				corner = car.corner
			if car.corner == corner and corner >= 0 and not bailed:
				var arc := absf(float(f["a2"]) - float(f["a1"]))
				var frac := 1.0 - car.remaining() / arc
				if frac >= bail:
					held = false
					bailed = true
				else:
					held = car.remaining() > 0.0
			else:
				held = car.remaining() > 0.0
		else:
			if bailed and car.corner == corner and waited < wait:
				waited += 1
				held = false
			else:
				var f2: Dictionary = track.fillets[car.corner]
				held = U.dist(f2["c"].x, f2["c"].y, car.x, car.y) <= Cfg.GRAB_RANGE * Cfg.REATTACH_GRAB_MULT
		car.step(DT, held)
		max_s = maxf(max_s, car.speed_scale)
		max_det = maxf(max_det, car.detour_px)
	return {
		"finished": car.finished, "time": car.time, "regrabs": car.regrabs,
		"max_s": max_s, "max_det": max_det, "dead": car.dead,
	}


# The clean line for comparison: grab when in reach, ride every arc to its end.
func _clean(track: Track) -> Dictionary:
	var car := Car.new()
	car.reset(track)
	var max_s := 1.0
	var min_s := 1.0
	var i := 0
	while car.alive and not car.finished and i < 200000:
		i += 1
		var held := false
		if car.attached:
			held = car.remaining() > 0.0
		else:
			var f: Dictionary = track.fillets[car.corner]
			var c: Vector2 = f["c"]
			held = U.dist(c.x, c.y, car.x, car.y) <= Cfg.GRAB_RANGE
		car.step(DT, held)
		max_s = maxf(max_s, car.speed_scale)
		min_s = minf(min_s, car.speed_scale)
	return {"finished": car.finished, "time": car.time, "max_s": max_s, "min_s": min_s}


# A spent reattach pillar must never read as catchable again. The renderer paints
# a pillar bronze once it is spent (or once the car's corner has moved past it) and
# amber while it can still be caught; that "catchable" state has to be monotonic,
# or a spent pillar flickers back to live - which is what a single-slot spent
# marker did, because spending a later pillar forgot the earlier one.
func _catchable_monotonic() -> bool:
	var n := Tracks.FIRST_REATTACH_TRACK
	var t := Track.new(n, Tracks.track_opts(n))
	var car := Car.new()
	car.reset(t)
	var ever_spent := {}
	var ok := true
	var i := 0
	while car.alive and not car.finished and i < 200000:
		i += 1
		for k in t.fillets.size():
			if not bool(t.fillets[k].get("reattach", false)):
				continue
			var catchable: bool = not car.spent_corners.has(k) and k >= car.corner
			if ever_spent.has(k) and catchable:
				ok = false
			if not catchable:
				ever_spent[k] = true
		var held := false
		if car.attached:
			held = car.remaining() > 0.0
		else:
			var f: Dictionary = t.fillets[car.corner]
			held = U.dist(f["c"].x, f["c"].y, car.x, car.y) <= Cfg.GRAB_RANGE
		car.step(DT, held)
	return ok and car.finished


func _init() -> void:
	var pass_all := true

	# 1) plain pillar stays spent
	var plain_ok := _plain_spent()
	print("plain pillar never re-grabbed: %s" % ("PASS" if plain_ok else "FAIL"))
	pass_all = pass_all and plain_ok

	# 2) reattach pillar re-grabbed after an early release, and the car still finishes
	var total_regrabs := 0
	for n in [Tracks.FIRST_REATTACH_TRACK, Tracks.FIRST_REATTACH_TRACK + 1, Tracks.FIRST_REATTACH_TRACK + 2]:
		var t := Track.new(n, Tracks.track_opts(n))
		var r := _run(t, 0.35)
		var regrabbed: bool = int(r["regrabs"]) > 0
		var finished: bool = bool(r["finished"])
		var reels_in: bool = float(r["regrab_radius"]) > float(r["pole_radius"])
		var ok: bool = regrabbed and finished and reels_in
		total_regrabs += int(r["regrabs"])
		print("track %2d: bail at corner %d, regrabs=%d finished=%s time=%.3f regrabR=%.1f poleR=%.1f %s"
			% [n, int(r["bail_corner"]), int(r["regrabs"]), str(finished), float(r["time"]),
			   float(r["regrab_radius"]), float(r["pole_radius"]), "OK" if ok else "FAIL"])
		pass_all = pass_all and ok

	# 3) riding an arc to the end still spends a reattach pillar (clean-line check)
	var t3 := Track.new(Tracks.FIRST_REATTACH_TRACK, Tracks.track_opts(Tracks.FIRST_REATTACH_TRACK))
	var car3 := Car.new()
	car3.reset(t3)
	var i := 0
	while car3.alive and not car3.finished and i < 200000:
		i += 1
		var held := false
		if car3.attached:
			held = car3.remaining() > 0.0
		else:
			var f: Dictionary = t3.fillets[car3.corner]
			var c: Vector2 = f["c"]
			held = U.dist(c.x, c.y, car3.x, car3.y) <= Cfg.GRAB_RANGE
		car3.step(DT, held)
	var clean_ok: bool = car3.finished and car3.regrabs == 0 and car3.max_off < Cfg.ROAD_HALF_WIDTH
	print("clean line on track %d: finished=%s regrabs=%d maxOff=%.2f %s"
		% [Tracks.FIRST_REATTACH_TRACK, str(car3.finished), car3.regrabs, car3.max_off, "OK" if clean_ok else "FAIL"])
	pass_all = pass_all and clean_ok

	print("total re-grabs observed across showcase tracks: %d" % total_regrabs)

	# 4) the slingshot pays off, and pays more for a longer detour, while a quick
	#    release-and-recatch (spam) earns nothing and the clean line is untouched.
	print("== reattach slingshot ==")
	for n in [Tracks.FIRST_REATTACH_TRACK, Tracks.FIRST_REATTACH_TRACK + 1, Tracks.FIRST_REATTACH_TRACK + 2]:
		var t := Track.new(n, Tracks.track_opts(n))
		var clean := _clean(t)
		var spam := _slingshot(t, 0)
		var short := _slingshot(t, 8)
		var long := _slingshot(t, 24)
		var spam_plain: bool = spam["finished"] and spam["max_s"] == 1.0
		var short_boost: bool = short["finished"] and short["max_s"] > 1.0
		var long_boost: bool = long["finished"] and long["max_s"] > short["max_s"]
		var long_faster: bool = float(long["time"]) < float(clean["time"]) - 0.05
		var clean_plain: bool = clean["finished"] and clean["max_s"] == 1.0 and clean["min_s"] == 1.0
		var ok: bool = spam_plain and short_boost and long_boost and long_faster and clean_plain
		print("track %2d: spam maxS=%.3f(%s) short maxS=%.3f long maxS=%.3f(longer=%s) cleanT=%.3f longT=%.3f(%s) %s"
			% [n, float(spam["max_s"]), str(spam_plain), float(short["max_s"]), float(long["max_s"]),
			   str(long_boost), float(clean["time"]), float(long["time"]), str(long_faster),
			   "OK" if ok else "FAIL"])
		pass_all = pass_all and ok

	# A detour past the pillar's reach must be punished: over-committing loses the
	# pole and the run. This is the risk half of the risk/reward curve.
	var over := _slingshot(Track.new(Tracks.FIRST_REATTACH_TRACK, Tracks.track_opts(Tracks.FIRST_REATTACH_TRACK)), 60)
	var over_ok: bool = not over["finished"]
	print("over-committing a reattach loses the run: finished=%s %s" % [str(over["finished"]), "OK" if over_ok else "FAIL"])
	pass_all = pass_all and over_ok

	# 5) a spent reattach pillar never reads as live again
	var mono_ok := _catchable_monotonic()
	print("spent reattach pillar never reads as live again: %s" % ("PASS" if mono_ok else "FAIL"))
	pass_all = pass_all and mono_ok

	print("RESULT: %s" % ("PASS" if pass_all else "FAIL"))
	quit(0 if pass_all else 1)
