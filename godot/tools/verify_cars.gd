extends SceneTree

# The Garage promises "pick the one you like", and the renderer draws every car
# from a sprite in `Renderer2D.CAR_MODELS`. This guards both halves of that: each
# model names its own texture, and each texture is a real, loadable image. It is
# the check that a car is not silently drawn as a placeholder or a repeat.

func _initialize() -> void:
	var renderer := Renderer2D.new()
	var seen := {}
	var failures := 0
	for model in renderer.CAR_MODELS:
		var name := str(model["name"])
		var path := str(model["tex"])
		if path == "":
			print("  FAIL %s has no texture" % name)
			failures += 1
			continue
		if seen.has(path):
			print("  FAIL %s reuses %s (already used by %s)" % [name, path, seen[path]])
			failures += 1
		seen[path] = name
		var tex := load(path) as Texture2D
		if tex == null:
			print("  FAIL %s texture did not load: %s" % [name, path])
			failures += 1
			continue
		var size := tex.get_size()
		if size.x < 8.0 or size.y < 8.0:
			print("  FAIL %s texture is tiny: %s" % [name, size])
			failures += 1
		print("%-9s %s  %dx%d" % [name, path.get_file(), int(size.x), int(size.y)])
	renderer.free()
	if failures == 0:
		print("CARS PASS (%d models, all distinct)" % seen.size())
	else:
		print("CARS FAIL: %d problem(s)" % failures)
	quit(1 if failures > 0 else 0)
