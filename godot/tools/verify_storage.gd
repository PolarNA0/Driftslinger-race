extends SceneTree

# Headless check of the save layer. Every write goes to a sibling temp file and
# is renamed over the target, so a crash mid-write leaves the last good save
# instead of a truncated JSON file. The rename is also the only step that has to
# overwrite an existing file, which is what makes the second write work at all.

var failures := 0


func _check(label: String, cond: bool) -> void:
	print("  %-56s %s" % [label, "ok " if cond else "FAIL"])
	if not cond:
		failures += 1


func _remove(path: String) -> void:
	if FileAccess.file_exists(path):
		DirAccess.remove_absolute(path)


func _initialize() -> void:
	var name := "verify.atomic.v1"
	var path := Storage._path(name)
	var tmp := path + ".tmp"
	_remove(tmp)
	_remove(path)

	print("-- storage --")
	Storage._write(name, {"n": 1})
	_check("a write lands and reads back", int(Storage._read(name, {}).get("n", 0)) == 1)
	_check("no temp file is left behind", not FileAccess.file_exists(tmp))
	Storage._write(name, {"n": 2})
	_check("a second write replaces the first", int(Storage._read(name, {}).get("n", 0)) == 2)

	# A temp file left by a crash must never be read as the save.
	var f := FileAccess.open(tmp, FileAccess.WRITE)
	f.store_string("{\"n\": 99}")
	f.close()
	_check("a stale temp file is ignored", int(Storage._read(name, {}).get("n", 0)) == 2)
	Storage._write(name, {"n": 3})
	_check("the next write clears the stale temp", not FileAccess.file_exists(tmp))
	_check("...and keeps the new value", int(Storage._read(name, {}).get("n", 0)) == 3)
	_remove(tmp)
	_remove(path)

	print("-- account --")
	var apath := Account._path(name)
	var atmp := apath + ".tmp"
	_remove(atmp)
	_remove(apath)
	Account._write_json(name, {"n": 1})
	_check("an account write reads back", int(Account._read_json(name, {}).get("n", 0)) == 1)
	_check("no account temp file is left behind", not FileAccess.file_exists(atmp))
	Account._write_json(name, {"n": 2})
	_check("an account write replaces the first", int(Account._read_json(name, {}).get("n", 0)) == 2)
	_remove(atmp)
	_remove(apath)

	print("STORAGE %s" % ("PASS" if failures == 0 else "FAIL (%d)" % failures))
	quit(0 if failures == 0 else 1)
