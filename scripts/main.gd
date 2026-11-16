extends Control
## App shell / router.  Every screen is a Control built in code; this node owns
## the top-level navigation and the shared transition.

const TitleScreen := preload("res://scripts/screens/title.gd")
const DuelScreen := preload("res://scripts/screens/duel.gd")

var current: Control = null
var _stage := "boot"


func _ready() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	# paint the backdrop immediately so a slow first frame is never a black window
	var bg := ColorRect.new()
	bg.color = Color("171320")
	bg.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	bg.mouse_filter = Control.MOUSE_FILTER_IGNORE
	bg.z_index = -10
	add_child(bg)
	_detect_low_spec()
	_report_environment()
	show_title()
	if OS.get_cmdline_user_args().has("--audit"):
		var audit = load("res://scripts/audit.gd").new()
		add_child(audit)
		audit.run(self)
	elif OS.get_cmdline_user_args().has("--smoke"):
		var smoke = load("res://scripts/audit.gd").new()
		add_child(smoke)
		smoke.smoke_test(self)


func _swap(screen: Control) -> void:
	if current != null and is_instance_valid(current):
		current.queue_free()
	current = screen
	add_child(screen)
	screen.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	screen.modulate.a = 0.0
	var t := create_tween()
	t.tween_property(screen, "modulate:a", 1.0, 0.22)


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
		" (square corners, flat backdrop, no glyph shadows)" if UI.LOW_SPEC else " (full visual style)")
	if OS.get_cmdline_user_args().has("--full-visuals"):
		UI.LOW_SPEC = false
		print("[scopa] low_spec   : overridden to false by --full-visuals")


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
		# frame_ms = script+CPU time per frame; draws/prims = how much the renderer
		# is being asked to do. If fps is low and frame_ms is small, the machine is
		# fill-rate bound (software rasteriser), not script bound.
		print("[scopa] heartbeat stage=", _stage,
			" fps=", Engine.get_frames_per_second(),
			" frame_ms=", "%.1f" % (Performance.get_monitor(Performance.TIME_PROCESS) * 1000.0),
			" draws=", int(Performance.get_monitor(Performance.RENDER_TOTAL_DRAW_CALLS_IN_FRAME)),
			" prims=", int(Performance.get_monitor(Performance.RENDER_TOTAL_PRIMITIVES_IN_FRAME)),
			" nodes=", int(Performance.get_monitor(Performance.OBJECT_NODE_COUNT)),
			" mem_mb=", "%.0f" % (Performance.get_monitor(Performance.MEMORY_STATIC) / 1048576.0)))
	add_child(hb)


func show_title() -> void:
	_stage = "title:building"
	print("[scopa] stage -> title")
	var s := TitleScreen.new()
	s.start_duel.connect(_start_duel)
	_swap(s)
	# if the title screen never builds anything, say so instead of showing a
	# blank window with no explanation
	await get_tree().process_frame
	await get_tree().process_frame
	_stage = "title:ready"
	if is_instance_valid(s) and s.get_child_count() == 0:
		push_error("Scopa: the title screen failed to build — see the log above")
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
	t.text = "Scopa: Four Realms"
	t.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	t.add_theme_font_size_override("font_size", 32)
	v.add_child(t)
	var l := Label.new()
	l.text = msg
	l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	v.add_child(l)
	var hint := Label.new()
	hint.text = "Full details are in the log: user://logs/godot.log\n(the folder is named \"Scopa- Four Realms\")"
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
	_stage = "duel:ready"
