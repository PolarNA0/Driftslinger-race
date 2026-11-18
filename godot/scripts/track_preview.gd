extends Control
class_name TrackPreview

# The editor's map: a top-down view of the whole road with a camera, so a long
# track can be inspected piece by piece instead of squashed to fit.
#
# It builds a real `Track` from the ops, so what is previewed is exactly the road
# the game will drive, including the lead-in and the closing straight. The camera
# is pan/zoom (`fit`, `zoom_by`, `pan_by`, `focus_index`) and a tap on a piece
# selects it (`piece_picked`), which is what makes the map an editing surface
# rather than a picture.

signal piece_picked(index: int)

var ops: Array = []
var ok := false
var error := ""

var selected := -1

var _track: Track = null
var _road: Array = []
var _finish_s := 0.0
var _spans: Array = []          # {op, s0, s1, cx, cy} per piece, in op order
var _poles: Array = []          # {op, x, y} per corner

var _zoom := 1.0
var _origin := Vector2.ZERO
var _dragging := false
var _drag_moved := 0.0

# The live session's colours, set by the editor so the map paints the track's own
# palette. `theme_of` reads them through `_entry`.
var palette := {"road": "", "ground": ""}

const PAD := 20.0
const MIN_ZOOM := 0.05
const MAX_ZOOM := 6.0


func _ready() -> void:
        mouse_filter = Control.MOUSE_FILTER_STOP
        clip_contents = true


func rebuild(p_ops: Array) -> void:
        ops = p_ops.duplicate(true)
        var v := CustomTracks.validate(ops)
        ok = bool(v["ok"])
        error = str(v["error"])
        _track = null
        _road = []
        _finish_s = 0.0
        _spans = []
        _poles = []
        if ok:
                _track = Track.new(0, CustomTracks.opts(ops))
                _road = _track.road
                _finish_s = _track.finish_s
                _collect()
        queue_redraw()


# Piece spans, computed the same way `Track.build_ops` walks the list (lead-in
# first, then one span per op), so a tap on the map can name the piece under it.
func _collect() -> void:
        var s := CustomTracks.LEAD_IN
        for i in range(ops.size()):
                var p: Dictionary = ops[i]
                var ln := 0.0
                if CustomTracks.is_corner(p):
                        ln = float(p["r"]) * absf(deg_to_rad(float(p["deg"])))
                        var f: Dictionary = _track.fillets[_poles.size()]
                        _poles.append({"op": i, "x": f["c"].x, "y": f["c"].y})
                else:
                        ln = float(p["len"])
                var mid := _track.point_at(s + ln * 0.5)
                _spans.append({"op": i, "s0": s, "s1": s + ln, "cx": float(mid["x"]), "cy": float(mid["y"])})
                s += ln


# --- camera ------------------------------------------------------------------

func fit() -> void:
        if _road.size() < 2:
                return
        var minx := INF
        var miny := INF
        var maxx := -INF
        var maxy := -INF
        for p in _road:
                minx = minf(minx, p.x)
                miny = minf(miny, p.y)
                maxx = maxf(maxx, p.x)
                maxy = maxf(maxy, p.y)
        var spanx := maxf(1.0, maxx - minx)
        var spany := maxf(1.0, maxy - miny)
        var z := minf((size.x - PAD * 2.0) / spanx, (size.y - PAD * 2.0) / spany)
        _zoom = clampf(z, MIN_ZOOM, MAX_ZOOM)
        var cx := (minx + maxx) * 0.5
        var cy := (miny + maxy) * 0.5
        _origin = size * 0.5 - Vector2(cx, cy) * _zoom
        queue_redraw()


func focus_index(index: int) -> void:
        var sp := _span(index)
        if sp.is_empty():
                return
        var w := Vector2(float(sp["cx"]), float(sp["cy"]))
        _origin = size * 0.5 - w * _zoom
        queue_redraw()


func zoom_by(factor: float) -> void:
        _zoom_at(size * 0.5, factor)


func _zoom_at(anchor: Vector2, factor: float) -> void:
        var before := screen_to_world(anchor)
        _zoom = clampf(_zoom * factor, MIN_ZOOM, MAX_ZOOM)
        var after := screen_to_world(anchor)
        _origin += (after - before) * _zoom
        queue_redraw()


func pan_by(delta: Vector2) -> void:
        _origin += delta
        queue_redraw()


func world_to_screen(p: Vector2) -> Vector2:
        return p * _zoom + _origin


func screen_to_world(p: Vector2) -> Vector2:
        return (p - _origin) / _zoom


func _span(index: int) -> Dictionary:
        for sp in _spans:
                if int(sp["op"]) == index:
                        return sp
        return {}


# --- picking -----------------------------------------------------------------

# The piece whose stretch of road is nearest the given screen point, or -1.
func pick_at(pos: Vector2) -> int:
        if _road.size() < 2 or _spans.is_empty():
                return -1
        var w := screen_to_world(pos)
        var best := INF
        var best_i := 0
        for i in range(_road.size()):
                var d := (_road[i] as Vector2).distance_squared_to(w)
                if d < best:
                        best = d
                        best_i = i
        var best_s := float(_track.rs[best_i])
        for sp in _spans:
                if best_s >= float(sp["s0"]) - 0.001 and best_s <= float(sp["s1"]) + 0.001:
                        return int(sp["op"])
        return -1


func _gui_input(event: InputEvent) -> void:
        if event is InputEventMouseButton:
                var mb := event as InputEventMouseButton
                if mb.button_index == MOUSE_BUTTON_WHEEL_UP and mb.pressed:
                        _zoom_at(mb.position, 1.15)
                elif mb.button_index == MOUSE_BUTTON_WHEEL_DOWN and mb.pressed:
                        _zoom_at(mb.position, 1.0 / 1.15)
                elif mb.button_index == MOUSE_BUTTON_LEFT:
                        if mb.pressed:
                                _dragging = true
                                _drag_moved = 0.0
                        else:
                                _dragging = false
                                if _drag_moved < 6.0:
                                        _tap(mb.position)
        elif event is InputEventMouseMotion and _dragging:
                var mm := event as InputEventMouseMotion
                _drag_moved += mm.relative.length()
                pan_by(mm.relative)
        elif event is InputEventScreenTouch:
                var st := event as InputEventScreenTouch
                if st.pressed:
                        _dragging = true
                        _drag_moved = 0.0
                else:
                        _dragging = false
                        if _drag_moved < 8.0:
                                _tap(st.position)
        elif event is InputEventScreenDrag:
                var sd := event as InputEventScreenDrag
                _drag_moved += sd.relative.length()
                pan_by(sd.relative)


func _tap(pos: Vector2) -> void:
        var i := pick_at(pos)
        if i >= 0:
                piece_picked.emit(i)


# --- draw --------------------------------------------------------------------

func _draw() -> void:
        var w := size.x
        var h := size.y
        draw_rect(Rect2(Vector2.ZERO, size), UiTheme.BG)
        if not ok or _road.size() < 2:
                var f := ThemeDB.fallback_font
                var msg := error if error != "" else "Add a piece to see the road."
                draw_string(f, Vector2(12, h * 0.5), msg, HORIZONTAL_ALIGNMENT_CENTER, w - 24, 13, UiTheme.INK_MUTE)
                return

        var colors := CustomTracks.theme_colors(_entry())
        var ground: Color = colors["ground"]
        var road: Color = colors["road"]
        var stripe: Color = colors["stripe"]

        # Ground: a generous rect in the track's background colour, so the palette is
        # visible while editing.
        draw_rect(Rect2(Vector2.ZERO, size), ground)

        var hw := maxf(1.0, Cfg.ROAD_HALF_WIDTH * _zoom)
        _band(road, hw)
        _band(stripe, hw * 0.10)

        _draw_pieces(colors)
        _mark(0.0, Color8(90, 226, 120))
        _mark(_finish_s, Color8(244, 244, 244))


func _entry() -> Dictionary:
        return {"road": str(palette.get("road", "")), "ground": str(palette.get("ground", ""))}


func _band(fill: Color, hw: float) -> void:
        var pts := PackedVector2Array()
        for i in range(_road.size() - 1):
                var a: Vector2 = _road[i]
                var b: Vector2 = _road[i + 1]
                var d := b - a
                var l := d.length()
                if l == 0.0:
                        l = 1.0
                var n := Vector2(-d.y / l, d.x / l) * hw
                var pa := world_to_screen(a)
                var pb := world_to_screen(b)
                pts.append(pa + n)
                pts.append(pb + n)
                pts.append(pb - n)
                pts.append(pa + n)
                pts.append(pb - n)
                pts.append(pa - n)
        var cols := PackedColorArray()
        cols.resize(pts.size())
        cols.fill(fill)
        RenderingServer.canvas_item_add_triangle_array(get_canvas_item(), PackedInt32Array(), pts, cols)


func _draw_pieces(colors: Dictionary) -> void:
        var pole: Color = colors["pole"]
        var f := ThemeDB.fallback_font
        for sp in _spans:
                var is_sel := int(sp["op"]) == selected
                var mid := world_to_screen(Vector2(float(sp["cx"]), float(sp["cy"])))
                if is_sel:
                        draw_circle(mid, 9.0, Color(UiTheme.ACCENT, 0.35))
                        draw_arc(mid, 11.0, 0.0, TAU, 24, UiTheme.ACCENT, 2.0, true)
                if _zoom > 0.22:
                        var label := str(int(sp["op"]) + 1)
                        draw_string(f, mid + Vector2(-4, 4), label, HORIZONTAL_ALIGNMENT_LEFT, -1, 11, UiTheme.INK)
        for p in _poles:
                var c := world_to_screen(Vector2(float(p["x"]), float(p["y"])))
                var r := clampf(7.0 * _zoom, 2.0, 9.0)
                draw_circle(c, r, pole)
                if int(p["op"]) == selected:
                        draw_arc(c, r + 3.0, 0.0, TAU, 24, UiTheme.ACCENT, 2.0, true)


func _mark(s: float, c: Color) -> void:
        if _track == null:
                return
        var p := _track.point_at(s)
        draw_circle(world_to_screen(Vector2(float(p["x"]), float(p["y"]))), clampf(6.0 * _zoom, 3.0, 9.0), c)
