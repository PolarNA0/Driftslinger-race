extends SceneTree

# Headless check for the track editor's model: `CustomTracks` (authoring, storing,
# renaming, duplicating, deleting, transforming) and the roads it produces.
#
# The editor authors the same op list `Track.build_ops` already walks, so the claim
# that matters is that a hand-built track is a *real* road: it builds, a clean line
# drives it, and it finishes. A track the editor says is fine but the car cannot
# drive would be worse than no editor.
#
# Nothing here is mocked. The op list goes through the same `Track` the game loads,
# and the car is the same `Car`.

const DT := 1.0 / 120.0


# Drive a road with the clean line: grab when the pole is in reach, hold the arc
# out, let go at its end. Returns the same fields verify_tracks reports.
func _drive(track: Track) -> Dictionary:
	var car := Car.new()
	car.reset(track)
	var i := 0
	while car.alive and not car.finished and i < 200000:
		i += 1
		var held := false
		if car.attached:
			held = car.remaining() > 0.0
		else:
			var f: Dictionary = track.fillets[car.corner]
			var c: Vector2 = f["c"]
			held = U.dist(c.x, c.y, car.x, car.y) <= Cfg.GRAB_RANGE
		car.step(DT, held)
	return {
		"finished": car.finished, "time": car.time,
		"max_off": car.max_off, "grabbed": car.grabbed, "dead": car.dead,
	}


# A road must build and be drivable: a clean line finishes it on the road.
func _drivable(ops: Array, label: String) -> bool:
	var v := CustomTracks.validate(ops)
	if not bool(v["ok"]):
		print("  %s: validate says no: %s FAIL" % [label, str(v["error"])])
		return false
	var t := Track.new(0, CustomTracks.opts(ops, {"road": "4a4a4a", "ground": "48d350"}))
	var r := _drive(t)
	var ok: bool = bool(r["finished"]) and float(r["max_off"]) < Cfg.ROAD_HALF_WIDTH
	print("  %s: corners=%d length=%.0f finished=%s time=%.3f maxOff=%.2f %s"
		% [label, t.fillets.size(), float(v["length"]), str(r["finished"]), float(r["time"]), float(r["max_off"]), "OK" if ok else "FAIL"])
	return ok


# Builders for the input events the map consumes, so the checks drive the real
# `_gui_input` rather than the camera methods directly.
func _touch(pressed: bool, pos: Vector2) -> InputEventScreenTouch:
	var e := InputEventScreenTouch.new()
	e.index = 0
	e.pressed = pressed
	e.position = pos
	return e


func _drag(rel: Vector2, device: int) -> InputEventScreenDrag:
	var e := InputEventScreenDrag.new()
	e.index = 0
	e.relative = rel
	e.position = Vector2(100.0, 100.0) + rel
	e.device = device
	return e


func _mouse_motion(rel: Vector2, device: int) -> InputEventMouseMotion:
	var e := InputEventMouseMotion.new()
	e.relative = rel
	e.position = Vector2(100.0, 100.0) + rel
	e.device = device
	return e


func _pinch(factor: float) -> InputEventMagnifyGesture:
	var e := InputEventMagnifyGesture.new()
	e.factor = factor
	e.position = Vector2(180.0, 120.0)
	return e


func _init() -> void:
	var pass_all := true

	print("== a fresh track builds and drives ==")
	# The starter road every new track gets.
	var starter := CustomTracks.default_ops()
	pass_all = _drivable(starter, "starter") and pass_all

	# The staircase shape the shipped tracks use: alternating quarter turns.
	var staircase := []
	for i in range(6):
		staircase.append(CustomTracks.make_straight(230.0))
		staircase.append(CustomTracks.make_corner(90 if i % 2 == 0 else -90))
	pass_all = _drivable(staircase, "staircase x6") and pass_all

	# Advanced shapes: a hairpin (180) and a loop (270), each a single arc round a
	# single pivot, which is the whole point of the op-list builder.
	pass_all = _drivable([
		CustomTracks.make_straight(260.0),
		CustomTracks.make_corner(90),
		CustomTracks.make_straight(200.0),
		CustomTracks.make_corner(180, 70.0),
		CustomTracks.make_straight(200.0),
		CustomTracks.make_corner(-270, 55.0),
		CustomTracks.make_straight(220.0),
		CustomTracks.make_corner(-90),
	], "hairpin + loop") and pass_all

	print("== the default direction never folds the road ==")
	# Two corners the same way in a row point the road back over itself. The
	# editor's default always opposes the last corner, so a stack of defaults is a
	# staircase, not a fold.
	var stacked := []
	for i in range(8):
		stacked.append(CustomTracks.next_corner(stacked, 90))
	var alternates := true
	for i in range(1, stacked.size()):
		if int(stacked[i]["deg"]) == int(stacked[i - 1]["deg"]):
			alternates = false
	print("  next_corner alternates direction over 8 corners: %s" % ("OK" if alternates else "FAIL"))
	pass_all = alternates and pass_all
	pass_all = _drivable(_interleave(stacked), "default stack") and pass_all

	print("== transforms keep the road drivable ==")
	pass_all = _drivable(CustomTracks.mirror(staircase), "mirrored") and pass_all
	pass_all = _drivable(CustomTracks.reverse(staircase), "reversed") and pass_all
	# A transform of a transform is the original shape (mirror is its own inverse;
	# reverse twice is the identity).
	var rt := CustomTracks.reverse(CustomTracks.reverse(staircase))
	var same := rt.size() == staircase.size()
	if same:
		for i in range(rt.size()):
			if str(rt[i]) != str(staircase[i]):
				same = false
				break
	print("  reverse(reverse(x)) == x: %s" % ("OK" if same else "FAIL"))
	pass_all = same and pass_all

	print("== validation refuses what cannot be driven ==")
	# A corner whose radius is out of range, and a straight that is too short, are
	# the two the sliders cannot produce but a hand-edited file can, so validate has
	# to catch them rather than build a broken road.
	var tight := [
		{"t": "A", "deg": 90, "r": 10.0},
		{"t": "L", "len": 300.0},
		{"t": "A", "deg": -90, "r": 10.0},
	]
	var short := [
		{"t": "L", "len": 5.0},
		{"t": "A", "deg": 90},
		{"t": "L", "len": 300.0},
		{"t": "A", "deg": -90},
	]
	var cases := [
		[[], "empty"],
		[[CustomTracks.make_corner(90)], "one corner"],
		[[CustomTracks.make_corner(45)], "a 45-degree corner"],
		[tight, "a too-tight radius"],
		[short, "a too-short straight"],
	]
	for c in cases:
		var ops: Array = c[0]
		var label: String = c[1]
		var v := CustomTracks.validate(ops)
		var ok: bool = not bool(v["ok"])
		print("  %s refused: \"%s\" %s" % [label, str(v["error"]), "OK" if ok else "FAIL"])
		pass_all = ok and pass_all

	print("== the store: new / rename / duplicate / delete ==")
	# Storage is per account and this runs signed out, so the guest bucket is the
	# test's. Clear it first so the check is repeatable.
	Storage.save_custom_tracks([])
	var a := CustomTracks.new_track()
	var b := CustomTracks.new_track()
	var dup: Variant = CustomTracks.duplicate_track(int(a["id"]))
	var unique_ids: bool = int(a["id"]) != int(b["id"]) and int(dup["id"]) != int(a["id"]) and int(dup["id"]) != int(b["id"])
	print("  ids are unique: %s" % ("OK" if unique_ids else "FAIL"))
	pass_all = unique_ids and pass_all

	var unique_names: bool = str(a["name"]) != str(b["name"]) and str(dup["name"]) != str(a["name"])
	print("  names are unique: %s" % ("OK" if unique_names else "FAIL"))
	pass_all = unique_names and pass_all

	var a_reloaded: Variant = CustomTracks.get_track(int(a["id"]))
	var copied_ops: bool = (dup["ops"] as Array) == (a_reloaded["ops"] as Array)
	print("  the copy carries the source's ops: %s" % ("OK" if copied_ops else "FAIL"))
	pass_all = copied_ops and pass_all

	CustomTracks.rename(int(a["id"]), "  My Road  ")
	var renamed: Variant = CustomTracks.get_track(int(a["id"]))
	var renamed_ok: bool = renamed != null and str(renamed["name"]) == "My Road"
	print("  rename trims and stores: %s" % ("OK" if renamed_ok else "FAIL"))
	pass_all = renamed_ok and pass_all

	CustomTracks.rename(int(a["id"]), "")
	var blank: Variant = CustomTracks.get_track(int(a["id"]))
	var blank_ok: bool = blank != null and str(blank["name"]) == "Untitled"
	print("  a blank name becomes Untitled: %s" % ("OK" if blank_ok else "FAIL"))
	pass_all = blank_ok and pass_all

	CustomTracks.erase(int(b["id"]))
	var erased: bool = CustomTracks.get_track(int(b["id"])) == null and CustomTracks.count() == 2
	print("  delete removes just that track: %s" % ("OK" if erased else "FAIL"))
	pass_all = erased and pass_all

	print("== a stored track resolves to the opts the game loads ==")
	var opts: Dictionary = CustomTracks.opts_for_id(int(a["id"]))
	var resolved: bool = not opts.is_empty() and int(opts["corners"]) == CustomTracks.corner_count(a["ops"])
	print("  opts_for_id returns a buildable opts dict: %s" % ("OK" if resolved else "FAIL"))
	pass_all = resolved and pass_all
	var gone: bool = CustomTracks.opts_for_id(999999).is_empty()
	print("  a deleted/unknown id resolves to empty (Game falls back): %s" % ("OK" if gone else "FAIL"))
	pass_all = gone and pass_all

	print("== every corner the editor allows is catchable ==")
	# The editor's radius cap has to be inside the grab range, or a wide corner is a
	# track that cannot be driven: the car flies past the pole and hits the wall. This
	# is the bug the old 120px cap shipped, so it is pinned here.
	var wide := []
	for i in range(6):
		wide.append(CustomTracks.make_straight(240.0))
		wide.append(CustomTracks.make_corner(90 if i % 2 == 0 else -90, CustomTracks.MAX_RADIUS))
	var wide_v := CustomTracks.validate(wide)
	var wide_ok: bool = bool(wide_v["ok"]) and CustomTracks.MAX_RADIUS < Cfg.GRAB_RANGE
	print("  max radius %d < grab range %d: %s" % [int(CustomTracks.MAX_RADIUS), int(Cfg.GRAB_RANGE), "OK" if wide_ok else "FAIL"])
	pass_all = wide_ok and pass_all
	pass_all = _drivable(wide, "widest corners") and pass_all
	# And a radius past the cap is refused rather than built.
	var past := CustomTracks.validate([
		CustomTracks.make_straight(240.0),
		{"t": "A", "deg": 90, "r": Cfg.GRAB_RANGE + 20.0},
		CustomTracks.make_straight(240.0),
		CustomTracks.make_corner(-90),
	])
	var past_ok: bool = not bool(past["ok"])
	print("  a radius past the grab range is refused: %s" % ("OK" if past_ok else "FAIL"))
	pass_all = past_ok and pass_all

	print("== the corner-count cap ==")
	var many := []
	for i in range(CustomTracks.MAX_CORNERS + 1):
		many.append(CustomTracks.make_corner(90 if i % 2 == 0 else -90))
	var many_v := CustomTracks.validate(many)
	var many_ok: bool = not bool(many_v["ok"]) and str(many_v["error"]).contains("Too many corners")
	print("  more than %d corners is refused: %s" % [CustomTracks.MAX_CORNERS, "OK" if many_ok else "FAIL"])
	pass_all = many_ok and pass_all

	print("== colours ==")
	Storage.save_custom_tracks([])
	var ct := CustomTracks.new_track()
	var theme: Dictionary = CustomTracks.theme_of(ct)
	var has_theme: bool = str(theme["road"]).length() == 6 and str(theme["ground"]).length() == 6
	print("  a new track carries a complete theme: %s" % ("OK" if has_theme else "FAIL"))
	pass_all = has_theme and pass_all
	CustomTracks.set_theme(int(ct["id"]), "ff0000", "00ff00")
	var set: Dictionary = CustomTracks.theme_for_id(int(ct["id"]))
	var set_ok: bool = set["road"] == "FF0000" and set["ground"] == "00FF00"
	print("  set_theme stores the colours: %s" % ("OK" if set_ok else "FAIL"))
	pass_all = set_ok and pass_all
	# A missing or short value falls back to the default, so the renderer never sees a
	# half-set palette.
	var fallback: Dictionary = CustomTracks.theme_of({"id": 1, "ops": [], "road": "zz"})
	var fb_ok: bool = fallback["road"] == str(CustomTracks.DEFAULT_THEME["road"])
	print("  an invalid colour falls back to the default: %s" % ("OK" if fb_ok else "FAIL"))
	pass_all = fb_ok and pass_all
	# A theme on the opts is what the renderer reads when the track is played.
	var topts: Dictionary = CustomTracks.opts_for_id(int(ct["id"]))
	var topts_ok: bool = topts.has("theme") and str(topts["theme"]["road"]) == "FF0000"
	print("  opts_for_id carries the theme through: %s" % ("OK" if topts_ok else "FAIL"))
	pass_all = topts_ok and pass_all
	# The derived stripe and pole are always present and never equal to the road.
	var colors: Dictionary = CustomTracks.theme_colors(ct)
	var colors_ok: bool = colors.has("stripe") and colors.has("pole") and colors["stripe"] != colors["road"]
	print("  theme_colors derives stripe and pole: %s" % ("OK" if colors_ok else "FAIL"))
	pass_all = colors_ok and pass_all

	print("== the preview camera ==")
	var pv := TrackPreview.new()
	pv.size = Vector2(360.0, 240.0)
	pv.rebuild(CustomTracks.default_ops())
	pv.palette = CustomTracks.theme_of(ct)
	var cam_ok: bool = pv.ok and pv._road.size() >= 2
	print("  the preview builds the road: %s" % ("OK" if cam_ok else "FAIL"))
	pass_all = cam_ok and pass_all
	if cam_ok:
		pv.fit()
		var w0 := pv.screen_to_world(Vector2(180.0, 120.0))
		var s0 := pv.world_to_screen(w0)
		var round_ok: bool = absf(s0.x - 180.0) < 0.01 and absf(s0.y - 120.0) < 0.01
		print("  world<->screen round-trips: %s" % ("OK" if round_ok else "FAIL"))
		pass_all = round_ok and pass_all
		var zoom0 := pv._zoom
		pv.zoom_by(1.5)
		var zoom_ok: bool = pv._zoom > zoom0
		print("  zoom_by changes the zoom: %s" % ("OK" if zoom_ok else "FAIL"))
		pass_all = zoom_ok and pass_all
		var before := pv._origin
		pv.pan_by(Vector2(30.0, -10.0))
		var pan_ok: bool = pv._origin != before
		print("  pan_by moves the camera: %s" % ("OK" if pan_ok else "FAIL"))
		pass_all = pan_ok and pass_all
		# Tapping a piece on the map picks that piece: walk every piece's midpoint back
		# to screen space and expect it to come back.
		var picks_ok := true
		for sp in pv._spans:
			var mid := pv.world_to_screen(Vector2(float(sp["cx"]), float(sp["cy"])))
			var hit := pv.pick_at(mid)
			if hit != int(sp["op"]):
				picks_ok = false
				break
		print("  every piece's midpoint picks that piece: %s" % ("OK" if picks_ok else "FAIL"))
		pass_all = picks_ok and pass_all
		pv.focus_index(2)
		var foc := pv._span(2)
		var foc_screen := pv.world_to_screen(Vector2(float(foc["cx"]), float(foc["cy"])))
		var focus_ok: bool = foc_screen.distance_to(Vector2(180.0, 120.0)) < 2.0
		print("  focus_index centres a piece: %s" % ("OK" if focus_ok else "FAIL"))
		pass_all = focus_ok and pass_all
		# A finger drag is delivered twice (touch + emulated mouse). The map must pan
		# on the touch event only, or every drag moves it at double speed - the
		# "super sensitive" bug. An emulated mouse drag must not pan at all.
		var org := pv._origin
		pv._gui_input(_touch(true, Vector2(100.0, 100.0)))
		pv._gui_input(_mouse_motion(Vector2(20.0, 0.0), InputEvent.DEVICE_ID_EMULATION))
		var emu_ok: bool = pv._origin == org
		print("  an emulated mouse motion does not pan (no double-pan): %s" % ("OK" if emu_ok else "FAIL"))
		pass_all = emu_ok and pass_all
		pv._gui_input(_touch(false, Vector2(100.0, 100.0)))
		org = pv._origin
		pv._gui_input(_touch(true, Vector2(100.0, 100.0)))
		pv._gui_input(_drag(Vector2(20.0, 0.0), 0))
		var touch_ok: bool = pv._origin != org
		print("  a real touch drag does pan: %s" % ("OK" if touch_ok else "FAIL"))
		pass_all = touch_ok and pass_all
		pv._gui_input(_touch(false, Vector2(120.0, 100.0)))
		# Pinch zooms the map, so a phone can zoom without the +/- buttons.
		var pinch_before := pv._zoom
		pv._gui_input(_pinch(1.4))
		var pinch_ok: bool = pv._zoom > pinch_before
		print("  pinch zoom changes the zoom: %s" % ("OK" if pinch_ok else "FAIL"))
		pass_all = pinch_ok and pass_all
	pv.free()
	Storage.save_custom_tracks([])

	print("== the store is capped ==")
	Storage.save_custom_tracks([])
	var made := 0
	while made < CustomTracks.MAX_TRACKS + 5:
		var t: Variant = CustomTracks.new_track()
		if t.is_empty():
			break
		made += 1
	var capped: bool = made == CustomTracks.MAX_TRACKS and CustomTracks.new_track().is_empty()
	print("  new_track stops at %d and then refuses: %s" % [CustomTracks.MAX_TRACKS, "OK" if capped else "FAIL"])
	pass_all = capped and pass_all

	Storage.save_custom_tracks([])

	print("RESULT: %s" % ("PASS" if pass_all else "FAIL"))
	quit(0 if pass_all else 1)


# Space a list of corners out with straights so the road is drivable: two fillets
# meeting with no straight between them would fold the ribbon.
func _interleave(corners: Array) -> Array:
	var out := []
	for c in corners:
		out.append(CustomTracks.make_straight(210.0))
		out.append(c)
	return out
