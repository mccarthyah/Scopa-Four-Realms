extends Node
## Local profile: stats, settings and the daily-puzzle rotation.  Saved to
## user://four_realms_profile.json so progress survives between sessions.

const T := preload("res://scripts/tables.gd")
const SAVE_PATH := "user://four_realms_profile.json"
const DUEL_PATH := "user://four_realms_duel.json"

var matches := 0
var wins := 0
var losses := 0
var draws := 0
var best_renown := 0
var total_glory := 0
var scopas := 0
var quests_done := 0
var puzzles_solved := 0
var campaign_cleared: Array = []
var classic_mode := false
var seen_intro := false
var card_back := 0
var board_theme := 0
var last_puzzle_date := ""
var last_puzzle_won := false
var saved_duel := {}
var _duel_cache := {}
var faction_wins := {0: 0, 1: 0, 2: 0, 3: 0}
var faction_plays := {0: 0, 1: 0, 2: 0, 3: 0}


func _ready() -> void:
	load_profile()


func load_profile() -> void:
	if not FileAccess.file_exists(SAVE_PATH):
		return
	var f := FileAccess.open(SAVE_PATH, FileAccess.READ)
	if f == null:
		return
	var txt := f.get_as_text()
	f.close()
	var d = JSON.parse_string(txt)
	if typeof(d) != TYPE_DICTIONARY:
		return
	matches = d.get("matches", 0)
	wins = d.get("wins", 0)
	losses = d.get("losses", 0)
	draws = d.get("draws", 0)
	best_renown = d.get("best_renown", 0)
	total_glory = d.get("total_glory", 0)
	scopas = d.get("scopas", 0)
	quests_done = d.get("quests_done", 0)
	puzzles_solved = d.get("puzzles_solved", 0)
	campaign_cleared = d.get("campaign_cleared", [])
	classic_mode = d.get("classic_mode", false)
	seen_intro = d.get("seen_intro", false)
	card_back = d.get("card_back", 0)
	board_theme = d.get("board_theme", 0)
	last_puzzle_date = d.get("last_puzzle_date", "")
	last_puzzle_won = d.get("last_puzzle_won", false)
	# JSON turns dictionary keys into strings, so map them back to ints
	for k in d.get("faction_wins", {}):
		faction_wins[int(k)] = int(d.faction_wins[k])
	for k in d.get("faction_plays", {}):
		faction_plays[int(k)] = int(d.faction_plays[k])


func save_profile() -> void:
	var d := {
		"matches": matches, "wins": wins, "losses": losses, "draws": draws,
		"best_renown": best_renown, "total_glory": total_glory, "scopas": scopas,
		"quests_done": quests_done, "puzzles_solved": puzzles_solved,
		"campaign_cleared": campaign_cleared, "classic_mode": classic_mode,
		"seen_intro": seen_intro, "card_back": card_back, "board_theme": board_theme,
		"last_puzzle_date": last_puzzle_date, "last_puzzle_won": last_puzzle_won,
		"faction_wins": faction_wins, "faction_plays": faction_plays,
	}
	var f := FileAccess.open(SAVE_PATH, FileAccess.WRITE)
	if f == null:
		return
	f.store_string(JSON.stringify(d, "  "))
	f.close()


func record_match(won: bool, draw: bool, renown_for: int, glory: int, scopa_total: int, faction: int, quests: int) -> void:
	matches += 1
	if draw:
		draws += 1
	elif won:
		wins += 1
		faction_wins[faction] = faction_wins.get(faction, 0) + 1
	else:
		losses += 1
	faction_plays[faction] = faction_plays.get(faction, 0) + 1
	best_renown = maxi(best_renown, renown_for)
	total_glory += glory
	scopas += scopa_total
	quests_done += quests
	save_profile()


func today_key() -> String:
	return Time.get_date_string_from_system()


## Which puzzle is live today (stable across the day, changes at midnight).
func daily_puzzle_index() -> int:
	var k := today_key()
	var h := 0
	for ch in k:
		h = (h * 31 + ch.unicode_at(0)) % 100000
	return h % T.PUZZLES.size()


func puzzle_done_today() -> bool:
	return last_puzzle_date == today_key() and last_puzzle_won


func mark_puzzle_solved(won: bool) -> void:
	last_puzzle_date = today_key()
	last_puzzle_won = won
	save_profile()


## --- interrupted-duel support (also the basis for async duels) -------------
func store_duel(state: Dictionary) -> void:
	saved_duel = state
	_duel_cache = state
	var f := FileAccess.open(DUEL_PATH, FileAccess.WRITE)
	if f == null:
		return
	f.store_string(JSON.stringify(state))
	f.close()


func clear_duel() -> void:
	saved_duel = {}
	_duel_cache = {}
	if FileAccess.file_exists(DUEL_PATH):
		DirAccess.remove_absolute(ProjectSettings.globalize_path(DUEL_PATH))


func has_saved_duel() -> bool:
	if saved_duel.is_empty():
		_load_duel_file()
	return not saved_duel.is_empty() and saved_duel.get("state", {}).size() > 0


func _load_duel_file() -> void:
	if not FileAccess.file_exists(DUEL_PATH):
		return
	var f := FileAccess.open(DUEL_PATH, FileAccess.READ)
	if f == null:
		return
	var txt := f.get_as_text()
	f.close()
	var d = JSON.parse_string(txt)
	if typeof(d) == TYPE_DICTIONARY:
		saved_duel = d
