extends SceneTree
## Offline only: godot --path . -s res://tools/generate_effect_atlas.gd
## Transparent 2x sprites for card effects, the felt sigil and Favor pips.
const UI := preload("res://scripts/ui/ui.gd")
const CW := 208
const CH := 292
const ATLAS_W := CW * 5
const ATLAS_H := CH + 96

class EffectPainter extends Control:
	var kind := 0
	func _draw() -> void:
		var box: StyleBoxFlat
		match kind:
			0: box = UI.flat(Color(0, 0, 0, 0.28), 5, Color.TRANSPARENT, 0, true)
			1: box = UI.flat(Color.TRANSPARENT, 5, UI.GOLD, 3, true)
			2: box = UI.flat(Color(UI.GOLD.r, UI.GOLD.g, UI.GOLD.b, 0.12), 5, Color.TRANSPARENT, 0, true)
			3: box = UI.flat(Color(UI.GOLD.r, UI.GOLD.g, UI.GOLD.b, 0.10), 5, Color.TRANSPARENT, 0, true)
			4: box = UI.flat(Color.TRANSPARENT, 5, UI.GOLD, 2, true)
		draw_style_box(box, Rect2(0, 0, 104, 146))

class IconPainter extends Control:
	var kind := 0
	func _draw() -> void:
		match kind:
			0:
				draw_arc(Vector2(24, 24), 22, 0, TAU, 26, Color(UI.GOLD.r, UI.GOLD.g, UI.GOLD.b, 0.07), 1.0, true)
			1:
				draw_arc(Vector2(8, 8), 6, 0, TAU, 18, Color("4a3f5e"), 1.4, true)
			2:
				draw_circle(Vector2(8, 8), 6, UI.GOLD)
				draw_circle(Vector2(8, 8), 3, Color("fff6dd"))

func _initialize() -> void:
	if DisplayServer.get_name() == "headless":
		printerr("A rendering display is required to generate the effects atlas.")
		quit(1)
		return
	UI.LOW_SPEC = true
	var vp := SubViewport.new()
	vp.size = Vector2i(ATLAS_W, ATLAS_H)
	vp.transparent_bg = true
	vp.disable_3d = true
	vp.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	root.add_child(vp)
	for i in range(5):
		var p := EffectPainter.new()
		p.kind = i
		p.size = Vector2(104, 146)
		p.scale = Vector2(2, 2)
		p.position = Vector2(i * CW, 0)
		p.clip_contents = true
		vp.add_child(p)
	for i in range(3):
		var p := IconPainter.new()
		p.kind = i
		p.size = Vector2(48, 48) if i == 0 else Vector2(16, 16)
		p.scale = Vector2(2, 2)
		p.position = Vector2(0 if i == 0 else (96 + (i - 1) * 32), CH)
		p.clip_contents = true
		vp.add_child(p)
	for i in range(3):
		await RenderingServer.frame_post_draw
	var image := vp.get_texture().get_image()
	if image == null or image.is_empty():
		printerr("No rendered atlas; existing asset left untouched.")
		quit(1)
		return
	# Check transparent corners, readable centers, and visible ring/pip pixels.
	if image.get_pixel(0, 0).a > 0.05 or image.get_pixel(104, 146).a < 0.2 \
			or image.get_pixel(CW + 104, 146).a > 0.05 \
			or image.get_pixel(CW + 104, 4).a < 0.8 \
			or image.get_pixel(2 * CW + 104, 146).a < 0.08 \
			or image.get_pixel(3 * CW + 104, 146).a < 0.07 \
			or image.get_pixel(4 * CW + 104, 4).a < 0.1 \
			or image.get_pixel(48, CH + 4).a < 0.02 \
			or image.get_pixel(112, CH + 4).a < 0.5 \
			or image.get_pixel(128 + 16, CH + 16).a < 0.5:
		printerr("Invalid effect atlas; existing asset left untouched.")
		quit(1)
		return
	# Transparent viewport pixels are premultiplied. The imported PNG is drawn
	# with straight-alpha blending, so unpremultiply before saving. Otherwise a
	# translucent gold glow becomes nearly black and tints the cards gray.
	for y in range(image.get_height()):
		for x in range(image.get_width()):
			var c := image.get_pixel(x, y)
			if c.a > 0.0 and c.a < 1.0:
				image.set_pixel(x, y, Color(minf(c.r / c.a, 1.0), minf(c.g / c.a, 1.0), minf(c.b / c.a, 1.0), c.a))
	var err := image.save_png(ProjectSettings.globalize_path("res://assets/cards/effect_atlas.png"))
	if err != OK:
		printerr("Saving effect atlas failed: ", err)
		quit(1)
		return
	print("Saved effects atlas: ", image.get_size())
	vp.queue_free()
	quit()
