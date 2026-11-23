extends RefCounted
## The four faction Oaths, as bottom-sheet card pickers.
##
## Extracted from screens/duel.gd, which was carrying layout, animation, modal
## sheets, oath pickers and score presentation in one 2,300-line file.
##
## Typed as Object, not RefCounted: the caller is a Control (the duel screen),
## which is not a RefCounted, so a RefCounted parameter rejects it outright.
##
## These cannot simply be moved as pure functions: every closure here reaches
## back into the live screen (toast, close, refresh, save) and into the local
## selection arrays it captured. Rather than pass six callbacks around, each
## picker takes ONE object - the screen itself - and calls a small, explicit
## contract on it. The screen is RefCounted-typed so this file does not import
## the screen and cannot create a cycle.
##
## The picker expects these on `picker`:
##   duel                the live Duel instance (engine, scripts/game/duel.gd)
##   open_sheet(t, sub)  PanelContainer whose "body" meta is a VBoxContainer
##   toast(title, sub)   transient message
##   finish()            oath committed: close, drain events, save, refresh
##   close()             dismiss the sheet without spending anything
##   refresh()           repaint the screen after a state change
##
## Everything else is static: no screen fields are read, so the lookup cannot
## quietly grow into a dependency on layout internals.

const T := preload("res://scripts/tables.gd")
const UI := preload("res://scripts/ui/ui.gd")
const CardView := preload("res://scripts/ui/card_view.gd")
const C := preload("res://scripts/game/cards.gd")


## Tapping the Oath button lands here; each faction has exactly one Oath.
static func open(picker: Object) -> void:
	match picker.duel.player_faction:
		T.FORGE:
			deep_delve(picker)
		T.GROVE:
			foresight(picker)
		T.HORDE:
			raid_picker(picker)
		T.CROWN:
			diplomacy(picker)


static func deep_delve(picker: Object) -> void:
	if picker.duel.deck.is_empty():
		picker.toast("Deck is empty", "There is nothing left to draw.")
		return
	var drawn: int = picker.duel.deck[picker.duel.deck.size() - 1]
	var panel: PanelContainer = picker.open_sheet("DEEP DELVE", "You drew %s. Now tap one card in your hand to bury it on the bottom of the deck." % C.label(drawn))
	var body: VBoxContainer = panel.get_meta("body")
	var row := HBoxContainer.new()
	row.alignment = BoxContainer.ALIGNMENT_CENTER
	row.add_theme_constant_override("separation", 8)
	body.add_child(row)
	# a revealed preview of the drawn card + the hand to choose from
	var preview := CardView.new()
	preview.setup(drawn, true, 84, 118)
	row.add_child(preview)
	for c in picker.duel.hands[0].duplicate():
		var b := Button.new()
		b.focus_mode = Control.FOCUS_NONE
		b.custom_minimum_size = Vector2(64, 90)
		b.add_theme_stylebox_override("normal", UI.flat(UI.PANEL_HI, 10, T.FACTIONS[picker.duel.player_faction].color, 1))
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
			if not picker.duel.use_deep_delve(0, c):
				return
			picker.finish()
			picker.toast("Deep Delve", "Drew %s, buried %s." % [C.label(drawn), C.label(c)]))
		row.add_child(b)


static func foresight(picker: Object) -> void:
	var top: Array = picker.duel.peek_top(3)
	if top.is_empty():
		return
	var order: Array = top.duplicate()
	var panel: PanelContainer = picker.open_sheet("FORESIGHT", "These are the next cards to be drawn, left to right. Tap two to swap them, then confirm.")
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

	var confirm := UI.button("Set the order", "primary")
	confirm.pressed.connect(func():
		if not picker.duel.use_foresight(0, order):
			return
		picker.finish()
		picker.toast("Foresight", "The deck is stacked: next draw is %s." % C.label(order[0])))
	body.add_child(confirm)


static func raid_picker(picker: Object) -> void:
	if not picker.duel.can_use_raid(0):
		picker.toast("Raid unavailable", "You need a card in the deck and a visible table card.")
		return
	var panel: PanelContainer = picker.open_sheet("RAID", "Choose a table card to put on the deck bottom. The top card replaces it. No capture or sweep.")
	var body: VBoxContainer = panel.get_meta("body")
	# Tables can have more cards than fit across a window. Wrap the choices and
	# let the sheet scroll vertically instead of hiding cards off the right edge.
	var row := HFlowContainer.new()
	row.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.alignment = FlowContainer.ALIGNMENT_CENTER
	row.add_theme_constant_override("h_separation", 8)
	row.add_theme_constant_override("v_separation", 8)
	body.add_child(row)
	for c in picker.duel.visible_table(0).duplicate():
		var cv := CardView.new()
		cv.setup(c, true, 84, 118)
		cv.set_playable(true)
		cv.pressed.connect(_use_raid_card.bind(picker, c))
		row.add_child(cv)


static func _use_raid_card(picker: Object, card: int) -> void:
	var drawn: int = picker.duel.deck.back() if not picker.duel.deck.is_empty() else -1
	if not picker.duel.use_raid(0, card):
		picker.close()
		picker.refresh()
		picker.toast("Raid unavailable", "The table or deck changed; no Favor was spent.")
		return
	picker.finish()
	picker.toast("Raid", "%s went to the deck bottom; %s replaced it." % [C.label(card), C.label(drawn)])


static func diplomacy(picker: Object) -> void:
	var panel: PanelContainer = picker.open_sheet("DIPLOMACY", "First tap a card in your hand, then a table card. They swap, and nothing is captured.")
	var body: VBoxContainer = panel.get_meta("body")
	var state := {"hand": -1}
	body.add_child(UI.label("YOUR HAND", 13, UI.TEXT_DIM))
	var hr := HBoxContainer.new()
	hr.alignment = BoxContainer.ALIGNMENT_CENTER
	hr.add_theme_constant_override("separation", 8)
	body.add_child(hr)
	var table_row := GridContainer.new()
	table_row.columns = 4
	table_row.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	table_row.add_theme_constant_override("h_separation", 8)
	table_row.add_theme_constant_override("v_separation", 8)
	var tl := UI.label("TABLE", 13, UI.TEXT_DIM)
	body.add_child(tl)
	body.add_child(table_row)
	var confirm := UI.button("Swap", "primary")
	confirm.disabled = true
	var chosen_table := [-1]

	for c in picker.duel.hands[0].duplicate():
		var cv := CardView.new()
		cv.setup(c, true, 84, 118)
		cv.pressed.connect(func():
			state["hand"] = c
			for ch in hr.get_children():
				ch.set_selected(ch.card_id == c)
			confirm.disabled = chosen_table[0] == -1
			Sfx.play("select", -14.0))
		hr.add_child(cv)
	for c in picker.duel.visible_table(0).duplicate():
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
		if not picker.duel.use_diplomacy(0, state["hand"], chosen_table[0]):
			return
		picker.finish()
		picker.toast("Diplomacy", "Swapped %s for %s." % [C.label(state["hand"]), C.label(chosen_table[0])]))
	body.add_child(confirm)
