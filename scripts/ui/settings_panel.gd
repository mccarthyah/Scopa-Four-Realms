extends RefCounted
## Settings controls shared by the home screen and paused matches.

const UI := preload("res://scripts/ui/ui.gd")
const CardView := preload("res://scripts/ui/card_view.gd")


static func populate(sheet: PanelContainer, close: Callable, reflow: Callable, in_game: bool = false) -> void:
	sheet.set_meta("settings", true)
	var body: VBoxContainer = sheet.get_meta("body")
	body.add_theme_constant_override("separation", 0)
	var grid := GridContainer.new()
	grid.name = "SettingsGrid"
	grid.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	grid.add_theme_constant_override("h_separation", 16)
	grid.add_theme_constant_override("v_separation", 12)
	body.add_child(grid)
	var left := VBoxContainer.new()
	left.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	left.add_theme_constant_override("separation", 12)
	grid.add_child(left)
	var gameplay := PanelContainer.new()
	gameplay.add_theme_stylebox_override("panel", UI.fantasy_style("panel", 14, 12))
	left.add_child(gameplay)
	var gameplay_rows := VBoxContainer.new()
	gameplay_rows.add_theme_constant_override("separation", 8)
	gameplay.add_child(gameplay_rows)
	for section in [_classic_panel(in_game), _orientation_panel()]:
		section.add_theme_stylebox_override("panel", StyleBoxEmpty.new())
		gameplay_rows.add_child(section)
	left.add_child(_cosmetics_panel())
	var animation := _animation_panel()
	animation.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	animation.size_flags_vertical = Control.SIZE_SHRINK_BEGIN
	grid.add_child(animation)
	var outer: VBoxContainer = body.get_parent().get_parent()
	var done := UI.button("Back" if in_game else "Done", "primary", 22)
	done.name = "SettingsDone"
	done.size_flags_horizontal = Control.SIZE_SHRINK_END
	done.custom_minimum_size = Vector2(140, 48)
	done.pressed.connect(close)
	outer.add_child(done)
	var controls: Array[Node] = [sheet]
	while not controls.is_empty():
		var control := controls.pop_back() as Node
		controls.append_array(control.get_children())
		if control is Label or control is Button:
			control.add_theme_font_override("font", ThemeDB.fallback_font)
			control.set_meta("settings_font_size", maxi(control.get_theme_font_size("font_size"), 20))
		if control is Button:
			control.set_meta("settings_minimum", control.custom_minimum_size)
	sheet.set_meta("settings_grid", grid)
	grid.minimum_size_changed.connect(reflow)
	reflow.call()
	reflow.call_deferred()


static func layout(sheet: PanelContainer, area: Vector2, wide: bool, maximum: float = 1280.0) -> void:
	var width := minf(area.x * 0.92, maximum if wide else 820.0)
	sheet.anchor_left = 0.5
	sheet.anchor_right = 0.5
	sheet.offset_left = -width * 0.5
	sheet.offset_right = width * 0.5
	var grid: GridContainer = sheet.get_meta("settings_grid")
	grid.columns = 2 if wide and width >= 900.0 else 1
	var factor := 1.3 if wide else 1.0
	var controls: Array[Node] = [sheet]
	while not controls.is_empty():
		var control := controls.pop_back() as Node
		controls.append_array(control.get_children())
		if control.has_meta("settings_font_size"):
			control.add_theme_font_size_override("font_size", int(control.get_meta("settings_font_size") * factor))
		if control.has_meta("settings_minimum"):
			var minimum: Vector2 = control.get_meta("settings_minimum")
			minimum.y = maxf(minimum.y, 44.0) * factor
			control.custom_minimum_size = minimum
	var outer: VBoxContainer = grid.get_parent().get_parent().get_parent()
	var chrome := outer.get_combined_minimum_size().y + sheet.get_theme_stylebox("panel").get_minimum_size().y
	var height := minf(area.y * 0.9, grid.get_combined_minimum_size().y + chrome + 8.0)
	sheet.anchor_top = 0.5
	sheet.anchor_bottom = 0.5
	sheet.offset_top = -height * 0.5
	sheet.offset_bottom = height * 0.5


static func _toggle(on: bool) -> Button:
	var b := Button.new()
	b.toggle_mode = true
	b.button_pressed = on
	b.focus_mode = Control.FOCUS_NONE
	b.custom_minimum_size = Vector2(64, 36)
	b.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	b.add_theme_stylebox_override("normal", UI.flat(UI.PANEL, 18, Color("453a5c"), 2))
	b.add_theme_stylebox_override("hover", UI.flat(UI.PANEL_HI, 18, UI.GOLD, 2))
	b.add_theme_stylebox_override("pressed", UI.flat(UI.GOLD, 18))
	b.add_theme_stylebox_override("focus", UI.flat(Color(0, 0, 0, 0), 18))
	b.draw.connect(func():
		var r := Rect2(Vector2.ZERO, b.size)
		var cx := r.size.x * (0.66 if b.button_pressed else 0.34)
		# Dark on gold when enabled; the former gold-on-gold thumb was invisible.
		b.draw_circle(Vector2(cx, r.size.y * 0.5), 13.0, UI.INK if b.button_pressed else UI.TEXT_DIM))
	return b


static func _orientation_panel() -> Control:
	var panel := PanelContainer.new()
	panel.name = "OrientationSettings"
	panel.add_theme_stylebox_override("panel", UI.fantasy_style("panel", 10, 8))
	var col := VBoxContainer.new()
	col.add_theme_constant_override("separation", 4)
	panel.add_child(col)
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 12)
	col.add_child(row)
	row.add_child(UI.label("Orientation", 22, UI.TEXT))
	var choice := OptionButton.new()
	choice.name = "OrientationChoice"
	choice.custom_minimum_size = Vector2(100, 44)
	choice.fit_to_longest_item = false
	choice.clip_text = true
	choice.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	choice.add_theme_font_override("font", UI.font_bold())
	choice.add_theme_font_size_override("font_size", 16)
	choice.add_theme_color_override("font_color", UI.TEXT)
	choice.add_theme_color_override("font_hover_color", UI.GOLD)
	choice.add_theme_stylebox_override("normal", UI.flat(UI.BG2, 8, Color("4a3f5e"), 1))
	choice.add_theme_stylebox_override("hover", UI.flat(UI.PANEL_HI, 8, UI.GOLD, 1))
	choice.add_theme_stylebox_override("pressed", UI.flat(UI.PANEL_HI, 8, UI.GOLD, 1))
	var values := ["auto", "landscape_left", "landscape_right", "portrait"]
	for text in ["Auto", "Landscape Left", "Landscape Right", "Portrait"]:
		choice.add_item(text)
	choice.select(maxi(values.find(Profile.orientation), 0))
	choice.item_selected.connect(func(index: int):
		Profile.set_orientation(values[index])
		Sfx.play("select", -14.0))
	row.add_child(choice)
	var note := "Auto follows the device. Forced directions use the phone orientation."
	if Engine.is_embedded_in_editor():
		choice.disabled = true
		note = "The embedded Game panel cannot resize. Stop the game, turn off Embed Game on Next Play in Godot's Game tab, then run again in a separate window."
	elif OS.has_feature("web"):
		choice.disabled = true
		note = "The browser controls orientation; the layout follows the window."
	elif not DisplayServer.has_feature(DisplayServer.FEATURE_ORIENTATION):
		note = "Auto follows the window. On desktop, forced modes resize the window."
	choice.tooltip_text = note
	if choice.disabled:
		col.add_child(UI.label(note, 14, UI.TEXT_DIM, false, true))
	return panel


static func _classic_panel(in_game: bool) -> Control:
	var panel := PanelContainer.new()
	panel.name = "ClassicSettings"
	panel.add_theme_stylebox_override("panel", UI.fantasy_style("panel", 10, 8))
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 12)
	var rows := VBoxContainer.new()
	rows.add_theme_constant_override("separation", 8)
	panel.add_child(rows)
	rows.add_child(row)
	var labels := VBoxContainer.new()
	labels.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.add_child(labels)
	labels.add_child(UI.label("Classic · new games" if in_game else "Classic · Oaths off", 22, UI.TEXT, false, true))
	labels.tooltip_text = "Oaths off. Pure card play, no Favor."
	var classic_toggle := _toggle(Profile.classic_mode)
	classic_toggle.set_meta("setting_key", "classic_mode")
	classic_toggle.tooltip_text = "Disable Oaths for new games. The current match keeps its rules." if in_game else "Enable or disable Classic Mode"
	classic_toggle.pressed.connect(func():
		Profile.classic_mode = not Profile.classic_mode
		Profile.save_profile()
		classic_toggle.set_pressed_no_signal(Profile.classic_mode)
		Sfx.play("select", -14.0))
	row.add_child(classic_toggle)
	var confirmation_row := HBoxContainer.new()
	confirmation_row.add_theme_constant_override("separation", 12)
	rows.add_child(confirmation_row)
	var confirmation_label := UI.label("Two-tap play", 22, UI.TEXT, false, true)
	confirmation_label.tooltip_text = "Select a card, then tap it again or tap a highlighted capture to confirm."
	confirmation_row.add_child(confirmation_label)
	var confirmation := _toggle(Profile.confirm_card_play)
	confirmation.name = "ConfirmCardPlay"
	confirmation.set_meta("setting_key", "confirm_card_play")
	confirmation.tooltip_text = confirmation_label.tooltip_text
	confirmation.pressed.connect(func():
		Profile.confirm_card_play = confirmation.button_pressed
		Profile.save_profile()
		Sfx.play("select", -14.0))
	confirmation_row.add_child(confirmation)
	return panel


## Presentation settings. Every animation can be turned off and the game stays
## completely playable - they are flourish, not mechanics.


static func _animation_panel() -> Control:
	var p := PanelContainer.new()
	p.name = "AnimationSettings"
	p.add_theme_stylebox_override("panel", UI.fantasy_style("panel", 10, 8))
	var v := VBoxContainer.new()
	v.add_theme_constant_override("separation", 4)
	p.add_child(v)
	var h := HBoxContainer.new()
	v.add_child(h)
	h.add_child(UI.label("ANIMATION", 18, UI.GOLD))
	var sp := Control.new()
	sp.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	h.add_child(sp)


	var rows := [
		["anim_enabled", "All animation", "Master switch. Off = instant, zero flourish."],
		["anim_spin", "Card spin", "Played cards turn a full 360 as they land."],
		["anim_slow", "Slower play", "Holds the beat so captures stay readable."],
		["anim_match", "Match cue", "Flash a ring on each card being taken."],
	]
	var toggles := {}
	for row in rows:
		var key: String = row[0]
		var r := HBoxContainer.new()
		r.add_theme_constant_override("separation", 12)
		v.add_child(r)
		var tv := VBoxContainer.new()
		tv.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		tv.add_theme_constant_override("separation", 0)
		r.add_child(tv)
		tv.add_child(UI.label(row[1], 19, UI.TEXT, true))
		r.tooltip_text = row[2]
		var t := _toggle(bool(Profile.get(key)))
		t.set_meta("setting_key", key)
		var k := key
		t.pressed.connect(func():
			Profile.set(k, not bool(Profile.get(k)))
			Profile.save_profile()
			Sfx.play("select", -14.0))
		r.add_child(t)
		toggles[key] = t
	# the sub-switches only mean anything while the master is on
	var dim_subs := func() -> void:
		var on: bool = Profile.anim_enabled
		for k in ["anim_spin", "anim_slow", "anim_match"]:
			var b: Button = toggles[k]
			b.disabled = not on
			b.modulate.a = 1.0 if on else 0.4
	dim_subs.call()
	var m: Button = toggles["anim_enabled"]
	m.pressed.connect(dim_subs)
	return p


static func _cosmetics_panel() -> Control:
	var p := PanelContainer.new()
	p.name = "TableSettings"
	p.add_theme_stylebox_override("panel", UI.fantasy_style("panel", 10, 8))
	var v := VBoxContainer.new()
	v.add_theme_constant_override("separation", 4)
	p.add_child(v)
	var h := HBoxContainer.new()
	v.add_child(h)
	h.add_child(UI.label("YOUR TABLE", 18, UI.GOLD))
	var sp := Control.new()
	sp.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	h.add_child(sp)


	# card backs
	var back_row := HBoxContainer.new()
	back_row.add_theme_constant_override("separation", 10)
	v.add_child(back_row)
	var back_label := UI.label("Back", 20, UI.TEXT)
	back_label.custom_minimum_size.x = 70
	back_row.add_child(back_label)
	var back_group := ButtonGroup.new()
	for i in range(3):
		var b := Button.new()
		b.focus_mode = Control.FOCUS_NONE
		b.custom_minimum_size = Vector2(46, 62)
		b.toggle_mode = true
		b.button_group = back_group
		b.button_pressed = i == Profile.card_back
		b.set_meta("card_back", i)
		b.tooltip_text = "Card back %d" % (i + 1)
		b.add_theme_stylebox_override("normal", UI.flat(Color(0, 0, 0, 0), 8))
		b.add_theme_stylebox_override("hover", UI.flat(Color(1, 1, 1, 0.06), 8))
		b.add_theme_stylebox_override("pressed", UI.flat(Color(0, 0, 0, 0), 8, UI.GOLD, 2))
		b.add_theme_stylebox_override("focus", UI.flat(Color(0, 0, 0, 0), 8))
		var cv := CardView.new()
		cv.setup(-1, false, 42, 58)
		cv.back_style = i
		# CardView._ready defaults to STOP for playable cards; this preview is
		# added before its parent enters the tree, so override after _ready runs.
		cv.ready.connect(func(): cv.mouse_filter = Control.MOUSE_FILTER_IGNORE)
		b.add_child(cv)
		cv.position = Vector2(2, 2)
		var idx := i
		b.pressed.connect(func():
			Profile.card_back = idx
			Profile.save_profile()
			Sfx.play("select", -12.0))
		back_row.add_child(b)
	var sp2 := Control.new()
	sp2.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	back_row.add_child(sp2)

	# board themes
	var board_row := HBoxContainer.new()
	board_row.add_theme_constant_override("separation", 6)
	v.add_child(board_row)
	var board_label := UI.label("Board", 20, UI.TEXT)
	board_label.custom_minimum_size.x = 70
	board_row.add_child(board_label)
	var themes := [Color("1b2a24"), Color("1a2230"), Color("2a1c22"), Color("241f2e")]
	var board_group := ButtonGroup.new()
	for i in range(themes.size()):
		var b2 := Button.new()
		b2.focus_mode = Control.FOCUS_NONE
		b2.custom_minimum_size = Vector2(36, 44)
		b2.toggle_mode = true
		b2.button_group = board_group
		b2.button_pressed = i == Profile.board_theme
		b2.set_meta("board_theme", i)
		b2.tooltip_text = "Board theme %d" % (i + 1)
		b2.add_theme_stylebox_override("normal", UI.flat(themes[i], 8, Color("4a3f5e"), 1))
		b2.add_theme_stylebox_override("hover", UI.flat(themes[i].lightened(0.12), 8, UI.GOLD, 2))
		b2.add_theme_stylebox_override("pressed", UI.flat(themes[i], 8, UI.GOLD, 2))
		b2.add_theme_stylebox_override("focus", UI.flat(Color(0, 0, 0, 0), 8))
		var idx2 := i
		b2.pressed.connect(func():
			Profile.board_theme = idx2
			Profile.save_profile()
			Sfx.play("select", -12.0))
		board_row.add_child(b2)
	var sp3 := Control.new()
	sp3.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	board_row.add_child(sp3)
	return p
