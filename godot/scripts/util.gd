extends RefCounted
class_name U

const TAU := PI * 2.0


static func clampf(v: float, a: float, b: float) -> float:
	return a if v < a else (b if v > b else v)


# Shortest signed angle from a to b, in (-PI, PI].
static func ang_diff(a: float, b: float) -> float:
	var d := fmod(b - a, TAU)
	if d > PI:
		d -= TAU
	if d <= -PI:
		d += TAU
	return d


static func dist(ax: float, ay: float, bx: float, by: float) -> float:
	return sqrt((bx - ax) * (bx - ax) + (by - ay) * (by - ay))


# 32-bit multiply, the way JS Math.imul does it. GDScript ints are 64-bit, so the
# product is masked down to 32 bits.
static func imul32(x: int, y: int) -> int:
	return (x * y) & 0xFFFFFFFF


# Deterministic PRNG, bit-for-bit the same as the JS mulberry32, so a track is the
# same road in both builds. Values are kept unsigned 32-bit throughout, which makes
# GDScript's logical >> match JS's >>>.
static func mulberry32(seed_val: int) -> Callable:
	var st := [seed_val & 0xFFFFFFFF]
	return func() -> float:
		var a: int = st[0]
		a = (a + 0x6D2B79F5) & 0xFFFFFFFF
		var t: int = imul32(a ^ (a >> 15), 1 | a)
		t = ((t + imul32(t ^ (t >> 7), 61 | t)) & 0xFFFFFFFF) ^ t
		t = t & 0xFFFFFFFF
		return float((t ^ (t >> 14)) & 0xFFFFFFFF) / 4294967296.0
