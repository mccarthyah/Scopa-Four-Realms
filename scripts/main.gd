extends Control
## App shell / router.  Every screen is a Control built in code; this node owns
## the top-level navigation and the shared transition.

const TitleScreen := preload("res://scripts/screens/title.gd")
const DuelScreen := preload("res://scripts/screens/duel.gd")

var current: Control = null


func _ready() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	# paint the backdrop immediately so a slow first frame is never a black window
	var bg := ColorRect.new()
	bg.color = Color("171320")
	bg.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	bg.mouse_filter = Control.MOUSE_FILTER_IGNORE
	bg.z_index = -10
	add_child(bg)
	print("[scopa] boot: ", OS.get_name(), " · godot ", Engine.get_version_info().string,
		" · renderer ", RenderingServer.get_video_adapter_name())
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


func show_title() -> void:
	var s := TitleScreen.new()
	s.start_duel.connect(_start_duel)
	_swap(s)
	# if the title screen never builds anything, say so instead of showing a
	# blank window with no explanation
	await get_tree().process_frame
	await get_tree().process_frame
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
	var s := DuelScreen.new()
	s.config = config.duplicate(true)
	s.exit_to_menu.connect(show_title)
	s.play_again.connect(func(cfg): _start_duel(cfg))
	_swap(s)
