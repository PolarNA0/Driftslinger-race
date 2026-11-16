extends SceneTree

# Headless check of the online layer's offline-testable parts.
#
# The board merge is compared against reference values produced by the JS build's
# own `boardPage` (js/leaderboard.js) on the same inputs, so the port is checked
# number for number rather than against itself. The network paths cannot be
# exercised headlessly without a server, so what is checked here is everything
# that runs before a request goes out: the queue, the config, and the account
# rules that must hold with no session.

var ok := true


func check(label: String, got: Variant, want: Variant) -> void:
	var good := str(got) == str(want)
	ok = ok and good
	print("  %-46s %s   (got %s, want %s)" % [label, "ok " if good else "FAIL", str(got), str(want)])


func check_true(label: String, cond: bool) -> void:
	ok = ok and cond
	print("  %-46s %s" % [label, "ok " if cond else "FAIL"])


func _init() -> void:
	print("== board merge (reference: js/leaderboard.js) ==")
	# The same three real runs the JS reference was produced from: one faster than
	# the head, one tying the head's last real ghost, one slower than the field.
	var reals := [
		{"name": "Alpha", "time": 9.30, "steps": "1010", "you": false},
		{"name": "Beta", "time": 10.35, "steps": "1111", "you": false},
		{"name": "Gamma", "time": 13.90, "steps": "0001", "you": true},
	]

	check("ghosts_beaten 9.30", Leaderboard.ghosts_beaten(1, 9.30), 0)
	check("ghosts_beaten 10.35", Leaderboard.ghosts_beaten(1, 10.35), 2)
	check("ghosts_beaten 13.90", Leaderboard.ghosts_beaten(1, 13.90), 50000)

	var wr: Dictionary = Leaderboard.world_record(1, reals)
	check("world_record name", wr["name"], "Alpha")
	check("world_record time", wr["time"], 9.3)
	check("world_record real", wr["real"], true)
	check("world_record watchable", wr["watchable"], true)
	check("world_record steps", wr["steps"], "1010")

	var p1: Dictionary = Leaderboard.board_page(1, 1, null, 50, reals)
	check("page1 total", p1["total"], 50003)
	check("page1 pages", p1["pages"], 1001)
	check("page1 player_rank", p1["player_rank"], 50003)
	check("page1 real_count", p1["real_count"], 3)
	# [rank, name, real, you, watchable] for the rows JS produced.
	var want_rows := [
		[1, "Alpha", 1, 0, 1], [2, "Ash-8", 0, 0, 1], [3, "Clover", 0, 0, 1],
		[4, "Beta", 1, 0, 1], [5, "Dash.", 0, 0, 1], [12, "Mist", 0, 0, 1],
		[13, "Sable58", 0, 0, 0], [16, "Marble", 0, 0, 0],
	]
	var got_rows := []
	for i in [0, 1, 2, 3, 4, 11, 12, 15]:
		var r: Dictionary = p1["rows"][i]
		got_rows.append([
			int(r["rank"]), str(r["name"]),
			1 if bool(r.get("real", false)) else 0,
			1 if bool(r.get("you", false)) else 0,
			1 if bool(r.get("watchable", false)) else 0,
		])
	check("page1 rows at 1,2,3,4,5,12,13,16", JSON.stringify(got_rows), JSON.stringify(want_rows))

	var last: Dictionary = Leaderboard.board_page(1, 1001, null, 50, reals)
	check("last page number", last["page"], 1001)
	var got_last := []
	for r in last["rows"]:
		got_last.append([int(r["rank"]), str(r["name"]), 1 if bool(r.get("real", false)) else 0])
	check("last page rows", JSON.stringify(got_last),
		JSON.stringify([[50001, "Quill.42", 0], [50002, "Flint", 0], [50003, "Gamma", 1]]))

	# A local best that has not uploaded merges like anything else, and is not
	# duplicated when the server has already listed the player.
	var p2: Dictionary = Leaderboard.board_page(1, 1, {"name": "Me", "time": 10.30}, 50, [])
	check("player-only rank", p2["player_rank"], 1)
	check("player-only row 1", str(p2["rows"][0]["name"]), "Me")
	check("player-only row 2", str(p2["rows"][1]["name"]), "Ash-8")
	check("player-only total", p2["total"], 50001)

	var p3: Dictionary = Leaderboard.board_page(1, 1, null, 50,
		[{"name": "Me", "time": 10.30, "steps": "11", "you": true}])
	check("listed rank", p3["player_rank"], 1)
	check("listed total", p3["total"], 50001)

	# The unchanged board must still match the old reference values. With nobody
	# handed in, the field is just the 50,000 ghosts.
	check("no-reals total", Leaderboard.board_page(1, 1)["total"], 50000)
	check("no-reals pages", Leaderboard.board_page(1, 1)["pages"], 1000)
	check("no-reals player_rank", Leaderboard.board_page(1, 1)["player_rank"], 0)

	print("== player rank counts the real runs (reference: js/leaderboard.js) ==")
	# Ignoring the real runs ranks a player among the baked ghosts alone, which is a
	# place they do not hold. Reference values come from the JS `playerRank` on the
	# same inputs: world record 10.35, t0 = 10.351.
	var wr0: Dictionary = Leaderboard.world_record(1, [])
	check("reference world record", wr0["time"], 10.35)
	var t0 := float(wr0["time"]) + 0.001
	var ahead := [
		{"name": "Cola", "time": float(wr0["time"]) - 0.02},
		{"name": "Polar", "time": float(wr0["time"]) - 0.01},
		{"name": "Ash-8", "time": float(wr0["time"])},
	]
	check("rank among ghosts alone", Leaderboard.player_rank(1, t0), 3)
	check("three runs ahead push it down", Leaderboard.player_rank(1, t0, ahead), 6)
	var behind := [{"name": "Slow", "time": t0 + 5.0}]
	check("a run behind changes nothing", Leaderboard.player_rank(1, t0, behind), 3)
	var only_one := [{"name": "Polar", "time": float(wr0["time"]) - 0.01}]
	check("second behind one real run", Leaderboard.player_rank(1, float(wr0["time"]) - 0.001, only_one), 2)
	# The two rankers have to agree on the same merged board.
	var merged: Dictionary = Leaderboard.board_page(1, 1, {"name": "Me", "time": t0}, 50, ahead)
	check("player_rank agrees with board_page", Leaderboard.player_rank(1, t0, ahead), merged["player_rank"])

	print("== run queue (offline) ==")
	_clear_queue()
	check("starts empty", Api.queue_length(), 0)
	Api.enqueue(3, "1010", "Me")
	check("one queued", Api.queue_length(), 1)
	Api.enqueue(3, "1010", "Me")
	check("identical run not queued twice", Api.queue_length(), 1)
	Api.enqueue(4, "0101", "Me")
	check("a different run is queued", Api.queue_length(), 2)
	# The oldest-first order is what flush relies on.
	var q := Api.read_queue()
	check("oldest first", int(q[0]["track"]), 3)
	check("newest last", int(q[1]["track"]), 4)
	check("entry carries its steps", str(q[0]["steps"]), "1010")

	for i in range(80):
		Api.enqueue(i + 1, "1", "Me")
	check("queue is capped at 50", Api.queue_length(), 50)
	_clear_queue()
	check("cleared", Api.queue_length(), 0)

	print("== client id ==")
	var id1 := Api.client_id()
	var id2 := Api.client_id()
	check_true("stable across calls", id1 == id2 and id1.length() == 32)

	print("== account rules with no session ==")
	# These must all hold before anything touches the network, so a signed-out
	# player never depends on a request.
	check("current_account is empty", Account.current_account(), "")
	check("current_user_id is empty", Account.current_user_id(), "")
	check("current_email is empty", Account.current_email(), "")
	check("signed_in is false", Account.signed_in(), false)
	check("validate_name short", Account.validate_name("ab"), "Username needs at least 3 characters.")
	check("validate_name long", Account.validate_name("abcdefghijklmnopq"), "Username is at most 16 characters.")
	check("validate_name charset", Account.validate_name("bad name!"), "Letters, numbers, _ . - only.")
	check("validate_name good", Account.validate_name("DriftKing_9"), "")

	print("== net config ==")
	check_true("configured", NetConfig.configured())
	check_true("url has no trailing slash", not NetConfig.url().ends_with("/"))
	check_true("anon key present", NetConfig.anon_key().length() > 40)
	check("function endpoint", NetConfig.function_endpoint("board"),
		"%s/functions/v1/board" % NetConfig.url())

	print("RESULT: ", "PASS" if ok else "FAIL")
	quit(0 if ok else 1)


func _clear_queue() -> void:
	var path := "user://slingdrift.queue.v2.json"
	if FileAccess.file_exists(path):
		DirAccess.remove_absolute(ProjectSettings.globalize_path(path))
