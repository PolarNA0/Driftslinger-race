extends SceneTree

# Headless check: every track builds, and a clean line finishes it near its
# target time without leaving the road. Mirrors the JS suite's track loop.

func _init() -> void:
	var bad := 0
	for n in Tracks.MENU_TRACKS:
		var opts := Tracks.track_opts(n)
		var t := Track.new(n, opts)
		var car := Car.new()
		car.reset(t)
		var dt := 1.0 / 120.0
		var i := 0
		# The clean line: grab when the pole is in reach, hold until the arc is
		# carried all the way round, then let go. Same policy as the JS suite.
		while car.alive and not car.finished and i < 200000:
			i += 1
			var held := false
			if car.attached:
				held = car.remaining() > 0.0
			else:
				var f: Dictionary = t.fillets[car.corner]
				var c: Vector2 = f["c"]
				held = U.dist(c.x, c.y, car.x, car.y) <= Cfg.GRAB_RANGE
			car.step(dt, held)
		var clean := (t.finish_s - Cfg.SPEEDRUN_START_FRAC * t.lead_in) / Cfg.SPEED
		var ok := car.finished and car.time > 9.2 and car.time < 10.8 and car.max_off < Cfg.ROAD_HALF_WIDTH
		if not ok:
			bad += 1
		var has_re: bool = t.fillets.any(func(f): return f.get("reattach", false))
		print("track %2d: corners=%2d clean=%.3f finished=%s time=%.3f maxOff=%.2f grabbed=%d regrabs=%d reattach=%s %s"
			% [n, t.fillets.size(), clean, str(car.finished), car.time, car.max_off, car.grabbed, car.regrabs, str(has_re), "OK" if ok else "FAIL"])
	print("MENU_TRACKS=%d  bad=%d" % [Tracks.MENU_TRACKS.size(), bad])
	quit(1 if bad > 0 else 0)
