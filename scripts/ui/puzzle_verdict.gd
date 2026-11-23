extends RefCounted
## The daily-puzzle verdict: decide whether the puzzle's goal was met, then
## render a solved/failed panel into the sheet body.
##
## Extracted from screens/duel.gd. The surrounding hand-summary sheet stays
## where it is - it owns the async timer, the play-again signal and the scene
## transitions, so it is orchestration, not presentation. This part is a pure
## function of the duel state plus a container to draw into.

const T := preload("res://scripts/tables.gd")
const UI := preload("res://scripts/ui/ui.gd")
const C := preload("res://scripts/game/cards.gd")


## Renders the verdict and returns whether the goal was met.
static func build(body: VBoxContainer, duel: Object, landscape: bool) -> bool:
	var goal: String = duel.puzzle.get("goal", "scopa")
	var ok := false
	var msg := ""
	match goal:
		"scopa":
			ok = duel.scopa_count[0] >= 1
			msg = "%d sweeps earned. You need at least 1." % duel.scopa_count[0]
		"runestone":
			ok = duel.captured[0].has(C.make(7, T.RUNESTONE_SUIT))
			msg = "Runestone captured." if ok else "The Runestone is outside your captured pile."
		"primiera":
			ok = duel.primiera_total(duel.captured[0]) > 40
			msg = "Banner strength %d. You need more than 40." % duel.primiera_total(duel.captured[0])
		"captures":
			ok = duel.captured[0].size() >= 12
			msg = "%d cards captured. You need at least 12." % duel.captured[0].size()
	_panel(body, ok, msg, landscape)
	return ok


## The solved/failed badge. Split out so the verdict above reads as rules rather
## than layout, and so a caller that already knows the outcome can render it.
static func _panel(body: VBoxContainer, ok: bool, msg: String, landscape: bool) -> void:
	var p := PanelContainer.new()
	p.add_theme_stylebox_override("panel", UI.panel(Color("233026") if ok else Color("2f2228"), 14,
		UI.GOOD if ok else UI.BAD, 2))
	var v := VBoxContainer.new()
	v.add_theme_constant_override("separation", 2)
	p.add_child(v)
	var t := UI.label("PUZZLE SOLVED" if ok else "PUZZLE FAILED", 36 if landscape else 28,
		UI.GOOD if ok else UI.BAD, true)
	t.add_theme_font_override("font", ThemeDB.fallback_font)
	t.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	v.add_child(t)
	var s := UI.label(msg, 24 if landscape else 20, UI.TEXT_DIM)
	s.add_theme_font_override("font", ThemeDB.fallback_font)
	s.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	s.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	v.add_child(s)
	body.add_child(p)
	if ok:
		Sfx.play("win", -8.0)
	else:
		Sfx.play("lose", -10.0)
