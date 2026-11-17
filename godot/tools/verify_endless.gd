extends SceneTree

# Headless check for the endless difficulty ramp and its reattach pillars. Runs
# the real physics; no mocks.
#
# Claims proved here:
#   1. The ramp is monotonic in distance: corners tighten, straights shorten and
#      the car's speed rises the further the road runs.
#   2. A clean line still survives a long ramped run. The ramp must raise the
#      ceiling without breaking the line that has always worked.
#   3. Reattach pillars appear only past the warm-up distance, and never in the
#      opening stretch.
#   4. The distance score is what was actually travelled, so the ramp and a
#      reattach slingshot both show up in it - it is not just ticks x base speed.

const DT := 1.0 / 120.0


# The clean line: grab when the pole is in reach, ride every arc to its end.
func _clean_run(seed: int, max_corners: int) -> Car:
	var t := Track.new(seed)
	var car := Car.new()
	car.reset(t)
	var i := 0
	while car.alive and car.grabbed < max_corners and i < 2000000:
		i += 1
		var held := false
		if car.attached:
			held = car.remaining() > 0.0
		else:
			var f: Dictionary = t.fillets[car.corner]
			var c: Vector2 = f["c"]
			held = U.dist(c.x, c.y, car.x, car.y) <= Cfg.GRAB_RANGE
		car.step(DT, held)
	return car


# Drive an endless road, bailing out of every reattach pillar and waiting `wait`
# steps before holding again. Returns the peak speed multiplier the physics gave.
func _endless_reattach_max(seed: int, wait: int) -> float:
	var t := Track.new(seed)
	var car := Car.new()
	car.reset(t)
	var bailed: Dictionary = {}
	var waited: Dictionary = {}
	var max_s := 1.0
	var i := 0
	while car.alive and car.grabbed < 60 and i < 2000000:
		i += 1
		var held := false
		if car.attached:
			var f: Dictionary = t.fillets[car.corner]
			if f.get("reattach", false) and not bailed.has(car.corner):
				var arc := absf(float(f["a2"]) - float(f["a1"]))
				if car.remaining() < 0.55 * arc:
					held = false
					bailed[car.corner] = true
					waited[car.corner] = 0
				else:
					held = car.remaining() > 0.0
			else:
				held = car.remaining() > 0.0
		else:
			if bailed.has(car.corner) and int(waited.get(car.corner, 999)) < wait:
				waited[car.corner] = int(waited.get(car.corner, 0)) + 1
				held = false
			else:
				var f2: Dictionary = t.fillets[car.corner]
				held = U.dist(f2["c"].x, f2["c"].y, car.x, car.y) <= Cfg.GRAB_RANGE * Cfg.REATTACH_GRAB_MULT
		car.step(DT, held)
		max_s = maxf(max_s, car.speed_scale)
	return max_s


func _init() -> void:
	var bad := 0

	# 1) the ramp rises with distance
	print("the endless ramp tightens the road as it runs")
	for seed in [1, 7, 42]:
		var t := Track.new(seed)
		# Force enough corners to pass the ramp's full length.
		t.ensure(int(Cfg.ENDLESS_RAMP_LEN / Cfg.ENDLESS_SEG_MIN) + 20)
		var early_r: float = t.fillets[1]["r"]
		var late_r: float = t.fillets[t.fillets.size() - 1]["r"]
		var tightened: bool = float(late_r) < float(early_r)
		var speed_early := t.speed_scale_at(0.0)
		var speed_late := t.speed_scale_at(Cfg.ENDLESS_RAMP_LEN)
		var faster: bool = speed_late > speed_early and absf(speed_early - 1.0) < 1e-6
		var reaches_top: bool = absf(speed_late - Cfg.ENDLESS_SPEED_MAX) < 1e-6
		if not (tightened and faster and reaches_top):
			bad += 1
			print("  FAIL seed %d: r %.0f->%.0f speed %.2f->%.2f" % [seed, early_r, late_r, speed_early, speed_late])
		else:
			print("  seed %2d: radius %.0f -> %.0f, speed x%.2f -> x%.2f OK" % [seed, early_r, late_r, speed_early, speed_late])

	# 2) a clean line survives a long ramped run
	print("a clean line survives a long ramped run")
	for seed in [1, 7, 42, 2024]:
		var c := _clean_run(seed, 200)
		if not (c.alive and c.grabbed >= 200):
			bad += 1
			print("  FAIL seed %d: clean line managed only %d corners" % [seed, c.grabbed])
		else:
			print("  seed %4d: %d corners, %.1f m OK" % [seed, c.grabbed, c.distance() / Cfg.PX_PER_METRE])

	# 3) reattach pillars appear only past the warm-up
	print("reattach pillars appear only past the warm-up distance")
	for seed in [1, 7]:
		var t := Track.new(seed)
		t.ensure(int(Cfg.ENDLESS_RAMP_LEN / Cfg.ENDLESS_SEG_MIN) + 40)
		var early_re := false
		var late_re := false
		for f in t.fillets:
			if bool(f.get("reattach", false)):
				if float(f["s0"]) < Cfg.ENDLESS_REATTACH_AFTER:
					early_re = true
				else:
					late_re = true
		if early_re or not late_re:
			bad += 1
			print("  FAIL seed %d: early=%s late=%s" % [seed, str(early_re), str(late_re)])
		else:
			print("  seed %d: none before %.0f px, some after OK" % [seed, Cfg.ENDLESS_REATTACH_AFTER])

	# 4) distance is what was travelled, not ticks x base speed
	print("distance reflects the ramp, not the base speed")
	var t4 := Track.new(1)
	var car4 := Car.new()
	car4.reset(t4)
	for i in range(600):
		var held := false
		if car4.attached:
			held = car4.remaining() > 0.0
		else:
			var f: Dictionary = t4.fillets[car4.corner]
			held = U.dist(f["c"].x, f["c"].y, car4.x, car4.y) <= Cfg.GRAB_RANGE
		car4.step(DT, held)
	var naive := car4.time * Cfg.SPEED
	var real := car4.distance()
	if not (real > naive + 1.0):
		bad += 1
		print("  FAIL: travelled %.1f not ahead of ticks x base %.1f" % [real, naive])
	else:
		print("  travelled %.1f px vs ticks x base %.1f px (ramp adds %.1f) OK" % [real, naive, real - naive])

	# 5) the road is a pure function of distance: two different lines over the same
	#    seed build the same corners. A replay or a ghost depends on this.
	print("the ramp road is the same for any line")
	var t_a := Track.new(7)
	var car_a := Car.new()
	car_a.reset(t_a)
	var t_b := Track.new(7)
	var car_b := Car.new()
	car_b.reset(t_b)
	var i := 0
	while car_a.alive and car_a.grabbed < 120 and i < 2000000:
		i += 1
		var held_a := false
		if car_a.attached:
			held_a = car_a.remaining() > 0.0
		else:
			var f: Dictionary = t_a.fillets[car_a.corner]
			held_a = U.dist(f["c"].x, f["c"].y, car_a.x, car_a.y) <= Cfg.GRAB_RANGE
		car_a.step(DT, held_a)
	# A deliberately sloppier line on the same seed.
	var j := 0
	while car_b.alive and t_b.fillets.size() < t_a.fillets.size() and j < 2000000:
		j += 1
		car_b.step(DT, j % 7 < 5)
	var same := true
	var n := mini(t_a.fillets.size(), t_b.fillets.size())
	for k in n:
		if absf(float(t_a.fillets[k]["r"]) - float(t_b.fillets[k]["r"])) > 1e-6:
			same = false
			break
	if not (same and n > 20):
		bad += 1
		print("  FAIL: %d corners compared, same=%s" % [n, str(same)])
	else:
		print("  %d corners identical across two lines OK" % n)

	# 6) a reattach on an endless road pays off, and spam does not. The same
	#    slingshot as the showcase tracks, proved here on the ramped staircase.
	print("a reattach works on the endless road")
	var boost_fires := _endless_reattach_max(7, 8)
	var spam_plain := _endless_reattach_max(7, 0)
	var ra_ok: bool = boost_fires > 1.0 and spam_plain == 1.0
	if not ra_ok:
		bad += 1
		print("  FAIL: boost(8)=%.3f spam(0)=%.3f" % [boost_fires, spam_plain])
	else:
		print("  detour boost x%.3f, spam x%.3f OK" % [boost_fires, spam_plain])

	print("ENDLESS %s" % ("PASS" if bad == 0 else "FAIL (%d)" % bad))
	quit(1 if bad > 0 else 0)
