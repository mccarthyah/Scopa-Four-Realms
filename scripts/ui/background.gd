extends Control
## Painted-sky background with drifting motes, drawn procedurally.

const UI := preload("res://scripts/ui/ui.gd")


var accent := UI.GOLD
var accent2 := Color("6f5aa8")
var _motes: Array = []
var _t := 0.0


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	var r := RandomNumberGenerator.new()
	r.seed = 20260214
	for i in range(46):
		_motes.append({
			"p": Vector2(r.randf(), r.randf()),
			"h": r.randf(),
			"r": r.randf_range(0.7, 2.6),
			"a": r.randf_range(0.12, 0.5),
		})
	set_process(true)


func set_accents(a: Color, b: Color) -> void:
	accent = a
	accent2 = b
	queue_redraw()


func _process(delta: float) -> void:
	_t += delta
	queue_redraw()


func _draw() -> void:
	var w := size.x
	var h := size.y
	# layered gradient
	var bands := 26
	for i in range(bands):
		var f := float(i) / (bands - 1)
		var col := UI.BG.lerp(UI.BG2, f * 0.9)
		col = col.lerp(Color(accent2.r, accent2.g, accent2.b, 1.0), pow(1.0 - f, 3.0) * 0.20)
		draw_rect(Rect2(0, h * f / 1.0 * 0.0 + h * (float(i) / bands), w, h / bands + 2), col)

	# soft radial glows
	_glow(Vector2(w * 0.16, h * 0.10), h * 0.42, Color(accent.r, accent.g, accent.b, 0.10))
	_glow(Vector2(w * 0.90, h * 0.30), h * 0.34, Color(accent2.r, accent2.g, accent2.b, 0.12))
	_glow(Vector2(w * 0.55, h * 0.95), h * 0.5, Color(0, 0, 0, 0.35))

	# faint rune rings
	for i in range(3):
		var c := Vector2(w * (0.5 + 0.24 * sin(_t * 0.11 + i)), h * (0.22 + 0.05 * i))
		draw_arc(c, h * (0.16 + 0.06 * i), 0, TAU, 64, Color(accent.r, accent.g, accent.b, 0.05), 1.5, true)

	# drifting motes
	for m in _motes:
		var pos: Vector2 = m.p
		var y := fmod(pos.y + _t * 0.012 * (0.4 + m.h), 1.0)
		var x := pos.x + sin(_t * 0.35 + m.h * 9.0) * 0.012
		var a: float = m.a * (0.5 + 0.5 * sin(_t * 1.4 + m.h * 12.0))
		draw_circle(Vector2(x * w, y * h), m.r, Color(accent.r, accent.g, accent.b, a * 0.55))

	# vignette
	for i in range(8):
		var f := float(i) / 8.0
		draw_rect(Rect2(0, 0, w, h), Color(0, 0, 0, 0.0))
	_draw_vignette(w, h)


func _glow(c: Vector2, r: float, col: Color) -> void:
	var steps := 7
	for i in range(steps):
		var f := 1.0 - float(i) / steps
		draw_circle(c, r * f, Color(col.r, col.g, col.b, col.a / steps * 1.6))


func _draw_vignette(w: float, h: float) -> void:
	var thickness := 90.0
	var steps := 10
	for i in range(steps):
		var f := float(i) / steps
		var a := 0.30 * (1.0 - f)
		var inset := thickness * f
		draw_rect(Rect2(0, inset, w, thickness * 0.6), Color(0, 0, 0, a * 0.5))
		draw_rect(Rect2(0, h - inset - thickness * 0.6, w, thickness * 0.6), Color(0, 0, 0, a * 0.5))
		draw_rect(Rect2(inset, 0, thickness * 0.6, h), Color(0, 0, 0, a * 0.4))
		draw_rect(Rect2(w - inset - thickness * 0.6, 0, thickness * 0.6, h), Color(0, 0, 0, a * 0.4))
