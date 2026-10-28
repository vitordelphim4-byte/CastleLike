class_name UiTheme
## Medieval pixel-art UI theme (HUD spec v1), built in code: every frame is a tiny Image painted
## with flat rects (2 px outline, light top-left / shadow bottom-right) used as a 9-slice.
## Game merges it into the engine default theme, so every Control picks it up.

const OUTLINE := Color("#140C07")
const WOOD_DARK := Color("#2B1A10")
const PANEL_BG := Color("#2E1D11")
const WELL := Color("#241710")
const WOOD_BASE := Color("#4A2E1A")
const WOOD := Color("#6B4325")
const WOOD_HOVER := Color("#7E5230")
const WOOD_LIGHT := Color("#B07B45")
const IRON := Color("#4A4D55")
const RIVET := Color("#C7CAD0")
const PARCH_DARK := Color("#B89A6A")
const PARCH := Color("#D9C49A")
const PARCH_LIGHT := Color("#EEDFB8")
const GOLD_DARK := Color("#9C6B1E")
const GOLD_MID := Color("#C98F32")
const GOLD := Color("#E8B04A")
const TEXT := Color("#F3E6C8")
const TEXT_DIM := Color("#C9B48C")
const TEXT_OFF := Color("#9C8C74")
const INK := Color("#1F140C")
const OK := Color("#6FAE3E")
const WARN := Color("#E5A23A")
const DANGER := Color("#C8402F")

static var FONT: Font = _font("res://fonts/PixelifySans.ttf")
static var BOLD: Font = _bold(FONT)
static var NUM: Font = _font("res://fonts/VT323.ttf")  # tabular digits: counters, clock, keycaps
static var _cache := {}


static func _font(path: String) -> FontFile:
	var f: FontFile = load(path)
	# ponytail: antialiased on purpose, Pixelify's pixels are 80-101 units wide (no exact grid size)
	f.subpixel_positioning = TextServer.SUBPIXEL_POSITIONING_DISABLED
	return f


static func _bold(base: Font) -> Font:
	var v := FontVariation.new()
	v.base_font = base
	v.variation_opentype = {TextServerManager.get_primary_interface().name_to_tag("wght"): 600}
	return v


# Bevelled box: [outline 2] [light/dark 2] fill. pressed = bevel inverted. shadow = +2/+2 drop.
# ring: outline color (gold = selected).
static func _bevel(fill: Color, light: Color, dark: Color, outline := true, shadow := false,
		ring := OUTLINE) -> StyleBoxTexture:
	var key := "bevel%s%s%s%s%s%s" % [fill, light, dark, outline, shadow, ring]
	if key in _cache:
		return _cache[key].duplicate()
	var o := 2 if outline else 0
	var n := 8 + 2 * o
	var s := 2 if shadow else 0
	var img := Image.create(n + s, n + s, false, Image.FORMAT_RGBA8)
	if shadow:
		img.fill_rect(Rect2i(s, s, n, n), OUTLINE)
	img.fill_rect(Rect2i(0, 0, n, n), ring)
	var i := n - 2 * o  # inside the outline
	img.fill_rect(Rect2i(o, o, i, i), light)
	img.fill_rect(Rect2i(o + 2, o + 2, i - 2, i - 2), dark)
	img.fill_rect(Rect2i(o + 2, o + 2, i - 4, i - 4), fill)
	var sb := _tex(img, o + 2, o + 2, o + 2 + s, o + 2 + s)
	sb.set_content_margin_all(o + 6)
	sb.content_margin_top = o + 3
	sb.content_margin_bottom = o + 3
	_cache[key] = sb
	return sb.duplicate()


static func _tex(img: Image, l: int, t: int, r: int, b: int) -> StyleBoxTexture:
	var sb := StyleBoxTexture.new()
	sb.texture = ImageTexture.create_from_image(img)
	sb.texture_margin_left = l
	sb.texture_margin_top = t
	sb.texture_margin_right = r
	sb.texture_margin_bottom = b
	return sb


## Big wooden frame with iron riveted corners (panels, modals, menus). 48x48 + shadow, 9-slice 16.
static func panel() -> StyleBoxTexture:
	if "panel" in _cache:
		return _cache.panel.duplicate()
	var img := Image.create(50, 50, false, Image.FORMAT_RGBA8)
	img.fill_rect(Rect2i(2, 2, 48, 48), OUTLINE)  # drop shadow
	img.fill_rect(Rect2i(0, 0, 48, 48), OUTLINE)
	img.fill_rect(Rect2i(2, 2, 44, 44), WOOD_LIGHT)
	img.fill_rect(Rect2i(4, 4, 42, 42), WOOD_DARK)
	img.fill_rect(Rect2i(4, 4, 40, 40), WOOD)
	img.fill_rect(Rect2i(10, 10, 28, 28), OUTLINE)
	img.fill_rect(Rect2i(12, 12, 24, 24), PANEL_BG)
	for c: Vector2i in [Vector2i(0, 0), Vector2i(32, 0), Vector2i(0, 32), Vector2i(32, 32)]:
		img.fill_rect(Rect2i(c, Vector2i(16, 16)), OUTLINE)
		img.fill_rect(Rect2i(c + Vector2i(2, 2), Vector2i(12, 12)), IRON)
		img.fill_rect(Rect2i(c + Vector2i(6, 6), Vector2i(4, 4)), RIVET)
	var sb := _tex(img, 16, 16, 18, 18)
	sb.set_content_margin_all(18)
	_cache.panel = sb
	return sb.duplicate()


## Top bar: flat dark wood with a lit plank edge along the bottom.
static func topbar() -> StyleBoxTexture:
	var img := Image.create(2, 12, false, Image.FORMAT_RGBA8)
	img.fill(PANEL_BG)
	img.fill_rect(Rect2i(0, 4, 2, 2), WOOD_LIGHT)
	img.fill_rect(Rect2i(0, 6, 2, 4), WOOD)
	img.fill_rect(Rect2i(0, 10, 2, 2), OUTLINE)
	var sb := _tex(img, 0, 0, 0, 8)
	sb.content_margin_left = 10
	sb.content_margin_right = 10
	sb.content_margin_top = 0
	sb.content_margin_bottom = 8
	return sb


static func parchment(shadow := true) -> StyleBoxTexture:
	return _bevel(PARCH, PARCH_LIGHT, PARCH_DARK, true, shadow)


## Sunken box: lists, fields, clock.
static func well() -> StyleBoxTexture:
	return _bevel(WELL, OUTLINE, WOOD_BASE, false)


## Parchment key cap for shortcut hints (text in NUM font, INK color).
static func keycap() -> StyleBoxTexture:
	var sb := _bevel(PARCH, PARCH_LIGHT, PARCH_DARK)
	sb.content_margin_left = 5
	sb.content_margin_right = 5
	sb.content_margin_top = 0
	sb.content_margin_bottom = 2
	return sb


## Key cap while its key is pressed: sunk 2 px, darker.
static func keycap_pressed() -> StyleBoxTexture:
	var sb := _bevel(PARCH_DARK, Color("#9C7F52"), PARCH_DARK)
	sb.content_margin_left = 5
	sb.content_margin_right = 5
	sb.content_margin_top = 2
	sb.content_margin_bottom = 0
	return sb


## Villager card / tile: "normal", "hover" or "selected" (gold ring).
static func card(state: String) -> StyleBoxTexture:
	var sb := _bevel(Color("#3A2618") if state == "hover" else PANEL_BG, WOOD_BASE, INK, true, false,
		GOLD if state == "selected" else OUTLINE)
	sb.set_content_margin_all(4)
	return sb


## Hunger bar fill: color and pattern both say the level (0 fed: solid, 1 hungry: dashes,
## 2 starving: fine stripes), so it reads without color too.
static func bar_fill(level: int) -> StyleBox:
	if level == 0:
		var f := _flat(OK)
		f.set_content_margin_all(0)
		return f
	var w := 6 if level == 1 else 4
	var img := Image.create(w, 4, false, Image.FORMAT_RGBA8)
	img.fill(GOLD_DARK if level == 1 else Color("#7A1F17"))
	img.fill_rect(Rect2i(0, 0, w - 2, 4) if level == 1 else Rect2i(0, 0, 2, 4), WARN if level == 1 else DANGER)
	var sb := _tex(img, 0, 0, 0, 0)
	sb.axis_stretch_horizontal = StyleBoxTexture.AXIS_STRETCH_MODE_TILE
	return sb


static func build() -> Theme:
	var t := Theme.new()
	t.default_font = FONT
	t.default_font_size = 16
	t.set_color("font_color", "Label", TEXT)
	t.set_stylebox("panel", "PanelContainer", panel())
	t.set_stylebox("panel", "Panel", panel())

	var normal := _bevel(WOOD, WOOD_LIGHT, WOOD_DARK)
	var hover := _bevel(WOOD_HOVER, Color("#D39A5A"), WOOD_DARK)
	var pressed := _bevel(GOLD_MID, GOLD_DARK, GOLD)  # toggled on (and held): sunken gold
	pressed.content_margin_top += 2
	pressed.content_margin_bottom -= 2
	var disabled := _bevel(Color("#4A3B2E"), Color("#5E4C3C"), Color("#33281F"))
	for type: String in ["Button", "OptionButton", "MenuButton"]:
		t.set_stylebox("normal", type, normal)
		t.set_stylebox("hover", type, hover)
		t.set_stylebox("pressed", type, pressed)
		t.set_stylebox("hover_pressed", type, pressed)
		t.set_stylebox("disabled", type, disabled)
		t.set_stylebox("focus", type, StyleBoxEmpty.new())
		t.set_color("font_color", type, TEXT)
		t.set_color("font_hover_color", type, TEXT)
		t.set_color("font_focus_color", type, TEXT)
		t.set_color("font_pressed_color", type, INK)
		t.set_color("font_hover_pressed_color", type, INK)
		t.set_color("font_disabled_color", type, TEXT_OFF)
		t.set_color("icon_pressed_color", type, Color.WHITE)
		t.set_color("icon_hover_pressed_color", type, Color.WHITE)

	var field := _bevel(INK, OUTLINE, WOOD_BASE, false)
	var field_focus := _bevel(INK, GOLD, GOLD, false)
	t.set_stylebox("normal", "LineEdit", field)
	t.set_stylebox("focus", "LineEdit", field_focus)
	t.set_stylebox("read_only", "LineEdit", field)
	t.set_color("font_color", "LineEdit", TEXT)
	t.set_color("font_placeholder_color", "LineEdit", TEXT_OFF)
	t.set_color("caret_color", "LineEdit", GOLD)
	t.set_color("selection_color", "LineEdit", Color(GOLD, 0.4))

	var popup := parchment()
	t.set_stylebox("panel", "PopupMenu", popup)
	t.set_stylebox("hover", "PopupMenu", _flat(GOLD_MID))
	t.set_color("font_color", "PopupMenu", INK)
	t.set_color("font_hover_color", "PopupMenu", INK)
	t.set_color("font_disabled_color", "PopupMenu", Color(INK, 0.5))
	t.set_stylebox("panel", "TooltipPanel", popup)
	t.set_color("font_color", "TooltipLabel", INK)
	t.set_font_size("font_size", "TooltipLabel", 12)

	t.set_stylebox("panel", "AcceptDialog", _flat(PANEL_BG))  # ponytail: window border stays default

	var bar_bg := _flat(OUTLINE)
	bar_bg.set_content_margin_all(0)
	t.set_stylebox("background", "ProgressBar", bar_bg)
	t.set_stylebox("fill", "ProgressBar", _flat(OK))

	for v: String in ["V", "H"]:
		var track := well()
		track.set_content_margin_all(4)
		t.set_stylebox("slider", v + "Slider", track)
		t.set_stylebox("grabber_area", v + "Slider", _flat(WOOD))
		t.set_stylebox("grabber_area_highlight", v + "Slider", _flat(WOOD_HOVER))
		t.set_icon("grabber", v + "Slider", _grabber(v == "V", GOLD_MID))
		t.set_icon("grabber_highlight", v + "Slider", _grabber(v == "V", GOLD))
		t.set_stylebox("scroll", v + "ScrollBar", well())
		t.set_stylebox("grabber", v + "ScrollBar", normal)
		t.set_stylebox("grabber_highlight", v + "ScrollBar", hover)
		t.set_stylebox("grabber_pressed", v + "ScrollBar", pressed)
		var line := _flat(WOOD_BASE)
		if v == "V":
			line.content_margin_left = 1
			line.content_margin_right = 1
		else:
			line.content_margin_top = 1
			line.content_margin_bottom = 1
		t.set_stylebox("separator", v + "Separator", line)
	return t


static func _flat(c: Color) -> StyleBoxFlat:
	var s := StyleBoxFlat.new()
	s.bg_color = c
	s.set_content_margin_all(4)
	return s


# Slider handle: 28x12 (vertical slider) or 12x28, gold with outline and bevel.
static func _grabber(vertical: bool, c: Color) -> ImageTexture:
	var w := 28 if vertical else 12
	var h := 12 if vertical else 28
	var img := Image.create(w, h, false, Image.FORMAT_RGBA8)
	img.fill(OUTLINE)
	img.fill_rect(Rect2i(2, 2, w - 4, h - 4), GOLD if c == GOLD_MID else PARCH_LIGHT)
	img.fill_rect(Rect2i(4, 4, w - 6, h - 6), GOLD_DARK)
	img.fill_rect(Rect2i(4, 4, w - 8, h - 8), c)
	return ImageTexture.create_from_image(img)


## Square button showing a pixel icon at exactly 2x (margins sized to fit), with a parchment tooltip
## (add a key / description / cost with .tip()).
static func icon_button(icon: Texture2D, tip: String, side := 22) -> TipButton:
	var b := TipButton.new().tip(tip)
	b.icon = icon
	b.expand_icon = true
	b.focus_mode = Control.FOCUS_NONE
	b.custom_minimum_size = Vector2(side, side)
	b.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	var pad := (side - icon.get_width() * 2) / 2.0
	for s: String in ["normal", "hover", "pressed", "hover_pressed", "disabled"]:
		var sb: StyleBox = ThemeDB.get_default_theme().get_stylebox(s, "Button").duplicate()
		sb.set_content_margin_all(pad)
		if s.contains("pressed"):
			sb.content_margin_top = pad + 2
			sb.content_margin_bottom = pad - 2
		b.add_theme_stylebox_override(s, sb)
	return b


## Small dim caption heading a section ("ORDENS ATIVAS").
static func caption(text: String) -> Label:
	var l := Label.new()
	l.text = text
	l.add_theme_font_size_override("font_size", 12)
	l.add_theme_color_override("font_color", TEXT_DIM)
	return l


## A key cap label ("T", "Esc", "Roda") for shortcut hints.
static func key_label(key: String) -> Label:
	var k := Label.new()
	k.text = key
	k.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	k.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	k.custom_minimum_size = Vector2(20, 22)
	k.add_theme_stylebox_override("normal", keycap())
	k.add_theme_font_override("font", NUM)
	k.add_theme_font_size_override("font_size", 18)
	k.add_theme_color_override("font_color", INK)
	k.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return k


## Thin progress bar (w x h) with a flat fill color.
static func bar(w: int, h: int, fill: Color) -> ProgressBar:
	var b := ProgressBar.new()
	b.show_percentage = false
	b.custom_minimum_size = Vector2(w, h)
	b.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	b.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var f := _flat(fill)
	f.set_content_margin_all(0)
	b.add_theme_stylebox_override("fill", f)
	return b


## Number label in the tabular pixel font.
static func num(size: int, col := TEXT) -> Label:
	var l := Label.new()
	l.add_theme_font_override("font", NUM)
	l.add_theme_font_size_override("font_size", size)
	l.add_theme_color_override("font_color", col)
	l.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	return l


## Work priority cell (1 first .. 4 last, 0 = never): a brightness ramp, "never" sunken instead of
## raised, so it reads without color. hover: light ring.
const PRIO := {1: ["#E8B04A", "#F6D27E", "#9C6B1E"], 2: ["#C98A3A", "#E0A85A", "#8A5A1E"],
	3: ["#7A5838", "#94704C", "#5E432A"], 4: ["#5A4130", "#6E5240", "#3A2A1E"]}


static func prio(level: int, hover := false) -> StyleBoxTexture:
	var ring := TEXT if hover else OUTLINE
	var sb: StyleBoxTexture
	if level == 0:
		sb = _bevel(WELL, OUTLINE, WELL, true, false, ring)
	else:
		sb = _bevel(Color(PRIO[level][0]), Color(PRIO[level][1]), Color(PRIO[level][2]), true, false, ring)
	sb.set_content_margin_all(0)
	return sb


static func prio_font(level: int) -> Color:
	return INK if level in [1, 2] else (Color("#A08C70") if level == 0 else TEXT)
