extends RefCounted
## Card face artwork, drawn directly as vectors into any CanvasItem.
##
## This replaced a texture-baking atlas. Baking seemed clever — render each face
## once, blit afterwards — but on the target machine (no GPU; ANGLE -> WARP
## software rasteriser) every readback is a hard CPU/GPU sync costing
## milliseconds, and a capture that came back empty produced invisible cards with
## no error. With anti_aliasing off a rounded box is 2 triangles, so drawing
## straight to the screen is cheap, direct, and cannot fail invisibly.
class_name CardArt

const UI := preload("res://scripts/ui/ui.gd")
const T := preload("res://scripts/tables.gd")
const C := preload("res://scripts/game/cards.gd")


## Draw a card face (id >= 0) or a card back (id < 0) into `target`.
## `alpha` is accepted for callers' convenience but deliberately IGNORED.
##
## It used to multiply target.modulate.a here and divide it back afterwards. On
## the first frame of a deal-in alpha is 0, so the round trip was 1.0 * 0 / 0 =
## NaN, and a NaN modulate makes the control invisible for good — which is exactly
## why every card rendered blank. Fading is the node's job: CardView sets
## modulate.a in _process, never inside _draw.
static func draw_face(target: CanvasItem, rect: Rect2, card_id: int, back_style: int = 0,
		alpha: float = 1.0) -> void:
	if card_id < 0:
		_draw_back(target, rect, back_style)
		return

	var w := rect.size.x
	var h := rect.size.y
	var origin := rect.position
	var f := C.faction(card_id)
	var r := C.rank(card_id)
	var info: Dictionary = T.FACTIONS[f]
	var col: Color = info.color
	var deep: Color = info.deep
	var pale: Color = info.pale
	var rune := C.is_runestone(card_id)

	# --- parchment face
	target.draw_style_box(UI.flat(UI.PARCHMENT, 11), rect)
	target.draw_style_box(UI.flat(Color(1, 1, 1, 0.30), 11),
		Rect2(origin, Vector2(w, h * 0.42)))

	# --- border
	var border_col := UI.GOLD if rune else Color(deep.r, deep.g, deep.b, 0.55)
	var bw := 3 if rune else 2
	target.draw_style_box(UI.flat(Color(0, 0, 0, 0), 11, border_col, bw), rect)

	# --- layout: big rank top-left, art window, name strip
	var pad := 7.0
	var rank_band := h * 0.44
	var strip_h := 18.0
	var art_rect := Rect2(origin + Vector2(pad, rank_band),
		Vector2(w - pad * 2, h - rank_band - strip_h - pad * 0.6))

	target.draw_style_box(UI.flat(deep, 8), art_rect)
	target.draw_style_box(UI.flat(Color(col.r, col.g, col.b, 0.30), 8),
		Rect2(art_rect.position, Vector2(art_rect.size.x, art_rect.size.y * 0.42)))
	var art_center := art_rect.position + art_rect.size * 0.5
	var sc := minf(art_rect.size.x, art_rect.size.y) / 100.0
	_draw_emblem(target, f, art_center, sc,
		Color(pale.r, pale.g, pale.b, 0.95), Color(col.r, col.g, col.b, 0.55))

	# --- rank numeral, large, top-left
	var num_size := int(h * 0.34)
	var num_h := UI.font_title().get_string_size("8", HORIZONTAL_ALIGNMENT_LEFT, -1, num_size).y
	target.draw_string(UI.font_title(), origin + Vector2(pad + 3, rank_band * 0.5 + num_h * 0.34),
		str(r), HORIZONTAL_ALIGNMENT_LEFT, -1, num_size, deep)

	# --- faction glyph, top-right
	var glyph_w := UI.font_bold().get_string_size(T.SUIT_GLYPH[f], HORIZONTAL_ALIGNMENT_LEFT, -1, 20).x
	target.draw_string(UI.font_bold(), origin + Vector2(w - pad - glyph_w - 2, rank_band * 0.52),
		T.SUIT_GLYPH[f], HORIZONTAL_ALIGNMENT_LEFT, -1, 20, col)

	# thin rule between rank band and art
	target.draw_line(origin + Vector2(pad + 2, rank_band - 3),
		origin + Vector2(w - pad - 2, rank_band - 3),
		Color(deep.r, deep.g, deep.b, 0.22), 1.0)

	# --- name strip along the bottom
	var name_size := int(clampf(h * 0.075, 9.0, 13.0))
	var nm: String = str(info.name).to_upper()
	var nw := UI.font_bold().get_string_size(nm, HORIZONTAL_ALIGNMENT_LEFT, -1, name_size).x
	target.draw_string(UI.font_bold(), origin + Vector2((w - nw) * 0.5, h - 6.0), nm,
		HORIZONTAL_ALIGNMENT_LEFT, -1, name_size, Color(deep.r, deep.g, deep.b, 0.85))

	# --- runestone flourish
	if rune:
		var star := "✦"
		var sw := UI.font_bold().get_string_size(star, HORIZONTAL_ALIGNMENT_LEFT, -1, 14).x
		target.draw_string(UI.font_bold(), origin + Vector2(w - pad - sw - 2, h - 6.0), star,
			HORIZONTAL_ALIGNMENT_LEFT, -1, 14, UI.GOLD_DEEP)



static func _draw_back(target: CanvasItem, rect: Rect2, back_style: int) -> void:
	var w := rect.size.x
	var h := rect.size.y
	var themes := [Color("221a30"), Color("1b2a2f"), Color("2f1f22")]
	var golds := [UI.GOLD, Color("7fd4c1"), Color("e0a08a")]
	var base: Color = themes[back_style % themes.size()]
	var gold: Color = golds[back_style % golds.size()]
	target.draw_style_box(UI.flat(base, 11), rect)
	# diagonal weave
	for i in range(-6, 12):
		var x := rect.position.x + i * 18.0
		target.draw_line(Vector2(x, rect.position.y + 4), Vector2(x + h * 0.6, rect.end.y - 4),
			Color(1, 1, 1, 0.045), 2.0)
	# emblem
	var c := rect.position + rect.size * 0.5
	var gold_a := Color(gold.r, gold.g, gold.b, 0.9)
	target.draw_circle(c, minf(w, h) * 0.28,
		Color(UI.GOLD_DEEP.r, UI.GOLD_DEEP.g, UI.GOLD_DEEP.b, 0.18))
	target.draw_arc(c, minf(w, h) * 0.28, 0, TAU, 32, gold_a, 1.6, true)
	target.draw_arc(c, minf(w, h) * 0.22, 0, TAU, 32, Color(gold.r, gold.g, gold.b, 0.5), 1.0, true)
	var pts := PackedVector2Array()
	for i in range(4):
		var ang := -PI / 2 + i * TAU / 4.0
		pts.append(c + Vector2(cos(ang), sin(ang)) * minf(w, h) * 0.16)
	target.draw_colored_polygon(pts, Color(gold.r, gold.g, gold.b, 0.85))
	var pts2 := PackedVector2Array()
	for i in range(4):
		var ang := PI / 4 + i * TAU / 4.0
		pts2.append(c + Vector2(cos(ang), sin(ang)) * minf(w, h) * 0.07)
	target.draw_colored_polygon(pts2, Color(gold.r, gold.g, gold.b, 0.5))
	target.draw_style_box(UI.flat(Color(0, 0, 0, 0), 11, gold, 2), rect)


# ---------------------------------------------------------------------------
# FACTION EMBLEMS
# ---------------------------------------------------------------------------
static func _draw_emblem(target: CanvasItem, f: int, c: Vector2, s: float,
		ink: Color, accent: Color) -> void:
	match f:
		T.FORGE:
			_draw_forge(target, c, s, ink, accent)
		T.GROVE:
			_draw_grove(target, c, s, ink, accent)
		T.HORDE:
			_draw_horde(target, c, s, ink, accent)
		T.CROWN:
			_draw_crown(target, c, s, ink, accent)


static func _draw_forge(target: CanvasItem, c: Vector2, s: float, ink: Color, accent: Color) -> void:
	# hammer over an anvil, with sparks
	var anvil := PackedVector2Array([
		c + Vector2(-26, 2) * s, c + Vector2(26, 2) * s,
		c + Vector2(20, 12) * s, c + Vector2(8, 12) * s,
		c + Vector2(6, 22) * s, c + Vector2(14, 26) * s,
		c + Vector2(-14, 26) * s, c + Vector2(-6, 22) * s,
		c + Vector2(-8, 12) * s, c + Vector2(-20, 12) * s,
	])
	target.draw_colored_polygon(anvil, ink)
	var head := PackedVector2Array([
		c + Vector2(2, -26) * s, c + Vector2(24, -20) * s,
		c + Vector2(21, -10) * s, c + Vector2(0, -16) * s,
	])
	target.draw_colored_polygon(head, ink)
	target.draw_line(c + Vector2(6, -16) * s, c + Vector2(-6, 0) * s, ink, 4.0 * s, true)
	target.draw_circle(c + Vector2(-22, -14) * s, 2.6 * s, accent)
	target.draw_circle(c + Vector2(-30, -4) * s, 1.8 * s, accent)
	target.draw_circle(c + Vector2(-16, -24) * s, 1.6 * s, accent)


static func _draw_grove(target: CanvasItem, c: Vector2, s: float, ink: Color, accent: Color) -> void:
	# a leafed arch
	target.draw_line(c + Vector2(0, 26) * s, c + Vector2(0, -4) * s, ink, 4.0 * s, true)
	target.draw_line(c + Vector2(0, 6) * s, c + Vector2(-16, -8) * s, ink, 3.0 * s, true)
	target.draw_line(c + Vector2(0, 0) * s, c + Vector2(16, -12) * s, ink, 3.0 * s, true)
	for p in [Vector2(-16, -8), Vector2(16, -12), Vector2(0, -14)]:
		var leaf := PackedVector2Array([
			c + p * s, c + (p + Vector2(-9, -12)) * s, c + (p + Vector2(9, -12)) * s,
		])
		target.draw_colored_polygon(leaf, ink)
	target.draw_arc(c + Vector2(0, -18) * s, 22 * s, PI * 1.1, PI * 1.9, 16, ink, 3.0 * s, true)
	target.draw_circle(c + Vector2(0, -14) * s, 5.0 * s, accent)


static func _draw_horde(target: CanvasItem, c: Vector2, s: float, ink: Color, accent: Color) -> void:
	# crossed axes
	for sign_ in [-1.0, 1.0]:
		target.draw_line(c + Vector2(-20 * sign_, 24) * s, c + Vector2(20 * sign_, -20) * s,
			ink, 5.0 * s, true)
		var blade := PackedVector2Array([
			c + Vector2(20 * sign_, -20) * s,
			c + Vector2(30 * sign_, -32) * s,
			c + Vector2(34 * sign_, -18) * s,
			c + Vector2(22 * sign_, -10) * s,
		])
		target.draw_colored_polygon(blade, ink)
		target.draw_circle(c + Vector2(14 * sign_, -12) * s, 3.0 * s, accent)
	target.draw_circle(c, 6.0 * s, accent)


static func _draw_crown(target: CanvasItem, c: Vector2, s: float, ink: Color, accent: Color) -> void:
	# banner and crown
	target.draw_line(c + Vector2(-18, -28) * s, c + Vector2(-18, 26) * s, ink, 4.0 * s, true)
	var flag := PackedVector2Array([
		c + Vector2(-18, -28) * s, c + Vector2(22, -22) * s,
		c + Vector2(12, -12) * s, c + Vector2(22, -2) * s,
		c + Vector2(-18, 2) * s,
	])
	target.draw_colored_polygon(flag, ink)
	var crown := PackedVector2Array([
		c + Vector2(-12, 26) * s, c + Vector2(-12, 12) * s,
		c + Vector2(-4, 19) * s, c + Vector2(2, 10) * s,
		c + Vector2(8, 19) * s, c + Vector2(14, 12) * s,
		c + Vector2(14, 26) * s,
	])
	target.draw_colored_polygon(crown, accent)
	target.draw_circle(c + Vector2(1, 22) * s, 2.4 * s, ink)
