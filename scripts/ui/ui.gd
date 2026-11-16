extends RefCounted
## Palette, fonts and widget factories.  Everything is built in code so the
## project is a handful of readable scripts with no scene-graph sprawl.
class_name UI

const T := preload("res://scripts/tables.gd")

# --- palette -----------------------------------------------------------------
const INK := Color("0e0b13")
const BG := Color("171320")
const BG2 := Color("1e1929")
const PANEL := Color("241e31")
const PANEL_HI := Color("302740")
const GOLD := Color("dcb673")
const GOLD_DEEP := Color("8c6a2b")
const PARCHMENT := Color("f5ecd8")
const PARCHMENT_HI := Color("fffaf0")
const PARCHMENT_LO := Color("e0d0ae")
const TEXT := Color("efe6d3")
const TEXT_DIM := Color("a89b88")
const GOOD := Color("6ec07a")
const BAD := Color("c85b52")

# Fonts are imported assets, so a bare checkout (before Godot's first import
# pass) may have no .fontdata yet. Resolve them on first use and fall back to
# Godot's own font rather than failing to parse the whole UI.
static var _fonts_resolved := false
static var FONT_TITLE: Font = null
static var FONT_BODY: Font = null
static var FONT_BODY_BOLD: Font = null


static func resolve_fonts() -> void:
	if _fonts_resolved:
		return
	_fonts_resolved = true
	FONT_TITLE = _load_font("res://fonts/Cinzel.ttf")
	FONT_BODY = _load_font("res://fonts/AlegreyaSans.ttf")
	FONT_BODY_BOLD = _load_font("res://fonts/AlegreyaSans-Bold.ttf")


## Called from every factory, so fonts are ready no matter which entry point
## draws first.
static func _font(path: String, title: bool = false, bold: bool = false) -> Font:
	resolve_fonts()
	if title:
		return FONT_TITLE
	if bold:
		return FONT_BODY_BOLD
	return FONT_BODY


static func font_title() -> Font:
	resolve_fonts()
	return FONT_TITLE


static func font_body() -> Font:
	resolve_fonts()
	return FONT_BODY


static func font_bold() -> Font:
	resolve_fonts()
	return FONT_BODY_BOLD


static func _load_font(path: String) -> Font:
	var fallback: Font = ThemeDB.fallback_font
	if not ResourceLoader.exists(path):
		return fallback
	var f = load(path)
	if f is Font:
		return f
	push_warning("Scopa: could not load font " + path + ", using the default font")
	return fallback

const CARD_W := 104
const CARD_H := 146
const CARD_W_BIG := 124
const CARD_H_BIG := 174


static func flat(col: Color, radius: int = 12, border: Color = Color(0, 0, 0, 0), bw: int = 0) -> StyleBoxFlat:
	var s := StyleBoxFlat.new()
	s.bg_color = col
	s.set_corner_radius_all(radius)
	if bw > 0:
		s.set_border_width_all(bw)
		s.border_color = border
	s.anti_aliasing = true
	return s


static func panel(col: Color = PANEL, radius: int = 18, border: Color = Color("40355266"), bw: int = 2) -> StyleBoxFlat:
	var s := flat(col, radius, border, bw)
	s.content_margin_left = 16
	s.content_margin_right = 16
	s.content_margin_top = 12
	s.content_margin_bottom = 12
	# No shadow_size: every StyleBoxFlat with a shadow blur costs a gaussian pass
	# each time it is drawn, and these panels are on screen constantly. A 2px
	# darker border gives the same sense of depth for free.
	s.shadow_color = Color(0, 0, 0, 0.0)
	s.shadow_size = 0
	s.border_color = Color(border.r, border.g, border.b, maxf(border.a, 0.55))
	return s


static func label(txt: String, size: int = 22, col: Color = TEXT, title: bool = false) -> Label:
	var l := Label.new()
	l.text = txt
	l.add_theme_font_override("font", _font("", title, false))
	l.add_theme_font_size_override("font_size", size)
	l.add_theme_color_override("font_color", col)
	l.add_theme_color_override("font_shadow_color", Color(0, 0, 0, 0.55))
	l.add_theme_constant_override("shadow_offset_x", 0)
	l.add_theme_constant_override("shadow_offset_y", 2)
	return l


static func button(txt: String, kind: String = "primary", size: int = 24) -> Button:
	var b := Button.new()
	b.text = txt
	b.focus_mode = Control.FOCUS_NONE
	b.add_theme_font_override("font", _font("", false, true))
	b.add_theme_font_size_override("font_size", size)
	var col := GOLD
	var txt_col := INK
	match kind:
		"primary":
			col = GOLD
			txt_col = Color("241a08")
		"secondary":
			col = PANEL_HI
			txt_col = TEXT
		"ghost":
			b.add_theme_stylebox_override("normal", flat(Color(0, 0, 0, 0), 12, Color("4a3f5e"), 2))
			b.add_theme_stylebox_override("hover", flat(Color(1, 1, 1, 0.06), 12, GOLD, 2))
			b.add_theme_stylebox_override("pressed", flat(GOLD, 12, GOLD, 2))
			b.add_theme_color_override("font_color", TEXT)
			b.add_theme_color_override("font_hover_color", GOLD)
			b.add_theme_color_override("font_pressed_color", INK)
			b.custom_minimum_size = Vector2(0, 56)
			return b
		"danger":
			col = BAD
			txt_col = Color("fff2ef")
	b.add_theme_stylebox_override("normal", flat(col, 14))
	b.add_theme_stylebox_override("hover", flat(col.lightened(0.12), 14))
	b.add_theme_stylebox_override("pressed", flat(col.darkened(0.18), 14))
	b.add_theme_stylebox_override("disabled", flat(col.darkened(0.45), 14))
	b.add_theme_color_override("font_color", txt_col)
	b.add_theme_color_override("font_hover_color", txt_col)
	b.add_theme_color_override("font_pressed_color", txt_col)
	b.add_theme_color_override("font_disabled_color", Color(txt_col.r, txt_col.g, txt_col.b, 0.4))
	b.custom_minimum_size = Vector2(0, 60)
	return b


static func icon_button(glyph: String, size: int = 44) -> Button:
	var b := button(glyph, "secondary", 22)
	b.custom_minimum_size = Vector2(size, size)
	b.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	return b


static func divider(col: Color = Color("3b3150")) -> ColorRect:
	var r := ColorRect.new()
	r.color = col
	r.custom_minimum_size = Vector2(0, 1)
	return r


static func spacer(h: int = 8) -> Control:
	var c := Control.new()
	c.custom_minimum_size = Vector2(0, h)
	return c


static func vspace(w: int = 8) -> Control:
	var c := Control.new()
	c.custom_minimum_size = Vector2(w, 0)
	return c


## Rounded "chip" with a label, used for HUD stats.
static func chip(txt: String, col: Color = PANEL_HI, txt_col: Color = TEXT, size: int = 18) -> PanelContainer:
	var p := PanelContainer.new()
	p.add_theme_stylebox_override("panel", flat(col, 12))
	var m := MarginContainer.new()
	m.add_theme_constant_override("margin_left", 10)
	m.add_theme_constant_override("margin_right", 10)
	m.add_theme_constant_override("margin_top", 3)
	m.add_theme_constant_override("margin_bottom", 3)
	var l := label(txt, size, txt_col)
	l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	m.add_child(l)
	p.add_child(m)
	return p


static func set_chip(p: PanelContainer, txt: String, col: Color = PANEL_HI, txt_col: Color = TEXT) -> void:
	var l: Label = p.get_child(0).get_child(0)
	l.text = txt
	l.add_theme_color_override("font_color", txt_col)
	p.add_theme_stylebox_override("panel", flat(col, 12))


static func faction_color(f: int) -> Color:
	return T.FACTIONS[f].color
