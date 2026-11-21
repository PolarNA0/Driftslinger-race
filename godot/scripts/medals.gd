extends RefCounted
class_name Medals

# Per-track goals, derived from the track's own target time. The targets are
# deliberately loose enough that a clean line earns gold on every shipped track
# (verify_medals.gd drives one and asserts it): gold is 3% over target, silver
# 10%, bronze 20%. A custom track has no target, so it has no medals.
#
# Keep this a pure function of the track number. A medal is not stored; it is
# recomputed from the player's best, so a threshold change re-colours every
# historical PB instead of leaving a stale award behind.

const GOLD_MULT := 1.03
const SILVER_MULT := 1.10
const BRONZE_MULT := 1.20


static func thresholds(seed: int) -> Dictionary:
        if not Tracks.is_playable_track(seed):
                return {}
        var target := float(Tracks.track_opts(seed).get("target_time", 0.0))
        if target <= 0.0:
                return {}
        return {
                "gold": target * GOLD_MULT,
                "silver": target * SILVER_MULT,
                "bronze": target * BRONZE_MULT,
        }


static func medal_for(seed: int, time: float) -> String:
        var t := thresholds(seed)
        if t.is_empty():
                return ""
        if time <= float(t["gold"]):
                return "gold"
        if time <= float(t["silver"]):
                return "silver"
        if time <= float(t["bronze"]):
                return "bronze"
        return ""


static func label(medal: String) -> String:
        match medal:
                "gold": return "Gold medal"
                "silver": return "Silver medal"
                "bronze": return "Bronze medal"
                _: return ""


static func color(medal: String) -> Color:
        match medal:
                "gold": return UiTheme.MEDAL_GOLD
                "silver": return UiTheme.MEDAL_SILVER
                "bronze": return UiTheme.MEDAL_BRONZE
                _: return UiTheme.INK_DIM


static func summary() -> Dictionary:
        var counts := {"gold": 0, "silver": 0, "bronze": 0}
        for s in Tracks.MENU_TRACKS:
                var best: Variant = Storage.get_best_time(int(s))
                if best == null:
                        continue
                var medal := medal_for(int(s), float(best))
                if counts.has(medal):
                        counts[medal] += 1
        return counts


static func summary_text() -> String:
        var c := summary()
        return "%d gold  ·  %d silver  ·  %d bronze" % [c["gold"], c["silver"], c["bronze"]]
