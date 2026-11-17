extends Control
## Title + mode select.  Also hosts the faction picker and the codex.

const UI := preload("res://scripts/ui/ui.gd")
const CardView := preload("res://scripts/ui/card_view.gd")
const CardArt := preload("res://scripts/ui/card_art.gd")
const RealmBackground := preload("res://scripts/ui/background.gd")
const LOGO_TRANSPARENT := preload("res://assets/branding/four_realms_logo.png")
const LOGO_SCENIC := preload("res://assets/branding/four_realms_scenic.png")

signal start_duel(config: Dictionary)

const T := preload("res://scripts/tables.gd")
const C := preload("res://scripts/game/cards.gd")

var faction := T.FORGE
var _faction_buttons: Array = []
var _mode_list: GridContainer
var _faction_grid: GridContainer
var _classic_toggle: Button
var _codex: Control
var _sheet_panel: PanelContainer
var _scroll: ScrollContainer
var _title_columns: HBoxContainer
var _title_left: VBoxContainer
var _title_right: VBoxContainer
var _title_parts: Array = []
var _title_landscape := false


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

	# Portrait uses the supplied scenic artwork; the landscape identity column
	# uses its transparent counterpart. Both preserve their full aspect ratio.
	var mast := TextureRect.new()
	mast.name = "Masthead"
	mast.texture = LOGO_SCENIC
	mast.texture_filter = CanvasItem.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS
	mast.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	mast.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	mast.custom_minimum_size = Vector2(0, 330)
	mast.mouse_filter = Control.MOUSE_FILTER_IGNORE
	col.add_child(mast)

	# ---- faction picker ------------------------------------------------
	var oath_heading := _section_header("CHOOSE YOUR OATH", "Change faction and the Oath you can spend Favor on.")
	col.add_child(oath_heading)
	var heading_row: HBoxContainer = oath_heading.get_child(0)
	var settings := UI.button("Settings", "ghost", 17)
	settings.name = "SettingsButton"
	settings.custom_minimum_size = Vector2(92, 40)
	settings.tooltip_text = "Classic mode, table appearance and animations"
	settings.pressed.connect(_open_settings)
	heading_row.add_child(settings)
	var row := GridContainer.new()
	_faction_grid = row
	row.columns = 4
	row.add_theme_constant_override("h_separation", 8)
	row.add_theme_constant_override("v_separation", 8)
	col.add_child(row)
	for f in range(4):
		var b := _faction_card(f)
		row.add_child(b)
		_faction_buttons.append(b)
	_refresh_factions()

	# ---- modes ---------------------------------------------------------
	var mode_gap := UI.spacer(2)
	col.add_child(mode_gap)
	var mode_heading := _section_header("DUEL TYPES", "")
	col.add_child(mode_heading)
	_mode_list = GridContainer.new()
	_mode_list.columns = 1
	_mode_list.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_mode_list.add_theme_constant_override("h_separation", 10)
	_mode_list.add_theme_constant_override("v_separation", 10)
	col.add_child(_mode_list)
	_build_modes()

	# Settings live in their own dialog; keep the record on the title page.
	var stats_gap := UI.spacer(4)
	col.add_child(stats_gap)
	var stats := _stats_panel()
	col.add_child(stats)
	var foot_gap := UI.spacer(10)
	col.add_child(foot_gap)

	var foot := UI.label("v1.0 · cosmetically yours, mechanically fair", 15, Color(UI.TEXT_DIM.r, UI.TEXT_DIM.g, UI.TEXT_DIM.b, 0.6), false, true)
	foot.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	col.add_child(foot)
	_title_parts = [mast, oath_heading, row, mode_gap, mode_heading, _mode_list,
		stats_gap, stats, foot_gap, foot]
	_update_title_layout()


func _notification(what: int) -> void:
	if what == NOTIFICATION_RESIZED and is_node_ready() and not _title_parts.is_empty():
		_update_title_layout()
		_layout_sheet()


## Move the existing controls so rotation keeps the selected faction, scroll
## interactions, settings and callbacks. Portrait is still one touch-scroll page.
func _update_title_layout() -> void:
	if _title_parts.is_empty():
		return
	var wide := size.x > size.y * 1.12
	_faction_grid.columns = 2 if wide else 4
	_mode_list.columns = 2 if wide and size.x >= 1500.0 else 1
	if wide == _title_landscape:
		return
	_title_landscape = wide
	var mast: TextureRect = _title_parts[0]
	mast.texture = LOGO_TRANSPARENT if wide else LOGO_SCENIC
	mast.custom_minimum_size.y = 270.0 if wide else 330.0
	_title_left.alignment = BoxContainer.ALIGNMENT_CENTER if wide else BoxContainer.ALIGNMENT_BEGIN
	_title_right.alignment = BoxContainer.ALIGNMENT_CENTER if wide else BoxContainer.ALIGNMENT_BEGIN
	if wide:
		for i in [3, 4, 5]:
			_title_parts[i].reparent(_title_right, false)
		_title_right.show()
	else:
		_title_right.hide()
		for node in _title_parts:
			if node.get_parent() != _title_left:
				node.reparent(_title_left, false)
		for i in range(_title_parts.size()):
			_title_left.move_child(_title_parts[i], i)
	_scroll.scroll_vertical = 0


## Keep an open sheet readable and inside the screen during rotation.
func _layout_sheet() -> void:
	if not is_instance_valid(_sheet_panel):
		return
	_sheet_panel.anchor_left = 0.5
	_sheet_panel.anchor_right = 0.5
	var width := minf(size.x * 0.92, 820.0)
	_sheet_panel.offset_left = -width * 0.5
	_sheet_panel.offset_right = width * 0.5


func _section_header(title: String, sub: String) -> Control:
	var v := VBoxContainer.new()
	v.add_theme_constant_override("separation", 0)
	var h := HBoxContainer.new()
	h.add_theme_constant_override("separation", 10)
	v.add_child(h)
	var l := UI.label(title, 19, UI.PARCHMENT, true)
	# Preserve room for the Settings action in very narrow portrait windows.
	v.resized.connect(func(): l.add_theme_font_size_override("font_size", 15 if v.size.x < 330 else 19))
	h.add_child(l)
	var rule := ColorRect.new()
	rule.color = Color(0.55, 0.84, 0.35, 0.58)
	rule.custom_minimum_size = Vector2(0, 1)
	rule.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	rule.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	h.add_child(rule)
	if sub != "":
		v.add_child(UI.label(sub, 16, UI.TEXT_DIM, false, true))
	return v


func _faction_card(f: int) -> Button:
	var info: Dictionary = T.FACTIONS[f]
	var b := Button.new()
	b.focus_mode = Control.FOCUS_NONE
	b.custom_minimum_size = Vector2(0, 132)
	b.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	b.toggle_mode = true
	b.add_theme_stylebox_override("normal", UI.flat(UI.PANEL, 14, Color("806a40"), 1))
	b.add_theme_stylebox_override("hover", UI.flat(UI.PANEL_HI, 14, info.color, 2))
	b.add_theme_stylebox_override("pressed", UI.flat(UI.PANEL_HI, 14, info.color, 2))
	b.add_theme_stylebox_override("focus", UI.flat(Color(0, 0, 0, 0), 14))
	b.pressed.connect(func():
		faction = f
		_refresh_factions()
		Sfx.play("tap"))

	var v := VBoxContainer.new()
	v.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	v.mouse_filter = Control.MOUSE_FILTER_IGNORE
	v.add_theme_constant_override("separation", 2)
	v.alignment = BoxContainer.ALIGNMENT_CENTER
	b.add_child(v)

	# Crop the emblem from the supplied card atlas, rather than introducing
	# replacement faction art. The buttons remain ordinary accessible controls.
	var icon := TextureRect.new()
	icon.custom_minimum_size = Vector2(0, 62)
	icon.texture_filter = CanvasItem.TEXTURE_FILTER_LINEAR
	icon.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	icon.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	icon.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var source := CardArt.atlas_texture()
	if source != null:
		var atlas := AtlasTexture.new()
		atlas.atlas = source
		atlas.region = Rect2(f * 208 + 30, 70, 148, 140)
		icon.texture = atlas
		v.add_child(icon)
	else:
		var fallback := UI.label(T.SUIT_GLYPH[f], 42, info.color)
		fallback.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		fallback.mouse_filter = Control.MOUSE_FILTER_IGNORE
		v.add_child(fallback)

	var nm := UI.label(info.name, 19, UI.TEXT, true)
	nm.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	nm.mouse_filter = Control.MOUSE_FILTER_IGNORE
	nm.add_theme_font_size_override("font_size", 18)
	# Keep four faction names readable without colliding in narrow columns.
	b.resized.connect(func(): nm.add_theme_font_size_override("font_size", 14 if b.size.x < 80 else 18))
	v.add_child(nm)

	var pp := UI.label(info.people, 14, UI.TEXT_DIM)
	pp.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	pp.mouse_filter = Control.MOUSE_FILTER_IGNORE
	v.add_child(pp)

	return b


func _refresh_factions() -> void:
	for i in range(_faction_buttons.size()):
		var b: Button = _faction_buttons[i]
		var on: bool = i == faction
		b.set_pressed_no_signal(on)
		var border := Color("95e659") if on else Color("987a43")
		b.add_theme_stylebox_override("normal", UI.flat(Color("18352b") if on else UI.PANEL, 14, border, 3 if on else 1))
		b.add_theme_stylebox_override("pressed", UI.flat(Color("18352b"), 14, Color("95e659"), 3))


func _toggle(on: bool) -> Button:
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


func _refresh_toggle() -> void:
	if is_instance_valid(_classic_toggle):
		_classic_toggle.set_pressed_no_signal(Profile.classic_mode)
		_classic_toggle.queue_redraw()


func _build_modes() -> void:
	for c in _mode_list.get_children():
		c.get_parent().remove_child(c)
		c.queue_free()
	if Profile.has_saved_duel():
		_mode_list.add_child(_mode_row("Resume duel", "Pick up where you left off.", "RESUME", _resume_duel, Color("9d7fe0")))
	var quick_sub := "One hand. Oaths off. Four minutes." if Profile.classic_mode else "One hand. Oaths on. Four minutes."
	_mode_list.add_child(_mode_row("Quick Duel", quick_sub, "QUICK", func(): _launch(T.Mode.QUICK), UI.GOLD))
	_mode_list.add_child(_mode_row("Fifteen Duel", "Fifteen or nothing. Rank matches never capture.", "XV", _launch_quindici, Color("6fa8d4")))
	_mode_list.add_child(_mode_row("Ranked Duel", "Best of three. First to 11 Renown.", "RANKED", _open_ranked, Color("9d7fe0")))
	_mode_list.add_child(_mode_row("Campaign", "Four bosses, four twists.", "CAMPAIGN", _open_campaign, Color("c86f4a")))
	var pz: Dictionary = T.PUZZLES[Profile.daily_puzzle_index()]
	var pz_sub: String = pz.name + (" · solved today" if Profile.puzzle_done_today() else "")
	_mode_list.add_child(_mode_row("Daily Puzzle", pz_sub, "PUZZLE", _open_puzzle, Color("5fae68")))
	_mode_list.add_child(_mode_row("Codex", "Rules, scoring, Oaths, quests.", "LEARN", _open_codex, UI.TEXT_DIM))


func _mode_row(title: String, sub: String, badge: String, cb: Callable, accent: Color) -> Control:
	var p := PanelContainer.new()
	p.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	p.add_theme_stylebox_override("panel", UI.panel(UI.PANEL, 14, Color("927845"), 1))
	var h := HBoxContainer.new()
	h.add_theme_constant_override("separation", 10)
	p.add_child(h)

	var emblem := PanelContainer.new()
	emblem.custom_minimum_size = Vector2(46, 46)
	emblem.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	emblem.mouse_filter = Control.MOUSE_FILTER_IGNORE
	emblem.add_theme_stylebox_override("panel", UI.flat(Color("183526"), 22, Color("78c85e"), 2))
	var glyphs := {"RESUME": "▶", "QUICK": "✦", "XV": "XV", "RANKED": "★", "CAMPAIGN": "⚑", "PUZZLE": "✧", "LEARN": "i"}
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
	t.add_theme_font_size_override("font_size", 22)
	v.add_child(t)
	v.add_child(UI.label(sub, 16, UI.TEXT_DIM, false, true))

	var go := UI.button("", "ghost", 18)
	go.custom_minimum_size = Vector2(42, 44)
	go.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	go.text = "›"
	go.add_theme_font_size_override("font_size", 30)
	go.add_theme_color_override("font_color", accent)
	go.pressed.connect(cb)
	h.add_child(go)

	# A swipe beginning over a row must scroll rather than immediately launch a
	# duel. Activate on release only if the pointer stayed inside the row.
	var pointer := {"down": false, "start": Vector2.ZERO, "scroll": 0}
	p.gui_input.connect(func(e):
		if e is InputEventMouseButton and e.button_index == MOUSE_BUTTON_LEFT:
			if e.pressed:
				pointer.down = true
				pointer.start = e.global_position
				pointer.scroll = _scroll.scroll_vertical
			else:
				var tap: bool = pointer.down and e.global_position.distance_to(pointer.start) < 12.0 \
					and abs(_scroll.scroll_vertical - int(pointer.scroll)) < 4 \
					and p.get_global_rect().has_point(e.global_position)
				pointer.down = false
				if tap: cb.call()
		elif e is InputEventMouseMotion and pointer.down and e.global_position.distance_to(pointer.start) >= 12.0:
			pointer.down = false)
	p.mouse_filter = Control.MOUSE_FILTER_PASS
	return p


## One scrollable dialog for rules, cosmetics and animation preferences.
func _open_settings() -> void:
	var sheet := _sheet("SETTINGS")
	var body: VBoxContainer = sheet.get_meta("body")
	body.add_child(_classic_panel())
	body.add_child(_orientation_panel())
	body.add_child(_cosmetics_panel())
	body.add_child(_animation_panel())
	var done := UI.button("Done", "primary", 20)
	done.name = "SettingsDone"
	done.pressed.connect(_codex_close)
	body.add_child(done)


func _orientation_panel() -> Control:
	var panel := PanelContainer.new()
	panel.name = "OrientationSettings"
	panel.add_theme_stylebox_override("panel", UI.panel(UI.PANEL, 16, Color("806a40")))
	var col := VBoxContainer.new()
	col.add_theme_constant_override("separation", 8)
	panel.add_child(col)
	col.add_child(UI.label("ORIENTATION", 18, UI.GOLD))
	var choice := OptionButton.new()
	choice.name = "OrientationChoice"
	choice.custom_minimum_size = Vector2(0, 44)
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
	col.add_child(choice)
	var note := "Auto follows the device. Forced directions use the phone orientation."
	if OS.has_feature("web"):
		choice.disabled = true
		note = "The browser controls orientation; the layout follows the window."
	elif not DisplayServer.has_feature(DisplayServer.FEATURE_ORIENTATION):
		note = "Auto follows the window. On desktop, forced modes resize the window."
	col.add_child(UI.label(note, 14, UI.TEXT_DIM, false, true))
	return panel


func _classic_panel() -> Control:
	var panel := PanelContainer.new()
	panel.name = "ClassicSettings"
	panel.add_theme_stylebox_override("panel", UI.panel())
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 12)
	panel.add_child(row)
	var labels := VBoxContainer.new()
	labels.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.add_child(labels)
	labels.add_child(UI.label("Classic Mode", 22, UI.TEXT, true))
	labels.add_child(UI.label("Oaths off. Pure card play, no Favor.", 17, UI.TEXT_DIM, false, true))
	_classic_toggle = _toggle(Profile.classic_mode)
	_classic_toggle.set_meta("setting_key", "classic_mode")
	_classic_toggle.tooltip_text = "Enable or disable Classic Mode"
	_classic_toggle.pressed.connect(func():
		Profile.classic_mode = not Profile.classic_mode
		Profile.save_profile()
		_refresh_toggle()
		_build_modes()
		Sfx.play("select", -14.0))
	row.add_child(_classic_toggle)
	return panel


## Presentation settings. Every animation can be turned off and the game stays
## completely playable - they are flourish, not mechanics.
func _animation_panel() -> Control:
	var p := PanelContainer.new()
	p.name = "AnimationSettings"
	p.add_theme_stylebox_override("panel", UI.panel(UI.PANEL, 16, Color("806a40")))
	var v := VBoxContainer.new()
	v.add_theme_constant_override("separation", 8)
	p.add_child(v)
	var h := HBoxContainer.new()
	v.add_child(h)
	h.add_child(UI.label("ANIMATION", 18, UI.GOLD))
	var sp := Control.new()
	sp.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	h.add_child(sp)
	h.add_child(UI.label("cosmetic · optional", 14, UI.TEXT_DIM))

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
		tv.add_child(UI.label(row[2], 15, UI.TEXT_DIM, false, true))
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


func _stats_panel() -> Control:
	var p := PanelContainer.new()
	p.add_theme_stylebox_override("panel", UI.panel(UI.PANEL, 16, Color("806a40")))
	var v := VBoxContainer.new()
	v.add_theme_constant_override("separation", 8)
	p.add_child(v)
	var h := HBoxContainer.new()
	h.add_theme_constant_override("separation", 10)
	v.add_child(h)
	h.add_child(UI.label("YOUR RECORD", 18, UI.GOLD))
	var sp := Control.new()
	sp.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	h.add_child(sp)
	h.add_child(UI.label("%d W · %d L · %d D" % [Profile.wins, Profile.losses, Profile.draws], 17, UI.TEXT_DIM))

	var grid := GridContainer.new()
	grid.columns = 4
	grid.add_theme_constant_override("h_separation", 8)
	v.add_child(grid)
	grid.add_child(_stat("Duels", str(Profile.matches)))
	grid.add_child(_stat("Sweeps", str(Profile.scopas)))
	grid.add_child(_stat("Best", str(Profile.best_renown)))
	grid.add_child(_stat("Quests", str(Profile.quests_done)))
	return p


func _stat(k: String, v: String) -> Control:
	var p := PanelContainer.new()
	p.add_theme_stylebox_override("panel", UI.flat(UI.BG2, 10))
	p.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	var vv := VBoxContainer.new()
	vv.add_theme_constant_override("separation", 0)
	p.add_child(vv)
	var a := UI.label(v, 24, UI.PARCHMENT, true)
	a.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	vv.add_child(a)
	var b := UI.label(k.to_upper(), 12, UI.TEXT_DIM)
	b.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	vv.add_child(b)
	return p


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
	var sv: Dictionary = Profile.saved_duel
	if sv.is_empty():
		return
	var cfg: Dictionary = {
		"mode": int(sv.get("mode", T.Mode.QUICK)),
		"player_faction": int(sv.get("player_faction", T.FORGE)),
		"oaths": not Profile.classic_mode,
		"campaign": sv.get("campaign", {}),
		"puzzle": sv.get("puzzle", {}),
		"rule": sv.get("state", {}).get("rule", "classic"),
		"resume": sv.get("state", {}),
	}
	Sfx.play("tap")
	start_duel.emit(cfg)


func _cosmetics_panel() -> Control:
	var p := PanelContainer.new()
	p.name = "TableSettings"
	p.add_theme_stylebox_override("panel", UI.panel(UI.PANEL, 16, Color("806a40")))
	var v := VBoxContainer.new()
	v.add_theme_constant_override("separation", 8)
	p.add_child(v)
	var h := HBoxContainer.new()
	v.add_child(h)
	h.add_child(UI.label("YOUR TABLE", 18, UI.GOLD))
	var sp := Control.new()
	sp.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	h.add_child(sp)
	h.add_child(UI.label("appearance only", 14, UI.TEXT_DIM))

	# card backs
	var back_row := HBoxContainer.new()
	back_row.add_theme_constant_override("separation", 10)
	v.add_child(back_row)
	back_row.add_child(UI.label("Card back", 16, UI.TEXT_DIM))
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
	board_row.add_theme_constant_override("separation", 10)
	v.add_child(board_row)
	board_row.add_child(UI.label("Board", 16, UI.TEXT_DIM))
	var themes := [Color("1b2a24"), Color("1a2230"), Color("2a1c22"), Color("241f2e")]
	var board_group := ButtonGroup.new()
	for i in range(themes.size()):
		var b2 := Button.new()
		b2.focus_mode = Control.FOCUS_NONE
		b2.custom_minimum_size = Vector2(38, 32)
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
	var l := UI.label(title, 17, UI.GOLD)
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
	_classic_toggle = null


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
	v.add_child(_para("Every duel shows two public quests. Both players can chase them; you get the bonus Renown when you complete one. They exist to teach strong card-play habits: hoard the 7s, deny the Runestone, keep the table clean."))
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
