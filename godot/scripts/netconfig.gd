extends RefCounted
class_name NetConfig

# Where the leaderboard server lives, and the public anon key that reaches it.
#
# Both values are public: the anon key is designed to ship in a client (it is
# RLS-restricted, not secret) and was already committed in the legacy JS client.
# Keeping the same pair here means the game and the server talk to one project.
#
# Override order, lowest priority first:
#   1. the baked-in defaults below
#   2. `user://slingdrift.net.json`  {"url": "...", "key": "..."}
#   3. `--net-url=... --net-key=...` on the command line (for local testing)
#
# The override exists so a build can be pointed at a staging project, or at a
# local mock, without editing the game.

const DEFAULT_URL := "https://pleotpbgzeohxbuxffiq.supabase.co"
const DEFAULT_KEY := "eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJpc3MiOiJzdXBhYmFzZSIsInJlZiI6InBsZW90cGJnemVvaHhidXhmZmlxIiwicm9sZSI6ImFub24iLCJpYXQiOjE3OTQ3NjkxOTIsImV4cCI6MjExMDM0NTE5Mn0.Q8Se4oWOQ55yj8J9EXcllSMBXpiEMtmpmQUhPeJHZbU"

const OVERRIDE_NAME := "net.v1"


static func _override() -> Dictionary:
	var path := "user://slingdrift.%s.json" % OVERRIDE_NAME
	if not FileAccess.file_exists(path):
		return {}
	var f := FileAccess.open(path, FileAccess.READ)
	if f == null:
		return {}
	var parsed: Variant = JSON.parse_string(f.get_as_text())
	f.close()
	return parsed if parsed is Dictionary else {}


static func _flag(prefix: String) -> String:
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with(prefix):
			return arg.substr(prefix.length())
	return ""


# The project URL with no trailing slash, so paths can be appended directly.
static func url() -> String:
	var flagged := _flag("--net-url=")
	if flagged != "":
		return flagged.trim_suffix("/")
	var over: Dictionary = _override()
	var value := str(over.get("url", DEFAULT_URL))
	return value.trim_suffix("/")


static func anon_key() -> String:
	var flagged := _flag("--net-key=")
	if flagged != "":
		return flagged
	var over: Dictionary = _override()
	return str(over.get("key", DEFAULT_KEY))


# True when there is a project to talk to. The game is fully playable without
# one; only the online features go quiet.
static func configured() -> bool:
	return url() != "" and anon_key() != ""


# Headers every request carries. `apikey` is what the Supabase gateway checks;
# `authorization` is added separately when a player is signed in.
static func base_headers() -> PackedStringArray:
	return PackedStringArray([
		"apikey: %s" % anon_key(),
		"content-type: application/json",
	])


static func auth_headers(token: String) -> PackedStringArray:
	var h := base_headers()
	if token != "":
		h.append("authorization: Bearer %s" % token)
	return h


static func auth_endpoint() -> String:
	return "%s/auth/v1" % url()


static func rest_endpoint() -> String:
	return "%s/rest/v1" % url()


static func function_endpoint(name: String) -> String:
	return "%s/functions/v1/%s" % [url(), name]
