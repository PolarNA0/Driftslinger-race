extends RefCounted
class_name UiTheme

# The game's look, in one place. A single Theme is applied to the whole UI tree,
# so nothing falls back to the engine's default grey buttons and black panels.
#
# The palette is deliberately dark-with-warm-accent: the shell has to read on top
# of every road theme (one road is near-white, one is near-black), so the panels
# are deep navy, the text is near-white, and the accent is a warm gold that does
# not collide with any of the road colours.

const INK := Color("eef1ff")          # primary text
const INK_DIM := Color("a3abd6")      # secondary text / hints
const INK_MUTE := Color("6f77a0")     # the quietest text
const PANEL := Color("151a30")        # overlay card fill
const PANEL_EDGE := Color("39427a")   # overlay card border
const PANEL_SHADOW := Color("05070f")
const ACCENT := Color("ffc94d")       # warm gold: primary actions, selection
const ACCENT_TEXT := Color("201a08")  # text on top of the accent
const BTN := Color("222949")
const BTN_HOVER := Color("2d3766")
const BTN_DOWN := Color("3c4884")
const BTN_EDGE := Color("434d88")
const DISABLED_BG := Color("171b2c")
const DISABLED_EDGE := Color("262c47")
const DANGER := Color("ff7b7b")

# The full-screen app shell. The whole window is the app now, not a card floating
# over the road, so these carry the chrome: BG is the page, BAR is the top and
# bottom rails, SURFACE is the content sheet between them.
const BG := Color("0a0e1c")
const BAR := Color("101531")
const BAR_EDGE := Color("232b52")
const SURFACE := Color("141a30")
const SURFACE_EDGE := Color("2b3462")
const TAB_IDLE := Color("8f98c8")


static func _flat(bg: Color, edge: Color, radius: int, border: int, pad_h: int, pad_v: int) -> StyleBoxFlat:
        var s := StyleBoxFlat.new()
        s.bg_color = bg
        s.border_color = edge
        s.set_border_width_all(border)
        s.set_corner_radius_all(radius)
        s.content_margin_left = pad_h
        s.content_margin_right = pad_h
        s.content_margin_top = pad_v
        s.content_margin_bottom = pad_v
        s.anti_aliasing = true
        return s


static func _button_styles(t: Theme, type_name: String, base_bg: Color, base_edge: Color,
                text: Color, radius: int = 12) -> void:
        t.set_stylebox("normal", type_name, _flat(base_bg, base_edge, radius, 2, 16, 12))
        t.set_stylebox("hover", type_name, _flat(base_bg.lightened(0.10), base_edge.lightened(0.12), radius, 2, 16, 12))
        t.set_stylebox("pressed", type_name, _flat(base_bg.lightened(0.20), base_edge.lightened(0.24), radius, 2, 16, 12))
        t.set_stylebox("hover_pressed", type_name, _flat(base_bg.lightened(0.20), base_edge.lightened(0.24), radius, 2, 16, 12))
        t.set_stylebox("focus", type_name, _flat(Color(0, 0, 0, 0), ACCENT, radius, 2, 16, 12))
        t.set_stylebox("disabled", type_name, _flat(DISABLED_BG, DISABLED_EDGE, radius, 2, 16, 12))
        t.set_color("font_color", type_name, text)
        t.set_color("font_hover_color", type_name, text)
        t.set_color("font_pressed_color", type_name, text)
        t.set_color("font_focus_color", type_name, text)
        t.set_color("font_disabled_color", type_name, INK_MUTE)
        t.set_font_size("font_size", type_name, 16)
        t.set_constant("outline_size", type_name, 0)
        t.set_constant("h_separation", type_name, 8)


static func build() -> Theme:
        var t := Theme.new()
        t.default_font_size = 16

        # --- Buttons: a rounded slate chip; the accent variation is the primary ---
        _button_styles(t, "Button", BTN, BTN_EDGE, INK)

        t.set_type_variation("PrimaryButton", "Button")
        _button_styles(t, "PrimaryButton", ACCENT, ACCENT.lightened(0.15), ACCENT_TEXT)

        # A "ghost" button for secondary actions (Back, Exit, the top-corner icons).
        t.set_type_variation("GhostButton", "Button")
        _button_styles(t, "GhostButton", Color(0.09, 0.11, 0.20, 0.72), BTN_EDGE.darkened(0.25), INK_DIM)

        # Toggle chips (mode / ghost / track / car pickers). The pressed look is the
        # accent, so the current choice is unmistakable.
        t.set_type_variation("ToggleButton", "Button")
        _button_styles(t, "ToggleButton", BTN, BTN_EDGE, INK)
        t.set_stylebox("pressed", "ToggleButton", _flat(ACCENT, ACCENT.lightened(0.15), 12, 2, 16, 12))
        t.set_stylebox("hover_pressed", "ToggleButton", _flat(ACCENT, ACCENT.lightened(0.15), 12, 2, 16, 12))
        t.set_color("font_pressed_color", "ToggleButton", ACCENT_TEXT)
        t.set_color("font_hover_pressed_color", "ToggleButton", ACCENT_TEXT)

        # --- Panels: the overlay cards and the watch badge ---
        var panel := _flat(PANEL, PANEL_EDGE, 20, 2, 20, 18)
        panel.shadow_color = Color(PANEL_SHADOW.r, PANEL_SHADOW.g, PANEL_SHADOW.b, 0.55)
        panel.shadow_size = 18
        panel.shadow_offset = Vector2(0, 8)
        t.set_stylebox("panel", "PanelContainer", panel)

        var flat_panel := _flat(PANEL, PANEL_EDGE, 16, 2, 14, 10)
        t.set_stylebox("panel", "Panel", flat_panel)

        # --- The app shell: page background, top/bottom rails, content sheet ---
        var shell := _flat(BG, BG, 0, 0, 0, 0)
        t.set_type_variation("ShellBg", "Panel")
        t.set_stylebox("panel", "ShellBg", shell)

        # A rail is a flat bar with a single hairline on the inner edge, so the top
        # and bottom bars read as chrome rather than as two more cards.
        var top_bar := _flat(BAR, BAR, 0, 0, 0, 0)
        top_bar.border_width_bottom = 1
        top_bar.border_color = BAR_EDGE
        t.set_type_variation("TopBar", "Panel")
        t.set_stylebox("panel", "TopBar", top_bar)

        var bottom_bar := _flat(BAR, BAR, 0, 0, 0, 0)
        bottom_bar.border_width_top = 1
        bottom_bar.border_color = BAR_EDGE
        t.set_type_variation("BottomBar", "Panel")
        t.set_stylebox("panel", "BottomBar", bottom_bar)

        # The content sheet: the surface the tabs' controls sit on. A soft edge, no
        # heavy shadow - it fills the space between the rails, it does not float.
        t.set_type_variation("Surface", "PanelContainer")
        t.set_stylebox("panel", "Surface", _flat(SURFACE, SURFACE_EDGE, 18, 2, 16, 14))

        # A quiet surface for grouping a few rows inside the sheet.
        t.set_type_variation("SubCard", "PanelContainer")
        t.set_stylebox("panel", "SubCard", _flat(Color("1a2140"), SURFACE_EDGE.darkened(0.18), 14, 1, 14, 12))

        # --- Tab buttons: icon over label, the active one accent-lit ---
        t.set_type_variation("TabButton", "Button")
        var tab_off := _flat(Color(0, 0, 0, 0), Color(0, 0, 0, 0), 12, 0, 6, 8)
        var tab_on := _flat(Color(ACCENT.r, ACCENT.g, ACCENT.b, 0.16), Color(0, 0, 0, 0), 12, 0, 6, 8)
        t.set_stylebox("normal", "TabButton", tab_off)
        t.set_stylebox("hover", "TabButton", _flat(Color(1, 1, 1, 0.05), Color(0, 0, 0, 0), 12, 0, 6, 8))
        t.set_stylebox("pressed", "TabButton", tab_on)
        t.set_stylebox("hover_pressed", "TabButton", tab_on)
        t.set_stylebox("focus", "TabButton", _flat(Color(0, 0, 0, 0), Color(0, 0, 0, 0), 12, 0, 6, 8))
        t.set_stylebox("disabled", "TabButton", tab_off)
        t.set_color("font_color", "TabButton", TAB_IDLE)
        t.set_color("font_hover_color", "TabButton", INK)
        t.set_color("font_pressed_color", "TabButton", ACCENT)
        t.set_color("font_hover_pressed_color", "TabButton", ACCENT)
        t.set_color("font_disabled_color", "TabButton", INK_MUTE)
        t.set_font_size("font_size", "TabButton", 13)

        # --- A round icon chip for the top bar (settings, back, close) ---
        t.set_type_variation("IconButton", "Button")
        _button_styles(t, "IconButton", Color(0, 0, 0, 0), Color(0, 0, 0, 0), INK_DIM, 10)
        t.set_stylebox("hover", "IconButton", _flat(Color(1, 1, 1, 0.07), Color(0, 0, 0, 0), 10, 0, 0, 0))
        t.set_stylebox("pressed", "IconButton", _flat(Color(1, 1, 1, 0.12), Color(0, 0, 0, 0), 10, 0, 0, 0))
        t.set_stylebox("hover_pressed", "IconButton", _flat(Color(1, 1, 1, 0.12), Color(0, 0, 0, 0), 10, 0, 0, 0))

        # --- Labels ---
        t.set_color("font_color", "Label", INK)
        t.set_font_size("font_size", "Label", 16)
        t.set_constant("outline_size", "Label", 0)
        t.set_color("font_outline_color", "Label", Color(0, 0, 0, 0.85))

        # --- Text fields ---
        t.set_stylebox("normal", "LineEdit", _flat(Color("0e1224"), BTN_EDGE.darkened(0.15), 12, 2, 14, 12))
        t.set_stylebox("focus", "LineEdit", _flat(Color("101530"), ACCENT, 12, 2, 14, 12))
        t.set_stylebox("read_only", "LineEdit", _flat(DISABLED_BG, DISABLED_EDGE, 12, 2, 14, 12))
        t.set_color("font_color", "LineEdit", INK)
        t.set_color("font_placeholder_color", "LineEdit", INK_MUTE)
        t.set_color("font_selected_color", "LineEdit", Color("ffffff"))
        t.set_color("caret_color", "LineEdit", ACCENT)
        t.set_color("selection_color", "LineEdit", Color(ACCENT.r, ACCENT.g, ACCENT.b, 0.35))
        t.set_font_size("font_size", "LineEdit", 16)
        t.set_constant("caret_width", "LineEdit", 2)
        t.set_constant("minimum_character_width", "LineEdit", 6)

        # --- Scrollbars: slim and unobtrusive ---
        t.set_stylebox("scroll", "VScrollBar", _flat(Color(0, 0, 0, 0), Color(0, 0, 0, 0), 6, 0, 0, 0))
        var grabber := _flat(PANEL_EDGE, PANEL_EDGE, 6, 0, 0, 0)
        grabber.corner_radius_top_left = 6
        t.set_stylebox("grabber", "VScrollBar", grabber)
        t.set_stylebox("grabber_highlight", "VScrollBar", _flat(ACCENT, ACCENT, 6, 0, 0, 0))
        t.set_stylebox("grabber_pressed", "VScrollBar", _flat(ACCENT, ACCENT, 6, 0, 0, 0))
        t.set_constant("minimum_grab_thickness", "VScrollBar", 10)
        t.set_constant("scroll_width", "VScrollBar", 10)

        return t
