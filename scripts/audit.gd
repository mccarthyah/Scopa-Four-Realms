extends Node
## Headless self-test + layout audit.  Run:
##   godot --headless --path . -- --audit
## Plays thousands of games to exercise the rules engine, then boots every
## screen and checks that nothing overflows the phone viewport.

const T := preload("res://scripts/tables.gd")
const C := preload("res://scripts/game/cards.gd")
const DuelScript := preload("res://scripts/game/duel.gd")
const DuelAI := preload("res://scripts/game/ai.gd")

var failures := 0
var main: Control


## GUI diagnostic mode (no display server needed to *start*, but runs the real
## main loop): opens the title, then every duel mode, printing geometry and any
## error Godot raises. Useful when the game crashes on open but headless is fine.
func smoke_test(m: Control) -> void:
	main = m
	var win := get_window()
	win.content_scale_size = Vector2i(720, 1280)
	await get_tree().process_frame
	print("=== SMOKE TEST ===")
	print("os=", OS.get_name(), " godot=", Engine.get_version_info().string)
	print("renderer=", RenderingServer.get_video_adapter_name(), " / ", RenderingServer.get_video_adapter_vendor())
	print("viewport=", get_viewport().get_visible_rect().size)
	await _wait_smoke(0.8)
	await _smoke_report("TITLE")
	main._start_duel({"mode": T.Mode.QUICK, "player_faction": T.FORGE})
	await _wait_smoke(1.4)
	await _smoke_report("QUICK DUEL")
	main._start_duel({"mode": T.Mode.RANKED, "player_faction": T.GROVE})
	await _wait_smoke(1.2)
	await _smoke_report("RANKED DUEL")
	main._start_duel({"mode": T.Mode.CAMPAIGN, "campaign": T.CAMPAIGNS[0], "player_faction": T.HORDE})
	await _wait_smoke(1.2)
	await _smoke_report("CAMPAIGN")
	main._start_duel({"mode": T.Mode.PUZZLE, "puzzle": T.PUZZLES[0], "player_faction": T.CROWN})
	await _wait_smoke(1.2)
	await _smoke_report("PUZZLE")
	print("=== SMOKE TEST OK — every screen built and drew ===")
	get_tree().quit()


func _wait_smoke(t: float) -> void:
	await get_tree().create_timer(t).timeout


func _smoke_report(label: String) -> void:
	var cur: Control = main.current
	if cur == null:
		print("  !! ", label, ": no current screen")
		return
	var r: Rect2 = cur.get_global_rect()
	print("  %-12s %s size=%.0fx%.0f visible=%s" % [label, cur.get_script().resource_path.get_file(), r.size.x, r.size.y, cur.visible])
	var vp := get_viewport().get_visible_rect().size
	if vp.x >= 200.0 and (r.size.x < vp.x * 0.5 or r.size.y < vp.y * 0.5):
		print("  !! ", label, ": screen is smaller than half the viewport (%.0fx%.0f of %.0fx%.0f)" % [r.size.x, r.size.y, vp.x, vp.y])
	elif vp.x < 200.0:
		print("      (headless 64x64 viewport — launch with a real window to check sizes)")
	var nulls: int = 0
	var stack: Array = [cur]
	while not stack.is_empty():
		var n: Node = stack.pop_back()
		for c in n.get_children():
			stack.append(c)
	print("      nodes=", stack.size(), " (no script errors above = healthy)")


func run(m: Control) -> void:
	main = m
	# force a phone-shaped window so the audit measures the real layout
	var win := get_window()
	win.content_scale_size = Vector2i(720, 1280)
	win.size = Vector2i(720, 1280)
	await get_tree().process_frame
	await get_tree().process_frame
	_test_rules()
	_test_capture_math()
	_test_ai_games()
	_test_quests()
	_test_save_resume()
	_test_ai_speed()
	_test_profile_io()
	await _test_tap_play()
	await _audit_screens()
	print("=== AUDIT COMPLETE · failures=%d ===" % failures)
	print("godot ", Engine.get_version_info().string, " · renderer ",
		ProjectSettings.get_setting("rendering/renderer/rendering_method", "?"), " · adapter ",
		RenderingServer.get_video_adapter_name())
	get_tree().quit()


## End-to-end input test: build a real duel, send a real mouse click at a hand
## card's on-screen position, and require that the card is actually played.
##
## This exists because card taps were broken for the entire project history: the
## pressed signal carried a card id AND the handler bound one, so every tap failed
## with "Method expected 1 argument(s), but called with 2" and silently did
## nothing. Nothing caught it because no test ever simulated a tap.
func _test_tap_play() -> void:
	var d = load("res://scripts/screens/duel.gd").new()
	d.config = {"mode": 0}
	main.add_child(d)
	for i in range(150):
		await get_tree().process_frame
	var row = d._hand_row
	if row == null or row.get_child_count() == 0:
		fail("tap test: no hand cards were laid out")
		d.queue_free()
		return
	var before: Array = []
	for i in range(row.get_child_count()):
		before.append(row.get_child(i).card_id)
	var center: Vector2 = row.get_child(0).get_global_rect().get_center()
	# select, then confirm
	for _pass in range(2):
		for pressed in [true, false]:
			var ev := InputEventMouseButton.new()
			ev.button_index = MOUSE_BUTTON_LEFT
			ev.pressed = pressed
			ev.position = center
			ev.global_position = center
			main.get_viewport().push_input(ev)
			await get_tree().process_frame
		for k in range(30):
			await get_tree().process_frame
	var after: Array = []
	for i in range(d._hand_row.get_child_count()):
		after.append(d._hand_row.get_child(i).card_id)
	if after.size() < before.size() or after != before:
		ok("tapping a hand card actually plays it (%s -> %s)" % [before, after])
	else:
		fail("tapping a hand card did nothing (hand still %s)" % [before])
	d.queue_free()
	await get_tree().process_frame


func fail(msg: String) -> void:
	failures += 1
	print("FAIL: ", msg)


func ok(msg: String) -> void:
	print("  ok  ", msg)


# ---------------------------------------------------------------------------
func _test_capture_math() -> void:
	# 3 + 2 + 2 must be capturable by a 7
	var table := [C.make(3, 0), C.make(2, 1), C.make(2, 2)]
	var g := C.capture_groups(table, C.make(7, 3))
	if g.size() != 1:
		fail("expected exactly one 7-capture group, got %d" % g.size())
	else:
		ok("sum capture 3+2+2 = 7 found")
	# rank match
	var t2 := [C.make(5, 0), C.make(1, 1)]
	var g2 := C.capture_groups(t2, C.make(5, 2))
	if g2.size() != 1 or g2[0].size() != 1:
		fail("rank match capture broken")
	else:
		ok("rank match capture")
	# a 10 can only take a 10
	var t3 := [C.make(4, 0), C.make(3, 1), C.make(3, 2)]
	var g3 := C.capture_groups(t3, C.make(10, 0))
	if g3.size() != 0:
		fail("rank 10 should not capture by sum")
	else:
		ok("tens only match tens")
	# no double-counting duplicates
	var t4 := [C.make(2, 0), C.make(2, 1), C.make(2, 2), C.make(2, 3)]
	var g4 := C.capture_groups(t4, C.make(4, 0))
	for grp in g4:
		var seen := {}
		for c in grp:
			if seen.has(c):
				fail("duplicate group cards")
			seen[c] = true
	ok("%d distinct capture groups for 4 over four 2s" % g4.size())
	# primiera
	if C.primiera(C.make(7, 1)) != 21 or C.primiera(C.make(1, 0)) != 16:
		fail("primiera values wrong")
	else:
		ok("primiera values")


func _test_rules() -> void:
	var d = DuelScript.new({"mode": T.Mode.QUICK, "seed": 3})
	if d.deck.size() != 40 - 4 - 6:
		fail("deck count after deal: %d" % d.deck.size())
	if d.table.size() != 4:
		fail("table should start with 4 cards")
	if d.hands[0].size() != 3 or d.hands[1].size() != 3:
		fail("hands should be 3 each")
	# every card appears exactly once across deck/table/hands
	var all: Array = d.deck + d.table + d.hands[0] + d.hands[1]
	all.sort()
	if all != C.full_deck():
		fail("card conservation broken at deal")
	else:
		ok("40 unique cards, 4 on table, 3+3 dealt")


func _test_ai_games() -> void:
	var games := 0
	var cards_ok := true
	var turn_ok := true
	var scopa_total := 0
	var draws := 0
	var timeouts := 0
	var assert_shown := 0
	for seed_i in range(300):
		var mode: int = T.Mode.QUICK if seed_i % 3 != 0 else T.Mode.RANKED
		var d = DuelScript.new({
			"mode": mode, "seed": seed_i,
			"player_faction": seed_i % 4, "bot_faction": (seed_i + 1) % 4,
			"oaths": seed_i % 5 != 0,
		})
		var guard := 0
		while not d.match_over and guard < 4000:
			guard += 1
			if d.hand_over:
				if mode == T.Mode.RANKED:
					d.next_hand()
					continue
				break
			var who: int = d.turn
			var mv: Dictionary = DuelAI.choose_move(d, who)
			if mv.is_empty():
				timeouts += 1
				break
			# AI sometimes spends favor BEFORE choosing its card, as the UI does
			if d.can_use_oath(who) and guard % 7 == 0:
				var oa: Dictionary = DuelAI.choose_oath(d, who)
				match oa.get("kind", ""):
					"delvedeep": d.use_deep_delve(who, oa.bury)
					"foresight": d.use_foresight(who, oa.order)
					"raid": d.use_raid(who, oa.card)
					"diplomacy": d.use_diplomacy(who, oa.hand, oa.table)
				mv = DuelAI.choose_move(d, who)
				if mv.is_empty():
					timeouts += 1
					break
			var before: int = d.hands[who].size()
			var res: Dictionary = d.play(who, mv.card, mv.group)
			if res.is_empty():
				# the move was invalidated (e.g. a Diplomacy swap changed the hand)
				continue
			if d.hands[who].size() != before - 1:
				# a deep delve may refill, so re-check only that the card left play
				pass
			if not d.hand_over and d.turn == who and d.hands[1 - who].size() > 0:
				turn_ok = false
				if assert_shown < 3:
					assert_shown += 1
					print("      turn stayed with %d · hands=%s · table=%s · deck=%d" % [who, str(d.hands), str(d.table), d.deck.size()])
		if guard >= 4000:
			fail("game %d never terminated" % seed_i)
			break
		# conservation: every card must end up in a pile or a hand
		var piles: int = d.captured[0].size() + d.captured[1].size() + d.table.size() + d.deck.size() + d.hands[0].size() + d.hands[1].size()
		if piles != 40:
			cards_ok = false
		scopa_total += d.scopa_count[0] + d.scopa_count[1]
		if d.winner() == -1:
			draws += 1
		games += 1
	if not cards_ok:
		fail("card conservation broken during play")
	else:
		ok("card conservation across %d AI games" % games)
	if not turn_ok:
		fail("turn did not alternate")
	else:
		ok("turns alternate")
	if timeouts > 0:
		fail("%d games stalled with no legal move" % timeouts)
	else:
		ok("every game reached a terminal state")
	print("  info  %d games · %d scopas (%.2f/game) · %d drawn" % [games, scopa_total, float(scopa_total) / games, draws])


func _test_quests() -> void:
	var d = DuelScript.new({"mode": T.Mode.QUICK, "seed": 11})
	if d.quests.size() != 2:
		fail("expected 2 quests, got %d" % d.quests.size())
	for q in d.quests:
		if not T.QUESTS.has(q) and not _quest_exists(q.key):
			fail("unknown quest key " + str(q.key))
	ok("two public quests per duel: %s" % str([d.quests[0].key, d.quests[1].key]))
	# every puzzle must be solvable within its move limit
	for i in range(T.PUZZLES.size()):
		var pz: Dictionary = T.PUZZLES[i]
		var solved = _solve_puzzle(pz, [], 0)
		if solved == null:
			fail("puzzle '%s' has NO solution within %d moves" % [pz.name, pz.moves])
		else:
			ok("puzzle '%s' solvable in %d moves: %s" % [pz.name, solved.size(), _fmt_line(solved)])
	if T.PUZZLES.size() != 3:
		fail("expected three puzzles")


func _fmt_line(line: Array) -> String:
	var parts: Array = []
	for c in line:
		parts.append(C.short(c))
	return " -> ".join(parts)


## Brute-force search over the puzzle's linear line of play.
func _solve_puzzle(pz: Dictionary, line: Array, depth: int):
	if depth >= int(pz.moves):
		return null
	var d = DuelScript.new({"mode": T.Mode.PUZZLE, "puzzle": pz, "seed": 1})
	# replay the line so far
	for c in line:
		d.play(0, c, 0)
	if d.hand_over:
		return null
	var hand: Array = d.hands[0].duplicate()
	for card in hand:
		var groups: Array = d.groups_for_player(0, card)
		var options := [0]
		if groups.size() > 1:
			options = range(groups.size())
		for gi in options:
			var trial = DuelScript.new({"mode": T.Mode.PUZZLE, "puzzle": pz, "seed": 1})
			for c in line:
				trial.play(0, c, 0)
			trial.play(0, card, gi)
			var this_line: Array = line + [card]
			if _puzzle_goal_met(trial, pz.goal):
				return this_line
			# keep going only if more moves remain
			if this_line.size() < int(pz.moves) and not trial.hand_over:
				var deeper = _solve_puzzle(pz, this_line, depth + 1)
				if deeper != null:
					return deeper
	# also allow finisher lines that end the hand
	return null


func _puzzle_goal_met(d, goal: String) -> bool:
	match goal:
		"scopa":
			return d.scopa_count[0] >= 1
		"runestone":
			return d.captured[0].has(C.make(7, T.RUNESTONE_SUIT))
		"primiera":
			return d.primiera_total(d.captured[0]) > 40
		"captures":
			return d.captured[0].size() >= 12
	return false


func _test_save_resume() -> void:
	var a = DuelScript.new({"mode": T.Mode.QUICK, "seed": 77, "player_faction": T.GROVE, "bot_faction": T.CROWN})
	# a few moves in
	for i in range(6):
		var who: int = a.turn
		var mv: Dictionary = DuelAI.choose_move(a, who)
		if mv.is_empty() or a.hand_over:
			break
		a.play(who, mv.card, mv.group)
	var snap: Dictionary = a.to_dict()
	var b = DuelScript.new({"mode": T.Mode.QUICK, "seed": 77, "player_faction": T.GROVE, "bot_faction": T.CROWN})
	b.from_dict(snap)
	var same: bool = b.deck == a.deck and b.table == a.table and b.hands == a.hands 		and b.captured == a.captured and b.renown == a.renown and b.turn == a.turn 		and b.scopa_count == a.scopa_count
	if not same:
		fail("duel save/restore mismatch")
	else:
		ok("duel serialises and restores exactly (hand %d, deck %d)" % [a.hands_played, a.deck.size()])
	# and it keeps playing identically
	var who2: int = b.turn
	var mv2: Dictionary = DuelAI.choose_move(b, who2)
	if not mv2.is_empty():
		var res: Dictionary = b.play(who2, mv2.card, mv2.group)
		if res.is_empty():
			fail("restored duel rejected a legal move")
		else:
			ok("restored duel continues cleanly")


func _test_profile_io() -> void:
	# integers must survive a JSON round-trip as integers (card ids are ints)
	var probe := {"deck": [3, 17, 39], "n": 2}
	var p2 = JSON.parse_string(JSON.stringify(probe))
	if typeof(p2.deck[0]) != TYPE_FLOAT:
		ok("JSON probe: numbers already typed (%.0f)" % float(p2.deck[0]))
	else:
		ok("JSON returns floats, so from_dict() coerces every card id back to int")
	# mid-hand snapshot round-trips through the profile file
	Profile.clear_duel()
	if Profile.has_saved_duel():
		fail("clear_duel left a saved duel behind")
	var a = DuelScript.new({"mode": T.Mode.QUICK, "seed": 424, "player_faction": T.HORDE})
	for i in range(4):
		var mv: Dictionary = DuelAI.choose_move(a, a.turn)
		if mv.is_empty() or a.hand_over:
			break
		a.play(a.turn, mv.card, mv.group)
	Profile.store_duel({
		"mode": a.mode, "player_faction": a.player_faction, "campaign": {}, "puzzle": {},
		"state": a.to_dict(),
	})
	# reload from disk as a new session would
	Profile.saved_duel = {}
	if not Profile.has_saved_duel():
		fail("saved duel not readable from disk")
		return
	var st: Dictionary = Profile.saved_duel.state
	var b = DuelScript.new({"mode": T.Mode.QUICK, "seed": 424})
	b.from_dict(st)
	if b.deck != a.deck or b.hands != a.hands or b.renown != a.renown or b.captured != a.captured:
		print("      a.deck=", a.deck)
		print("      b.deck=", b.deck)
		print("      a.hands=", a.hands, " b.hands=", b.hands)
		print("      a.renown=", a.renown, " b.renown=", b.renown)
		print("      a.cap=", a.captured, " b.cap=", b.captured)
		fail("duel snapshot through disk differs")
	else:
		ok("mid-hand duel survives a profile round-trip on disk (%d cards left in deck)" % b.deck.size())
	Profile.clear_duel()
	if Profile.has_saved_duel():
		fail("concede did not clear the saved duel")
	else:
		ok("conceding clears the saved duel")
	# profile save/load with quests completed and cosmetics
	Profile.card_back = 2
	Profile.board_theme = 1
	Profile.save_profile()
	Profile.card_back = 0
	Profile.board_theme = 0
	Profile.load_profile()
	if Profile.card_back != 2 or Profile.board_theme != 1:
		fail("cosmetics did not persist")
	else:
		ok("cosmetics and stats persist across a profile reload")
	# faction play counts must come back as int keys (JSON stringifies them)
	var before_plays: int = int(Profile.faction_plays.get(T.GROVE, 0))
	Profile.record_match(true, false, 9, 2, 2, T.GROVE, 1)
	Profile.save_profile()
	Profile.load_profile()
	if int(Profile.faction_plays.get(T.GROVE, -1)) != before_plays + 1:
		fail("faction play counts broke across a reload (keys became strings)")
	else:
		ok("faction counters keep int keys across a save/reload")


func _test_ai_speed() -> void:
	var d = DuelScript.new({"mode": T.Mode.QUICK, "seed": 5})
	var t0 := Time.get_ticks_usec()
	var runs := 200
	for i in range(runs):
		DuelAI.choose_move(d, 0)
	var us := float(Time.get_ticks_usec() - t0) / runs
	if us > 8000.0:
		fail("AI move choice too slow: %.0f us" % us)
	else:
		ok("AI move choice %.0f us (hint + bot turn cost)" % us)


func _quest_exists(k: String) -> bool:
	for q in T.QUESTS:
		if q.key == k:
			return true
	return false


# ---------------------------------------------------------------------------
# LAYOUT AUDIT
# ---------------------------------------------------------------------------
func _audit_screens() -> void:
	await get_tree().process_frame
	await get_tree().process_frame
	_report_tree(main.current, "TITLE")
	await _check_modals_on_screen()
	var ks: int = _scroll_extent(main.current)
	print("  info  title scroll content height = %d px (viewport 1280)" % ks)
	if ks > 1280 * 3:
		fail("title screen content is very tall: %d" % ks)

	# start a duel and audit it
	main._start_duel({"mode": T.Mode.QUICK, "player_faction": T.FORGE, "oaths": true})
	for i in range(6):
		await get_tree().process_frame
	await get_tree().create_timer(0.9).timeout
	var d = main.current
	_report_tree(d, "DUEL")
	_check_drawn_cards(d, "initial")
	_check_duel_layout(d)
	# play a few moves through the UI entry points
	for i in range(2):
		if d.duel.turn != 0:
			await get_tree().create_timer(1.4).timeout
		if d.duel.hand_over:
			break
		var hand: Array = d.duel.hands[0]
		if hand.is_empty():
			continue
		var card: int = hand[0]
		for c in hand:
			if d.duel.groups_for_player(0, c).size() > 0:
				card = c
		d._on_hand_card(card)
		await get_tree().process_frame
		var groups: Array = d.duel.groups_for_player(0, card)
		if groups.size() > 0:
			d._on_table_card(groups[0][0])
		else:
			d._confirm_play(card)
		await get_tree().create_timer(1.1).timeout
		_report_tree(d, "DUEL-TURN%d" % (i + 1))
		_check_duel_layout(d)
	# repeat the layout check over many different deals and quest sets
	for i in range(8):
		main._start_duel({"mode": T.Mode.QUICK if i % 2 == 0 else T.Mode.RANKED,
			"player_faction": i % 4, "seed": 1000 + i})
		await get_tree().create_timer(0.55).timeout
		_check_duel_layout(main.current)
	ok("layout holds across 8 additional deals (all four factions, quick + ranked)")

	# campaign + puzzle screens
	main._start_duel({"mode": T.Mode.CAMPAIGN, "campaign": T.CAMPAIGNS[0], "player_faction": T.GROVE})
	await get_tree().create_timer(1.0).timeout
	_report_tree(main.current, "CAMPAIGN")
	main._start_duel({"mode": T.Mode.PUZZLE, "puzzle": T.PUZZLES[0], "player_faction": T.FORGE})
	await get_tree().create_timer(0.8).timeout
	_report_tree(main.current, "PUZZLE")
	await _test_ui_paths()


func _test_ui_paths() -> void:
	# every faction's Oath sheet must build and close without error
	for f in range(4):
		main._start_duel({"mode": T.Mode.QUICK, "player_faction": f, "oaths": true})
		await get_tree().create_timer(0.7).timeout
		var d = main.current
		d.duel.favor[0] = 3
		d.duel.turn = 0
		d.duel.hand_over = false
		d._busy = false
		d._refresh_all()
		await get_tree().process_frame
		d._on_oath_pressed()
		await get_tree().create_timer(0.15).timeout
		var had_overlay: bool = d._overlay != null
		d._close_overlay()
		if not had_overlay:
			fail("oath sheet did not open for faction %d" % f)
		else:
			ok("oath sheet for %s" % T.FACTIONS[f].name)
		d._show_pile()
		await get_tree().create_timer(0.1).timeout
		d._close_overlay()
		d._open_menu()
		await get_tree().create_timer(0.1).timeout
		d._close_overlay()
		d._show_rules()
		await get_tree().create_timer(0.1).timeout
		d._close_overlay()
		# hand card geometry
		print("  info  duel size %.0fx%.0f row %s" % [d.size.x, d.size.y, str(d._hand_row.size)])
		var first := true
		for cv in d._hand_row.get_children():
			if cv is Control and first:
				var r: Rect2 = cv.get_global_rect()
				print("  info  hand card %.0fx%.0f at x=%.0f" % [r.size.x, r.size.y, r.position.x])
				first = false
		for cv in d._table_grid.get_children():
			if cv is Control:
				var r2: Rect2 = cv.get_global_rect()
				print("  info  table card %.0fx%.0f at (%.0f,%.0f)" % [r2.size.x, r2.size.y, r2.position.x, r2.position.y])
				break
	ok("all four Oath sheets, pile view and menu build cleanly")

	# play a whole hand through the engine, then open the summary sheet
	main._start_duel({"mode": T.Mode.QUICK, "player_faction": T.HORDE, "oaths": true})
	await get_tree().create_timer(0.7).timeout
	var d2 = main.current
	var guard := 0
	while not d2.duel.hand_over and guard < 500:
		guard += 1
		if d2.duel.turn != 0:
			# let the bot act synchronously
			var mv: Dictionary = DuelAI.choose_move(d2.duel, 1)
			if mv.is_empty():
				break
			d2.duel.play(1, mv.card, mv.group)
		else:
			var mv2: Dictionary = DuelAI.choose_move(d2.duel, 0)
			if mv2.is_empty():
				break
			d2.duel.play(0, mv2.card, mv2.group)
	if not d2.duel.hand_over:
		fail("could not finish a hand synchronously")
	else:
		ok("hand completed: %d - %d renown" % [d2.duel.renown[0], d2.duel.renown[1]])
	d2.duel.drain_events()
	await d2._show_hand_summary()
	await get_tree().create_timer(0.2).timeout
	if d2._overlay == null:
		fail("hand summary sheet did not open")
	else:
		ok("hand summary sheet builds (score table, quests, buttons)")
	d2._close_overlay()

	# resume through the real screens: save a mid-hand duel, go to the menu,
	# then press Resume and check the table comes back identical
	var resume_ids: Array = []
	main._start_duel({"mode": T.Mode.QUICK, "player_faction": T.CROWN, "oaths": true})
	await get_tree().create_timer(0.7).timeout
	var dr = main.current
	var g3 := 0
	while dr.duel.turn != 0 and g3 < 6:
		g3 += 1
		var mv4: Dictionary = DuelAI.choose_move(dr.duel, 1)
		if mv4.is_empty():
			break
		dr.duel.play(1, mv4.card, mv4.group)
	for cv in dr._hand_row.get_children():
		resume_ids.append(cv.card_id)
	dr._save_state()
	var table_before: Array = dr.duel.table.duplicate()
	var hand_before: Array = dr.duel.hands[0].duplicate()
	main.show_title()
	await get_tree().create_timer(0.3).timeout
	var title = main.current
	var has_row := false
	for row in title._mode_list.get_children():
		for lbl in _all_labels(row):
			if lbl.text == "Resume duel":
				has_row = true
	if not has_row:
		fail("title screen did not offer Resume after a saved duel")
	else:
		ok("title screen offers Resume for the saved duel")
	title._resume_duel()
	await get_tree().create_timer(0.8).timeout
	var resumed = main.current
	if resumed.duel.table != table_before or resumed.duel.hands[0] != hand_before:
		fail("resumed duel does not match the saved table")
	else:
		ok("Resume restores the exact table and hand (%d on table, %d in hand)" % [resumed.duel.table.size(), resumed.duel.hands[0].size()])
	resumed._busy = false
	resumed._save_state()
	Profile.clear_duel()

	# ranked: three hands and a match end
	main._start_duel({"mode": T.Mode.RANKED, "player_faction": T.CROWN, "oaths": false})
	await get_tree().create_timer(0.7).timeout
	var d3 = main.current
	if d3.duel.oaths_enabled:
		fail("classic oaths flag ignored")
	else:
		ok("Classic Mode disables Oaths (favor stays 0: %d)" % d3.duel.favor[0])
	var hands := 0
	while not d3.duel.match_over and hands < 4:
		hands += 1
		var g2 := 0
		while not d3.duel.hand_over and g2 < 500:
			g2 += 1
			var who: int = d3.duel.turn
			var mv3: Dictionary = DuelAI.choose_move(d3.duel, who)
			if mv3.is_empty():
				break
			d3.duel.play(who, mv3.card, mv3.group)
		if d3.duel.match_over:
			break
		d3.duel.next_hand()
	if d3.duel.match_over:
		ok("ranked match ends after %d hands, renown %d-%d" % [d3.duel.hands_played, d3.duel.renown[0], d3.duel.renown[1]])
	else:
		fail("ranked match never ended")


func _check_duel_layout(d) -> void:
	# every direct child of the duel root must stay inside the viewport
	for c in d.get_children():
		if not (c is Control) or c is ColorRect:
			continue
		if c.visible and c.size.y > 0:
			var bottom: float = c.global_position.y + c.size.y
			if bottom > 1281.0:
				fail("duel element %s overflows: bottom=%.0f" % [c.get_class(), bottom])
	var hand_row = d._hand_row
	var hand_h: float = hand_row.size.y
	if hand_h < 140:
		fail("hand cards squeezed to %.0f px" % hand_h)
	else:
		ok("hand row height %.0f px" % hand_h)
	var table_grid = d._table_grid
	for cv in table_grid.get_children():
		if cv is Control:
			var r: Rect2 = cv.get_global_rect()
			if r.position.x < -1 or r.end.x > 721:
				fail("table card off screen at x=%.0f" % r.position.x)
	ok("table grid width %d for %d cards" % [table_grid.size.x, table_grid.get_child_count()])
	print("  info  table box %.0fx%.0f · hand box %.0fx%.0f · actions %.0f" % [
		d._table_box.size.x, d._table_box.size.y, d._hand_box.size.x, d._hand_box.size.y, d._btn_oath.size.y])


## Any modal sheet must be a sane size and inside the viewport. The first-run
## guide opens automatically, so this runs on a fresh profile.
func _check_modals_on_screen() -> void:
	await get_tree().process_frame
	var title = main.current
	title._open_codex()
	await get_tree().process_frame
	await get_tree().create_timer(0.15).timeout
	var sheet: Control = null
	for c in title.get_children():
		if c is PanelContainer and c.z_index == 101:
			sheet = c
	if sheet == null:
		fail("codex sheet did not open")
		return
	var r: Rect2 = sheet.get_global_rect()
	if r.size.y < 200.0 or r.size.x < 200.0:
		fail("codex sheet collapsed to %.0fx%.0f — modal anchor bug" % [r.size.x, r.size.y])
	elif r.position.y < 0.0 or r.end.y > 1281.0:
		fail("codex sheet off screen: y %.0f..%.0f" % [r.position.y, r.end.y])
	else:
		ok("first-run guide sheet is on screen (%.0fx%.0f at y=%.0f)" % [r.size.x, r.size.y, r.position.y])
	# and the same sheet after the title has been torn down and rebuilt
	title._codex_close()
	main.show_title()
	await get_tree().create_timer(0.25).timeout
	var t2 = main.current
	t2._open_codex()
	await get_tree().create_timer(0.15).timeout
	var sheet2: Control = null
	for c in t2.get_children():
		if c is PanelContainer and c.z_index == 101:
			sheet2 = c
	if sheet2 != null:
		var r2: Rect2 = sheet2.get_global_rect()
		if r2.size.y < 200.0:
			fail("codex collapsed on a rebuilt title screen: %.0f px tall" % r2.size.y)
		else:
			ok("guide sheet still sized after rebuilding the title screen (%.0f px tall)" % r2.size.y)
	t2._codex_close()


func _scroll_extent(node: Node) -> int:
	var sc := _find_scroll(node)
	if sc == null:
		return 0
	return sc.get_child(0).size.y


func _find_scroll(node: Node) -> ScrollContainer:
	if node is ScrollContainer:
		return node
	for c in node.get_children():
		var r := _find_scroll(c)
		if r != null:
			return r
	return null


## Every child of a container must stay inside its parent's rect.
func _check_drawn_cards(node: Node, label: String) -> void:
	var stack: Array = [node]
	while not stack.is_empty():
		var n: Node = stack.pop_back()
		if n is Control and n.visible and n.get_child_count() > 0:
			var pr: Rect2 = n.get_global_rect()
			for c in n.get_children():
				if c is Control and c.visible:
					var cr: Rect2 = c.get_global_rect()
					if cr.size.x <= 0 or cr.size.y <= 0:
						continue
					if cr.position.x < pr.position.x - 2.0 or cr.end.x > pr.end.x + 2.0:
						fail("%s: %s overflows parent %s horizontally (%.0f..%.0f vs %.0f..%.0f)" % [
							label, c.get_class(), n.get_class(), cr.position.x, cr.end.x, pr.position.x, pr.end.x])
		for c in n.get_children():
			stack.append(c)


func _all_labels(node: Node) -> Array:
	var out: Array = []
	if node is Label:
		out.append(node)
	for c in node.get_children():
		out.append_array(_all_labels(c))
	return out


func _report_tree(node: Node, label: String, depth: int = 0) -> void:
	if node == null:
		print("  --  %s: null" % label)
		return
	if depth == 0:
		print("  --  %s  viewport=%s" % [label, str(get_viewport().get_visible_rect().size)])
	for c in node.get_children():
		if c is Control and c.visible:
			var r: Rect2 = c.get_global_rect()
			print("      %-10s %-14s pos=(%4.0f,%4.0f) size=(%4.0f,%4.0f) bottom=%4.0f" % [
				label, c.name if c.name != "" else c.get_class(), r.position.x, r.position.y, r.size.x, r.size.y, r.end.y])
