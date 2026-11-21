extends Control
class_name TrackMap

# A tiny top-down map of a real Track, used by the Play track cards. It is a
# centreline, not the full road band: at 60px tall the band would be a blob, and
# the shape is what tells one track from another.

var track: Track = null

var line_color := UiTheme.INK
var under_color := UiTheme.CARD_SUNK
var start_color := UiTheme.ACCENT
var finish_color := UiTheme.INK_MUTE


func _ready() -> void:
        mouse_filter = Control.MOUSE_FILTER_IGNORE
        clip_contents = true


func set_track(t: Track) -> void:
        track = t
        queue_redraw()


func _draw() -> void:
        if track == null or track.road.size() < 2 or size.x <= 4.0 or size.y <= 4.0:
                return
        var lo := Vector2(INF, INF)
        var hi := Vector2(-INF, -INF)
        for p in track.road:
                var v: Vector2 = p
                lo = lo.min(v)
                hi = hi.max(v)
        var span := hi - lo
        if span.x <= 0.01 or span.y <= 0.01:
                return
        var pad := 7.0
        var scale := minf((size.x - pad * 2.0) / span.x, (size.y - pad * 2.0) / span.y)
        var offset := (size - span * scale) * 0.5 - lo * scale
        var pts := PackedVector2Array()
        for p in track.road:
                pts.append((p as Vector2) * scale + offset)
        draw_polyline(pts, under_color, 7.0, true)
        draw_polyline(pts, line_color, 2.0, true)
        draw_circle(pts[0], 3.0, start_color)
        draw_circle(pts[pts.size() - 1], 2.5, finish_color)
