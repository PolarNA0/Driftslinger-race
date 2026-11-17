extends SceneTree

# Headless check of the endless board: one board, furthest distance wins.
#
# The endless board has no baked ghost field (a field exists to give a *time*
# board depth, and the endless board is short and real), so it is the real runs
# sorted, with a generated backdrop behind them so the board is not a handful of
# names over white space. What matters is that the merge is honest: a real run
# lands exactly where its distance says, the player's own rank agrees with the
# page they are drawn on, and paging is contiguous.

func _init() -> void:
        var ok := true

        # --- the backdrop is monotonic, so a rank found by search is the rank
        # --- a player sees.
        var prev := INF
        var mono := true
        for i in range(0, 2000, 7):
                var d := Leaderboard.endless_backdrop_dist(i)
                if d > prev + 1e-9:
                        mono = false
                prev = d
        print("backdrop monotonic: ", mono)
        ok = ok and mono

        # --- the world record is the furthest real run.
        var reals := [
                {"name": "Ash", "dist": 900.0, "steps": "01", "you": false},
                {"name": "Me", "dist": 1200.0, "steps": "10", "you": true},
                {"name": "Clover", "dist": 300.0, "steps": null, "you": false},
        ]
        var wr = Leaderboard.endless_world_record(reals)
        print("WR endless: ", JSON.stringify(wr))
        ok = ok and wr != null and str(wr["name"]) == "Me" and is_equal_approx(float(wr["dist"]), 1200.0)

        # --- the player is ranked by distance, and their rank matches the page
        # --- they are drawn on.
        var rank := Leaderboard.endless_rank(1200.0, reals)
        var page := Leaderboard.endless_page(1, {"name": "Me", "dist": 1200.0}, 50, reals)
        print("rank=%d player_rank=%d page=%d/%d total=%d" % [
                rank, int(page["player_rank"]), int(page["page"]), int(page["pages"]), int(page["total"])])
        ok = ok and rank == 1 and int(page["player_rank"]) == 1

        # The first row is the player, drawn once, and watchable (it has steps).
        var first: Dictionary = page["rows"][0]
        print("row0: ", JSON.stringify(first))
        ok = ok and bool(first["you"]) and str(first["name"]) == "Me" and bool(first["watchable"])

        # The second row is the next-furthest real run, not a duplicate.
        var second: Dictionary = page["rows"][1]
        ok = ok and str(second["name"]) == "Ash" and int(second["rank"]) == 2

        # --- a player not yet on the server board is slotted in locally, behind
        # --- the backdrop rows their distance has already beaten. `others` has no
        # --- "you" row, which is the case the local best exists to cover.
        var others := [
                {"name": "Ash", "dist": 900.0, "steps": "01", "you": false},
                {"name": "Clover", "dist": 300.0, "steps": null, "you": false},
        ]
        var mid_rank := Leaderboard.endless_rank(200.0, others)
        var mid_page := Leaderboard.endless_page(Leaderboard.page_for_rank(mid_rank), {"name": "Me", "dist": 200.0}, 50, others)
        var found := false
        var found_rank := -1
        for r in mid_page["rows"]:
                if bool((r as Dictionary).get("you", false)):
                        found = true
                        found_rank = int(r["rank"])
        print("short player rank=%d found=%s found_rank=%d page=%d" % [mid_rank, str(found), found_rank, int(mid_page["page"])])
        ok = ok and found and found_rank == mid_rank and mid_rank > 3

        # --- paging is contiguous: page N ends one rank before page N+1 begins.
        var p1 := Leaderboard.endless_page(1, null, 50, reals)
        var p2 := Leaderboard.endless_page(2, null, 50, reals)
        ok = ok and int(p1["rows"][49]["rank"]) == 50 and int(p2["rows"][0]["rank"]) == 51
        ok = ok and p1["rows"].size() == 50 and int(p1["pages"]) == int(p2["pages"])

        # --- no real run is drawn twice across the first two pages.
        var seen := {}
        var dup := 0
        for pg in [p1, p2]:
                for r in pg["rows"]:
                        var key := "%d:%s" % [int(r["rank"]), str(r["name"])]
                        if seen.has(key):
                                dup += 1
                        seen[key] = true
        print("duplicate rows across pages 1-2: ", dup)
        ok = ok and dup == 0

        print("RESULT: ", "PASS" if ok else "FAIL")
        quit(0 if ok else 1)
