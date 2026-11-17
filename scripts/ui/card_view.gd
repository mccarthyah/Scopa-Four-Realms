extends Control
## A single card, with pre-rendered artwork on software renderers.
## Live selection, highlights, lift and centre spin remain separate. The atlas
## is generated offline; missing assets fall back to the original vector art.
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
const EffectAtlas := preload("res://scripts/ui/effect_atlas.gd")

## Height / width of a card. One constant, shared with the table layout so the
## grid and the cards can never disagree about how tall a card is.
const ASPECT := 1.404

## Corner radius of a card, in pixels at the card's own scale. Derived from the
## card's size rather than fixed, so the rings and shadow around a card follow
## exactly the same curve as the card face - otherwise a small hand card would get
## a rounder halo than its own corners.

var card_id := -1
var face_up := true
var playable := false
var selected := false
var dim := false
var hinted := false
var capturable := false
var animated_in := false
## Rotation of the card about its own centre, in radians. A full turn is a real
## spin: the art stays face up throughout and the whole card rotates, rather than
## the card flattening and flipping to its back.
var spin := 0.0
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
	set_card_size(Vector2(w, h))
	_t = 0.0
	_fig = 0.0
	queue_redraw()
	return self


func set_card_size(card_size: Vector2) -> void:
	if custom_minimum_size == card_size and size == card_size:
		return
	custom_minimum_size = card_size
	size = card_size
	_styles_ready = false
	queue_redraw()


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
	# If the animation ever fails to advance we must not leave the card invisible:
	# a card the player cannot see is worse than a card that pops in.
	if _fig >= 1.0 and modulate.a < 0.999 and not dim:
		modulate.a = 1.0
	if dirty:
		queue_redraw()


func _gui_input(event: InputEvent) -> void:
	if event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_LEFT:
		pressed.emit()
		accept_event()
	elif event is InputEventScreenTouch and event.pressed:
		pressed.emit()
		accept_event()


## The transform used for the spin, exposed so it can be checked without
## rendering: a rotation about the card's CENTRE with no scale.
##
## Transform2D(angle, origin) rotates about the node origin, so passing the centre
## as `origin` rotates the card about (0,0) and swings its centre away by |centre|
## pixels - measured at 103 px for a 120x168 card. Rotating in place about point p
## needs origin = p - R*p, which is what this does.
func _spin_transform() -> Transform2D:
	var p := size * 0.5
	var basis := Transform2D(spin, Vector2.ZERO)
	return Transform2D(spin, p - basis.basis_xform(p))


func _draw() -> void:
	var fig := clampf(_fig, 0.0, 1.0)
	var ease_out := 1.0 - pow(1.0 - fig, 3.0)
	var draw_pos := Vector2(0, (1.0 - ease_out) * 26.0 + _lift)
	var rect := Rect2(draw_pos, size)
	var visible_rect := CardArt.visual_rect(rect)

	# --- spin: rotate about the card's centre. The Art draws in local space and
	# this rotates the whole drawing context; the art itself is untouched and stays
	# face up, so a full turn reads as a spin rather than a flip.
	var spinning: bool = absf(spin) > 0.0001
	var spin_origin := Vector2.ZERO
	if spinning:
		# rotate about the centre of the card where it currently sits
		var mid := draw_pos + size * 0.5
		var basis := Transform2D(spin, Vector2.ZERO)
		spin_origin = mid - basis.basis_xform(mid)
		draw_set_transform(spin_origin, spin, Vector2.ONE)
	var alpha := 1.0  # the node's modulate carries fade/dim; see _process


	# Each separate shadow alternates the effect texture with the face atlas,
	# splitting batches for every card. On software renderers omit that subtle
	# decoration when the supplied atlas is present; the card frames stay intact.
	# Keep vector shadows on full visual quality and when the atlas is missing.
	_ensure_styles()
	if _needs_separate_shadow():
		var shadow_rect := Rect2(visible_rect.position + Vector2(0, 3), visible_rect.size)
		draw_style_box(_sb_shadow, shadow_rect)

	# Use the supplied artwork on every renderer. Face cells already contain
	# transparent side margins; the legacy back cells are fitted to that width.
	var atlas_rect := rect if card_id >= 0 else visible_rect
	if not CardArt.draw_atlas_face(self, atlas_rect, card_id, back_style):
		CardArt.draw_face(self, visible_rect, card_id, back_style)

	if spinning:
		draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)

	# --- interaction feedback, still live (dim is handled by modulate)

	if playable or selected:
		var pulse := 0.55 + 0.45 * sin(_ring_phase)
		_sb_ring.border_color = Color(UI.GOLD.r, UI.GOLD.g, UI.GOLD.b, (0.55 + 0.45 * pulse) * alpha)
		if not UI.LOW_SPEC or not EffectAtlas.draw_sprite(self, visible_rect.grow(2.0), EffectAtlas.PLAYABLE_RING,
				Color(1, 1, 1, _sb_ring.border_color.a)):
			draw_style_box(_sb_ring, visible_rect.grow(2.0))
		_sb_glow.bg_color = Color(UI.GOLD.r, UI.GOLD.g, UI.GOLD.b, 0.12 * alpha)
		if not UI.LOW_SPEC or not EffectAtlas.draw_sprite(self, visible_rect.grow(5.0), EffectAtlas.GLOW):
			draw_style_box(_sb_glow, visible_rect.grow(5.0))

	if selected:
		_sb_sel.bg_color = Color(UI.GOLD.r, UI.GOLD.g, UI.GOLD.b, 0.10 * alpha)
		if not UI.LOW_SPEC or not EffectAtlas.draw_sprite(self, visible_rect, EffectAtlas.SELECTED):
			draw_style_box(_sb_sel, visible_rect)

	if capturable:
		var pulse2 := 0.5 + 0.5 * sin(_ring_phase * 0.8)
		_sb_cap.border_color = Color(UI.GOLD.r, UI.GOLD.g, UI.GOLD.b, (0.35 + 0.45 * pulse2) * alpha)
		if not UI.LOW_SPEC or not EffectAtlas.draw_sprite(self, visible_rect.grow(3.0), EffectAtlas.CAPTURE_RING,
				Color(1, 1, 1, _sb_cap.border_color.a)):
			draw_style_box(_sb_cap, visible_rect.grow(3.0))
		draw_string(UI.font_bold(), visible_rect.position + Vector2(visible_rect.size.x - 20, 20), "◆",
			HORIZONTAL_ALIGNMENT_LEFT, -1, 12, Color(UI.GOLD.r, UI.GOLD.g, UI.GOLD.b, alpha))

	if hinted:
		draw_circle(visible_rect.position + Vector2(visible_rect.size.x - 12, 12), 5.0,
			Color(UI.GOLD.r, UI.GOLD.g, UI.GOLD.b, alpha))


## Keep fallback art legible while avoiding an effect/face texture switch for
## every card on the software path when the prebuilt atlas is available.
static func _needs_separate_shadow() -> bool:
	return not UI.LOW_SPEC or CardArt.atlas_texture() == null


## Corner radius for a rect of this size, matching the card art exactly.
static func _radius_for(sz: Vector2) -> int:
	return CardArt.corner_radius(Rect2(Vector2.ZERO, sz))


func _ensure_styles() -> void:
	if _styles_ready:
		return
	_styles_ready = true
	var visual_size := CardArt.visual_rect(Rect2(Vector2.ZERO, size)).size
	var r := _radius_for(visual_size)
	_sb_ring = UI.flat(Color(0, 0, 0, 0), r, UI.GOLD, 3, true)
	_sb_glow = UI.flat(Color(UI.GOLD.r, UI.GOLD.g, UI.GOLD.b, 0.12), _radius_for(visual_size + Vector2(10, 10)), Color(0, 0, 0, 0), 0, true)
	_sb_sel = UI.flat(Color(UI.GOLD.r, UI.GOLD.g, UI.GOLD.b, 0.10), r, Color(0, 0, 0, 0), 0, true)
	_sb_cap = UI.flat(Color(0, 0, 0, 0), _radius_for(visual_size + Vector2(6, 6)), UI.GOLD, 2, true)
	_sb_shadow = UI.flat(Color(0, 0, 0, 0.28), r, Color(0,0,0,0), 0, true)
