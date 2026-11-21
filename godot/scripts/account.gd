extends RefCounted
class_name Account

# Port of the old js/account.js (removed with the JS client). Accounts.
#
# These are real accounts on a server, not device-local ones. Supabase Auth owns
# the credentials - the password is bcrypt-hashed on their side, and reset and
# confirmation emails come for free - and a `profiles` table owns the public name
# that the leaderboard shows.
#
# The point of moving off the device is that a player can sign in somewhere else
# and get their times back, which a device-local account could never do.
#
# The session (access token, refresh token, expiry) is kept in a file under
# user://. For a game with no sensitive data behind the login that is the normal
# trade for a client, but it does mean anything running on this device can read
# the token. It is a leaderboard token, not a bank token.

const SESSION_NAME := "session.v2"
const PENDING_NAME := "pending-name.v1"
const NAMES_NAME := "names.v1"
const IDNAMES_NAME := "idnames.v1"

const MIN_PASSWORD := 6


static func _path(name: String) -> String:
	return "user://slingdrift.%s.json" % name


# --- session storage ---------------------------------------------------------

static func _read_session() -> Variant:
	if not FileAccess.file_exists(_path(SESSION_NAME)):
		return null
	var f := FileAccess.open(_path(SESSION_NAME), FileAccess.READ)
	if f == null:
		return null
	var parsed: Variant = JSON.parse_string(f.get_as_text())
	f.close()
	return parsed if parsed is Dictionary else null


static func _write_session(s: Variant) -> void:
	if s == null:
		_delete(SESSION_NAME)
		return
	_write_text(_path(SESSION_NAME), JSON.stringify(s))
	var d: Dictionary = s
	var user: Variant = d.get("user")
	if user is Dictionary:
		remember_id(str((user as Dictionary).get("id", "")), str(d.get("username", "")))


# --- name by user id ---------------------------------------------------------
# The session is the source of truth for the signed-in name, but a name can go
# missing from it: a token refresh returns a session with no username on it. The
# name is what the per-account records are keyed by, so losing it silently moves
# every best time to the guest bucket. Remembering the id -> name pair means the
# account still resolves even if a session arrives without it.

static func _read_json(name: String, fallback: Variant) -> Variant:
	if not FileAccess.file_exists(_path(name)):
		return fallback
	var f := FileAccess.open(_path(name), FileAccess.READ)
	if f == null:
		return fallback
	var parsed: Variant = JSON.parse_string(f.get_as_text())
	f.close()
	return fallback if parsed == null else parsed


static func _write_json(name: String, value: Variant) -> void:
	_write_text(_path(name), JSON.stringify(value))


# Write a sibling temp file, then rename it over the target, so a crash mid-write
# leaves the previous save intact instead of a truncated JSON file.
static func _write_text(path: String, text: String) -> void:
	var tmp := path + ".tmp"
	var f := FileAccess.open(tmp, FileAccess.WRITE)
	if f == null:
		return
	f.store_string(text)
	f.close()
	var dir := DirAccess.open("user://")
	if dir == null:
		return
	dir.rename(tmp.get_file(), path.get_file())


static func remember_id(user_id: String, name: String) -> void:
	if user_id == "" or name == "":
		return
	var all: Dictionary = _read_json(IDNAMES_NAME, {})
	all[user_id] = name
	_write_json(IDNAMES_NAME, all)


static func _recall_id(user_id: String) -> String:
	if user_id == "":
		return ""
	var all: Dictionary = _read_json(IDNAMES_NAME, {})
	return str(all.get(user_id, ""))


# Turn a session response from the auth service into what we store.
static func _to_session(d: Dictionary, prev: Variant = null) -> Dictionary:
	var user: Dictionary = d.get("user", {})
	var expires_at := int(d.get("expires_at", 0))
	if expires_at == 0:
		expires_at = int(Time.get_unix_time_from_system()) + int(d.get("expires_in", 3600))
	var out := {
		"access_token": str(d.get("access_token", "")),
		"refresh_token": str(d.get("refresh_token", "")),
		"expires_at": expires_at,
		"user": {"id": str(user.get("id", "")), "email": str(user.get("email", ""))},
	}
	# A token refresh returns a session with no username on it. Carry over the one
	# we already had, but only for the same user. Records are keyed by name, so a
	# session that loses its name resolves the account to null and silently moves
	# every best time to the guest bucket.
	if prev is Dictionary:
		var p: Dictionary = prev
		var pu: Variant = p.get("user")
		if str(p.get("username", "")) != "" and pu is Dictionary \
				and str((pu as Dictionary).get("id", "")) == str(user.get("id", "")):
			out["username"] = str(p["username"])
	return out


# Trade the refresh token for a new access token, or "" if it will not.
static func _refresh_session(s: Dictionary) -> String:
	var res: Dictionary = await Net.shared().post_json(
		"%s/token?grant_type=refresh_token" % NetConfig.auth_endpoint(),
		NetConfig.auth_headers(""),
		{"refresh_token": str(s.get("refresh_token", ""))},
	)
	if not bool(res["ok"]):
		# A 4xx means the refresh token is dead; a transport failure means we are
		# offline and should keep the session for later.
		if int(res["status"]) >= 400:
			_write_session(null)
		return ""
	var body: Variant = res["body"]
	if not (body is Dictionary):
		return ""
	var next := _to_session(body, s)
	_write_session(next)
	return str(next["access_token"])


# A usable access token, refreshing it if it is close to expiry.
#
# Refreshing a minute early avoids the case where a token is valid when the
# upload starts and expired by the time it arrives.
static func auth_token() -> String:
	var s: Variant = _read_session()
	if s == null:
		return ""
	var sess: Dictionary = s
	var expires_at := int(sess.get("expires_at", 0))
	if expires_at > 0 and expires_at - int(Time.get_unix_time_from_system()) < 60:
		return await _refresh_session(sess)
	return str(sess.get("access_token", ""))


# --- profiles ----------------------------------------------------------------

# The signed-in player's public name, or "". Prefers the name on the session and
# falls back to the one remembered for this user id, because a refresh can hand
# back a session without the name and the records are keyed by it.
static func current_account() -> String:
	var s: Variant = _read_session()
	if s == null:
		return ""
	var sess: Dictionary = s
	var name := str(sess.get("username", ""))
	if name != "":
		return name
	return _recall_id(current_user_id())


static func current_email() -> String:
	var s: Variant = _read_session()
	if s == null:
		return ""
	var user: Variant = (s as Dictionary).get("user")
	return str((user as Dictionary).get("email", "")) if user is Dictionary else ""


# The signed-in player's auth id, or "". Used to ask the server for their runs.
static func current_user_id() -> String:
	var s: Variant = _read_session()
	if s == null:
		return ""
	var user: Variant = (s as Dictionary).get("user")
	return str((user as Dictionary).get("id", "")) if user is Dictionary else ""


static func signed_in() -> bool:
	return _read_session() != null


# Read a user's public name. {ok} says whether the server answered.
static func _fetch_profile(token: String, user_id: String) -> Dictionary:
	var res: Dictionary = await Net.shared().get_json(
		"%s/profiles?id=eq.%s&select=username" % [NetConfig.rest_endpoint(), user_id],
		NetConfig.auth_headers(token),
	)
	if not bool(res["ok"]):
		return {"ok": false, "username": ""}
	var rows: Variant = res["body"]
	if not (rows is Array) or (rows as Array).is_empty():
		return {"ok": true, "username": ""}
	return {"ok": true, "username": str((rows as Array)[0].get("username", ""))}


# Heal a session that is missing its username, and report the name.
#
# A session can arrive without a name: token refreshes used to drop it, and an
# install that predates the id -> name map has no fallback. Records are keyed by
# the name, so a nameless session shows the guest's best times instead of the
# player's. Ask the server for the name and write it back.
#
# Returns the resolved name, or "" if there is no session or the server cannot be
# reached. Never fails: boot must not depend on the network.
static func resolve_account() -> String:
	var s: Variant = _read_session()
	if s == null:
		return ""
	var known := current_account()
	if known != "":
		return known

	var user_id := current_user_id()
	var tok: String = await auth_token()
	if tok == "":
		return ""
	var mine: Dictionary = await _fetch_profile(tok, user_id)
	if not bool(mine["ok"]) or str(mine["username"]) == "":
		return ""
	# Signed out meanwhile: do not resurrect a session the player abandoned.
	if _read_session() == null or current_user_id() != user_id:
		return ""
	_set_session_name(str(mine["username"]))
	remember_name(str(mine["username"]))
	return str(mine["username"])


# Create the profile row for a signed-in user.
#
# Returns {ok, username} or {ok:false, error}. A taken name comes back as a 409
# from the unique index, which is the honest place to catch it: two people
# registering at once would both pass a client-side check.
static func ensure_profile(username: String, token: String = "") -> Dictionary:
	var tok := token
	if tok == "":
		tok = await auth_token()
	if tok == "" or not signed_in():
		return {"ok": false, "error": "Not signed in."}

	# This account may already have a name - a sign-in that could not reach the
	# profiles table leaves the session nameless, and picking your own existing
	# name would otherwise dead-end as "taken". Adopt it instead.
	var user_id := current_user_id()
	var mine: Dictionary = await _fetch_profile(tok, user_id)
	if bool(mine["ok"]) and str(mine["username"]) != "":
		_set_session_name(str(mine["username"]))
		remember_name(str(mine["username"]))
		return {"ok": true, "username": str(mine["username"])}

	var name := username.strip_edges()
	var bad := validate_name(name)
	if bad != "":
		return {"ok": false, "error": bad}

	var res: Dictionary = await Net.shared().post_json(
		NetConfig.rest_endpoint() + "/profiles",
		NetConfig.auth_headers(tok),
		{"id": user_id, "username": name},
	)
	if int(res["status"]) == 409:
		return {"ok": false, "error": "That username is taken."}
	if not bool(res["ok"]):
		return {"ok": false, "error": "Could not save that name. Try another."}

	_set_session_name(name)
	remember_name(name)
	return {"ok": true, "username": name}


static func _set_session_name(name: String) -> void:
	var s: Variant = _read_session()
	if s == null:
		return
	var sess: Dictionary = s
	sess["username"] = name
	_write_session(sess)


static func validate_name(name: String) -> String:
	if name.length() < 3:
		return "Username needs at least 3 characters."
	if name.length() > 16:
		return "Username is at most 16 characters."
	var re := RegEx.new()
	re.compile("^[A-Za-z0-9_.-]+$")
	if re.search(name) == null:
		return "Letters, numbers, _ . - only."
	return ""


# --- names seen on this device (a hint, not an account list) -----------------

static func list_accounts() -> Array:
	var parsed: Variant = _read_json(NAMES_NAME, [])
	return parsed if parsed is Array else []


static func remember_name(name: String) -> void:
	if name == "":
		return
	var all := []
	for n in list_accounts():
		if str(n) != name:
			all.append(str(n))
	all.push_front(name)
	if all.size() > 5:
		all = all.slice(0, 5)
	_write_json(NAMES_NAME, all)


# --- sign up, sign in, sign out ----------------------------------------------

# Create an account. `username` is the public name, `email` the login.
#
# If the project has email confirmation on, the auth service returns no session
# and the player must click the link before they can sign in; the chosen name is
# remembered so the first sign-in can complete the profile.
static func register(username: String, email: String, password: String) -> Dictionary:
	var name := username.strip_edges()
	var bad := validate_name(name)
	if bad != "":
		return {"ok": false, "error": bad}
	var mail := email.strip_edges()
	var re := RegEx.new()
	re.compile("^[^@\\s]+@[^@\\s]+\\.[^@\\s]+$")
	if re.search(mail) == null:
		return {"ok": false, "error": "That does not look like an email address."}
	if password.length() < MIN_PASSWORD:
		return {"ok": false, "error": "Password needs at least 6 characters."}

	var res: Dictionary = await Net.shared().post_json(
		"%s/signup" % NetConfig.auth_endpoint(),
		NetConfig.auth_headers(""),
		{"email": mail, "password": password},
	)
	var body: Variant = res["body"]
	var b: Dictionary = body if body is Dictionary else {}
	if not bool(res["ok"]):
		return {"ok": false, "error": _friendly(b, "Could not create that account.")}

	if str(b.get("access_token", "")) == "":
		# Confirmation is on: no session yet. Keep the name for the first sign-in.
		_write_json(PENDING_NAME, name)
		return {"ok": true, "pending": true}

	# Hold on to whatever session we had. Signing up must never cost a player the
	# account they were already using: if the name turns out to be taken, we put
	# the old session back rather than leaving them signed out.
	var prev: Variant = _read_session()
	_write_session(_to_session(b))
	var made: Dictionary = await ensure_profile(name, str(b.get("access_token", "")))
	if not bool(made["ok"]):
		# The auth user exists but has no profile, so it is not lost: signing in
		# later asks for a name. Keep the old session.
		_write_session(prev)
		return {"ok": false, "error": str(made.get("error", ""))}
	return {"ok": true}


# Sign in with an email and password.
static func login(email: String, password: String) -> Dictionary:
	var res: Dictionary = await Net.shared().post_json(
		"%s/token?grant_type=password" % NetConfig.auth_endpoint(),
		NetConfig.auth_headers(""),
		{"email": email.strip_edges(), "password": password},
	)
	var body: Variant = res["body"]
	var b: Dictionary = body if body is Dictionary else {}
	if not bool(res["ok"]):
		return {"ok": false, "error": _friendly(b, "Wrong email or password.")}

	_write_session(_to_session(b))

	# Completing a profile left over from a confirmation-flow signup.
	var user: Dictionary = b.get("user", {})
	var user_id := str(user.get("id", ""))
	var existing: Dictionary = await _fetch_profile(str(b.get("access_token", "")), user_id)
	if bool(existing["ok"]) and str(existing["username"]) != "":
		_set_session_name(str(existing["username"]))
		remember_name(str(existing["username"]))
		return {"ok": true}
	# The profile read failed (offline blip, say) but this device has signed this
	# user in before, so their name is known. Use it rather than asking again -
	# asking would dead-end, since their name is already taken by them.
	var known := _recall_id(user_id)
	if known != "":
		_set_session_name(known)
		remember_name(known)
		return {"ok": true}

	var pending: Variant = _read_json(PENDING_NAME, "")
	if str(pending) != "":
		var made: Dictionary = await ensure_profile(str(pending), str(b.get("access_token", "")))
		if bool(made["ok"]):
			_delete(PENDING_NAME)
			return {"ok": true}
	# Signed in, but no username yet: the caller should ask for one.
	return {"ok": true, "needs_name": true}


# Sign out on this device.
static func logout() -> void:
	_write_session(null)


static func _delete(name: String) -> void:
	if FileAccess.file_exists(_path(name)):
		DirAccess.remove_absolute(ProjectSettings.globalize_path(_path(name)))


# A message worth showing, rather than the raw error code.
static func _friendly(body: Dictionary, fallback: String) -> String:
	var raw := str(body.get("msg", body.get("error_description", body.get("message", ""))))
	var lower := raw.to_lower()
	if lower.contains("invalid login credentials"):
		return "Wrong email or password."
	if lower.contains("already registered"):
		return "That email already has an account. Sign in instead."
	if lower.contains("invalid") and lower.contains("email"):
		return "That email address is not accepted."
	if lower.contains("email not confirmed"):
		return "Confirm your email first - check your inbox."
	if lower.contains("password"):
		return "Password is too short. Use at least 6 characters."
	if lower.contains("rate limit"):
		return "Too many attempts. Wait a minute and try again."
	return fallback
