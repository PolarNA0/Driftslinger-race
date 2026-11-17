extends SceneTree

# Headless check for the one rule that matters: holding or mashing must never
# beat the game. Ported from the JS suite so the rule is proved against the
# Godot physics, which is the build players actually run.
#
# Claims proved here:
#   1. A cleanly-timed line survives a long run.
#   2. Holding forever crashes within a couple of corners.
#   3. Every mash pattern (alternating, 3-on/3-off, 5-on/1-off) dies within ~3.
#   4. Releasing up to ~15 degrees early still finishes.

# A representative spread rather than every seed the JS suite used: a clean
# 120-corner run is a couple of seconds of real simulation, so the seed list is
# kept short enough that the whole guard stays a quick regression check.
const SEEDS := [1, 2, 3, 7, 42, 2024]
const RUN := 120          # corners a good run should manage
const DT := 1.0 / 120.0


# The clean line: grab when the pole is in reach, hold until the arc end, release
# `deg` degrees early.
func _timing(car: Car, deg: float) -> bool:
        if car.attached:
                return car.remaining() > deg * PI / 180.0
        var f: Dictionary = car.track.fillets[car.corner]
        var c: Vector2 = f["c"]
        return U.dist(c.x, c.y, car.x, car.y) <= Cfg.GRAB_RANGE


func _run(seed: int, policy: Callable, max_c: int) -> Car:
        var t := Track.new(seed)
        var car := Car.new()
        car.reset(t)
        var i := 0
        while car.alive and car.grabbed < max_c and i < 600000:
                i += 1
                car.step(DT, policy.call(car, i))
        return car


func _median(a: Array) -> int:
        var s := a.duplicate()
        s.sort()
        return int(s[s.size() / 2])


func _init() -> void:
        var bad := 0

        print("a clean line survives a long run")
        for seed in SEEDS:
                var c := _run(seed, func(car, _i): return _timing(car, 0.0), RUN)
                if not (c.alive and c.grabbed >= RUN):
                        bad += 1
                        print("  FAIL: seed %d clean line managed only %d corners" % [seed, c.grabbed])

        print("holding past the corner ends in the wall")
        for seed in SEEDS:
                var c := _run(seed, func(_car, _i): return true, RUN)
                if c.alive:
                        bad += 1
                        print("  FAIL: seed %d holding forever never crashed" % seed)
                if c.grabbed > 2:
                        bad += 1
                        print("  FAIL: seed %d holding forever got %d corners" % [seed, c.grabbed])

        print("mashing cannot beat the game")
        var patterns := {
                "mash": func(_car, i): return i % 2 == 0,
                "mash 3on3off": func(_car, i): return i % 6 < 3,
                "mash 5on1off": func(_car, i): return i % 6 < 5,
        }
        for seed in SEEDS:
                for name in patterns:
                        var c := _run(seed, patterns[name], 40)
                        if c.grabbed > 3:
                                bad += 1
                                print("  FAIL: seed %d %s got %d corners" % [seed, name, c.grabbed])

        # The reattach flag must not open a cheese either. A live reattach pillar can
        # be caught again on the approach, so a mash pattern racks up re-grabs - but
        # it must never carry the car to the finish, on any showcase track.
        print("holding or mashing cannot finish a reattach track")
        for n in [Tracks.FIRST_REATTACH_TRACK, Tracks.FIRST_REATTACH_TRACK + 1, Tracks.FIRST_REATTACH_TRACK + 2]:
                var policies := {
                        "hold": func(_car, _i): return true,
                        "mash": func(_car, i): return i % 2 == 0,
                        "mash 5on1off": func(_car, i): return i % 6 < 5,
                }
                for name in policies:
                        var t := Track.new(n, Tracks.track_opts(n))
                        var car := Car.new()
                        car.reset(t)
                        var i := 0
                        while car.alive and not car.finished and i < 600000:
                                i += 1
                                car.step(DT, policies[name].call(car, i))
                        if car.finished:
                                bad += 1
                                print("  FAIL: track %d %s finished (grabbed=%d regrabs=%d)" % [n, name, car.grabbed, car.regrabs])

        print("release timing is forgiving")
        for deg in [0, 5, 10, 15]:
                var got := []
                for seed in SEEDS:
                        got.append(_run(seed, func(car, _i): return _timing(car, float(deg)), RUN).grabbed)
                if _median(got) < RUN:
                        bad += 1
                        print("  FAIL: releasing %ddeg early only managed %d corners" % [deg, _median(got)])

        print("GUARD %s" % ("PASS" if bad == 0 else "FAIL (%d)" % bad))
        quit(1 if bad > 0 else 0)
