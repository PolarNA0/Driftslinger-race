extends SceneTree

# Headless parity check: same scripted input as tools/_parity.mjs in the JS repo,
# so the two builds can be compared number for number.

func _init() -> void:
	var opts := Tracks.track_opts(1)
	var t := Track.new(1, opts)
	var car := Car.new()
	car.reset(t)
	var dt := Cfg.DT
	var steps := 0
	while car.alive and not car.finished and steps < 12000:
		var phase := int(floor(float(steps) * dt / 0.35)) % 2 == 0
		car.step(dt, phase)
		steps += 1
	print("SIM steps=%d time=%.6f x=%.6f y=%.6f angle=%.6f finished=%s dead=%s off=%.6f grabbed=%d"
		% [steps, car.time, car.x, car.y, car.angle, str(car.finished), str(car.dead), car.off, car.grabbed])
	quit()
