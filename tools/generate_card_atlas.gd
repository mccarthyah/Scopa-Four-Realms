extends SceneTree
## Offline asset generator: run with a real rendering display, never at game boot.
## godot --path . -s res://tools/generate_card_atlas.gd
## 40 faces in card-id order, then the three backs.  Each 104x146 face is
## rendered at 2x resolution from the vector source into a transparent PNG.
const UI := preload("res://scripts/ui/ui.gd")
const Art := preload("res://scripts/ui/card_art.gd")
const COLS := 8
const ROWS := 6
const SCALE := 2
const W := 104
const H := 146

class Painter extends Control:
	var id := 0
	var back := 0
	func _draw() -> void:
		Art.draw_face(self, Rect2(0, 0, W, H), id, back, 1.0, true)

func _initialize() -> void:
	if DisplayServer.get_name() == "headless":
		printerr("A rendering display is required to generate the card atlas.")
		quit(1)
		return
	UI.LOW_SPEC = true
	UI.resolve_fonts()
	var vp := SubViewport.new()
	vp.size = Vector2i(COLS * W * SCALE, ROWS * H * SCALE)
	vp.transparent_bg = true
	vp.disable_3d = true
	vp.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	root.add_child(vp)
	for i in range(43):
		var p := Painter.new()
		p.id = i if i < 40 else -1
		p.back = maxi(i - 40, 0)
		p.size = Vector2(W, H)
		p.scale = Vector2(SCALE, SCALE)
		p.position = Vector2((i % COLS) * W * SCALE, (i / COLS) * H * SCALE)
		p.clip_contents = true
		vp.add_child(p)
	# Wait for actual completed rendering, not only a process frame; otherwise the
	# viewport readback can return empty textures. This runs only offline.
	for i in range(3):
		await RenderingServer.frame_post_draw
	var image := vp.get_texture().get_image()
	if image == null or image.is_empty():
		printerr("Atlas capture failed; not writing an empty asset.")
		quit(1)
		return
	# Never replace the shipped atlas with a blank or misaligned GPU readback.
	var seen := {}
	for i in range(43):
		var cell := Rect2i((i % COLS) * W * SCALE, (i / COLS) * H * SCALE, W * SCALE, H * SCALE)
		var tile := image.get_region(cell)
		if tile.get_pixel(W, H).a < 0.9 or tile.get_pixel(0, 0).a > 0.05:
			printerr("Invalid or blank atlas card ", i, "; existing asset left untouched.")
			quit(1)
			return
		seen[hash(tile.get_data())] = true
	if seen.size() != 43:
		printerr("Atlas cards are not distinct; existing asset left untouched.")
		quit(1)
		return
	var path := ProjectSettings.globalize_path("res://assets/cards/card_atlas.png")
	var err := image.save_png(path)
	if err != OK:
		printerr("Could not save atlas: ", err)
		quit(1)
		return
	print("Saved ", path, " (", image.get_size(), ", 40 faces and 3 backs)")
	vp.queue_free()
	quit()
