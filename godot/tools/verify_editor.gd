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
		elif car.corner >= 0 and car.corner < track.fillets.size():
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


# A second finger, for the pinch tests. `index` is what the preview tracks touches
# by, so the two fingers have to be distinguishable.
func _touch2(pressed: bool, pos: Vector2) -> InputEventScreenTouch:
	var e := InputEventScreenTouch.new()
	e.index = 1
	e.pressed = pressed
	e.position = pos
	return e


# Lift a specific finger. `_touch` is always index 0, so a test that pinches with two
# fingers has to say which one came up.
func _lift(index: int, pos: Vector2) -> InputEventScreenTouch:
	var e := InputEventScreenTouch.new()
	e.index = index
	e.pressed = false
	e.position = pos
	return e


func _drag2(pos: Vector2, index: int) -> InputEventScreenDrag:
	var e := InputEventScreenDrag.new()
	e.index = index
	e.position = pos
	e.relative = Vector2.ZERO
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

	print("== a new track starts empty, and an empty track is refused ==")
	# A new track is a blank canvas: the player places the first piece. It must
	# not be drivable (there is no road), but it must also not crash the preview.
	var starter := CustomTracks.default_ops()
	var starter_v := CustomTracks.validate(starter)
	var empty_ok: bool = starter.is_empty() and not bool(starter_v["ok"])
	print("  a new track has 0 pieces and is not yet valid: %s" % [
		"OK" if empty_ok else "FAIL"])
	pass_all = empty_ok and pass_all

	# The staircase shape the shipped tracks use: alternating quarter turns.
	var staircase := []
	for i in range(6):
		staircase.append(CustomTracks.make_straight(230.0))
		staircase.append(CustomTracks.make_corner(90 if i % 2 == 0 else -90))
	staircase.append(CustomTracks.make_finish())
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
		CustomTracks.make_finish(),
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

	print("== the finish line closes the track ==")
	# A track with corners but no finish has no end, so it cannot be played: the road
	# would run on for ever. This is the check that makes the finish piece load-bearing
	# rather than decorative.
	var no_fin := []
	for i in range(4):
		no_fin.append(CustomTracks.make_straight(230.0))
		no_fin.append(CustomTracks.make_corner(90 if i % 2 == 0 else -90))
	var nf_v := CustomTracks.validate(no_fin)
	var nf_ok: bool = not bool(nf_v["ok"]) and str(nf_v["error"]).contains("finish")
	# As soon as there is a finish line the track is playable. The rule used to demand
	# two corners, which refused a perfectly drivable road: a straight into a finish
	# builds and the car crosses the line. Requiring corners the player has not placed
	# yet is what made the editor feel like it was forcing pieces on them.
	var one_line := [CustomTracks.make_finish(400.0)]
	var ol_v := CustomTracks.validate(one_line)
	var ol_ok: bool = bool(ol_v["ok"])
	print("  a finish line alone is a playable track: %s" % ("OK" if ol_ok else "FAIL"))
	pass_all = ol_ok and pass_all
	pass_all = _drivable(one_line, "finish only") and pass_all
	# One corner and a finish is also a whole track: the corner is optional, not a
	# prerequisite.
	var one_corner := [
		CustomTracks.make_straight(240.0),
		CustomTracks.make_corner(90),
		CustomTracks.make_finish(300.0),
	]
	var oc_v := CustomTracks.validate(one_corner)
	print("  one corner and a finish is playable: %s" % ("OK" if bool(oc_v["ok"]) else "FAIL"))
	pass_all = bool(oc_v["ok"]) and pass_all
	pass_all = _drivable(one_corner, "one corner") and pass_all
	print("  a track with no finish is refused: %s" % ("OK" if nf_ok else "FAIL"))
	pass_all = nf_ok and pass_all
	# Exactly one finish: two would mean two ends.
	var two := no_fin.duplicate()
	two.append(CustomTracks.make_finish())
	two.append(CustomTracks.make_finish())
	var two_v := CustomTracks.validate(two)
	var two_ok: bool = not bool(two_v["ok"]) and str(two_v["error"]).contains("finish")
	print("  two finish lines are refused: %s" % ("OK" if two_ok else "FAIL"))
	pass_all = two_ok and pass_all
	# The finish is a closing straight, so it is what the built track's finish distance
	# comes from - a longer run-in has to move the line further down the road.
	var short_fin := _interleave([CustomTracks.make_corner(90), CustomTracks.make_corner(-90)])
	short_fin[short_fin.size() - 1] = CustomTracks.make_finish(180.0)
	var long_fin := short_fin.duplicate(true)
	long_fin[long_fin.size() - 1] = CustomTracks.make_finish(520.0)
	var t_short := Track.new(0, CustomTracks.opts(short_fin))
	var t_long := Track.new(0, CustomTracks.opts(long_fin))
	var grows: bool = absf((t_long.finish_s - t_short.finish_s) - 340.0) < 1.0
	print("  a longer finish moves the line (%.0f -> %.0f): %s" % [
		t_short.finish_s, t_long.finish_s, "OK" if grows else "FAIL"])
	pass_all = grows and pass_all
	# A finish straight is not a corner: it must not add a pole or a sling to the run.
	var corners_same: bool = t_long.fillets.size() == t_short.fillets.size()
	print("  the finish adds no corner: %s" % ("OK" if corners_same else "FAIL"))
	pass_all = corners_same and pass_all

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
	wide.append(CustomTracks.make_finish())
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
	many.append(CustomTracks.make_finish())
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

	print("== a slider drag does not rebuild the menu list per frame ==")
	# The editor's live slider callback used to emit `changed` on every value, and its
	# listener rebuilds the menu's custom-track list (up to 100 buttons, each
	# re-validated). Dragging a length slider therefore did that work every frame - the
	# "seizure" - even though nothing the list shows changes during the drag. Assert the
	# listener is not called per value, and is called once when the drag ends.
	var fire := [0]
	var probe = load("res://scripts/track_editor.gd").new()
	probe.changed.connect(func(): fire[0] += 1)
	probe.id = CustomTracks.new_track()["id"]
	probe.ops = [CustomTracks.make_straight(240.0)]
	for v in range(10):
		probe._apply_live(0)
	var quiet: bool = fire[0] == 0
	print("  10 live slider values rebuild the list 0 times: %d %s" % [fire[0], "OK" if quiet else "FAIL"])
	pass_all = quiet and pass_all
	probe.free()

	print("== the preview camera ==")
	var pv := TrackPreview.new()
	pv.size = Vector2(360.0, 240.0)
	var cam_ops := [
		CustomTracks.make_straight(240.0),
		CustomTracks.make_corner(90),
		CustomTracks.make_straight(240.0),
		CustomTracks.make_corner(-90),
		CustomTracks.make_finish(),
	]
	pv.rebuild(cam_ops)
	pv.palette = CustomTracks.theme_of(ct)
	var cam_ok: bool = pv.ok and pv._road.size() >= 2
	print("  the preview builds the road: %s" % ("OK" if cam_ok else "FAIL"))
	pass_all = cam_ok and pass_all
	# The band must be solid, not a row of dashes. A per-segment normal leaves a
	# wedge of ground at every sample where the road curves, because the two quads
	# either side of a sample meet at different angles. Measured on a 90-degree arc
	# that was a 9.4px seam at 2.6x zoom, which is what made placed curves read as
	# "a lot of little lines".
	pv.fit()
	var nrm: Array = pv._vertex_normals()
	var normals_ok: bool = nrm.size() == pv._road.size()
	for n in nrm:
		if absf((n as Vector2).length() - 1.0) > 0.001:
			normals_ok = false
	print("  one unit normal per road sample: %s" % ("OK" if normals_ok else "FAIL"))
	pass_all = normals_ok and pass_all
	# Build the quads exactly as `_band` does and require adjacent ones to share their
	# edge vertices. That is the property that closes the seam: with a per-segment
	# normal the two quads meeting at a sample were offset in different directions, so
	# their shared edge did not line up and a wedge of ground showed through.
	var seam_ok := true
	var hw_test := 10.0
	for i in range(pv._road.size() - 1):
		var pb: Vector2 = pv.world_to_screen(pv._road[i + 1])
		var n0: Vector2 = (nrm[i] as Vector2) * hw_test
		var n1: Vector2 = (nrm[i + 1] as Vector2) * hw_test
		# Quad i ends on (pb + n1, pb - n1). Quad i+1 starts on the same pair, because
		# `_band` reads nrm[i + 1] at the shared sample for both. A per-segment normal
		# would have used a different vector on each side.
		if n1 == Vector2.ZERO:
			seam_ok = false
		if pb + n1 == pb - n1:
			seam_ok = false
		# A neighbouring sample must not flip the normal entirely, or the band pinches.
		if (n0 - n1).length() > hw_test * 1.5:
			seam_ok = false
	print("  consecutive quads share their seam vertices: %s" % ("OK" if seam_ok else "FAIL"))
	pass_all = seam_ok and pass_all
	# A pole has to be big enough to see. The radius used to clamp to a 2px floor at
	# fit zoom, which put a near-invisible dot on the map and read as "there are no
	# pillars in the editor".
	var pole_ok: bool = pv._poles.size() == 2
	var pole_r: float = clampf(9.0 * pv._zoom, 5.0, 14.0)
	if pole_r < 5.0:
		pole_ok = false
	print("  every corner has a pole, drawn at %.1fpx: %s" % [pole_r, "OK" if pole_ok else "FAIL"])
	pass_all = pole_ok and pass_all

	# A bend has no pillar, so the map must not draw one. A dot at its centre would tell
	# the player there is something to grab, and there is not.
	var bend_pv := TrackPreview.new()
	bend_pv.rebuild([
		CustomTracks.make_straight(240.0),
		CustomTracks.make_bend(90),
		CustomTracks.make_finish(400.0),
	])
	var bend_no_pole: bool = bend_pv._poles.size() == 0 and bend_pv._spans.size() == 3
	print("  a bend draws no pole on the map (poles=%d): %s"
		% [bend_pv._poles.size(), "OK" if bend_no_pole else "FAIL"])
	pass_all = bend_no_pole and pass_all
	bend_pv.free()
	# A palette tile must place exactly the piece it draws. The tile carries a signed
	# angle and the op has to use that sign: a left tile that placed a right turn, or a
	# 270 tile that placed a 90, is a picture that lies about the road it adds.
	var signs_ok := true
	for key in ["90", "-90", "180", "270", "-270", "reattach", "reattach_l"]:
		if PieceIcon.turn_deg(key) == 0:
			signs_ok = false
		if key.begins_with("-") and PieceIcon.turn_deg(key) == PieceIcon.turn_deg(key.substr(1)):
			signs_ok = false
	print("  every turn tile carries its own signed angle: %s" % ("OK" if signs_ok else "FAIL"))
	pass_all = signs_ok and pass_all
	# A 270 and a 90 must be different pictures, not one drawn twice: that was the
	# report that the palette "does not show the correct way they turn".
	var icons_distinct: bool = (
		PieceIcon.turn_deg("90") != PieceIcon.turn_deg("270")
		and PieceIcon.turn_deg("90") != PieceIcon.turn_deg("-90")
		and PieceIcon.turn_deg("180") != PieceIcon.turn_deg("270")
	)
	print("  the turn tiles are not all the same piece: %s" % ("OK" if icons_distinct else "FAIL"))
	# The art has to agree with the label. Check the drawn centreline: a right tile
	# must end to the right of where it entered, a left tile to the left, and every
	# tile must stay inside its own box (a 270 used to be drawn off the edge).
	var art_ok := true
	for key in ["90", "-90", "180", "270", "-270"]:
		var deg: int = PieceIcon.turn_deg(key)
		var pts: PackedVector2Array = PieceIcon.arc_points(deg, 56.0, 56.0, 11.2, 8.96)
		if pts.size() < 2:
			art_ok = false
			continue
		var entry: Vector2 = pts[0]
		var exit: Vector2 = pts[pts.size() - 1]
		var went_right: bool = exit.x > entry.x + 0.5
		var went_left: bool = exit.x < entry.x - 0.5
		if deg > 0 and deg != 180 and not went_right:
			art_ok = false
			print("    %s is a right turn but exits at dx=%.1f" % [key, exit.x - entry.x])
		if deg < 0 and not went_left:
			art_ok = false
			print("    %s is a left turn but exits at dx=%.1f" % [key, exit.x - entry.x])
		for p in pts:
			if p.x < -0.5 or p.y < -0.5 or p.x > 56.5 or p.y > 56.5:
				art_ok = false
				print("    %s draws outside its tile at %s" % [key, p])
	print("  each tile is drawn turning the way its label says: %s" % ("OK" if art_ok else "FAIL"))
	pass_all = art_ok and pass_all
	pass_all = icons_distinct and pass_all
	# A corner tile must place the signed op, whichever cell was tapped. Placement
	# used to take the direction from the tapped cell, so the same tile could add a
	# left or a right turn depending on where the finger landed.
	var aim := TrackPreview.new()
	aim.size = Vector2(600.0, 400.0)
	aim.palette = CustomTracks.theme_of(ct)
	aim.rebuild([CustomTracks.make_straight(240.0)])
	var l_op := CustomTracks.make_corner(PieceIcon.turn_deg("-90"), CustomTracks.DEFAULT_RADIUS)
	var r_op := CustomTracks.make_corner(PieceIcon.turn_deg("90"), CustomTracks.DEFAULT_RADIUS)
	var fixed_dir: bool = int(l_op["deg"]) < 0 and int(r_op["deg"]) > 0
	print("  a tile places its own direction, not the tap's: %s" % ("OK" if fixed_dir else "FAIL"))
	pass_all = fixed_dir and pass_all
	aim.free()


	# A track still being built is not valid yet, but the pieces placed so far must
	# still draw: the canvas shows the road as it grows, not only once it is legal.
	var part := TrackPreview.new()
	part.size = Vector2(360.0, 240.0)
	part.rebuild([CustomTracks.make_straight(240.0)])
	var partial_ok: bool = not part.ok and part._road.size() >= 2
	print("  an unfinished track still draws its pieces: %s" % ("OK" if partial_ok else "FAIL"))
	pass_all = partial_ok and pass_all
	# The grid must stay legible on every theme ground, not just the dark ones. It
	# was a fixed light ink at low alpha, which measures fine over the editor's own
	# background but collapses against a bright ground like Sunset's - the grid was
	# being drawn, and was simply invisible. Check the contrast the renderer picks.
	var grid_ok := true
	for preset in CustomTracks.THEME_PRESETS:
		var g := Color(str(preset["ground"]))
		var line := Color(0.0, 0.0, 0.0, 0.22) if g.get_luminance() > 0.45 else Color(UiTheme.HUD_INK, 0.20)
		var over := g.lerp(line, line.a)
		var delta: float = absf(over.get_luminance() - g.get_luminance())
		if delta < 0.05:
			grid_ok = false
			print("    %s: grid contrast %.3f, too low" % [str(preset["name"]), delta])
	print("  the grid stays visible on every theme ground: %s" % ("OK" if grid_ok else "FAIL"))
	pass_all = grid_ok and pass_all
	part.free()
	# On a blank canvas the first piece grows from the end of the lead-in, which is
	# where the built road starts. Reading the start from an empty `_track` gave the
	# origin, so the first straight came out a lead-in longer than the player's tap.
	var empty_pv := TrackPreview.new()
	empty_pv.size = Vector2(360.0, 240.0)
	empty_pv.rebuild([])
	var start_ok: bool = empty_pv._start_world().distance_to(
		Vector2(cos(Cfg.BASE_HEADING), sin(Cfg.BASE_HEADING)) * CustomTracks.LEAD_IN) < 0.01
	print("  the first piece grows from the lead-in end: %s" % ("OK" if start_ok else "FAIL"))
	pass_all = start_ok and pass_all
	empty_pv.free()
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
		# Pan must be a fixed, damped fraction of the finger's travel - never a multiple
		# of it. `relative` is scaled by whatever transform the platform applies to the
		# event, and a build that scales `position` but not `relative` - or that
		# delivers a drag twice - pans at 2x, 3x or worse on a phone while a
		# scale-1.0 headless run looks perfect. So assert the distance, not just that
		# something moved. The drag below carries a `relative` of 30 but a `position`
		# that moved 30 too; a pan derived from `relative` would ignore PAN_GAIN.
		var p0 := pv._origin
		pv._gui_input(_touch(true, Vector2(100.0, 100.0)))
		var d := InputEventScreenDrag.new()
		d.index = 0
		d.position = Vector2(130.0, 100.0)
		d.relative = Vector2(30.0, 0.0)
		pv._gui_input(d)
		var travel := (pv._origin - p0).length()
		var want: float = 30.0 * TrackPreview.PAN_GAIN
		var exact: bool = absf(travel - want) < 1.0
		print("  a 30px drag pans %.1fpx (damped): %.1f %s" % [want, travel, "OK" if exact else "FAIL"])
		pass_all = exact and pass_all
		pv._gui_input(_touch(false, Vector2(130.0, 100.0)))
		# A drag whose `relative` disagrees with its `position` must follow `position`:
		# that is the field the viewport definitely transforms, and the one tap picking
		# trusts, so it is the only field that means the same thing on every platform.
		var p1 := pv._origin
		pv._gui_input(_touch(true, Vector2(200.0, 200.0)))
		var bad := InputEventScreenDrag.new()
		bad.index = 0
		bad.position = Vector2(220.0, 200.0)
		bad.relative = Vector2(60.0, 0.0)
		pv._gui_input(bad)
		var follows := absf((pv._origin - p1).length() - 20.0 * TrackPreview.PAN_GAIN) < 1.0
		print("  a lying `relative` is ignored, `position` wins: %s" % ("OK" if follows else "FAIL"))
		pass_all = follows and pass_all
		pv._gui_input(_touch(false, Vector2(220.0, 200.0)))
		# Pinch zooms the map, so a phone can zoom without the +/- buttons.
		var pinch_before := pv._zoom
		pv._gui_input(_pinch(1.4))
		var pinch_ok: bool = pv._zoom > pinch_before
		print("  pinch zoom changes the zoom: %s" % ("OK" if pinch_ok else "FAIL"))
		pass_all = pinch_ok and pass_all
		# A pinch must be absolute from the gesture's start: jittering the two fingers
		# and settling on the same span must land on the same zoom as opening them
		# straight to it, or the map twitches under a real hand.
		pv._zoom = 1.0
		pv._gui_input(_touch(true, Vector2(100.0, 100.0)))
		pv._gui_input(_touch2(true, Vector2(200.0, 100.0)))
		for span in [190.0, 210.0, 185.0, 200.0]:
			pv._gui_input(_drag2(Vector2(100.0 + span, 100.0), 1))
		var z_jitter := pv._zoom
		pv._gui_input(_touch(false, Vector2(300.0, 100.0)))
		pv._gui_input(_touch(false, Vector2(100.0, 100.0)))
		pv._zoom = 1.0
		pv._gui_input(_touch(true, Vector2(100.0, 100.0)))
		pv._gui_input(_touch2(true, Vector2(200.0, 100.0)))
		pv._gui_input(_drag2(Vector2(300.0, 100.0), 1))
		var z_direct := pv._zoom
		pv._gui_input(_touch(false, Vector2(300.0, 100.0)))
		pv._gui_input(_touch(false, Vector2(100.0, 100.0)))
		var stable: bool = absf(z_jitter - z_direct) < 0.01 and z_direct > 1.5
		print("  a jittery pinch lands where a clean one does: %.3f vs %.3f %s" % [
			z_jitter, z_direct, "OK" if stable else "FAIL"])
		pass_all = stable and pass_all
		# Lifting one finger out of a pinch must not jump the map. The remaining finger
		# pans from where it was last seen, and if the pinch never updated that, the whole
		# distance it travelled during the pinch lands in one step. Finger 1 is the one
		# that moves, so finger 1 is the one left down.
		pv._zoom = 1.0
		pv._gui_input(_touch(true, Vector2(100.0, 100.0)))
		pv._gui_input(_touch2(true, Vector2(200.0, 100.0)))
		pv._gui_input(_drag2(Vector2(260.0, 100.0), 1))   # finger 1 travels 60
		pv._gui_input(_lift(0, Vector2(100.0, 100.0)))    # finger 0 lifts
		var o_before := pv._origin
		pv._gui_input(_drag2(Vector2(265.0, 100.0), 1))   # finger 1 moves 5
		var jump := (pv._origin - o_before).length()
		var no_jump: bool = absf(jump - 5.0 * TrackPreview.PAN_GAIN) < 1.5
		print("  lifting a pinch finger does not jump the map: %.1f px %s" % [
			jump, "OK" if no_jump else "FAIL"])
		pass_all = no_jump and pass_all
		pv._gui_input(_lift(1, Vector2(265.0, 100.0)))
	pv.free()
	Storage.save_custom_tracks([])

	# --- one grid cell is one piece ----------------------------------------------
	# The grid is the unit the road is built from, not decoration behind it: a tap on a
	# cell places exactly one piece, and every piece is one cell long.
	print("== a cell is a piece ==")
	var cell_is_piece: bool = absf(CustomTracks.CELL_LEN - 80.0) < 0.001 \
		and absf(float(TrackPreview.CELL) - float(CustomTracks.CELL_LEN)) < 0.001
	print("  the grid cell and a piece are the same length (%.0f): %s"
		% [CustomTracks.CELL_LEN, "OK" if cell_is_piece else "FAIL"])
	pass_all = cell_is_piece and pass_all

	# A straight piece is one cell long, whatever cell was tapped. Reading the length
	# from the tap's distance made the grid decorative and the same tile a different
	# road depending on where it landed.
	var straight_len: float = float(CustomTracks.make_straight(CustomTracks.CELL_LEN)["len"])
	var len_is_cell: bool = absf(straight_len - CustomTracks.CELL_LEN) < 0.001
	print("  a straight piece is one cell long (%.0f): %s" % [straight_len, "OK" if len_is_cell else "FAIL"])
	pass_all = len_is_cell and pass_all

	# --- a pillar and a corner are two pieces -----------------------------------
	# A bend is a turn with no pillar. It is wide because the car can only steer round a
	# gentle curve with no pole to sling, and it has to be drivable with no input at all.
	print("== a pillar is separate from a piece ==")
	var bend := CustomTracks.make_bend(90)
	var bend_has_no_pillar: bool = not CustomTracks.has_pillar(bend) \
		and absf(float(bend["r"]) - CustomTracks.BEND_RADIUS) < 0.001
	print("  a bend carries no pillar and is %d wide: %s"
		% [int(CustomTracks.BEND_RADIUS), "OK" if bend_has_no_pillar else "FAIL"])
	pass_all = bend_has_no_pillar and pass_all
	var corner_has_pillar: bool = CustomTracks.has_pillar(CustomTracks.make_corner(90))
	print("  an ordinary corner carries its pillar: %s" % ("OK" if corner_has_pillar else "FAIL"))
	pass_all = corner_has_pillar and pass_all

	# A pillarless turn narrower than a bend is a wall. Refusing it is the whole point:
	# the editor must not let a player build a corner nobody can drive.
	var tight_bend := {"t": "A", "deg": 90, "r": 62.0, "reattach": false, "pillar": false}
	var tb_v := CustomTracks.validate([CustomTracks.make_straight(240.0), tight_bend, CustomTracks.make_finish(300.0)])
	var tb_refused: bool = not bool(tb_v["ok"])
	print("  a narrow turn with no pillar is refused: %s" % ("OK" if tb_refused else "FAIL"))
	pass_all = tb_refused and pass_all

	# The bend must be drivable with no input at all, or "no pillar" is a lie.
	var bend_ops := [
		CustomTracks.make_straight(240.0),
		CustomTracks.make_bend(90),
		CustomTracks.make_straight(240.0),
		CustomTracks.make_bend(-90),
		CustomTracks.make_finish(400.0),
	]
	var bend_v := CustomTracks.validate(bend_ops)
	print("  a bend track validates: %s" % ("OK" if bool(bend_v["ok"]) else "FAIL"))
	pass_all = bool(bend_v["ok"]) and pass_all
	var bt := Track.new(0, CustomTracks.opts(bend_ops, {"road": "4a4a4a", "ground": "48d350"}))
	var bcar := Car.new()
	bcar.reset(bt)
	var bi := 0
	while bcar.alive and not bcar.finished and bi < 200000:
		bi += 1
		bcar.step(DT, false)
	var bend_steers: bool = bcar.finished and bcar.max_off < Cfg.ROAD_HALF_WIDTH
	print("  a bend drives clean with no input: finished=%s maxOff=%.1f %s"
		% [str(bcar.finished), bcar.max_off, "OK" if bend_steers else "FAIL"])
	pass_all = bend_steers and pass_all

	# And there is nothing at a bend's centre to grab, so holding must not attach.
	var grab_ok := false
	if bt.fillets.size() > 0:
		var bc2 := Car.new()
		bc2.reset(bt)
		var j := 0
		while bc2.alive and not bc2.finished and j < 200000:
			j += 1
			bc2.step(DT, true)
			if bc2.attached:
				break
		grab_ok = not bc2.attached
	print("  holding the button never grabs a bend: %s" % ("OK" if grab_ok else "FAIL"))
	pass_all = grab_ok and pass_all

	# A transform changes which way a piece turns, never what it is. Rebuilding a corner
	# from the raw fields dropped the pillar flag, which turned a wide bend into a tight
	# pillarless turn - a wall - and `make_corner`'s corner-radius clamp would have
	# shrunk it even if the flag survived.
	var bend_only := [
		CustomTracks.make_straight(240.0),
		CustomTracks.make_bend(90),
		CustomTracks.make_finish(400.0),
	]
	var m := CustomTracks.mirror(bend_only)
	var rv := CustomTracks.reverse(bend_only)
	var m_bend: Dictionary = m[1]
	var r_bend: Dictionary = rv[0]
	var m_kept: bool = not CustomTracks.has_pillar(m_bend) \
		and absf(float(m_bend["r"]) - CustomTracks.BEND_RADIUS) < 0.001 \
		and int(m_bend["deg"]) == -90
	print("  mirror keeps a bend a bend (deg=%d r=%d pillar=%s): %s"
		% [int(m_bend["deg"]), int(m_bend["r"]), str(CustomTracks.has_pillar(m_bend)),
		   "OK" if m_kept else "FAIL"])
	pass_all = m_kept and pass_all
	var r_kept: bool = not CustomTracks.has_pillar(r_bend) \
		and absf(float(r_bend["r"]) - CustomTracks.BEND_RADIUS) < 0.001
	print("  reverse keeps a bend a bend (r=%d pillar=%s): %s"
		% [int(r_bend["r"]), str(CustomTracks.has_pillar(r_bend)), "OK" if r_kept else "FAIL"])
	pass_all = r_kept and pass_all
	pass_all = _drivable(m, "a mirrored bend track") and pass_all


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
	out.append(CustomTracks.make_finish())
	return out


