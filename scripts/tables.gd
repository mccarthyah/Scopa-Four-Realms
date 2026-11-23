extends RefCounted
# gdlint: disable=class-definitions-order
# Declarations here are grouped for readability (constants beside the tables
# they describe, fields beside the build code that fills them) rather than
# strictly consts-before-vars. Ordering is a style rule with no runtime effect;
# see docs/ASSESSMENT.md.

## Static game tables: factions, ranks, Oaths, quests, campaigns and puzzles.
## Everything theme-facing lives here so the rules engine stays pure.

# ---------------------------------------------------------------------------
# FACTIONS  (index order matters: it is used by card ids and capture logic)
# ---------------------------------------------------------------------------
const FORGE := 0
const GROVE := 1
const HORDE := 2
const CROWN := 3

const FACTIONS := [
	{
		"id": "forge",
		"name": "Forge",
		"people": "Dwarves",
		"color": Color("d9743a"),
		"deep": Color("4a2a1c"),
		"pale": Color("f0b98a"),
		"suit": "Coins",
		"oath": "Deep Delve",
		"oath_short": "Draw, then bury a card",
		"oath_long": "Draw the top card of the deck, then put one card from your hand on the bottom of the deck.",
		"ability": "treasury",
		"boast": "Every forge coin counts double in the treasury.",
	},
	{
		"id": "grove",
		"name": "Grove",
		"people": "Elves",
		"color": Color("5fae68"),
		"deep": Color("1e3d29"),
		"pale": Color("b9e6b0"),
		"suit": "Cups",
		"oath": "Foresight",
		"oath_short": "Reorder the top 3 cards",
		"oath_long": "Look at the top three cards of the deck and put them back in any order you choose.",
		"ability": "peek",
		"boast": "Elves see the draws before they happen.",
	},
	{
		"id": "horde",
		"name": "Horde",
		"people": "Orcs",
		"color": Color("b8453f"),
		"deep": Color("3d1a1a"),
		"pale": Color("eda79a"),
		"suit": "Swords",
		"oath": "Raid",
		"oath_short": "Replace a table card",
		"oath_long": "Put a table card on the bottom of the deck and replace it with the top card. No capture or sweep. Requires a card in the deck.",
		"ability": "never_lose",
		"boast": "Orcs never lose a tie on the table.",
	},
	{
		"id": "crown",
		"name": "Crown",
		"people": "Humans",
		"color": Color("c9a24a"),
		"deep": Color("463314"),
		"pale": Color("f6e2a8"),
		"suit": "Batons",
		"oath": "Diplomacy",
		"oath_short": "Swap a hand and table card",
		"oath_long": "Swap one card from your hand with one card on the table. No capture is triggered.",
		"ability": "banner_tie",
		"boast": "Humans win Banner ties, and hold the table on a draw.",
	},
]

const SUIT_GLYPH := ["⛭", "❧", "⚔", "♛"]

# ---------------------------------------------------------------------------
# RANKS
# ---------------------------------------------------------------------------
const RANK_NAMES := [
	"Fool", "Seer", "Smith", "Warden", "Healer", "Knight",
	"Queen", "King", "Mage", "Dragon",
]

const RANK_GLYPH_CROWN := "♛"
const RANK_GLYPH_HORDE := "⚔"
const RUNESTONE_SUIT := FORGE
const RUNESTONE_RANK := 7

# Primiera values (classic Scopa: 7 = 21, 6 = 18, ace = 16, face cards = 10)
const PRIMIERA := [16, 12, 13, 14, 15, 18, 21, 10, 10, 10]

const POINT_NAMES := ["Loot", "Treasury", "Runestone", "Banner", "Glory"]

# ---------------------------------------------------------------------------
# QUESTS
# ---------------------------------------------------------------------------
const QUESTS := [
	{"key": "runestone", "name": "Claim the Runestone", "desc": "Capture the 7 of Forge.", "reward": 1},
	{"key": "double_scopa", "name": "Two Sweeps", "desc": "Make two sweeps.", "reward": 1},
	{"key": "grove_most", "name": "Grove Tribute", "desc": "Win most Grove cards.", "reward": 1},
	{"key": "banner", "name": "Raise the Banner", "desc": "Finish with the best Banner total.", "reward": 1},
	{"key": "horde_three", "name": "Horde Raid", "desc": "Capture three Horde cards.", "reward": 1},
	{"key": "scopetta", "name": "Fool's Errand", "desc": "Capture the 1 of any faction.", "reward": 1},
	{"key": "sevens", "name": "Lucky Sevens", "desc": "Capture three cards of rank 7.", "reward": 1},
	{"key": "sweep_all", "name": "Empty Halls", "desc": "Capture every Forge card.", "reward": 1},
]

# ---------------------------------------------------------------------------
# MATCH MODES
# ---------------------------------------------------------------------------
## QUINDICI is a ruleset variant, not a different kind of match: same deck, same
## Oaths, same scoring - only the capture rule changes.  Variants are chosen per
## match and never mixed inside one.
enum Mode { QUICK, RANKED, CAMPAIGN, PUZZLE, QUINDICI }

const MODE_INFO := {
	Mode.QUICK: {
		"name": "Quick Duel",
		"blurb": "One hand. Oaths on. ~4 minutes.",
		"oaths": true, "hands": 1, "target": 0,
	},
	Mode.RANKED: {
		"name": "Ranked Duel",
		"blurb": "Best of three hands, first to 11 Renown.",
		"oaths": true, "hands": 3, "target": 11,
	},
	Mode.CAMPAIGN: {
		"name": "Campaign",
		"blurb": "Fight fantasy AI with a twist per boss.",
		"oaths": true, "hands": 1, "target": 0,
	},
	Mode.PUZZLE: {
		"name": "Daily Puzzle",
		"blurb": "A fixed deal. Hit the goal in time.",
		"oaths": false, "hands": 1, "target": 0,
	},
	Mode.QUINDICI: {
		"name": "Fifteen Duel",
		"blurb": "Only combinations totalling 15 capture. Never take your own value.",
		"oaths": true, "hands": 1, "target": 0,
	},
}

# ---------------------------------------------------------------------------
# CAMPAIGN CHAPTERS
# ---------------------------------------------------------------------------
const CAMPAIGNS := [
	{
		"id": "grove_warden",
		"name": "The Veiled Warden",
		"faction": GROVE,
		"title": "Grove Boss · Hides a table card",
		"twist": "Foresight: one table card stays hidden from you, just as he sees the deck.",
		"twist_kind": "hidden_table",
		"reveal": 3.0,
		"ai": "greedy",
		"quote": "The Grove does not hide the path. It hides the stones you trip on.",
	},
	{
		"id": "horde_warlord",
		"name": "Grasha Ironjaw",
		"faction": HORDE,
		"title": "Horde Boss · Demands aggression",
		"twist": "Raid Fury: from turn six, every sweep she makes scores 2 Glory.",
		"twist_kind": "fury",
		"reveal": 0.0,
		"ai": "aggressive",
		"quote": "Pick up the table or die staring at it.",
	},
	{
		"id": "forge_thane",
		"name": "Thane Brund",
		"faction": FORGE,
		"title": "Forge Boss · Double treasure",
		"twist": "Vault: his Forge cards are worth double in the Treasury count.",
		"twist_kind": "vault",
		"reveal": 0.0,
		"ai": "primiera",
		"quote": "Gold remembers every hand that touched it.",
	},
	{
		"id": "crown_regent",
		"name": "Regent Aurelia",
		"faction": CROWN,
		"title": "Crown Boss · Best Banner",
		"twist": "Banner: she wins the Banner even on a Banner tie, but only holds 6 Favor.",
		"twist_kind": "banner",
		"reveal": 0.0,
		"ai": "smart",
		"quote": "The crown is not won with swords. It is won before the swords come out.",
	},
]

# ---------------------------------------------------------------------------
# PUZZLES  — fixed deals with a fixed goal.  Cards are written as [rank, faction]
# so the deals read like the table does; the engine converts them to card ids and
# builds the remaining deck automatically.
# ---------------------------------------------------------------------------
const PUZZLES := [
	{
		"name": "Sweep the Hall",
		"goal": "scopa",
		"moves": 3,
		"desc": "Empty the table for a sweep in three moves.",
		"table": [[10, 3], [5, 1], [3, 2], [2, 0]],
		"hand": [[10, 0], [5, 2], [5, 0]],
		"hint": "The 10 must be taken by a 10 — the 3 and 2 will add up to a 5.",
	},
	{
		"name": "Gather the Runestone",
		"goal": "runestone",
		"moves": 2,
		"desc": "Capture the Runestone — the 7 of Forge — in two moves.",
		"table": [[7, 0], [3, 3], [4, 1], [6, 2], [2, 2]],
		"hand": [[7, 1], [10, 0], [2, 0]],
		"hint": "The Runestone can only fall to a 7, never to a sum. Taking 3 and 4 instead leaves it lying there.",
	},
	{
		"name": "Golden Banner",
		"goal": "primiera",
		"moves": 3,
		"desc": "Hoard the 7s. Finish with a Banner total over 40.",
		"table": [[7, 1], [7, 2], [4, 0], [2, 3]],
		"hand": [[7, 0], [7, 3], [3, 2]],
		"hint": "Banner totals your best card in each faction — a 7 is worth 21.",
	},
]


# ---------------------------------------------------------------------------
# SHARED LOOKUPS
# One definition each, used by both the engine and the duel screen. These used
# to exist twice: game/duel.gd counted a faction one way and screens/duel.gd
# counted it again in its own copy, so a rules change could make the pile view
# disagree with the score sheet about the same pile.
# ---------------------------------------------------------------------------
## How many cards of faction `f` are in `arr`.
static func count_faction(arr: Array, f: int) -> int:
	var n := 0
	for c in arr:
		if Cards.faction(c) == f:
			n += 1
	return n


## The quest table entry for `key`, or {} if it drifted. Returning {} rather
## than a fabricated {"name": key, "reward": 1} matters: the old fallback
## invented a quest with a made-up reward, so a bad key silently scored points.
static func quest_by_key(key: String) -> Dictionary:
	for q in QUESTS:
		if q.key == key:
			return q
	return {}
