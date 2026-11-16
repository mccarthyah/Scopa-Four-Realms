extends Control
## Title + mode select.  Also hosts the faction picker and the codex.

const UI := preload("res://scripts/ui/ui.gd")
const CardView := preload("res://scripts/ui/card_view.gd")
const RealmBackground := preload("res://scripts/ui/background.gd")

signal start_duel(config: Dictionary)

const T := preload("res://scripts/tables.gd")
const C := preload("res://scripts/game/cards.gd")

var faction := T.FORGE
var _faction_buttons: Array = []
var _mode_list: VBoxContainer
var _classic_toggle: Button
var _codex: Control
var _scroll: ScrollContainer


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
	_scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	root.add_child(_scroll)

	var col := VBoxContainer.new()
	col.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	col.add_theme_constant_override("separation", 14)
	_scroll.add_child(col)

	# ---- masthead -------------------------------------------------------
	var mast := Control.new()
	mast.custom_minimum_size = Vector2(0, 178)
	col.add_child(mast)

	var emblem := Control.new()
	emblem.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	emblem.mouse_filter = Control.MOUSE_FILTER_IGNORE
	emblem.draw.connect(_draw_masthead.bind(emblem))
	mast.add_child(emblem)

	var title := UI.label("SCOPA", 62, UI.PARCHMENT, true)
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	title.add_theme_color_override("font_shadow_color", Color(0, 0, 0, 0.7))
	title.add_theme_constant_override("shadow_offset_y", 4)
	mast.add_child(title)
	title.set_anchors_and_offsets_preset(Control.PRESET_TOP_WIDE)
	title.position = Vector2(0, 34)

	var sub := UI.label("FOUR REALMS", 26, UI.GOLD, true)
	sub.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	mast.add_child(sub)
	sub.set_anchors_and_offsets_preset(Control.PRESET_TOP_WIDE)
	sub.position = Vector2(0, 104)

	var tag := UI.label("Capture. Sweep. Rule the table.", 19, UI.TEXT_DIM)
	tag.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	mast.add_child(tag)
	tag.set_anchors_and_offsets_preset(Control.PRESET_TOP_WIDE)
	tag.position = Vector2(0, 140)

	# ---- faction picker ------------------------------------------------
	col.add_child(_section_header("CHOOSE YOUR OATH", "Change faction and the Oath you can spend Favor on."))
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 8)
	col.add_child(row)
	for f in range(4):
		var b := _faction_card(f)
		row.add_child(b)
		_faction_buttons.append(b)
	_refresh_factions()

	# ---- modes ---------------------------------------------------------
	col.add_child(UI.spacer(2))
	col.add_child(_section_header("DUEL TYPES", ""))
	_mode_list = VBoxContainer.new()
	_mode_list.add_theme_constant_override("separation", 10)
	col.add_child(_mode_list)
	_build_modes()

	# ---- classic toggle + stats ---------------------------------------
	var opt := PanelContainer.new()
	opt.add_theme_stylebox_override("panel", UI.panel())
	col.add_child(opt)
	var ob := HBoxContainer.new()
	ob.add_theme_constant_override("separation", 12)
	opt.add_child(ob)
	var ol := VBoxContainer.new()
	ol.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	ob.add_child(ol)
	ol.add_child(UI.label("Classic Mode", 22, UI.TEXT, true))
	ol.add_child(UI.label("Oaths off. Pure Scopa, no Favor.", 17, UI.TEXT_DIM))
	_classic_toggle = _toggle(Profile.classic_mode)
	_classic_toggle.pressed.connect(func():
		Profile.classic_mode = not Profile.classic_mode
		Profile.save_profile()
		_refresh_toggle())
	ob.add_child(_classic_toggle)

	col.add_child(UI.spacer(4))
	col.add_child(_cosmetics_panel())
	col.add_child(UI.spacer(4))
	col.add_child(_stats_panel())
	col.add_child(UI.spacer(10))

	var foot := UI.label("v1.0 · cosmetically yours, mechanically fair", 15, Color(UI.TEXT_DIM.r, UI.TEXT_DIM.g, UI.TEXT_DIM.b, 0.6))
	foot.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	col.add_child(foot)


func _section_header(title: String, sub: String) -> Control:
	var v := VBoxContainer.new()
	v.add_theme_constant_override("separation", 0)
	var h := HBoxContainer.new()
	h.add_theme_constant_override("separation", 10)
	v.add_child(h)
	var l := UI.label(title, 18, UI.GOLD)
	l.add_theme_font_override("font", UI.font_bold())
	h.add_child(l)
	var rule := ColorRect.new()
	rule.color = Color(UI.GOLD.r, UI.GOLD.g, UI.GOLD.b, 0.22)
	rule.custom_minimum_size = Vector2(0, 1)
	rule.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	rule.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	h.add_child(rule)
	if sub != "":
		v.add_child(UI.label(sub, 16, UI.TEXT_DIM))
	return v


func _draw_masthead(node: Control) -> void:
	var w := node.size.x
	# decorative flourishes either side of the subtitle
	var y := 118.0
	for sgn in [-1.0, 1.0]:
		var s: float = sgn
		var x: float = w * 0.5 + s * 96.0
		node.draw_line(Vector2(x + s * 12, y), Vector2(x + s * 54, y), Color(UI.GOLD.r, UI.GOLD.g, UI.GOLD.b, 0.5), 1.5)
		node.draw_circle(Vector2(x + s * 8, y), 2.2, Color(UI.GOLD.r, UI.GOLD.g, UI.GOLD.b, 0.8))


func _faction_card(f: int) -> Button:
	var info: Dictionary = T.FACTIONS[f]
	var b := Button.new()
	b.focus_mode = Control.FOCUS_NONE
	b.custom_minimum_size = Vector2(0, 132)
	b.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	b.toggle_mode = true
	b.add_theme_stylebox_override("normal", UI.flat(UI.PANEL, 14, Color("3a3050"), 1))
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

	var glyph := UI.label(T.SUIT_GLYPH[f], 26, info.color)
	glyph.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	glyph.mouse_filter = Control.MOUSE_FILTER_IGNORE
	v.add_child(glyph)

	var nm := UI.label(info.name, 19, UI.TEXT, true)
	nm.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	nm.mouse_filter = Control.MOUSE_FILTER_IGNORE
	nm.add_theme_font_size_override("font_size", 18)
	v.add_child(nm)

	var pp := UI.label(info.people, 14, UI.TEXT_DIM)
	pp.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	pp.mouse_filter = Control.MOUSE_FILTER_IGNORE
	v.add_child(pp)

	return b


func _refresh_factions() -> void:
	for i in range(_faction_buttons.size()):
		var b: Button = _faction_buttons[i]
		var info: Dictionary = T.FACTIONS[i]
		var on: bool = i == faction
		b.set_pressed_no_signal(on)
		b.add_theme_stylebox_override("normal", UI.flat(UI.PANEL_HI if on else UI.PANEL, 14,
			info.color if on else Color("3a3050"), 2 if on else 1))


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
		b.draw_circle(Vector2(cx, r.size.y * 0.5), 13.0, UI.GOLD if b.button_pressed else UI.TEXT_DIM)
		b.draw_circle(Vector2(cx, r.size.y * 0.5), 13.0, Color(0, 0, 0, 0.0)))
	return b


func _refresh_toggle() -> void:
	_classic_toggle.button_pressed = Profile.classic_mode
	_classic_toggle.queue_redraw()


func _build_modes() -> void:
	for c in _mode_list.get_children():
		c.queue_free()
	if Profile.has_saved_duel():
		_mode_list.add_child(_mode_row("Resume duel", "Pick up where you left off.", "RESUME", _resume_duel, Color("9d7fe0")))
	_mode_list.add_child(_mode_row("Quick Duel", "One hand. Oaths on. Four minutes.", "QUICK", func(): _launch(T.Mode.QUICK), UI.GOLD))
	_mode_list.add_child(_mode_row("Ranked Duel", "Best of three. First to 11 Renown.", "RANKED", _open_ranked, Color("9d7fe0")))
	_mode_list.add_child(_mode_row("Campaign", "Four bosses, four twists.", "CAMPAIGN", _open_campaign, Color("c86f4a")))
	var pz: Dictionary = T.PUZZLES[Profile.daily_puzzle_index()]
	var pz_sub: String = pz.name + (" · solved today" if Profile.puzzle_done_today() else "")
	_mode_list.add_child(_mode_row("Daily Puzzle", pz_sub, "PUZZLE", _open_puzzle, Color("5fae68")))
	_mode_list.add_child(_mode_row("Codex", "Rules, scoring, Oaths, quests.", "LEARN", _open_codex, UI.TEXT_DIM))


func _mode_row(title: String, sub: String, badge: String, cb: Callable, accent: Color) -> Control:
	var p := PanelContainer.new()
	p.add_theme_stylebox_override("panel", UI.panel())
	var h := HBoxContainer.new()
	h.add_theme_constant_override("separation", 14)
	p.add_child(h)

	var v := VBoxContainer.new()
	v.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	v.add_theme_constant_override("separation", 1)
	h.add_child(v)
	var t := UI.label(title, 24, UI.TEXT, true)
	t.add_theme_font_size_override("font_size", 22)
	v.add_child(t)
	v.add_child(UI.label(sub, 16, UI.TEXT_DIM))

	var go := UI.button("", "ghost", 18)
	go.custom_minimum_size = Vector2(52, 44)
	go.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	go.text = "›"
	go.add_theme_font_size_override("font_size", 30)
	go.add_theme_color_override("font_color", accent)
	go.pressed.connect(cb)
	h.add_child(go)

	# whole row is tappable
	p.gui_input.connect(func(e):
		if e is InputEventMouseButton and e.pressed:
			cb.call())
	p.mouse_filter = Control.MOUSE_FILTER_STOP
	return p


func _stats_panel() -> Control:
	var p := PanelContainer.new()
	p.add_theme_stylebox_override("panel", UI.panel(UI.PANEL, 16, Color("3a3050")))
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
	grid.add_child(_stat("Scopas", str(Profile.scopas)))
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
		"resume": sv.get("state", {}),
	}
	Sfx.play("tap")
	start_duel.emit(cfg)


func _cosmetics_panel() -> Control:
	var p := PanelContainer.new()
	p.add_theme_stylebox_override("panel", UI.panel(UI.PANEL, 16, Color("3a3050")))
	var v := VBoxContainer.new()
	v.add_theme_constant_override("separation", 8)
	p.add_child(v)
	var h := HBoxContainer.new()
	v.add_child(h)
	h.add_child(UI.label("YOUR TABLE", 18, UI.GOLD))
	var sp := Control.new()
	sp.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	h.add_child(sp)
	h.add_child(UI.label("cosmetics only · no card power", 14, UI.TEXT_DIM))

	# card backs
	var back_row := HBoxContainer.new()
	back_row.add_theme_constant_override("separation", 10)
	v.add_child(back_row)
	back_row.add_child(UI.label("Card back", 16, UI.TEXT_DIM))
	for i in range(3):
		var b := Button.new()
		b.focus_mode = Control.FOCUS_NONE
		b.custom_minimum_size = Vector2(46, 62)
		b.add_theme_stylebox_override("normal", UI.flat(Color(0, 0, 0, 0), 8))
		b.add_theme_stylebox_override("hover", UI.flat(Color(1, 1, 1, 0.06), 8))
		b.add_theme_stylebox_override("pressed", UI.flat(Color(1, 1, 1, 0.1), 8))
		b.add_theme_stylebox_override("focus", UI.flat(Color(0, 0, 0, 0), 8))
		var cv := CardView.new()
		cv.setup(-1, false, 42, 58)
		cv.back_style = i
		cv.mouse_filter = Control.MOUSE_FILTER_IGNORE
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
	for i in range(themes.size()):
		var b2 := Button.new()
		b2.focus_mode = Control.FOCUS_NONE
		b2.custom_minimum_size = Vector2(44, 30)
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
	for c in pz.table:
		var cv := CardView.new()
		cv.setup(c, true, 58, 82)
		tr.add_child(cv)
	v.add_child(UI.label("YOUR HAND", 13, UI.TEXT_DIM))
	var hr := HBoxContainer.new()
	hr.add_theme_constant_override("separation", 8)
	hr.alignment = BoxContainer.ALIGNMENT_CENTER
	v.add_child(hr)
	for c in pz.hand:
		var cv2 := CardView.new()
		cv2.setup(c, true, 58, 82)
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
	sc.size_flags_vertical = Control.SIZE_EXPAND_FILL
	outer.add_child(sc)
	var body := VBoxContainer.new()
	body.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	body.add_theme_constant_override("separation", 12)
	sc.add_child(body)
	p.set_meta("body", body)
	return p


func _codex_close() -> void:
	if _codex != null and is_instance_valid(_codex):
		_codex.queue_free()
	_codex = null


func _open_codex() -> void:
	var p := _sheet("CODEX")
	var v: VBoxContainer = p.get_meta("body")
	v.add_child(UI.label("How Scopa works", 26, UI.PARCHMENT, true))
	v.add_child(_para("A 40-card deck, ranks 1–10 in four factions, replaces the suits: Forge (Coins), Grove (Cups), Horde (Swords) and Crown (Batons). Each player is dealt 3 cards; 4 lie face up on the table."))
	v.add_child(_para("On your turn play one card. If its rank matches a table card you capture it. If a set of table cards adds up to your rank, you may capture that set instead — one card for a rank, or several whose sum equals it. Rank 10 can only take an exact 10."))
	v.add_child(_para("Clear every card off the table with a capture and you score a Scopa. The last player to capture sweeps the remaining table cards at the end of the hand."))
	v.add_child(UI.label("Scoring, live", 26, UI.PARCHMENT, true))
	for line in [
		["Loot", "most captured cards"],
		["Treasury", "most Forge cards"],
		["Runestone", "whoever holds the 7 of Forge"],
		["Banner", "best Primiera — 7=21, 6=18, Ace=16, faces=10 per faction"],
		["Glory", "one point per scopa"],
	]:
		v.add_child(_score_line(line[0], line[1]))
	v.add_child(UI.label("Oaths & Favor", 26, UI.PARCHMENT, true))
	v.add_child(_para("You gain 1 Favor whenever you make a scopa or capture any 7. Once per hand, you may spend 1 Favor to use your faction's Oath. Classic Mode turns Oaths off entirely."))
	for f in range(4):
		var info: Dictionary = T.FACTIONS[f]
		v.add_child(_oath_line(f))
	v.add_child(UI.label("Quests", 26, UI.PARCHMENT, true))
	v.add_child(_para("Every duel shows two public quests. Both players can chase them; you get the bonus Renown when you complete one. They exist to teach the deeper Scopa habits: hoard the 7s, deny the Runestone, keep the table clean."))
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
			push_warning("Scopa: first-run guide failed to size; skipping it")
			_codex_close()
