extends SceneTree

# Headless check: build the twenty tracks in GDScript and print their geometry,
# so the port can be compared against the JS build. Run with:
#   godot --headless --script res://tools/verify.gd


func _init() -> void:
	print("== sling drift (godot) track geometry ==")
	var total_time := 0.0
	for n in range(1, 21):
		var opts := Tracks.track_opts(n)
		var t := Track.new(n, opts)
		var start_s := Cfg.SPEEDRUN_START_FRAC * float(opts["lead_in"])
		var clean := (t.finish_s - start_s) / Cfg.SPEED
		total_time += clean
		print("track %2d  r=%.0f  corners=%d  length=%.1f  finishS=%.1f  clean=%.4fs  target=%.1fs"
			% [n, float(opts["radius"]), int(opts["corners"]), t.length, t.finish_s, clean, float(opts["target_time"])])
	print("mean clean time = %.4fs" % (total_time / 20.0))
	quit()
