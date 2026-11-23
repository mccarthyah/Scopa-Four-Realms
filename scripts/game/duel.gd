extends RefCounted
# gdlint: disable=class-definitions-order
# Declarations here are grouped for readability (constants beside the tables
# they describe, fields beside the build code that fills them) rather than
# strictly consts-before-vars. Ordering is a style rule with no runtime effect;
# see docs/ASSESSMENT.md.

## The whole rules engine, with no UI at all.
##
## Standard Scopa:
##   * 40 cards, ranks 1-10 in four factions
##   * deal 3 each + 4 face up on the table
##   * capture by matching rank (one card) or by a set that sums to your rank
##   * clearing the table scores a scopa (but not on the final play of a deal)
##   * the last player to capture takes the remaining table cards
##
## On top of that: faction Oaths (spend 1 Favor, once per hand), two public
## quests, and hand/match scoring into Renown.
class_name Duel

const T := preload("res://scripts/tables.gd")
const C := preload("res://scripts/game/cards.gd")

const MAX_FAVOR := 6
const HAND_SIZE := 3
const TABLE_START := 4

# --- match configuration -----------------------------------------------------
var mode: int = T.Mode.QUICK
var oaths_enabled := true
var player_faction := T.FORGE
var bot_faction := T.HORDE
var campaign: Dictionary = {}
var puzzle: Dictionary = {}
## Which capture ruleset this match uses (see Cards.RULE_*).  Chosen per match
## from the title screen - variants are never mixed inside one match.
var rule := C.RULE_CLASSIC

# --- state -------------------------------------------------------------------
var deck: Array = []              # deck[0] = bottom, deck[-1] = next drawn
var table: Array = []
var hands: Array = [[], []]
var captured: Array = [[], []]
var scopa_count: Array = [0, 0]
var favor: Array = [0, 0]
var oath_used: Array = [false, false]
var turn := 0
var starter := 0
var last_capturer := -1
var hand_no := 0
var turn_count := 0
var renown: Array = [0, 0]
var match_id := Crypto.new().generate_random_bytes(16).hex_encode()
var player_sweeps := 0
var player_glory := 0
var quests: Array = []
var quest_done: Array = [false, false]
var events: Array = []
var hand_over := false
var match_over := false
var veiled := -1                  # campaign: a table card the player cannot see or take
## Campaign hidden_table: once the veil lifts it stays lifted for the rest of the
## hand (one veiled card per hand, never a new one).  Reset in start_hand().
var veil_lifted := false
var rng := RandomNumberGenerator.new()
var hands_played := 0
var stat := {}
var _capture_table: Array = []
var _capture_rule := ""
var _capture_groups := {}


func _init(config: Dictionary = {}) -> void:
	mode = config.get("mode", T.Mode.QUICK)
	oaths_enabled = config.get("oaths", T.MODE_INFO[mode].oaths)
	player_faction = config.get("player_faction", T.FORGE)
	bot_faction = config.get("bot_faction", T.HORDE)
	campaign = config.get("campaign", {})
	puzzle = config.get("puzzle", {})
	rule = config.get("rule", C.RULE_CLASSIC)
	rng.seed = config.get("seed", randi())
	quests = config.get("quests", [])
	renown = [0, 0]
	match_over = false
	starter = 0
	if quests.is_empty() and mode != T.Mode.PUZZLE:
		quests = _roll_quests()
	start_hand()


# ---------------------------------------------------------------------------
# SET UP A HAND
# ---------------------------------------------------------------------------
func start_hand() -> void:
	deck = []
	table = []
	hands = [[], []]
	captured = [[], []]
	scopa_count = [0, 0]
	favor = [0, 0]
	oath_used = [false, false]
	last_capturer = -1
	turn_count = 0
	hand_over = false
	veiled = -1
	veil_lifted = false
	stat = {"7s": 0, "horde": 0, "forge": 0, "runestone": false, "scopas": 0, "fools": 0}

	if not puzzle.is_empty():
		# fixed deal authored as [rank, faction] pairs
		var used := {}
		for pair in puzzle.table:
			var c: int = C.make(pair[0], pair[1])
			table.append(c)
			used[c] = true
		for pair in puzzle.hand:
			var c: int = C.make(pair[0], pair[1])
			hands[0].append(c)
			used[c] = true
		hands[1] = []
		var rest: Array = []
		for c in C.full_deck():
			if not used.has(c):
				rest.append(c)
		_shuffle(rest)
		deck = rest
		turn = 0
	else:
		var d := C.full_deck()
		_shuffle(d)
		deck = d
		for i in range(TABLE_START):
			table.append(deck.pop_back())
		for p in range(2):
			for i in range(HAND_SIZE):
				hands[p].append(deck.pop_back())
		turn = starter

	_push({"t": "deal"})
	_maybe_hide_table()


func _shuffle(a: Array) -> void:
	for i in range(a.size() - 1, 0, -1):
		var j := rng.randi_range(0, i)
		var tmp = a[i]
		a[i] = a[j]
		a[j] = tmp


## The Warden's twist veils ONE card per hand.  Once that veil has lifted it must
## not fall again: _reveal_if_thin() runs immediately before this on every play, so
## without the veil_lifted latch the engine lifted the veil and instantly hid a
## different card (the player was told "the veil lifts" on the same play that a card
## vanished).  The README promises the card stays visible "until the table thins".
func _maybe_hide_table() -> void:
	if campaign.get("twist_kind", "") != "hidden_table":
		return
	if veiled >= 0 or veil_lifted or table.size() <= 1:
		return
	veiled = table[rng.randi() % table.size()]


## A veiled card is invisible to the player: it can be neither seen nor taken
## until the table thins out and the veil lifts.
func visible_table(who: int) -> Array:
	if who == 0 and veiled >= 0:
		var out: Array = []
		for c in table:
			if c != veiled:
				out.append(c)
		return out
	return table


func _reveal_if_thin() -> void:
	if veiled >= 0 and table.size() <= 2:
		_push({"t": "reveal", "card": veiled})
		veiled = -1
		veil_lifted = true


# ---------------------------------------------------------------------------
# QUERIES
# ---------------------------------------------------------------------------
func groups_for(card: int) -> Array:
	return groups_for_player(0, card)


func groups_for_player(who: int, card: int) -> Array:
	var visible := visible_table(who)
	if _capture_table != visible or _capture_rule != rule:
		_capture_table = visible.duplicate()
		_capture_rule = rule
		_capture_groups.clear()
	if not _capture_groups.has(card):
		_capture_groups[card] = C.capture_groups_rule(visible, card, rule)
	return _capture_groups[card]


## True when Quindici is what stops this card: under classic rules it would have
## captured, and the only capture Quindici removes is matching a card's own value.
## Used purely to explain the rule, so it never looks like a broken tap.
func blocked_by_quindici(card: int) -> bool:
	if rule != C.RULE_QUINDICI:
		return false
	if not C.capture_groups_quindici(visible_table(0), card).is_empty():
		return false
	for c in visible_table(0):
		if C.rank(c) == C.rank(card):
			return true
	return false


func is_my_turn(p: int) -> bool:
	return turn == p and not hand_over and not match_over


func deck_low() -> bool:
	return deck.size() <= 3


# ---------------------------------------------------------------------------
# PLAYING A CARD
# ---------------------------------------------------------------------------
## Play `card` from `who`'s hand.  `group_idx` selects which capture group to
## take when several are legal.
func play(who: int, card: int, group_idx: int = 0) -> Dictionary:
	var empty_result := {}
	if not is_my_turn(who):
		return empty_result
	if not hands[who].has(card):
		return empty_result

	var groups := groups_for_player(who, card)
	hands[who].erase(card)
	turn_count += 1
	var result := {"card": card, "captured": [], "scopa": false, "who": who, "placed": false}

	if groups.is_empty():
		table.append(card)
		result["placed"] = true
		_push({"t": "place", "who": who, "card": card})
	else:
		var gi: int = clampi(group_idx, 0, groups.size() - 1)
		var group: Array = groups[gi]
		var got: Array = group.duplicate()
		got.append(card)
		for c in got:
			table.erase(c)
			captured[who].append(c)
			_track_capture(who, c)
		last_capturer = who
		result["captured"] = got
		_push({"t": "capture", "who": who, "card": card, "group": group})

		# Favor: one per play in which you capture a 7
		for c in got:
			if C.rank(c) == 7:
				gain_favor(who, 1)
				break

		# A scopa only counts if it is not the very last play of the deal
		var last_play: bool = deck.is_empty() and hands[0].is_empty() and hands[1].is_empty()
		if table.is_empty() and not last_play:
			result["scopa"] = true
			_scopa(who)

	_reveal_if_thin()
	_maybe_hide_table()
	_advance_turn()
	return result


func _track_capture(who: int, c: int) -> void:
	if who != 0:
		return
	if C.rank(c) == 7:
		stat["7s"] += 1
	if C.rank(c) == 1:
		stat["fools"] += 1
	match C.faction(c):
		T.HORDE: stat["horde"] += 1
		T.FORGE: stat["forge"] += 1
	if C.is_runestone(c):
		stat["runestone"] = true


func _scopa(who: int) -> void:
	var glory := 1
	if campaign.get("twist_kind", "") == "fury" and who == 1 and turn_count >= 6:
		glory = 2
	scopa_count[who] += glory
	if who == 0:
		stat["scopas"] += 1
		player_sweeps += 1
		player_glory += glory
	gain_favor(who, 1)
	_push({"t": "scopa", "who": who, "glory": glory})


func gain_favor(who: int, n: int) -> void:
	if not oaths_enabled:
		return
	favor[who] = mini(MAX_FAVOR, favor[who] + n)
	_push({"t": "favor", "who": who, "n": n})


# ---------------------------------------------------------------------------
# TURN / DEAL FLOW
# ---------------------------------------------------------------------------
func _advance_turn() -> void:
	if puzzle.is_empty():
		if hands[0].is_empty() and hands[1].is_empty():
			if deck.size() >= 2:
				# Deal the next round (Scopa deals what is left, splitting unevenly)
				while deck.size() > 0:
					if hands[0].size() <= hands[1].size() and hands[0].size() < HAND_SIZE:
						hands[0].append(deck.pop_back())
					elif hands[1].size() < HAND_SIZE:
						hands[1].append(deck.pop_back())
					else:
						break
				_push({"t": "deal"})
				_maybe_hide_table()
			else:
				_end_hand()
				return
	else:
		# Puzzles are challenges with a fixed move budget, not a full deal.
		if hands[0].is_empty() or turn_count >= int(puzzle.get("moves", hands[0].size() + turn_count)):
			_end_hand()
			return

	turn = 1 - turn
	if not puzzle.is_empty():
		# a puzzle is a solitaire line: the turn always stays with you
		if not hands[0].is_empty():
			turn = 0
	elif hands[turn].is_empty() and not hands[1 - turn].is_empty():
		turn = 1 - turn
	_push({"t": "turn", "who": turn})


# ---------------------------------------------------------------------------
# OATHS
# ---------------------------------------------------------------------------
func can_use_oath(who: int) -> bool:
	return oaths_enabled and not oath_used[who] and favor[who] >= 1 and is_my_turn(who) and not hand_over


func oath_title(who: int) -> String:
	return T.FACTIONS[player_faction if who == 0 else bot_faction].oath


func use_deep_delve(who: int, bury: int) -> bool:
	if not can_use_oath(who) or deck.is_empty():
		return false
	if not hands[who].has(bury) and not hands[who].is_empty():
		return false
	var drawn: int = deck.pop_back()
	hands[who].append(drawn)
	if hands[who].has(bury):
		hands[who].erase(bury)
		deck.push_front(bury)
	_finish_oath(who)
	_push({"t": "oath", "who": who, "oath": "Deep Delve", "drawn": drawn, "buried": bury})
	return true


func peek_top(n: int = 3) -> Array:
	var out: Array = []
	for i in range(n):
		if deck.size() - 1 - i >= 0:
			out.append(deck[deck.size() - 1 - i])
	return out


## order: next-to-draw first.
func use_foresight(who: int, order: Array) -> bool:
	if not can_use_oath(who):
		return false
	var top := peek_top(3)
	var sorted_order := order.duplicate()
	sorted_order.sort()
	top.sort()
	if top.is_empty() or sorted_order != top:
		return false
	for c in top:
		deck.pop_back()
	for i in range(order.size() - 1, -1, -1):
		deck.append(order[i])
	_finish_oath(who)
	_push({"t": "oath", "who": who, "oath": "Foresight", "order": order.duplicate()})
	return true


## Raid trades a visible table card for the deck's original top card. The deck
## must already have a replacement; burying first in an empty deck would allow
## the same card to be drawn back and incorrectly spend Favor.
func can_use_raid(who: int) -> bool:
	return can_use_oath(who) and not deck.is_empty() and not visible_table(who).is_empty()


func use_raid(who: int, table_card: int) -> bool:
	if not can_use_raid(who) or not visible_table(who).has(table_card):
		return false
	var idx: int = table.find(table_card)
	var replacement: int = deck.pop_back()
	table[idx] = replacement
	deck.push_front(table_card)
	if table_card == veiled:
		veiled = -1
	_finish_oath(who)
	_push({"t": "oath", "who": who, "oath": "Raid", "banished": table_card, "replacement": replacement})
	return true


func use_diplomacy(who: int, hand_card: int, table_card: int) -> bool:
	if not can_use_oath(who):
		return false
	if not hands[who].has(hand_card) or not visible_table(who).has(table_card):
		return false
	hands[who].erase(hand_card)
	table.erase(table_card)
	hands[who].append(table_card)
	table.append(hand_card)
	_finish_oath(who)
	_push({"t": "oath", "who": who, "oath": "Diplomacy", "given": hand_card, "taken": table_card})
	return true


func _finish_oath(who: int) -> void:
	favor[who] -= 1
	oath_used[who] = true


# ---------------------------------------------------------------------------
# END OF HAND / SCORING
# ---------------------------------------------------------------------------
func _end_hand() -> void:
	if hand_over:
		return
	hand_over = true
	# The normal final-table award would falsely satisfy puzzle objectives with
	# cards the player never captured. Leave the puzzle table as played.
	if last_capturer >= 0 and puzzle.is_empty():
		for c in table:
			captured[last_capturer].append(c)
			if last_capturer == 0:
				_track_capture(0, c)
		table = []
	_push({"t": "sweep_rest", "who": last_capturer})

	var score := score_hand()
	renown[0] += score.points[0]
	renown[1] += score.points[1]
	hands_played += 1
	_eval_quests(score)
	_push({"t": "hand_end", "score": score})

	if _match_finished():
		match_over = true
		_push({"t": "match_end", "winner": winner()})


func _faction_ability(who: int) -> String:
	return T.FACTIONS[player_faction if who == 0 else bot_faction].ability


func score_hand() -> Dictionary:
	var p0: Array = captured[0]
	var p1: Array = captured[1]
	var pts := [0, 0]
	var loot := _winner_of(p0.size(), p1.size(), _tie_owner("loot"))
	var forge0 := _count_faction(p0, T.FORGE)
	var forge1 := _count_faction(p1, T.FORGE)
	if campaign.get("twist_kind", "") == "vault":
		forge1 *= 2
	var treasury := _winner_of(forge0, forge1, _tie_owner("treasury"))
	var prim0 := primiera_total(p0)
	var prim1 := primiera_total(p1)
	var banner := _winner_of(prim0, prim1, _tie_owner("banner"))
	var rs := -1
	if p0.has(C.make(7, T.RUNESTONE_SUIT)):
		rs = 0
	if p1.has(C.make(7, T.RUNESTONE_SUIT)):
		rs = -1 if rs == 0 else 1

	if loot >= 0:
		pts[loot] += 1
	if treasury >= 0:
		pts[treasury] += 1
	if rs >= 0:
		pts[rs] += 1
	if banner >= 0:
		pts[banner] += 1
	pts[0] += scopa_count[0]
	pts[1] += scopa_count[1]

	return {
		"loot": loot, "treasury": treasury, "banner": banner, "runestone": rs,
		"cards": [p0.size(), p1.size()],
		"forge": [forge0, forge1],
		"primiera": [prim0, prim1],
		"scopa": [scopa_count[0], scopa_count[1]],
		"points": pts,
	}


## Who wins a tie?  Returns -1 (nobody) unless a faction/campaign rule claims it.
func _tie_owner(which: String) -> int:
	if which == "banner":
		if campaign.get("twist_kind", "") == "banner":
			return 1
		if _faction_ability(1) == "banner_tie":
			return 1
		if _faction_ability(0) == "banner_tie":
			return 0
	if which == "loot" or which == "treasury":
		# Orcs never lose a tie: they keep the table on a draw
		if _faction_ability(0) == "never_lose" and _faction_ability(1) != "never_lose":
			return 0
		if _faction_ability(1) == "never_lose" and _faction_ability(0) != "never_lose":
			return 1
	return -1


func _winner_of(a: int, b: int, tie_owner: int) -> int:
	if a == b:
		return tie_owner
	return 0 if a > b else 1


func _count_faction(arr: Array, f: int) -> int:
	var n := 0
	for c in arr:
		if C.faction(c) == f:
			n += 1
	return n


func primiera_total(arr: Array) -> int:
	var best := [0, 0, 0, 0]
	for c in arr:
		var f := C.faction(c)
		best[f] = maxi(best[f], C.primiera(c))
	var tot := 0
	for v in best:
		tot += v
	return tot


func _eval_quests(score: Dictionary) -> void:
	for i in range(quests.size()):
		if quest_done[i]:
			continue
		var q: Dictionary = quests[i]
		var ok := false
		match q.key:
			"runestone":
				ok = stat["runestone"]
			"double_scopa":
				ok = stat["scopas"] >= 2
			"grove_most":
				ok = _count_faction(captured[0], T.GROVE) > _count_faction(captured[1], T.GROVE)
			"banner":
				ok = score.banner == 0
			"horde_three":
				ok = stat["horde"] >= 3
			"scopetta":
				ok = stat["fools"] >= 1
			"sevens":
				ok = stat["7s"] >= 3
			"sweep_all":
				ok = _count_faction(captured[0], T.FORGE) >= 6
		if ok:
			quest_done[i] = true
			renown[0] += q.reward
			_push({"t": "quest", "quest": q.key, "reward": q.reward})


func _match_finished() -> bool:
	if mode != T.Mode.RANKED:
		return true
	if renown[0] >= T.MODE_INFO[T.Mode.RANKED].target or renown[1] >= T.MODE_INFO[T.Mode.RANKED].target:
		return true
	return hands_played >= 3


func winner() -> int:
	if not puzzle.is_empty():
		return 0
	if renown[0] > renown[1]:
		return 0
	if renown[1] > renown[0]:
		return 1
	return -1


func next_hand() -> void:
	if match_over:
		return
	hand_no += 1
	starter = 1 - starter
	start_hand()


func _roll_quests() -> Array:
	var pool: Array = T.QUESTS.duplicate()
	var out: Array = []
	for i in range(2):
		var idx := rng.randi() % pool.size()
		out.append(pool[idx])
		pool.remove_at(idx)
	return out


# ---------------------------------------------------------------------------
# SERIALISATION — lets a duel be saved mid-hand, resumed later, or handed to
# another device (the basis for async duels).
# ---------------------------------------------------------------------------
func to_dict() -> Dictionary:
	return {
		"version": 1, "mode": mode, "oaths": oaths_enabled, "rule": rule, "match_id": match_id,
		"player_faction": player_faction, "bot_faction": bot_faction,
		"campaign_id": campaign.get("id", ""), "puzzle_name": puzzle.get("name", ""),
		"deck": deck, "table": table, "hands": hands, "captured": captured,
		"scopa_count": scopa_count, "favor": favor, "oath_used": oath_used,
		"turn": turn, "starter": starter, "last_capturer": last_capturer,
		"hand_no": hand_no, "turn_count": turn_count, "renown": renown,
		"quest_keys": _quest_keys(), "quest_done": quest_done,
		"hand_over": hand_over, "match_over": match_over, "veiled": veiled,
		"hands_played": hands_played, "stat": stat,
		"player_sweeps": player_sweeps, "player_glory": player_glory,
		"rng_seed": str(rng.seed), "rng_state": str(rng.state),
	}


## Validate the persisted boundary before constructing a duel or reading nested fields.
static func valid_save(save: Variant) -> bool:
	if not (save is Dictionary) or not (save.get("state") is Dictionary):
		return false
	var d: Dictionary = save.state
	if not _int_in(d.get("version", 0), 0, 1):
		return false
	if not _int_in(d.get("mode"), 0, T.Mode.QUINDICI):
		return false
	for key in ["player_faction", "bot_faction"]:
		if not _int_in(d.get(key), 0, 3):
			return false
	for key in ["turn", "starter"]:
		if not _int_in(d.get(key), 0, 1):
			return false
	if not _int_in(d.get("last_capturer"), -1, 1) or not _int_in(d.get("veiled"), -1, C.DECK_SIZE - 1):
		return false
	for key in ["hand_no", "turn_count", "hands_played", "player_sweeps", "player_glory"]:
		if not _int_in(d.get(key, 0), 0, 1000):
			return false
	for key in ["hand_over", "match_over", "oaths"]:
		if not (d.get(key) is bool):
			return false
	if d.match_over and not d.hand_over:
		return false
	if d.get("rule", C.RULE_CLASSIC) not in [C.RULE_CLASSIC, C.RULE_QUINDICI]:
		return false
	for key in ["scopa_count", "favor", "renown", "oath_used", "quest_done"]:
		var values: Variant = d.get(key)
		if not (values is Array) or values.size() != 2:
			return false
		for value in values:
			if key in ["oath_used", "quest_done"]:
				if not (value is bool):
					return false
			elif not _int_in(value, 0, 1000):
				return false
	var piles: Array = [d.get("deck"), d.get("table")]
	for key in ["hands", "captured"]:
		var pair: Variant = d.get(key)
		if not (pair is Array) or pair.size() != 2:
			return false
		piles.append_array(pair)
	var seen := {}
	for pile in piles:
		if not (pile is Array):
			return false
		for card in pile:
			if not _int_in(card, 0, C.DECK_SIZE - 1) or seen.has(int(card)):
				return false
			seen[int(card)] = true
	if seen.size() != C.DECK_SIZE or (not d.hand_over and d.hands[int(d.turn)].is_empty()):
		return false
	var stat_data: Variant = d.get("stat")
	var quest_keys: Variant = d.get("quest_keys")
	if not (stat_data is Dictionary) or not (quest_keys is Array) or quest_keys.size() > 2:
		return false
	for key in ["7s", "horde", "forge", "scopas", "fools"]:
		if not _int_in(stat_data.get(key), 0, C.DECK_SIZE):
			return false
	if not (stat_data.get("runestone") is bool):
		return false
	if (int(d.mode) == T.Mode.CAMPAIGN) == saved_campaign(d).is_empty():
		return false
	if (int(d.mode) == T.Mode.PUZZLE) == saved_puzzle(d).is_empty():
		return false
	for key in ["rng_seed", "rng_state"]:
		var value: Variant = d.get(key, "0")
		if not (value is String and value.is_valid_int()) and not (value is int or value is float):
			return false
	if not (d.get("match_id", "") is String):
		return false
	return true


static func saved_campaign(state: Dictionary) -> Dictionary:
	for campaign_entry in T.CAMPAIGNS:
		if campaign_entry.id == state.get("campaign_id", ""):
			return campaign_entry
	return {}


static func saved_puzzle(state: Dictionary) -> Dictionary:
	for puzzle_entry in T.PUZZLES:
		if puzzle_entry.name == state.get("puzzle_name", ""):
			return puzzle_entry
	return {}


static func _int_in(value: Variant, minimum: int, maximum: int) -> bool:
	return (value is int or value is float) and value >= minimum and value <= maximum and value == int(value)


func from_dict(d: Dictionary) -> void:
	# JSON hands numbers back as floats; every card id, count and index here is
	# an int, so coerce on the way in.
	mode = int(d.get("mode", mode))
	oaths_enabled = bool(d.get("oaths", oaths_enabled))
	player_faction = int(d.get("player_faction", player_faction))
	bot_faction = int(d.get("bot_faction", bot_faction))
	match_id = str(d.get("match_id", JSON.stringify(d).sha256_text()))
	deck = _ints(d.get("deck", []))
	table = _ints(d.get("table", []))
	hands = _ints2(d.get("hands", [[], []]))
	captured = _ints2(d.get("captured", [[], []]))
	scopa_count = _ints(d.get("scopa_count", [0, 0]))
	favor = _ints(d.get("favor", [0, 0]))
	oath_used = d.get("oath_used", [false, false])
	turn = int(d.get("turn", 0))
	starter = int(d.get("starter", 0))
	last_capturer = int(d.get("last_capturer", -1))
	hand_no = int(d.get("hand_no", 0))
	turn_count = int(d.get("turn_count", 0))
	renown = _ints(d.get("renown", [0, 0]))
	quest_done = d.get("quest_done", [false, false])
	hand_over = bool(d.get("hand_over", false))
	match_over = bool(d.get("match_over", false))
	rule = String(d.get("rule", C.RULE_CLASSIC))
	veiled = int(d.get("veiled", -1))
	hands_played = int(d.get("hands_played", 0))
	stat = d.get("stat", {})
	for k in stat.keys():
		if k == "runestone":
			stat[k] = bool(stat[k])
		else:
			stat[k] = int(stat[k])
	player_sweeps = int(d.get("player_sweeps", stat.get("scopas", 0)))
	player_glory = int(d.get("player_glory", scopa_count[0]))
	rng.seed = int(d.get("rng_seed", rng.seed))
	if d.has("rng_state"):
		rng.state = int(d.rng_state)
	# rebuild quest dictionaries from their keys
	quests = []
	for k in d.get("quest_keys", []):
		for q in T.QUESTS:
			if q.key == k:
				quests.append(q)
				break
	events = []


func _ints(a) -> Array:
	var out: Array = []
	for v in a:
		out.append(int(v))
	return out


func _ints2(a) -> Array:
	var out: Array = []
	for row in a:
		out.append(_ints(row))
	return out


func _quest_keys() -> Array:
	var out: Array = []
	for q in quests:
		out.append(q.key)
	return out


func _push(ev: Dictionary) -> void:
	events.append(ev)


func drain_events() -> Array:
	var e := events
	events = []
	return e
