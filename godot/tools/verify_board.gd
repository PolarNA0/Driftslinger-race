extends SceneTree

# Headless check of the leaderboard. The board is the real runs and nothing else:
# no baked ghost head and no generated tail. These cases pin the ranking rules -
# competition ranks, ties, paging, and the local best that has not uploaded yet.

var ok := true


func check(label: String, got: Variant, want: Variant) -> void:
	var good := str(got) == str(want)
	ok = ok and good
	print("  %-48s %s   (got %s, want %s)" % [label, "ok " if good else "FAIL", str(got), str(want)])


func _init() -> void:
	print("== empty board ==")
	var empty: Dictionary = Leaderboard.board_page(1)
	check("no rows", empty["rows"].size(), 0)
	check("total", empty["total"], 0)
	check("pages", empty["pages"], 1)
	check("player_rank", empty["player_rank"], 0)
	check("world_record null", Leaderboard.world_record([]) == null, true)

	print("== a small real board ==")
	# One run per player, the shape `_reals_for` hands in.
	var reals := [
		{"name": "Ash", "time": 10.0, "steps": "1010", "you": false},
		{"name": "Bolt", "time": 10.5, "steps": "1100", "you": false},
		{"name": "Cinder", "time": 11.0, "steps": null, "you": false},
	]
	var wr: Dictionary = Leaderboard.world_record(reals)
	check("world_record name", wr["name"], "Ash")
	check("world_record time", wr["time"], 10.0)
	check("world_record watchable", wr["watchable"], true)
	check("world_record steps", wr["steps"], "1010")

	check("rank of a slower run", Leaderboard.player_rank(10.2, reals), 2)
	check("rank tying the leader", Leaderboard.player_rank(10.0, reals), 1)
	check("rank behind everyone", Leaderboard.player_rank(12.0, reals), 4)

	var p: Dictionary = Leaderboard.board_page(1, null, 50, reals)
	check("board total", p["total"], 3)
	check("board pages", p["pages"], 1)
	var got := []
	for r in p["rows"]:
		got.append([int(r["rank"]), str(r["name"])])
	check("board rows", JSON.stringify(got), JSON.stringify([[1, "Ash"], [2, "Bolt"], [3, "Cinder"]]))
	check("no-steps row is not watchable", bool(p["rows"][2]["watchable"]), false)
	check("steps row is watchable", bool(p["rows"][0]["watchable"]), true)

	print("== ties share a rank ==")
	var tied := [
		{"name": "A", "time": 10.0, "steps": "1", "you": false},
		{"name": "B", "time": 10.0, "steps": "1", "you": false},
		{"name": "C", "time": 10.0, "steps": "1", "you": false},
		{"name": "D", "time": 10.5, "steps": "1", "you": false},
	]
	var pt: Dictionary = Leaderboard.board_page(1, null, 50, tied)
	var gott := []
	for r in pt["rows"]:
		gott.append(int(r["rank"]))
	check("three tied at 1, next at 4", JSON.stringify(gott), JSON.stringify([1, 1, 1, 4]))
	check("player_rank matches a tie", Leaderboard.player_rank(10.0, tied), 1)

	print("== a local best that has not uploaded ==")
	var me := {"name": "Me", "time": 10.2}
	var pm: Dictionary = Leaderboard.board_page(1, me, 50, reals)
	check("slotted in", pm["total"], 4)
	check("its rank", pm["player_rank"], 2)
	check("row 2 is Me", str(pm["rows"][1]["name"]), "Me")
	check("Me is not watchable", bool(pm["rows"][1]["watchable"]), false)

	# When the server already lists the player, they must not appear twice.
	var listed := [
		{"name": "Me", "time": 10.2, "steps": "11", "you": true},
		{"name": "Ash", "time": 10.0, "steps": "10", "you": false},
	]
	var pl: Dictionary = Leaderboard.board_page(1, me, 50, listed)
	check("listed player not duplicated", pl["total"], 2)
	check("listed player rank", pl["player_rank"], 2)

	print("== paging ==")
	var many := []
	for i in range(60):
		many.append({"name": "P%d" % i, "time": 10.0 + float(i) * 0.01, "steps": "1", "you": false})
	var page1: Dictionary = Leaderboard.board_page(1, null, 50, many)
	check("page 1 size", page1["rows"].size(), 50)
	check("page 1 pages", page1["pages"], 2)
	check("page 1 first rank", int(page1["rows"][0]["rank"]), 1)
	var page2: Dictionary = Leaderboard.board_page(2, null, 50, many)
	check("page 2 size", page2["rows"].size(), 10)
	check("page 2 first rank", int(page2["rows"][0]["rank"]), 51)
	check("page_for_rank(51)", Leaderboard.page_for_rank(51), 2)
	check("page_for_rank(1)", Leaderboard.page_for_rank(1), 1)
	# A page past the end clamps to the last page rather than returning nothing.
	var page9: Dictionary = Leaderboard.board_page(9, null, 50, many)
	check("page past the end clamps", page9["page"], 2)

	print("RESULT: ", "PASS" if ok else "FAIL")
	quit(0 if ok else 1)
