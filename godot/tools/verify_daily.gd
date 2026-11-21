extends SceneTree

# Headless check for the daily challenge: the date picks the same road on every
# device, each modifier still drives, and a day's result is a different seed
# from the next day's rather than an overwrite.

var bad := 0


func _check(ok: bool, what: String) -> void:
        if ok:
                print("ok    %s" % what)
        else:
                bad += 1
                print("FAIL  %s" % what)


func _clean_line(t: Track) -> Car:
        var car := Car.new()
        car.reset(t)
        var dt := 1.0 / 120.0
        var i := 0
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
        return car


func _daily_track(track: int, modifier: String) -> Track:
        return Track.new(Daily.seed_for("2026-11-21"), Daily.opts({
                "track": track, "modifier": modifier,
        }))


func _init() -> void:
        # --- the same date is the same challenge ----------------------------
        var a := Daily.challenge_for("2026-11-21")
        var b := Daily.challenge_for("2026-11-21")
        _check(a == b, "a date picks the same challenge twice")
        _check(int(a["seed"]) == Daily.seed_for("2026-11-21"), "the challenge carries its own seed")
        _check(Daily.date_for_seed(int(a["seed"])) == "2026-11-21", "a seed maps back to its date")
        _check(Tracks.MENU_TRACKS.has(int(a["track"])), "the daily track is in the menu")
        _check(Daily.is_daily(int(a["seed"])), "the daily seed is recognised as daily")
        _check(not Daily.is_daily(1) and not Daily.is_daily(28) and not Daily.is_daily(1000), "built-in and custom ids are not daily")
        _check(not Daily.is_daily(Daily.BASE - 1) and not Daily.is_daily(Daily.BASE + Daily.SPAN), "the daily range has hard edges")

        # --- different dates move around ------------------------------------
        var tracks := {}
        var mods := {}
        for day in range(1, 31):
                var date := "2026-11-%02d" % day
                var ch := Daily.challenge_for(date)
                tracks[int(ch["track"])] = true
                mods[str(ch["modifier"])] = true
                _check(Daily.date_for_seed(int(ch["seed"])) == date, "%s round-trips through its seed" % date)
        _check(tracks.size() > 1, "a month does not repeat one track")
        _check(mods.size() > 1, "a month does not repeat one modifier")
        _check(mods.has("mirror"), "mirror is part of the rotation")

        # --- every modifier drives on every track ---------------------------
        var driven := 0
        for n in Tracks.MENU_TRACKS:
                var mods_here := ["none", "mirror"]
                if int(n) >= Tracks.FIRST_REATTACH_TRACK:
                        mods_here.append("no_reattach")
                for mod in mods_here:
                        var t := _daily_track(int(n), mod)
                        var car := _clean_line(t)
                        var ok := car.finished and car.time > 9.0 and car.time < 11.0 and car.max_off < Cfg.ROAD_HALF_WIDTH
                        if not ok:
                                bad += 1
                                print("FAIL  track %d / %s: finished=%s time=%.3f maxOff=%.2f" % [
                                        n, mod, str(car.finished), car.time, car.max_off])
                        driven += 1
        _check(bad == 0, "all %d daily variants finish on a clean line" % driven)

        # --- mirror really mirrors ------------------------------------------
        for n in [1, 21, 26]:
                var normal := Track.new(int(n), Tracks.track_opts(int(n)))
                var flipped := _daily_track(int(n), "mirror")
                var same_count := normal.fillets.size() == flipped.fillets.size()
                var opposite := true
                for k in range(mini(normal.fillets.size(), flipped.fillets.size())):
                        var fn: Dictionary = normal.fillets[k]
                        var ff: Dictionary = flipped.fillets[k]
                        if absf(float(fn["r"]) - float(ff["r"])) > 0.01 or absf(float(fn["phi"]) + float(ff["phi"])) > 0.001:
                                opposite = false
                _check(same_count and opposite, "track %d mirrors every corner" % n)
                _check(absf(normal.finish_s - flipped.finish_s) < 0.01, "track %d keeps its length when mirrored" % n)

        # --- no_reattach strips the pillars ---------------------------------
        var re := Track.new(26, Tracks.track_opts(26))
        var plain := _daily_track(26, "no_reattach")
        var had := re.fillets.any(func(f): return bool(f.get("reattach", false)))
        var none := not plain.fillets.any(func(f): return bool(f.get("reattach", false)))
        _check(had and none, "no_reattach removes every reattach pillar")

        # --- yesterday's result is a different seed --------------------------
        var d1 := Daily.seed_for("2026-11-20")
        var d2 := Daily.seed_for("2026-11-21")
        _check(d1 != d2, "two dates are two seeds")
        var times_snapshot: Variant = Storage._read("times.v1", {})
        var tries_snapshot: Variant = Storage._read("attempts.v1", {})
        Storage.save_best_time(d1, 10.5)
        Storage.save_best_time(d2, 11.5)
        _check(float(Storage.get_best_time(d1)) == 10.5, "yesterday's best survives today's")
        _check(float(Storage.get_best_time(d2)) == 11.5, "today's best is stored under today")
        Storage.add_attempt(d1)
        Storage.add_attempt(d1)
        Storage.add_attempt(d2)
        _check(Storage.get_attempts(d1) == 2 and Storage.get_attempts(d2) == 1, "attempts are per date")
        Storage._write("times.v1", times_snapshot)
        Storage._write("attempts.v1", tries_snapshot)

        print("DAILY %s" % ("PASS" if bad == 0 else "FAIL (%d)" % bad))
        quit(1 if bad > 0 else 0)
