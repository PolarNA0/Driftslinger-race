extends RefCounted
class_name Api

# Port of the old js/api.js (removed with the JS client). Talking to the leaderboard server.
#
# The game is offline-first, so nothing here is allowed to block play: a run is
# always saved locally first, and the upload is best-effort. If there is no
# network the submission goes into a queue and is retried later, so a run made in
# a tunnel still counts when the phone gets signal back.
#
# The submitted time is not sent: the server recomputes it from the button steps.
# Sending it would only invite the server to disagree with the client.
#
# An upload needs a signed-in player, because a run belongs to an account. A
# guest's runs still queue, and are sent once they sign in.

const QUEUE_NAME := "queue.v2"
const CLIENT_NAME := "clientId.v1"
const MAX_QUEUE := 50


static func _queue_path() -> String:
	return "user://slingdrift.%s.json" % QUEUE_NAME


static func _client_path() -> String:
	return "user://slingdrift.%s.json" % CLIENT_NAME


# A stable per-device id, kept so a guest's queue survives a reload.
static func client_id() -> String:
	if FileAccess.file_exists(_client_path()):
		var f := FileAccess.open(_client_path(), FileAccess.READ)
		if f != null:
			var existing := f.get_as_text().strip_edges()
			f.close()
			if existing != "":
				return existing
	var id := ""
	for i in range(16):
		id += "%02x" % (randi() % 256)
	var w := FileAccess.open(_client_path(), FileAccess.WRITE)
	if w != null:
		w.store_string(id)
		w.close()
	return id


static func read_queue() -> Array:
	if not FileAccess.file_exists(_queue_path()):
		return []
	var f := FileAccess.open(_queue_path(), FileAccess.READ)
	if f == null:
		return []
	var parsed: Variant = JSON.parse_string(f.get_as_text())
	f.close()
	return parsed if parsed is Array else []


static func _write_queue(q: Array) -> void:
	var f := FileAccess.open(_queue_path(), FileAccess.WRITE)
	if f == null:
		return
	var trimmed := q
	if trimmed.size() > MAX_QUEUE:
		trimmed = trimmed.slice(trimmed.size() - MAX_QUEUE, trimmed.size())
	f.store_string(JSON.stringify(trimmed))
	f.close()


# Queue a finished run. Always succeeds - uploading is not the player's problem.
static func enqueue(track: int, steps: String, name: String) -> int:
	var q := []
	for e in read_queue():
		var entry: Dictionary = e
		if int(entry.get("track", -1)) == track and str(entry.get("steps", "")) == steps:
			continue
		q.append(entry)
	q.append({
		"track": track,
		"steps": steps,
		"name": name,
		"at": int(Time.get_unix_time_from_system() * 1000.0),
	})
	_write_queue(q)
	return q.size()


static func queue_length() -> int:
	return read_queue().size()


# Send one queued entry. Returns {drop}, {retry} or {ok, body}.
static func _post(entry: Dictionary) -> Dictionary:
	var token: String = await Account.auth_token()
	# A guest cannot upload: the run has no account to belong to. Keep it queued
	# rather than dropping it, so signing in later sends it.
	if token == "":
		return {"retry": true}

	var res: Dictionary = await Net.shared().post_json(
		NetConfig.function_endpoint("run"),
		NetConfig.auth_headers(token),
		{"track": int(entry["track"]), "steps": str(entry["steps"])},
	)

	# 422: the server replayed the run and it was not a finish. Re-sending it
	# cannot change that, so drop it instead of retrying forever.
	if int(res["status"]) == 422:
		return {"drop": true}
	# 401: the token went stale mid-queue. Retry, and the next flush refreshes.
	if int(res["status"]) == 401:
		return {"retry": true}
	# 409: signed in but with no username yet. Retry once a name exists.
	if int(res["status"]) == 409:
		return {"retry": true}
	if not bool(res["ok"]):
		return {"retry": true}
	return {"ok": true, "body": res["body"]}


# Try to send everything queued. Returns the last successful result, so the
# caller can show "you are #12" once the run lands. Runs are sent oldest first.
static func flush() -> Variant:
	var q := read_queue()
	if q.is_empty():
		return null
	var keep := []
	var last: Variant = null
	for e in q:
		var entry: Dictionary = e
		var r: Dictionary = await _post(entry)
		if bool(r.get("drop", false)):
			continue
		if bool(r.get("retry", false)):
			keep.append(entry)
			continue
		var body: Variant = r.get("body")
		var merged: Dictionary = body if body is Dictionary else {}
		merged["track"] = int(entry["track"])
		last = merged
	_write_queue(keep)
	return last


# The signed-in player's own best runs, keyed by track, or null when offline.
#
# A player's times live on the server, but the game reads its records from local
# storage. On a device that never made the run - a reinstall, a second phone, a
# cleared cache - signing in would otherwise show nothing even though the account
# holds the times. This pulls them back down so the account is the source of
# truth, not the device.
static func fetch_my_runs() -> Variant:
	var me := Account.current_user_id()
	if me == "":
		return null
	var token: String = await Account.auth_token()
	if token == "":
		return null
	var res: Dictionary = await Net.shared().get_json(
		"%s/runs?user_id=eq.%s&select=track,ticks,steps" % [NetConfig.rest_endpoint(), me],
		NetConfig.auth_headers(token),
	)
	if not bool(res["ok"]):
		return null
	var rows: Variant = res["body"]
	if not (rows is Array):
		return null
	# One row per track, so this is the player's best by construction: the table
	# keeps a single row per user per track and only ever lowers it.
	var out := []
	for r in rows:
		var row: Dictionary = r
		out.append({
			"track": int(row["track"]),
			"time": float(row["ticks"]) / 120.0,
			"steps": row.get("steps"),
		})
	return out


# The real runs on a track, or null when offline.
#
# This is not a page of a board: it is every real run on the track, so the client
# can rank and page them itself. A track holds one run per player, so the whole
# list is small and there is nothing to paginate here.
static func fetch_board(track: int) -> Variant:
	var token: String = await Account.auth_token()
	var res: Dictionary = await Net.shared().get_json(
		"%s?track=%d" % [NetConfig.function_endpoint("board"), track],
		NetConfig.auth_headers(token),
	)
	if not bool(res["ok"]):
		return null
	var body: Variant = res["body"]
	if not (body is Dictionary):
		return null
	var rows: Variant = body.get("rows")
	return rows if rows is Array else null
