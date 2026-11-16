extends RefCounted
## Tiny juice helpers: particle bursts, floating text, screen shake.
class_name FX

const UI := preload("res://scripts/ui/ui.gd")



static func burst(parent: Node, pos: Vector2, col: Color, amount: int = 18, spread: float = 220.0) -> void:
	var p := CPUParticles2D.new()
	p.position = pos
	p.amount = amount
	p.one_shot = true
	p.emitting = true
	p.explosiveness = 0.92
	p.lifetime = 0.85
	p.direction = Vector2(0, -1)
	p.spread = 180.0
	p.gravity = Vector2(0, 420)
	p.initial_velocity_min = spread * 0.45
	p.initial_velocity_max = spread
	p.scale_amount_min = 1.0
	p.scale_amount_max = 3.4
	p.color = col
	p.z_index = 60
	parent.add_child(p)
	p.finished.connect(p.queue_free)


static func float_text(parent: Node, pos: Vector2, text: String, col: Color = UI.GOLD, size: int = 30, rise: float = 90.0) -> void:
	var l: Label = UI.label(text, size, col, true)
	l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	l.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	l.z_index = 80
	l.modulate.a = 0.0
	parent.add_child(l)
	await l.get_tree().process_frame
	l.size = l.get_combined_minimum_size()
	l.pivot_offset = l.size * 0.5
	l.position = pos - l.size * 0.5
	var t := l.create_tween()
	t.set_parallel(true)
	t.tween_property(l, "modulate:a", 1.0, 0.14)
	t.tween_property(l, "position:y", l.position.y - rise, 1.1).set_ease(Tween.EASE_OUT).set_trans(Tween.TRANS_CUBIC)
	t.tween_property(l, "scale", Vector2(1.12, 1.12), 0.2).from(Vector2(0.7, 0.7))
	t.chain().tween_property(l, "modulate:a", 0.0, 0.45).set_delay(0.55)
	t.chain().tween_callback(l.queue_free)


static func shake(node: Control, amount: float = 10.0, dur: float = 0.4) -> void:
	if not is_instance_valid(node):
		return
	var base := node.position
	var t := node.create_tween()
	var steps := 6
	for i in range(steps):
		var f := 1.0 - float(i) / steps
		var off := Vector2(randf_range(-1, 1), randf_range(-1, 1)) * amount * f
		t.tween_property(node, "position", base + off, dur / steps)
	t.tween_property(node, "position", base, dur / steps)


static func flash(node: Control, col: Color, dur: float = 0.35) -> void:
	var r := ColorRect.new()
	r.color = col
	r.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	r.mouse_filter = Control.MOUSE_FILTER_IGNORE
	r.z_index = 90
	node.add_child(r)
	var t := r.create_tween()
	t.tween_property(r, "color:a", 0.0, dur)
	t.tween_callback(r.queue_free)
