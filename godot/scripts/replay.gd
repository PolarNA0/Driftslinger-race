extends RefCounted
class_name Replay

# Port of the old js/replay.js (removed with the JS client). A replay is not positions - it is the button sequence, and
# the game re-simulates it. The physics is fixed-step and deterministic, so the
# same steps always give the same run. One bit per step.

static func encode_steps(steps: Array) -> String:
	var out := ""
	for h in steps:
		out += "1" if h else "0"
	return out


static func decode_steps(s: String) -> Array:
	var out := []
	for i in range(s.length()):
		out.append(s[i] == "1")
	return out


static func make_replay(track: int, steps: Array, time: float) -> Dictionary:
	return {"track": track, "time": time, "steps": encode_steps(steps)}
