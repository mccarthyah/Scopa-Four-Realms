extends RefCounted
## Heuristic Scopa opponent.  It only ever sees its own hand plus the table, and
## its personality changes which heuristics it weighs.
class_name DuelAI

const T := preload("res://scripts/tables.gd")
const C := preload("res://scripts/game/cards.gd")


static func _card_value(c: int) -> float:
	var v := 2.0
	v += float(C.primiera(c)) / 8.0
	if C.rank(c) == 7:
		v += 2.5
	if C.is_runestone(c):
		v += 5.0
	if C.faction(c) == T.FORGE:
		v += 1.2
	return v


## Returns {"card": int, "group": int} — group is the index of the capture group.
static func choose_move(duel, who: int) -> Dictionary:
	var style: String = duel.campaign.get("ai", "smart")
	var hand: Array = duel.hands[who]
	if hand.is_empty():
		return {}

	var best := {}
	var best_score := -INF
	for card in hand:
		var groups := C.capture_groups(duel.table, card)
		if groups.is_empty():
			var s := _place_score(duel, who, card, style)
			if s > best_score:
				best_score = s
				best = {"card": card, "group": -1}
		else:
			for gi in range(groups.size()):
				var s := _capture_score(duel, who, card, groups[gi], style)
				if s > best_score:
					best_score = s
					best = {"card": card, "group": gi}
	return best


static func _capture_score(duel, who: int, card: int, group: Array, style: String) -> float:
	var s := 0.0
	for c in group:
		s += _card_value(c)
	# the played card itself also joins your pile
	s += _card_value(card) * 0.35
	# scopa?
	var last_play: bool = duel.deck.is_empty() and duel.hands[0].is_empty() and duel.hands[1].is_empty()
	if duel.table.size() == group.size() and not last_play:
		s += 6.0
		if style == "aggressive":
			s += 3.0
	# prefer capturing sevens (Favor + Runestone + Primiera)
	for c in group:
		if C.rank(c) == 7:
			s += 2.0
	# humans like keeping strong primiera
	if style == "primiera":
		s += float(C.primiera(card)) / 3.0
	# aggressive orcs sweep even when it is not optimal
	if style == "aggressive" and duel.table.size() <= 2:
		s += 1.5
	# greedy elves love the biggest pile
	if style == "greedy":
		s += group.size() * 0.8
	return s


static func _place_score(duel, who: int, card: int, style: String) -> float:
	# Dumping a card is a weak move: score it in the negative, penalising the
	# cards that are most valuable to leave lying around.
	var s := -3.0 - _card_value(card) * 0.5
	if C.rank(card) == 7 or C.is_runestone(card):
		s -= 4.0
	# dumping a duplicate rank the table already shows is safer
	for c in duel.table:
		if C.rank(c) == C.rank(card):
			s += 1.0
			break
	if style == "aggressive":
		s -= 1.0
	return s


## Decide whether to spend Favor this turn.  Returns an action dictionary for
## the caller to apply, or {} to just play a card.
static func choose_oath(duel, who: int) -> Dictionary:
	if not duel.can_use_oath(who):
		return {}
	# keep Oaths for the mid-game unless they are clearly useful
	var faction: int = duel.player_faction if who == 0 else duel.bot_faction
	var move := choose_move(duel, who)
	var hand: Array = duel.hands[who]

	match faction:
		T.FORGE: # Deep Delve — trade the worst card for a fresh one
			if duel.deck.size() < 4 or duel.rng.randf() > 0.5:
				return {}
			var worst: int = hand[0]
			for c in hand:
				if _card_value(c) < _card_value(worst):
					worst = c
			return {"kind": "delvedeep", "bury": worst}

		T.GROVE: # Foresight — stack the next draw in our favour
			if duel.deck.size() < 3 or duel.rng.randf() > 0.45:
				return {}
			var top: Array = duel.peek_top(3)
			var sorted: Array = top.duplicate()
			sorted.sort_custom(func(a, b): return _card_value(a) > _card_value(b))
			return {"kind": "foresight", "order": sorted}

		T.HORDE: # Raid — banish the table card the enemy wants most
			if duel.table.is_empty() or duel.rng.randf() > 0.5:
				return {}
			var target: int = duel.table[0]
			for c in duel.table:
				if _card_value(c) > _card_value(target):
					target = c
			return {"kind": "raid", "card": target}

		T.CROWN: # Diplomacy — take a strong table card into hand
			if duel.table.is_empty() or hand.is_empty() or duel.rng.randf() > 0.5:
				return {}
			var take: int = duel.table[0]
			for c in duel.table:
				if _card_value(c) > _card_value(take):
					take = c
			var give: int = hand[0]
			for c in hand:
				if _card_value(c) < _card_value(give):
					give = c
			if _card_value(take) <= _card_value(give):
				return {}
			return {"kind": "diplomacy", "hand": give, "table": take}
	return {}
