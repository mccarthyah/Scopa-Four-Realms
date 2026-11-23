extends Control
# gdlint: disable=class-definitions-order
# Declarations here are grouped for readability (constants beside the tables
# they describe, fields beside the build code that fills them) rather than
# strictly consts-before-vars. Ordering is a style rule with no runtime effect;
# see docs/ASSESSMENT.md.


const LANDSCAPE_LOGO := preload("res://assets/branding/four_realms_logo.png")
## The duel table: HUD, opponent, table cards, your hand, Oath controls,
## scoring sheet and the campaign puzzle goals.  Portrait-first, one-handed.

const UI := preload("res://scripts/ui/ui.gd")
const SettingsPanel := preload("res://scripts/ui/settings_panel.gd")
const FX := preload("res://scripts/ui/fx.gd")
const CardView := preload("res://scripts/ui/card_view.gd")
const EffectAtlas := preload("res://scripts/ui/effect_atlas.gd")
const DuelAI := preload("res://scripts/game/ai.gd")

signal exit_to_menu
signal play_again(config)

const T := preload("res://scripts/tables.gd")
const ScoreSheet := preload("res://scripts/ui/score_sheet.gd")
const OathPickers := preload("res://scripts/ui/oath_pickers.gd")
const CardAnim := preload("res://scripts/ui/card_anim.gd")
const PuzzleVerdict := preload("res://scripts/ui/puzzle_verdict.gd")
const C := preload("res://scripts/game/cards.gd")
const Duel := preload("res://scripts/game/duel.gd")

const TURN_SECONDS := 26.0
## How many toasts may stack before the oldest is retired. Without a cap the box
## accumulated one panel per event for the whole duel.
const MAX_TOASTS := 3
## Largest frame delta the turn clock will accept. A suspended app or a long hitch
## can deliver a multi-second delta; without this clamp that landed as one frame
## and auto-played the player's turn.
const MAX_TURN_DELTA := 0.25

var config: Dictionary = {}
var duel: Duel

# --- widgets -----------------------------------------------------------------
var _top_name: Label
var _top_meta: Label
var _top_avatar: Control
var _top_favor: PanelContainer
var _top_scoopa: PanelContainer
var _renown0: Label
var _renown1: Label
var _renown_bar: Control
var _turn_label: Label
var _turn_meter: Control
var _bot_row: HBoxContainer
## Opponent hand cards are drawn this fraction of a playfield card.
const BOT_HAND_SCALE := 0.5
var _table_box: Control
var _table_grid: Control
var _table_sub: Label
var _hand_box: Control
var _hand_row: HBoxContainer
var _btn_oath: Button
var _btn_hint: Button
var _btn_pile: Button
var _btn_menu: Button
var _favor_strip: Control
var _quest_list: VBoxContainer
var _banner_meter: Control
var _toast_box: VBoxContainer
var _overlay: Control
## True while the open sheet is one the player must answer (the results screen), so
## the back gesture cannot discard it.
var _overlay_blocks_back := false
var _menu_paused := false
var _pause_before_menu := false
var _deck_chip: PanelContainer
var _goal_chip: PanelContainer
var _score_chip: PanelContainer
var _portrait_root: VBoxContainer
var _landscape_root: HBoxContainer
var _landscape_side: VBoxContainer
var _landscape_table: VBoxContainer
var _landscape_bottom: HBoxContainer
var _landscape_player: VBoxContainer
var _layout_mode := "portrait"
var _layout_parts := {}
var _landscape := false
var _layout_ready := false
var _layout_refresh_pending := false

# --- runtime -----------------------------------------------------------------
var _turn_time := TURN_SECONDS
var _selection := -1
var _busy := false
var _ai_token := 0
var _hinted_once := false
var _match_recorded := false
var _last_tick := -10.0
var _scopa_held := false


func _ready() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_build_duel()


# ---------------------------------------------------------------------------
# BOOT
# ---------------------------------------------------------------------------
func _build_duel() -> void:
	var mode: int = config.get("mode", T.Mode.QUICK)
	var pfac: int = config.get("player_faction", T.FORGE)
	var camp: Dictionary = config.get("campaign", {})
	var bfac: int = config.get("bot_faction", -1)
	if bfac < 0:
		if camp.has("faction"):
			bfac = int(camp.faction)
		else:
			var pool := [T.FORGE, T.GROVE, T.HORDE, T.CROWN]
			pool.erase(pfac)
			bfac = pool[randi() % pool.size()]
	duel = Duel.new({
		"mode": mode,
		"oaths": config.get("oaths", true),
		"player_faction": pfac,
		"bot_faction": bfac,
		"campaign": config.get("campaign", {}),
		"puzzle": config.get("puzzle", {}),
		"rule": config.get("rule", "classic"),
		"seed": config.get("seed", randi()),
	})

	var root := VBoxContainer.new()
	_portrait_root = root
	root.name = "PortraitLayout"
	root.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	root.offset_left = 12
	root.offset_right = -12
	root.offset_top = 10
	root.offset_bottom = -10
	root.add_theme_constant_override("separation", 6)
	add_child(root)

	# A compact portrait crest echoes the reference without consuming the
	# interactive card area on shorter windows.
	var portrait_logo := TextureRect.new()
	portrait_logo.name = "PortraitDuelLogo"
	portrait_logo.texture = LANDSCAPE_LOGO
	portrait_logo.texture_filter = CanvasItem.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS
	portrait_logo.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	portrait_logo.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	portrait_logo.custom_minimum_size = Vector2(0, 100)
	portrait_logo.mouse_filter = Control.MOUSE_FILTER_IGNORE
	root.add_child(portrait_logo)

	var t := _build_top()
	t.name = "HUD"
	root.add_child(t)
	var mid := _build_mid()
	mid.name = "TurnBar"
	root.add_child(mid)
	var bot := _build_bot_hand()
	bot.name = "BotHand"
	root.add_child(bot)
	var tbl := _build_table()
	tbl.name = "Table"
	root.add_child(tbl)
	var q := _build_quests()
	q.name = "Quests"
	root.add_child(q)
	var h := _build_hand()
	h.name = "Hand"
	root.add_child(h)
	var a := _build_actions()
	a.name = "Actions"
	root.add_child(a)
	_layout_parts = {"HUD": t, "TurnBar": mid, "BotHand": bot, "Table": tbl,
		"Quests": q, "Hand": h, "Actions": a}
	_landscape_root = HBoxContainer.new()
	_landscape_root.name = "LandscapeLayout"
	_landscape_root.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_landscape_root.offset_left = 12
	_landscape_root.offset_right = -12
	_landscape_root.offset_top = 10
	_landscape_root.offset_bottom = -10
	_landscape_root.add_theme_constant_override("separation", 14)
	_landscape_root.hide()
	add_child(_landscape_root)
	_landscape_side = VBoxContainer.new()
	_landscape_side.name = "DuelSidebar"
	_landscape_side.custom_minimum_size = Vector2(380, 0)
	_landscape_side.add_theme_constant_override("separation", 8)
	_landscape_root.add_child(_landscape_side)
	var side_logo := TextureRect.new()
	side_logo.name = "LandscapeStatusLogo"
	side_logo.texture = LANDSCAPE_LOGO
	side_logo.texture_filter = CanvasItem.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS
	side_logo.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	side_logo.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	side_logo.size_flags_vertical = Control.SIZE_EXPAND_FILL
	side_logo.size_flags_stretch_ratio = 0.65
	side_logo.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_landscape_side.add_child(side_logo)
	var side_spacer := Control.new()
	side_spacer.name = "LandscapeStatusSpacer"
	side_spacer.size_flags_vertical = Control.SIZE_EXPAND_FILL
	side_spacer.size_flags_stretch_ratio = 0.35
	side_spacer.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_landscape_side.add_child(side_spacer)
	_landscape_table = VBoxContainer.new()
	_landscape_table.name = "DuelPlayfield"
	_landscape_table.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_landscape_table.add_theme_constant_override("separation", 6)
	_landscape_root.add_child(_landscape_table)
	_landscape_bottom = HBoxContainer.new()
	_landscape_bottom.name = "PlayerBottomRow"
	_landscape_bottom.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_landscape_bottom.add_theme_constant_override("separation", 16)
	_landscape_table.add_child(_landscape_bottom)
	_landscape_player = VBoxContainer.new()
	_landscape_player.name = "PlayerActions"
	_landscape_player.custom_minimum_size = Vector2(320, 0)
	_landscape_player.size_flags_vertical = Control.SIZE_SHRINK_END
	_landscape_bottom.add_child(_landscape_player)
	_layout_ready = true
	_apply_orientation_layout()
	_table_grid.resized.connect(_schedule_layout_refresh)

	_toast_box = VBoxContainer.new()
	_toast_box.set_anchors_and_offsets_preset(Control.PRESET_TOP_WIDE)
	_toast_box.offset_left = 40
	_toast_box.offset_right = -40
	_toast_box.offset_top = 118
	_toast_box.offset_bottom = 330
	_toast_box.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_toast_box.alignment = BoxContainer.ALIGNMENT_BEGIN
	_toast_box.add_theme_constant_override("separation", 6)
	add_child(_toast_box)

	if config.has("resume") and config.resume.size() > 0:
		duel.from_dict(config.resume)
	duel.drain_events()
	_refresh_all()
	if config.has("resume") and config.resume.size() > 0:
		_resumed_boot()
	else:
		_boot_sequence()


func _resumed_boot() -> void:
	_busy = false
	_refresh_all()
	_toast("Welcome back", "Your duel was restored.")
	_after_turn()


func _build_top() -> Control:
	var p := PanelContainer.new()
	p.add_theme_stylebox_override("panel", UI.panel(UI.PANEL, 16, Color("826b40"), 1))
	var v := VBoxContainer.new()
	v.add_theme_constant_override("separation", 4)
	p.add_child(v)

	# row 1: opponent
	var r1 := HBoxContainer.new()
	r1.name = "OpponentRow"
	r1.add_theme_constant_override("separation", 10)
	v.add_child(r1)

	_top_avatar = _avatar_pip(duel.bot_faction)
	r1.add_child(_top_avatar)

	var nv := VBoxContainer.new()
	nv.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	nv.add_theme_constant_override("separation", 0)
	r1.add_child(nv)
	_top_name = UI.label("", 20, UI.TEXT, true, true)
	_top_name.add_theme_font_size_override("font_size", 19)
	nv.add_child(_top_name)
	_top_meta = UI.label("", 14, UI.TEXT_DIM, false, true)
	nv.add_child(_top_meta)

	_top_favor = UI.chip("FAVOR 0", Color("3a2f22"), UI.GOLD, 15)
	r1.add_child(_top_favor)
	_top_scoopa = UI.chip("SWEEPS 0", Color("2b2338"), UI.TEXT_DIM, 15)
	r1.add_child(_top_scoopa)

	var counters := HBoxContainer.new()
	counters.name = "HUDCounters"
	counters.add_theme_constant_override("separation", 8)
	counters.hide()
	v.add_child(counters)

	# row 2: renown bar
	var r2 := HBoxContainer.new()
	r2.add_theme_constant_override("separation", 8)
	v.add_child(r2)
	_renown0 = UI.label("0", 30, UI.PARCHMENT, true)
	r2.add_child(_renown0)
	_renown_bar = Control.new()
	_renown_bar.custom_minimum_size = Vector2(0, 20)
	_renown_bar.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_renown_bar.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	_renown_bar.draw.connect(_draw_renown_bar)
	r2.add_child(_renown_bar)
	_renown1 = UI.label("0", 30, UI.PARCHMENT, true)
	_renown1.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	r2.add_child(_renown1)
	return p


func _avatar_pip(f: int) -> Control:
	var c := Control.new()
	c.custom_minimum_size = Vector2(46, 46)
	c.draw.connect(func():
		var info: Dictionary = T.FACTIONS[f]
		var ctr := c.size * 0.5
		c.draw_circle(ctr, 22, info.deep)
		c.draw_arc(ctr, 22, 0, TAU, 40, info.color, 2.0, true)
		var txt: String = T.SUIT_GLYPH[f]
		var sz := 22
		var w := UI.font_bold().get_string_size(txt, HORIZONTAL_ALIGNMENT_LEFT, -1, sz).x
		c.draw_string(UI.font_bold(), ctr + Vector2(-w * 0.5, 8), txt, HORIZONTAL_ALIGNMENT_LEFT, -1, sz, info.pale))
	return c


func _build_mid() -> Control:
	var p := PanelContainer.new()
	p.add_theme_stylebox_override("panel", UI.panel(UI.BG2, 14, Color("332b47")))
	var h := BoxContainer.new()
	h.name = "TurnContents"
	h.add_theme_constant_override("separation", 10)
	p.add_child(h)

	_turn_label = UI.label("", 17, UI.GOLD)
	_turn_label.size_flags_horizontal = Control.SIZE_SHRINK_BEGIN
	_turn_label.custom_minimum_size = Vector2(132, 0)
	h.add_child(_turn_label)

	_turn_meter = Control.new()
	_turn_meter.custom_minimum_size = Vector2(0, 18)
	_turn_meter.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_turn_meter.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	_turn_meter.draw.connect(_draw_turn_meter)
	h.add_child(_turn_meter)

	_deck_chip = UI.chip("DECK 40", Color("2b2338"), UI.TEXT_DIM, 14)
	h.add_child(_deck_chip)
	_goal_chip = UI.chip("", Color("2b2338"), UI.GOLD, 14)
	h.add_child(_goal_chip)
	_score_chip = UI.chip("", Color("2b2338"), UI.TEXT_DIM, 14)
	h.add_child(_score_chip)
	var counters := HBoxContainer.new()
	counters.name = "TurnCounters"
	counters.add_theme_constant_override("separation", 6)
	counters.hide()
	h.add_child(counters)
	return p


## The opponent's hand, face down, sitting above the playfield. Cards shrink as
## the hand grows so it never eats the felt.
func _build_bot_hand() -> Control:
	var box := Control.new()
	box.custom_minimum_size = Vector2(0, 54)
	box.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	_bot_row = HBoxContainer.new()
	_bot_row.alignment = BoxContainer.ALIGNMENT_CENTER
	_bot_row.add_theme_constant_override("separation", 7)
	_bot_row.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	box.add_child(_bot_row)
	return box


## Height and width of one opponent hand card.
func _bot_card_size() -> Vector2:
	var fh: float = clampf(maxf(_table_box.size.y, 260.0) * 0.40, 148.0, 208.0)
	return Vector2(fh / 1.404, fh) * BOT_HAND_SCALE


func _notification(what: int) -> void:
	# Android's hardware/gesture back. Without this the OS closed the activity
	# mid-duel with no pause, no confirmation and no hint that Continue exists.
	# Back closes the top sheet if one is open, otherwise opens the pause menu.
	if what == NOTIFICATION_WM_GO_BACK_REQUEST:
		_on_back_pressed()
		return
	if what != NOTIFICATION_RESIZED or not is_node_ready() or not _layout_ready:
		return
	_apply_orientation_layout()
	_schedule_layout_refresh()
	_layout_game_dialogs()


func _unhandled_input(event: InputEvent) -> void:
	# Escape is the desktop equivalent of Android's back gesture.
	if event.is_action_pressed("ui_cancel"):
		_on_back_pressed()
		get_viewport().set_input_as_handled()


func _on_back_pressed() -> void:
	if not is_node_ready() or duel == null:
		return
	# A sheet that demands an answer (the results screen) is never dismissed by a
	# back press, or the player would lose the hand summary with no way back to it.
	if _overlay != null and is_instance_valid(_overlay):
		if _overlay_blocks_back:
			return
		_close_overlay()
		return
	if duel.hand_over:
		return
	_open_menu()


## Reparent existing controls rather than rebuilding the duel: a rotation must
## not restart the game, invalidate a selection, or discard an open sheet.
func _apply_orientation_layout() -> void:
	if not _layout_ready:
		return
	var wide := size.x > size.y * 1.12
	# Landscape shares the bottom row between the hand and its action controls.
	var mode := "full" if wide and size.x >= 1450.0 else ("compact" if wide else "portrait")
	_portrait_root.get_node("PortraitDuelLogo").visible = not wide and size.y >= 850.0
	if mode == _layout_mode:
		return
	_layout_mode = mode
	_landscape = wide
	if wide:
		for key in ["HUD", "TurnBar", "BotHand", "Quests"]:
			_layout_parts[key].reparent(_landscape_side, false)
		_layout_parts.Table.reparent(_landscape_table, false)
		_landscape_table.move_child(_layout_parts.Table, 0)
		_layout_parts.Hand.reparent(_landscape_bottom, false)
		_landscape_bottom.move_child(_layout_parts.Hand, 0)
		_layout_parts.Hand.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		_layout_parts.Actions.reparent(_landscape_player, false)
		_layout_parts.Actions.vertical = true
		_landscape_player.show()
		_landscape_side.move_child(_landscape_side.get_node("LandscapeStatusLogo"), 0)
		_landscape_side.move_child(_landscape_side.get_node("LandscapeStatusSpacer"), _landscape_side.get_child_count() - 1)
		_portrait_root.hide()
		_landscape_root.show()
	else:
		for key in ["HUD", "TurnBar", "BotHand", "Table", "Quests", "Hand", "Actions"]:
			_layout_parts[key].reparent(_portrait_root, false)
		_layout_parts.Actions.vertical = false
		_landscape_root.hide()
		_portrait_root.show()
	var opponent_row: HBoxContainer = _layout_parts.HUD.find_child("OpponentRow", true, false)
	var hud_counters: HBoxContainer = _layout_parts.HUD.find_child("HUDCounters", true, false)
	for counter in [_top_favor, _top_scoopa]:
		counter.reparent(hud_counters if wide else opponent_row, false)
	hud_counters.visible = wide
	var turn_contents: BoxContainer = _layout_parts.TurnBar.find_child("TurnContents", true, false)
	var turn_counters: HBoxContainer = _layout_parts.TurnBar.find_child("TurnCounters", true, false)
	turn_contents.vertical = wide
	for counter in [_deck_chip, _goal_chip, _score_chip]:
		counter.reparent(turn_counters if wide else turn_contents, false)
	turn_counters.visible = wide
	_btn_menu.text = "Menu" if wide else "☰"
	_table_grid.offset_bottom = -70 if wide else -26
	_table_sub.offset_top = -68 if wide else -24
	_table_sub.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART if wide else TextServer.AUTOWRAP_OFF
	_hand_row.offset_top = 48 if wide else 28
	_favor_strip.offset_bottom = 42 if wide else 22
	_favor_strip.custom_minimum_size.y = 42 if wide else 22
	_apply_duel_typography()
	_schedule_layout_refresh()


func _apply_duel_typography() -> void:
	for section in _layout_parts.values():
		var controls: Array[Node] = [section]
		while not controls.is_empty():
			var control := controls.pop_back() as Node
			controls.append_array(control.get_children())
			if control is Label or control is Button:
				if not control.has_meta("portrait_font_size"):
					control.set_meta("portrait_font_size", control.get_theme_font_size("font_size"))
					control.set_meta("portrait_font", control.get_theme_font("font"))
				var original: int = control.get_meta("portrait_font_size")
				control.add_theme_font_size_override("font_size", maxi(28, int(original * 1.4)) if _landscape else original)
				control.add_theme_font_override("font", ThemeDB.fallback_font if _landscape else control.get_meta("portrait_font"))
			if control is Button:
				if not control.has_meta("portrait_minimum"):
					control.set_meta("portrait_minimum", control.custom_minimum_size)
				var minimum: Vector2 = control.get_meta("portrait_minimum")
				if _landscape:
					minimum.y = maxf(minimum.y, 80.0)
				control.custom_minimum_size = minimum



func _schedule_layout_refresh() -> void:
	if not _layout_ready or _layout_refresh_pending:
		return
	_layout_refresh_pending = true
	_refresh_after_layout.call_deferred()


func _refresh_after_layout() -> void:
	# Containers settle after a frame, including after reparenting and resizing.
	await get_tree().process_frame
	_layout_refresh_pending = false
	if not is_inside_tree() or duel == null:
		return
	var hand_width: float = _hand_box.size.x
	var hw: float = _hand_card_width(hand_width)
	_hand_box.custom_minimum_size = Vector2(0, int(hw * 1.404) + (56 if _landscape else 36))
	_refresh_table()
	_refresh_hand()
	_refresh_bot_hand()


func _refresh_bot_hand() -> void:
	if _bot_row == null:
		return
	for c in _bot_row.get_children():
		c.get_parent().remove_child(c)
		c.queue_free()
	var n: int = duel.hands[1].size()
	if n == 0:
		_bot_row.add_child(UI.label("no cards left", 13, UI.TEXT_DIM))
		return
	# Sized as a fraction of a PLAYFIELD card rather than of the window, so the card
	# the opponent plays grows by a known factor (BOT_HAND_SCALE) and the window
	# size never makes the hand and the felt disagree.
	var sz := _bot_card_size()
	var cw: float = maxf(sz.x, 28.0)
	var ch: float = maxf(sz.y, 40.0)
	# The row must be at least as tall as the cards, or the container compresses
	# them out of aspect (measured: 91 px cards squashed into a 54 px box).
	var holder := _bot_row.get_parent() as Control
	if holder != null:
		holder.custom_minimum_size = Vector2(0, ch + 6.0)
	for i in range(n):
		var cv := CardView.new()
		cv.setup(-1, false, int(cw), int(ch))
		cv.back_style = Profile.card_back
		cv.mouse_filter = Control.MOUSE_FILTER_IGNORE
		cv.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		_bot_row.add_child(cv)
		cv.enter_anim(0.04 * i)


func _build_table() -> Control:
	_table_box = Control.new()
	_table_box.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_table_box.custom_minimum_size = Vector2(0, 200)
	_table_box.draw.connect(_draw_table_felt)

	# A plain Control, not an HBoxContainer: a box lays every card out in ONE row
	# and simply overflows once they are wider than the felt, which is how cards
	# ended up off both sides. We solve the layout ourselves - see _table_layout().
	_table_grid = Control.new()
	_table_grid.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_table_grid.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_table_grid.offset_top = 6
	_table_grid.offset_bottom = -26
	_table_box.add_child(_table_grid)

	_table_sub = UI.label("", 14, Color(UI.TEXT_DIM.r, UI.TEXT_DIM.g, UI.TEXT_DIM.b, 0.85))
	_table_sub.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_table_box.add_child(_table_sub)
	_table_sub.set_anchors_and_offsets_preset(Control.PRESET_BOTTOM_WIDE)
	_table_sub.offset_top = -24
	return _table_box


func _build_quests() -> Control:
	var p := PanelContainer.new()
	p.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	p.add_theme_stylebox_override("panel", UI.panel(UI.PANEL, 14, Color("826b40")))
	var v := VBoxContainer.new()
	v.add_theme_constant_override("separation", 3)
	p.add_child(v)
	var head := HBoxContainer.new()
	head.add_theme_constant_override("separation", 8)
	v.add_child(head)
	head.add_child(UI.label("QUESTS", 13, UI.GOLD))
	_banner_meter = Control.new()
	_banner_meter.custom_minimum_size = Vector2(0, 14)
	_banner_meter.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_banner_meter.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	_banner_meter.draw.connect(_draw_banner_meter)
	head.add_child(_banner_meter)
	_quest_list = VBoxContainer.new()
	_quest_list.add_theme_constant_override("separation", 2)
	v.add_child(_quest_list)
	return p


func _build_hand() -> Control:
	UI.resolve_fonts()
	_hand_box = Control.new()
	_hand_box.custom_minimum_size = Vector2(0, int(clampf(size.x * 0.215, 112.0, 150.0) * 1.404) + 36)
	_hand_box.size_flags_vertical = Control.SIZE_SHRINK_END

	_hand_row = HBoxContainer.new()
	_hand_row.alignment = BoxContainer.ALIGNMENT_CENTER
	_hand_row.add_theme_constant_override("separation", 10)
	_hand_row.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_hand_row.offset_top = 28
	_hand_box.add_child(_hand_row)

	var fav := Control.new()
	fav.set_anchors_and_offsets_preset(Control.PRESET_TOP_WIDE)
	fav.offset_bottom = 22
	fav.custom_minimum_size = Vector2(0, 22)
	fav.mouse_filter = Control.MOUSE_FILTER_IGNORE
	fav.draw.connect(_draw_favor_pips)
	_hand_box.add_child(fav)
	_favor_strip = fav
	return _hand_box


func _build_actions() -> Control:
	var h := BoxContainer.new()
	h.vertical = false
	h.add_theme_constant_override("separation", 8)
	var info: Dictionary = T.FACTIONS[duel.player_faction]

	_btn_oath = UI.button("", "secondary", 17)
	_btn_oath.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_btn_oath.custom_minimum_size = Vector2(0, 52)
	_btn_oath.pressed.connect(_on_oath_pressed)
	h.add_child(_btn_oath)

	_btn_hint = UI.button("Hint", "ghost", 16)
	_btn_hint.custom_minimum_size = Vector2(76, 52)
	_btn_hint.pressed.connect(_on_hint)
	h.add_child(_btn_hint)

	_btn_pile = UI.button("Pile", "ghost", 16)
	_btn_pile.custom_minimum_size = Vector2(76, 52)
	_btn_pile.pressed.connect(_show_pile)
	h.add_child(_btn_pile)

	_btn_menu = UI.button("☰", "ghost", 18)
	_btn_menu.custom_minimum_size = Vector2(52, 52)
	_btn_menu.pressed.connect(_open_menu)
	h.add_child(_btn_menu)
	return h


# ---------------------------------------------------------------------------
# DRAWING HELPERS
# ---------------------------------------------------------------------------
func _draw_renown_bar() -> void:
	var w := _renown_bar.size.x
	var h := _renown_bar.size.y
	_renown_bar.draw_rect(Rect2(0, 0, w, h), Color("241d31"))
	var target: int = T.MODE_INFO[duel.mode].target
	var total: int = maxi(1, duel.renown[0] + duel.renown[1])
	var f: float = float(duel.renown[0]) / float(maxi(1, duel.renown[0] + duel.renown[1])) if (duel.renown[0] + duel.renown[1]) > 0 else 0.5
	var split := w * f
	var cf0: Color = T.FACTIONS[duel.player_faction].color
	var cf1: Color = T.FACTIONS[duel.bot_faction].color
	_renown_bar.draw_rect(Rect2(0, 0, split, h), cf0)
	_renown_bar.draw_rect(Rect2(split, 0, w - split, h), cf1)
	_renown_bar.draw_rect(Rect2(split - 1, 0, 2, h), UI.INK)
	if target > 0:
		var tx := w * clampf(float(target) / 22.0, 0.0, 1.0)
		_renown_bar.draw_line(Vector2(tx, -2), Vector2(tx, h + 2), UI.GOLD, 2.0)
	# segmentation
	for i in range(1, 11):
		var x := w * i / 11.0
		_renown_bar.draw_line(Vector2(x, 0), Vector2(x, h), Color(0, 0, 0, 0.18), 1.0)


func _draw_turn_meter() -> void:
	var w := _turn_meter.size.x
	var h := _turn_meter.size.y
	_turn_meter.draw_rect(Rect2(0, 0, w, h), Color("221b2e"))
	var mine := duel.turn == 0
	var f := clampf(_turn_time / TURN_SECONDS, 0.0, 1.0)
	var col := UI.GOOD if f > 0.45 else (UI.GOLD if f > 0.2 else UI.BAD)
	if not mine:
		col = Color("5a4f70")
		f = 1.0
	_turn_meter.draw_rect(Rect2(0, 0, w * f, h), Color(col.r, col.g, col.b, 0.9))
	_turn_meter.draw_rect(Rect2(0, 0, w, h), Color(0, 0, 0, 0))
	for i in range(1, 26):
		var x := w * i / 26.0
		_turn_meter.draw_line(Vector2(x, 2), Vector2(x, h - 2), Color(0, 0, 0, 0.12), 1.0)


func _draw_banner_meter() -> void:
	var w := _banner_meter.size.x
	var h := _banner_meter.size.y
	var a: int = duel.primiera_total(duel.captured[0])
	var b: int = duel.primiera_total(duel.captured[1])
	var tot: int = maxi(1, a + b)
	var f := float(a) / float(tot)
	_banner_meter.draw_rect(Rect2(0, 0, w, h), Color("221b2e"))
	_banner_meter.draw_rect(Rect2(0, 0, w * f, h), T.FACTIONS[duel.player_faction].color)
	_banner_meter.draw_rect(Rect2(w * f, 0, w * (1 - f), h), T.FACTIONS[duel.bot_faction].color)
	_banner_meter.draw_line(Vector2(w * f, 0), Vector2(w * f, h), UI.INK, 1.5)


func _draw_favor_pips() -> void:
	var fav_node := _favor_strip
	if fav_node == null:
		return
	var n: int = duel.favor[0]
	var font := ThemeDB.fallback_font if _landscape else UI.font_bold()
	var font_size := 28 if _landscape else 12
	var baseline := 30.0 if _landscape else 16.0
	var x := 124.0 if _landscape else 96.0
	var gap := 26.0 if _landscape else 20.0
	var center_y := 20.0 if _landscape else 10.0
	var diameter := 22.0 if _landscape else 16.0
	fav_node.draw_string(font, Vector2(4, baseline), "FAVOR", HORIZONTAL_ALIGNMENT_LEFT, -1, font_size, UI.TEXT_DIM)
	for i in range(Duel.MAX_FAVOR):
		var center := Vector2(x + i * gap, center_y)
		var icon := EffectAtlas.FAVOR_FILLED if i < n else EffectAtlas.FAVOR_EMPTY
		var pip_rect := Rect2(center - Vector2.ONE * diameter * 0.5, Vector2.ONE * diameter)
		if not UI.LOW_SPEC or not EffectAtlas.draw_sprite(fav_node, pip_rect, icon):
			if i < n:
				fav_node.draw_circle(center, diameter * 0.375, UI.GOLD)
				fav_node.draw_circle(center, diameter * 0.1875, Color("fff6dd"))
			else:
				fav_node.draw_arc(center, diameter * 0.375, 0, TAU, 18, Color("4a3f5e"), 1.4, true)
	if duel.oath_used[0]:
		fav_node.draw_string(font, Vector2(x + Duel.MAX_FAVOR * gap + 12, baseline),
			"Oath spent", HORIZONTAL_ALIGNMENT_LEFT, -1, 24 if _landscape else 12, UI.TEXT_DIM)


const BOARD_THEMES := [
	[Color("1b2a24"), Color("2f4438")],   # Hearth (default)
	[Color("1a2230"), Color("2d3f57")],   # Frostwood
	[Color("2a1c22"), Color("4a2b33")],   # Ember Hall
	[Color("241f2e"), Color("3d3352")],   # Night Court
]

func _draw_table_felt() -> void:
	var r := Rect2(Vector2.ZERO, _table_box.size)
	# The complete rounded felt and engraved frame are built offline and scaled
	# as nine slices, so low-spec machines keep the shape without expensive AA.
	var felt_names := ["felt_green", "felt_blue", "felt_red", "felt_purple"]
	var selected: int = clampi(Profile.board_theme, 0, felt_names.size() - 1)
	_table_box.draw_style_box(UI.fantasy_style(felt_names[selected], 0, 0), r)
	# A subtle contained rune is decorative only and never extends past the felt.
	var c := r.size * Vector2(0.5, 0.48)
	var radius := minf(r.size.x, r.size.y) * 0.30
	for factor in [1.0, 0.78]:
		_table_box.draw_arc(c, radius * factor, 0, TAU, 48, Color(0.78, 0.72, 0.42, 0.12), 1.5, true)
	var mark := radius * 0.48
	var points := PackedVector2Array([c + Vector2(0, -mark), c + Vector2(mark, 0), c + Vector2(0, mark), c + Vector2(-mark, 0), c + Vector2(0, -mark)])
	_table_box.draw_polyline(points, Color(0.78, 0.72, 0.42, 0.12), 1.5, true)
	# corner sigils
	for sx in [0.0, 1.0]:
		for sy in [0.0, 1.0]:
			var p := Vector2(r.size.x * (0.06 + 0.88 * sx), r.size.y * (0.10 + 0.80 * sy))
			var sigil_rect := Rect2(p - Vector2(24, 24), Vector2(48, 48))
			if not UI.LOW_SPEC or not EffectAtlas.draw_sprite(_table_box, sigil_rect, EffectAtlas.SIGIL):
				_table_box.draw_arc(p, 22, 0, TAU, 26, Color(UI.GOLD.r, UI.GOLD.g, UI.GOLD.b, 0.07), 1.0, true)


# ---------------------------------------------------------------------------
# REFRESH
# ---------------------------------------------------------------------------
func _refresh_all() -> void:
	_refresh_bot_hand()
	var bot: Dictionary = T.FACTIONS[duel.bot_faction]
	var mine: Dictionary = T.FACTIONS[duel.player_faction]
	var camp: Dictionary = config.get("campaign", {})
	if camp.has("name"):
		_top_name.text = camp.get("name", bot.people)
		_top_meta.text = camp.get("title", "")
	else:
		_top_name.text = "%s · %s" % [bot.people, bot.name]
		_top_meta.text = bot.oath + " · " + T.MODE_INFO[duel.mode].name
		if duel.rule == C.RULE_QUINDICI:
			_top_meta.text = bot.oath + " · Fifteen Duel"

	UI.set_chip(_top_favor, "FAVOR %d" % duel.favor[1], Color("3a2f22") if duel.favor[1] > 0 else Color("2b2338"),
		UI.GOLD if duel.favor[1] > 0 else UI.TEXT_DIM)
	UI.set_chip(_top_scoopa, "SWEEPS %d" % duel.scopa_count[1], Color("2b2338"),
		UI.GOLD if duel.scopa_count[1] > 0 else UI.TEXT_DIM)

	_renown0.text = str(duel.renown[0])
	_renown1.text = str(duel.renown[1])
	_renown_bar.queue_redraw()

	UI.set_chip(_deck_chip, "DECK %d" % duel.deck.size(),
		Color("3a2f22") if duel.deck_low() else Color("2b2338"),
		UI.GOLD if duel.deck_low() else UI.TEXT_DIM)

	var goal := ""
	if duel.puzzle.size() > 0:
		var left := int(duel.puzzle.get("moves", 3)) - duel.turn_count
		_goal_chip.visible = true
		UI.set_chip(_goal_chip, "MOVES %d" % maxi(0, left), Color("3a2f22"), UI.GOLD)
	else:
		_goal_chip.visible = duel.mode == T.Mode.RANKED
		if duel.mode == T.Mode.RANKED:
			UI.set_chip(_goal_chip, "HAND %d/3" % (duel.hands_played + 1), Color("2b2338"), UI.GOLD)

	var prim0: int = duel.primiera_total(duel.captured[0])
	var prim1: int = duel.primiera_total(duel.captured[1])
	UI.set_chip(_score_chip, "P %d·%d" % [prim0, prim1], Color("2b2338"), UI.TEXT_DIM)
	_banner_meter.queue_redraw()

	# turn label
	if duel.hand_over:
		_turn_label.text = "Hand complete"
	elif duel.turn == 0:
		_turn_label.text = "▸ Your turn"
	else:
		_turn_label.text = "%s thinking…" % T.FACTIONS[duel.bot_faction].people
	_turn_label.add_theme_color_override("font_color", UI.GOLD if duel.turn == 0 else UI.TEXT_DIM)

	_refresh_hand()
	_refresh_table()
	_refresh_quests()
	_refresh_actions()
	if _favor_strip != null:
		_favor_strip.queue_redraw()
	_apply_duel_typography()


func _hand_card_width(available: float) -> float:
	if _layout_mode == "full":
		var count := maxi(duel.hands[0].size(), 3)
		return clampf((available - 10.0 * float(count - 1) - 12.0) / float(count), 48.0, 150.0)
	return clampf(available * 0.215, 112.0, 150.0)


func _refresh_hand() -> void:
	var hand: Array = duel.hands[0].duplicate()
	hand.sort_custom(C.sort_by_faction)
	var my_turn := duel.is_my_turn(0) and not _busy
	var hw: float = _hand_card_width(_hand_box.size.x)
	var cards := _retain_cards(_hand_row, hand)
	for i in range(hand.size()):
		var card: int = hand[i]
		var cv: CardView = cards.get(card)
		if cv == null:
			cv = CardView.new()
			cv.setup(card, true, int(hw), int(hw * CardView.ASPECT))
			cv.size_flags_vertical = Control.SIZE_SHRINK_CENTER
			cv.pressed.connect(_on_hand_card.bind(card))
			_hand_row.add_child(cv)
			cv.enter_anim()
		cv.set_card_size(Vector2(int(hw), int(hw * CardView.ASPECT)))
		cv.back_style = Profile.card_back
		cv.set_playable(my_turn and not duel.groups_for_player(0, card).is_empty())
		cv.dim = not my_turn
		cv.set_selected(card == _selection)
		_hand_row.move_child(cv, i)


func _retain_cards(parent: Control, ids: Array) -> Dictionary:
	var retained := {}
	for child in parent.get_children():
		if child is CardView and ids.has(child.card_id):
			retained[child.card_id] = child
		else:
			_remove_now(child)
	return retained


## Work out where `n` table cards go inside `avail`, shrinking them as needed and
## wrapping onto extra rows. Cards keep their aspect, grow no bigger than the old
## fixed maximum, and never leave the felt.
##
## Returns {cw, ch, cols, rows, at: Array[Vector2]} where `at` holds each card's
## top-left corner, the whole block centred.
##
## A container cannot do this: an HBoxContainer keeps every card on one row at its
## minimum width and lets the overflow hang off both sides of the table.
func _table_layout(n: int, avail: Vector2) -> Dictionary:
	var out := {"cw": 0.0, "ch": 0.0, "cols": 0, "rows": 0, "at": []}
	if n <= 0:
		return out
	const GAP := 6.0
	var max_ch := 245.0 if _layout_mode == "full" else 208.0
	const MIN_CW := 34.0    # small, but still a readable card
	var w: float = maxf(avail.x, 80.0)
	var h: float = maxf(avail.y, 80.0)

	# Try every column count, keep whichever yields the largest card that still
	# fits both ways: more columns = wider but shorter, fewer = taller.
	var best_cw := 0.0
	var best_cols := 1
	for cols in range(1, n + 1):
		var rows: int = int(ceil(float(n) / float(cols)))
		var cw_by_width: float = (w - GAP * float(cols - 1)) / float(cols)
		var ch_by_height: float = (h - GAP * float(rows - 1)) / float(rows)
		var cw_by_height: float = ch_by_height / CardView.ASPECT
		var cw: float = minf(minf(cw_by_width, cw_by_height), max_ch / CardView.ASPECT)
		# In a roomy landscape, equal-size cards should use the width rather
		# than unnecessarily stacking into a tall portrait-shaped block.
		if cw > best_cw + 0.01 or (_layout_mode == "full" and absf(cw - best_cw) <= 0.01 and cols > best_cols):
			best_cw = cw
			best_cols = cols
	best_cw = maxf(best_cw, MIN_CW)
	var ch: float = best_cw * CardView.ASPECT
	var rows_n: int = int(ceil(float(n) / float(best_cols)))

	var total_w: float = best_cw * float(best_cols) + GAP * float(best_cols - 1)
	var total_h: float = ch * float(rows_n) + GAP * float(rows_n - 1)
	var y0: float = (h - total_h) * 0.5
	var at: Array = []
	for i in range(n):
		var col: int = i % best_cols
		var row: int = i / best_cols
		# centre a short final row instead of left-aligning it
		var in_row: int = mini(best_cols, n - row * best_cols)
		var row_w: float = best_cw * float(in_row) + GAP * float(in_row - 1)
		at.append(Vector2((w - row_w) * 0.5 + float(col) * (best_cw + GAP),
			y0 + float(row) * (ch + GAP)))
	return {"cw": best_cw, "ch": ch, "cols": best_cols, "rows": rows_n, "at": at}


func _refresh_table() -> void:
	var vis: Array = duel.visible_table(0).duplicate()
	vis.sort_custom(C.sort_by_rank)
	var cards := _retain_cards(_table_grid, vis)
	var highlight := {}
	var groups: Array = duel.groups_for_player(0, _selection) if _selection >= 0 else []
	for group in groups:
		for card in group:
			highlight[card] = true

	var n := vis.size()
	# Fit the cards to the felt rather than letting them overflow it: shrink to fit
	# and wrap onto extra rows as the table gets crowded.
	var layout := _table_layout(n, _table_grid.size)
	var cw: float = layout.cw
	var ch: float = layout.ch
	var at: Array = layout.at
	for i in range(n):
		var c: int = vis[i]
		var cv: CardView = cards.get(c)
		if cv == null:
			cv = CardView.new()
			cv.setup(c, true, int(cw), int(ch))
			cv.pressed.connect(_on_table_card.bind(c))
			_table_grid.add_child(cv)
			cv.enter_anim(0.05 * i)
		cv.set_card_size(Vector2(int(cw), int(ch)))
		cv.capturable = highlight.has(c)
		cv.queue_redraw()
		cv.position = at[i]
		_table_grid.move_child(cv, i)

	if n == 0:
		_table_sub.text = "the table is clear"
	elif duel.veiled >= 0:
		_table_sub.text = "%d on the table · one veiled by the Warden" % n
	else:
		_table_sub.text = ""

	if _selection >= 0:
		if groups.size() > 1:
			_table_sub.text = "Tap a glowing card to choose a capture"
		elif groups.size() == 1:
			_table_sub.text = "Tap your card again or a glowing card to capture" if Profile.confirm_card_play else "Tap the glowing card to capture"
		elif duel.blocked_by_quindici(_selection):
			_table_sub.text = "Fifteen Duel: matching a value never captures — only cards totalling 15"
		else:
			_table_sub.text = "No capture. Tap your card again to play." if Profile.confirm_card_play else "No capture — this card will lie on the table"


func _refresh_quests() -> void:
	for c in _quest_list.get_children():
		c.get_parent().remove_child(c)
		c.queue_free()
	if duel.quests.is_empty():
		_quest_list.add_child(UI.label("Classic rules · no quests in puzzles", 15, UI.TEXT_DIM, false, true))
		return
	for i in range(duel.quests.size()):
		var q: Dictionary = duel.quests[i]
		var done: bool = duel.quest_done[i]
		var h := HBoxContainer.new()
		h.add_theme_constant_override("separation", 8)
		var mark := UI.label("✦" if done else "◇", 15, UI.GOLD if done else Color("5a4f70"))
		h.add_child(mark)
		var txt := UI.label(q.name, 16, UI.TEXT, true, _landscape)
		txt.add_theme_font_size_override("font_size", 16)
		if done:
			txt.add_theme_color_override("font_color", UI.GOOD)
		h.add_child(txt)
		var d := UI.label(q.desc if _landscape else "· " + q.desc, 14, UI.TEXT_DIM, false, _landscape)
		d.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		d.clip_text = not _landscape
		d.text_overrun_behavior = TextServer.OVERRUN_NO_TRIMMING if _landscape else TextServer.OVERRUN_TRIM_ELLIPSIS
		h.add_child(UI.label("+%d" % q.reward, 15, UI.GOOD if done else UI.GOLD))
		if _landscape:
			var quest := VBoxContainer.new()
			quest.add_theme_constant_override("separation", 2)
			quest.add_child(h)
			quest.add_child(d)
			_quest_list.add_child(quest)
		else:
			h.add_child(d)
			h.move_child(d, 2)
			_quest_list.add_child(h)


func _refresh_actions() -> void:
	var mine := duel.is_my_turn(0) and not _busy
	var can_oath: bool = mine and duel.can_use_oath(0)
	var info: Dictionary = T.FACTIONS[duel.player_faction]
	if not duel.oaths_enabled:
		_btn_oath.text = "Oaths off · Classic"
		_btn_oath.disabled = true
	elif duel.oath_used[0]:
		_btn_oath.text = "%s · spent" % info.oath
		_btn_oath.disabled = true
	elif duel.player_faction == T.HORDE and duel.deck.is_empty():
		_btn_oath.text = "Raid · deck empty"
		_btn_oath.disabled = true
	elif duel.player_faction == T.HORDE and duel.visible_table(0).is_empty():
		_btn_oath.text = "Raid · no table card"
		_btn_oath.disabled = true
	else:
		_btn_oath.text = "%s  ·  %d Favor" % [info.oath, duel.favor[0]]
		_btn_oath.disabled = not can_oath
	_btn_hint.disabled = not mine or _hinted_once
	_btn_pile.disabled = duel.hand_over


# ---------------------------------------------------------------------------
# INPUT
# ---------------------------------------------------------------------------
func _on_hand_card(c: int) -> void:
	if not duel.is_my_turn(0) or _busy:
		return
	if not Profile.confirm_card_play:
		_selection = c
		_confirm_play(c)
		return
	if _selection == c:
		# second tap on the same card confirms the play
		_confirm_play(c)
		return
	_selection = c
	Sfx.play("select", -14.0)
	_refresh_table()
	_refresh_hand()


func _on_table_card(c: int) -> void:
	if _selection < 0 or _busy or not duel.is_my_turn(0):
		return
	var groups: Array = duel.groups_for_player(0, _selection)
	var matches: Array[int] = []
	for i in range(groups.size()):
		if groups[i].has(c):
			matches.append(i)
	if matches.is_empty():
		Sfx.play("deny", -16.0)
	elif matches.size() == 1:
		_play_card(_selection, matches[0])
	else:
		_show_capture_options(c, groups, matches)


func _show_capture_options(table_card: int, groups: Array, matches: Array[int]) -> void:
	var card := _selection
	var prompt := "Choose the cards to capture." if table_card < 0 else "Each option includes %s." % C.short(table_card)
	var panel := _oath_sheet("CHOOSE A CAPTURE", prompt)
	var body: VBoxContainer = panel.get_meta("body")
	for index in matches:
		var names := PackedStringArray()
		for captured_card in groups[index]:
			names.append(C.short(captured_card))
		var option := UI.button(" + ".join(names), "secondary", 15)
		option.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		option.pressed.connect(func():
			_close_overlay()
			if duel.is_my_turn(0) and _selection == card:
				_play_card(card, index))
		body.add_child(option)


func _confirm_play(c: int) -> void:
	if _busy or not duel.is_my_turn(0) or not duel.hands[0].has(c):
		return
	var groups: Array = duel.groups_for_player(0, c)
	if groups.size() > 1:
		_selection = c
		_refresh_table()
		_refresh_hand()
		var choices: Array[int] = []
		for i in range(groups.size()):
			choices.append(i)
		_show_capture_options(-1, groups, choices)
	else:
		_play_card(c, 0)


func _play_card(card: int, group_idx: int) -> void:
	if _busy or not duel.is_my_turn(0) or not duel.hands[0].has(card):
		return
	_busy = true
	_close_overlay()
	_selection = -1
	_turn_time = TURN_SECONDS

	var groups: Array = duel.groups_for_player(0, card)
	var target_center := _table_center()
	var from_center := _hand_card_center(card)
	if from_center == Vector2.ZERO:
		from_center = _hand_box.global_position - global_position + _hand_box.size * Vector2(0.5, 0.6)

	# pre-compute what will be captured so the animation can fly the cards, and so
	# the match can be shown on the real table cards before they leave it
	var captured: Array = []
	if groups.size() > 0:
		captured = groups[clampi(group_idx, 0, groups.size() - 1)] + [card]
	var matched: Array = captured.duplicate()
	matched.erase(card)

	if anim_on("all"):
		# 1. the played card travels to the playfield, spinning
		Sfx.play("tap", -14.0)
		var landing := target_center if matched.is_empty() else _card_slot_center(matched[0])
		var ch: float = clampf(maxf(_table_box.size.y, 260.0) * 0.40, 148.0, 208.0)
		var cw: float = ch / 1.404
		_fly_card_in(card, from_center, landing, int(cw), int(ch))
		await get_tree().create_timer(_beat(0.26, 0.10), false).timeout
		# 2. whatever it matched lights up, so the pairing is legible
		if not matched.is_empty() and anim_on("match"):
			_mark_match(matched)
			await get_tree().create_timer(_beat(0.34, 0.08), false).timeout

	_commit_play(0, card, group_idx)
	_refresh_all()

	# fly the cards into the pile
	if not captured.is_empty():
		Sfx.play("capture", -8.0)
		_fly_to_pile(captured, from_center)
		FX.burst(self, target_center, T.FACTIONS[duel.player_faction].color, 16, 200)
	else:
		Sfx.play("deal", -12.0)

	# a scopa holds the beat so the celebration lands before the next turn
	var hold: float = _beat(1.9, 0.9) if _scopa_held else _beat(0.62, 0.24)
	await get_tree().create_timer(hold, false).timeout
	_scopa_held = false
	_busy = false
	_refresh_all()
	_after_turn()


## Where a table card currently sits, so a played card can land beside it.
func _card_slot_center(c: int) -> Vector2:
	var node := _table_card_node(c)
	if node != null:
		return node.global_position - global_position + node.size * 0.5
	return _table_center()


func _commit_play(who: int, card: int, group_index: int) -> void:
	duel.play(who, card, group_index)
	_save_state()
	_handle_events()


func _save_state() -> void:
	Profile.store_duel({
		"state": duel.to_dict(),
	})


func _after_turn() -> void:
	if duel.hand_over:
		_show_hand_summary()
		return
	if duel.turn == 1:
		_run_bot()


func _run_bot() -> void:
	_ai_token += 1
	var token := _ai_token
	_busy = true
	_refresh_all()
	await get_tree().create_timer(_beat(0.45, 0.3), false).timeout
	if token != _ai_token or duel.hand_over:
		_busy = false
		return

	# maybe spend Favor first
	var oath_action: Dictionary = DuelAI.choose_oath(duel, 1)
	if not oath_action.is_empty():
		match oath_action.kind:
			"delvedeep":
				_apply_bot_oath_delve(oath_action.bury)
			"foresight":
				duel.use_foresight(1, oath_action.order)
			"raid":
				duel.use_raid(1, oath_action.card)
			"diplomacy":
				duel.use_diplomacy(1, oath_action.hand, oath_action.table)
		_handle_events()
		_refresh_all()
		await get_tree().create_timer(0.6, false).timeout
		if token != _ai_token:
			return

	var move: Dictionary = DuelAI.choose_move(duel, 1)
	if move.is_empty():
		_busy = false
		return
	var card: int = move.card
	var gi: int = move.group
	var groups: Array = duel.groups_for_player(1, card)
	var captured: Array = []
	if not groups.is_empty():
		captured = groups[clampi(gi, 0, groups.size() - 1)] + [card]
	var matched: Array = captured.duplicate()
	matched.erase(card)

	if anim_on("all"):
		# the opponent's card visibly leaves their hand and travels down
		var ch: float = clampf(maxf(_table_box.size.y, 260.0) * 0.40, 148.0, 208.0)
		var cw: float = ch / 1.404
		var origin: Vector2 = _bot_row.global_position - global_position + _bot_row.size * Vector2(0.5, 0.5)
		if _bot_row.get_child_count() > 0:
			var first := _bot_row.get_child(0) as Control
			if first != null:
				origin = first.global_position - global_position + first.size * 0.5
		var landing := _table_center() if matched.is_empty() else _card_slot_center(matched[0])
		# How small their hand card is drawn, relative to a playfield card, so the
		# card grows from that size to full as it flies and spins.
		var hand_scale := BOT_HAND_SCALE
		var backs := _bot_row.get_child_count()
		if backs > 0:
			var back_node := _bot_row.get_child(backs - 1) as Control
			if back_node != null and cw > 0.0:
				hand_scale = clampf(back_node.size.x / cw, 0.2, 1.0)
		_fly_card_in(card, origin, landing, int(cw), int(ch), 0.0, hand_scale)
		# their hand thins as the card leaves it
		if backs > 0:
			var leaving := _bot_row.get_child(backs - 1)
			if leaving != null:
				leaving.queue_free()
		await get_tree().create_timer(_beat(0.30, 0.10), false).timeout
		if not matched.is_empty() and anim_on("match"):
			_mark_match(matched)
			await get_tree().create_timer(_beat(0.32, 0.08), false).timeout
		if token != _ai_token:
			_busy = false
			return

	_commit_play(1, card, gi)
	if not captured.is_empty():
		Sfx.play("capture", -12.0, 0.92)
		FX.burst(self, _table_center(), T.FACTIONS[duel.bot_faction].color, 12, 160)
	else:
		Sfx.play("deal", -16.0, 0.9)
	_refresh_all()
	await get_tree().create_timer(_beat(0.36, 0.22), false).timeout
	_busy = false
	if duel.hand_over:
		_show_hand_summary()
		return
	_refresh_all()


func _apply_bot_oath_delve(bury: int) -> void:
	duel.use_deep_delve(1, bury)


# ---------------------------------------------------------------------------
# OATH UI (human)
# ---------------------------------------------------------------------------
func _on_oath_pressed() -> void:
	if _busy or not duel.can_use_oath(0):
		Sfx.play("deny", -14.0)
		return
	Sfx.play("tap")
	var f: int = duel.player_faction
	match f:
		T.FORGE:
			_oath_deep_delve()
		T.GROVE:
			_oath_foresight()
		T.HORDE:
			_oath_raid()
		T.CROWN:
			_oath_diplomacy()


# --- the contract scripts/ui/oath_pickers.gd calls back on -------------------
## The pickers are static and take this screen as one object rather than six
## callbacks; these wrappers keep that surface honest and greppable.
func open_sheet(title: String, sub: String) -> PanelContainer:
	return _oath_sheet(title, sub)


func toast(title: String, sub: String) -> void:
	_toast(title, sub)


## Commit an Oath: close the sheet, then run the normal post-play path.
func finish() -> void:
	_finish_player_oath()


func close() -> void:
	_close_overlay()


func refresh() -> void:
	_refresh_all()


## The four Oaths live in scripts/ui/oath_pickers.gd. These keep their names
## because the screen's own button handler and the audit both call them, and a
## one-line delegation reads better than six call sites learning a new path.
func _oath_deep_delve() -> void:
	OathPickers.deep_delve(self)


func _oath_foresight() -> void:
	OathPickers.foresight(self)


func _oath_raid() -> void:
	OathPickers.raid_picker(self)


func _oath_diplomacy() -> void:
	OathPickers.diplomacy(self)



# EVENTS → JUICE
# ---------------------------------------------------------------------------
func _finish_player_oath() -> void:
	_close_overlay()
	if not duel.hands[0].has(_selection):
		_selection = -1
	_handle_events()
	_save_state()
	_refresh_all()


func _handle_events() -> void:
	for ev in duel.drain_events():
		match ev.get("t", ""):
			"scopa":
				var who: int = ev.who
				_scopa_held = true
				_scopa_celebration(who, ev.get("glory", 1))
			"favor":
				if ev.who == 0:
					Sfx.play("favor", -14.0)
			"oath":
				if ev.who == 1:
					Sfx.play("oath", -16.0, 0.85)
					_toast("%s uses %s" % [T.FACTIONS[duel.bot_faction].people, ev.get("oath", "Oath")], "")
				else:
					Sfx.play("oath", -12.0)
			"quest":
				var q := T.quest_by_key(ev.quest)
				Sfx.play("favor", -8.0)
				var qname: String = q.get("name", ev.quest)
				_toast("Quest complete · %s" % qname, "+%d Renown" % ev.reward, UI.GOOD)
			"reveal":
				_toast("The veil lifts", "A hidden table card is revealed: %s." % C.label(ev.card))
			"match_end":
				pass




func _scopa_celebration(who: int, glory: int) -> void:
	Sfx.play("scopa", -4.0)
	if who == 0:
		_haptic(70)
	FX.flash(self, Color(UI.GOLD.r, UI.GOLD.g, UI.GOLD.b, 0.30), 0.5)
	FX.shake(self, 12.0, 0.45)
	var center := _table_center()
	FX.burst(self, center, UI.GOLD, 40, 340)
	FX.burst(self, center, T.FACTIONS[who].color if who == 0 else T.FACTIONS[duel.bot_faction].color, 26, 260)
	var big := UI.label("SWEEP!", 54, UI.GOLD, true)
	big.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	if not UI.LOW_SPEC:
		big.add_theme_color_override("font_shadow_color", Color(0, 0, 0, 0.8))
	big.add_theme_constant_override("shadow_offset_y", 4)
	big.z_index = 95
	big.modulate.a = 0.0
	add_child(big)
	big.size = Vector2(size.x, 90)
	big.position = Vector2(0, center.y - 130)
	big.pivot_offset = big.size * 0.5
	big.scale = Vector2(0.5, 0.5)
	var t := create_tween()
	t.set_parallel(true)
	t.tween_property(big, "modulate:a", 1.0, 0.12)
	t.tween_property(big, "scale", Vector2(1.0, 1.0), 0.35).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	t.chain().tween_property(big, "modulate:a", 0.0, 0.4).set_delay(0.75)
	t.chain().tween_callback(big.queue_free)
	var sub := "+%d Glory · +1 Favor" % glory
	FX.float_text(self, center + Vector2(0, 30), sub, UI.PARCHMENT, 22)
	if who == 1:
		_toast("%s sweeps the table!" % T.FACTIONS[duel.bot_faction].people, "+%d Glory" % glory)


# ---------------------------------------------------------------------------
# CARD ANIMATION
# Every one of these honours the settings, and all of them are purely cosmetic:
# with animations off the same moves resolve on the same frames, just instantly.
# ---------------------------------------------------------------------------
func anim_on(kind: String = "all") -> bool:
	if not Profile.anim_enabled:
		return false
	match kind:
		"spin":
			return Profile.anim_spin
		"slow":
			return Profile.anim_slow
		"match":
			return Profile.anim_match
	return true


## Seconds to wait for a beat that is only there for the animation's sake.
## Collapses to ~0 when slow-motion is off, so the game never feels padded.
func _beat(long_s: float, short_s: float = 0.0) -> float:
	return long_s if anim_on("slow") else short_s


## Fly a card from `from` onto the playfield. With spin enabled it turns a
## full 360 degrees about its centre, face up throughout, without a shader.
func _fly_card_in(c: int, from: Vector2, to: Vector2, w: int, h: int, delay: float = 0.0,
		start_scale: float = 1.0) -> void:
	var cv := CardView.new()
	cv.setup(c, true, w, h)
	cv.mouse_filter = Control.MOUSE_FILTER_IGNORE
	cv.z_index = 80
	add_child(cv)
	var spin: bool = anim_on("spin")
	var dur: float = 0.46 if spin else 0.26
	if not anim_on("all"):
		cv.queue_free()
		return
	# Scale about the card's centre, so a card that starts small (an opponent's
	# card, drawn small in their hand) grows out of its own middle while it travels
	# and turns, and arrives at exactly playfield size.
	cv.pivot_offset = Vector2(w, h) * 0.5
	var from_scale := maxf(start_scale, 0.05)
	cv.scale = Vector2(from_scale, from_scale)
	cv.position = from - Vector2(w, h) * 0.5

	var t := create_tween()
	t.set_parallel(true)
	t.tween_property(cv, "position", to - Vector2(w, h) * 0.5, dur).set_delay(delay) \
		.set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)
	if not is_equal_approx(from_scale, 1.0):
		t.tween_property(cv, "scale", Vector2.ONE, dur).set_delay(delay) \
			.set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)
	if spin:
		# 0..1 across the flight mapped to exactly one full turn about the card's
		# centre. Face up the whole way; the art does not flip.
		t.tween_method(func(v: float) -> void:
			cv.spin = v * TAU
			cv.queue_redraw(), 0.0, 1.0, dur).set_delay(delay)
	t.chain().tween_callback(cv.queue_free)


## Flash a ring on every card involved in a capture, so it is obvious what was
## matched before the cards leave the table.
func _mark_match(cards: Array) -> void:
	if not anim_on("match"):
		return
	CardAnim.mark_match(self, _table_grid, cards, global_position)


func _table_card_node(id: int) -> Control:
	return CardAnim.table_card_node(_table_grid, id)


func _hand_card_node(id: int) -> Control:
	return CardAnim.hand_card_node(_hand_row, id)


func _fly_to_pile(cards: Array, from: Vector2) -> void:
	CardAnim.fly_to_pile(self, cards, from, _pile_chip_center())


func _haptic(ms: int) -> void:
	if OS.has_feature("mobile"):
		Input.vibrate_handheld(ms)


func _table_center() -> Vector2:
	return _table_box.global_position - global_position + _table_box.size * Vector2(0.5, 0.5)


func _hand_card_center(card: int) -> Vector2:
	for c in _hand_row.get_children():
		if c is CardView and c.card_id == card:
			return c.global_position - global_position + c.size * 0.5
	return _hand_box.global_position - global_position + _hand_box.size * 0.5


func _pile_chip_center() -> Vector2:
	return _score_chip.global_position - global_position + _score_chip.size * 0.5


func _toast(title: String, sub: String, col: Color = UI.GOLD) -> void:
	var p := PanelContainer.new()
	p.add_theme_stylebox_override("panel", UI.panel(Color(UI.PANEL.r, UI.PANEL.g, UI.PANEL.b, 0.95), 14, col, 2))
	p.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var v := VBoxContainer.new()
	v.add_theme_constant_override("separation", 0)
	p.add_child(v)
	var l := UI.label(title, 18, col, true)
	l.add_theme_font_size_override("font_size", 28 if _landscape else 17)
	if _landscape:
		l.add_theme_font_override("font", ThemeDB.fallback_font)
	l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	v.add_child(l)
	if sub != "":
		var s := UI.label(sub, 26 if _landscape else 14, UI.TEXT_DIM)
		if _landscape:
			s.add_theme_font_override("font", ThemeDB.fallback_font)
		s.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		s.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		v.add_child(s)
	p.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	if _landscape:
		p.custom_minimum_size.x = minf(640, size.x * 0.5)
	_toast_box.add_child(p)
	p.modulate.a = 0.0
	var t := create_tween()
	t.set_parallel(true)
	t.tween_property(p, "modulate:a", 1.0, 0.16)
	t.chain().tween_property(p, "modulate:a", 0.0, 0.4).set_delay(1.9)
	t.chain().tween_callback(p.queue_free)
	# Trim the oldest toasts. This was a `while` containing a `break`, so it only
	# ever retired one panel — and queue_free() is deferred, so the freed child was
	# still counted by get_child_count() on the next pass. Every toast is a panel
	# carrying its own tween, so the box grew for the whole duel. _remove_now()
	# detaches first (which is what actually drops the count) and frees after.
	while _toast_box.get_child_count() > MAX_TOASTS:
		_remove_now(_toast_box.get_child(0))


# ---------------------------------------------------------------------------
# HINTS
# ---------------------------------------------------------------------------
func _on_hint() -> void:
	if _busy or not duel.is_my_turn(0):
		return
	_hinted_once = true
	var best := DuelAI.choose_move(duel, 0)
	if best.is_empty():
		return
	var msg := "Play %s" % C.label(best.card)
	if best.group >= 0:
		var groups: Array = duel.groups_for_player(0, best.card)
		if not groups.is_empty():
			var names: Array = []
			for c in groups[clampi(best.group, 0, groups.size() - 1)]:
				names.append(C.short(c))
			msg += " and capture " + ", ".join(names)
	else:
		msg += " — nothing to take, so keep it low."
	_toast("Hint", msg)
	# highlight it
	for cv in _hand_row.get_children():
		if cv is CardView and cv.card_id == best.card:
			cv.set_selected(true)
			break
	_refresh_actions()


func _show_rules(paused: bool = false) -> void:
	var panel := _oath_sheet("RULES & SCORING", "")
	var body: VBoxContainer = panel.get_meta("body")
	var capture_line := "Play a card whose rank matches a table card, or whose rank equals the sum of several table cards. A 10 can only take a 10."
	if duel.rule == C.RULE_QUINDICI:
		capture_line = "Fifteen Duel: your card plus the cards you take must total exactly 15, and a card can never take another card of the same value. A 10 can only be taken by a 5."
	for line in [
		["Capture", capture_line],
		["Sweep", "Clear the table with a capture to score a sweep. The final capture of a hand is not a sweep."],
		["Final take", "When the deck runs out, whoever captured last takes the remaining table cards."],
		["Loot", "1 Renown for the most captured cards."],
		["Treasury", "1 Renown for the most Forge cards."],
		["Runestone", "1 Renown for whoever holds the 7 of Forge."],
		["Banner", "1 Renown for the best Banner total: your best card in each faction (7=21, 6=18, Ace=16, faces=10)."],
		["Glory", "1 Renown per sweep."],
		["Favor", "You earn 1 Favor for a sweep or for capturing any 7. Spend 1 to use your faction Oath, once per hand."],
	]:
		var h := HBoxContainer.new()
		h.add_theme_constant_override("separation", 8)
		body.add_child(h)
		var a := UI.label(line[0], 16, UI.GOLD, true)
		a.custom_minimum_size = Vector2(84, 0)
		h.add_child(a)
		var b := UI.label(line[1], 15, UI.TEXT)
		b.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		b.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		h.add_child(b)

	if paused:
		_pause_for_menu(panel)


func _show_pile() -> void:
	Sfx.play("tap")
	var f := [0, 1]
	var panel := _oath_sheet("CAPTURED PILES", "Loot, Treasury, Runestone and Banner are read from these piles.")
	var body: VBoxContainer = panel.get_meta("body")
	for who in f:
		var title := "You · %s" % T.FACTIONS[duel.player_faction].people if who == 0 else "%s · %s" % [T.FACTIONS[duel.bot_faction].people, T.FACTIONS[duel.bot_faction].name]
		var head := VBoxContainer.new()
		head.add_theme_constant_override("separation", 8)
		body.add_child(head)
		head.add_child(UI.label(title, 18, UI.GOLD, true, true))
		head.add_child(UI.label("%d cards · Forge %d · Banner %d" % [
			duel.captured[who].size(),
			T.count_faction(duel.captured[who], T.FORGE),
			duel.primiera_total(duel.captured[who])], 14, UI.TEXT_DIM, false, true))
		var wrap := HFlowContainer.new()
		wrap.add_theme_constant_override("h_separation", 5)
		wrap.add_theme_constant_override("v_separation", 5)
		body.add_child(wrap)
		var sorted: Array = duel.captured[who].duplicate()
		sorted.sort_custom(C.sort_by_faction)
		for c in sorted:
			var mini := CardView.new()
			mini.setup(c, true, 46, 64)
			mini.mouse_filter = Control.MOUSE_FILTER_IGNORE
			wrap.add_child(mini)
		body.add_child(UI.spacer(6))




# ---------------------------------------------------------------------------
# OVERLAY / SHEETS
# ---------------------------------------------------------------------------
func _oath_sheet(title: String, sub: String, dismissible: bool = true) -> PanelContainer:
	_close_overlay()
	var dim := ColorRect.new()
	dim.color = Color(0, 0, 0, 0.72)
	dim.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	dim.mouse_filter = Control.MOUSE_FILTER_STOP
	dim.z_index = 100
	if dismissible:
		dim.gui_input.connect(func(e):
			if e is InputEventMouseButton and e.button_index == MOUSE_BUTTON_LEFT and e.pressed:
				_close_overlay())
	add_child(dim)
	_overlay = dim
	# A sheet that cannot be dismissed by tapping the dimmer (the results screen)
	# must also refuse the back gesture, or back would throw the hand summary away.
	_overlay_blocks_back = not dismissible

	var p := PanelContainer.new()
	p.add_theme_stylebox_override("panel", UI.panel(UI.BG2, 20, UI.GOLD, 2))
	p.z_index = 101
	add_child(p)
	p.set_meta("dialog_width", 900.0)
	p.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	p.anchor_left = 0.5
	p.anchor_right = 0.5
	p.anchor_top = 0.18
	p.anchor_bottom = 0.82
	p.offset_left = 0
	p.offset_right = 0
	p.offset_top = 0
	p.offset_bottom = 0
	p.grow_horizontal = Control.GROW_DIRECTION_BOTH
	p.grow_vertical = Control.GROW_DIRECTION_BOTH

	var sc := ScrollContainer.new()
	sc.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	sc.vertical_scroll_mode = ScrollContainer.SCROLL_MODE_SHOW_NEVER
	p.add_child(sc)
	var body := VBoxContainer.new()
	body.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	body.add_theme_constant_override("separation", 10)
	sc.add_child(body)

	var t := UI.label(title, 15, UI.GOLD)
	body.add_child(t)
	if sub != "":
		var s := UI.label(sub, 17, UI.TEXT)
		s.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		body.add_child(s)
	if dismissible:
		var close := UI.button("Close", "ghost", 16)
		close.pressed.connect(_close_overlay)
		body.add_child(close)
	p.set_meta("body", body)
	body.minimum_size_changed.connect(_layout_game_dialogs, CONNECT_DEFERRED)
	_layout_game_dialogs.call_deferred()
	return p



func _layout_game_dialogs() -> void:
	for panel in get_children():
		if not (panel is PanelContainer) or panel.z_index != 101 or not panel.has_meta("body"):
			continue
		if panel.has_meta("settings_grid"):
			SettingsPanel.layout(panel, size, _landscape, 1040.0)
			continue
		var width := minf(size.x * 0.92, float(panel.get_meta("dialog_width", 900.0)))
		panel.anchor_left = 0.5
		panel.anchor_right = 0.5
		panel.offset_left = -width * 0.5
		panel.offset_right = width * 0.5
		var controls: Array[Node] = [panel]
		while not controls.is_empty():
			var control := controls.pop_back() as Node
			controls.append_array(control.get_children())
			if control is Label or control is Button:
				if not control.has_meta("dialog_font_size"):
					control.set_meta("dialog_font_size", control.get_theme_font_size("font_size"))
				var original: int = control.get_meta("dialog_font_size")
				control.add_theme_font_override("font", ThemeDB.fallback_font)
				control.add_theme_font_size_override("font_size", maxi(26, original) if _landscape else maxi(18, original))
				if control is Label:
					control.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
					control.size_flags_horizontal = Control.SIZE_EXPAND_FILL
			if control is Button:
				control.custom_minimum_size.y = maxf(control.custom_minimum_size.y, 80 if _landscape else 48)


func _pause_for_menu(panel: PanelContainer) -> void:
	_pause_before_menu = get_tree().paused
	_menu_paused = true
	panel.process_mode = Node.PROCESS_MODE_ALWAYS
	_overlay.process_mode = Node.PROCESS_MODE_ALWAYS
	get_tree().paused = true


func _exit_tree() -> void:
	if _menu_paused:
		get_tree().paused = _pause_before_menu


func _close_overlay() -> void:
	if _menu_paused:
		get_tree().paused = _pause_before_menu
		_menu_paused = false
	# Remove from the tree FIRST, then free. queue_free() alone is deferred, so a
	# closing oath/score sheet left its full-screen dim panel (MOUSE_FILTER_STOP,
	# z_index 100) in front of the table for the rest of the frame - and it sits
	# above the cards (z 0). Any tap in that window hit the dim instead of a card:
	# taps appeared to do nothing, a hand card could not be played while the very
	# next tap (a fraction later) worked, and the dim's "tap to dismiss" fired and
	# re-shuffled the table. That is exactly the "I had a 4, there was a 4 on the
	# table, it would not let me play it" report.
	if _overlay != null and is_instance_valid(_overlay):
		_remove_now(_overlay)
	_overlay = null
	_overlay_blocks_back = false
	for c in get_children():
		if c is PanelContainer and c.z_index == 101:
			_remove_now(c)


## Detach a node immediately so it stops receiving input, then delete it at the
## end of the frame (free() during a container callback throws "locked object").
func _remove_now(n: Node) -> void:
	if n == null or not is_instance_valid(n):
		return
	var parent := n.get_parent()
	if parent != null:
		parent.remove_child(n)
	n.queue_free()


# ---------------------------------------------------------------------------
# HAND SUMMARY / MATCH END
# ---------------------------------------------------------------------------
func _show_hand_summary() -> void:
	_busy = true
	await get_tree().create_timer(0.5, false).timeout
	var score: Dictionary = duel.score_hand()
	var final := duel.match_over
	var panel := _oath_sheet("RESULTS", "", false)
	panel.set_meta("dialog_width", 1100.0)
	panel.anchor_top = 0.06
	panel.anchor_bottom = 0.94
	var body: VBoxContainer = panel.get_meta("body")
	var scroll := body.get_parent() as ScrollContainer
	panel.remove_child(scroll)
	var outer := VBoxContainer.new()
	outer.add_theme_constant_override("separation", 12)
	panel.add_child(outer)
	outer.add_child(scroll)
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	var puzzle_result := -1
	if not duel.puzzle.is_empty():
		puzzle_result = int(_puzzle_verdict(body))
	else:
		var winner := duel.winner()
		var headline := "HAND COMPLETE"
		var color := UI.GOLD
		if final:
			headline = "YOU WIN!" if winner == 0 else ("OPPONENT WINS" if winner == 1 else "MATCH DRAW")
			color = UI.GOOD if winner == 0 else (UI.BAD if winner == 1 else UI.GOLD)
		var result := UI.label(headline, 40 if _landscape else 32, color, true, true)
		result.add_theme_font_override("font", ThemeDB.fallback_font)
		result.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		body.add_child(result)
		var total := UI.label("You %d  —  Opponent %d" % [duel.renown[0], duel.renown[1]], 34 if _landscape else 28, UI.TEXT, false, true)
		total.add_theme_font_override("font", ThemeDB.fallback_font)
		total.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		body.add_child(total)
		var quest_bonus := 0
		for i in range(duel.quests.size()):
			if duel.quest_done[i]:
				quest_bonus += int(duel.quests[i].reward)
		if quest_bonus > 0:
			var bonus := UI.label("Your quest bonuses add +%d to the match score." % quest_bonus, 24 if _landscape else 20, UI.GOOD, false, true)
			bonus.add_theme_font_override("font", ThemeDB.fallback_font)
			body.add_child(bonus)
		var explanation := "Final score in Renown points, including quest bonuses. Higher score wins." if final else "Current match score in Renown points. More hands remain."
		if not final:
			explanation += " " + ("You lead." if winner == 0 else ("Opponent leads." if winner == 1 else "The match is tied."))
		if duel.mode == T.Mode.RANKED:
			explanation += " Hand %d of 3." % duel.hands_played
		var meaning := UI.label(explanation, 24 if _landscape else 20, UI.TEXT_DIM, false, true)
		meaning.add_theme_font_override("font", ThemeDB.fallback_font)
		body.add_child(meaning)

	ScoreSheet.build(body, score, duel, _landscape)

	if final:
		_record_match(puzzle_result)
		if duel.puzzle.is_empty():
			_play_end_sound(duel.winner())
		var row := HBoxContainer.new()
		row.add_theme_constant_override("separation", 10)
		outer.add_child(row)
		var again := UI.button("Play again", "primary", 28 if _landscape else 24)
		again.custom_minimum_size.y = 80 if _landscape else 56
		again.add_theme_font_override("font", ThemeDB.fallback_font)
		again.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		again.pressed.connect(func():
			_close_overlay()
			play_again.emit(_fresh_config()))
		row.add_child(again)
		var menu := UI.button("Menu", "secondary", 28 if _landscape else 24)
		menu.custom_minimum_size.y = 80 if _landscape else 56
		menu.add_theme_font_override("font", ThemeDB.fallback_font)
		menu.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		menu.pressed.connect(func():
			_close_overlay()
			exit_to_menu.emit())
		row.add_child(menu)
		if duel.mode == T.Mode.RANKED:
			var c: Dictionary = _fresh_config()
			c["mode"] = T.Mode.QUICK
			var quick := UI.button("Quick Duel instead", "ghost", 16)
			quick.pressed.connect(func():
				_close_overlay()
				play_again.emit(c))
			outer.add_child(quick)
	else:
		var nxt := UI.button("Next hand", "primary", 28 if _landscape else 24)
		nxt.custom_minimum_size.y = 80 if _landscape else 56
		nxt.add_theme_font_override("font", ThemeDB.fallback_font)
		nxt.pressed.connect(func():
			_close_overlay()
			duel.next_hand()
			duel.drain_events()
			_busy = false
			_save_state()
			_hinted_once = false
			_turn_time = TURN_SECONDS
			_refresh_all()
			if duel.turn == 1:
				_run_bot())
		outer.add_child(nxt)
		if duel.mode == T.Mode.RANKED:
			var note := UI.label("Best of three · first to %d Renown wins the match" % T.MODE_INFO[T.Mode.RANKED].target, 14, UI.TEXT_DIM)
			note.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
			body.add_child(note)


func _puzzle_verdict(body: VBoxContainer) -> bool:
	return PuzzleVerdict.build(body, duel, _landscape)


func _record_match(puzzle_result: int = -1) -> void:
	if _match_recorded:
		return
	var w := duel.winner()
	var won := puzzle_result == 1 if puzzle_result >= 0 else w == 0
	_match_recorded = Profile.record_match(won, w == -1, duel.renown[0], duel.player_glory,
		duel.player_sweeps, duel.player_faction, duel.quest_done.count(true), duel.match_id,
		duel.campaign.get("id", ""), puzzle_result)
	if _match_recorded:
		Profile.clear_duel()


func _play_end_sound(w: int) -> void:
	if w == 0:
		Sfx.play("win", -4.0)
	elif w == 1:
		Sfx.play("lose", -6.0)
	else:
		Sfx.play("tap", -10.0)
	var txt := "VICTORY" if w == 0 else ("DEFEAT" if w == 1 else "DRAWN DUEL")
	var col := UI.GOLD if w == 0 else (UI.BAD if w == 1 else UI.TEXT)
	FX.float_text(self, Vector2(size.x * 0.5, size.y * 0.3), txt, col, 44, 40)


# ---------------------------------------------------------------------------
# MENU
# ---------------------------------------------------------------------------
func _fresh_config() -> Dictionary:
	var next_config := config.duplicate(true)
	next_config.erase("resume")
	return next_config


func _open_menu() -> void:
	if duel.hand_over:
		return
	Sfx.play("tap")
	_refresh_all()
	_table_box.queue_redraw()
	var panel := _oath_sheet("PAUSED", "", false)
	panel.set_meta("dialog_width", 720.0)
	var body: VBoxContainer = panel.get_meta("body")
	var resume := UI.button("Resume", "primary")
	resume.pressed.connect(_close_overlay)
	body.add_child(resume)
	var settings := UI.button("Settings", "secondary", 24)
	settings.name = "GameSettings"
	settings.pressed.connect(_open_game_settings)
	body.add_child(settings)
	var quit := UI.button("Concede & return to menu", "ghost", 17)
	quit.pressed.connect(func():
		_close_overlay()
		Profile.clear_duel()
		exit_to_menu.emit())
	body.add_child(quit)
	var rules := UI.button("Rules & scoring", "ghost", 17)
	rules.pressed.connect(func(): _show_rules(true))
	body.add_child(rules)
	var restart := UI.button("Restart duel", "ghost", 17)
	restart.pressed.connect(func():
		_close_overlay()
		play_again.emit(_fresh_config()))
	body.add_child(restart)
	body.move_child(quit, body.get_child_count() - 1)
	_pause_for_menu(panel)
	_layout_game_dialogs()


func _open_game_settings() -> void:
	var panel := _oath_sheet("SETTINGS", "", false)
	var body: VBoxContainer = panel.get_meta("body")
	var scroll := body.get_parent() as ScrollContainer
	panel.remove_child(scroll)
	var outer := VBoxContainer.new()
	outer.add_theme_constant_override("separation", 10)
	panel.add_child(outer)
	var heading := body.get_child(0)
	body.remove_child(heading)
	outer.add_child(heading)
	outer.add_child(scroll)
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	SettingsPanel.populate(panel, _open_menu, _layout_game_dialogs, true)
	_pause_for_menu(panel)
	_layout_game_dialogs()


# ---------------------------------------------------------------------------
# BOOT SEQUENCE + TIMER
# ---------------------------------------------------------------------------
func _boot_sequence() -> void:
	_busy = true
	_refresh_all()
	if duel.puzzle.size() > 0:
		_toast("Daily Puzzle · " + duel.puzzle.name, duel.puzzle.desc)
		await get_tree().create_timer(0.4, false).timeout
		_busy = false
		_refresh_all()
		return
	await get_tree().create_timer(0.15, false).timeout
	Sfx.play("deal", -12.0)
	_toast("The table is set", "Deal 3 each. Play a card: match a rank or a sum.")
	await get_tree().create_timer(0.55, false).timeout
	_busy = false
	_refresh_all()
	# teaching nudges: glow the first card you can capture with
	if duel.mode == T.Mode.QUICK and duel.turn == 0:
		_tutorial_glow()
	if duel.turn == 1:
		_run_bot()


func _tutorial_glow() -> void:
	for cv in _hand_row.get_children():
		if cv is CardView:
			var groups: Array = duel.groups_for_player(0, cv.card_id)
			if groups.size() > 0:
				cv.hinted = true
				break


var _perf_checked := false


func _process(delta: float) -> void:
	if duel == null:
		return
	# On a software rasteriser the full-screen backdrop competes with the cards
	# for draw time. Check once, a few seconds in, and say so. There is nothing to
	# switch off: this used to call a no-op RealmBackground.set_quiet() and print
	# "background animations paused", a claim about work that never happened.
	if not _perf_checked and Engine.get_process_frames() > 240:
		_perf_checked = true
		var fps := Engine.get_frames_per_second()
		if fps < 30.0:
			print("[scopa] performance: ", fps, " fps on a software rasteriser")
	# Reading a sheet is not a move. Opening the rules, the pile view or an Oath
	# picker does not set _busy or pause the tree, so the clock used to run down
	# behind the panel and auto-play a card the player never chose. The clock is
	# held while any sheet is open, and a suspended app cannot hand this a huge
	# delta that skips the whole turn in one frame.
	if duel.is_my_turn(0) and not duel.hand_over and not _busy and _overlay == null:
		_turn_time -= minf(delta, MAX_TURN_DELTA)
		if _turn_time <= 5.0 and _turn_time > 0.0:
			var bucket := int(_turn_time)
			if bucket != int(_last_tick):
				_last_tick = _turn_time
				Sfx.play("tick", -22.0)
		if _turn_time <= 0.0:
			_turn_time = 0.0
			_auto_play()
		_turn_meter.queue_redraw()
	elif _turn_time != TURN_SECONDS and not _busy and _overlay == null:
		_turn_time = TURN_SECONDS
		_turn_meter.queue_redraw()


func _auto_play() -> void:
	var best := DuelAI.choose_move(duel, 0)
	if best.is_empty():
		return
	_close_overlay()
	_toast("Time", "The realm chose for you.")
	_play_card(best.card, maxi(0, best.group))
