extends RefCounted
class_name Leaderboard

# The board: the head is real (scripts/ghostdata.gd, baked by tools/bake_ghosts.gd)
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
#
# `reals` are the other real runs on the track. They have to be counted: the ghost
# field is only the backdrop, and a real run slots into it by time, so counting
# ghosts alone reports a place the player does not hold. This is the same merged
# board `board_page` draws, so the two never disagree.
static func player_rank(n: int, time: float, reals: Array = []) -> int:
	if is_nan(time) or is_inf(time):
		return 0
	var ahead := 0
	for r in reals:
		var rt := float((r as Dictionary).get("time", INF))
		if not (is_nan(rt) or is_inf(rt)) and rt < time:
			ahead += 1
	return ghosts_beaten(n, time) + ahead + 1


static func ghost_count() -> int:
	return FIELD


static func page_for_rank(rank: int, per_page: int = PER_PAGE) -> int:
	return maxi(1, int(ceil(float(rank) / float(per_page))))


# The world record: the fastest real run if there is one, else the baked head.
#
# A real submitted run beats a baked ghost, so the board's record follows the
# players as soon as one goes faster. The record can then be watched from its
# stored steps rather than a ghost id, which is why it carries `steps`.
static func world_record(n: int, reals: Array = []) -> Variant:
	var sorted := reals.duplicate()
	sorted.sort_custom(func(a, b): return float(a["time"]) < float(b["time"]))
	if sorted.size() > 0:
		var r: Dictionary = sorted[0]
		var steps: Variant = r.get("steps")
		return {
			"rank": 1, "name": str(r["name"]), "time": float(r["time"]),
			"ghost_id": -1, "steps": steps, "real": true,
			"watchable": steps != null and str(steps) != "",
		}
	var head := REAL(n)
	if head.is_empty():
		return null
	return {
		"rank": 1, "name": head[0][2], "time": head[0][0],
		"ghost_id": head[0][1], "steps": null, "real": false, "watchable": true,
	}


# The ghost at ghost-index `gi` (0-based, head first then generated).
static func ghost_at(n: int, gi: int) -> Dictionary:
	var head := REAL(n)
	if gi < head.size():
		var row: Array = head[gi]
		return {"name": row[2], "time": row[0], "ghost_id": row[1], "watchable": true}
	var i := gi - head.size()
	return {"name": gen_name(n, i), "time": gen_time(n, i), "ghost_id": -1, "watchable": false}


# One page of the board, with real runs merged into the ghost field.
#
# There is one board, not two. The ghost field is the backdrop and a real
# submitted run is slotted into it by time, so a fast real run lands high and a
# slow one lands deep - both against the same field, and both ranked honestly.
# A real row carries `real: true`, which is what the UI turns into the green dot;
# the ghost rows around it are untouched.
#
# `reals` are the real runs on this track as {name, time, steps, you} in any
# order; they are sorted here. `player` is {name, time} for the signed-in
# account, used only when the server has not listed them, so their rank and page
# are still right.
#
# This is a merge of two sorted lists, and the merge has to be exact: a real run
# displaces the ghosts it beats, so a run slower than the whole field lands after
# all of them rather than partway up it. Ranks are merged positions, so a rank on
# the board is the rank the player sees. A real run tying a ghost sorts after it.
static func board_page(n: int, page: int, player: Variant = null, per_page: int = PER_PAGE, reals: Array = []) -> Dictionary:
	# The signed-in player is just another real run, so a local best that has not
	# uploaded yet merges by time like everything else rather than being special-cased.
	var all := []
	for r in reals:
		all.append((r as Dictionary).duplicate())
	if player != null:
		var listed := false
		for r in all:
			if bool(r.get("you", false)):
				listed = true
				break
		if not listed:
			var p: Dictionary = (player as Dictionary).duplicate()
			p["you"] = true
			p["steps"] = null
			all.append(p)
	all.sort_custom(func(a, b): return float(a["time"]) < float(b["time"]))

	var total := FIELD + all.size()
	var pages := maxi(1, int(ceil(float(total) / float(per_page))))
	var p2 := clampi(page, 1, pages)

	# Ghosts each real run beats or ties, in real-run order. Non-decreasing because
	# `all` is sorted by time, and left unadjusted: two runs on the same time
	# simply take the two adjacent slots. A real run ties *after* the ghosts it
	# matches, so this is the same count `player_rank` uses and the two never
	# disagree.
	var beaten := []
	for r in all:
		beaten.append(ghosts_beaten(n, float(r["time"])))

	# Real run k sits after the ghosts it beat *and* the k real runs already placed.
	var real_at := {}
	for k in range(all.size()):
		real_at[int(beaten[k]) + k] = all[k]

	var my_index := -1
	for k in range(all.size()):
		if bool(all[k].get("you", false)):
			my_index = k
			break
	var player_rank_here := 0 if my_index < 0 else int(beaten[my_index]) + my_index + 1

	var start := (p2 - 1) * per_page
	var out := []
	var pos := start
	while pos < mini(start + per_page, total):
		if real_at.has(pos):
			var r: Dictionary = real_at[pos]
			var steps: Variant = r.get("steps")
			out.append({
				"rank": pos + 1, "name": str(r["name"]), "time": float(r["time"]),
				"real": true, "you": bool(r.get("you", false)),
				"steps": steps, "ghost_id": -1,
				"watchable": steps != null and str(steps) != "",
			})
			pos += 1
			continue
		# Ghost index: gi + pushedBy(gi) == pos, and that is strictly increasing in
		# gi, so it inverts with a binary search.
		var lo := 0
		var hi := FIELD
		while lo < hi:
			var m := (lo + hi) >> 1
			if m + _pushed_by(beaten, m) < pos:
				lo = m + 1
			else:
				hi = m
		var row := ghost_at(n, lo)
		row["rank"] = pos + 1
		row["you"] = false
		out.append(row)
		pos += 1

	return {
		"rows": out, "page": p2, "pages": pages, "total": total,
		"player_rank": player_rank_here, "real_count": all.size(),
	}


# =============================================================================
# Endless: one board, furthest distance wins
# =============================================================================
#
# Endless is one road, so there is one board, and it ranks the other way round
# from a track board: more distance is better. There is no baked ghost field to
# merge into - a ghost field exists to give a *time* board depth, and the endless
# board is short and real - so this board is simply the real runs, sorted. The
# player is slotted in by distance, so their rank is real.

const ENDLESS_BACKDROP := 50000


# A generated endless row, so the board has a field to sit in rather than a
# handful of names and a lot of white space. It is the same idea as a track
# board's tail: a monotonic curve *behind* the real rows. A track board's tail is
# slower than its real head; here "behind" means shorter, because more distance
# wins, so the curve runs from a modest maximum down to a bare opening straight.
# A run longer than the maximum is therefore at the very top of the board, and a
# weak run is honestly buried in the field.
static func endless_backdrop_dist(i: int) -> float:
	var frac := float(i + 1) / float(ENDLESS_BACKDROP)
	return 10.0 + 290.0 * pow(1.0 - frac, 1.6)


static func endless_backdrop_name(i: int) -> String:
	var h := U.imul32(i + 104729, 2654435761) & 0xFFFFFFFF
	return GhostRun.ghost_name(h)


# The world record distance: the furthest real run, or null when the board is
# empty. Endless has no baked head, so an empty board has no record to show.
static func endless_world_record(reals: Array = []) -> Variant:
	if reals.is_empty():
		return null
	var best: Dictionary = reals[0]
	for r in reals:
		var row: Dictionary = r
		if float(row.get("dist", 0.0)) > float(best.get("dist", 0.0)):
			best = row
	return {
		"rank": 1, "name": str(best["name"]), "dist": float(best["dist"]),
		"steps": best.get("steps"), "real": true,
		"watchable": best.get("steps") != null and str(best.get("steps")) != "",
	}


# Racers no shorter than `dist` (ties included).
static func endless_beaten(dist: float) -> int:
	if is_nan(dist) or is_inf(dist) or dist <= 0.0:
		return 0
	var lo := 0
	var hi := ENDLESS_BACKDROP
	while lo < hi:
		var m := (lo + hi) >> 1
		if endless_backdrop_dist(m) >= dist:
			lo = m + 1
		else:
			hi = m
	return lo


# The player's 1-based rank, or 0 when there is no distance. Same merged count
# `endless_page` draws, so the two never disagree.
static func endless_rank(dist: float, reals: Array = []) -> int:
	if is_nan(dist) or is_inf(dist) or dist <= 0.0:
		return 0
	var ahead := 0
	for r in reals:
		var rd := float((r as Dictionary).get("dist", 0.0))
		if not (is_nan(rd) or is_inf(rd)) and rd > dist:
			ahead += 1
	return endless_beaten(dist) + ahead + 1


# One page of the endless board, with the signed-in player slotted in by
# distance. `reals` are {name, dist, steps, you}; `player` is {name, dist} for a
# local best the server has not listed yet.
static func endless_page(page: int, player: Variant = null, per_page: int = PER_PAGE, reals: Array = []) -> Dictionary:
	var all := []
	for r in reals:
		all.append((r as Dictionary).duplicate())
	if player != null:
		var listed := false
		for r in all:
			if bool(r.get("you", false)):
				listed = true
				break
		if not listed:
			var p: Dictionary = (player as Dictionary).duplicate()
			p["you"] = true
			p["steps"] = null
			all.append(p)
	all.sort_custom(func(a, b): return float(a["dist"]) > float(b["dist"]))

	var total := ENDLESS_BACKDROP + all.size()
	var pages := maxi(1, int(ceil(float(total) / float(per_page))))
	var p2 := clampi(page, 1, pages)

	# Backdrop rows each real run beats or ties, in real-run order.
	var beaten := []
	for r in all:
		beaten.append(endless_beaten(float(r["dist"])))

	# Real run k sits after the backdrop rows it beat *and* the k real runs
	# already placed. Higher distance sorts first, so this is a descending
	# merge - the same shape as the track board, mirrored.
	var real_at := {}
	for k in range(all.size()):
		real_at[int(beaten[k]) + k] = all[k]

	var my_index := -1
	for k in range(all.size()):
		if bool(all[k].get("you", false)):
			my_index = k
			break
	var player_rank_here := 0 if my_index < 0 else int(beaten[my_index]) + my_index + 1

	var start := (p2 - 1) * per_page
	var out := []
	var pos := start
	while pos < mini(start + per_page, total):
		if real_at.has(pos):
			var r: Dictionary = real_at[pos]
			var steps: Variant = r.get("steps")
			out.append({
				"rank": pos + 1, "name": str(r["name"]), "dist": float(r["dist"]),
				"real": true, "you": bool(r.get("you", false)),
				"steps": steps,
				"watchable": steps != null and str(steps) != "",
			})
			pos += 1
			continue
		# Backdrop index: gi + pushedBy(gi) == pos, strictly increasing in gi.
		var lo := 0
		var hi := ENDLESS_BACKDROP
		while lo < hi:
			var m := (lo + hi) >> 1
			if m + _pushed_by(beaten, m) < pos:
				lo = m + 1
			else:
				hi = m
		out.append({
			"rank": pos + 1, "name": endless_backdrop_name(lo),
			"dist": endless_backdrop_dist(lo), "real": false, "you": false,
			"steps": null, "watchable": false,
		})
		pos += 1

	return {
		"rows": out, "page": p2, "pages": pages, "total": total,
		"player_rank": player_rank_here, "real_count": all.size(),
	}


# How many real runs were inserted at or before ghost index `gi`.
static func _pushed_by(beaten: Array, gi: int) -> int:
	var lo := 0
	var hi := beaten.size()
	while lo < hi:
		var m := (lo + hi) >> 1
		if int(beaten[m]) <= gi:
			lo = m + 1
		else:
			hi = m
	return lo
