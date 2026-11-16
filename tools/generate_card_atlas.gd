extends SceneTree
## Offline generator for the three existing vector card backs only. This does
## NOT overwrite the shipped user-supplied face atlas. After regenerating backs,
## run: python3 tools/build_image_card_atlas.py
## Requires a real rendering display, never executed while playing.
const UI := preload("res://scripts/ui/ui.gd")
const Art := preload("res://scripts/ui/card_art.gd")
const W := 104
const H := 146
const SCALE := 2

class Painter extends Control:
	var back := 0
	func _draw() -> void:
		Art.draw_face(self, Rect2(0, 0, W, H), -1, back, 1.0, true)

func _initialize() -> void:
	if DisplayServer.get_name() == "headless":
		printerr("A rendering display is required to generate the card backs.")
		quit(1)
		return
	UI.LOW_SPEC = true
	UI.resolve_fonts()
	var vp := SubViewport.new()
	vp.size = Vector2i(3 * W * SCALE, H * SCALE)
	vp.transparent_bg = true
	vp.disable_3d = true
	vp.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	root.add_child(vp)
	for i in range(3):
		var p := Painter.new()
		p.back = i
		p.size = Vector2(W, H)
		p.scale = Vector2(SCALE, SCALE)
		p.position = Vector2(i * W * SCALE, 0)
		p.clip_contents = true
		vp.add_child(p)
	for i in range(3):
		await RenderingServer.frame_post_draw
	var image := vp.get_texture().get_image()
	if image == null or image.is_empty():
		printerr("Card back capture failed; not writing an empty asset.")
		quit(1)
		return
	var seen := {}
	for i in range(3):
		var tile := image.get_region(Rect2i(i * W * SCALE, 0, W * SCALE, H * SCALE))
		if tile.get_pixel(W, H).a < 0.9 or tile.get_pixel(0, 0).a > 0.05:
			printerr("Invalid or blank card back ", i, "; existing asset left untouched.")
			quit(1)
			return
		seen[hash(tile.get_data())] = true
	if seen.size() != 3:
		printerr("Card backs are not distinct; existing asset left untouched.")
		quit(1)
		return
	var path := ProjectSettings.globalize_path("res://tools/card_sources/card_backs.png")
	if image.save_png(path) != OK:
		printerr("Could not save card backs: ", path)
		quit(1)
		return
	print("Saved ", path, "; run tools/build_image_card_atlas.py to assemble the face atlas.")
	vp.queue_free()
	quit()
