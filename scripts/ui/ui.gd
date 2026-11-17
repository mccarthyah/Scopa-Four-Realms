extends RefCounted
## Palette, fonts and widget factories.  Everything is built in code so the
## project is a handful of readable scripts with no scene-graph sprawl.
class_name UI

const T := preload("res://scripts/tables.gd")

# --- palette -----------------------------------------------------------------
const INK := Color("070e19")
const BG := Color("091321")
const BG2 := Color("0c1c2c")
const PANEL := Color("101e30")
const PANEL_HI := Color("193147")
const GOLD := Color("e6c679")
const GOLD_DEEP := Color("927037")
const PARCHMENT := Color("f5ecd8")
const PARCHMENT_HI := Color("fffaf0")
const PARCHMENT_LO := Color("e0d0ae")
const TEXT := Color("efe6d3")
const TEXT_DIM := Color("b9c1c1")
const GOOD := Color("86db53")
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


## Anti-aliasing on a StyleBoxFlat replaces the rectangle with a tessellated
## triangle mesh: roughly 57 primitives per draw instead of 2, every frame, for
## every panel. On a software rasteriser (any VM without a GPU) that was the
## single largest cost in the game — ~9,700 primitives per frame. Off, plus the
## optional freeze() helper so no StyleBox is ever mutated per frame.
## Low-spec mode: set at boot when the machine has no real GPU (see main.gd).
## Square corners are 2 triangles; a rounded corner is tessellated into ~50-100,
## and on a software rasteriser every one of those triangles costs CPU time.
static var LOW_SPEC := false


## LOW_SPEC squares off DOM chrome - popups, chips, buttons - because rounded
## corners there are invisible and the rounding costs time on a software
## rasteriser. Cards are the exception: a playing card's curved corners are a
## defining feature, so anything drawn with keep_corners keeps them.
static func flat(col: Color, radius: int = 12, border: Color = Color(0, 0, 0, 0), bw: int = 0,
		keep_corners: bool = false) -> StyleBoxFlat:
	var s := StyleBoxFlat.new()
	s.bg_color = col
	s.set_corner_radius_all(radius if (keep_corners or not LOW_SPEC) else 0)
	if bw > 0:
		s.set_border_width_all(bw)
		s.border_color = border
	# Rounded corners drawn without AA are visibly jagged, so only the card styles
	# pay for it; everything squared-off stays on the cheap path.
	s.anti_aliasing = keep_corners
	return s


## Convert a StyleBox into a cheap textured quad.
##
## WARNING: this renders a SubViewport and reads the pixels back, which is a hard
## CPU/GPU sync costing milliseconds on a software rasteriser. Use it for
## long-lived, rarely created boxes only — never inside a per-item loop, and never
## per frame. With anti_aliasing off a plain StyleBox is already 2 triangles.
##
## A plain rectangle with square corners is only 2 triangles, but a StyleBox with
## corner radii is tessellated on every draw. freeze() rasterises the box once
## into a texture (one quad, alpha preserved) and returns a StyleBoxTexture, so a
## rounded panel costs 2 primitives per frame instead of ~57. Returns null if the
## texture cannot be created, so callers can fall back to the StyleBox itself.
static func freeze(box: StyleBox, w: int, h: int) -> StyleBoxTexture:
	if box == null or w < 2 or h < 2:
		return null
	if DisplayServer.get_name() == "headless":
		return null
	if RenderingServer.get_video_adapter_name() == "":
		return null
	var vp := SubViewport.new()
	vp.size = Vector2i(w, h)
	vp.transparent_bg = true
	vp.disable_3d = true
	vp.render_target_update_mode = SubViewport.UPDATE_ONCE
	vp.gui_disable_input = true
	var host := Control.new()
	host.size = Vector2(w, h)
	host.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var painter := _BoxPainter.new()
	painter.box = box
	painter.size = Vector2(w, h)
	host.add_child(painter)
	vp.add_child(host)
	Engine.get_main_loop().root.add_child(vp)
	# Two processed frames, then read back. Deliberately not awaiting
	# RenderingServer.frame_post_draw: that signal does not fire on every
	# renderer and awaiting it would hang the caller forever.
	var t := 0
	while t < 2:
		await Engine.get_main_loop().process_frame
		t += 1
	var tex: Texture2D = vp.get_texture()
	var img: Image = tex.get_image() if tex != null else null
	vp.get_parent().remove_child(vp)
	vp.free()
	if img == null:
		return null
	var st := StyleBoxTexture.new()
	st.texture = ImageTexture.create_from_image(img)
	return st


## Paints a StyleBox into a viewport so freeze() can capture it.
class _BoxPainter extends Control:
	var box: StyleBox

	func _draw() -> void:
		if box != null:
			draw_style_box(box, Rect2(Vector2.ZERO, size))


static func panel(col: Color = PANEL, radius: int = 18, border: Color = Color("8f754c"), bw: int = 2) -> StyleBoxFlat:
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


## `wrap` makes a label break across lines instead of growing arbitrarily wide,
## which is what a long line does on a wide desktop window.
static func label(txt: String, size: int = 22, col: Color = TEXT, title: bool = false,
		wrap: bool = false) -> Label:
	var l := Label.new()
	l.text = txt
	if wrap:
		l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		l.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	l.add_theme_font_override("font", _font("", title, false))
	l.add_theme_font_size_override("font_size", size)
	l.add_theme_color_override("font_color", col)
	# A font shadow draws every glyph twice. That is affordable on a GPU and not
	# on a CPU rasteriser, and text is the bulk of what is left on screen.
	if not LOW_SPEC:
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
			b.add_theme_stylebox_override("normal", flat(Color(0, 0, 0, 0), 12, Color("8c7448"), 2))
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
