extends Node
class_name Net

# HTTP for the online layer: the transport under the port of the old js/api.js
# (removed with the JS client).
#
# The web export is built without thread support, so this uses HTTPRequest in
# single-threaded mode and serialises every call through one in-flight slot. A
# second caller waits its turn rather than fighting the first for the same
# request object.
#
# Every call resolves to the same shape, so a caller never has to handle a
# thrown error:
#   { ok: bool, status: int, body: Variant, error: String }
#
# `ok` is true for any 2xx. `status` is 0 when no HTTP response arrived at all.
# `error` is "" unless the failure happened below HTTP ("offline", "timeout",
# "request_failed"). A caller that cares about 401/409/422 reads `status`.

const TIMEOUT := 8.0

signal _slot_free

static var _shared: Net

var _http: HTTPRequest
var _busy := false


# The one instance every caller shares, created on first use. Static modules
# (Account, Api) reach the network through this, which keeps them static.
#
# The node is not parented here: a caller can reach this from a script's _init,
# before the tree exists, and both add_child and awaiting a frame are unsafe at
# that point. _send parents it once the tree is up.
static func shared() -> Net:
	if _shared == null or not is_instance_valid(_shared):
		_shared = Net.new()
		_shared.name = "Net"
	return _shared


func _ready() -> void:
	if _http != null:
		return
	_http = HTTPRequest.new()
	# Matches the JS client's 8s abort: a stalled request must not wedge the
	# queue, and a run is never worth waiting longer than this for.
	_http.timeout = TIMEOUT
	# Threads are off in the web export, so never rely on them here.
	_http.use_threads = false
	add_child(_http)


# Parent this node to the running tree, waiting for the tree to exist first.
# HTTPRequest refuses to send outside the tree, and a caller may arrive before
# the tree is up (a headless script, or the first frame of the game).
func _attach() -> void:
	var loop := Engine.get_main_loop()
	if not (loop is SceneTree):
		return
	var tree := loop as SceneTree
	# root is null until the tree starts, and `process_frame` does not fire
	# before then either, so this only awaits once the loop is actually running.
	while tree.root == null:
		await tree.process_frame
	if not is_inside_tree():
		tree.root.add_child(self)
	if _http == null:
		_ready()


func get_json(url: String, headers: PackedStringArray = PackedStringArray()) -> Dictionary:
	return await _send(HTTPClient.METHOD_GET, url, headers, "")


func post_json(url: String, headers: PackedStringArray, body: Dictionary) -> Dictionary:
	return await _send(HTTPClient.METHOD_POST, url, headers, JSON.stringify(body))


func _send(method: int, url: String, headers: PackedStringArray, body: String) -> Dictionary:
	await _attach()
	if _http == null:
		return {"ok": false, "status": 0, "body": null, "error": "no_transport"}

	await _acquire()
	var started := _http.request(url, headers, method, body)
	if started != OK:
		_release()
		return {"ok": false, "status": 0, "body": null, "error": "request_failed"}

	var res: Array = await _http.request_completed
	_release()

	var result := int(res[0])
	var status := int(res[1])
	var raw: PackedByteArray = res[3]

	if result == HTTPRequest.RESULT_TIMEOUT:
		return {"ok": false, "status": 0, "body": null, "error": "timeout"}
	if result != HTTPRequest.RESULT_SUCCESS:
		# No HTTP status at all: offline, DNS, TLS, or a dropped connection.
		return {"ok": false, "status": 0, "body": null, "error": "offline"}

	var text := raw.get_string_from_utf8()
	var parsed: Variant = null
	if text != "":
		parsed = JSON.parse_string(text)

	return {
		"ok": status >= 200 and status < 300,
		"status": status,
		"body": parsed,
		"error": "",
	}


# One request at a time. Awaiting resumes callers in arrival order, and the
# `while` re-checks because several can wake on the same emit.
func _acquire() -> void:
	while _busy:
		await _slot_free
	_busy = true


func _release() -> void:
	_busy = false
	_slot_free.emit()
