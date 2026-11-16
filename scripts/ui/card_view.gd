extends Control
## A single card. The face is a baked texture (see card_atlas.gd) drawn as one
## quad, so a table of cards costs a handful of draw calls per frame instead of
## ~250. Everything animated — lift, glow rings, selection, capturable pulse —
## stays live and cheap.
##
## If the atlas cannot bake (headless, or a renderer that refuses capture) the
## card falls back to a light vector drawing. It never renders nothing.
class_name CardView

const UI := preload("res://scripts/ui/ui.gd")

signal pressed(card_id: int)

const T := preload("res://scripts/tables.gd")
const C := preload("res://scripts/game/cards.gd")
const CardAtlas := preload("res://scripts/ui/card_atlas.gd")

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

# Interactive styles, built once per card and only recoloured.
var _sb_ring: StyleBoxFlat
var _sb_glow: StyleBoxFlat
var _sb_sel: StyleBoxFlat
var _sb_cap: StyleBoxFlat
var _sb_shadow: StyleBoxFlat
var _styles_ready := false
var _ring_phase := 0.0
var _last_pulse := -1.0


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_STOP
	# setup() may already have sized us; only fall back to the default card size
	if not _sized:
		custom_minimum_size = Vector2(UI.CARD_W, UI.CARD_H)
		size = custom_minimum_size
	set_process(true)
	_request_texture()


func setup(id: int, up: bool = true, w: int = UI.CARD_W, h: int = UI.CARD_H) -> CardView:
	card_id = id
	face_up = up
	_sized = true
	custom_minimum_size = Vector2(w, h)
	size = Vector2(w, h)
	_t = 0.0
	_fig = 0.0
	queue_redraw()
	_request_texture()
	return self


func _request_texture() -> void:
	if is_inside_tree():
		CardAtlas.request(self, card_id, back_style)


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
	_ring_phase = fmod(_t * 5.0, TAU)
	var dirty := false
	if _fig < 1.0:
		_fig = minf(1.0, _fig + delta * 3.4)
		dirty = true
	if absf(_lift - _target_lift) > 0.4:
		_lift = lerpf(_lift, _target_lift, 1.0 - pow(0.001, delta))
		dirty = true
	else:
		_lift = _target_lift
	var target_glow := 1.0 if playable else 0.0
	if absf(_glow - target_glow) > 0.01:
		_glow = lerpf(_glow, target_glow, 1.0 - pow(0.002, delta))
		dirty = true
	# Only repaint the pulse while its phase has visibly moved.
	if playable or selected or capturable:
		if absf(_ring_phase - _last_pulse) > 0.02:
			_last_pulse = _ring_phase
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
	var fig := clampf(_fig, 0.0, 1.0)
	var ease_out := 1.0 - pow(1.0 - fig, 3.0)
	var draw_pos := Vector2(0, (1.0 - ease_out) * 26.0 + _lift)
	var rect := Rect2(draw_pos, size)
	var alpha := fig
	var base_alpha := alpha * (0.6 if dim else 1.0)

	# --- drop shadow: one cheap quad, no blur pass
	_ensure_styles()
	draw_style_box(_sb_shadow, Rect2(rect.position + Vector2(0, 3), rect.size))

	# --- the card itself: one textured quad
	var tex := CardAtlas.texture(card_id, back_style)
	if tex != null:
		draw_texture_rect(tex, rect, false, Color(1, 1, 1, base_alpha))
	else:
		_draw_fallback(rect, base_alpha)
		_request_texture()

	# --- interaction feedback, still live
	if dim:
		draw_rect(rect, Color(0, 0, 0, 0.35 * alpha))

	if playable or selected:
		var pulse := 0.55 + 0.45 * sin(_ring_phase)
		_sb_ring.border_color = Color(UI.GOLD.r, UI.GOLD.g, UI.GOLD.b, (0.55 + 0.45 * pulse) * alpha)
		draw_style_box(_sb_ring, rect.grow(2.0))
		_sb_glow.bg_color = Color(UI.GOLD.r, UI.GOLD.g, UI.GOLD.b, 0.12 * alpha)
		draw_style_box(_sb_glow, rect.grow(5.0))

	if selected:
		_sb_sel.bg_color = Color(UI.GOLD.r, UI.GOLD.g, UI.GOLD.b, 0.10 * alpha)
		draw_style_box(_sb_sel, rect)

	if capturable:
		var pulse2 := 0.5 + 0.5 * sin(_ring_phase * 0.8)
		_sb_cap.border_color = Color(UI.GOLD.r, UI.GOLD.g, UI.GOLD.b, (0.35 + 0.45 * pulse2) * alpha)
		draw_style_box(_sb_cap, rect.grow(3.0))
		draw_string(UI.font_bold(), rect.position + Vector2(size.x - 20, 20), "◆",
			HORIZONTAL_ALIGNMENT_LEFT, -1, 12, Color(UI.GOLD.r, UI.GOLD.g, UI.GOLD.b, alpha))

	if hinted:
		draw_circle(rect.position + Vector2(size.x - 12, 12), 5.0,
			Color(UI.GOLD.r, UI.GOLD.g, UI.GOLD.b, alpha))


## Deliberately crude: shown only for a frame or two while the texture bakes, or
## if capture is impossible. Keeping it cheap matters more than making it pretty.
func _draw_fallback(rect: Rect2, a: float) -> void:
	var face := Color(UI.PARCHMENT.r, UI.PARCHMENT.g, UI.PARCHMENT.b, a) if face_up \
		else Color(0.13, 0.10, 0.19, a)
	draw_rect(rect, face)
	if not face_up or card_id < 0:
		return
	var info: Dictionary = T.FACTIONS[C.faction(card_id)]
	var col: Color = info.color
	draw_rect(Rect2(rect.position + Vector2(7, size.y * 0.44),
		Vector2(size.x - 14, size.y * 0.42)), Color(col.r, col.g, col.b, 0.35 * a))
	draw_string(UI.font_title(), rect.position + Vector2(10, size.y * 0.34), str(C.rank(card_id)),
		HORIZONTAL_ALIGNMENT_LEFT, -1, int(size.y * 0.34), Color(0.05, 0.04, 0.08, a))


func _ensure_styles() -> void:
	if _styles_ready:
		return
	_styles_ready = true
	_sb_ring = UI.flat(Color(0, 0, 0, 0), 12, UI.GOLD, 3)
	_sb_glow = UI.flat(Color(UI.GOLD.r, UI.GOLD.g, UI.GOLD.b, 0.12), 14)
	_sb_sel = UI.flat(Color(UI.GOLD.r, UI.GOLD.g, UI.GOLD.b, 0.10), 11)
	_sb_cap = UI.flat(Color(0, 0, 0, 0), 12, UI.GOLD, 2)
	_sb_shadow = UI.flat(Color(0, 0, 0, 0.28), 12)
