extends Control
class_name RetryIcon

# A retry glyph drawn as geometry, not text.
#
# The button used to show the character U+21BB, but the theme's font (Open Sans
# SemiBold, the engine default) carries no rotation arrow, so it rendered as a
# missing-glyph box. Drawing the icon keeps it correct on every platform without
# shipping a font.

@export var color := Color(0.86, 0.90, 1.0)


func _draw() -> void:
	var r := minf(size.x, size.y) * 0.5
	var c := size * 0.5
	var rad := r * 0.60
	var w := maxf(2.0, r * 0.20)
	# A near-full ring, left open at the top-right where the arrowhead sits.
	var a0 := -PI * 0.42
	var a1 := PI * 1.30
	draw_arc(c, rad, a0, a1, 48, color, w, true)
	# Arrowhead on the open end, pointing along the sweep so it reads as a loop.
	var tip := c + Vector2(cos(a0), sin(a0)) * rad
	var tangent := Vector2(-sin(a0), cos(a0))
	var normal := Vector2(cos(a0), sin(a0))
	var s := w * 2.1
	draw_colored_polygon(PackedVector2Array([
		tip + tangent * s,
		tip - normal * s,
		tip + normal * s,
	]), color)
