extends RefCounted
## Card-flight and match-ring animation.
##
## Extracted from screens/duel.gd, which was carrying layout, animation, modal
## sheets, oath pickers and score presentation in one file. These five functions
## were the last animation seam in it: they only need somewhere to add their
## transient nodes, a way to look up the card views already on screen, and the
## position of the pile chip.
##
## Everything here is cosmetic. `anim_on()` is checked by the caller before any
## of it runs, and each helper returns early rather than leaving a node behind,
## so a machine with animation switched off gets no tweens at all.
##
## The two lookups take concrete containers instead of reaching for screen
## fields: the caller owns its layout tree, this module only reads it.

const UI := preload("res://scripts/ui/ui.gd")
const CardView := preload("res://scripts/ui/card_view.gd")


## The card view for `id` in `grid`, or null if it is not on the table any more.
static func table_card_node(grid: Control, id: int) -> Control:
	for cv in grid.get_children():
		if cv is CardView and cv.card_id == id:
			return cv
	return null


## The card view for `id` in the player's hand row, or null.
static func hand_card_node(row: Control, id: int) -> Control:
	for cv in row.get_children():
		if cv is CardView and cv.card_id == id:
			return cv
	return null


## A gold ring that fades in and out on every card a capture matched. `host`
## must be the control the rings are positioned inside; `grid` is searched for
## the card views. `origin` is host's global position, for the same reason.
static func mark_match(host: Control, grid: Control, cards: Array, origin: Vector2) -> void:
	for c in cards:
		var node := table_card_node(grid, c)
		if node == null:
			continue
		var ring := Panel.new()
		ring.add_theme_stylebox_override("panel", UI.panel(Color(0, 0, 0, 0), 8, UI.GOLD, 3))
		ring.mouse_filter = Control.MOUSE_FILTER_IGNORE
		ring.z_index = 60
		ring.size = node.size + Vector2(12, 12)
		ring.position = node.global_position - Vector2(6, 6) - origin
		ring.modulate.a = 0.0
		host.add_child(ring)
		var t := host.create_tween()
		t.tween_property(ring, "modulate:a", 1.0, 0.12)
		t.chain().tween_property(ring, "modulate:a", 0.0, 0.34).set_delay(0.16)
		t.chain().tween_callback(ring.queue_free)


## Copies of the captured cards fly to the pile chip and shrink away. Staggered
## by 45 ms so a four-card capture reads as a fan rather than a single blob.
static func fly_to_pile(host: Control, cards: Array, from: Vector2, pile_pos: Vector2) -> void:
	for i in range(cards.size()):
		var cv := CardView.new()
		cv.setup(cards[i], true, 64, 90)
		cv.mouse_filter = Control.MOUSE_FILTER_IGNORE
		cv.z_index = 70
		host.add_child(cv)
		cv.position = from - Vector2(32, 45)
		var t := host.create_tween()
		t.set_parallel(true)
		var delay := 0.045 * i
		t.tween_property(cv, "position", pile_pos - Vector2(32, 45), 0.34).set_delay(delay).set_ease(Tween.EASE_IN).set_trans(Tween.TRANS_CUBIC)
		t.tween_property(cv, "scale", Vector2(0.55, 0.55), 0.34).set_delay(delay)
		t.tween_property(cv, "modulate:a", 0.0, 0.16).set_delay(delay + 0.22)
		t.chain().tween_callback(cv.queue_free)
