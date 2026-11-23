extends Control
# gdlint: disable=class-definitions-order
# Declarations here are grouped for readability (constants beside the tables
# they describe, fields beside the build code that fills them) rather than
# strictly consts-before-vars. Ordering is a style rule with no runtime effect;
# see docs/ASSESSMENT.md.

## App shell / router.  Every screen is a Control built in code; this node owns
## the top-level navigation and the shared transition.

const TitleScreen := preload("res://scripts/screens/title.gd")
const DuelScreen := preload("res://scripts/screens/duel.gd")
# The audit is dev-only and excluded from exports (export_presets.cfg), so it is
# loaded on demand rather than preloaded into every build.
static var AuditScript := load("res://scripts/audit.gd")

var current: Control = null
var _stage := "boot"
# Cheap wall-clock frame intervals for diagnosing stutter. These include the
# intentional FPS cap and OS scheduling; they are not GPU timing measurements.
var _last_frame_time_us := 0
var _frame_intervals_ms := PackedFloat32Array()


func _notification(what: int) -> void:
	if what == NOTIFICATION_RESIZED and is_node_ready() and current != null \
			and is_instance_valid(current):
		_layout_stage(current)


func _process(_delta: float) -> void:
	var now: int = Time.get_ticks_usec()
	if _last_frame_time_us > 0 and _frame_intervals_ms.size() < 2048:
		_frame_intervals_ms.append(float(now - _last_frame_time_us) / 1000.0)
	_last_frame_time_us = now


## Summarise the preceding heartbeat interval. Wall-clock intervals include the
## 30 FPS cap and scheduling, so they reveal stutter but do not identify its cause.
func _summarize_frame_intervals(samples: PackedFloat32Array) -> Dictionary:
	if samples.is_empty():
		return {"count": 0, "p95": 0.0, "max": 0.0, "over50": 0}
	var sorted := samples.duplicate()
	sorted.sort()
	var over50 := 0
	for interval in sorted:
		if interval > 50.0:
			over50 += 1
	var p95_index: int = clampi(int(ceil(float(sorted.size()) * 0.95)) - 1, 0, sorted.size() - 1)
	return {"count": sorted.size(), "p95": sorted[p95_index],
		"max": sorted[sorted.size() - 1], "over50": over50}


func _ready() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	# The renderer already clears the screen before every frame. Use that clear
	# colour for the margins and first frame instead of drawing a second full-
	# window ColorRect beneath the screen's own opaque background. This avoids
	# a redundant full-screen pass on software renderers without changing it.
	RenderingServer.set_default_clear_color(ProjectSettings.get_setting("application/boot_splash/bg_color"))
	_detect_low_spec()
	_report_environment()
	show_title(true)
	if OS.get_cmdline_user_args().has("--audit"):
		var audit = AuditScript.new()
		add_child(audit)
		audit.run(self)
	elif OS.get_cmdline_user_args().has("--smoke"):
		var smoke = AuditScript.new()
		add_child(smoke)
		smoke.smoke_test(self)


## Portrait remains a readable phone column. Both the title and duel get a
## dedicated landscape layout rather than a stretched or centred portrait page.
const DESIGN_WIDTH := 540.0


func _is_wide() -> bool:
	var v := get_viewport_rect().size
	return v.x > v.y * 0.72


func _swap(screen: Control, fade: bool = true) -> void:
	if current != null and is_instance_valid(current):
		current.queue_free()
	current = screen
	add_child(screen)
	_layout_stage(screen)
	if fade and Profile.anim_enabled and not UI.LOW_SPEC:
		screen.modulate.a = 0.0
		var t := create_tween()
		t.tween_property(screen, "modulate:a", 1.0, 0.22)


## Home uses the whole window. Gameplay keeps its bounded stage, and both
## layouts reflow without restarting play.
func _layout_stage(screen: Control) -> void:
	screen.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	var v := get_viewport_rect().size
	if screen is TitleScreen:
		return
	if v.x > v.y * 1.12:
		var w: float = minf(1760.0, v.x)
		var margin: float = maxf((v.x - w) * 0.5, 0.0)
		screen.anchor_left = 0.0
		screen.anchor_right = 0.0
		screen.offset_left = margin
		screen.offset_right = margin + w
	elif _is_wide():
		var w: float = minf(DESIGN_WIDTH, v.x)
		var margin: float = maxf((v.x - w) * 0.5, 0.0)
		screen.anchor_left = 0.0
		screen.anchor_right = 0.0
		screen.offset_left = margin
		screen.offset_right = margin + w


## One line, printed at boot and visible in the log, that says everything needed
## to diagnose a rendering/display problem remotely.
## Decide once, at boot, whether this machine can afford rounded corners and
## animated full-screen effects. Corner radii are tessellated into ~50-100
## triangles per rectangle, which is free on a GPU and expensive on a software
## rasteriser. Everything still works, it is just drawn the cheap way.
func _detect_low_spec() -> void:
	var adapter := RenderingServer.get_video_adapter_name().to_lower()
	var soft := adapter.contains("basic render") or adapter.contains("llvmpipe") \
		or adapter.contains("swiftshader") or adapter.contains("warp") \
		or adapter == ""
	UI.LOW_SPEC = soft
	print("[scopa] low_spec   : ", UI.LOW_SPEC,
		" (pre-rendered UI frames, rounded cards, no glyph shadows)" if UI.LOW_SPEC else " (full visual style)")
	if OS.get_cmdline_user_args().has("--full-visuals"):
		UI.LOW_SPEC = false
		print("[scopa] low_spec   : overridden to false by --full-visuals")
	# Software rendering can saturate a VM even on an unchanged menu. Leave CPU
	# time for input and the host; this does not alter game logic or speed timers.
	if UI.LOW_SPEC:
		Engine.max_fps = 30
		print("[scopa] frame cap  : 30 fps (software rendering)")


func _report_environment() -> void:
	var v := Engine.get_version_info()
	var method: String = str(ProjectSettings.get_setting("rendering/renderer/rendering_method", "?"))
	var adapter := RenderingServer.get_video_adapter_name()
	var vendor := RenderingServer.get_video_adapter_vendor()
	print("[scopa] ---- environment ----")
	print("[scopa] godot      : ", v.get("string", "?"), "  (", OS.get_name(), ")")
	print("[scopa] rendering  : ", method, " / driver ", str(ProjectSettings.get_setting("rendering/rendering_device/driver", "?")),
		" · gl driver ", str(ProjectSettings.get_setting("rendering/gl_compatibility/driver", "?")))
	print("[scopa] adapter    : ", adapter if adapter != "" else "(none — headless/dummy)", " · ", vendor if vendor != "" else "-")
	if adapter.to_lower().contains("basic render") or adapter.to_lower().contains("llvmpipe") \
			or adapter.to_lower().contains("swiftshader") or adapter.to_lower().contains("warp"):
		print("[scopa] WARNING    : software rasteriser — no GPU acceleration. Everything is")
		print("[scopa]              drawn on the CPU, so full-screen effects cost real time.")
		print("[scopa]              Keep the window near 540x960; maximising multiplies the cost.")
	print("[scopa] display    : ", DisplayServer.get_name(), " · window ", DisplayServer.window_get_size(),
		" · screen ", DisplayServer.screen_get_size())
	print("[scopa] viewport   : ", str(get_viewport().get_visible_rect().size))
	print("[scopa] log file   : ", ProjectSettings.globalize_path("user://logs/godot.log"))
	print("[scopa] process    : pid ", OS.get_process_id(), " · ", Engine.get_physics_ticks_per_second(), " physics tps")
	print("[scopa] ---------------------")
	# A heartbeat every 5s proves whether the process is alive-but-stuck or gone,
	# and the stage marker says which screen was being built when it stopped.
	var hb := Timer.new()
	hb.wait_time = 5.0
	hb.autostart = true
	hb.timeout.connect(func():
		var stats := _summarize_frame_intervals(_frame_intervals_ms)
		_frame_intervals_ms.clear()
		# A process-time sample and wall-clock intervals are useful symptoms, but
		# neither one alone proves whether the CPU, GPU or scheduler is at fault.
		print("[scopa] heartbeat stage=", _stage,
			" fps=", Engine.get_frames_per_second(),
			" process_ms=", "%.1f" % (Performance.get_monitor(Performance.TIME_PROCESS) * 1000.0),
			" interval_p95_ms=", "%.1f" % stats.p95,
			" interval_max_ms=", "%.1f" % stats.max,
			" interval_over50=", stats.over50, "/", stats.count,
			" draws=", int(Performance.get_monitor(Performance.RENDER_TOTAL_DRAW_CALLS_IN_FRAME)),
			" prims=", int(Performance.get_monitor(Performance.RENDER_TOTAL_PRIMITIVES_IN_FRAME)),
			" nodes=", int(Performance.get_monitor(Performance.OBJECT_NODE_COUNT)),
			" mem_mb=", "%.0f" % (Performance.get_monitor(Performance.MEMORY_STATIC) / 1048576.0)))
	add_child(hb)


func show_title(from_splash: bool = false) -> void:
	_stage = "title:building"
	print("[scopa] stage -> title")
	var s := TitleScreen.new()
	s.start_duel.connect(_start_duel)
	_swap(s, not from_splash)
	if from_splash and not OS.get_cmdline_user_args().has("--audit") and not OS.get_cmdline_user_args().has("--smoke"):
		s.play_intro()
	# if the title screen never builds anything, say so instead of showing a
	# blank window with no explanation
	await get_tree().process_frame
	await get_tree().process_frame
	if not is_instance_valid(s) or current != s:
		return
	_stage = "title:ready"
	if s.get_child_count() == 0:
		push_error("Four Realms: the title screen failed to build — see the log above")
		_fatal_screen("The title screen could not be built.\nCheck the log for the first error.")


func _fatal_screen(msg: String) -> void:
	if current != null and is_instance_valid(current):
		current.queue_free()
	var p := PanelContainer.new()
	p.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(p)
	current = p
	var v := VBoxContainer.new()
	v.add_theme_constant_override("separation", 12)
	v.alignment = BoxContainer.ALIGNMENT_CENTER
	p.add_child(v)
	var t := Label.new()
	t.text = "Four Realms"
	t.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	t.add_theme_font_size_override("font_size", 32)
	v.add_child(t)
	var l := Label.new()
	l.text = msg
	l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	v.add_child(l)
	var hint := Label.new()
	hint.text = "Full details are in the log: user://logs/godot.log"
	hint.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	hint.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	hint.add_theme_color_override("font_color", Color(0.66, 0.61, 0.53))
	v.add_child(hint)


func _start_duel(config: Dictionary) -> void:
	_stage = "duel:building"
	print("[scopa] stage -> duel (mode ", config.get("mode", -1), ")")
	var s := DuelScreen.new()
	s.config = config.duplicate(true)
	s.exit_to_menu.connect(show_title)
	s.play_again.connect(func(cfg): _start_duel(cfg))
	_swap(s)
	await get_tree().process_frame
	await get_tree().process_frame
	if is_instance_valid(s) and current == s:
		_stage = "duel:ready"
