extends RefCounted
class_name UiTheme

# The game's look, in one place. A single Theme is applied to the whole UI tree,
# so nothing falls back to the engine's default grey buttons and black panels.
#
# The direction is deliberately clean: a near-white page, white cards, near-black
# ink and one signal-red accent. The road and the car carry the colour; the menu
# stays neutral. There are no gradients, glass, grain or glow - a card is a card.

const INK := Color("111111")          # primary text
const INK_DIM := Color("5f5f5f")      # secondary text
const INK_MUTE := Color("686868")     # hints and labels (4.9:1 on CARD_SUNK)
const BG := Color("f6f6f4")           # page
const SURFACE := Color("ffffff")      # card
const CARD_SUNK := Color("f0f0ed")    # inset row / track chip
const SURFACE_EDGE := Color("e4e4e0") # 1px hairline
const PANEL := SURFACE
const PANEL_EDGE := SURFACE_EDGE
const PANEL_SHADOW := Color("111111")
const ACCENT := Color("c13526")       # signal red: primary action, active tab
const ACCENT_TEXT := Color("ffffff")
const BTN := SURFACE
const BTN_HOVER := Color("f7f7f5")
const BTN_DOWN := Color("efefec")
const BTN_EDGE := SURFACE_EDGE
const DISABLED_BG := Color("f0f0ed")
const DISABLED_EDGE := Color("e4e4e0")
const DANGER := Color("b23a2e")
const GOOD := Color("2e6b4f")
const MEDAL_GOLD := Color("b08a2e")
const MEDAL_SILVER := Color("9a9a9a")
const MEDAL_BRONZE := Color("9a6a3a")
const TAB_IDLE := Color("686868")

# The HUD is the only translucent surface: it sits over the road, so it needs a
# dark smoked fill and cream text. It is still flat, with no gradient or blur.
const HUD_BG := Color("0e0e0e")
const HUD_INK := Color("f5f5f2")
const HUD_DIM := Color("bdbdb7")
const HUD_MUTE := Color("8e8e88")
const HUD_GOOD := Color("8fbf9f")
const HUD_BAD := Color("e08a76")
const HUD_ACCENT := Color("ff6b4a")

const FONT_REGULAR := "res://assets/fonts/Inter-Regular.woff2"
const FONT_MEDIUM := "res://assets/fonts/Inter-Medium.woff2"
const FONT_SEMIBOLD := "res://assets/fonts/Inter-SemiBold.woff2"
const FONT_BOLD := "res://assets/fonts/Inter-Bold.woff2"

static var _fonts := {}


static func font_weight(weight: int) -> Font:
        if _fonts.has(weight):
                return _fonts[weight]
        var path := FONT_REGULAR
        match weight:
                500: path = FONT_MEDIUM
                600: path = FONT_SEMIBOLD
                700: path = FONT_BOLD
        var f: Font = load(path)
        _fonts[weight] = f
        return f


# Labels pick their weight from their size, so a screen gets a display/title/
# body hierarchy without every caller naming a font.
static func font_for_size(size: int) -> Font:
        if size >= 24:
                return font_weight(700)
        if size >= 16:
                return font_weight(600)
        return font_weight(400)


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
                text: Color, radius: int = 14, pad_h: int = 16, border: int = 1) -> void:
        t.set_stylebox("normal", type_name, _flat(base_bg, base_edge, radius, border, pad_h, 11))
        t.set_stylebox("hover", type_name, _flat(base_bg.lightened(0.04) if base_bg != Color(0, 0, 0, 0) else Color(0, 0, 0, 0.04), base_edge, radius, border, pad_h, 11))
        t.set_stylebox("pressed", type_name, _flat(base_bg.darkened(0.04) if base_bg != Color(0, 0, 0, 0) else Color(0, 0, 0, 0.07), base_edge, radius, border, pad_h, 11))
        t.set_stylebox("hover_pressed", type_name, _flat(base_bg.darkened(0.04) if base_bg != Color(0, 0, 0, 0) else Color(0, 0, 0, 0.07), base_edge, radius, border, pad_h, 11))
        t.set_stylebox("focus", type_name, _flat(Color(0, 0, 0, 0), ACCENT, radius, 2, pad_h, 11))
        t.set_stylebox("disabled", type_name, _flat(DISABLED_BG, DISABLED_EDGE, radius, border, pad_h, 11))
        t.set_color("font_color", type_name, text)
        t.set_color("font_hover_color", type_name, text)
        t.set_color("font_pressed_color", type_name, text)
        t.set_color("font_hover_pressed_color", type_name, text)
        t.set_color("font_focus_color", type_name, text)
        t.set_color("font_disabled_color", type_name, INK_MUTE)
        t.set_font("font", type_name, font_weight(600))
        t.set_font_size("font_size", type_name, 15)
        t.set_constant("outline_size", type_name, 0)
        t.set_constant("h_separation", type_name, 8)


# A soft dot for slider grabbers. The engine default is a grey square.
static func _dot(color: Color, size: int) -> ImageTexture:
        var img := Image.create(size, size, false, Image.FORMAT_RGBA8)
        img.fill(Color(0, 0, 0, 0))
        var centre := (size - 1) / 2.0
        var radius := size / 2.0 - 1.0
        for y in range(size):
                for x in range(size):
                        var d := Vector2(x - centre, y - centre).length()
                        if d <= radius:
                                var a := clampf(radius - d + 1.0, 0.0, 1.0)
                                img.set_pixel(x, y, Color(color.r, color.g, color.b, color.a * a))
        return ImageTexture.create_from_image(img)


static func build() -> Theme:
        var t := Theme.new()
        t.default_font = font_weight(400)
        t.default_font_size = 15

        # --- Buttons: flat white chips with a hairline; the accent is the primary ---
        _button_styles(t, "Button", BTN, BTN_EDGE, INK)

        t.set_type_variation("PrimaryButton", "Button")
        _button_styles(t, "PrimaryButton", ACCENT, ACCENT, ACCENT_TEXT)
        t.set_stylebox("hover", "PrimaryButton", _flat(ACCENT.lightened(0.08), ACCENT.lightened(0.08), 14, 1, 16, 11))
        t.set_stylebox("pressed", "PrimaryButton", _flat(ACCENT.darkened(0.06), ACCENT.darkened(0.06), 14, 1, 16, 11))
        t.set_stylebox("hover_pressed", "PrimaryButton", _flat(ACCENT.darkened(0.06), ACCENT.darkened(0.06), 14, 1, 16, 11))

        t.set_type_variation("DangerButton", "Button")
        _button_styles(t, "DangerButton", DANGER, DANGER, ACCENT_TEXT)

        t.set_type_variation("GhostButton", "Button")
        _button_styles(t, "GhostButton", Color(0, 0, 0, 0), BTN_EDGE, INK_DIM)
        t.set_stylebox("hover", "GhostButton", _flat(CARD_SUNK, BTN_EDGE, 14, 1, 16, 11))
        t.set_stylebox("pressed", "GhostButton", _flat(CARD_SUNK, BTN_EDGE, 14, 1, 16, 11))
        t.set_stylebox("hover_pressed", "GhostButton", _flat(CARD_SUNK, BTN_EDGE, 14, 1, 16, 11))

        # A selected chip is a white card with a 2px accent border, not a solid
        # accent fill. A full-width filled segment read as a banner.
        t.set_type_variation("ToggleButton", "Button")
        _button_styles(t, "ToggleButton", BTN, BTN_EDGE, INK)
        var on := _flat(BTN, ACCENT, 14, 2, 16, 11)
        t.set_stylebox("pressed", "ToggleButton", on)
        t.set_stylebox("hover_pressed", "ToggleButton", on)
        t.set_color("font_pressed_color", "ToggleButton", ACCENT)
        t.set_color("font_hover_pressed_color", "ToggleButton", ACCENT)

        # The track card: a tall white card with a map, number and best. Selected is
        # a 2px accent border; the labels stay ink, so contrast never depends on the
        # selection.
        t.set_type_variation("TrackCard", "Button")
        _button_styles(t, "TrackCard", BTN, BTN_EDGE, INK, 16, 10, 1)
        var track_on := _flat(BTN, ACCENT, 16, 2, 10, 9)
        t.set_stylebox("pressed", "TrackCard", track_on)
        t.set_stylebox("hover_pressed", "TrackCard", track_on)
        t.set_color("font_pressed_color", "TrackCard", INK)
        t.set_color("font_hover_pressed_color", "TrackCard", INK)

        t.set_type_variation("KeyCap", "Button")
        _button_styles(t, "KeyCap", CARD_SUNK, BTN_EDGE, INK, 10, 8, 1)
        t.set_font_size("font_size", "KeyCap", 14)

        # --- Panels: flat cards, one hairline, a shadow only on a sheet ---
        var card := _flat(PANEL, PANEL_EDGE, 20, 1, 18, 16)
        card.shadow_color = Color(PANEL_SHADOW.r, PANEL_SHADOW.g, PANEL_SHADOW.b, 0.06)
        card.shadow_size = 8
        card.shadow_offset = Vector2(0, 2)
        t.set_stylebox("panel", "PanelContainer", card)

        var flat_panel := _flat(PANEL, PANEL_EDGE, 16, 1, 14, 10)
        t.set_stylebox("panel", "Panel", flat_panel)

        t.set_type_variation("SubCard", "PanelContainer")
        t.set_stylebox("panel", "SubCard", _flat(CARD_SUNK, SURFACE_EDGE, 16, 1, 16, 14))

        t.set_type_variation("Sheet", "PanelContainer")
        var sheet := _flat(PANEL, PANEL_EDGE, 24, 1, 20, 18)
        sheet.shadow_color = Color(PANEL_SHADOW.r, PANEL_SHADOW.g, PANEL_SHADOW.b, 0.16)
        sheet.shadow_size = 24
        sheet.shadow_offset = Vector2(0, -6)
        t.set_stylebox("panel", "Sheet", sheet)

        # --- The app shell: page background, top/bottom rails ---
        t.set_type_variation("ShellBg", "Panel")
        t.set_stylebox("panel", "ShellBg", _flat(BG, BG, 0, 0, 0, 0))

        t.set_type_variation("TopBar", "Panel")
        var top_bar := _flat(PANEL, PANEL, 0, 0, 0, 0)
        top_bar.border_width_bottom = 1
        top_bar.border_color = SURFACE_EDGE
        t.set_stylebox("panel", "TopBar", top_bar)

        t.set_type_variation("BottomBar", "Panel")
        var bottom_bar := _flat(PANEL, PANEL, 0, 0, 0, 0)
        bottom_bar.border_width_top = 1
        bottom_bar.border_color = SURFACE_EDGE
        t.set_stylebox("panel", "BottomBar", bottom_bar)

        t.set_type_variation("Surface", "PanelContainer")
        t.set_stylebox("panel", "Surface", _flat(SURFACE, SURFACE_EDGE, 20, 1, 16, 14))

        # --- Tab buttons: icon over label, a 3px accent rule on the active tab ---
        t.set_type_variation("TabButton", "Button")
        var tab_off := _flat(Color(0, 0, 0, 0), Color(0, 0, 0, 0), 0, 0, 6, 6)
        var tab_on := _flat(Color(0, 0, 0, 0), Color(0, 0, 0, 0), 0, 0, 6, 6)
        tab_on.border_width_top = 3
        tab_on.border_color = ACCENT
        t.set_stylebox("normal", "TabButton", tab_off)
        t.set_stylebox("hover", "TabButton", _flat(Color(0, 0, 0, 0.035), Color(0, 0, 0, 0), 0, 0, 6, 6))
        t.set_stylebox("pressed", "TabButton", tab_on)
        t.set_stylebox("hover_pressed", "TabButton", tab_on)
        t.set_stylebox("focus", "TabButton", tab_off)
        t.set_stylebox("disabled", "TabButton", tab_off)
        t.set_color("font_color", "TabButton", TAB_IDLE)
        t.set_color("font_hover_color", "TabButton", INK)
        t.set_color("font_pressed_color", "TabButton", ACCENT)
        t.set_color("font_hover_pressed_color", "TabButton", ACCENT)
        t.set_color("font_disabled_color", "TabButton", INK_MUTE)
        t.set_font("font", "TabButton", font_weight(600))
        t.set_font_size("font_size", "TabButton", 11)

        # --- A round icon chip for the top bar ---
        t.set_type_variation("IconButton", "Button")
        _button_styles(t, "IconButton", Color(0, 0, 0, 0), Color(0, 0, 0, 0), INK_DIM, 10, 0)
        t.set_stylebox("hover", "IconButton", _flat(CARD_SUNK, Color(0, 0, 0, 0), 10, 0, 0, 0))
        t.set_stylebox("pressed", "IconButton", _flat(CARD_SUNK.darkened(0.04), Color(0, 0, 0, 0), 10, 0, 0, 0))
        t.set_stylebox("hover_pressed", "IconButton", _flat(CARD_SUNK.darkened(0.04), Color(0, 0, 0, 0), 10, 0, 0, 0))

        # --- Labels ---
        t.set_color("font_color", "Label", INK)
        t.set_font("font", "Label", font_weight(400))
        t.set_font_size("font_size", "Label", 15)
        t.set_constant("outline_size", "Label", 0)
        t.set_color("font_outline_color", "Label", Color(0, 0, 0, 0))

        # --- Text fields ---
        t.set_stylebox("normal", "LineEdit", _flat(SURFACE, SURFACE_EDGE, 12, 1, 14, 11))
        t.set_stylebox("focus", "LineEdit", _flat(SURFACE, ACCENT, 12, 2, 14, 11))
        t.set_stylebox("read_only", "LineEdit", _flat(DISABLED_BG, DISABLED_EDGE, 12, 1, 14, 11))
        t.set_color("font_color", "LineEdit", INK)
        t.set_color("font_placeholder_color", "LineEdit", INK_MUTE)
        t.set_color("font_selected_color", "LineEdit", Color("ffffff"))
        t.set_color("caret_color", "LineEdit", ACCENT)
        t.set_color("selection_color", "LineEdit", Color(ACCENT.r, ACCENT.g, ACCENT.b, 0.25))
        t.set_font("font", "LineEdit", font_weight(400))
        t.set_font_size("font_size", "LineEdit", 15)
        t.set_constant("caret_width", "LineEdit", 2)
        t.set_constant("minimum_character_width", "LineEdit", 6)

        # --- Sliders ---
        var track := _flat(CARD_SUNK, SURFACE_EDGE, 3, 0, 0, 0)
        track.content_margin_top = 3
        track.content_margin_bottom = 3
        t.set_stylebox("slider", "HSlider", track)
        var fill := _flat(ACCENT, ACCENT, 3, 0, 0, 0)
        fill.content_margin_top = 3
        fill.content_margin_bottom = 3
        t.set_stylebox("grabber_area", "HSlider", fill)
        t.set_stylebox("grabber_area_highlight", "HSlider", fill)
        t.set_icon("grabber", "HSlider", _dot(ACCENT, 18))
        t.set_icon("grabber_highlight", "HSlider", _dot(ACCENT.lightened(0.12), 20))
        t.set_icon("grabber_disabled", "HSlider", _dot(INK_MUTE, 18))

        # --- Scrollbars: slim and unobtrusive ---
        t.set_stylebox("scroll", "VScrollBar", _flat(Color(0, 0, 0, 0), Color(0, 0, 0, 0), 6, 0, 0, 0))
        var grabber := _flat(SURFACE_EDGE, SURFACE_EDGE, 6, 0, 0, 0)
        grabber.corner_radius_top_left = 6
        t.set_stylebox("grabber", "VScrollBar", grabber)
        t.set_stylebox("grabber_highlight", "VScrollBar", _flat(INK_MUTE, INK_MUTE, 6, 0, 0, 0))
        t.set_stylebox("grabber_pressed", "VScrollBar", _flat(ACCENT, ACCENT, 6, 0, 0, 0))
        t.set_constant("minimum_grab_thickness", "VScrollBar", 10)
        t.set_constant("scroll_width", "VScrollBar", 10)

        return t
