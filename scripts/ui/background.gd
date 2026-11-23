extends Control
# gdlint: disable=class-definitions-order
# Declarations here are grouped for readability (constants beside the tables
# they describe, fields beside the build code that fills them) rather than
# strictly consts-before-vars. Ordering is a style rule with no runtime effect;
# see docs/ASSESSMENT.md.

## A single pre-rendered fantasy landscape, shared by menu and duel.
## It is drawn as one opaque, aspect-cover quad; no runtime readback, baking,
## extra full-screen overlays or animated full-screen effects are required.
class_name RealmBackground

const ART := preload("res://assets/branding/realm_background.png")

func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	texture_filter = CanvasItem.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)


## The artwork carries its own palette, so both screens pass colours that are
## deliberately unused; kept so a caller does not have to special-case us.
## (set_quiet() used to live here as an empty method. Its only caller measured
## FPS and then printed "background animations paused" - the one thing this
## backdrop cannot do, since it has no animations. That call is gone; do not
## reintroduce a no-op hook just to keep a log line honest.)
func set_accents(_a: Color, _b: Color) -> void:
	pass


# gdlint: enable=class-definitions-order
func _notification(what: int) -> void:
	if what == NOTIFICATION_RESIZED:
		queue_redraw()


func _draw() -> void:
	if size.x <= 0 or size.y <= 0:
		return
	var image_size := Vector2(ART.get_width(), ART.get_height())
	var cover := maxf(size.x / image_size.x, size.y / image_size.y)
	var source_size := size / cover
	var source := Rect2((image_size - source_size) * 0.5, source_size)
	draw_texture_rect_region(ART, Rect2(Vector2.ZERO, size), source, Color(0.72, 0.75, 0.80, 1.0))
