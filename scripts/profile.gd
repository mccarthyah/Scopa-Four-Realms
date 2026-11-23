extends Node
# gdlint: disable=class-definitions-order
# Declarations here are grouped for readability (constants beside the tables
# they describe, fields beside the build code that fills them) rather than
# strictly consts-before-vars. Ordering is a style rule with no runtime effect;
# see docs/ASSESSMENT.md.

## Local profile: stats, settings and the daily-puzzle rotation.  Saved to
## user://four_realms_profile.json so progress survives between sessions.

signal orientation_changed(value: String)

const T := preload("res://scripts/tables.gd")
const DuelRules := preload("res://scripts/game/duel.gd")
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
var confirm_card_play := false
## Auto follows the window/device; left/right are device orientations on mobile.
var orientation := "auto"
var _orientation_correction_queued := false
## Presentation settings.  Animations are purely cosmetic: the game is fully
## playable with every one of them off.
var anim_enabled := true
var anim_spin := true
var anim_slow := true
var anim_match := true
var seen_intro := false
var card_back := 0
var board_theme := 0
var last_puzzle_date := ""
var last_puzzle_won := false
var saved_duel := {}
var last_recorded_match := ""
var faction_wins := {0: 0, 1: 0, 2: 0, 3: 0}
var faction_plays := {0: 0, 1: 0, 2: 0, 3: 0}


func _ready() -> void:
	load_profile()
	get_window().size_changed.connect(_on_window_size_changed)
	call_deferred("apply_orientation")


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
	confirm_card_play = bool(d.get("confirm_card_play", false))
	orientation = str(d.get("orientation", "auto"))
	if orientation not in ["auto", "landscape_left", "landscape_right", "portrait"]:
		orientation = "auto"
	seen_intro = d.get("seen_intro", false)
	card_back = d.get("card_back", 0)
	board_theme = d.get("board_theme", 0)
	anim_enabled = bool(d.get("anim_enabled", true))
	anim_spin = bool(d.get("anim_spin", true))
	anim_slow = bool(d.get("anim_slow", true))
	anim_match = bool(d.get("anim_match", true))
	last_puzzle_date = d.get("last_puzzle_date", "")
	last_puzzle_won = d.get("last_puzzle_won", false)
	last_recorded_match = str(d.get("last_recorded_match", ""))
	# JSON turns dictionary keys into strings, so map them back to ints
	for k in d.get("faction_wins", {}):
		faction_wins[int(k)] = int(d.faction_wins[k])
	for k in d.get("faction_plays", {}):
		faction_plays[int(k)] = int(d.faction_plays[k])


func save_profile() -> bool:
	var d := {
		"matches": matches, "wins": wins, "losses": losses, "draws": draws,
		"best_renown": best_renown, "total_glory": total_glory, "scopas": scopas,
		"quests_done": quests_done, "puzzles_solved": puzzles_solved,
		"campaign_cleared": campaign_cleared, "classic_mode": classic_mode,
		"confirm_card_play": confirm_card_play,
		"orientation": orientation,
		"seen_intro": seen_intro, "card_back": card_back, "board_theme": board_theme,
		"anim_enabled": anim_enabled, "anim_spin": anim_spin,
		"anim_slow": anim_slow, "anim_match": anim_match,
		"last_puzzle_date": last_puzzle_date, "last_puzzle_won": last_puzzle_won,
		"faction_wins": faction_wins, "faction_plays": faction_plays,
		"last_recorded_match": last_recorded_match,
	}
	return _write_json(SAVE_PATH, d)


func _write_json(path: String, data: Dictionary) -> bool:
	var temporary := path + ".tmp"
	var file := FileAccess.open(temporary, FileAccess.WRITE)
	if file == null:
		return false
	file.store_string(JSON.stringify(data))
	file.flush()
	var written := file.get_error() == OK
	file.close()
	return written and DirAccess.rename_absolute(temporary, path) == OK


## Mobile uses the OS orientation sensor. Desktop cannot rotate an individual
## window, so forced modes instead make the window portrait/landscape shaped.
func set_orientation(value: String) -> void:
	if value not in ["auto", "landscape_left", "landscape_right", "portrait"]:
		return
	orientation = value
	save_profile()
	apply_orientation()
	orientation_changed.emit(value)


func apply_orientation() -> void:
	# Browsers control their own windows; Godot's desktop window resizing APIs
	# are not a reliable way to lock a browser or a mobile web page.
	if OS.has_feature("web"):
		return
	# Desktop must resize its own window, even if a driver advertises screen
	# orientation. Never ask Windows to rotate the user's entire display.
	var mobile := OS.get_name() in ["Android", "iOS"]
	if mobile and DisplayServer.has_feature(DisplayServer.FEATURE_ORIENTATION):
		var mode := DisplayServer.SCREEN_SENSOR
		match orientation:
			"portrait": mode = DisplayServer.SCREEN_PORTRAIT
			"landscape_left": mode = DisplayServer.SCREEN_LANDSCAPE
			"landscape_right": mode = DisplayServer.SCREEN_REVERSE_LANDSCAPE
		DisplayServer.screen_set_orientation(mode)
		return
	if mobile or DisplayServer.get_name() == "headless" or orientation == "auto":
		return
	# Godot embeds the running game inside its editor by default on some
	# versions. The OS forbids resizing that child window; the Settings UI
	# explains how to run it detached instead of silently doing nothing.
	if Engine.is_embedded_in_editor():
		print("[four-realms] Orientation: embedded editor window cannot be resized; disable Embed Game and restart.")
		return
	_resize_desktop_window.call_deferred(orientation)


func _resize_desktop_window(requested: String) -> void:
	if orientation != requested or orientation == "auto" or Engine.is_embedded_in_editor():
		return
	# A maximized/fullscreen window cannot be resized until windowed. Centre the
	# new shape inside the monitor's usable area, with room for window chrome.
	var window := get_window()
	if window == null:
		return
	if window.mode != Window.MODE_WINDOWED:
		window.mode = Window.MODE_WINDOWED
		# Let the OS complete the restore before attempting to resize.
		await get_tree().process_frame
		await get_tree().process_frame
		if orientation != requested or not is_instance_valid(window):
			return
	var screen: int = DisplayServer.window_get_current_screen()
	var usable: Rect2i = DisplayServer.screen_get_usable_rect(screen)
	var bounds := Vector2i(maxi(usable.size.x - 32, 320), maxi(usable.size.y - 80, 240))
	var landscape: bool = orientation != "portrait"
	var desired := Vector2(960, 540) if landscape else Vector2(540, 960)
	var scale_factor := minf(1.0, minf(float(bounds.x) / desired.x, float(bounds.y) / desired.y))
	var target := Vector2i(desired * scale_factor)
	window.size = target
	window.position = usable.position + (usable.size - target) / 2
	print("[four-realms] Orientation ", requested, ": requested window ", target, "; actual ", window.size)


## On desktop keep a forced shape even if the user drags the window past square.
## Auto never interferes with manual resizing. Mobile is controlled by the OS.
func _on_window_size_changed() -> void:
	if _orientation_correction_queued or orientation == "auto" or OS.has_feature("web") or DisplayServer.get_name() == "headless" or OS.get_name() in ["Android", "iOS"] or Engine.is_embedded_in_editor():
		return
	_orientation_correction_queued = true
	_correct_window_shape.call_deferred()


func _correct_window_shape() -> void:
	_orientation_correction_queued = false
	# The preference or window mode may have changed since the resize event.
	if orientation == "auto" or OS.get_name() in ["Android", "iOS"] or Engine.is_embedded_in_editor():
		return
	var window := get_window()
	if window == null or window.mode != Window.MODE_WINDOWED:
		return
	var sz := window.size
	var landscape: bool = orientation != "portrait"
	# Keep enough aspect difference for the corresponding responsive layout,
	# even while a user drags the window close to square.
	if (landscape and float(sz.x) >= float(sz.y) * 1.2) or (not landscape and float(sz.y) >= float(sz.x) * 1.2):
		return
	var usable: Rect2i = DisplayServer.screen_get_usable_rect(DisplayServer.window_get_current_screen())
	var bounds := Vector2i(maxi(usable.size.x - 32, 320), maxi(usable.size.y - 80, 240))
	var short_side: float = float(mini(sz.x, sz.y))
	var long_side: float = maxf(float(maxi(sz.x, sz.y)), short_side * 1.2)
	var target := Vector2(long_side, short_side) if landscape else Vector2(short_side, long_side)
	var factor := minf(1.0, minf(float(bounds.x) / target.x, float(bounds.y) / target.y))
	window.size = Vector2i(target * factor)


func record_match(won: bool, draw: bool, renown_for: int, glory: int, scopa_total: int, faction: int, quests: int, match_id: String = "", campaign_id: String = "", puzzle_result: int = -1) -> bool:
	if match_id != "" and match_id == last_recorded_match:
		return save_profile()
	last_recorded_match = match_id
	if won and campaign_id != "" and not campaign_cleared.has(campaign_id):
		campaign_cleared.append(campaign_id)
	if puzzle_result == 1 and not puzzle_done_today():
		puzzles_solved += 1
		last_puzzle_date = today_key()
		last_puzzle_won = true
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
	return save_profile()


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
	saved_duel = state.duplicate(true)
	if not _write_json(DUEL_PATH, saved_duel):
		push_warning("Could not save the duel to disk.")


func clear_duel() -> void:
	saved_duel = {}
	if FileAccess.file_exists(DUEL_PATH):
		DirAccess.remove_absolute(ProjectSettings.globalize_path(DUEL_PATH))


func has_saved_duel() -> bool:
	if saved_duel.is_empty():
		_load_duel_file()
	return DuelRules.valid_save(saved_duel)


func _load_duel_file() -> void:
	if not FileAccess.file_exists(DUEL_PATH):
		return
	var f := FileAccess.open(DUEL_PATH, FileAccess.READ)
	if f == null:
		return
	var txt := f.get_as_text()
	f.close()
	var d = JSON.parse_string(txt)
	if DuelRules.valid_save(d):
		saved_duel = d
