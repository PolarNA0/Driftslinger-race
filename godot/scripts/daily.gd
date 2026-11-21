extends RefCounted
class_name Daily

# The daily challenge: one track, one modifier, the same for everyone on the same
# UTC date. It is local-only - a modifier is not the built-in track, so the run is
# never uploaded and never ranked.
#
# The date is turned into a seed so the existing per-seed stores (best time,
# history, replay) work unchanged and yesterday's result is a different seed
# rather than an overwrite. `Track` is told the real track number as its
# `shape_seed`, so a daily on track 1 is the real track 1 (or its mirror), not a
# different road that happens to share a number.
#
# Determinism is the whole feature: the same date must pick the same track and
# modifier on every device. `String.hash()` is stable across runs and platforms,
# and the date is UTC, so time zones cannot disagree.

# Far above the built-in numbers (1-28) and the custom id range (1000+).
const BASE := 900_000_000
# About 273 years of dates. A seed outside this window is not a daily.
const SPAN := 100_000

const MODIFIERS := ["none", "mirror"]

static func today() -> Dictionary:
        return challenge_for(Time.get_date_string_from_system(true))


static func challenge_for(date: String) -> Dictionary:
        var h := ("slingdrift-daily-v1:" + date).hash() & 0x7fffffff
        var tracks: Array = Tracks.MENU_TRACKS
        var track := int(tracks[h % tracks.size()])
        # `no_reattach` only changes a road that has reattach pillars, so it is not
        # offered on the tracks where it would be a no-op.
        var mods := MODIFIERS.duplicate()
        if track >= Tracks.FIRST_REATTACH_TRACK:
                mods.append("no_reattach")
        var modifier: String = mods[int(h / tracks.size()) % mods.size()]
        return {
                "date": date,
                "track": track,
                "modifier": modifier,
                "seed": seed_for(date),
        }


static func challenge_for_seed(seed: int) -> Dictionary:
        return challenge_for(date_for_seed(seed))


static func is_daily(seed: int) -> bool:
        return seed >= BASE and seed < BASE + SPAN


static func seed_for(date: String) -> int:
        var unix := int(Time.get_unix_time_from_datetime_string(date + "T00:00:00"))
        return BASE + int(floor(float(unix) / 86400.0))


static func date_for_seed(seed: int) -> String:
        return Time.get_date_string_from_unix_time((seed - BASE) * 86400)


static func modifier_label(modifier: String) -> String:
        match modifier:
                "mirror":
                        return "Mirror"
                "no_reattach":
                        return "No reattach"
                _:
                        return "Standard"


static func summary(ch: Dictionary) -> String:
        return "Track %d \u00b7 %s" % [int(ch["track"]), modifier_label(str(ch["modifier"]))]


# The `Track` opts for a challenge. A custom op-list track keeps its own arcs; a
# staircase track keeps its real shape seed and only flips its first turn when
# mirrored.
static func opts(ch: Dictionary) -> Dictionary:
        var o: Dictionary = Tracks.track_opts(int(ch["track"]))
        o["shape_seed"] = int(ch["track"])
        if str(ch["modifier"]) == "mirror":
                o["mirror"] = true
        elif str(ch["modifier"]) == "no_reattach":
                o["no_reattach"] = true
        return o
