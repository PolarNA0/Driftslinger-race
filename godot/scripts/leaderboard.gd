extends RefCounted
class_name Leaderboard

# Port of js/leaderboard.js. The head of the board is real (js/ghostdata.js, baked)
# and watchable; the tail is generated from a formula and is a backdrop to rank
# against. The player is slotted in by time, so their rank is real.

const PER_PAGE := 50
const FIELD := 50000


static func REAL(n: int) -> Array:
	return GhostData.GHOSTS.get(n, [])


static func GEN(n: int) -> int:
	return FIELD - REAL(n).size()


static func tail_span(n: int) -> float:
	var head := REAL(n)
	if head.is_empty():
		return 1.0
	var wr: float = head[0][0]
	return maxf(1.6, wr * 0.2)


# Time of generated row `i` (0-based) on track `n`. Monotonic in `i`, so the whole
# board stays sorted and a rank found by binary search is the rank a player sees.
static func gen_time(n: int, i: int) -> float:
	var head := REAL(n)
	var base := 10.0
	if not head.is_empty():
		base = float(head[head.size() - 1][0])
	var span := tail_span(n)
	var frac := float(i + 1) / float(GEN(n))
	return base + span * pow(frac, 1.35)


static func gen_name(n: int, i: int) -> String:
	var h := U.imul32(i + 7919, 2654435761) & 0xFFFFFFFF
	var g := U.imul32(n + 13, 0x9e3779b1) & 0xFFFFFFFF
	return GhostRun.ghost_name(h ^ g)


# Racers on track `n` no slower than `time` (ties included).
static func ghosts_beaten(n: int, time: float) -> int:
	if is_nan(time) or is_inf(time):
		return 0
	var head := REAL(n)
	if head.is_empty() or time <= float(head[head.size() - 1][0]):
		var lo := 0
		var hi := head.size()
		while lo < hi:
			var m := (lo + hi) >> 1
			if float(head[m][0]) <= time:
				lo = m + 1
			else:
				hi = m
		return lo
	# Past the head, so every real row counts and the tail is a binary search.
	var lo2 := 0
	var hi2 := GEN(n)
	while lo2 < hi2:
		var m2 := (lo2 + hi2) >> 1
		if gen_time(n, m2) <= time:
			lo2 = m2 + 1
		else:
			hi2 = m2
	return head.size() + lo2


# The player's 1-based rank among the field, or 0 when there is no time.
static func player_rank(n: int, time: float) -> int:
	if is_nan(time) or is_inf(time):
		return 0
	return ghosts_beaten(n, time) + 1


static func ghost_count() -> int:
	return FIELD


static func page_for_rank(rank: int, per_page: int = PER_PAGE) -> int:
	return maxi(1, int(ceil(float(rank) / float(per_page))))


# The world record: the fastest real run, and the way to watch it.
static func world_record(n: int) -> Variant:
	var head := REAL(n)
	if head.is_empty():
		return null
	return {"rank": 1, "name": head[0][2], "time": head[0][0], "ghost_id": head[0][1], "watchable": true}


# The ghost at ghost-index `gi` (0-based, head first then generated).
static func ghost_at(n: int, gi: int) -> Dictionary:
	var head := REAL(n)
	if gi < head.size():
		var row: Array = head[gi]
		return {"name": row[2], "time": row[0], "ghost_id": row[1], "watchable": true}
	var i := gi - head.size()
	return {"name": gen_name(n, i), "time": gen_time(n, i), "ghost_id": -1, "watchable": false}


# One page of the board. `player` is {name, time} or null.
static func board_page(n: int, page: int, player: Variant = null, per_page: int = PER_PAGE) -> Dictionary:
	var total := FIELD + (1 if player != null else 0)
	var pages := maxi(1, int(ceil(float(total) / float(per_page))))
	var p := clampi(page, 1, pages)
	var player_pos := -1
	if player != null:
		player_pos = ghosts_beaten(n, float(player["time"]))

	var start := (p - 1) * per_page
	var out := []
	var pos := start
	while pos < mini(start + per_page, total):
		if player != null and pos == player_pos:
			out.append({
				"rank": pos + 1, "name": player["name"], "time": player["time"],
				"you": true, "ghost_id": -1, "watchable": false,
			})
		else:
			var gi := pos - 1 if (player != null and pos > player_pos) else pos
			var row := ghost_at(n, gi)
			row["rank"] = pos + 1
			row["you"] = false
			out.append(row)
		pos += 1
	return {
		"rows": out, "page": p, "pages": pages, "total": total,
		"player_rank": player_pos + 1 if player != null else 0,
	}
