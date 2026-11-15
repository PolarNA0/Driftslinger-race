extends SceneTree

# Headless check that the Godot leaderboard matches the JS build number for
# number. Reference values come from tools/_lb.mjs in the JS repo.

func _init() -> void:
	var ok := true
	var wr = Leaderboard.world_record(1)
	print("WR1 ", JSON.stringify(wr))
	ok = ok and int(wr["ghost_id"]) == 746 and is_equal_approx(float(wr["time"]), 10.35)

	var ranks := {10.0: 1, 10.35: 3, 10.5: 6869, 11.0: 21005, 12.5: 50001}
	for t in ranks:
		var r := Leaderboard.player_rank(1, t)
		print("rank1 t=%s -> %d (want %d)" % [str(t), r, ranks[t]])
		ok = ok and r == int(ranks[t])

	var p := Leaderboard.board_page(1, 1, {"name": "Me", "time": 10.3})
	print("page1 playerRank=%d pages=%d total=%d" % [p["player_rank"], p["pages"], p["total"]])
	ok = ok and int(p["player_rank"]) == 1 and int(p["pages"]) == 1001 and int(p["total"]) == 50001
	var names := []
	for i in range(4):
		names.append(p["rows"][i]["name"])
	print("  head rows: ", ", ".join(names))
	ok = ok and names[0] == "Me" and names[1] == "Ash-8" and names[3] == "Dash."

	var last := Leaderboard.board_page(1, 1000)
	print("last page %d of %d rows=%d first=%s" % [last["page"], last["pages"], last["rows"].size(), JSON.stringify(last["rows"][0])])
	ok = ok and int(last["page"]) == 1000 and last["rows"].size() == 50
	ok = ok and int(last["rows"][0]["rank"]) == 49951 and last["rows"][0]["name"] == "DriftKing-"
	ok = ok and abs(float(last["rows"][0]["time"]) - 12.425561312127801) < 1e-9

	var gen2 := []
	var plain := Leaderboard.board_page(1, 1)
	for i in range(10, 14):
		gen2.append(plain["rows"][i]["name"])
	print("  gen rows 10-13: ", ", ".join(gen2))
	ok = ok and gen2[0] == "Sable58" and gen2[1] == "Snap" and gen2[2] == "Kestrel" and gen2[3] == "Marble"

	print("RESULT: ", "PASS" if ok else "FAIL")
	quit(0 if ok else 1)
