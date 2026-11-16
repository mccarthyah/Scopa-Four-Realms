extends RefCounted
## Offline-generated card decorations and small HUD sprites. No viewport capture
## or readback happens at runtime. Missing assets fall back to vector drawing.
class_name EffectAtlas

const PATH := "res://assets/cards/effect_atlas.png"
const WIDTH := 1040
const HEIGHT := 388
const CELL := Vector2i(208, 292)
const SHADOW := 0
const PLAYABLE_RING := 1
const GLOW := 2
const SELECTED := 3
const CAPTURE_RING := 4
const SIGIL := 5
const FAVOR_EMPTY := 6
const FAVOR_FILLED := 7
static var _checked := false
static var _texture: Texture2D = null


static func texture() -> Texture2D:
	if not _checked:
		_checked = true
		if ResourceLoader.exists(PATH):
			var res = load(PATH)
			if res is Texture2D and res.get_width() == WIDTH and res.get_height() == HEIGHT:
				_texture = res
		if _texture == null:
			push_warning("Scopa: effects atlas unavailable; using vector decorations")
	return _texture


static func region(kind: int) -> Rect2:
	if kind >= SHADOW and kind <= CAPTURE_RING:
		return Rect2(kind * CELL.x, 0, CELL.x, CELL.y)
	match kind:
		SIGIL: return Rect2(0, CELL.y, 96, 96)
		FAVOR_EMPTY: return Rect2(96, CELL.y, 32, 32)
		FAVOR_FILLED: return Rect2(128, CELL.y, 32, 32)
	return Rect2()


static func draw_sprite(target: CanvasItem, rect: Rect2, kind: int, tint: Color = Color.WHITE) -> bool:
	var src := region(kind)
	var tex := texture()
	if tex == null or src.size == Vector2.ZERO:
		return false
	target.draw_texture_rect_region(tex, rect, src, tint, false, true)
	return true
