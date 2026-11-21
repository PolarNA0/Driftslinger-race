extends Control
class_name MedalIcon

# A tiny drawn medal for a track chip. It is geometry, not a glyph: the theme
# font has no medal characters (the same trap the restart arrow hit). It draws
# nothing when the player has no medal, so a chip does not reserve space for one.

var medal := "":
        set(value):
                medal = value
                queue_redraw()


func _ready() -> void:
        mouse_filter = Control.MOUSE_FILTER_IGNORE


func _draw() -> void:
        if medal == "":
                return
        var centre := size * 0.5
        var radius := minf(size.x, size.y) * 0.5
        draw_circle(centre, radius, Medals.color(medal))
        draw_arc(centre, maxf(radius - 1.0, 0.5), 0.0, TAU, 16, Color(0, 0, 0, 0.35), 1.0, true)
