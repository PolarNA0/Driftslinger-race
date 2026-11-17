extends RefCounted
class_name Leaderboard

# The board is the real runs, and nothing else.
#
# There is no baked field and no generated tail. A row is on the board because a
# player finished a run and the server verified it, or because this device holds a
# local best that has not uploaded yet. Every row can be watched: a real run
# carries its own button steps, so there is no ghost id to regenerate from.
#
# An empty board is honest. A board padded with invented racers ranks a player
# against ghosts of nobody, which is worse than an empty list.

const PER_PAGE := 50


# The player's 1-based rank among the real runs, or 0 when there is no time.
#
# A run counts as ahead only when it is strictly faster, so two runs on the same
# time share a rank. This is the same rule `board_page` reports, so the rank on
# the finish card and the rank on the board never disagree.
static func player_rank(time: float, reals: Array = []) -> int:
	if is_nan(time) or is_inf(time):
		return 0
	var ahead := 0
	for r in reals:
		var rt := float((r as Dictionary).get("time", INF))
		if not (is_nan(rt) or is_inf(rt)) and rt < time:
			ahead += 1
	return ahead + 1


# The world record: the fastest real run, or null when the board is empty. A run
# with no steps still ranks; it just cannot be watched.
static func world_record(reals: Array = []) -> Variant:
	var sorted := reals.duplicate()
	sorted.sort_custom(func(a, b): return float(a["time"]) < float(b["time"]))
	if sorted.is_empty():
		return null
	var r: Dictionary = sorted[0]
	var steps: Variant = r.get("steps")
	return {
		"rank": 1, "name": str(r["name"]), "time": float(r["time"]),
		"steps": steps, "real": true,
		"watchable": steps != null and str(steps) != "",
	}


# The page that holds rank `rank`.
static func page_for_rank(rank: int, per_page: int = PER_PAGE) -> int:
	return maxi(1, int(ceil(float(rank) / float(per_page))))


# One page of the board.
#
# `reals` are the real runs on the track as {name, time, steps, you} in any order;
# they are sorted here. `player` is {name, time} for the signed-in account, handed
# in only when the server has not already listed them, so a local best that has not
# uploaded still ranks rather than vanishing from the board.
#
# Sorting is by time alone and Godot's sort is stable, so two runs on the same time
# keep the order they arrived in. Ranks are competition ranks: tied runs share a
# place, matching `player_rank`.
static func board_page(page: int, player: Variant = null, per_page: int = PER_PAGE, reals: Array = []) -> Dictionary:
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

	var total := all.size()
	var pages := maxi(1, int(ceil(float(total) / float(per_page))))
	var p2 := clampi(page, 1, pages)

	# Competition ranks over the sorted field: a tied run keeps the earlier rank.
	var ranks := []
	var my_rank := 0
	var i := 0
	while i < total:
		var j := i
		while j < total and float(all[j]["time"]) == float(all[i]["time"]):
			j += 1
		for k in range(i, j):
			ranks.append(i + 1)
			if bool(all[k].get("you", false)):
				my_rank = i + 1
		i = j

	var start := (p2 - 1) * per_page
	var out := []
	for idx in range(start, mini(start + per_page, total)):
		var r: Dictionary = all[idx]
		var steps: Variant = r.get("steps")
		out.append({
			"rank": int(ranks[idx]), "name": str(r["name"]), "time": float(r["time"]),
			"real": true, "you": bool(r.get("you", false)),
			"steps": steps,
			"watchable": steps != null and str(steps) != "",
		})

	return {
		"rows": out, "page": p2, "pages": pages, "total": total,
		"player_rank": my_rank, "real_count": total,
	}
