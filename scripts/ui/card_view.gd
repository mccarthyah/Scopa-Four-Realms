extends Control
## A single card, drawn directly as vectors (see card_art.gd).
##
## Everything animated — lift, glow rings, selection, capturable pulse — is live.
## Drawing direct rather than from a baked texture is deliberate: baking needed a
## pixel readback per card, which is a hard CPU/GPU sync and cost milliseconds on
## a software rasteriser, and an empty capture silently produced blank cards.
class_name CardView

const UI := preload("res://scripts/ui/ui.gd")

## Emitted on tap/click. Carries NO argument: callers connect with
## `pressed.connect(_on_card.bind(id))`, so the id arrives via bind(). This used
## to be declared as `signal pressed(card_id: int)` AND bound at the call site,
## which made every handler receive two arguments and fail with "Method expected
## 1 argument(s), but called with 2" — so cards were never playable.
signal pressed()

const T := preload("res://scripts/tables.gd")
const C := preload("res://scripts/game/cards.gd")
const CardArt := preload("res://scripts/ui/card_art.gd")

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
var _reported := false

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
	# clip_contents forces a stencil pass for the node every frame. Cards are
	# already drawn inside their own rect, so clipping buys nothing.
	clip_contents = false
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
	# The deal-in fade belongs on the node, not inside _draw. Set here, where it
	# cannot be corrupted by a draw-time multiply/divide round trip.
	var a := clampf(_fig, 0.0, 1.0) * (0.6 if dim else 1.0)
	if not is_finite(a):
		a = 1.0
	modulate.a = a
	if dirty:
		queue_redraw()


func _gui_input(event: InputEvent) -> void:
	if event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_LEFT:
		pressed.emit()
		accept_event()
	elif event is InputEventScreenTouch and event.pressed:
		pressed.emit()
		accept_event()


func _draw() -> void:
	var fig := clampf(_fig, 0.0, 1.0)
	var ease_out := 1.0 - pow(1.0 - fig, 3.0)
	var draw_pos := Vector2(0, (1.0 - ease_out) * 26.0 + _lift)
	var rect := Rect2(draw_pos, size)
	var alpha := 1.0  # the node's modulate carries fade/dim; see _process

	# One-time proof that a card really drew, with the numbers that would reveal a
	# degenerate rect or a bad modulate — so a blank card can be diagnosed from the
	# log instead of guessed at.
	if not _reported:
		_reported = true
		print("[scopa] card draw    : id=", card_id, " view=", size, " rect=", rect,
			" alpha=", snappedf(modulate.a, 0.01), " clip=", clip_contents)

	# --- drop shadow: one cheap quad, no blur pass
	_ensure_styles()
	draw_style_box(_sb_shadow, Rect2(rect.position + Vector2(0, 3), rect.size))

	# --- the card itself, drawn direct
	CardArt.draw_face(self, rect, card_id, back_style)

	# --- interaction feedback, still live (dim is handled by modulate)

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


func _ensure_styles() -> void:
	if _styles_ready:
		return
	_styles_ready = true
	_sb_ring = UI.flat(Color(0, 0, 0, 0), 12, UI.GOLD, 3)
	_sb_glow = UI.flat(Color(UI.GOLD.r, UI.GOLD.g, UI.GOLD.b, 0.12), 14)
	_sb_sel = UI.flat(Color(UI.GOLD.r, UI.GOLD.g, UI.GOLD.b, 0.10), 11)
	_sb_cap = UI.flat(Color(0, 0, 0, 0), 12, UI.GOLD, 2)
	_sb_shadow = UI.flat(Color(0, 0, 0, 0.28), 12)
