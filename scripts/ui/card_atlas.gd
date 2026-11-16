extends Node
## Bakes each card face into a texture once, at startup, so that drawing a card
## later costs exactly one textured quad.
##
## Why this exists: the game used to draw every card from ~60 vector primitives
## on every frame — six StyleBoxFlat allocations (one with an 8px shadow blur),
## emblem polygons, arcs, and four glyph measurements each. On a machine with no
## GPU (Windows "Microsoft Basic Render Driver", llvmpipe, SwiftShader) that is
## pure CPU rasterisation and it dominated frame time: ~250 draw calls and 17k
## primitives per frame, 30-45ms each.
##
## A card face never changes, so it is rasterised once into an ImageTexture and
## afterwards blitted. 40 faces + 3 backs = 43 small textures (about 5 MB) and
## one draw call per card per frame.
##
## Robustness: if capture fails for any reason the atlas disables itself, every
## card silently keeps a cheap vector look, and a line is written to the log.
## Nothing can end up blank.
class_name CardAtlas

const UI := preload("res://scripts/ui/ui.gd")
const T := preload("res://scripts/tables.gd")
const C := preload("res://scripts/game/cards.gd")

## Canonical raster size. Cards are drawn at or below this and scaled down, which
## stays sharp; scaling down also looks better than scaling up.
const FACE_W := 148
const FACE_H := 208

## In low-spec mode every card pixel is filtered and stretched on the CPU, so the
## atlas bakes smaller and the cards are drawn at their natural size.
const FACE_W_LOW := 120
const FACE_H_LOW := 168

static var _tex := {}          # key -> ImageTexture
static var _all_done := false
static var _failed := false


static func _key(card_id: int, back_style: int) -> String:
	return "b%d" % back_style if card_id < 0 else "c%d" % card_id


## The size faces are baked at for this machine.
static func bake_size() -> Vector2i:
	return Vector2i(FACE_W_LOW, FACE_H_LOW) if UI.LOW_SPEC else Vector2i(FACE_W, FACE_H)


static func is_available() -> bool:
	return not _failed


## True only if this renderer can actually hand back a rendered image. The dummy
## renderer used by --headless cannot, and asking it produces a scary
## "texture_2d_get: Parameter t is null" in the log, so we never ask.
static var _checked := false
static var _can_bake := true


static func _renderer_can_bake() -> bool:
	if not _checked:
		_checked = true
		_can_bake = DisplayServer.get_name() != "headless" \
			and RenderingServer.get_video_adapter_name() != ""
	return _can_bake


## The baked texture, or null if it is not ready yet (call request() then).
static func texture(card_id: int, back_style: int = 0) -> Texture2D:
	return _tex.get(_key(card_id, back_style), null)


## Safety net: if the boot-time bake did not happen (it normally runs from
## main.gd before any card exists), make sure it does. Never bakes per card.
static func request(host: Node, _card_id: int = 0, _back_style: int = 0) -> void:
	if _failed or _all_done or not is_instance_valid(host) or not host.is_inside_tree():
		return
	if not _renderer_can_bake():
		_failed = true  # headless / dummy renderer: cards use flat fallback faces
		return
	bake_all(host.get_tree())


static func bake_all(tree: SceneTree) -> bool:
	if _failed or _all_done or not _renderer_can_bake():
		return _all_done
	_all_done = true
	var fw := bake_size().x
	var fh := bake_size().y
	var cols := 5
	var ids: Array = []
	for i in range(C.DECK_SIZE):
		ids.append(i)
	var rows := int(ceil(float(ids.size()) / float(cols)))
	var sheet := SubViewport.new()
	sheet.size = Vector2i(fw * cols, fh * rows)
	sheet.transparent_bg = true
	sheet.disable_3d = true
	sheet.render_target_update_mode = SubViewport.UPDATE_ONCE
	# backs go in the last row
	var back_count := 3
	var grid := Control.new()
	grid.size = Vector2(sheet.size)
	grid.mouse_filter = Control.MOUSE_FILTER_IGNORE
	sheet.add_child(grid)
	for idx in range(ids.size()):
		var p := Painter.new()
		p.card_id = int(ids[idx])
		p.size = Vector2(fw, fh)
		p.position = Vector2((idx % cols) * fw, (idx / cols) * fh)
		grid.add_child(p)
	for b in range(back_count):
		var p2 := Painter.new()
		p2.card_id = -1
		p2.back_style = b
		p2.size = Vector2(fw, fh)
		var slot: int = ids.size() + b
		p2.position = Vector2((slot % cols) * fw, (slot / cols) * fh)
		grid.add_child(p2)
	tree.root.add_child(sheet)
	# Frames, not RenderingServer.frame_post_draw: that signal never fires on
	# some renderers and awaiting it would hang here forever.
	await tree.process_frame
	await tree.process_frame
	await tree.process_frame
	var vt := sheet.get_texture()
	var img: Image = vt.get_image() if vt != null else null
	tree.root.remove_child(sheet)
	sheet.free()
	if img == null:
		_failed = true
		return false
	# slice the sheet into individual textures
	for idx in range(ids.size()):
		var r := Rect2i((idx % cols) * fw, (idx / cols) * fh, fw, fh)
		var sub := img.get_region(r)
		if sub != null and not sub.is_empty():
			_tex["c%d" % int(ids[idx])] = ImageTexture.create_from_image(sub)
	for b in range(back_count):
		var slot2: int = ids.size() + b
		var r2 := Rect2i((slot2 % cols) * fw, (slot2 / cols) * fh, fw, fh)
		var sub2 := img.get_region(r2)
		if sub2 != null and not sub2.is_empty():
			_tex["b%d" % b] = ImageTexture.create_from_image(sub2)
	if _tex.is_empty():
		_failed = true
		return false
	return true


# ---------------------------------------------------------------------------
# PAINTER — the card artwork. This is the original vector drawing, unchanged in
# appearance; it now happens once per card into a texture instead of per frame.
# ---------------------------------------------------------------------------
class Painter extends Control:
	var card_id := -1
	var back_style := 0

	func _ready() -> void:
		mouse_filter = Control.MOUSE_FILTER_IGNORE

	func _draw() -> void:
		var rect := Rect2(Vector2.ZERO, size)
		if card_id < 0:
			_draw_back(rect)
			return
		var f := C.faction(card_id)
		var r := C.rank(card_id)
		var info: Dictionary = T.FACTIONS[f]
		var col: Color = info.color
		var deep: Color = info.deep
		var pale: Color = info.pale
		var rune := C.is_runestone(card_id)
		var w := size.x
		var h := size.y

		# The face fills the texture exactly, so the drop shadow is drawn live by
		# CardView (a baked one would be clipped at the texture edge).

		# --- parchment face
		draw_style_box(UI.flat(Color(UI.PARCHMENT.r, UI.PARCHMENT.g, UI.PARCHMENT.b, 1.0), 11), rect)
		draw_style_box(UI.flat(Color(1, 1, 1, 0.30), 11), Rect2(rect.position, Vector2(w, h * 0.42)))

		# --- border
		var border_col := UI.GOLD if rune else Color(deep.r, deep.g, deep.b, 0.55)
		var bw := 3 if rune else 2
		draw_style_box(UI.flat(Color(0, 0, 0, 0), 11, border_col, bw), rect)

		# --- layout: big rank top-left, art window, name strip
		var pad := 7.0
		var rank_band := h * 0.44
		var strip_h := 18.0
		var art_rect := Rect2(rect.position + Vector2(pad, rank_band),
			Vector2(w - pad * 2, h - rank_band - strip_h - pad * 0.6))

		draw_style_box(UI.flat(deep, 8), art_rect)
		draw_style_box(UI.flat(Color(col.r, col.g, col.b, 0.30), 8),
			Rect2(art_rect.position, Vector2(art_rect.size.x, art_rect.size.y * 0.42)))
		var art_center := art_rect.position + art_rect.size * 0.5
		var s := minf(art_rect.size.x, art_rect.size.y) / 100.0
		_draw_emblem(f, art_center, s, Color(pale.r, pale.g, pale.b, 0.95), Color(col.r, col.g, col.b, 0.55))

		# --- rank numeral, large, top-left
		var num_size := int(h * 0.34)
		var num_h := UI.font_title().get_string_size("8", HORIZONTAL_ALIGNMENT_LEFT, -1, num_size).y
		draw_string(UI.font_title(), rect.position + Vector2(pad + 3, rank_band * 0.5 + num_h * 0.34),
			str(r), HORIZONTAL_ALIGNMENT_LEFT, -1, num_size, deep)

		# --- faction glyph, top-right
		var glyph_w := UI.font_bold().get_string_size(T.SUIT_GLYPH[f], HORIZONTAL_ALIGNMENT_LEFT, -1, 20).x
		draw_string(UI.font_bold(), rect.position + Vector2(w - pad - glyph_w - 2, rank_band * 0.52),
			T.SUIT_GLYPH[f], HORIZONTAL_ALIGNMENT_LEFT, -1, 20, col)

		draw_line(rect.position + Vector2(pad + 2, rank_band - 3),
			rect.position + Vector2(w - pad - 2, rank_band - 3),
			Color(deep.r, deep.g, deep.b, 0.22), 1.0)

		# --- name strip along the bottom
		var name_size := int(clampf(h * 0.075, 9.0, 13.0))
		var nm: String = str(info.name).to_upper()
		var nw := UI.font_bold().get_string_size(nm, HORIZONTAL_ALIGNMENT_LEFT, -1, name_size).x
		draw_string(UI.font_bold(), rect.position + Vector2((w - nw) * 0.5, h - 6.0), nm,
			HORIZONTAL_ALIGNMENT_LEFT, -1, name_size, Color(deep.r, deep.g, deep.b, 0.85))

		# --- runestone flourish
		if rune:
			var star := "✦"
			var sw := UI.font_bold().get_string_size(star, HORIZONTAL_ALIGNMENT_LEFT, -1, 14).x
			draw_string(UI.font_bold(), rect.position + Vector2(w - pad - sw - 2, h - 6.0), star,
				HORIZONTAL_ALIGNMENT_LEFT, -1, 14, UI.GOLD_DEEP)


	func _draw_back(rect: Rect2) -> void:
		var w := rect.size.x
		var h := rect.size.y
		var themes := [Color("221a30"), Color("1b2a2f"), Color("2f1f22")]
		var golds := [UI.GOLD, Color("7fd4c1"), Color("e0a08a")]
		var base: Color = themes[back_style % themes.size()]
		var gold: Color = golds[back_style % golds.size()]
		draw_style_box(UI.flat(base, 11), rect)
		# diagonal weave
		for i in range(-6, 12):
			var x := rect.position.x + i * 18.0
			draw_line(Vector2(x, rect.position.y + 4), Vector2(x + h * 0.6, rect.end.y - 4),
				Color(1, 1, 1, 0.045), 2.0)
		# emblem
		var c := rect.position + rect.size * 0.5
		var gold_a := Color(gold.r, gold.g, gold.b, 0.9)
		draw_circle(c, minf(w, h) * 0.28, Color(UI.GOLD_DEEP.r, UI.GOLD_DEEP.g, UI.GOLD_DEEP.b, 0.18))
		draw_arc(c, minf(w, h) * 0.28, 0, TAU, 40, gold_a, 1.6, true)
		draw_arc(c, minf(w, h) * 0.22, 0, TAU, 40, Color(gold.r, gold.g, gold.b, 0.5), 1.0, true)
		var pts := PackedVector2Array()
		for i in range(4):
			var ang := -PI / 2 + i * TAU / 4.0
			pts.append(c + Vector2(cos(ang), sin(ang)) * minf(w, h) * 0.16)
		draw_colored_polygon(pts, Color(gold.r, gold.g, gold.b, 0.85))
		var pts2 := PackedVector2Array()
		for i in range(4):
			var ang := PI / 4 + i * TAU / 4.0
			pts2.append(c + Vector2(cos(ang), sin(ang)) * minf(w, h) * 0.07)
		draw_colored_polygon(pts2, Color(gold.r, gold.g, gold.b, 0.5))
		draw_style_box(UI.flat(Color(0, 0, 0, 0), 11, gold, 2), rect)


	# -----------------------------------------------------------------------
	# FACTION EMBLEMS
	# -----------------------------------------------------------------------
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
		var anvil := PackedVector2Array([
			c + Vector2(-26, 2) * s, c + Vector2(26, 2) * s,
			c + Vector2(20, 12) * s, c + Vector2(8, 12) * s,
			c + Vector2(6, 22) * s, c + Vector2(14, 26) * s,
			c + Vector2(-14, 26) * s, c + Vector2(-6, 22) * s,
			c + Vector2(-8, 12) * s, c + Vector2(-20, 12) * s,
		])
		draw_colored_polygon(anvil, ink)
		var head := PackedVector2Array([
			c + Vector2(2, -26) * s, c + Vector2(24, -20) * s,
			c + Vector2(21, -10) * s, c + Vector2(0, -16) * s,
		])
		draw_colored_polygon(head, ink)
		draw_line(c + Vector2(6, -16) * s, c + Vector2(-6, 0) * s, ink, 4.0 * s, true)
		draw_circle(c + Vector2(-22, -14) * s, 2.6 * s, accent)
		draw_circle(c + Vector2(-30, -4) * s, 1.8 * s, accent)
		draw_circle(c + Vector2(-16, -24) * s, 1.6 * s, accent)


	func _draw_grove(c: Vector2, s: float, ink: Color, accent: Color) -> void:
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
