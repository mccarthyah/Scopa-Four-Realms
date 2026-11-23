extends RefCounted
## The end-of-hand score sheet: the "HOW THIS HAND SCORED" award grid, the tie
## explanation and the quest bonus list.
##
## Extracted from screens/duel.gd, which was carrying layout, animation, modal
## sheets, oath pickers and score presentation in one 2,300-line file. This part
## has no dependency on the duel screen's state: it takes a score dictionary and
## a container, and builds labels. Keeping it separate also means the scoring
## presentation can be checked without constructing a whole duel screen.
##
## `landscape` only scales the type; the caller passes the flag it already has.

const T := preload("res://scripts/tables.gd")
const UI := preload("res://scripts/ui/ui.gd")


## Appends the scoring grid, any tie notes, and the quest bonus list to `body`.
static func build(body: VBoxContainer, score: Dictionary, duel: RefCounted, landscape: bool) -> void:
	var scoring_title := UI.label("HOW THIS HAND SCORED", 24 if landscape else 20, UI.GOLD)
	scoring_title.add_theme_font_override("font", ThemeDB.fallback_font)
	body.add_child(scoring_title)

	var grid := GridContainer.new()
	grid.columns = 3
	grid.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	grid.add_theme_constant_override("h_separation", 12)
	grid.add_theme_constant_override("v_separation", 12)
	body.add_child(grid)

	_cell(grid, "Award", "", UI.TEXT_DIM, true, landscape)
	_cell(grid, "", "You", UI.GOLD, true, landscape)
	_cell(grid, "", "Opponent", UI.TEXT, true, landscape)

	var tie_notes := PackedStringArray()
	for category in [
		["Most cards", "cards", "loot", "cards"],
		["Most Forge cards", "forge", "treasury", "Forge"],
		["Best Banner", "primiera", "banner", "strength"],
	]:
		_cell(grid, category[0], "", UI.TEXT, false, landscape)
		var owner: int = score[category[2]]
		if score[category[1]][0] == score[category[1]][1] and owner >= 0:
			tie_notes.append("%s tied. %s wins this award through a faction or boss tie rule." % [
				category[0], "You" if owner == 0 else "Opponent"])
		for who in range(2):
			var points := 1 if int(score[category[2]]) == who else 0
			_cell(grid, "", "%d %s\n+%d %s" % [
				score[category[1]][who], category[3],
				points, "point" if points == 1 else "points"],
				UI.GOOD if points else UI.TEXT_DIM, false, landscape)

	_cell(grid, "Runestone\n7 of Forge", "", UI.TEXT, false, landscape)
	for who in range(2):
		var points := 1 if int(score.runestone) == who else 0
		_cell(grid, "", ("Captured\n+1 point" if points else "+0 points"),
			UI.GOOD if points else UI.TEXT_DIM, false, landscape)

	_cell(grid, "Sweeps", "", UI.TEXT, false, landscape)
	for who in range(2):
		_cell(grid, "", "+%d points" % score.scopa[who],
			UI.GOOD if score.scopa[who] else UI.TEXT_DIM, false, landscape)

	_cell(grid, "Hand points", "", UI.GOLD, true, landscape)
	_cell(grid, "", "+%d" % score.points[0], UI.GOLD, true, landscape)
	_cell(grid, "", "+%d" % score.points[1], UI.TEXT, true, landscape)

	if not tie_notes.is_empty():
		var tie_explanation := UI.label(" ".join(tie_notes), 24 if landscape else 19, UI.TEXT_DIM, false, true)
		tie_explanation.add_theme_font_override("font", ThemeDB.fallback_font)
		body.add_child(tie_explanation)

	if not duel.quests.is_empty():
		var quests_title := UI.label("QUEST BONUSES · THIS MATCH", 24 if landscape else 20, UI.GOLD)
		quests_title.add_theme_font_override("font", ThemeDB.fallback_font)
		body.add_child(quests_title)
	for i in range(duel.quests.size()):
		var quest: Dictionary = duel.quests[i]
		var bonus := ("%s · You earned +%d points" % [quest.name, quest.reward]
			if duel.quest_done[i] else "%s · Not completed (+0)" % quest.name)
		var quest_line := UI.label(bonus, 24 if landscape else 20,
			UI.GOOD if duel.quest_done[i] else UI.TEXT_DIM, false, true)
		quest_line.add_theme_font_override("font", ThemeDB.fallback_font)
		quest_line.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		body.add_child(quest_line)


## One grid cell. `val` is used when `txt` is empty, so the call sites can pass
## an empty label for the award column without repeating the string.
static func _cell(grid: GridContainer, txt: String, val: String, col: Color, header: bool, landscape: bool) -> void:
	var use := val if txt == "" else txt
	var l := UI.label(use, 24 if landscape else 19, col, false, true)
	l.add_theme_font_override("font", ThemeDB.fallback_font)
	l.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	if header:
		l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	grid.add_child(l)
