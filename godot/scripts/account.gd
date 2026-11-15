extends RefCounted
class_name Account

# Port of js/account.js. These are *local* accounts: the password is checked
# against a hash kept on this device, not against anything remote. They exist so a
# shared device can keep separate scores, and so the board can show a name.
#
# Passwords are never stored. Each account keeps a random salt and the SHA-256 of
# salt + password. Honest, not bulletproof: anyone with the device could tamper
# with the file.

const ACC_NAME := "accounts.v1"
const SESSION_NAME := "session.v1"


static func _acc_path() -> String:
	return "user://slingdrift.%s.json" % ACC_NAME


static func _session_path() -> String:
	return "user://slingdrift.%s.json" % SESSION_NAME


static func _read_accounts() -> Dictionary:
	if not FileAccess.file_exists(_acc_path()):
		return {}
	var f := FileAccess.open(_acc_path(), FileAccess.READ)
	var txt := f.get_as_text()
	f.close()
	var parsed: Variant = JSON.parse_string(txt)
	return parsed if parsed is Dictionary else {}


static func _write_accounts(all: Dictionary) -> void:
	var f := FileAccess.open(_acc_path(), FileAccess.WRITE)
	f.store_string(JSON.stringify(all))
	f.close()


static func _norm(u: String) -> String:
	return u.strip_edges()


static func hash_password(password: String, salt: String) -> String:
	var ctx := HashingContext.new()
	ctx.start(HashingContext.HASH_SHA256)
	ctx.update(("%s\u0000%s" % [salt, password]).to_utf8_buffer())
	return ctx.finish().hex_encode()


static func random_salt() -> String:
	var b := PackedByteArray()
	for i in range(16):
		b.append(randi() % 256)
	return b.hex_encode()


# Every account name on this device, oldest first.
static func list_accounts() -> Array:
	var all := _read_accounts()
	var names := all.keys()
	names.sort_custom(func(a, b): return int(all[a]["createdAt"]) < int(all[b]["createdAt"]))
	return names


static func has_account(username: String) -> bool:
	return _read_accounts().has(_norm(username))


# The signed-in username, or "".
static func current_account() -> String:
	if not FileAccess.file_exists(_session_path()):
		return ""
	var f := FileAccess.open(_session_path(), FileAccess.READ)
	var name := f.get_as_text().strip_edges()
	f.close()
	return name


# Create an account and sign in. Returns {ok:true} or {ok:false, error:String}.
static func register(username: String, password: String) -> Dictionary:
	var name := _norm(username)
	if name.length() < 3:
		return {"ok": false, "error": "Username needs at least 3 characters."}
	if name.length() > 16:
		return {"ok": false, "error": "Username is at most 16 characters."}
	var re := RegEx.new()
	re.compile("^[A-Za-z0-9_.-]+$")
	if re.search(name) == null:
		return {"ok": false, "error": "Letters, numbers, _ . - only."}
	if password.length() < 4:
		return {"ok": false, "error": "Password needs at least 4 characters."}
	var all := _read_accounts()
	if all.has(name):
		return {"ok": false, "error": "That username is taken on this device."}
	var salt := random_salt()
	all[name] = {
		"salt": salt,
		"hash": hash_password(password, salt),
		"createdAt": int(Time.get_unix_time_from_system() * 1000.0),
	}
	_write_accounts(all)
	_sign_in(name)
	return {"ok": true}


static func login(username: String, password: String) -> Dictionary:
	var name := _norm(username)
	var all := _read_accounts()
	if not all.has(name):
		return {"ok": false, "error": "No such account on this device."}
	if hash_password(password, all[name]["salt"]) != all[name]["hash"]:
		return {"ok": false, "error": "Wrong password."}
	_sign_in(name)
	return {"ok": true}


static func _sign_in(name: String) -> void:
	var f := FileAccess.open(_session_path(), FileAccess.WRITE)
	f.store_string(name)
	f.close()


static func logout() -> void:
	if FileAccess.file_exists(_session_path()):
		DirAccess.remove_absolute(ProjectSettings.globalize_path(_session_path()))
