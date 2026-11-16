extends Control
## App shell / router.  Every screen is a Control built in code; this node owns
## the top-level navigation and the shared transition.

const TitleScreen := preload("res://scripts/screens/title.gd")
const DuelScreen := preload("res://scripts/screens/duel.gd")

var current: Control = null


func _ready() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	show_title()
	if OS.get_cmdline_user_args().has("--audit"):
		var audit = load("res://scripts/audit.gd").new()
		add_child(audit)
		audit.run(self)


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


func _start_duel(config: Dictionary) -> void:
	var s := DuelScreen.new()
	s.config = config.duplicate(true)
	s.exit_to_menu.connect(show_title)
	s.play_again.connect(func(cfg): _start_duel(cfg))
	_swap(s)
