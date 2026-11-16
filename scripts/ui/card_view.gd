extends Control
## A single card, drawn entirely with vector primitives so the whole game ships
## with no art pipeline.  Rank numbers are deliberately the loudest element;
## faction art is the texture behind them.
class_name CardView

const UI := preload("res://scripts/ui/ui.gd")

signal pressed(card_id: int)

const T := preload("res://scripts/tables.gd")
const C := preload("res://scripts/game/cards.gd")

var card_id := -1
var face_up := true
var playable := false
var selected := false
var dim := false
var hinted := false
var capturable := false
var animated_in := false
var back_style := 0
var _sized := false

var _t := 0.0
var _lift := 0.0
var _target_lift := 0.0
var _glow := 0.0
var _fig := 0.0


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_STOP
	# setup() may already have sized us; only fall back to the default card size
	if not _sized:
		custom_minimum_size = Vector2(UI.CARD_W, UI.CARD_H)
		size = custom_minimum_size
	set_process(true)


func setup(id: int, up: bool = true, w: int = UI.CARD_W, h: int = UI.CARD_H) -> CardView:
	card_id = id
	face_up = up
	_sized = true
	custom_minimum_size = Vector2(w, h)
	size = Vector2(w, h)
	_t = 0.0
	_fig = 0.0
	queue_redraw()
	return self


func enter_anim(delay: float = 0.0) -> void:
	animated_in = true
	_fig = -delay
	queue_redraw()


func set_playable(v: bool) -> void:
	playable = v
	_target_lift = -10.0 if v else 0.0
	queue_redraw()


func set_selected(v: bool) -> void:
	selected = v
	_target_lift = -26.0 if v else (-10.0 if playable else 0.0)
	queue_redraw()


func _process(delta: float) -> void:
	_t += delta
	var dirty := false
	if _fig < 1.0:
		_fig = min(1.0, _fig + delta * 3.4)
		dirty = true
	if abs(_lift - _target_lift) > 0.4:
		_lift = lerp(_lift, _target_lift, 1.0 - pow(0.001, delta))
		dirty = true
	else:
		_lift = _target_lift
	var target_glow := 1.0 if playable else 0.0
	if abs(_glow - target_glow) > 0.01:
		_glow = lerp(_glow, target_glow, 1.0 - pow(0.002, delta))
		dirty = true
	if playable or selected or capturable:
		dirty = true
	if dirty:
		queue_redraw()


func _gui_input(event: InputEvent) -> void:
	if event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_LEFT:
		pressed.emit(card_id)
		accept_event()
	elif event is InputEventScreenTouch and event.pressed:
		pressed.emit(card_id)
		accept_event()


func _draw() -> void:
	var w := size.x
	var h := size.y
	var fig := clampf(_fig, 0.0, 1.0)
	var ease_out := 1.0 - pow(1.0 - fig, 3.0)
	var draw_pos := Vector2(0, (1.0 - ease_out) * 26.0 + _lift)
	var rect := Rect2(draw_pos, Vector2(w, h))
	var alpha := fig

	var modulate_a := 0.6 if dim else 1.0
	var base_alpha := alpha * modulate_a

	if not face_up:
		_draw_back(rect, base_alpha)
		return

	var f := C.faction(card_id)
	var r := C.rank(card_id)
	var info: Dictionary = T.FACTIONS[f]
	var col: Color = info.color
	var deep: Color = info.deep
	var pale: Color = info.pale
	var rune := C.is_runestone(card_id)

	# --- drop shadow
	var sh := UI.flat(Color(0, 0, 0, 0.35 * base_alpha), 11)
	sh.shadow_color = Color(0, 0, 0, 0.4 * base_alpha)
	sh.shadow_size = 8
	sh.shadow_offset = Vector2(0, 5)
	draw_style_box(sh, Rect2(rect.position + Vector2(0, -1), rect.size))

	# --- parchment face
	var face := UI.flat(Color(UI.PARCHMENT.r, UI.PARCHMENT.g, UI.PARCHMENT.b, base_alpha), 11)
	draw_style_box(face, rect)

	# warm top light
	var top := UI.flat(Color(1, 1, 1, 0.30 * base_alpha), 11)
	draw_style_box(top, Rect2(rect.position, Vector2(w, h * 0.42)))

	# --- border
	var border_col := UI.GOLD if rune else Color(deep.r, deep.g, deep.b, 0.55)
	var bw := 3 if rune else 2
	var bord := UI.flat(Color(0, 0, 0, 0), 11, Color(border_col.r, border_col.g, border_col.b, base_alpha), bw)
	draw_style_box(bord, rect)

	# --- layout: big rank top-left, art window, name strip
	var pad := 7.0
	var rank_band := h * 0.44
	var strip_h := 18.0
	var art_rect := Rect2(rect.position + Vector2(pad, rank_band), Vector2(w - pad * 2, h - rank_band - strip_h - pad * 0.6))

	# art window
	var art := UI.flat(Color(deep.r, deep.g, deep.b, base_alpha), 8)
	draw_style_box(art, art_rect)
	var art_hi := UI.flat(Color(col.r, col.g, col.b, 0.30 * base_alpha), 8)
	draw_style_box(art_hi, Rect2(art_rect.position, Vector2(art_rect.size.x, art_rect.size.y * 0.42)))
	var art_center := art_rect.position + art_rect.size * 0.5
	var s := minf(art_rect.size.x, art_rect.size.y) / 100.0
	_draw_emblem(f, art_center, s, Color(pale.r, pale.g, pale.b, 0.95 * base_alpha), Color(col.r, col.g, col.b, 0.55 * base_alpha))

	# --- rank numeral, large, top-left
	var num_col := Color(deep.r, deep.g, deep.b, base_alpha)
	var num_size := int(h * 0.34)
	var num_h := UI.FONT_TITLE.get_string_size("8", HORIZONTAL_ALIGNMENT_LEFT, -1, num_size).y
	draw_string(UI.FONT_TITLE, rect.position + Vector2(pad + 3, rank_band * 0.5 + num_h * 0.34), str(r),
		HORIZONTAL_ALIGNMENT_LEFT, -1, num_size, num_col)

	# --- faction glyph, top-right
	var glyph_w := UI.FONT_BODY_BOLD.get_string_size(T.SUIT_GLYPH[f], HORIZONTAL_ALIGNMENT_LEFT, -1, 20).x
	draw_string(UI.FONT_BODY_BOLD, rect.position + Vector2(w - pad - glyph_w - 2, rank_band * 0.52), T.SUIT_GLYPH[f],
		HORIZONTAL_ALIGNMENT_LEFT, -1, 20, Color(col.r, col.g, col.b, base_alpha))

	# thin rule between rank band and art
	draw_line(rect.position + Vector2(pad + 2, rank_band - 3), rect.position + Vector2(w - pad - 2, rank_band - 3),
		Color(deep.r, deep.g, deep.b, 0.22 * base_alpha), 1.0)

	# --- name strip along the bottom
	var name_size := int(clampf(h * 0.075, 9.0, 13.0))
	var nm: String = info.name.to_upper()
	var nw := UI.FONT_BODY_BOLD.get_string_size(nm, HORIZONTAL_ALIGNMENT_LEFT, -1, name_size).x
	draw_string(UI.FONT_BODY_BOLD, rect.position + Vector2((w - nw) * 0.5, h - 6.0), nm,
		HORIZONTAL_ALIGNMENT_LEFT, -1, name_size, Color(deep.r, deep.g, deep.b, 0.85 * base_alpha))

	# --- runestone flourish
	if rune:
		var star := "✦"
		var sw := UI.FONT_BODY_BOLD.get_string_size(star, HORIZONTAL_ALIGNMENT_LEFT, -1, 14).x
		draw_string(UI.FONT_BODY_BOLD, rect.position + Vector2(w - pad - sw - 2, h - 6.0), star,
			HORIZONTAL_ALIGNMENT_LEFT, -1, 14, Color(UI.GOLD_DEEP.r, UI.GOLD_DEEP.g, UI.GOLD_DEEP.b, base_alpha))

	# --- interactive rings
	if playable or selected:
		var pulse := 0.55 + 0.45 * sin(_t * 5.0)
		var ring_col := UI.GOLD
		ring_col.a = (0.55 + 0.45 * pulse) * alpha
		var ring := UI.flat(Color(0, 0, 0, 0), 12, ring_col, 3)
		draw_style_box(ring, rect.grow(2.0))
		var glow := UI.flat(Color(UI.GOLD.r, UI.GOLD.g, UI.GOLD.b, 0.12 * alpha), 14)
		draw_style_box(glow, rect.grow(5.0))

	if selected:
		var sel := UI.flat(Color(UI.GOLD.r, UI.GOLD.g, UI.GOLD.b, 0.10 * alpha), 11)
		draw_style_box(sel, rect)

	if capturable:
		var pulse2 := 0.5 + 0.5 * sin(_t * 4.0)
		var ring2 := UI.GOLD
		ring2.a = (0.35 + 0.45 * pulse2) * alpha
		var r2 := UI.flat(Color(0, 0, 0, 0), 12, ring2, 2)
		draw_style_box(r2, rect.grow(3.0))
		draw_string(UI.FONT_BODY_BOLD, rect.position + Vector2(w - 20, 20), "◆",
			HORIZONTAL_ALIGNMENT_LEFT, -1, 12, Color(UI.GOLD.r, UI.GOLD.g, UI.GOLD.b, alpha))

	if hinted:
		draw_circle(rect.position + Vector2(w - 12, 12), 5.0, Color(UI.GOLD.r, UI.GOLD.g, UI.GOLD.b, alpha))


func _draw_back(rect: Rect2, a: float) -> void:
	var w := rect.size.x
	var h := rect.size.y
	var themes := [Color("221a30"), Color("1b2a2f"), Color("2f1f22")]
	var golds := [UI.GOLD, Color("7fd4c1"), Color("e0a08a")]
	var base: Color = themes[back_style % themes.size()]
	var gold: Color = golds[back_style % golds.size()]
	var sh := UI.flat(Color(0, 0, 0, 0.4 * a), 11)
	draw_style_box(sh, rect)
	var bg := UI.flat(Color(base.r, base.g, base.b, a), 11)
	draw_style_box(bg, rect)
	# diagonal weave
	for i in range(-6, 12):
		var x := rect.position.x + i * 18.0
		draw_line(Vector2(x, rect.position.y + 4), Vector2(x + h * 0.6, rect.end.y - 4),
			Color(1, 1, 1, 0.045 * a), 2.0)
	# emblem
	var c := rect.position + rect.size * 0.5
	gold = Color(gold.r, gold.g, gold.b, 0.9 * a)
	draw_circle(c, minf(w, h) * 0.28, Color(UI.GOLD_DEEP.r, UI.GOLD_DEEP.g, UI.GOLD_DEEP.b, 0.18 * a))
	draw_arc(c, minf(w, h) * 0.28, 0, TAU, 40, gold, 1.6, true)
	draw_arc(c, minf(w, h) * 0.22, 0, TAU, 40, Color(gold.r, gold.g, gold.b, 0.5 * a), 1.0, true)
	var pts := PackedVector2Array()
	for i in range(4):
		var ang := -PI / 2 + i * TAU / 4.0
		pts.append(c + Vector2(cos(ang), sin(ang)) * minf(w, h) * 0.16)
	draw_colored_polygon(pts, Color(gold.r, gold.g, gold.b, 0.85 * a))
	var pts2 := PackedVector2Array()
	for i in range(4):
		var ang := PI / 4 + i * TAU / 4.0
		pts2.append(c + Vector2(cos(ang), sin(ang)) * minf(w, h) * 0.07)
	draw_colored_polygon(pts2, Color(gold.r, gold.g, gold.b, 0.5 * a))
	var bord := UI.flat(Color(0, 0, 0, 0), 11, Color(gold.r, gold.g, gold.b, a), 2)
	draw_style_box(bord, rect)


# ---------------------------------------------------------------------------
# FACTION EMBLEMS
# ---------------------------------------------------------------------------
func _draw_emblem(f: int, c: Vector2, s: float, ink: Color, accent: Color) -> void:
	match f:
		T.FORGE:
			_draw_forge(c, s, ink, accent)
		T.GROVE:
			_draw_grove(c, s, ink, accent)
		T.HORDE:
			_draw_horde(c, s, ink, accent)
		T.CROWN:
			_draw_crown(c, s, ink, accent)


func _draw_forge(c: Vector2, s: float, ink: Color, accent: Color) -> void:
	# hammer over an anvil, with sparks
	var anvil := PackedVector2Array([
		c + Vector2(-26, 2) * s, c + Vector2(26, 2) * s,
		c + Vector2(20, 12) * s, c + Vector2(8, 12) * s,
		c + Vector2(6, 22) * s, c + Vector2(14, 26) * s,
		c + Vector2(-14, 26) * s, c + Vector2(-6, 22) * s,
		c + Vector2(-8, 12) * s, c + Vector2(-20, 12) * s,
	])
	draw_colored_polygon(anvil, ink)
	# hammer
	var head := PackedVector2Array([
		c + Vector2(2, -26) * s, c + Vector2(24, -20) * s,
		c + Vector2(21, -10) * s, c + Vector2(0, -16) * s,
	])
	draw_colored_polygon(head, ink)
	draw_line(c + Vector2(6, -16) * s, c + Vector2(-6, 0) * s, ink, 4.0 * s, true)
	# sparks
	draw_circle(c + Vector2(-22, -14) * s, 2.6 * s, accent)
	draw_circle(c + Vector2(-30, -4) * s, 1.8 * s, accent)
	draw_circle(c + Vector2(-16, -24) * s, 1.6 * s, accent)


func _draw_grove(c: Vector2, s: float, ink: Color, accent: Color) -> void:
	# a leafed arch
	draw_line(c + Vector2(0, 26) * s, c + Vector2(0, -4) * s, ink, 4.0 * s, true)
	draw_line(c + Vector2(0, 6) * s, c + Vector2(-16, -8) * s, ink, 3.0 * s, true)
	draw_line(c + Vector2(0, 0) * s, c + Vector2(16, -12) * s, ink, 3.0 * s, true)
	for p in [Vector2(-16, -8), Vector2(16, -12), Vector2(0, -14)]:
		var leaf := PackedVector2Array([
			c + p * s, c + (p + Vector2(-9, -12)) * s, c + (p + Vector2(9, -12)) * s,
		])
		draw_colored_polygon(leaf, ink)
	draw_arc(c + Vector2(0, -18) * s, 22 * s, PI * 1.1, PI * 1.9, 18, ink, 3.0 * s, true)
	draw_circle(c + Vector2(0, -14) * s, 5.0 * s, accent)


func _draw_horde(c: Vector2, s: float, ink: Color, accent: Color) -> void:
	# crossed axes
	for sign_ in [-1.0, 1.0]:
		draw_line(c + Vector2(-20 * sign_, 24) * s, c + Vector2(20 * sign_, -20) * s, ink, 5.0 * s, true)
		var blade := PackedVector2Array([
			c + Vector2(20 * sign_, -20) * s,
			c + Vector2(30 * sign_, -32) * s,
			c + Vector2(34 * sign_, -18) * s,
			c + Vector2(22 * sign_, -10) * s,
		])
		draw_colored_polygon(blade, ink)
		draw_circle(c + Vector2(14 * sign_, -12) * s, 3.0 * s, accent)
	draw_circle(c, 6.0 * s, accent)


func _draw_crown(c: Vector2, s: float, ink: Color, accent: Color) -> void:
	# banner and crown
	draw_line(c + Vector2(-18, -28) * s, c + Vector2(-18, 26) * s, ink, 4.0 * s, true)
	var flag := PackedVector2Array([
		c + Vector2(-18, -28) * s, c + Vector2(22, -22) * s,
		c + Vector2(12, -12) * s, c + Vector2(22, -2) * s,
		c + Vector2(-18, 2) * s,
	])
	draw_colored_polygon(flag, ink)
	var crown := PackedVector2Array([
		c + Vector2(-12, 26) * s, c + Vector2(-12, 12) * s,
		c + Vector2(-4, 19) * s, c + Vector2(2, 10) * s,
		c + Vector2(8, 19) * s, c + Vector2(14, 12) * s,
		c + Vector2(14, 26) * s,
	])
	draw_colored_polygon(crown, accent)
	draw_circle(c + Vector2(1, 22) * s, 2.4 * s, ink)
