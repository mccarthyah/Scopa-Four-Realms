extends RefCounted
## Card helpers.  Cards are plain integers, so decks, hands and the table are
## trivially serialisable (useful later for async duels / online play).
##
##   id = (rank - 1) * 4 + faction      0 = 1 of Forge ... 39 = 10 of Crown
##
## A standard 40-card Scopa deck, re-skinned.
class_name Cards

const T := preload("res://scripts/tables.gd")

const DECK_SIZE := 40


static func make(rank: int, faction: int) -> int:
	return (rank - 1) * 4 + faction


static func rank(id: int) -> int:
	return int(id / 4) + 1


static func faction(id: int) -> int:
	return id % 4


static func is_runestone(id: int) -> bool:
	return rank(id) == 7 and faction(id) == T.RUNESTONE_SUIT


static func primiera(id: int) -> int:
	return T.PRIMIERA[rank(id) - 1]


static func is_face(id: int) -> bool:
	return rank(id) >= 8


static func full_deck() -> Array:
	var d: Array = []
	for i in range(DECK_SIZE):
		d.append(i)
	return d


static func faction_name(id: int) -> String:
	return T.FACTIONS[faction(id)].people


static func label(id: int) -> String:
	if is_runestone(id):
		return "Runestone (7 Forge)"
	return str(rank(id)) + " of " + T.FACTIONS[faction(id)].name


## Short label used on cards: "7 · Forge"
static func short(id: int) -> String:
	return str(rank(id)) + " · " + T.FACTIONS[faction(id)].name


static func sort_by_faction(a: int, b: int) -> bool:
	if faction(a) != faction(b):
		return faction(a) < faction(b)
	return rank(a) < rank(b)


static func sort_by_rank(a: int, b: int) -> bool:
	if rank(a) != rank(b):
		return rank(a) < rank(b)
	return faction(a) < faction(b)


# ---------------------------------------------------------------------------
# CAPTURE RULES (classic Scopa)
# ---------------------------------------------------------------------------

## All legal groups the played card may capture.  A group is an Array of table
## card ids whose ranks add up to the played card's rank:
##   * exactly one opponent card of that rank, or
##   * a set of cards that sums to that rank.
## Cards of rank 10 can only be taken by an exact 10.
static func capture_groups(table: Array, played: int) -> Array:
	var target := rank(played)
	var by_rank: Array = []
	for c in table:
		if rank(c) == target:
			by_rank.append([c])

	var by_sum: Array = []
	if target < 10:
		_sum_groups(table, target, 0, [], by_sum)

	# de-duplicate (a single card is never produced twice)
	var out: Array = []
	var seen := {}
	for g in by_rank + by_sum:
		var key := _key(g)
		if not seen.has(key):
			seen[key] = true
			out.append(g)
	return out


static func _key(group: Array) -> String:
	var s: Array = group.duplicate()
	s.sort()
	return str(s)


static func _sum_groups(table: Array, remaining: int, start: int, acc: Array, out: Array) -> void:
	if remaining == 0:
		if acc.size() >= 2:
			out.append(acc.duplicate())
		return
	for i in range(start, table.size()):
		var c: int = table[i]
		if rank(c) <= remaining:
			acc.append(c)
			_sum_groups(table, remaining - rank(c), i + 1, acc, out)
			acc.pop_back()


## Convenience: does playing `played` capture anything?
static func can_capture(table: Array, played: int) -> bool:
	return not capture_groups(table, played).is_empty()
