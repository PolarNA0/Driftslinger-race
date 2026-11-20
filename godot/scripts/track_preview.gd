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

# Two-finger pinch is tracked from the raw touches. Godot's `InputEventMagnifyGesture`
# only exists when `input_devices/pointing/android/enable_pan_and_scale_gestures` is
# on, which it is not (and the web build never emits it), so relying on it alone left
# pinch dead everywhere. Touch events are always delivered, so they drive it.
var _touches := {}              # touch index -> current position
var _last_pos := {}             # touch index -> position at the previous drag event
var _pinch_dist := 0.0
var _pinching := false
var _pinch_zoom := 1.0          # zoom when the pinch began
var _pinch_mid := Vector2.ZERO  # midpoint when the pinch began
var _pinch_world := Vector2.ZERO  # world point under that midpoint

# Placement mode. While a palette piece is armed, a tap on the grid appends that piece
# and reports the grid cell it landed on, instead of picking an existing piece.
signal cell_tapped(cell: Vector2i)
var armed: Callable = Callable()
var show_grid := false

# The live session's colours, set by the editor so the map paints the track's own
# palette. `theme_of` reads them through `_entry`.
var palette := {"road": "", "ground": ""}

const PAD := 20.0
const MIN_ZOOM := 0.05
const MAX_ZOOM := 6.0
const WHEEL_STEP := 1.15
# One grid cell in world pixels. The editor snaps placement to this so a tap lands on
# a cell rather than an arbitrary point.
const CELL := 80.0
const TAP_SLOP := 10.0
# Pan gain. One finger of travel moves the map one design pixel, which is what the
# finger appears to grab; the map is not a slider and does not need a multiplier.
const PAN_GAIN := 1.0


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
                if CustomTracks.is_finish(p):
                        # The finish piece is the closing straight: its span runs to the
                        # finish line, which is where the builder put it.
                        ln = maxf(0.0, _finish_s - s)
                elif CustomTracks.is_corner(p):
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


# A finger drag arrives twice: once as a touch event and once as an emulated mouse
# event (`input_devices/pointing/emulate_mouse_from_touch` is on by default and
# Android/iOS need it). Handling both panned the map at double speed, which is the
# "super sensitive" drag. Emulated events carry DEVICE_ID_EMULATION, so they are
# ignored here and the touch events do the work. A real mouse is not emulated, so
# the wheel, drag and click still work on desktop.
func _gui_input(event: InputEvent) -> void:
        if event is InputEventMouseButton:
                var mb := event as InputEventMouseButton
                if mb.device == InputEvent.DEVICE_ID_EMULATION:
                        return
                if mb.button_index == MOUSE_BUTTON_WHEEL_UP and mb.pressed:
                        _zoom_at(mb.position, WHEEL_STEP)
                elif mb.button_index == MOUSE_BUTTON_WHEEL_DOWN and mb.pressed:
                        _zoom_at(mb.position, 1.0 / WHEEL_STEP)
                elif mb.button_index == MOUSE_BUTTON_LEFT:
                        if mb.pressed:
                                _dragging = true
                                _drag_moved = 0.0
                        else:
                                _dragging = false
                                if _drag_moved < 6.0:
                                        _tap(mb.position)
        elif event is InputEventMouseMotion:
                var mm := event as InputEventMouseMotion
                if mm.device == InputEvent.DEVICE_ID_EMULATION or not _dragging:
                        return
                _drag_moved += mm.relative.length()
                pan_by(mm.relative)
        elif event is InputEventScreenTouch:
                _on_touch(event as InputEventScreenTouch)
        elif event is InputEventScreenDrag:
                _on_touch_drag(event as InputEventScreenDrag)
        # Kept for desktop trackpads and for a build that turns the gesture on. Phones
        # go through the two-touch path above, because this event does not exist there.
        elif event is InputEventMagnifyGesture:
                var mg := event as InputEventMagnifyGesture
                _zoom_at(mg.position, mg.factor)
                accept_event()


# --- touch: one finger pans, two fingers pinch -------------------------------
#
# Panning used to read every touch independently, so two fingers down meant two pans
# applied at once - a pinch dragged the map sideways at double speed and then fired a
# stray tap on release. Both are handled here: while a second finger is down the map
# never pans, and a release never taps unless the finger barely moved and was alone.

func _on_touch(st: InputEventScreenTouch) -> void:
        if st.pressed:
                _touches[st.index] = st.position
                _last_pos[st.index] = st.position
                if _touches.size() == 1:
                        _dragging = true
                        _drag_moved = 0.0
                elif _touches.size() == 2:
                        # A second finger turns this into a pinch: no pan, no tap. The
                        # gesture is measured from the state at this moment and never
                        # accumulated, so a wobble cannot drift the map.
                        _pinching = true
                        _dragging = false
                        _pinch_dist = _touch_span()
                        _pinch_zoom = _zoom
                        _pinch_mid = _touch_mid()
                        _pinch_world = screen_to_world(_pinch_mid)
        else:
                var was_alone := _touches.size() == 1
                _touches.erase(st.index)
                _last_pos.erase(st.index)
                if _touches.size() < 2:
                        _pinching = false
                        _pinch_dist = 0.0
                if _touches.is_empty():
                        _dragging = false
                        if was_alone and _drag_moved < TAP_SLOP:
                                _tap(st.position)
                else:
                        # The remaining finger continues as a pan from where it is, with
                        # its travel reset so lifting the pinch finger does not jump.
                        _dragging = true
                        _drag_moved = TAP_SLOP


# Pan is measured from the finger's own position, not from the event's `relative`.
# `relative` is scaled by whatever transform the platform applied to the event, and a
# build that scales `position` but not `relative` (or that delivers a drag twice) pans
# at a multiple of the finger's travel - the "WAY too sensitive" map. `position` is the
# field tap picking already trusts, so a pan derived from it moves exactly as far as
# the finger did, on every platform.
func _on_touch_drag(sd: InputEventScreenDrag) -> void:
        if not _touches.has(sd.index):
                return
        _touches[sd.index] = sd.position
        if _pinching and _touches.size() >= 2:
                var span := _touch_span()
                if _pinch_dist > 1.0 and span > 1.0:
                        # Absolute from the gesture's start: zoom = start * span ratio.
                        # Accumulating per-event ratios compounds rounding and makes the
                        # map twitch as the fingers wobble.
                        _zoom = clampf(_pinch_zoom * (span / _pinch_dist), MIN_ZOOM, MAX_ZOOM)
                        # Keep the world point that was under the midpoint under the
                        # midpoint, wherever the fingers have moved to.
                        var mid := _touch_mid()
                        _origin = mid - _pinch_world * _zoom
                        queue_redraw()
                # Track the fingers through the pinch too. Lifting one of them leaves the
                # other panning, and it pans from `_last_pos`; a stale entry there is the
                # whole distance the finger travelled during the pinch, which lands as a
                # jump the instant the second finger comes up.
                for k in _touches.keys():
                        _last_pos[k] = _touches[k]
                return
        if _touches.size() == 1:
                var last: Vector2 = _last_pos.get(sd.index, sd.position)
                var delta := sd.position - last
                _drag_moved += delta.length()
                pan_by(delta * PAN_GAIN)
        _last_pos[sd.index] = sd.position


# Distance between the first two fingers, in screen pixels.
func _touch_span() -> float:
        var pts := _touches.values()
        if pts.size() < 2:
                return 0.0
        return (pts[0] as Vector2).distance_to(pts[1] as Vector2)


# The point between the first two fingers: the pinch anchor, so the spot under the
# fingers stays put while the zoom changes.
func _touch_mid() -> Vector2:
        var pts := _touches.values()
        if pts.size() < 2:
                return size * 0.5
        return ((pts[0] as Vector2) + (pts[1] as Vector2)) * 0.5


func _tap(pos: Vector2) -> void:
        if armed.is_valid():
                cell_tapped.emit(world_to_cell(screen_to_world(pos)))
                return
        var i := pick_at(pos)
        if i >= 0:
                piece_picked.emit(i)


# --- grid --------------------------------------------------------------------

func world_to_cell(w: Vector2) -> Vector2i:
        return Vector2i(floori(w.x / CELL), floori(w.y / CELL))


func cell_to_world(c: Vector2i) -> Vector2:
        return Vector2(float(c.x) * CELL, float(c.y) * CELL)


# Where the road ends right now - the point a newly placed piece grows from. The
# op list is continuous, so this is also the only place a piece can start.
func op_end_world() -> Vector2:
        if _road.size() < 2:
                return Vector2.ZERO
        return _road[_road.size() - 1]


# Where a piece appended after the first `count` pieces would start. A piece goes in
# front of the finish line, so the growth point is the end of the piece before it, not
# the end of the road.
func growth_point(count: int) -> Vector2:
        if _track == null or count <= 0:
                return _start_world()
        var s := CustomTracks.LEAD_IN
        for i in range(mini(count, _spans.size())):
                s = float(_spans[i]["s1"])
        var p := _track.point_at(s)
        return Vector2(float(p["x"]), float(p["y"]))


# The start of the road, where the first piece grows from.
func _start_world() -> Vector2:
        if _track == null:
                return Vector2.ZERO
        var p := _track.point_at(CustomTracks.LEAD_IN)
        return Vector2(float(p["x"]), float(p["y"]))


# The grid line nearest a screen point, snapped in world space so it lines up with the
# road at every zoom.
func _draw_grid() -> void:
        var w0 := screen_to_world(Vector2.ZERO)
        var w1 := screen_to_world(size)
        var c0 := world_to_cell(w0) - Vector2i.ONE
        var c1 := world_to_cell(w1) + Vector2i.ONE
        var line := Color(UiTheme.INK, 0.07)
        for cx in range(c0.x, c1.x + 1):
                var x := float(cx) * CELL
                var a := world_to_screen(Vector2(x, w0.y))
                var b := world_to_screen(Vector2(x, w1.y))
                draw_line(a, b, line, 1.0)
        for cy in range(c0.y, c1.y + 1):
                var y := float(cy) * CELL
                var a := world_to_screen(Vector2(w0.x, y))
                var b := world_to_screen(Vector2(w1.x, y))
                draw_line(a, b, line, 1.0)


# --- draw --------------------------------------------------------------------

func _draw() -> void:
        var w := size.x
        var h := size.y
        draw_rect(Rect2(Vector2.ZERO, size), UiTheme.BG)
        if show_grid:
                _draw_grid()
        if not ok or _road.size() < 2:
                var f := ThemeDB.fallback_font
                var msg := error if error != "" else "Pick a piece below, then tap the grid."
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
        _finish_bar()


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


# The finish line: a chequered bar across the road, which is what the player drives
# over. Two rows of alternating squares read as a finish line at any zoom.
func _finish_bar() -> void:
        if _track == null or _road.size() < 2:
                return
        var p := _track.point_at(_finish_s)
        var at := Vector2(float(p["x"]), float(p["y"]))
        var n := _road_normal(_finish_s) * Cfg.ROAD_HALF_WIDTH
        var a := world_to_screen(at - n)
        var b := world_to_screen(at + n)
        var d := b - a
        var l := d.length()
        if l < 1.0:
                return
        var u := d / l
        var v := Vector2(-u.y, u.x)
        var cells := 8
        var step := l / float(cells)
        var depth := clampf(Cfg.ROAD_HALF_WIDTH * _zoom * 0.45, 3.0, 14.0)
        for row in range(2):
                for i in range(cells):
                        var col := Color8(250, 250, 250) if (i + row) % 2 == 0 else Color8(26, 26, 26)
                        var o := a + u * (step * float(i)) + v * (depth * float(row))
                        draw_colored_polygon(PackedVector2Array([
                                o, o + u * step, o + u * step + v * depth, o + v * depth]), col)


# The road's unit normal at a road distance, for drawing across the ribbon.
func _road_normal(s: float) -> Vector2:
        if _track == null:
                return Vector2.UP
        var a := _track.point_at(maxf(0.0, s - 4.0))
        var b := _track.point_at(minf(_track.length, s + 4.0))
        var d := Vector2(float(b["x"]) - float(a["x"]), float(b["y"]) - float(a["y"]))
        if d.length() < 0.001:
                return Vector2.UP
        d = d.normalized()
        return Vector2(-d.y, d.x)
