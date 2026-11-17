extends Control
## The duel table: HUD, opponent, table cards, your hand, Oath controls,
## scoring sheet and the campaign puzzle goals.  Portrait-first, one-handed.

const UI := preload("res://scripts/ui/ui.gd")
const FX := preload("res://scripts/ui/fx.gd")
const CardView := preload("res://scripts/ui/card_view.gd")
const EffectAtlas := preload("res://scripts/ui/effect_atlas.gd")
const DuelAI := preload("res://scripts/game/ai.gd")
const RealmBackground := preload("res://scripts/ui/background.gd")

signal exit_to_menu
signal play_again(config)

const T := preload("res://scripts/tables.gd")
const C := preload("res://scripts/game/cards.gd")
const Duel := preload("res://scripts/game/duel.gd")

const TURN_SECONDS := 26.0

var config: Dictionary = {}
var duel: Duel

# --- widgets -----------------------------------------------------------------
var _bg: Control
var _top_name: Label
var _top_meta: Label
var _top_avatar: Control
var _top_favor: PanelContainer
var _top_scoopa: PanelContainer
var _top_pile: Label
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
var _favor_label: Label
var _favor_strip: Control
var _quest_list: VBoxContainer
var _banner_meter: Control
var _toast_box: VBoxContainer
var _overlay: Control
var _deck_chip: PanelContainer
var _pile_chip: PanelContainer
var _goal_chip: PanelContainer
var _score_chip: PanelContainer
var _portrait_root: VBoxContainer
var _landscape_root: HBoxContainer
var _landscape_side: VBoxContainer
var _landscape_table: VBoxContainer
var _landscape_player: VBoxContainer
var _layout_mode := "portrait"
var _layout_parts := {}
var _landscape := false
var _layout_ready := false
var _layout_refresh_pending := false

# --- runtime -----------------------------------------------------------------
var _turn_time := TURN_SECONDS
var _selection := -1
var _pending_groups: Array = []
var _busy := false
var _ai_token := 0
var _hinted_once := false
var _timeouts := 0
var _scopa_total := [0, 0]
var _quests_completed := 0
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

	_bg = RealmBackground.new()
	add_child(_bg)
	_bg.set_accents(T.FACTIONS[pfac].color, T.FACTIONS[bfac].color)
	_bg.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)

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
	_landscape_side.custom_minimum_size = Vector2(400, 0)
	_landscape_side.add_theme_constant_override("separation", 8)
	_landscape_root.add_child(_landscape_side)
	_landscape_table = VBoxContainer.new()
	_landscape_table.name = "DuelPlayfield"
	_landscape_table.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_landscape_table.add_theme_constant_override("separation", 6)
	_landscape_root.add_child(_landscape_table)
	_landscape_player = VBoxContainer.new()
	_landscape_player.name = "PlayerPanel"
	_landscape_player.custom_minimum_size = Vector2(450, 0)
	_landscape_player.add_theme_constant_override("separation", 10)
	_landscape_root.add_child(_landscape_player)
	_landscape_player.hide()
	var player_spacer := Control.new()
	player_spacer.name = "PlayerTopSpacer"
	player_spacer.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_landscape_player.add_child(player_spacer)
	var player_heading := UI.label("YOUR HAND", 18, UI.GOLD)
	player_heading.name = "PlayerHeading"
	_landscape_player.add_child(player_heading)
	var player_bottom := Control.new()
	player_bottom.name = "PlayerBottomSpacer"
	player_bottom.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_landscape_player.add_child(player_bottom)
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
	_toast("Welcome back", "Your duel was saved mid-hand.")
	if duel.turn == 1 and not duel.hand_over:
		_run_bot()


func _build_top() -> Control:
	var p := PanelContainer.new()
	p.add_theme_stylebox_override("panel", UI.panel(UI.PANEL, 16, Color("3b3153"), 1))
	var v := VBoxContainer.new()
	v.add_theme_constant_override("separation", 4)
	p.add_child(v)

	# row 1: opponent
	var r1 := HBoxContainer.new()
	r1.add_theme_constant_override("separation", 10)
	v.add_child(r1)

	_top_avatar = _avatar_pip(duel.bot_faction)
	r1.add_child(_top_avatar)

	var nv := VBoxContainer.new()
	nv.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	nv.add_theme_constant_override("separation", 0)
	r1.add_child(nv)
	_top_name = UI.label("", 20, UI.TEXT, true)
	_top_name.add_theme_font_size_override("font_size", 19)
	nv.add_child(_top_name)
	_top_meta = UI.label("", 14, UI.TEXT_DIM)
	nv.add_child(_top_meta)

	_top_favor = UI.chip("FAVOR 0", Color("3a2f22"), UI.GOLD, 15)
	r1.add_child(_top_favor)
	_top_scoopa = UI.chip("SCOPA 0", Color("2b2338"), UI.TEXT_DIM, 15)
	r1.add_child(_top_scoopa)

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
	var h := HBoxContainer.new()
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
	if what != NOTIFICATION_RESIZED or not is_node_ready() or not _layout_ready:
		return
	_apply_orientation_layout()
	_schedule_layout_refresh()


## Reparent existing controls rather than rebuilding the duel: a rotation must
## not restart the game, invalidate a selection, or discard an open sheet.
func _apply_orientation_layout() -> void:
	if not _layout_ready:
		return
	var wide := size.x > size.y * 1.12
	# At true phone-landscape widths a separate player panel avoids squeezing
	# everything into a portrait stack. Near-square layouts use two columns.
	var mode := "full" if wide and size.x >= 1450.0 else ("compact" if wide else "portrait")
	if mode == _layout_mode:
		return
	_layout_mode = mode
	_landscape = wide
	if wide:
		for key in ["HUD", "TurnBar", "Quests"]:
			_layout_parts[key].reparent(_landscape_side, false)
		if mode == "full":
			_layout_parts.BotHand.reparent(_landscape_side, false)
			_layout_parts.Table.reparent(_landscape_table, false)
			for key in ["Hand", "Actions"]:
				_layout_parts[key].reparent(_landscape_player, false)
			_landscape_player.move_child(_layout_parts.Hand, 2)
			_landscape_player.move_child(_layout_parts.Actions, 3)
			_landscape_player.show()
		else:
			_landscape_player.hide()
			for key in ["BotHand", "Table", "Hand", "Actions"]:
				_layout_parts[key].reparent(_landscape_table, false)
		_portrait_root.hide()
		_landscape_root.show()
	else:
		_landscape_player.hide()
		for key in ["HUD", "TurnBar", "BotHand", "Table", "Quests", "Hand", "Actions"]:
			_layout_parts[key].reparent(_portrait_root, false)
		_landscape_root.hide()
		_portrait_root.show()
	_schedule_layout_refresh()


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
	_hand_box.custom_minimum_size = Vector2(0, int(hw * 1.404) + 36)
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
	p.add_theme_stylebox_override("panel", UI.panel(UI.PANEL, 14, Color("3b3153")))
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
	_favor_label = UI.label("", 13, UI.GOLD)
	_favor_label.position = Vector2(4, 2)
	fav.add_child(_favor_label)
	return _hand_box


func _build_actions() -> Control:
	var h := HBoxContainer.new()
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

	var menu := UI.button("☰", "ghost", 18)
	menu.custom_minimum_size = Vector2(52, 52)
	menu.pressed.connect(_open_menu)
	h.add_child(menu)
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
	var x := 96.0
	fav_node.draw_string(UI.font_bold(), Vector2(4, 16), "FAVOR", HORIZONTAL_ALIGNMENT_LEFT, -1, 12, UI.TEXT_DIM)
	for i in range(Duel.MAX_FAVOR):
		var c := Vector2(x + i * 20, 10)
		var icon := EffectAtlas.FAVOR_FILLED if i < n else EffectAtlas.FAVOR_EMPTY
		var pip_rect := Rect2(c - Vector2(8, 8), Vector2(16, 16))
		if not UI.LOW_SPEC or not EffectAtlas.draw_sprite(fav_node, pip_rect, icon):
			if i < n:
				fav_node.draw_circle(c, 6.0, UI.GOLD)
				fav_node.draw_circle(c, 3.0, Color("fff6dd"))
			else:
				fav_node.draw_arc(c, 6.0, 0, TAU, 18, Color("4a3f5e"), 1.4, true)
	if duel.oath_used[0]:
		fav_node.draw_string(UI.font_bold(), Vector2(96 + Duel.MAX_FAVOR * 20 + 12, 16),
			"Oath spent", HORIZONTAL_ALIGNMENT_LEFT, -1, 12, UI.TEXT_DIM)


const BOARD_THEMES := [
	[Color("1b2a24"), Color("2f4438")],   # Hearth (default)
	[Color("1a2230"), Color("2d3f57")],   # Frostwood
	[Color("2a1c22"), Color("4a2b33")],   # Ember Hall
	[Color("241f2e"), Color("3d3352")],   # Night Court
]

func _draw_table_felt() -> void:
	var r := Rect2(Vector2.ZERO, _table_box.size)
	var theme: Array = BOARD_THEMES[clampi(Profile.board_theme, 0, BOARD_THEMES.size() - 1)]
	# No shadow_size here: a 12px shadow blur is a gaussian pass over the whole
	# board on every repaint, which is ruinous on a software rasteriser. A flat
	# offset block reads the same at this size.
	var sb := UI.flat(Color(0, 0, 0, 0.30), 20)
	_table_box.draw_style_box(sb, Rect2(r.position + Vector2(0, 4), r.size))
	var sb2 := UI.flat(theme[0], 20, theme[1], 2)
	_table_box.draw_style_box(sb2, r)
	# radial felt light: one soft quad instead of six overlapping circles
	var c := r.size * Vector2(0.5, 0.45)
	_table_box.draw_circle(c, r.size.x * 0.55, Color(1, 1, 1, 0.05))
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
			_top_meta.text = bot.oath + " · Scopa di Quindici"

	UI.set_chip(_top_favor, "FAVOR %d" % duel.favor[1], Color("3a2f22") if duel.favor[1] > 0 else Color("2b2338"),
		UI.GOLD if duel.favor[1] > 0 else UI.TEXT_DIM)
	UI.set_chip(_top_scoopa, "SCOPA %d" % duel.scopa_count[1], Color("2b2338"),
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


func _hand_card_width(available: float) -> float:
	if _layout_mode == "full":
		var count := maxi(duel.hands[0].size(), 3)
		return clampf((available - 10.0 * float(count - 1) - 12.0) / float(count), 48.0, 150.0)
	return clampf(available * 0.215, 112.0, 150.0)


func _refresh_hand() -> void:
	for c in _hand_row.get_children():
		c.get_parent().remove_child(c)
		c.queue_free()
	if duel.puzzle.size() > 0:
		pass
	var hand: Array = duel.hands[0].duplicate()
	hand.sort_custom(C.sort_by_faction)
	var my_turn := duel.is_my_turn(0) and not _busy
	var hw: float = _hand_card_width(_hand_box.size.x)
	for c in hand:
		var cv := CardView.new()
		cv.setup(c, true, int(hw), int(hw * 1.404))
		cv.back_style = Profile.card_back
		cv.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		var groups: Array = duel.groups_for_player(0, c)
		cv.set_playable(my_turn and not groups.is_empty())
		cv.dim = not my_turn
		cv.set_selected(c == _selection)
		cv.pressed.connect(_on_hand_card.bind(c))
		_hand_row.add_child(cv)
		cv.enter_anim(0.0)

	if hand.is_empty():
		var l := UI.label("", 18, UI.TEXT_DIM)
		_hand_row.add_child(l)


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
	var MAX_CH := 245.0 if _layout_mode == "full" else 208.0
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
		var cw: float = minf(minf(cw_by_width, cw_by_height), MAX_CH / CardView.ASPECT)
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
	for c in _table_grid.get_children():
		c.get_parent().remove_child(c)
		c.queue_free()
	var vis: Array = duel.visible_table(0)
	vis.sort_custom(C.sort_by_rank)
	var highlight: Array = []
	if _selection >= 0:
		for g in duel.groups_for_player(0, _selection):
			for c in g:
				highlight.append(c)
	elif _pending_groups.size() > 0:
		for c in _pending_groups[0]:
			highlight.append(c)

	var n := vis.size()
	# Fit the cards to the felt rather than letting them overflow it: shrink to fit
	# and wrap onto extra rows as the table gets crowded.
	var layout := _table_layout(n, _table_grid.size)
	var cw: float = layout.cw
	var ch: float = layout.ch
	var at: Array = layout.at
	for i in range(n):
		var c: int = vis[i]
		var cv := CardView.new()
		cv.setup(c, true, int(cw), int(ch))
		cv.capturable = highlight.has(c)
		cv.pressed.connect(_on_table_card.bind(c))
		_table_grid.add_child(cv)
		cv.position = at[i]
		cv.enter_anim(0.05 * i)

	if n == 0:
		_table_sub.text = "the table is clear"
	elif duel.veiled >= 0:
		_table_sub.text = "%d on the table · one veiled by the Warden" % n
	else:
		_table_sub.text = ""

	if _selection >= 0:
		var gs: Array = duel.groups_for_player(0, _selection)
		if gs.size() > 1:
			_table_sub.text = "Tap a glowing card to choose which cards to take"
		elif gs.size() == 1:
			_table_sub.text = "Tap the glowing card to capture"
		elif duel.blocked_by_quindici(_selection):
			_table_sub.text = "Quindici: matching a value never captures — only cards totalling 15"
		else:
			_table_sub.text = "No capture — this card will lie on the table"


func _refresh_quests() -> void:
	for c in _quest_list.get_children():
		c.get_parent().remove_child(c)
		c.queue_free()
	if duel.quests.is_empty():
		_quest_list.add_child(UI.label("Classic rules · no quests in puzzles", 15, UI.TEXT_DIM))
		return
	for i in range(duel.quests.size()):
		var q: Dictionary = duel.quests[i]
		var done: bool = duel.quest_done[i]
		var h := HBoxContainer.new()
		h.add_theme_constant_override("separation", 8)
		var mark := UI.label("✦" if done else "◇", 15, UI.GOLD if done else Color("5a4f70"))
		h.add_child(mark)
		var txt := UI.label(q.name, 16, UI.TEXT if done else UI.TEXT, true)
		txt.add_theme_font_size_override("font_size", 16)
		if done:
			txt.add_theme_color_override("font_color", UI.GOOD)
		h.add_child(txt)
		var d := UI.label("· " + q.desc, 14, UI.TEXT_DIM)
		d.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		d.clip_text = true
		d.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
		h.add_child(d)
		h.add_child(UI.label("+%d" % q.reward, 15, UI.GOOD if done else UI.GOLD))
		_quest_list.add_child(h)


func _refresh_actions() -> void:
	var mine := duel.is_my_turn(0) and not _busy
	var can_oath: bool = duel.can_use_oath(0)
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
	_btn_pile.disabled = false


# ---------------------------------------------------------------------------
# INPUT
# ---------------------------------------------------------------------------
func _on_hand_card(c: int) -> void:
	if not duel.is_my_turn(0) or _busy:
		return
	if _selection == c:
		# second tap on the same card confirms the play
		_confirm_play(c)
		return
	var groups: Array = duel.groups_for_player(0, c)
	_selection = c
	Sfx.play("select", -14.0)
	if groups.size() > 1:
		_pending_groups = groups
		_selection = c
		_refresh_table()
		_refresh_hand()
		_toast("Choose a capture", "Tap a glowing table card, or tap your card again for the first option.")
	else:
		_pending_groups = groups
		_refresh_table()
		_refresh_hand()


func _on_table_card(c: int) -> void:
	if _selection < 0 or _busy:
		return
	var groups: Array = duel.groups_for_player(0, _selection)
	# whichever legal group contains this card
	var pick := -1
	for i in range(groups.size()):
		if groups[i].has(c):
			pick = i
			break
	if pick < 0:
		Sfx.play("deny", -16.0)
		return
	_play_card(_selection, pick)


func _confirm_play(c: int) -> void:
	var groups: Array = duel.groups_for_player(0, c)
	_play_card(c, 0 if groups.size() > 0 else 0)


func _play_card(card: int, group_idx: int) -> void:
	if _busy:
		return
	_busy = true
	_selection = -1
	_pending_groups = []
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
		await get_tree().create_timer(_beat(0.26, 0.10)).timeout
		# 2. whatever it matched lights up, so the pairing is legible
		if not matched.is_empty() and anim_on("match"):
			_mark_match(matched)
			await get_tree().create_timer(_beat(0.34, 0.08)).timeout

	duel.play(0, card, group_idx)
	_handle_events()
	_refresh_all()
	_save_state()

	# fly the cards into the pile
	if not captured.is_empty():
		Sfx.play("capture", -8.0)
		_fly_to_pile(captured, from_center)
		FX.burst(self, target_center, T.FACTIONS[duel.player_faction].color, 16, 200)
	else:
		Sfx.play("deal", -12.0)

	# a scopa holds the beat so the celebration lands before the next turn
	var hold: float = _beat(1.9, 0.9) if _scopa_held else _beat(0.62, 0.24)
	await get_tree().create_timer(hold).timeout
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


func _save_state() -> void:
	Profile.store_duel({
		"mode": duel.mode,
		"player_faction": duel.player_faction,
		"campaign": config.get("campaign", {}),
		"puzzle": config.get("puzzle", {}),
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
	await get_tree().create_timer(_beat(0.45, 0.3)).timeout
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
		await get_tree().create_timer(0.6).timeout
		if token != _ai_token:
			return

	var move: Dictionary = DuelAI.choose_move(duel, 1)
	if move.is_empty():
		_busy = false
		return
	var card: int = move.card
	var gi: int = move.group
	var groups: Array = C.capture_groups_rule(duel.table, card, duel.rule)
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
		await get_tree().create_timer(_beat(0.30, 0.10)).timeout
		if not matched.is_empty() and anim_on("match"):
			_mark_match(matched)
			await get_tree().create_timer(_beat(0.32, 0.08)).timeout
		if token != _ai_token:
			_busy = false
			return

	duel.play(1, card, gi)
	_handle_events()
	_save_state()
	if not captured.is_empty():
		Sfx.play("capture", -12.0, 0.92)
		FX.burst(self, _table_center(), T.FACTIONS[duel.bot_faction].color, 12, 160)
	else:
		Sfx.play("deal", -16.0, 0.9)
	_refresh_all()
	await get_tree().create_timer(_beat(0.36, 0.22)).timeout
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
	if not duel.can_use_oath(0):
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


func _oath_deep_delve() -> void:
	if duel.deck.is_empty():
		_toast("Deck is empty", "There is nothing left to draw.")
		return
	var drawn: int = duel.deck[duel.deck.size() - 1]
	var panel := _oath_sheet("DEEP DELVE", "You drew %s. Now tap one card in your hand to bury it on the bottom of the deck." % C.label(drawn))
	var body: VBoxContainer = panel.get_meta("body")
	var row := HBoxContainer.new()
	row.alignment = BoxContainer.ALIGNMENT_CENTER
	row.add_theme_constant_override("separation", 8)
	body.add_child(row)
	# a revealed preview of the drawn card + the hand to choose from
	var preview := CardView.new()
	preview.setup(drawn, true, 84, 118)
	row.add_child(preview)
	for c in duel.hands[0].duplicate():
		var b := Button.new()
		b.focus_mode = Control.FOCUS_NONE
		b.custom_minimum_size = Vector2(64, 90)
		b.add_theme_stylebox_override("normal", UI.flat(UI.PANEL_HI, 10, T.FACTIONS[duel.player_faction].color, 1))
		b.add_theme_stylebox_override("hover", UI.flat(UI.PANEL_HI, 10, UI.GOLD, 2))
		b.add_theme_stylebox_override("pressed", UI.flat(UI.GOLD, 10))
		b.add_theme_stylebox_override("focus", UI.flat(Color(0, 0, 0, 0), 10))
		var v := VBoxContainer.new()
		v.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
		v.mouse_filter = Control.MOUSE_FILTER_IGNORE
		v.alignment = BoxContainer.ALIGNMENT_CENTER
		b.add_child(v)
		var num := UI.label(str(C.rank(c)), 26, UI.PARCHMENT, true)
		num.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		num.mouse_filter = Control.MOUSE_FILTER_IGNORE
		v.add_child(num)
		var fn := UI.label(T.FACTIONS[C.faction(c)].name, 12, T.FACTIONS[C.faction(c)].pale)
		fn.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		fn.mouse_filter = Control.MOUSE_FILTER_IGNORE
		v.add_child(fn)
		b.pressed.connect(func():
			duel.use_deep_delve(0, c)
			_close_overlay()
			_handle_events()
			_refresh_all()
			_toast("Deep Delve", "Drew %s, buried %s." % [C.label(drawn), C.label(c)]))
		row.add_child(b)


func _oath_foresight() -> void:
	var top: Array = duel.peek_top(3)
	if top.is_empty():
		return
	var order: Array = top.duplicate()
	var panel := _oath_sheet("FORESIGHT", "These are the next cards to be drawn, left to right. Tap two to swap them, then confirm.")
	var body: VBoxContainer = panel.get_meta("body")
	var row := HBoxContainer.new()
	row.alignment = BoxContainer.ALIGNMENT_CENTER
	row.add_theme_constant_override("separation", 10)
	body.add_child(row)
	var sel := [-1]
	var views: Array = []
	var labels := ["next", "2nd", "3rd"]
	for i in range(order.size()):
		var col := VBoxContainer.new()
		col.add_theme_constant_override("separation", 4)
		row.add_child(col)
		var cv := CardView.new()
		cv.setup(order[i], true, 84, 118)
		col.add_child(cv)
		views.append(cv)
		var lb := UI.label(labels[i], 12, UI.TEXT_DIM)
		lb.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		col.add_child(lb)
		var btn_holder := Control.new()
		btn_holder.custom_minimum_size = Vector2(0, 0)
		var cb := func(idx: int):
			if sel[0] == -1:
				sel[0] = idx
				cv.set_selected(true)
				Sfx.play("select", -14.0)
			elif sel[0] == idx:
				sel[0] = -1
				cv.set_selected(false)
			else:
				var tmp = order[idx]
				order[idx] = order[sel[0]]
				order[sel[0]] = tmp
				var a: CardView = views[sel[0]]
				var b: CardView = views[idx]
				a.setup(order[sel[0]], true, 84, 118)
				b.setup(order[idx], true, 84, 118)
				a.set_selected(false)
				sel[0] = -1
				Sfx.play("tap")
		cv.pressed.connect(func(): cb.call(i))

	var go := UI.button("Set the order", "primary")
	go.pressed.connect(func():
		duel.use_foresight(0, order)
		_close_overlay()
		_handle_events()
		_refresh_all()
		_toast("Foresight", "The deck is stacked: next draw is %s." % C.label(order[0])))
	body.add_child(go)


func _oath_raid() -> void:
	if not duel.can_use_raid(0):
		_toast("Raid unavailable", "You need a card in the deck and a visible table card.")
		return
	var panel := _oath_sheet("RAID", "Choose a table card to put on the deck bottom. The top card replaces it. No capture or scopa.")
	var body: VBoxContainer = panel.get_meta("body")
	# Tables can have more cards than fit across a window. Wrap the choices and
	# let the sheet scroll vertically instead of hiding cards off the right edge.
	var row := HFlowContainer.new()
	row.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.alignment = FlowContainer.ALIGNMENT_CENTER
	row.add_theme_constant_override("h_separation", 8)
	row.add_theme_constant_override("v_separation", 8)
	body.add_child(row)
	for c in duel.visible_table(0).duplicate():
		var cv := CardView.new()
		cv.setup(c, true, 84, 118)
		cv.set_playable(true)
		cv.pressed.connect(_use_raid_card.bind(c))
		row.add_child(cv)


func _use_raid_card(card: int) -> void:
	var drawn: int = duel.deck.back() if not duel.deck.is_empty() else -1
	if not duel.use_raid(0, card):
		_close_overlay()
		_refresh_all()
		_toast("Raid unavailable", "The table or deck changed; no Favor was spent.")
		return
	_close_overlay()
	_handle_events()
	_refresh_all()
	_save_state()
	_toast("Raid", "%s went to the deck bottom; %s replaced it." % [C.label(card), C.label(drawn)])


func _oath_diplomacy() -> void:
	var panel := _oath_sheet("DIPLOMACY", "First tap a card in your hand, then a table card. They swap, and nothing is captured.")
	var body: VBoxContainer = panel.get_meta("body")
	var state := {"hand": -1}
	body.add_child(UI.label("YOUR HAND", 13, UI.TEXT_DIM))
	var hr := HBoxContainer.new()
	hr.alignment = BoxContainer.ALIGNMENT_CENTER
	hr.add_theme_constant_override("separation", 8)
	body.add_child(hr)
	var table_row := HBoxContainer.new()
	table_row.alignment = BoxContainer.ALIGNMENT_CENTER
	table_row.add_theme_constant_override("separation", 8)
	var tl := UI.label("TABLE", 13, UI.TEXT_DIM)
	body.add_child(tl)
	body.add_child(table_row)
	var confirm := UI.button("Swap", "primary")
	confirm.disabled = true
	var chosen_table := [-1]

	for c in duel.hands[0].duplicate():
		var cv := CardView.new()
		cv.setup(c, true, 84, 118)
		cv.pressed.connect(func():
			state["hand"] = c
			for ch in hr.get_children():
				ch.set_selected(ch.card_id == c)
			confirm.disabled = chosen_table[0] == -1
			Sfx.play("select", -14.0))
		hr.add_child(cv)
	for c in duel.visible_table(0).duplicate():
		var cv2 := CardView.new()
		cv2.setup(c, true, 84, 118)
		cv2.set_playable(true)
		cv2.pressed.connect(func():
			chosen_table[0] = c
			for ch in table_row.get_children():
				ch.set_selected(ch.card_id == c)
			confirm.disabled = state["hand"] == -1
			Sfx.play("select", -14.0))
		table_row.add_child(cv2)
	confirm.pressed.connect(func():
		duel.use_diplomacy(0, state["hand"], chosen_table[0])
		_close_overlay()
		_handle_events()
		_refresh_all()
		_toast("Diplomacy", "Swapped %s for %s." % [C.label(state["hand"]), C.label(chosen_table[0])]))
	body.add_child(confirm)


# ---------------------------------------------------------------------------
# EVENTS → JUICE
# ---------------------------------------------------------------------------
func _handle_events() -> void:
	for ev in duel.drain_events():
		match ev.get("t", ""):
			"scopa":
				var who: int = ev.who
				_scopa_total[who] += 1
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
				_quests_completed += 1
				var q := _quest_by_key(ev.quest)
				Sfx.play("favor", -8.0)
				_toast("Quest complete · %s" % q.name, "+%d Renown" % ev.reward, UI.GOOD)
			"reveal":
				_toast("The veil lifts", "A hidden table card is revealed: %s." % C.label(ev.card))
			"match_end":
				pass


func _quest_by_key(k: String) -> Dictionary:
	for q in T.QUESTS:
		if q.key == k:
			return q
	return {"name": k, "reward": 1}


func _scopa_celebration(who: int, glory: int) -> void:
	Sfx.play("scopa", -4.0)
	if who == 0:
		_haptic(70)
	FX.flash(self, Color(UI.GOLD.r, UI.GOLD.g, UI.GOLD.b, 0.30), 0.5)
	FX.shake(self, 12.0, 0.45)
	var center := _table_center()
	FX.burst(self, center, UI.GOLD, 40, 340)
	FX.burst(self, center, T.FACTIONS[who].color if who == 0 else T.FACTIONS[duel.bot_faction].color, 26, 260)
	var big := UI.label("SCOPA!", 54, UI.GOLD, true)
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
func _mark_match(cards: Array, from_hand: int = -1) -> void:
	if not anim_on("match"):
		return
	for c in cards:
		var node := _table_card_node(c)
		if node == null:
			continue
		var ring := Panel.new()
		ring.add_theme_stylebox_override("panel", UI.panel(Color(0, 0, 0, 0), 8, UI.GOLD, 3))
		ring.mouse_filter = Control.MOUSE_FILTER_IGNORE
		ring.z_index = 60
		ring.size = node.size + Vector2(12, 12)
		ring.position = node.global_position - Vector2(6, 6) - global_position
		ring.modulate.a = 0.0
		add_child(ring)
		var t := create_tween()
		t.tween_property(ring, "modulate:a", 1.0, 0.12)
		t.chain().tween_property(ring, "modulate:a", 0.0, 0.34).set_delay(0.16)
		t.chain().tween_callback(ring.queue_free)


func _table_card_node(id: int) -> Control:
	for cv in _table_grid.get_children():
		if cv is CardView and cv.card_id == id:
			return cv
	return null


func _hand_card_node(id: int) -> Control:
	for cv in _hand_row.get_children():
		if cv is CardView and cv.card_id == id:
			return cv
	return null


func _fly_to_pile(cards: Array, from: Vector2) -> void:
	var pile_pos := _pile_chip_center()
	for i in range(cards.size()):
		var cv := CardView.new()
		cv.setup(cards[i], true, 64, 90)
		cv.mouse_filter = Control.MOUSE_FILTER_IGNORE
		cv.z_index = 70
		add_child(cv)
		cv.position = from - Vector2(32, 45)
		var t := create_tween()
		t.set_parallel(true)
		var delay := 0.045 * i
		t.tween_property(cv, "position", pile_pos - Vector2(32, 45), 0.34).set_delay(delay).set_ease(Tween.EASE_IN).set_trans(Tween.TRANS_CUBIC)
		t.tween_property(cv, "scale", Vector2(0.55, 0.55), 0.34).set_delay(delay)
		t.tween_property(cv, "modulate:a", 0.0, 0.16).set_delay(delay + 0.22)
		t.chain().tween_callback(cv.queue_free)


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
	l.add_theme_font_size_override("font_size", 17)
	l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	v.add_child(l)
	if sub != "":
		var s := UI.label(sub, 14, UI.TEXT_DIM)
		s.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		s.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		v.add_child(s)
	p.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	_toast_box.add_child(p)
	p.modulate.a = 0.0
	var t := create_tween()
	t.set_parallel(true)
	t.tween_property(p, "modulate:a", 1.0, 0.16)
	t.chain().tween_property(p, "modulate:a", 0.0, 0.4).set_delay(1.9)
	t.chain().tween_callback(p.queue_free)
	while _toast_box.get_child_count() > 3:
		_toast_box.get_child(0).queue_free()
		break


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


func _show_rules() -> void:
	var panel := _oath_sheet("RULES & SCORING", "")
	var body: VBoxContainer = panel.get_meta("body")
	var capture_line := "Play a card whose rank matches a table card, or whose rank equals the sum of several table cards. A 10 can only take a 10."
	if duel.rule == C.RULE_QUINDICI:
		capture_line = "Scopa di Quindici: your card plus the cards you take must total exactly 15, and a card can never take another card of the same value. A 10 can only be taken by a 5."
	for line in [
		["Capture", capture_line],
		["Scopa", "Clear the table with a capture to score a scopa. The final capture of a hand is not a scopa."],
		["The sweep", "When the deck runs out, whoever captured last takes the remaining table cards."],
		["Loot", "1 Renown for the most captured cards."],
		["Treasury", "1 Renown for the most Forge cards."],
		["Runestone", "1 Renown for whoever holds the 7 of Forge."],
		["Banner", "1 Renown for the best Primiera: your best card in each faction (7=21, 6=18, Ace=16, faces=10)."],
		["Glory", "1 Renown per scopa."],
		["Favor", "You earn 1 Favor for a scopa or for capturing any 7. Spend 1 to use your faction Oath, once per hand."],
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


func _show_pile() -> void:
	Sfx.play("tap")
	var f := [0, 1]
	var panel := _oath_sheet("CAPTURED PILES", "Loot, Treasury, Runestone and Banner are read from these piles.")
	var body: VBoxContainer = panel.get_meta("body")
	for who in f:
		var title := "You · %s" % T.FACTIONS[duel.player_faction].people if who == 0 else "%s · %s" % [T.FACTIONS[duel.bot_faction].people, T.FACTIONS[duel.bot_faction].name]
		var head := HBoxContainer.new()
		head.add_theme_constant_override("separation", 8)
		body.add_child(head)
		head.add_child(UI.label(title, 18, UI.GOLD, true))
		head.add_child(UI.label("%d cards · Forge %d · Primiera %d" % [
			duel.captured[who].size(),
			_CountFaction(duel.captured[who], T.FORGE),
			duel.primiera_total(duel.captured[who])], 14, UI.TEXT_DIM))
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


func _CountFaction(arr: Array, f: int) -> int:
	var n := 0
	for c in arr:
		if C.faction(c) == f:
			n += 1
	return n


# ---------------------------------------------------------------------------
# OVERLAY / SHEETS
# ---------------------------------------------------------------------------
func _oath_sheet(title: String, sub: String) -> PanelContainer:
	_close_overlay()
	var dim := ColorRect.new()
	dim.color = Color(0, 0, 0, 0.72)
	dim.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	dim.mouse_filter = Control.MOUSE_FILTER_STOP
	dim.z_index = 100
	dim.gui_input.connect(func(e):
		if e is InputEventMouseButton and e.button_index == MOUSE_BUTTON_LEFT and e.pressed:
			_close_overlay())
	add_child(dim)
	_overlay = dim

	var p := PanelContainer.new()
	p.add_theme_stylebox_override("panel", UI.panel(UI.BG2, 20, UI.GOLD, 2))
	p.z_index = 101
	add_child(p)
	p.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	p.anchor_left = 0.05
	p.anchor_right = 0.95
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
	var close := UI.button("Close", "ghost", 16)
	close.pressed.connect(_close_overlay)
	body.add_child(close)
	p.set_meta("body", body)
	return p


func _close_overlay() -> void:
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
	await get_tree().create_timer(0.5).timeout
	var score: Dictionary = duel.history[duel.history.size() - 1]
	var final := duel.match_over
	var panel := _oath_sheet("HAND %d · RENOWN" % maxi(1, duel.hands_played), "")
	var body: VBoxContainer = panel.get_meta("body")

	# score table
	var grid := GridContainer.new()
	grid.columns = 3
	grid.add_theme_constant_override("h_separation", 8)
	grid.add_theme_constant_override("v_separation", 6)
	body.add_child(grid)
	_hcell(grid, "", "YOU", UI.GOLD, true)
	_hcell(grid, "", T.FACTIONS[duel.bot_faction].people.to_upper(), T.FACTIONS[duel.bot_faction].color, true)
	_hcell(grid, "Loot · most cards", "", UI.TEXT, false)
	_hcell(grid, "", str(score.cards[0]) + ("  ✦" if score.loot == 0 else ""), UI.TEXT, false)
	_hcell(grid, "", str(score.cards[1]) + ("  ✦" if score.loot == 1 else ""), UI.TEXT, false)
	_hcell(grid, "Treasury · Forge", "", UI.TEXT, false)
	_hcell(grid, "", str(score.forge[0]) + ("  ✦" if score.treasury == 0 else ""), UI.TEXT, false)
	_hcell(grid, "", str(score.forge[1]) + ("  ✦" if score.treasury == 1 else ""), UI.TEXT, false)
	_hcell(grid, "Runestone", "", UI.TEXT, false)
	_hcell(grid, "", "✧" if score.runestone == 0 else "—", UI.GOLD if score.runestone == 0 else UI.TEXT_DIM, false)
	_hcell(grid, "", "✧" if score.runestone == 1 else "—", UI.GOLD if score.runestone == 1 else UI.TEXT_DIM, false)
	_hcell(grid, "Banner · Primiera", "", UI.TEXT, false)
	_hcell(grid, "", str(score.primiera[0]) + ("  ✦" if score.banner == 0 else ""), UI.TEXT, false)
	_hcell(grid, "", str(score.primiera[1]) + ("  ✦" if score.banner == 1 else ""), UI.TEXT, false)
	_hcell(grid, "Glory · scopa", "", UI.TEXT, false)
	_hcell(grid, "", str(score.scopa[0]), UI.TEXT, false)
	_hcell(grid, "", str(score.scopa[1]), UI.TEXT, false)
	for f in range(4):
		var info: Dictionary = T.FACTIONS[f]
		_hcell(grid, "%s %s" % [T.SUIT_GLYPH[f], info.name], "", info.color, false)
		var c0 := 0
		var c1 := 0
		for c in duel.captured[0]:
			if C.faction(c) == f:
				c0 += 1
		for c in duel.captured[1]:
			if C.faction(c) == f:
				c1 += 1
		_hcell(grid, "", str(c0), UI.TEXT, false)
		_hcell(grid, "", str(c1), UI.TEXT, false)
	_hcell(grid, "HAND RENOWN", "", UI.GOLD, true)
	_hcell(grid, "", "+%d" % score.points[0], UI.PARCHMENT, true)
	_hcell(grid, "", "+%d" % score.points[1], UI.PARCHMENT, true)

	var ladder := ""
	if duel.mode == T.Mode.RANKED:
		ladder = "   ·   first to %d" % T.MODE_INFO[T.Mode.RANKED].target
	var tot := UI.label("Match Renown   %d — %d%s" % [duel.renown[0], duel.renown[1], ladder], 24, UI.GOLD, true)
	tot.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	body.add_child(tot)

	var qs := HBoxContainer.new()
	qs.alignment = BoxContainer.ALIGNMENT_CENTER
	qs.add_theme_constant_override("separation", 10)
	body.add_child(qs)
	for i in range(duel.quests.size()):
		var q: Dictionary = duel.quests[i]
		qs.add_child(UI.chip(("✦ " if duel.quest_done[i] else "◇ ") + q.name, Color("2b2338"),
			UI.GOOD if duel.quest_done[i] else UI.TEXT_DIM, 13))

	if duel.puzzle.size() > 0:
		_puzzle_verdict(body, score)

	if final:
		_record_match()
		if duel.mode == T.Mode.RANKED or duel.mode == T.Mode.QUICK or duel.mode == T.Mode.CAMPAIGN:
			_play_end_sound(duel.winner())
		var row := HBoxContainer.new()
		row.add_theme_constant_override("separation", 10)
		body.add_child(row)
		var again := UI.button("Play again", "primary")
		again.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		again.pressed.connect(func():
			_close_overlay()
			play_again.emit(config))
		row.add_child(again)
		var menu := UI.button("Menu", "secondary")
		menu.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		menu.pressed.connect(func():
			_close_overlay()
			exit_to_menu.emit())
		row.add_child(menu)
		if duel.mode == T.Mode.RANKED:
			var c: Dictionary = config.duplicate()
			c["mode"] = T.Mode.QUICK
			var quick := UI.button("Quick Duel instead", "ghost", 16)
			quick.pressed.connect(func():
				_close_overlay()
				play_again.emit(c))
			body.add_child(quick)
	else:
		var nxt := UI.button("Next hand", "primary")
		nxt.pressed.connect(func():
			_close_overlay()
			duel.next_hand()
			duel.drain_events()
			_busy = false
			_scopa_total = [0, 0]
			_hinted_once = false
			_turn_time = TURN_SECONDS
			_refresh_all()
			if duel.turn == 1:
				_run_bot())
		body.add_child(nxt)
		if duel.mode == T.Mode.RANKED:
			var note := UI.label("Best of three · first to %d Renown wins the match" % T.MODE_INFO[T.Mode.RANKED].target, 14, UI.TEXT_DIM)
			note.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
			body.add_child(note)


func _hcell(grid: GridContainer, txt: String, val: String, col: Color, header: bool) -> void:
	var use := val if txt == "" else txt
	var l := UI.label(use, 17 if not header else 15, col, header)
	if header:
		l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	grid.add_child(l)


func _puzzle_verdict(body: VBoxContainer, score: Dictionary) -> void:
	var goal: String = duel.puzzle.get("goal", "scopa")
	var ok := false
	var msg := ""
	var players := 0
	match goal:
		"scopa":
			ok = _scopa_total[0] >= 1
			msg = "Clear the table with a capture to score a scopa."
		"runestone":
			ok = duel.captured[0].has(C.make(7, T.RUNESTONE_SUIT))
			msg = "Capture the 7 of Forge — the Runestone."
		"primiera":
			ok = duel.primiera_total(duel.captured[0]) > 40
			msg = "Finish with a Primiera total above 40."
		"captures":
			ok = duel.captured[0].size() >= 12
			msg = "Capture at least 12 cards."
	_solved_puzzle(ok, msg, body)


func _solved_puzzle(ok: bool, msg: String, body: VBoxContainer) -> void:
	var p := PanelContainer.new()
	p.add_theme_stylebox_override("panel", UI.panel(Color("233026") if ok else Color("2f2228"), 14, UI.GOOD if ok else UI.BAD, 2))
	var v := VBoxContainer.new()
	v.add_theme_constant_override("separation", 2)
	p.add_child(v)
	var t := UI.label("PUZZLE SOLVED" if ok else "PUZZLE FAILED", 20, UI.GOOD if ok else UI.BAD, true)
	t.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	v.add_child(t)
	var s := UI.label(msg, 15, UI.TEXT_DIM)
	s.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	s.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	v.add_child(s)
	body.add_child(p)
	if ok:
		Profile.puzzles_solved += 1
		Profile.mark_puzzle_solved(true)
		Sfx.play("win", -8.0)
	else:
		Profile.mark_puzzle_solved(false)
		Sfx.play("lose", -10.0)


func _record_match() -> void:
	if _match_recorded:
		return
	_match_recorded = true
	Profile.clear_duel()
	var w := duel.winner()
	var campaign_id: String = duel.campaign.get("id", "")
	if duel.mode == T.Mode.CAMPAIGN and w == 0 and campaign_id != "" and not Profile.campaign_cleared.has(campaign_id):
		Profile.campaign_cleared.append(campaign_id)
	Profile.record_match(w == 0, w == -1, duel.renown[0], _scopa_total[0], _scopa_total[0],
		duel.player_faction, _quests_completed)


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
func _open_menu() -> void:
	Sfx.play("tap")
	var panel := _oath_sheet("PAUSED", "Scopa: Four Realms")
	var body: VBoxContainer = panel.get_meta("body")
	var info: Dictionary = T.FACTIONS[duel.player_faction]
	body.add_child(UI.label("%s · %s" % [info.people, info.oath], 18, info.color, true))
	var d := UI.label(info.oath_long, 15, UI.TEXT_DIM)
	d.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	body.add_child(d)
	var resume := UI.button("Resume", "primary")
	resume.pressed.connect(_close_overlay)
	body.add_child(resume)
	var quit := UI.button("Concede & return to menu", "ghost", 17)
	quit.pressed.connect(func():
		_close_overlay()
		Profile.clear_duel()
		exit_to_menu.emit())
	body.add_child(quit)
	var rules := UI.button("Rules & scoring", "ghost", 17)
	rules.pressed.connect(_close_overlay)
	rules.pressed.connect(_show_rules)
	body.add_child(rules)
	var restart := UI.button("Restart duel", "ghost", 17)
	restart.pressed.connect(func():
		_close_overlay()
		play_again.emit(config))
	body.add_child(restart)


# ---------------------------------------------------------------------------
# BOOT SEQUENCE + TIMER
# ---------------------------------------------------------------------------
func _boot_sequence() -> void:
	_busy = true
	_refresh_all()
	if duel.puzzle.size() > 0:
		_toast("Daily Puzzle · " + duel.puzzle.name, duel.puzzle.desc)
		await get_tree().create_timer(0.4).timeout
		_busy = false
		_refresh_all()
		return
	await get_tree().create_timer(0.15).timeout
	Sfx.play("deal", -12.0)
	_toast("The table is set", "Deal 3 each. Play a card: match a rank or a sum.")
	await get_tree().create_timer(0.55).timeout
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
	# On a software rasteriser every full-screen animated layer competes with the
	# cards for draw time. Check once, a few seconds in, and let the backdrop rest
	# if this machine cannot hold 30fps.
	if not _perf_checked and Engine.get_process_frames() > 240:
		_perf_checked = true
		var fps := Engine.get_frames_per_second()
		if fps < 30.0 and _bg != null and _bg.has_method("set_quiet"):
			_bg.set_quiet()
			print("[scopa] performance: ", fps, " fps — background animations paused")
	if duel.is_my_turn(0) and not duel.hand_over and not _busy:
		_turn_time -= delta
		if _turn_time <= 5.0 and _turn_time > 0.0:
			var bucket := int(_turn_time)
			if bucket != int(_last_tick):
				_last_tick = _turn_time
				Sfx.play("tick", -22.0)
		if _turn_time <= 0.0:
			_turn_time = 0.0
			_auto_play()
		_turn_meter.queue_redraw()
	elif _turn_time != TURN_SECONDS and not _busy:
		_turn_time = TURN_SECONDS
		_turn_meter.queue_redraw()
	if _bg != null:
		pass


func _auto_play() -> void:
	_timeouts += 1
	var best := DuelAI.choose_move(duel, 0)
	if best.is_empty():
		return
	_toast("Time", "The realm chose for you.")
	_play_card(best.card, maxi(0, best.group))
