extends SceneTree

# Headless check of the online layer's offline-testable parts.
#
# The board is real runs only, so what is checked here is the merge the client does
# with the server's rows: competition ranks, paging, and the local best that has
# not uploaded yet. The network paths cannot be exercised headlessly without a
# server, so the rest is everything that runs before a request goes out: the queue,
# the config, and the account rules that must hold with no session.

var ok := true


func check(label: String, got: Variant, want: Variant) -> void:
	var good := str(got) == str(want)
	ok = ok and good
	print("  %-46s %s   (got %s, want %s)" % [label, "ok " if good else "FAIL", str(got), str(want)])


func check_true(label: String, cond: bool) -> void:
	ok = ok and cond
	print("  %-46s %s" % [label, "ok " if cond else "FAIL"])


func _init() -> void:
	print("== the board is the real runs ==")
	var reals := [
		{"name": "Alpha", "time": 9.30, "steps": "1010", "you": false},
		{"name": "Beta", "time": 10.35, "steps": "1111", "you": false},
		{"name": "Gamma", "time": 13.90, "steps": "0001", "you": true},
	]

	var wr: Dictionary = Leaderboard.world_record(reals)
	check("world_record name", wr["name"], "Alpha")
	check("world_record time", wr["time"], 9.3)
	check("world_record real", wr["real"], true)
	check("world_record watchable", wr["watchable"], true)
	check("world_record steps", wr["steps"], "1010")

	var p1: Dictionary = Leaderboard.board_page(1, null, 50, reals)
	check("page1 total", p1["total"], 3)
	check("page1 pages", p1["pages"], 1)
	# [rank, name, real, you, watchable] for the three real runs.
	var want_rows := [[1, "Alpha", 1, 0, 1], [2, "Beta", 1, 0, 1], [3, "Gamma", 1, 1, 1]]
	var got_rows := []
	for r in p1["rows"]:
		got_rows.append([
			int(r["rank"]), str(r["name"]),
			1 if bool(r.get("real", false)) else 0,
			1 if bool(r.get("you", false)) else 0,
			1 if bool(r.get("watchable", false)) else 0,
		])
	check("page1 rows", JSON.stringify(got_rows), JSON.stringify(want_rows))

	# A local best that has not uploaded merges like anything else, and is not
	# duplicated when the server has already listed the player.
	var p2: Dictionary = Leaderboard.board_page(1, {"name": "Me", "time": 10.30}, 50, [])
	check("player-only rank", p2["player_rank"], 1)
	check("player-only row 1", str(p2["rows"][0]["name"]), "Me")
	check("player-only total", p2["total"], 1)

	var p3: Dictionary = Leaderboard.board_page(1, null, 50,
		[{"name": "Me", "time": 10.30, "steps": "11", "you": true}])
	check("listed rank", p3["player_rank"], 1)
	check("listed total", p3["total"], 1)

	# An empty board is a valid state, not a crash.
	var empty: Dictionary = Leaderboard.board_page(1)
	check("empty total", empty["total"], 0)
	check("empty pages", empty["pages"], 1)
	check("empty player_rank", empty["player_rank"], 0)
	check_true("empty world_record is null", Leaderboard.world_record([]) == null)

	print("== player rank counts only the real runs ==")
	# Reference: world record 9.30, t0 = 9.301.
	var t0 := 9.301
	var ahead := [
		{"name": "Cola", "time": 9.28},
		{"name": "Polar", "time": 9.29},
		{"name": "Alpha", "time": 9.30},
	]
	check("rank among the real runs", Leaderboard.player_rank(t0, reals), 2)
	check("three runs ahead push it down", Leaderboard.player_rank(t0, ahead), 4)
	var behind := [{"name": "Slow", "time": t0 + 5.0}]
	check("a run behind changes nothing", Leaderboard.player_rank(t0, behind), 1)
	# The two rankers have to agree on the same board.
	var merged: Dictionary = Leaderboard.board_page(1, {"name": "Me", "time": t0}, 50, ahead)
	check("player_rank agrees with board_page", Leaderboard.player_rank(t0, ahead), merged["player_rank"])

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
