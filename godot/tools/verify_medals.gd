extends SceneTree

# Headless check for the per-track medals. The thresholds must be ordered and a
# pure function of the track number, a clean line must earn gold on every shipped
# track, and a time past bronze (or a custom track, which has no target) must
# earn nothing.

func _init() -> void:
        var bad := 0
        for n in Tracks.MENU_TRACKS:
                var t := Medals.thresholds(n)
                var ordered := not t.is_empty() \
                        and float(t["gold"]) < float(t["silver"]) \
                        and float(t["silver"]) < float(t["bronze"])
                var deterministic := t == Medals.thresholds(n)
                if not (ordered and deterministic):
                        bad += 1
                        print("track %2d: thresholds FAIL %s" % [n, str(t)])
                        continue

                var track := Track.new(n, Tracks.track_opts(n))
                var car := Car.new()
                car.reset(track)
                var dt := 1.0 / 120.0
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
                        car.step(dt, held)

                var medal := Medals.medal_for(n, car.time)
                var ok := car.finished and medal == "gold"
                if not ok:
                        bad += 1
                print("track %2d: gold<=%.3f silver<=%.3f bronze<=%.3f clean=%.3f medal=%-6s %s"
                        % [n, t["gold"], t["silver"], t["bronze"], car.time, medal, "OK" if ok else "FAIL"])

        # The boundaries: exactly on a threshold earns it, a hair past the last
        # threshold earns nothing, and a custom id has no target at all.
        var first := int(Tracks.MENU_TRACKS[0])
        var t1 := Medals.thresholds(first)
        if Medals.medal_for(first, float(t1["gold"])) != "gold":
                bad += 1
                print("boundary: exactly gold is not gold")
        if Medals.medal_for(first, float(t1["gold"]) + 0.001) != "silver":
                bad += 1
                print("boundary: just past gold is not silver")
        if Medals.medal_for(first, float(t1["bronze"]) + 0.001) != "":
                bad += 1
                print("boundary: past bronze still earns a medal")
        if Medals.medal_for(1000, 1.0) != "":
                bad += 1
                print("custom track earned a medal")

        print("MENU_TRACKS=%d  bad=%d" % [Tracks.MENU_TRACKS.size(), bad])
        quit(1 if bad > 0 else 0)
