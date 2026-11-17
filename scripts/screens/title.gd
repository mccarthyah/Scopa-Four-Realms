extends Control
## Title + mode select.  Also hosts the faction picker and the codex.

const UI := preload("res://scripts/ui/ui.gd")
const SettingsPanel := preload("res://scripts/ui/settings_panel.gd")
const CardView := preload("res://scripts/ui/card_view.gd")
const CardArt := preload("res://scripts/ui/card_art.gd")
const RealmBackground := preload("res://scripts/ui/background.gd")
const PUBLISHER_LOGO := preload("res://assets/branding/veloce_logo_transparent.png")
const LOGO_TRANSPARENT := preload("res://assets/branding/four_realms_logo.png")
const TILE_ART := [preload("res://assets/branding/forge_tile.png"), preload("res://assets/branding/grove_tile.png"), preload("res://assets/branding/horde_tile.png"), preload("res://assets/branding/crown_tile.png")]
const MODE_ART := preload("res://assets/branding/panel_landscape.png")

signal start_duel(config: Dictionary)

const T := preload("res://scripts/tables.gd")
const C := preload("res://scripts/game/cards.gd")

var faction := T.FORGE
var _faction_buttons: Array = []
var _mode_list: GridContainer
var _codex: Control
var _sheet_panel: PanelContainer
var _scroll: ScrollContainer
var _title_margin: MarginContainer
var _title_columns: HBoxContainer
var _title_left: VBoxContainer
var _title_right: VBoxContainer
var _title_parts: Array = []
var _title_landscape := false
var _mode_rows: Array[Callable] = []
var _intro_layer: Control
var _intro_progress := 0.0
var _intro_phase := "menu"

var _faction_power_title: Label
var _faction_power_text: Label


func _ready() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	UI.resolve_fonts()
	# default to the faction you play most, so a returning player lands on it
	var best := 0
	for f in range(4):
		if int(Profile.faction_plays.get(f, 0)) > int(Profile.faction_plays.get(best, 0)):
			best = f
	faction = best
	_build()
	if not Profile.seen_intro:
		Profile.seen_intro = true
		Profile.save_profile()
		_show_howto()


func _build() -> void:
	var bg := RealmBackground.new()
	add_child(bg)
	bg.set_accents(UI.GOLD, Color("6f5aa8"))
	bg.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)

	var root := MarginContainer.new()
	_title_margin = root
	root.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	root.add_theme_constant_override("margin_left", 22)
	root.add_theme_constant_override("margin_right", 22)
	root.add_theme_constant_override("margin_top", 26)
	root.add_theme_constant_override("margin_bottom", 20)
	add_child(root)

	_scroll = ScrollContainer.new()
	_scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	_scroll.vertical_scroll_mode = ScrollContainer.SCROLL_MODE_SHOW_NEVER
	_scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	root.add_child(_scroll)

	_title_columns = HBoxContainer.new()
	_title_columns.name = "TitleColumns"
	_title_columns.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_title_columns.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_title_columns.mouse_filter = Control.MOUSE_FILTER_PASS
	_title_columns.add_theme_constant_override("separation", 44)
	_scroll.add_child(_title_columns)
	_title_left = VBoxContainer.new()
	_title_left.name = "TitleIdentity"
	_title_left.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_title_left.mouse_filter = Control.MOUSE_FILTER_PASS
	_title_left.add_theme_constant_override("separation", 14)
	_title_columns.add_child(_title_left)
	_title_right = VBoxContainer.new()
	_title_right.name = "TitleModes"
	_title_right.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_title_right.mouse_filter = Control.MOUSE_FILTER_PASS
	_title_right.add_theme_constant_override("separation", 14)
	_title_columns.add_child(_title_right)
	_title_right.hide()
	var col := _title_left

	# The same transparent logo carries from the splash into either layout.
	var mast := TextureRect.new()
	mast.name = "Masthead"
	mast.texture = LOGO_TRANSPARENT
	mast.texture_filter = CanvasItem.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS
	mast.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	mast.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	mast.custom_minimum_size = Vector2(0, 330)
	mast.mouse_filter = Control.MOUSE_FILTER_IGNORE
	col.add_child(mast)

	_mode_list = GridContainer.new()
	_mode_list.columns = 1
	_mode_list.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_mode_list.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_mode_list.add_theme_constant_override("h_separation", 10)
	_mode_list.add_theme_constant_override("v_separation", 10)
	col.add_child(_mode_list)
	_build_modes()

	var stats := _stats_panel()
	col.add_child(stats)
	_title_parts = [mast, _mode_list, stats]
	_update_title_layout()


func _notification(what: int) -> void:
	if what == NOTIFICATION_RESIZED and is_node_ready() and not _title_parts.is_empty():
		_update_title_layout()
		_layout_sheet()
		_place_intro_logo(_intro_progress)


## Move the existing controls so rotation keeps the selected faction, scroll
## interactions, settings and callbacks. Home actions fit in both orientations.
func _update_title_layout() -> void:
	if _title_parts.is_empty():
		return
	var wide := size.x > size.y * 1.12
	var rotated := wide != _title_landscape
	_title_landscape = wide
	_mode_list.columns = 2
	var mast: TextureRect = _title_parts[0]
	mast.texture = LOGO_TRANSPARENT
	mast.custom_minimum_size.y = clampf(size.y * 0.48, 180.0, 620.0) if wide else clampf(size.y * 0.32, 100.0, 440.0)
	mast.size_flags_vertical = Control.SIZE_EXPAND_FILL if wide else Control.SIZE_FILL
	_title_left.size_flags_stretch_ratio = 0.85 if wide else 1.0
	_title_right.size_flags_stretch_ratio = 1.15 if wide else 1.0
	_title_left.add_theme_constant_override("separation", 16)
	_title_columns.add_theme_constant_override("separation", 32)
	_title_margin.add_theme_constant_override("margin_left", 24 if wide else 18)
	_title_margin.add_theme_constant_override("margin_right", 24 if wide else 18)
	_title_margin.add_theme_constant_override("margin_top", 16)
	_title_margin.add_theme_constant_override("margin_bottom", 16)
	if OS.get_name() in ["Android", "iOS"]:
		var safe := DisplayServer.get_display_safe_area()
		var screen := DisplayServer.screen_get_size()
		var viewport := get_viewport_rect().size
		if screen.x > 0 and screen.y > 0 and safe.has_area():
			var top_left := Vector2(safe.position) * viewport / Vector2(screen)
			var bottom_right := Vector2(safe.end) * viewport / Vector2(screen)
			_title_margin.add_theme_constant_override("margin_left", int(maxf(24, top_left.x - global_position.x)))
			_title_margin.add_theme_constant_override("margin_right", int(maxf(24, global_position.x + size.x - bottom_right.x)))
			_title_margin.add_theme_constant_override("margin_top", int(maxf(16, top_left.y)))
			_title_margin.add_theme_constant_override("margin_bottom", int(maxf(16, viewport.y - bottom_right.y)))
	var record_scale := 1.3 if wide else clampf(size.x / 540.0, 1.0, 1.3)
	for label in _title_parts[2].find_children("*", "Label", true, false):
		if not label.has_meta("home_font_size"):
			label.set_meta("home_font_size", label.get_theme_font_size("font_size"))
		label.add_theme_font_size_override("font_size", int(float(label.get_meta("home_font_size")) * record_scale))
	_mode_list.add_theme_constant_override("h_separation", 12)
	_mode_list.add_theme_constant_override("v_separation", 12)
	for style_row in _mode_rows:
		style_row.call(wide)
	_title_left.alignment = BoxContainer.ALIGNMENT_CENTER
	_title_right.alignment = BoxContainer.ALIGNMENT_CENTER
	if wide:
		if _mode_list.get_parent() != _title_right:
			_mode_list.reparent(_title_right, false)
		_title_right.show()
	else:
		if _mode_list.get_parent() != _title_left:
			_mode_list.reparent(_title_left, false)
		_title_left.move_child(_mode_list, _title_left.get_child_count() - 1)
		_title_left.move_child(_title_parts[2], _title_left.get_child_count() - 1)
		_title_right.hide()
	if rotated:
		_scroll.scroll_vertical = 0


## The runtime splash follows the actual viewport after Profile applies the
## saved orientation. A static engine splash cannot read saved preferences.
func play_intro() -> void:
	if is_instance_valid(_intro_layer):
		return
	_intro_progress = 0.0
	_intro_phase = "settling"
	_intro_layer = Control.new()
	_intro_layer.name = "SplashTransition"
	_intro_layer.z_index = 200
	_intro_layer.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_intro_layer.mouse_filter = Control.MOUSE_FILTER_STOP
	add_child(_intro_layer)
	var curtain := ColorRect.new()
	curtain.color = Color(0.078, 0.071, 0.109, 1)
	curtain.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_intro_layer.add_child(curtain)
	var publisher := TextureRect.new()
	publisher.name = "PublisherLogo"
	publisher.texture = PUBLISHER_LOGO
	publisher.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	publisher.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	publisher.texture_filter = CanvasItem.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS
	publisher.mouse_filter = Control.MOUSE_FILTER_IGNORE
	publisher.modulate.a = 0.0
	_intro_layer.add_child(publisher)
	publisher.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	publisher.anchor_left = 0.08
	publisher.anchor_right = 0.92
	publisher.anchor_top = 0.15
	publisher.anchor_bottom = 0.85
	var flying := TextureRect.new()
	flying.name = "MovingLogo"
	flying.texture = LOGO_TRANSPARENT
	flying.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	flying.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	flying.texture_filter = CanvasItem.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS
	flying.mouse_filter = Control.MOUSE_FILTER_IGNORE
	flying.modulate.a = 0.0
	_intro_layer.add_child(flying)
	var mast: TextureRect = _title_parts[0]
	mast.modulate.a = 0.0
	_title_margin.modulate.a = 0.0
	_place_intro_logo(0.0)
	# Mobile startup can report a provisional viewport before the OS applies
	# orientation and safe areas. Keep branding hidden until that has settled.
	var last_size := Vector2.ZERO
	var last_viewport_size := Vector2.ZERO
	var stable_frames := 0
	var started := Time.get_ticks_msec()
	while Time.get_ticks_msec() - started < 1200:
		await get_tree().process_frame
		var viewport_size := get_viewport_rect().size
		var matches_setting := Profile.orientation == "auto" or (viewport_size.x < viewport_size.y if Profile.orientation == "portrait" else viewport_size.x > viewport_size.y)
		if viewport_size.is_equal_approx(last_viewport_size) and size.is_equal_approx(last_size) and matches_setting:
			stable_frames += 1
		else:
			stable_frames = 0
		last_size = size
		last_viewport_size = viewport_size
		if stable_frames >= 3 and Time.get_ticks_msec() - started >= 150:
			break
	_place_intro_logo(0.0)
	_intro_phase = "veloce"
	var tween := create_tween()
	if Profile.anim_enabled:
		tween.tween_property(publisher, "modulate:a", 1.0, 0.16)
	else:
		publisher.modulate.a = 1.0
	tween.tween_interval(1.0)
	if Profile.anim_enabled:
		tween.tween_callback(func(): _intro_phase = "fade")
		tween.tween_property(publisher, "modulate:a", 0.0, 0.7)
		tween.parallel().tween_property(flying, "modulate:a", 1.0, 0.7)
		tween.tween_interval(0.3)
		tween.tween_callback(func(): _intro_phase = "four_realms")
		tween.tween_method(_place_intro_logo, 0.0, 1.0, 2.2).set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_IN_OUT)
		tween.parallel().tween_property(curtain, "modulate:a", 0.0, 1.6).set_delay(0.3)
		tween.parallel().tween_property(_title_margin, "modulate:a", 1.0, 1.2).set_delay(0.8)
	else:
		# Keep the publisher/game sequence while respecting disabled animation.
		tween.tween_callback(func():
			_intro_phase = "four_realms"
			publisher.hide()
			flying.modulate.a = 1.0)
		tween.tween_interval(0.5)
	await tween.finished
	mast.modulate.a = 1.0
	_title_margin.modulate.a = 1.0
	_intro_layer.queue_free()
	_intro_layer = null
	_intro_phase = "menu"


func _place_intro_logo(progress: float) -> void:
	_intro_progress = progress
	if not is_instance_valid(_intro_layer):
		return
	var flying := _intro_layer.get_node_or_null("MovingLogo") as TextureRect
	if flying == null:
		return
	var mast: TextureRect = _title_parts[0]
	var texture_size := Vector2(LOGO_TRANSPARENT.get_size())
	var start_size := texture_size * minf(size.x * 0.9 / texture_size.x, size.y * 0.9 / texture_size.y)
	var start := Rect2((size - start_size) * 0.5, start_size)
	var target_size := texture_size * minf(mast.size.x / texture_size.x, mast.size.y / texture_size.y)
	var target := Rect2(mast.global_position - global_position + (mast.size - target_size) * 0.5, target_size)
	flying.position = start.position.lerp(target.position, progress)
	flying.size = start.size.lerp(target.size, progress)


## Keep an open sheet readable and inside the screen during rotation.
func _open_settings() -> void:
	var sheet := _sheet("SETTINGS")
	SettingsPanel.populate(sheet, _codex_close, _layout_sheet)


func _layout_sheet() -> void:
	if not is_instance_valid(_sheet_panel):
		return
	if _sheet_panel.has_meta("settings_grid"):
		SettingsPanel.layout(_sheet_panel, size, _title_landscape)
		return
	_sheet_panel.anchor_left = 0.5
	_sheet_panel.anchor_right = 0.5
	var settings := _sheet_panel.has_meta("settings")
	var maximum := 1280.0 if settings and _title_landscape else 820.0
	var width := minf(size.x * 0.92, maximum)
	_sheet_panel.offset_left = -width * 0.5
	_sheet_panel.offset_right = width * 0.5
	if _sheet_panel.has_meta("navigation_body"):
		var layout: GridContainer = _sheet_panel.get_meta("navigation_layout")
		var factions: GridContainer = _sheet_panel.get_meta("navigation_factions")
		var modes: GridContainer = _sheet_panel.get_meta("navigation_modes")
		layout.columns = 2 if _title_landscape else 1
		modes.columns = 1 if _title_landscape else 2
		for button in factions.get_children():
			button.custom_minimum_size.y = 230.0 if _title_landscape else 140.0
		_faction_power_title.add_theme_font_size_override("font_size", 28 if _title_landscape else 24)
		_faction_power_text.add_theme_font_size_override("font_size", 26 if _title_landscape else 20)
		var power_font := _faction_power_text.get_theme_font("font")
		var power_size := _faction_power_text.get_theme_font_size("font_size")
		_faction_power_text.custom_minimum_size.y = power_font.get_height(power_size) * 2.0 + 4.0
		var body: VBoxContainer = _sheet_panel.get_meta("navigation_body")
		var outer: VBoxContainer = body.get_parent().get_parent()
		var chrome := outer.get_combined_minimum_size().y + _sheet_panel.get_theme_stylebox("panel").get_minimum_size().y
		var height := minf(size.y * 0.92, body.get_combined_minimum_size().y + chrome + 8.0)
		_sheet_panel.anchor_top = 0.5
		_sheet_panel.anchor_bottom = 0.5
		_sheet_panel.offset_top = -height * 0.5
		_sheet_panel.offset_bottom = height * 0.5

func _faction_card(f: int) -> Button:
	var info: Dictionary = T.FACTIONS[f]
	var b := Button.new()
	b.focus_mode = Control.FOCUS_NONE
	b.custom_minimum_size = Vector2(0, 132)
	b.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	b.toggle_mode = true
	b.set_meta("faction", f)
	for state in ["normal", "hover", "pressed", "focus"]:
		b.add_theme_stylebox_override(state, StyleBoxEmpty.new())
	b.pressed.connect(func():
		faction = f
		_refresh_factions()
		Sfx.play("tap"))

	var art := TextureRect.new()
	art.name = "FactionArtwork"
	art.texture = TILE_ART[f]
	art.texture_filter = CanvasItem.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS
	art.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	art.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_COVERED
	art.mouse_filter = Control.MOUSE_FILTER_IGNORE
	art.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	art.offset_left = 4
	art.offset_top = 4
	art.offset_right = -4
	art.offset_bottom = -4
	b.add_child(art)
	var caption := ColorRect.new()
	caption.color = Color(0.015, 0.035, 0.06, 0.82)
	caption.mouse_filter = Control.MOUSE_FILTER_IGNORE
	caption.set_anchors_and_offsets_preset(Control.PRESET_BOTTOM_WIDE)
	caption.offset_left = 4
	caption.offset_right = -4
	caption.offset_top = -45
	caption.offset_bottom = -4
	b.add_child(caption)
	var frame := Panel.new()
	frame.name = "FactionFrame"
	frame.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	frame.mouse_filter = Control.MOUSE_FILTER_IGNORE
	frame.add_theme_stylebox_override("panel", UI.fantasy_style("frame", 0, 0))
	b.add_child(frame)

	var v := VBoxContainer.new()
	v.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	v.mouse_filter = Control.MOUSE_FILTER_IGNORE
	v.add_theme_constant_override("separation", 0)
	v.alignment = BoxContainer.ALIGNMENT_END
	v.offset_bottom = -6
	b.add_child(v)

	var nm := UI.label(info.name, 19, UI.TEXT, true)
	nm.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	nm.mouse_filter = Control.MOUSE_FILTER_IGNORE
	nm.add_theme_font_size_override("font_size", 18)
	# Keep four faction names readable without colliding in narrow columns.
	v.add_child(nm)

	var pp := UI.label(info.people, 14, UI.TEXT_DIM)
	pp.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	pp.add_theme_color_override("font_color", Color("eee9d5"))
	pp.mouse_filter = Control.MOUSE_FILTER_IGNORE
	v.add_child(pp)
	b.resized.connect(func():
		caption.offset_top = -78 if _title_landscape else -45
		nm.add_theme_font_override("font", ThemeDB.fallback_font if _title_landscape else UI.font_title())
		pp.add_theme_font_override("font", ThemeDB.fallback_font if _title_landscape else UI.font_body())
		nm.add_theme_font_size_override("font_size", 30 if _title_landscape else (14 if b.size.x < 80 else 18))
		pp.add_theme_font_size_override("font_size", 23 if _title_landscape else 14))

	return b


func _refresh_factions() -> void:
	_faction_buttons = _faction_buttons.filter(func(button): return is_instance_valid(button))
	for i in range(_faction_buttons.size()):
		var b: Button = _faction_buttons[i]
		var on: bool = int(b.get_meta("faction")) == faction
		b.set_pressed_no_signal(on)
		var frame: Panel = b.get_node("FactionFrame")
		frame.add_theme_stylebox_override("panel", UI.fantasy_style("frame_active" if on else "frame", 0, 0))
	_refresh_faction_power()


func _refresh_faction_power() -> void:
	if not is_instance_valid(_faction_power_title):
		return
	var info: Dictionary = T.FACTIONS[faction]
	_faction_power_title.text = "%s · %s" % [info.name, info.oath]
	_faction_power_title.add_theme_color_override("font_color", info.pale)
	_faction_power_text.text = info.oath_short
	_layout_sheet.call_deferred()


func _build_modes() -> void:
	_mode_rows.clear()
	for child in _mode_list.get_children():
		child.get_parent().remove_child(child)
		child.queue_free()
	var saved := Profile.has_saved_duel()
	var entries := [
		["Continue", "Resume your duel" if saved else "No saved duel", "RESUME", _resume_duel, Color("9d7fe0")],
		["New Game", "Choose a mode", "QUICK", _open_new_game, UI.GOLD],
		["Puzzle", "Today's challenge", "PUZZLE", _open_puzzle, Color("5fae68")],
		["Codex", "How to play", "LEARN", _open_codex, UI.TEXT_DIM],
		["Settings", "Preferences", "SETTINGS", _open_settings, UI.TEXT_DIM],
		["About", "Four Realms", "ABOUT", _open_about, UI.TEXT_DIM],
	]
	for entry in entries:
		var row := _mode_row(entry[0], entry[1], entry[2], entry[3], entry[4])
		row.name = entry[0].replace(" ", "") + "Entry"
		_mode_list.add_child(row)
		if entry[0] == "Settings":
			var action: Button = row.get_meta("action")
			action.name = "SettingsButton"
		if entry[0] == "Continue" and not saved:
			row.modulate.a = 0.45
			var arrow: Button = row.get_meta("action")
			arrow.disabled = true
	if not _title_parts.is_empty():
		_update_title_layout()


func _open_new_game() -> void:
	var sheet := _sheet("NEW GAME")
	sheet.set_meta("settings", true)
	var body: VBoxContainer = sheet.get_meta("body")
	body.add_theme_constant_override("separation", 8)
	body.add_child(UI.label("Choose your faction", 28 if _title_landscape else 24, UI.GOLD))
	var layout := GridContainer.new()
	layout.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	layout.add_theme_constant_override("h_separation", 16)
	layout.add_theme_constant_override("v_separation", 12)
	body.add_child(layout)
	var factions := GridContainer.new()
	factions.columns = 2
	factions.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	factions.add_theme_constant_override("h_separation", 8)
	factions.add_theme_constant_override("v_separation", 8)
	layout.add_child(factions)
	for f in range(4):
		var button := _faction_card(f)
		button.custom_minimum_size.y = 160.0
		var art: TextureRect = button.get_node("FactionArtwork")
		art.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
		factions.add_child(button)
		_faction_buttons.append(button)
	var choices := VBoxContainer.new()
	choices.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	choices.add_theme_constant_override("separation", 8)
	layout.add_child(choices)
	var power := PanelContainer.new()
	power.name = "FactionPower"
	power.add_theme_stylebox_override("panel", UI.fantasy_style("panel", 12, 8))
	choices.add_child(power)
	var power_content := VBoxContainer.new()
	power_content.add_theme_constant_override("separation", 4)
	power.add_child(power_content)
	_faction_power_title = UI.label("", 24, UI.GOLD, false, true)
	_faction_power_title.name = "FactionPowerTitle"
	_faction_power_title.autowrap_mode = TextServer.AUTOWRAP_OFF
	_faction_power_title.clip_text = true
	_faction_power_title.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	_faction_power_title.add_theme_font_override("font", ThemeDB.fallback_font)
	power_content.add_child(_faction_power_title)
	_faction_power_text = UI.label("", 20, UI.TEXT, false, true)
	_faction_power_text.name = "FactionPowerDescription"
	_faction_power_text.max_lines_visible = 2
	_faction_power_text.add_theme_font_override("font", ThemeDB.fallback_font)
	power_content.add_child(_faction_power_text)
	var usage := UI.label("Oaths are off in Classic mode" if Profile.classic_mode else "1 Favor · Once per hand", 18, UI.TEXT_DIM, false, true)
	usage.add_theme_font_override("font", ThemeDB.fallback_font)
	power_content.add_child(usage)
	_refresh_factions()
	var modes := GridContainer.new()
	modes.columns = 2
	modes.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	modes.add_theme_constant_override("h_separation", 12)
	modes.add_theme_constant_override("v_separation", 8)
	choices.add_child(modes)
	var entries := [
		["Duel", "One hand", "QUICK", func(): _launch(T.Mode.QUICK), UI.GOLD],
		["Fifteen", "Capture totals of 15", "XV", _launch_quindici, Color("6fa8d4")],
		["Ranked", "Best of three", "RANKED", _open_ranked, Color("9d7fe0")],
		["Campaign", "Four bosses", "CAMPAIGN", _open_campaign, Color("c86f4a")],
	]
	for entry in entries:
		var row := _mode_row(entry[0], entry[1], entry[2], entry[3], entry[4], false)
		row.name = entry[0] + "Entry"
		modes.add_child(row)
		row.custom_minimum_size.y = 100.0
		row.add_theme_stylebox_override("panel", UI.fantasy_style("panel", 12, 8))
	var back := UI.button("Back", "secondary", 24)
	back.pressed.connect(_codex_close)
	body.get_parent().get_parent().add_child(back)
	sheet.set_meta("navigation_body", body)
	sheet.set_meta("navigation_layout", layout)
	sheet.set_meta("navigation_factions", factions)
	sheet.set_meta("navigation_modes", modes)
	layout.minimum_size_changed.connect(_layout_sheet)
	_layout_sheet()
	_layout_sheet.call_deferred()


func _open_about() -> void:
	var sheet := _sheet("ABOUT FOUR REALMS")
	var body: VBoxContainer = sheet.get_meta("body")
	body.add_child(_para("Four Realms is a fantasy card game inspired by Scopa. Choose Forge, Grove, Horde or Crown and play with faction Oaths, public quests and quick duels."))
	body.add_child(_para("Version 1.0"))
	var close := UI.button("Back", "secondary", 24)
	close.pressed.connect(_codex_close)
	body.add_child(close)


func _mode_row(title: String, sub: String, badge: String, cb: Callable, accent: Color, register: bool = true) -> Control:
	var p := PanelContainer.new()
	p.tooltip_text = title
	p.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	var portrait_style := UI.panel(UI.PANEL, 14, Color("927845"), 1)
	p.add_theme_stylebox_override("panel", portrait_style)
	var backdrop := TextureRect.new()
	backdrop.texture = MODE_ART
	backdrop.modulate = Color(0.48, 0.53, 0.58, 1.0)
	backdrop.texture_filter = CanvasItem.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS
	backdrop.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	backdrop.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_COVERED
	backdrop.mouse_filter = Control.MOUSE_FILTER_IGNORE
	p.add_child(backdrop)
	var h := HBoxContainer.new()
	h.add_theme_constant_override("separation", 6)
	p.add_child(h)
	h.mouse_filter = Control.MOUSE_FILTER_IGNORE

	var emblem := PanelContainer.new()
	emblem.custom_minimum_size = Vector2(34, 38)
	emblem.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	emblem.mouse_filter = Control.MOUSE_FILTER_IGNORE
	emblem.add_theme_stylebox_override("panel", UI.fantasy_style("button_hover", 0, 0))
	var glyphs := {"SETTINGS": "⚙", "ABOUT": "i", "RESUME": "▶", "QUICK": "✦", "XV": "XV", "RANKED": "★", "CAMPAIGN": "⚑", "PUZZLE": "✧", "LEARN": "i"}
	var emblem_label := UI.label(str(glyphs.get(badge, "✦")), 20, Color("a7ec80"), true)
	emblem_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	emblem_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	emblem_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	emblem.add_child(emblem_label)
	h.add_child(emblem)

	var v := VBoxContainer.new()
	v.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	v.add_theme_constant_override("separation", 1)
	h.add_child(v)
	var t := UI.label(title, 24, UI.TEXT, true, true)
	t.autowrap_mode = TextServer.AUTOWRAP_OFF
	t.clip_text = true
	t.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	t.add_theme_font_size_override("font_size", 20)
	v.add_child(t)
	var subtitle := UI.label(sub, 15, UI.TEXT_DIM, false, true)
	subtitle.max_lines_visible = 2
	subtitle.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	v.add_child(subtitle)
	v.mouse_filter = Control.MOUSE_FILTER_IGNORE
	t.mouse_filter = Control.MOUSE_FILTER_IGNORE
	subtitle.mouse_filter = Control.MOUSE_FILTER_IGNORE
	# Two-column portrait tiles use compact typography, while a wide row keeps
	# the larger display size. Full strings remain available and wrap naturally.
	var apply_type := func():
		t.add_theme_font_override("font", ThemeDB.fallback_font)
		subtitle.add_theme_font_override("font", ThemeDB.fallback_font)
		t.add_theme_font_size_override("font_size", int(clampf(size.y * 0.04, 30, 42)) if _title_landscape else int(clampf(size.x * 0.05, 26, 38)))
		subtitle.add_theme_font_size_override("font_size", int(clampf(size.y * 0.028, 23, 30)) if _title_landscape else int(clampf(size.x * 0.033, 18, 26)))
	p.resized.connect(apply_type)

	var go := UI.button("", "ghost", 18)
	go.custom_minimum_size = Vector2(34, 44)
	go.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	go.text = "›"
	go.add_theme_font_size_override("font_size", 30)
	go.add_theme_color_override("font_color", accent)
	go.pressed.connect(cb)
	go.mouse_filter = Control.MOUSE_FILTER_IGNORE
	p.set_meta("action", go)
	h.add_child(go)

	var primary := badge in ["QUICK", "RESUME"]
	var landscape_style := UI.fantasy_style("panel", 16, 14)
	var apply_style := func(wide: bool):
		p.add_theme_stylebox_override("panel", landscape_style if wide else portrait_style)
		p.custom_minimum_size.y = 150.0 if wide else (112.0 if size.x >= 460 else 80.0)
		p.size_flags_vertical = Control.SIZE_EXPAND_FILL
		backdrop.modulate = Color(0.40, 0.46, 0.52) if wide else Color(0.48, 0.53, 0.58)
		h.add_theme_constant_override("separation", 6)
		emblem.visible = wide or size.x >= 460
		emblem.custom_minimum_size = Vector2(44, 44) if wide else Vector2(34, 38)
		go.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
		emblem.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
		emblem_label.add_theme_font_size_override("font_size", 25 if wide else 20)
		v.alignment = BoxContainer.ALIGNMENT_CENTER if wide else BoxContainer.ALIGNMENT_BEGIN
		v.add_theme_constant_override("separation", 6 if wide else 1)
		go.visible = wide
		go.custom_minimum_size = Vector2(44, 44) if wide else Vector2(34, 44)
		t.add_theme_color_override("font_color", UI.GOLD if wide and primary else UI.TEXT)
		subtitle.add_theme_color_override("font_color", Color("bec8d6") if wide else UI.TEXT_DIM)
		apply_type.call()
	if badge != "" and register:
		_mode_rows.append(apply_style)
	apply_style.call(_title_landscape)

	# A swipe beginning over a row must scroll rather than immediately launch a
	# duel. Activate on release only if the pointer stayed inside the row.
	var activate := func():
		if not go.disabled:
			go.pressed.emit()
	var pointer := {"down": false, "start": Vector2.ZERO, "scroll": 0, "finger": -1}
	p.gui_input.connect(func(e):
		if e is InputEventMouseButton and e.device != InputEvent.DEVICE_ID_EMULATION and e.button_index == MOUSE_BUTTON_LEFT:
			if e.pressed:
				pointer.down = true
				pointer.start = e.global_position
				pointer.scroll = _scroll.scroll_vertical
			else:
				var tap: bool = pointer.down and e.global_position.distance_to(pointer.start) < 12.0 \
					and abs(_scroll.scroll_vertical - int(pointer.scroll)) < 4 \
					and p.get_global_rect().has_point(e.global_position)
				pointer.down = false
				if tap: activate.call()
		elif e is InputEventMouseMotion and pointer.down and e.global_position.distance_to(pointer.start) >= 12.0:
			pointer.down = false
		elif e is InputEventScreenTouch and e.device != InputEvent.DEVICE_ID_EMULATION:
			if e.pressed and not e.canceled:
				pointer.down = true
				pointer.finger = e.index
				pointer.start = e.position
				pointer.scroll = _scroll.scroll_vertical
			else:
				var tap: bool = (
					pointer.down and not e.canceled and e.index == pointer.finger
					and e.position.distance_to(pointer.start) < 12.0
					and abs(_scroll.scroll_vertical - int(pointer.scroll)) < 4
					and Rect2(Vector2.ZERO, p.size).has_point(e.position)
				)
				pointer.down = false
				if tap:
					activate.call()
			p.accept_event()
		elif e is InputEventScreenDrag and e.device != InputEvent.DEVICE_ID_EMULATION and pointer.down and e.position.distance_to(pointer.start) >= 12.0:
			pointer.down = false)
	p.mouse_filter = Control.MOUSE_FILTER_PASS
	return p


## One scrollable dialog for rules, cosmetics and animation preferences.
func _stats_panel() -> Control:
	var panel := PanelContainer.new()
	panel.name = "YourRecord"
	panel.add_theme_stylebox_override("panel", UI.fantasy_style("panel", 12, 10))
	var rows := VBoxContainer.new()
	rows.add_theme_constant_override("separation", 4)
	panel.add_child(rows)
	var title := UI.label("YOUR RECORD", 22, UI.GOLD)
	title.add_theme_font_override("font", ThemeDB.fallback_font)
	rows.add_child(title)
	var record := HBoxContainer.new()
	record.add_theme_constant_override("separation", 12)
	rows.add_child(record)
	for result in [[Profile.wins, "Wins", UI.GOOD], [Profile.losses, "Losses", UI.BAD], [Profile.draws, "Draws", UI.TEXT]]:
		var column := VBoxContainer.new()
		column.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		column.add_theme_constant_override("separation", 0)
		record.add_child(column)
		var count := UI.label(str(result[0]), 34, result[2])
		count.add_theme_font_override("font", ThemeDB.fallback_font)
		column.add_child(count)
		var caption := UI.label(result[1], 22, UI.TEXT)
		caption.add_theme_font_override("font", ThemeDB.fallback_font)
		column.add_child(caption)
	var detail := UI.label("%d games played · Best score %d\n%d sweeps · %d quests completed" % [Profile.matches, Profile.best_renown, Profile.scopas, Profile.quests_done], 20, UI.TEXT_DIM, false, true)
	detail.add_theme_font_override("font", ThemeDB.fallback_font)
	rows.add_child(detail)
	return panel




# ---------------------------------------------------------------------------
# LAUNCHERS
# ---------------------------------------------------------------------------
func _launch(mode: int, extra: Dictionary = {}) -> void:
	var cfg := {
		"mode": mode,
		"player_faction": faction,
		"oaths": not Profile.classic_mode,
	}
	cfg.merge(extra, true)
	Sfx.play("tap")
	start_duel.emit(cfg)


## Scopa di Quindici - a ruleset variant of the same duel, never mixed into
## another match.
func _launch_quindici() -> void:
	_launch(T.Mode.QUINDICI, {"rule": "quindici"})


func _resume_duel() -> void:
	if not Profile.has_saved_duel():
		return
	var state: Dictionary = Profile.saved_duel.state
	var cfg: Dictionary = {
		"mode": int(state.mode),
		"player_faction": int(state.get("player_faction", T.FORGE)),
		"bot_faction": int(state.get("bot_faction", -1)),
		"oaths": bool(state.get("oaths", not Profile.classic_mode)),
		"campaign": Duel.saved_campaign(state),
		"puzzle": Duel.saved_puzzle(state),
		"rule": state.get("rule", "classic"),
		"resume": state,
	}
	Sfx.play("tap")
	start_duel.emit(cfg)


func _open_ranked() -> void:
	_launch(T.Mode.RANKED)


func _open_campaign() -> void:
	var p := _sheet("CAMPAIGN · FOUR TWISTS")
	var v: VBoxContainer = p.get_meta("body")
	for i in range(T.CAMPAIGNS.size()):
		var c: Dictionary = T.CAMPAIGNS[i]
		var row := _campaign_row(c, i)
		v.add_child(row)


func _campaign_row(c: Dictionary, idx: int) -> Control:
	var info: Dictionary = T.FACTIONS[c.faction]
	var btn := Button.new()
	btn.focus_mode = Control.FOCUS_NONE
	btn.custom_minimum_size = Vector2(0, 86)
	var cleared: bool = Profile.campaign_cleared.has(c.id)
	btn.add_theme_stylebox_override("normal", UI.flat(UI.PANEL_HI, 14, info.color.darkened(0.3), 2))
	btn.add_theme_stylebox_override("hover", UI.flat(UI.PANEL_HI.lightened(0.06), 14, info.color, 2))
	btn.add_theme_stylebox_override("pressed", UI.flat(UI.PANEL, 14, info.color, 2))
	btn.add_theme_stylebox_override("focus", UI.flat(Color(0, 0, 0, 0), 14))
	btn.pressed.connect(func():
		_codex_close()
		_launch(T.Mode.CAMPAIGN, {"campaign": c}))
	var h := HBoxContainer.new()
	h.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	h.mouse_filter = Control.MOUSE_FILTER_IGNORE
	h.add_theme_constant_override("separation", 12)
	var m := MarginContainer.new()
	m.add_theme_constant_override("margin_left", 14)
	m.add_theme_constant_override("margin_top", 10)
	m.add_theme_constant_override("margin_bottom", 10)
	m.add_theme_constant_override("margin_right", 12)
	m.mouse_filter = Control.MOUSE_FILTER_IGNORE
	m.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	h.add_child(m)
	var v := VBoxContainer.new()
	v.add_theme_constant_override("separation", 1)
	v.mouse_filter = Control.MOUSE_FILTER_IGNORE
	m.add_child(v)
	var t := UI.label(c.name, 21, UI.TEXT, true)
	t.add_theme_font_size_override("font_size", 19)
	t.mouse_filter = Control.MOUSE_FILTER_IGNORE
	v.add_child(t)
	var l1 := UI.label("%s · %s" % [info.people, c.get("title", "")], 14, info.color)
	l1.mouse_filter = Control.MOUSE_FILTER_IGNORE
	v.add_child(l1)
	var l2 := UI.label(c.get("twist", ""), 14, UI.TEXT_DIM)
	l2.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	l2.mouse_filter = Control.MOUSE_FILTER_IGNORE
	v.add_child(l2)

	var star := UI.label("✦" if cleared else "◈", 22, UI.GOLD if cleared else Color("5a4f70"))
	star.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	star.mouse_filter = Control.MOUSE_FILTER_IGNORE
	h.add_child(star)
	btn.add_child(h)
	return btn


func _open_puzzle() -> void:
	var idx := Profile.daily_puzzle_index()
	var pz: Dictionary = T.PUZZLES[idx]
	var p := _sheet("DAILY PUZZLE")
	var v: VBoxContainer = p.get_meta("body")
	v.add_child(UI.label(pz.name, 30, UI.PARCHMENT, true))
	v.add_child(UI.label(pz.desc + "  You play solitaire: the aim is the objective, not the score.", 18, UI.TEXT_DIM, false))
	var card := _mini_deal(pz)
	v.add_child(card)
	var go := UI.button("Begin Puzzle", "primary")
	go.pressed.connect(func():
		_codex_close()
		_launch(T.Mode.PUZZLE, {"puzzle": pz, "seed": idx}))
	v.add_child(go)


func _mini_deal(pz: Dictionary) -> Control:
	var p := PanelContainer.new()
	p.add_theme_stylebox_override("panel", UI.panel(UI.BG2))
	var v := VBoxContainer.new()
	v.add_theme_constant_override("separation", 8)
	p.add_child(v)
	v.add_child(UI.label("TABLE", 13, UI.TEXT_DIM))
	var tr := HBoxContainer.new()
	tr.add_theme_constant_override("separation", 8)
	tr.alignment = BoxContainer.ALIGNMENT_CENTER
	v.add_child(tr)
	# The deal is authored as [rank, faction] PAIRS (see tables.gd PUZZLES), so each
	# one has to be converted to a card id. Passing the pair straight through gave
	# "Invalid type in function 'setup' ... Cannot convert argument 1 from Array
	# to int" the moment the Daily Puzzle sheet opened.
	for pair in pz.table:
		var cv := CardView.new()
		cv.setup(C.make(int(pair[0]), int(pair[1])), true, 58, 82)
		tr.add_child(cv)
	v.add_child(UI.label("YOUR HAND", 13, UI.TEXT_DIM))
	var hr := HBoxContainer.new()
	hr.add_theme_constant_override("separation", 8)
	hr.alignment = BoxContainer.ALIGNMENT_CENTER
	v.add_child(hr)
	for pair in pz.hand:
		var cv2 := CardView.new()
		cv2.setup(C.make(int(pair[0]), int(pair[1])), true, 58, 82)
		hr.add_child(cv2)
	if pz.has("hint"):
		var h := UI.label("Hint: " + pz.hint, 15, UI.TEXT_DIM)
		h.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		v.add_child(h)
	return p


# ---------------------------------------------------------------------------
# SHEET (modal)
# ---------------------------------------------------------------------------
func _sheet(title: String) -> PanelContainer:
	_codex_close()
	var dim := ColorRect.new()
	dim.color = Color(0, 0, 0, 0.72)
	dim.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	dim.mouse_filter = Control.MOUSE_FILTER_STOP
	dim.z_index = 100
	add_child(dim)
	_codex = dim

	var p := PanelContainer.new()
	_sheet_panel = p
	p.add_theme_stylebox_override("panel", UI.panel(UI.BG2, 22, Color("4a3f63"), 2))
	p.z_index = 101
	add_child(p)
	# full-rect element -> explicit fractions -> zero offsets (two passes: the
	# anchors are only relative to the parent once it has a size)
	p.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	p.anchor_left = 0.04
	p.anchor_right = 0.96
	p.anchor_top = 0.06
	p.anchor_bottom = 0.94
	p.offset_left = 0
	p.offset_right = 0
	p.offset_top = 0
	p.offset_bottom = 0
	p.grow_horizontal = Control.GROW_DIRECTION_BOTH
	p.grow_vertical = Control.GROW_DIRECTION_BOTH
	_layout_sheet()

	var outer := VBoxContainer.new()
	outer.add_theme_constant_override("separation", 10)
	p.add_child(outer)

	var head := HBoxContainer.new()
	outer.add_child(head)
	var l := UI.label(title, 28 if _title_landscape else 22, UI.GOLD)
	l.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	head.add_child(l)
	var x := UI.button("✕", "ghost", 20)
	x.custom_minimum_size = Vector2(44, 40)
	x.pressed.connect(_codex_close)
	head.add_child(x)

	var sc := ScrollContainer.new()
	sc.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	sc.vertical_scroll_mode = ScrollContainer.SCROLL_MODE_SHOW_NEVER
	sc.size_flags_vertical = Control.SIZE_EXPAND_FILL
	outer.add_child(sc)
	var body := VBoxContainer.new()
	body.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	body.add_theme_constant_override("separation", 12)
	sc.add_child(body)
	p.set_meta("body", body)
	return p


func _codex_close() -> void:
	# The panel and dimmer are siblings. Remove both immediately from hit testing;
	# queue_free alone leaves them blocking input until the end of the frame.
	for part in [_sheet_panel, _codex]:
		if is_instance_valid(part):
			part.hide()
			part.queue_free()
	_sheet_panel = null
	_codex = null


func _open_codex() -> void:
	var p := _sheet("CODEX")
	var v: VBoxContainer = p.get_meta("body")
	v.add_child(UI.label("How Four Realms works", 26, UI.PARCHMENT, true))
	v.add_child(_para("Four Realms is inspired by Scopa, a traditional Italian card game."))
	v.add_child(_para("A 40-card deck, ranks 1–10 in four factions, replaces the suits: Forge (Coins), Grove (Cups), Horde (Swords) and Crown (Batons). Each player is dealt 3 cards; 4 lie face up on the table."))
	v.add_child(_para("On your turn play one card. If its rank matches a table card you capture it. If a set of table cards adds up to your rank, you may capture that set instead — one card for a rank, or several whose sum equals it. Rank 10 can only take an exact 10."))
	v.add_child(_para("Clear every card off the table with a capture to score a sweep. The final capture of a hand does not score a sweep. The last player to capture collects any remaining table cards at the end of the hand."))
	v.add_child(UI.label("Scoring, live", 26, UI.PARCHMENT, true))
	for line in [
		["Loot", "most captured cards"],
		["Treasury", "most Forge cards"],
		["Runestone", "whoever holds the 7 of Forge"],
		["Banner", "best Banner total — 7=21, 6=18, Ace=16, faces=10 per faction"],
		["Glory", "one point per sweep"],
	]:
		v.add_child(_score_line(line[0], line[1]))
	v.add_child(UI.label("Oaths & Favor", 26, UI.PARCHMENT, true))
	v.add_child(_para("You gain 1 Favor whenever you make a sweep or capture any 7. Once per hand, you may spend 1 Favor to use your faction's Oath. Classic Mode turns Oaths off entirely."))
	for f in range(4):
		var info: Dictionary = T.FACTIONS[f]
		v.add_child(_oath_line(f))
	v.add_child(UI.label("Quests", 26, UI.PARCHMENT, true))
	v.add_child(_para("Every duel shows two public quests. Complete a quest to earn its bonus Renown. They exist to teach strong card-play habits: hoard the 7s, deny the Runestone, keep the table clean."))
	var close := UI.button("Understood", "primary")
	close.pressed.connect(_codex_close)
	v.add_child(close)


func _para(t: String) -> Label:
	var l := UI.label(t, 18, UI.TEXT)
	l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	return l


func _score_line(name: String, desc: String) -> Control:
	var h := HBoxContainer.new()
	h.add_theme_constant_override("separation", 10)
	var a := UI.label(name, 18, UI.GOLD)
	a.custom_minimum_size = Vector2(96, 0)
	h.add_child(a)
	var b := UI.label(desc, 17, UI.TEXT)
	b.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	b.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	h.add_child(b)
	return h


func _oath_line(f: int) -> Control:
	var info: Dictionary = T.FACTIONS[f]
	var p := PanelContainer.new()
	p.add_theme_stylebox_override("panel", UI.panel(UI.PANEL, 12, info.color.darkened(0.2), 1))
	var v := VBoxContainer.new()
	v.add_theme_constant_override("separation", 2)
	p.add_child(v)
	var h := HBoxContainer.new()
	h.add_theme_constant_override("separation", 8)
	v.add_child(h)
	var g := UI.label(T.SUIT_GLYPH[f], 18, info.color)
	h.add_child(g)
	var nm := UI.label("%s · %s" % [info.name, info.oath], 18, UI.TEXT, true)
	nm.add_theme_font_size_override("font_size", 17)
	h.add_child(nm)
	var d := UI.label(info.oath_long, 16, UI.TEXT_DIM)
	d.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	v.add_child(d)
	return p


func _show_howto() -> void:
	# wait for a real layout pass, then verify the sheet is actually on screen
	await get_tree().process_frame
	await get_tree().process_frame
	_open_codex()
	await get_tree().process_frame
	if _codex != null:
		var sheet: Control = null
		for c in get_children():
			if c is PanelContainer and c.z_index == 101:
				sheet = c
		if sheet != null and sheet.size.y < 40.0:
			push_warning("Four Realms: first-run guide failed to size; skipping it")
			_codex_close()
