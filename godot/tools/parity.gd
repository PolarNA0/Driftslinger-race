extends SceneTree

# Headless parity check for the physics.
#
# This used to compare against `tools/_parity.mjs` in the JS build, live. That JS
# build has since been removed, so the JS numbers are frozen here as golden
# values, recorded from the JS `Car.step` before it was deleted (the scripted
# input is the same: hold and release in 0.35s phases on track 1).
#
# The port runs in 32-bit floats where the JS ran in 64-bit doubles, so the
# comparison is a tolerance, not an exact match. The tolerances are tight enough
# that a real physics change fails them and float noise does not.

# Recorded from js/car.js + js/track.js, track 1, trackOpts(1), dt = 1/120.
const WANT_STEPS := 334
const WANT_TIME := 2.783333333333326
const WANT_X := 657.803119682678
const WANT_Y := -278.8598768516045
const WANT_ANGLE := 5.652742761315502
const WANT_OFF := 46.88287849852895
const WANT_GRABBED := 2

# A 32-bit float has ~7 significant digits, so this is the noise floor, not a
# fudge factor.
const TOL := 1e-4


func _init() -> void:
        var opts := Tracks.track_opts(1)
        var t := Track.new(1, opts)
        var car := Car.new()
        car.reset(t)
        var dt := Cfg.DT
        var steps := 0
        while car.alive and not car.finished and steps < 12000:
                var phase := int(floor(float(steps) * dt / 0.35)) % 2 == 0
                car.step(dt, phase)
                steps += 1

        var checks := [
                ["steps", float(steps), float(WANT_STEPS)],
                ["time", car.time, WANT_TIME],
                ["x", car.x, WANT_X],
                ["y", car.y, WANT_Y],
                ["angle", car.angle, WANT_ANGLE],
                ["off", car.off, WANT_OFF],
                ["grabbed", float(car.grabbed), float(WANT_GRABBED)],
        ]
        var bad := 0
        for c: Array in checks:
                var got: float = c[1]
                var want: float = c[2]
                var ok: bool = absf(got - want) <= TOL * maxf(1.0, absf(want))
                if not ok:
                        bad += 1
                print("  %-8s got=%.6f want=%.6f %s" % [c[0], got, want, "ok" if ok else "FAIL"])
        var dead_ok: bool = not car.finished and car.dead == "wall"
        if not dead_ok:
                bad += 1
        print("  finished=%s dead=%s %s" % [str(car.finished), str(car.dead), "ok" if dead_ok else "FAIL"])
        print("PARITY %s" % ("PASS" if bad == 0 else "FAIL (%d)" % bad))
        quit(1 if bad > 0 else 0)
