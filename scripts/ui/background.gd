extends Control
## Painted-sky background with drifting motes.
##
## Performance note: the still layers (vertical gradient, three soft glows and a
## vignette) used to be drawn as ~60 piled-up translucent primitives every frame
## — about 12x screen overdraw (11 Mpix of alpha fill per frame at 720x1280).
## That is free on a GPU, but it can saturate a software rasteriser (llvmpipe, or
## a VM with no GPU acceleration), which shows up as a hang rather than a crash.
## The same look is now built from five gradient textures, one texture fetch per
## screen pixel, and if the frame rate still sags the background quietly drops to
## a cheaper build instead of dragging the machine down.
class_name RealmBackground

const UI := preload("res://scripts/ui/ui.gd")

var accent := UI.GOLD
var accent2 := Color("6f5aa8")
var _motes: Array = []
var _t := 0.0

# Cached gradient textures, keyed by the colour they were built for.
var _tex_glow := {}
var _tex_vignette: GradientTexture2D = null
var _tex_sky: GradientTexture2D = null
var _sky_key := ""

# Adaptive quality: if the machine cannot keep up we draw less, not slower.
var _fps_sample := 0
var _fps_worst := 999.0
var _degraded := false


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


## Stop animating entirely: keeps the painted sky, drops the moving layers and
## the per-frame work. Used when the machine cannot afford the animation.
func set_quiet() -> void:
	_degraded = true
	set_process(false)
	queue_redraw()


func set_accents(a: Color, b: Color) -> void:
	accent = a
	accent2 = b
	_tex_glow.clear()
	_sky_key = ""
	queue_redraw()


func _process(delta: float) -> void:
	_t += delta
	# Watch the frame rate for a few seconds; if this machine is struggling, drop
	# the animated motes and the glow layer on its own rather than compounding it.
	if not _degraded:
		_fps_sample += 1
		if _fps_sample > 90:
			_fps_sample = 0
			_fps_worst = minf(_fps_worst, Engine.get_frames_per_second()) if _fps_worst < 999.0 \
				else Engine.get_frames_per_second()
			if _fps_worst < 20.0:
				_degraded = true
				set_process(false)  # nothing left that changes per frame
	queue_redraw()


func _draw() -> void:
	var w := size.x
	var h := size.y
	if w < 8.0 or h < 8.0:
		return

	# --- 1. vertical sky gradient: one quad
	draw_texture_rect(_sky(), Rect2(0, 0, w, h), false)

	# --- 2. soft glows: one quad each (was 21 nested circles)
	if not _degraded:
		_glow(Vector2(w * 0.16, h * 0.10), h * 0.42, Color(accent.r, accent.g, accent.b, 0.10))
		_glow(Vector2(w * 0.90, h * 0.30), h * 0.34, Color(accent2.r, accent2.g, accent2.b, 0.12))
		_glow(Vector2(w * 0.55, h * 0.95), h * 0.50, Color(0, 0, 0, 0.35))

	# --- 3. faint rune rings (3 thin arcs, cheap)
	if not _degraded:
		for i in range(3):
			var c := Vector2(w * (0.5 + 0.24 * sin(_t * 0.11 + i)), h * (0.22 + 0.05 * i))
			draw_arc(c, h * (0.16 + 0.06 * i), 0, TAU, 48, Color(accent.r, accent.g, accent.b, 0.05), 1.5, true)

	# --- 4. drifting motes
	if not _degraded:
		for m in _motes:
			var pos: Vector2 = m.p
			var y := fmod(pos.y + _t * 0.012 * (0.4 + m.h), 1.0)
			var x := pos.x + sin(_t * 0.35 + m.h * 9.0) * 0.012
			var a: float = m.a * (0.5 + 0.5 * sin(_t * 1.4 + m.h * 12.0))
			draw_circle(Vector2(x * w, y * h), m.r, Color(accent.r, accent.g, accent.b, a * 0.55))

	# --- 5. vignette: one quad
	draw_texture_rect(_vignette(), Rect2(0, 0, w, h), false)


# --- gradient textures, each built once ---------------------------------------

func _sky() -> GradientTexture2D:
	var key := "%s|%s" % [accent2.to_html(false), UI.BG.to_html(false)]
	if _tex_sky != null and _sky_key == key:
		return _tex_sky
	var g := Gradient.new()
	g.set_color(0, UI.BG)
	g.set_color(1, UI.BG2.lerp(accent2, 0.20))
	# keep a hint of the sky itself under the accent tint
	g.add_point(0.45, UI.BG.lerp(UI.BG2, 0.5))
	var t := GradientTexture2D.new()
	t.gradient = g
	t.width = 4
	t.height = 256
	t.fill = GradientTexture2D.FILL_LINEAR
	t.fill_from = Vector2(0, 0)
	t.fill_to = Vector2(0, 1)
	_tex_sky = t
	_sky_key = key
	return _tex_sky


func _glow(c: Vector2, r: float, col: Color) -> void:
	var key := col.to_html(true)
	var tex: GradientTexture2D = _tex_glow.get(key)
	if tex == null:
		var g := Gradient.new()
		g.set_color(0, col)
		g.set_color(1, Color(col.r, col.g, col.b, 0.0))
		tex = GradientTexture2D.new()
		tex.gradient = g
		tex.width = 64
		tex.height = 64
		tex.fill = GradientTexture2D.FILL_RADIAL
		tex.fill_from = Vector2(0.5, 0.5)
		tex.fill_to = Vector2(1.0, 0.5)
		_tex_glow[key] = tex
	draw_texture_rect(tex, Rect2(c - Vector2(r, r), Vector2(r, r) * 2.0), false)


func _vignette() -> GradientTexture2D:
	if _tex_vignette != null:
		return _tex_vignette
	var g := Gradient.new()
	g.set_color(0, Color(0, 0, 0, 0.0))
	g.set_color(1, Color(0, 0, 0, 0.34))
	g.add_point(0.62, Color(0, 0, 0, 0.06))
	var t := GradientTexture2D.new()
	t.gradient = g
	t.width = 64
	t.height = 64
	t.fill = GradientTexture2D.FILL_RADIAL
	t.fill_from = Vector2(0.5, 0.5)
	t.fill_to = Vector2(0.85, 0.5)
	_tex_vignette = t
	return _tex_vignette
