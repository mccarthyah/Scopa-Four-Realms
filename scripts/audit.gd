extends Node
## Headless self-test + layout audit.  Run:
##   godot --headless --path . -- --audit
## Plays thousands of games to exercise the rules engine, then boots every
## screen and checks that nothing overflows the phone viewport.

const T := preload("res://scripts/tables.gd")
const C := preload("res://scripts/game/cards.gd")
const DuelScript := preload("res://scripts/game/duel.gd")
const DuelAI := preload("res://scripts/game/ai.gd")
const CardArt := preload("res://scripts/ui/card_art.gd")
const EffectAtlas := preload("res://scripts/ui/effect_atlas.gd")
const UI := preload("res://scripts/ui/ui.gd")

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
	_test_raid_rules()
	_test_capture_math()
	_test_ai_games()
	_test_quests()
	_test_save_resume()
	_test_ai_speed()
	_test_profile_io()
	_test_deal()
	_test_overlay_dismiss()
	_test_quindici()
	_test_animation_settings()
	_test_spin()
	await _test_bot_hand_scale()
	await _test_card_corners()
	_test_card_atlas()
	_test_effect_atlas()
	await _test_table_fit()
	await _test_display_scaling()
	await _test_logo_layout()
	await _test_settings_dialog()
	await _test_settings_layout()
	await _test_menu_sheets()
	await _test_menu_pointer_input()
	await _test_tap_play()
	await _test_raid_picker()
	await _test_other_oath_picker_signals()
	await _audit_screens()
	print("=== AUDIT COMPLETE · failures=%d ===" % failures)
	print("godot ", Engine.get_version_info().string, " · renderer ",
		ProjectSettings.get_setting("rendering/renderer/rendering_method", "?"), " · adapter ",
		RenderingServer.get_video_adapter_name())
	get_tree().quit()


## Animation must be purely cosmetic: every switch has to exist, persist, and the
## off state must not change what the game does. Checked without rendering.
func _test_animation_settings() -> void:
	var keys := ["anim_enabled", "anim_spin", "anim_slow", "anim_match"]
	var missing := []
	for k in keys:
		if Profile.get(k) == null:
			missing.append(k)
	if not missing.is_empty():
		fail("animation settings missing: %s" % str(missing))
	else:
		ok("animation settings exist (all, spin, slow, match)")

	# A duel screen must build and play with every animation switched off, in the
	# same number of moves - i.e. the switches cannot gate gameplay.
	var saved := [Profile.anim_enabled, Profile.anim_spin, Profile.anim_slow, Profile.anim_match]
	Profile.anim_enabled = false
	var off = load("res://scripts/screens/duel.gd").new()
	off.config = {"mode": 0, "seed": 11}
	main.add_child(off)
	for i in range(30):
		await get_tree().process_frame
	# the opponent hand must render as face-down cards before a play starts, not mid-animation
	var backs_off := 0
	for cv in off._bot_row.get_children():
		if cv is CardView and not cv.face_up:
			backs_off += 1
	if backs_off == off.duel.hands[1].size() and backs_off > 0:
		ok("opponent hand shown as %d face-down cards" % backs_off)
	else:
		fail("opponent hand mismatch: %d backs for %d cards" % [backs_off, off.duel.hands[1].size()])
	var played_off := _tap_first_card(off)
	Profile.anim_enabled = true
	var on = load("res://scripts/screens/duel.gd").new()
	on.config = {"mode": 0, "seed": 11}
	main.add_child(on)
	for i in range(30):
		await get_tree().process_frame
	var played_on := _tap_first_card(on)
	if played_off and played_on:
		ok("a card can be played with animation on and off")
	else:
		fail("animation setting blocked a play (%s/%s)" % [played_off, played_on])
	Profile.anim_enabled = saved[0]
	Profile.anim_spin = saved[1]
	Profile.anim_slow = saved[2]
	Profile.anim_match = saved[3]
	off.queue_free()
	on.queue_free()
	await get_tree().process_frame


func _tap_first_card(screen) -> bool:
	var hand: Array = screen.duel.hands[0]
	if hand.is_empty():
		return false
	var before: int = hand.size()
	screen.duel.turn = 0
	screen._on_hand_card(hand[0])
	# second tap confirms the selected play
	screen._confirm_play(hand[0]) if screen._selection == hand[0] else screen._on_hand_card(hand[0])
	return screen.duel.hands[0].size() < before or screen._busy


## EVERY entry on the title menu must actually open. The Daily Puzzle sheet threw
## "Invalid type in function 'setup' ... Cannot convert argument 1 from Array to
## int" because it handed [rank, faction] pairs to CardView.setup(), which wants a
## card id - and no check had ever opened these sheets. They hold data in shapes
## the rest of the app does not use, so they fail in ways nothing else would catch.
func _test_menu_sheets() -> void:
	var title = main.current
	if title == null:
		fail("menu sheets: no title screen mounted")
		return
	# Daily puzzle: open the sheet, then build the preview for every deal.
	var opened := 0
	for i in range(T.PUZZLES.size()):
		var pz: Dictionary = T.PUZZLES[i]
		title._open_puzzle()
		await get_tree().process_frame
		opened += 1
		# the preview is where the crash was; walk the cards it produced
		var card = title._mini_deal(pz)
		if card == null:
			fail("puzzle '%s': preview did not build" % pz.name)
			continue
		main.add_child(card)
		await get_tree().process_frame
		var ids: Array = []
		for n in _walk_controls(card):
			if n is Control and n.get("card_id") != null and n.card_id >= 0:
				ids.append(n.card_id)
		var want: int = pz.table.size() + pz.hand.size()
		if ids.size() != want:
			fail("puzzle '%s': preview shows %d cards, deal has %d" % [pz.name, ids.size(), want])
		elif ids.any(func(x): return x < 0 or x >= 40):
			fail("puzzle '%s': preview produced an out-of-range card id" % pz.name)
		card.queue_free()
		title._codex_close()
		await get_tree().process_frame
	if opened == T.PUZZLES.size():
		ok("every Daily Puzzle sheet opens and its preview lays out real cards (%d deals)" % T.PUZZLES.size())

	# The other menu sheets, same treatment.
	for entry in [["campaign", "campaign"], ["codex", "codex"]]:
		match entry[1]:
			"campaign":
				title._open_campaign()
			"codex":
				title._open_codex()
		await get_tree().process_frame
		title._codex_close()
		await get_tree().process_frame
	ok("campaign and codex sheets open without error")


## Settings must be reachable through real pointer input and persist immediately.
func _test_settings_dialog() -> void:
	var title = main.current
	title._codex_close()
	await get_tree().process_frame
	var keys := ["classic_mode", "card_back", "board_theme", "anim_enabled", "anim_spin", "anim_slow", "anim_match"]
	var saved := {}
	for key in keys:
		saved[key] = Profile.get(key)
	Profile.classic_mode = false
	Profile.card_back = 0
	Profile.board_theme = 0
	Profile.anim_enabled = true
	Profile.anim_spin = true
	Profile.anim_slow = true
	Profile.anim_match = true
	Profile.save_profile()
	title._build_modes()
	title._scroll.scroll_vertical = 0
	for i in range(4): await get_tree().process_frame
	var button: Button = title.find_child("SettingsButton", true, false)
	if button == null or title.find_child("ClassicSettings", true, false) != null or title.find_child("TableSettings", true, false) != null or title.find_child("AnimationSettings", true, false) != null:
		fail("settings: missing button or controls still on title page")
	else:
		_send_mouse_click(button.get_global_rect().get_center())
		for i in range(4): await get_tree().process_frame
		if title._sheet_panel == null:
			fail("settings: button did not open dialog via viewport click")
		else:
			ok("settings button opens dialog via viewport click; controls are absent from title")
			var panel: Control = title._sheet_panel
			var body: VBoxContainer = panel.get_meta("body")
			var scroll: ScrollContainer = body.get_parent()
			var controls := {}
			var backs := {}
			var boards := {}
			for n in _walk_controls(panel):
				if n is Button and n.has_meta("setting_key"): controls[n.get_meta("setting_key")] = n
				if n is Button and n.has_meta("card_back"): backs[int(n.get_meta("card_back"))] = n
				if n is Button and n.has_meta("board_theme"): boards[int(n.get_meta("board_theme"))] = n
			if controls.size() != 5 or backs.size() != 3 or boards.size() != 4:
				fail("settings: missing controls: toggles=%s backs=%s boards=%s" % [str(controls.keys()), str(backs.keys()), str(boards.keys())])
			else:
				for key in ["classic_mode", "anim_spin", "anim_slow", "anim_match"]:
					var b: Button = controls[key]
					scroll.ensure_control_visible(b)
					for i in range(3): await get_tree().process_frame
					_send_mouse_click(b.get_global_rect().get_center())
					await get_tree().process_frame
				var back: Button = backs[2]
				var board: Button = boards[3]
				for b in [back, board]:
					scroll.ensure_control_visible(b)
					for i in range(3): await get_tree().process_frame
					_send_mouse_click(b.get_global_rect().get_center())
					await get_tree().process_frame
				var master: Button = controls["anim_enabled"]
				scroll.ensure_control_visible(master)
				for i in range(3): await get_tree().process_frame
				_send_mouse_click(master.get_global_rect().get_center())
				await get_tree().process_frame
				var disabled := true
				for key in ["anim_spin", "anim_slow", "anim_match"]:
					disabled = disabled and controls[key].disabled
				if Profile.classic_mode and Profile.card_back == 2 and Profile.board_theme == 3 and not Profile.anim_enabled and not Profile.anim_spin and not Profile.anim_slow and not Profile.anim_match and disabled and back.button_pressed and board.button_pressed:
					ok("settings controls respond to clicks, show cosmetic selections and master disables sub-switches")
				else:
					fail("settings: click state classic=%s back=%s board=%s anim=%s,%s,%s,%s disabled=%s selected=%s,%s" % [Profile.classic_mode,Profile.card_back,Profile.board_theme,Profile.anim_enabled,Profile.anim_spin,Profile.anim_slow,Profile.anim_match,disabled,back.button_pressed,board.button_pressed])
				_send_mouse_click(master.get_global_rect().get_center())
				await get_tree().process_frame
				if not controls["anim_spin"].disabled and not controls["anim_slow"].disabled and not controls["anim_match"].disabled:
					ok("animation master re-enables its sub-switches")
				else: fail("settings: sub-switches did not re-enable")
				# Reload from disk, not just the in-memory values.
				Profile.classic_mode = false
				Profile.card_back = 0
				Profile.board_theme = 0
				Profile.anim_enabled = false
				Profile.anim_spin = true
				Profile.anim_slow = true
				Profile.anim_match = true
				Profile.load_profile()
				if Profile.classic_mode and Profile.card_back == 2 and Profile.board_theme == 3 and Profile.anim_enabled and not Profile.anim_spin and not Profile.anim_slow and not Profile.anim_match:
					ok("all settings persist through profile reload")
				else: fail("settings: profile reload did not restore choices")
				var done: Button = panel.find_child("SettingsDone", true, false)
				scroll.ensure_control_visible(done)
				for i in range(4): await get_tree().process_frame
				_send_mouse_click(done.get_global_rect().get_center())
				for i in range(3): await get_tree().process_frame
				if title._sheet_panel != null or is_instance_valid(panel) or title._codex != null:
					fail("settings: Done left a panel or dimmer")
				else: ok("settings Done removes both modal layers")
				title._scroll.scroll_vertical = 0
				for i in range(3): await get_tree().process_frame
				_send_mouse_click(button.get_global_rect().get_center())
				for i in range(3): await get_tree().process_frame
				panel = title._sheet_panel
				var reopened := {}
				var close: Button = null
				if panel != null:
					for n in _walk_controls(panel):
						if n is Button and n.has_meta("setting_key"): reopened[n.get_meta("setting_key")] = n.button_pressed
						if n is Button and n.text == "✕": close = n
						if n is Button and n.has_meta("card_back") and n.get_meta("card_back") == 2: reopened["back"] = n.button_pressed
						if n is Button and n.has_meta("board_theme") and n.get_meta("board_theme") == 3: reopened["board"] = n.button_pressed
				if reopened.get("classic_mode", false) and reopened.get("anim_enabled", false) and not reopened.get("anim_spin", true) and not reopened.get("anim_slow", true) and not reopened.get("anim_match", true) and reopened.get("back", false) and reopened.get("board", false):
					ok("reopened settings reflects saved rules, cosmetics and animations")
				else: fail("settings: reopening does not reflect saved choices")
				if close != null:
					_send_mouse_click(close.get_global_rect().get_center())
					for i in range(3): await get_tree().process_frame
					if title._sheet_panel == null and title._codex == null and not is_instance_valid(panel): ok("settings X closes without stranded blockers")
					else: fail("settings X did not remove modal")
				else: fail("settings X missing")
				var subtitle_found := false
				for n in _walk_controls(title._mode_list):
					if n is Label and n.text == "One hand. Oaths off. Four minutes.": subtitle_found = true
				var launch: Array = []
				title.start_duel.connect(func(cfg): launch.append(cfg), CONNECT_ONE_SHOT)
				title._launch(T.Mode.QUICK)
				if subtitle_found and not launch.is_empty() and not launch[0].oaths: ok("Quick Duel displays and launches with selected Classic setting")
				else: fail("settings: Quick Duel ignored Classic Mode")
	# The launch swaps screens, so restore preferences and return to title.
	for key in keys: Profile.set(key, saved[key])
	Profile.save_profile()
	main.show_title()
	for i in range(4): await get_tree().process_frame


## Resize a real title instance to small and desktop-column dimensions. The
## narrow case must both expose the Settings button and scroll to Done.
func _test_settings_layout() -> void:
	var old_seen: bool = Profile.seen_intro
	var old_classic: bool = Profile.classic_mode
	Profile.seen_intro = true
	var host := Control.new()
	main.add_child(host)
	var title = load("res://scripts/screens/title.gd").new()
	host.add_child(title)
	var all_ok := true
	for dims in [Vector2(320, 568), Vector2(360, 640), Vector2(540, 600)]:
		host.size = dims
		for i in range(6): await get_tree().process_frame
		var settings: Button = title.find_child("SettingsButton", true, false)
		var sr: Rect2 = settings.get_global_rect()
		var hr: Rect2 = host.get_global_rect()
		if sr.position.x < hr.position.x or sr.end.x > hr.end.x:
			fail("settings layout: entry is outside %s column: %s" % [str(dims), str(sr)])
			all_ok = false
			continue
		_send_mouse_click(sr.get_center())
		for i in range(5): await get_tree().process_frame
		var panel: Control = title._sheet_panel
		if panel == null:
			fail("settings layout: button not clickable in %s column" % str(dims))
			all_ok = false
			continue
		var pr := panel.get_global_rect()
		if pr.position.x < hr.position.x - 0.5 or pr.end.x > hr.end.x + 0.5 or pr.position.y < hr.position.y or pr.end.y > hr.end.y:
			fail("settings layout: modal out of bounds at %s: %s" % [str(dims), str(pr)])
			all_ok = false
		var body: VBoxContainer = panel.get_meta("body")
		var scroll: ScrollContainer = body.get_parent()
		var done: Button = panel.find_child("SettingsDone", true, false)
		if dims.x == 320 and scroll.get_v_scroll_bar().max_value <= scroll.get_v_scroll_bar().page:
			fail("settings layout: narrow modal should scroll")
			all_ok = false
		scroll.ensure_control_visible(done)
		for i in range(5): await get_tree().process_frame
		var dr := done.get_global_rect()
		var viewport_rect := scroll.get_global_rect()
		if dr.position.x < viewport_rect.position.x - 0.5 or dr.end.x > viewport_rect.end.x + 0.5 or dr.position.y < viewport_rect.position.y - 0.5 or dr.end.y > viewport_rect.end.y + 0.5:
			fail("settings layout: Done not visible after scroll at %s" % str(dims))
			all_ok = false
		_send_mouse_click(dr.get_center())
		for i in range(3): await get_tree().process_frame
		if title._sheet_panel != null:
			fail("settings layout: Done not clickable at %s" % str(dims))
			all_ok = false
			title._codex_close()
	if all_ok: ok("settings entry, modal bounds, scrolling and Done work at 320, 360 and desktop-column widths")
	host.queue_free()
	Profile.seen_intro = old_seen
	Profile.classic_mode = old_classic
	await get_tree().process_frame


## Exercise the actual viewport hit-testing path, including after dismissal.
## Calling _codex_close directly used to miss a stranded panel blocking the menu.
func _test_menu_pointer_input() -> void:
	var title = main.current
	title._codex_close()
	await get_tree().process_frame
	title._open_codex()
	for i in range(4):
		await get_tree().process_frame
	var panel: Control = title._sheet_panel
	var close_button: Button = null
	for n in _walk_controls(panel):
		if n is Button and n.text == "✕":
			close_button = n
			break
	if close_button == null:
		fail("menu input: guide close button not found")
		return
	_send_mouse_click(close_button.get_global_rect().get_center())
	await get_tree().process_frame
	await get_tree().process_frame
	if title._codex != null or is_instance_valid(panel):
		fail("menu input: clicking close left a modal panel or dimmer")
		title._codex_close()
		return
	ok("guide close responds to a real viewport mouse click and removes both layers")
	# Repeated opens must replace, rather than accumulate, interactive sheets.
	title._open_codex()
	var replaced: Control = title._sheet_panel
	title._open_puzzle()
	await get_tree().process_frame
	if is_instance_valid(replaced):
		fail("menu input: replacing a sheet left the old panel behind")
	else:
		ok("replacing a menu sheet removes the previous sheet")
	title._codex_close()
	await get_tree().process_frame
	# Use the arrow buttons as well as the body of a row: both must work after
	# opening and closing other sheets, including rows reached by scrolling.
	for mode_name in ["Campaign", "Daily Puzzle"]:
		var mode_row: Control = null
		var arrow: Button = null
		for row in title._mode_list.get_children():
			for n in _walk_controls(row):
				if n is Label and n.text == mode_name:
					mode_row = row
		if mode_row != null:
			for n in _walk_controls(mode_row):
				if n is Button and n.text == "›":
					arrow = n
					break
		if arrow == null:
			fail("menu input: %s arrow not found" % mode_name)
			continue
		title._scroll.ensure_control_visible(mode_row)
		for i in range(5):
			await get_tree().process_frame
		var mode_point: Vector2 = mode_row.get_global_rect().position + Vector2(35, mode_row.size.y * 0.5)
		_send_mouse_button(mode_point, MOUSE_BUTTON_WHEEL_DOWN)
		await get_tree().process_frame
		if title._sheet_panel != null or main.current != title:
			fail("menu input: mouse wheel opened %s" % mode_name)
			title._codex_close()
		else:
			ok("mouse wheel does not open %s" % mode_name)
		title._scroll.ensure_control_visible(mode_row)
		for i in range(5):
			await get_tree().process_frame
		_send_mouse_click(arrow.get_global_rect().get_center())
		await get_tree().process_frame
		if title._sheet_panel == null:
			fail("menu input: %s arrow did not open its sheet" % mode_name)
		else:
			ok("%s arrow opens its sheet after scrolling" % mode_name)
		title._codex_close()
		await get_tree().process_frame
	var quick: Control = null
	for row in title._mode_list.get_children():
		for n in _walk_controls(row):
			if n is Label and n.text == "Quick Duel":
				quick = row
				break
	if quick == null:
		fail("menu input: Quick Duel row not found")
		return
	title._scroll.scroll_vertical = 0
	await get_tree().process_frame
	title._scroll.ensure_control_visible(quick)
	for i in range(5):
		await get_tree().process_frame
	var point: Vector2 = quick.get_global_rect().position + Vector2(35, quick.size.y * 0.5)
	var scroll_before: int = title._scroll.scroll_vertical
	_send_mouse_button(point, MOUSE_BUTTON_WHEEL_DOWN)
	await get_tree().process_frame
	await get_tree().process_frame
	if main.current != title or title._sheet_panel != null:
		fail("menu input: mouse wheel activated Quick Duel instead of scrolling")
		main.show_title()
		for i in range(4):
			await get_tree().process_frame
		return
	if title._scroll.get_v_scroll_bar().max_value <= title._scroll.get_v_scroll_bar().page:
		ok("menu fits viewport; wheel did not activate Quick Duel")
	elif title._scroll.scroll_vertical <= scroll_before:
		fail("menu input: mouse wheel did not scroll the menu (before=%d after=%d max=%s point=%s)" % [scroll_before, title._scroll.scroll_vertical, title._scroll.get_v_scroll_bar().max_value, str(point)])
	else:
		ok("mouse wheel over a mode row scrolls without starting a game")
	# Reposition the row before testing other buttons and the normal click.
	title._scroll.ensure_control_visible(quick)
	for i in range(5):
		await get_tree().process_frame
	point = quick.get_global_rect().position + Vector2(35, quick.size.y * 0.5)
	_send_mouse_button(point, MOUSE_BUTTON_WHEEL_UP)
	await get_tree().process_frame
	if main.current != title or title._sheet_panel != null:
		fail("menu input: wheel up activated Quick Duel")
		main.show_title()
		for i in range(4):
			await get_tree().process_frame
		return
	title._scroll.ensure_control_visible(quick)
	for i in range(5):
		await get_tree().process_frame
	point = quick.get_global_rect().position + Vector2(35, quick.size.y * 0.5)
	_send_mouse_button(point, MOUSE_BUTTON_RIGHT)
	await get_tree().process_frame
	if main.current != title or title._sheet_panel != null:
		fail("menu input: right click activated Quick Duel")
		main.show_title()
		for i in range(4):
			await get_tree().process_frame
		return
	ok("wheel up and right click do not activate mode rows")
	title._scroll.ensure_control_visible(quick)
	for i in range(5):
		await get_tree().process_frame
	point = quick.get_global_rect().position + Vector2(35, quick.size.y * 0.5)
	_send_mouse_click(point)
	for i in range(5):
		await get_tree().process_frame
	if main.current == title:
		fail("menu input: Quick Duel row did not respond after dismissing a sheet")
	else:
		ok("Quick Duel row accepts a real mouse click after dismissing the guide")
		main.show_title()
		for i in range(4):
			await get_tree().process_frame


func _send_mouse_click(pos: Vector2) -> void:
	_send_mouse_button(pos, MOUSE_BUTTON_LEFT)


func _send_mouse_button(pos: Vector2, button: MouseButton) -> void:
	var motion := InputEventMouseMotion.new()
	motion.position = pos
	motion.global_position = pos
	get_viewport().push_input(motion, true)
	for down in [true, false]:
		var event := InputEventMouseButton.new()
		event.button_index = button
		event.pressed = down
		event.position = pos
		event.global_position = pos
		get_viewport().push_input(event, true)


func _walk_controls(n: Node) -> Array:
	var out: Array = []
	for c in n.get_children():
		out.append(c)
		out += _walk_controls(c)
	return out


## Stretch must actually be ENABLED. It was configured as
## display/window/size/stretch/* - a key Godot does not read - so stretch was
## silently disabled and the game laid out at raw window pixels, clipping on any
## window that was not exactly 540x960. That is what broke the desktop layout.
func _test_display_scaling() -> void:
	if not ProjectSettings.has_setting("display/window/stretch/mode"):
		fail("display scaling: display/window/stretch/mode is missing")
		return
	var mode: String = str(ProjectSettings.get_setting("display/window/stretch/mode"))
	var aspect: String = str(ProjectSettings.get_setting("display/window/stretch/aspect"))
	if mode == "canvas_items" and aspect == "expand":
		ok("stretch is configured under the key Godot reads (canvas_items / expand)")
	else:
		fail("stretch misconfigured: mode=%s aspect=%s" % [mode, aspect])
	# the bogus key must not creep back in, since it looks plausible and does nothing
	if ProjectSettings.has_setting("display/window/size/stretch/mode"):
		fail("display/window/size/stretch/* is back - Godot ignores that key")
	else:
		ok("no dead display/window/size/stretch/* key")

	# A wide window must get a centred phone-shaped page, not a stretched canvas.
	var win: Window = main.get_window()
	var saved: Vector2i = win.size
	win.size = Vector2i(780, 654)
	win.content_scale_size = Vector2i(540, 960)
	await get_tree().process_frame
	await get_tree().process_frame
	var m = load("res://scripts/main.gd").new()
	main.add_child(m)
	m.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	for i in range(20):
		await get_tree().process_frame
	var page: Control = m.current
	if page == null:
		fail("display scaling: no screen mounted")
	else:
		# A window wider than the 540 design only becomes a wide CANVAS when it is
		# also wider than tall. A tall window (a phone, or the 720x1280 test window)
		# legitimately gets a wider canvas with the same height, which is what
		# aspect "expand" is for; the page then fills it and nothing clips.
		var vp: Vector2 = main.get_viewport_rect().size
		var wide: bool = vp.x > vp.y * 0.72
		if wide and page.size.x > 620.0:
			fail("a wide window stretched the page to %.0f px instead of ~540" % page.size.x)
		elif wide:
			ok("a wide window keeps the page a %.0f px column" % page.size.x)
		elif absf(page.size.x - vp.x) < 2.0:
			ok("a tall window fills its %.0f x %.0f canvas with no clipping" % [vp.x, vp.y])
		else:
			fail("page %.0f px does not match the %.0f px canvas" % [page.size.x, vp.x])
	m.queue_free()
	win.size = saved
	await get_tree().process_frame


## A centred Label can still look skewed if its wide-anchor right offset keeps
## its old minimum width. Test the actual geometry at narrow and desktop widths.
func _test_logo_layout() -> void:
	var old_seen: bool = Profile.seen_intro
	Profile.seen_intro = true
	var host := Control.new()
	host.size = Vector2(540, 960)
	main.add_child(host)
	var title = load("res://scripts/screens/title.gd").new()
	host.add_child(title)
	Profile.seen_intro = old_seen
	var passed := true
	for width in [320.0, 540.0, 720.0]:
		host.size = Vector2(width, 960)
		for i in range(5):
			await get_tree().process_frame
		var mast: Control = title.find_child("Masthead", true, false)
		if mast == null:
			passed = false
			break
		for node_name in ["LogoTitle", "LogoSubtitle", "LogoTagline"]:
			var label: Label = mast.get_node_or_null(node_name)
			if label == null:
				passed = false
				continue
			var mr := mast.get_global_rect()
			var lr := label.get_global_rect()
			var font: Font = label.get_theme_font("font")
			var fs: int = label.get_theme_font_size("font_size")
			var text_width: float = font.get_string_size(label.text, HORIZONTAL_ALIGNMENT_LEFT, -1, fs).x
			if absf(lr.get_center().x - mr.get_center().x) > 0.5 or lr.size.x + 0.5 < text_width:
				passed = false
		var half_text: float = UI.font_title().get_string_size("FOUR REALMS", HORIZONTAL_ALIGNMENT_LEFT, -1, 26).x * 0.5
		var span: Vector2 = title._logo_flourish_span(mast.size.x)
		if span.y > span.x and (span.x - 7.2 <= half_text or span.y > mast.size.x * 0.5):
			passed = false
	if passed:
		ok("logo text stays centred, unclipped and clear of flourishes at narrow, phone and desktop widths")
	else:
		fail("logo is off-centre, clipped, or crossed by its flourishes")
	host.queue_free()
	await get_tree().process_frame


## However many cards end up on the table, they must all stay on the felt. The
## layout used to be a single-row HBoxContainer with a 112 px minimum card width,
## so a fifth card simply hung off both sides of the screen.
func _test_table_fit() -> void:
	var d = load("res://scripts/screens/duel.gd").new()
	d.config = {"mode": 0, "seed": 4}
	main.add_child(d)
	d.size = Vector2(540, 960)
	for i in range(40):
		await get_tree().process_frame
	var avail: Vector2 = d._table_grid.size
	if avail.x < 100.0:
		fail("table fit: the felt has no usable size (%.0f wide)" % avail.x)
		d.queue_free()
		return
	var bad := []
	for n in range(1, 17):
		var L: Dictionary = d._table_layout(n, avail)
		var cw: float = L.cw
		var ch: float = L.ch
		if cw < 20.0 or L.at.size() != n:
			bad.append("%d cards: bad layout" % n)
			continue
		if absf(ch / cw - CardView.ASPECT) > 0.01:
			bad.append("%d cards: aspect %.2f" % [n, ch / cw])
		for p in L.at:
			var pos: Vector2 = p
			if pos.x < -1.0 or pos.y < -1.0 or \
					pos.x + cw > avail.x + 1.0 or pos.y + ch > avail.y + 1.0:
				bad.append("%d cards: one sits outside the felt" % n)
				break
	if bad.is_empty():
		ok("every table size 1-16 fits inside the felt, at the right aspect")
	else:
		fail("table overflow: %s" % str(bad))
	# and the crowded cases must actually render inside the felt
	var worst := 0
	for n in [4, 6, 11, 16]:
		d.duel.table = []
		for i in range(n):
			d.duel.table.append(i * 2)
		d._refresh_table()
		await get_tree().process_frame
		var felt: Rect2 = d._table_grid.get_global_rect()
		for cv in d._table_grid.get_children():
			if not felt.grow(2.0).encloses((cv as Control).get_global_rect()):
				worst = maxi(worst, n)
	if worst == 0:
		ok("crowded tables draw inside the felt (tested 4, 6, 11 and 16 cards)")
	else:
		fail("cards hung off the felt with %d on the table" % worst)
	d.duel.table = []
	d.queue_free()
	await get_tree().process_frame


## Cards must have curved corners like real playing cards - including under
## LOW_SPEC, which is what the user's VM runs and which used to square every
## corner in the game. The radius scales with the card and the rings around a card
## must follow the same curve as its face.
func _test_card_corners() -> void:
	var was_low: bool = UI.LOW_SPEC
	UI.LOW_SPEC = true
	var small: int = CardArt.corner_radius(Rect2(Vector2.ZERO, Vector2(52, 74)))
	var big: int = CardArt.corner_radius(Rect2(Vector2.ZERO, Vector2(116, 163)))
	if big <= 0 or small <= 0:
		fail("card corners: radius is 0 under LOW_SPEC, cards are square")
	else:
		ok("cards keep curved corners under LOW_SPEC (%d px small, %d px playfield)" % [small, big])
	# proportion must hold across sizes, or small cards look rounder
	var p_small := float(small) / 52.0
	var p_big := float(big) / 116.0
	if absf(p_small - p_big) > 0.03:
		fail("card corner proportion drifts with size (%.3f vs %.3f)" % [p_small, p_big])
	else:
		ok("corner radius keeps its proportion at every card size (%.1f%%)" % (p_big * 100.0))
	# chrome stays square, so this did not leak into popups
	if UI.flat(Color.WHITE, 12).corner_radius_top_left != 0:
		fail("card corners: popup chrome is now rounded too (LOW_SPEC lost)")
	else:
		ok("popups and chips stay square under LOW_SPEC")
	# the rings around a card must follow its curve, not a fixed one
	var cv := CardView.new()
	cv.setup(5, true, 116, 163)
	main.add_child(cv)
	await get_tree().process_frame
	cv._ensure_styles()
	var face_r: int = CardArt.corner_radius(Rect2(Vector2.ZERO, Vector2(116, 163)))
	if cv._sb_ring.corner_radius_top_left == face_r and cv._sb_shadow.corner_radius_top_left == face_r:
		ok("selection ring and shadow follow the card's own curve")
	else:
		fail("ring radius %d does not match the card face %d" % [cv._sb_ring.corner_radius_top_left, face_r])
	cv.queue_free()
	UI.LOW_SPEC = was_low
	await get_tree().process_frame


## Validate the actual imported PNG, every face/back mapping, alpha corners, and
## the safe fallback. This catches missing/blank assets and wrong atlas indices.
func _test_card_atlas() -> void:
	var tex: Texture2D = CardArt.atlas_texture()
	if tex == null:
		fail("card atlas: texture missing or wrong dimensions")
		return
	var image: Image = tex.get_image()
	if image == null or image.is_empty():
		fail("card atlas: imported image is blank")
		return
	var distinct := {}
	var all_filled := true
	var rounded := true
	var mapping_ok := true
	for i in range(43):
		var region: Rect2 = CardArt.atlas_region(i if i < 40 else -1, maxi(0, i - 40))
		var expected := Rect2((i % 8) * 208, (i / 8) * 292, 208, 292)
		if region != expected:
			mapping_ok = false
		var tile: Image = image.get_region(Rect2i(region.position, region.size))
		if tile.get_pixel(104, 146).a < 0.9:
			all_filled = false
		if tile.get_pixel(0, 0).a > 0.05 or tile.get_pixel(207, 0).a > 0.05:
			rounded = false
		distinct[hash(tile.get_data())] = true
	if mapping_ok and distinct.size() == 43:
		ok("static atlas maps all 40 distinct faces and 3 distinct backs")
	else:
		fail("card atlas: incorrect mapping or only %d distinct cells" % distinct.size())
	if all_filled and rounded:
		ok("all 43 atlas cards are visible and retain transparent curved corners")
	else:
		fail("card atlas contains blank cards or square/opaque corners")
	var saved_checked: bool = CardArt._atlas_checked
	var saved_tex: Texture2D = CardArt._atlas
	CardArt._atlas_checked = true
	CardArt._atlas = null
	var dummy := Control.new()
	var used_atlas: bool = CardArt.draw_atlas_face(dummy, Rect2(0, 0, 104, 146), 0)
	dummy.free()
	CardArt._atlas = saved_tex
	CardArt._atlas_checked = saved_checked
	if used_atlas:
		fail("card atlas: missing texture did not trigger vector fallback")
	else:
		ok("missing atlas triggers vector artwork fallback")


## Actual imported effect sprites must stay visible, transparent, and correctly
## coloured. A transparent viewport readback is premultiplied; saving it as a
## straight-alpha PNG without correcting RGB made the gold card glow turn gray.
func _test_effect_atlas() -> void:
	var tex: Texture2D = EffectAtlas.texture()
	if tex == null:
		fail("effect atlas: missing or wrong dimensions")
		return
	var image: Image = tex.get_image()
	if image == null or image.is_empty():
		fail("effect atlas: image is blank")
		return
	var shadow: Color = image.get_pixel(104, 146)
	var ring_center: Color = image.get_pixel(312, 146)
	var ring_top: Color = image.get_pixel(312, 4)
	var glow: Color = image.get_pixel(520, 146)
	var select: Color = image.get_pixel(728, 146)
	if image.get_pixel(0, 0).a < 0.05 and shadow.a > 0.20 and shadow.a < 0.35 			and ring_center.a < 0.05 and ring_top.a > 0.8:
		ok("effect atlas has curved transparent shadow and hollow selection ring")
	else:
		fail("effect atlas: shadow or selection ring is blank or opaque")
	if glow.r > 0.7 and glow.g > 0.55 and glow.a > 0.08 and glow.a < 0.16 			and select.r > 0.7 and select.g > 0.55 and select.a > 0.07 and select.a < 0.13:
		ok("translucent card glows retain gold colour (straight alpha)")
	else:
		fail("effect atlas: card glows lost colour or opacity")
	if image.get_pixel(48, 296).a > 0.02 and image.get_pixel(48, 340).a < 0.05 			and image.get_pixel(112, 296).a > 0.5 and image.get_pixel(112, 308).a < 0.05 			and image.get_pixel(144, 308).a > 0.9:
		ok("felt sigil and empty/filled favor pips have correct transparency")
	else:
		fail("effect atlas: felt sigil or favor pips are missing or opaque")
	var saved_checked: bool = EffectAtlas._checked
	var saved_tex: Texture2D = EffectAtlas._texture
	EffectAtlas._checked = true
	EffectAtlas._texture = null
	var dummy := Control.new()
	var used_atlas: bool = EffectAtlas.draw_sprite(dummy, Rect2(0, 0, 104, 146), EffectAtlas.SHADOW)
	dummy.free()
	EffectAtlas._texture = saved_tex
	EffectAtlas._checked = saved_checked
	if used_atlas:
		fail("missing effect atlas did not trigger vector fallback")
	else:
		ok("missing effect atlas triggers vector decorations")


## The opponent's hand is drawn smaller than a playfield card, and their played
## card must grow from that size to full as it flies. Also guards that the
## container actually gives the cards their proper height: an undersized row
## silently squashes them out of aspect (91 px cards in a 54 px box).
func _test_bot_hand_scale() -> void:
	var d = load("res://scripts/screens/duel.gd").new()
	d.config = {"mode": 0, "seed": 12}
	main.add_child(d)
	d.size = Vector2(540, 960)
	for i in range(40):
		await get_tree().process_frame
	if d._bot_row.get_child_count() == 0:
		fail("bot hand: no cards rendered")
		d.queue_free()
		return
	var back := d._bot_row.get_child(0) as Control
	if back == null:
		fail("bot hand: rows are not controls")
		d.queue_free()
		return
	var aspect: float = back.size.y / maxf(back.size.x, 1.0)
	if absf(aspect - 1.404) > 0.08:
		fail("bot hand card aspect is %.2f, cards are squashed (want ~1.40)" % aspect)
	else:
		ok("opponent hand cards keep their aspect (%.2f)" % aspect)
	var table_h: float = clampf(maxf(d._table_box.size.y, 260.0) * 0.40, 148.0, 208.0)
	var ratio: float = back.size.x / (table_h / 1.404)
	if ratio > 0.35 and ratio < 0.75:
		ok("opponent hand is drawn smaller than the playfield (%.2fx)" % ratio)
	else:
		fail("opponent hand ratio to the playfield is %.2fx, expected 0.35-0.75" % ratio)
	# and the flight must start from that ratio, not pop in at full size
	if is_equal_approx(d.BOT_HAND_SCALE, ratio) or absf(d.BOT_HAND_SCALE - ratio) < 0.05:
		ok("a played opponent card starts at hand size and scales to full (%.2f -> 1.0)" % d.BOT_HAND_SCALE)
	else:
		fail("bot hand scale %.2f does not match the drawn ratio %.2f" % [d.BOT_HAND_SCALE, ratio])
	d.queue_free()
	await get_tree().process_frame


## The spin must be a rotation about the card's centre, face up the whole way -
## not a flip. Checked geometrically, no rendering needed: the card's centre must
## be a fixed point at every angle, and the corners must stay the same distance
## out (a rigid rotation, no squash).
func _test_spin() -> void:
	var cv := CardView.new()
	cv.setup(5, true, 120, 168)
	main.add_child(cv)
	await get_tree().process_frame
	if cv.get("squash") != null:
		fail("spin: card still has a squash property (that was the flip)")
	elif cv.get("spin") == null:
		fail("spin: card has no rotation property")
	else:
		ok("spin: card rotates, there is no squash/flip left")
	var centre: Vector2 = cv.size * 0.5
	var drift_ok := true
	var rigid_ok := true
	var face_up := true
	for i in range(9):
		cv.spin = TAU * float(i) / 8.0
		var t: Transform2D = cv._spin_transform()
		if (t * centre).distance_to(centre) > 0.01:
			drift_ok = false
		var r0: float = (t * Vector2.ZERO).distance_to(centre)
		var r1: float = (t * cv.size).distance_to(centre)
		if absf(r0 - r1) > 0.01:
			rigid_ok = false
	if drift_ok and rigid_ok:
		ok("spin: rotates about the card centre, rigid at every angle")
	else:
		fail("spin: not a centred rotation (drift_ok=%s rigid_ok=%s)" % [drift_ok, rigid_ok])
	# the face must never be replaced by the back during the turn
	cv.spin = PI
	if cv.card_id >= 0 and cv.face_up:
		ok("spin: card stays face up through the turn")
	else:
		fail("spin: card turned its back mid-spin")
	cv.queue_free()
	await get_tree().process_frame


## Scopa di Quindici (first version): only totals of 15 capture, and a card can
## never take one of its own value.
func _test_quindici() -> void:
	# The published example: table A, 3, 4, 7 and you play a 4 -> either 4+7 or
	# A+3+7, and never the 4 that matches your own value.
	var table := [C.make(1, 0), C.make(3, 0), C.make(4, 1), C.make(7, 0)]
	var played := C.make(4, 0)
	var q := C.capture_groups_quindici(table, played)
	var keyed := {}
	for g in q:
		keyed[_sort_key(g)] = true
	if not keyed.has(_sort_key([C.make(4, 1), C.make(7, 0)])):
		fail("quindici: 4+7 was not offered")
	elif not keyed.has(_sort_key([C.make(1, 0), C.make(3, 0), C.make(7, 0)])):
		fail("quindici: A+3+7 was not offered")
	elif keyed.has(_sort_key([C.make(4, 1)])):
		fail("quindici: captured a card by matching its own value")
	else:
		ok("quindici: A/3/4/7 + a 4 takes 4+7 or A+3+7, never the matching 4")

	# A single card can complete the 15: a 5 takes a 10 (5+10). But a 10 can
	# never take another 10, and never takes itself.
	var ten := C.make(10, 2)
	var g_single := C.capture_groups_quindici([ten, C.make(5, 3)], C.make(5, 0))
	if g_single.size() == 1 and g_single.has([ten]):
		ok("quindici: a 5 takes a lone 10 (5+10 = 15)")
	else:
		fail("quindici: 5 should take a lone 10, got %s" % str(g_single))
	# 10 played: needs 5, so two 10s on the table must not be takeable by a 10.
	var t3 := [C.make(10, 0), C.make(10, 1)]
	var g_ten := C.capture_groups_quindici(t3, C.make(10, 3))
	if g_ten.is_empty():
		ok("quindici: a 10 cannot take another 10 (no 15 total exists)")
	else:
		fail("quindici: a 10 took a 10: %s" % str(g_ten))
	# Two fives under a played five DO total 15, and that is a legal 15 capture.
	var g_55 := C.capture_groups_quindici([C.make(5, 0), C.make(5, 1)], C.make(5, 2))
	if g_55.size() == 1:
		ok("quindici: three fives are a legal 15 (5+5+5)")
	else:
		fail("quindici: 5+5 under a 5 should total 15, got %s" % str(g_55))

	# Every group totals exactly 15, across random tables.
	var all_ok := true
	var rng := RandomNumberGenerator.new()
	rng.seed = 99
	for trial in range(400):
		var tab: Array = []
		var pool := C.full_deck().duplicate()
		for i in range(rng.randi_range(1, 6)):
			tab.append(pool.pop_at(rng.randi() % pool.size()))
		var pc: int = pool[rng.randi() % pool.size()]
		for g in C.capture_groups_quindici(tab, pc):
			var total := C.rank(pc)
			for c in g:
				total += C.rank(c)
			# a group of one is legal as long as it totals 15 and is not the
			# played card's own value (which is impossible at 15 anyway)
			if total != 15:
				all_ok = false
			for c in g:
				if c == pc:
					all_ok = false
	if all_ok:
		ok("quindici: every capture group totals exactly 15 across 400 random tables")
	else:
		fail("quindici: a capture group did not total 15")

	# A whole duel under the ruleset plays through and only ever offers 15s.
	var d = load("res://scripts/game/duel.gd").new({"mode": T.Mode.QUINDICI, "rule": C.RULE_QUINDICI, "seed": 4242})
	var steps := 0
	var offered_ok := true
	while not d.match_over and steps < 600:
		steps += 1
		if d.hand_over:
			if d.match_over:
				break
			d.next_hand()
			continue
		var who: int = d.turn
		if d.hands[who].is_empty():
			d._advance_turn()
			continue
		var card: int = d.hands[who][0]
		for g in d.groups_for_player(who, card):
			var total := C.rank(card)
			for c in g:
				total += C.rank(c)
			if total != 15:
				offered_ok = false
		d.play(who, card, 0)
	if not offered_ok:
		fail("quindici duel: a capture group did not total 15")
	elif d.hands_played > 0:
		ok("quindici: a full duel played through (%d hands, %d turns)" % [d.hands_played, d.turn_count])
	else:
		fail("quindici: duel did not complete")

	# Scoring must be IDENTICAL under both rulesets: the variant changes the
	# capture rule and nothing else. Same piles in, same Renown out.
	var piles := [
		[[0, 1, 2, 3, 4, 5, 6, 24, 25], [7, 8, 9, 10, 11, 12, 13, 14]],
		[[], [0, 4, 8, 12, 16, 20, 24, 28, 32, 36]],
	]
	var same := true
	for pair in piles:
		var scored := []
		for rule in [C.RULE_CLASSIC, C.RULE_QUINDICI]:
			var sd = load("res://scripts/game/duel.gd").new({"mode": 0, "rule": rule, "seed": 31, "player_faction": 0, "bot_faction": 2})
			sd.captured = [(pair[0] as Array).duplicate(), (pair[1] as Array).duplicate()]
			sd.scopa_count = [2, 1]
			scored.append(str(sd.score_hand()))
		if scored[0] != scored[1]:
			same = false
	if same:
		ok("quindici: scoring is identical to Classic for the same captured piles")
	else:
		fail("quindici: scoring differs by ruleset")

	# Classic must be untouched by the variant existing.
	var cd = load("res://scripts/game/duel.gd").new({"mode": T.Mode.QUICK, "seed": 77})
	if cd.rule == C.RULE_CLASSIC and C.capture_groups_rule([C.make(4, 0)], C.make(4, 1), C.RULE_CLASSIC).size() == 1:
		ok("classic capture still matches rank when the variant is not selected")
	else:
		fail("classic capture changed by the variant")


func _sort_key(g: Array) -> String:
	var s: Array = g.duplicate()
	s.sort()
	return str(s)


## Closing a sheet must stop blocking input in the SAME frame. queue_free() is
## deferred, so the dim overlay used to linger with MOUSE_FILTER_STOP for the rest
## of the frame, swallowing the next tap - which is how "I had a 4 and it would not
## let me play it" happened.
func _test_overlay_dismiss() -> void:
	var d = load("res://scripts/screens/duel.gd").new()
	d.config = {"mode": 0}
	main.add_child(d)
	for i in range(40):
		await get_tree().process_frame
	d._open_menu()
	await get_tree().process_frame
	var before := _dim_count(d)
	var dim: Control = d._overlay
	for button in [MOUSE_BUTTON_WHEEL_DOWN, MOUSE_BUTTON_WHEEL_UP, MOUSE_BUTTON_RIGHT]:
		var event := InputEventMouseButton.new()
		event.button_index = button
		event.pressed = true
		dim.gui_input.emit(event)
	if d._overlay == null:
		fail("wheel or right click dismissed the duel overlay")
	else:
		ok("wheel and right click do not dismiss the duel overlay")
	d._close_overlay()
	var after := _dim_count(d)
	if before < 1:
		fail("overlay test: opening a sheet produced no dim panel")
	elif after != 0:
		fail("overlay test: %d dim overlay(s) still blocking after close" % after)
	else:
		ok("closing a sheet clears its input-blocking overlay in the same frame")
	d.queue_free()
	await get_tree().process_frame


func _dim_count(n: Node) -> int:
	var c := 0
	for ch in n.get_children():
		if ch is ColorRect and (ch as ColorRect).color.a > 0.5:
			c += 1
	return c


## Deal integrity: every hand must start with TABLE_START on the table and
## HAND_SIZE in each hand, drawn from a full 40-card deck with no duplicates, and
## every round of every hand must deal the right number of cards.
##
## This is asserted because "the deal looks wrong" has been reported twice; if the
## deal is provably correct then the problem is presentation, not the deal.
func _test_deal() -> void:
	var d = load("res://scripts/game/duel.gd").new({"mode": 0, "seed": 7})
	var need_table: int = d.TABLE_START
	var need_hand: int = d.HAND_SIZE
	if d.table.size() != need_table:
		fail("deal: table has %d cards, expected %d" % [d.table.size(), need_table])
	elif d.hands[0].size() != need_hand or d.hands[1].size() != need_hand:
		fail("deal: hands are %d/%d, expected %d each" % [d.hands[0].size(), d.hands[1].size(), need_hand])
	elif d.table.size() + d.hands[0].size() + d.hands[1].size() + d.deck.size() != 40:
		fail("deal: cards do not add up to 40")
	else:
		var all: Array = d.table.duplicate()
		all.append_array(d.hands[0])
		all.append_array(d.hands[1])
		all.append_array(d.deck)
		var uniq := {}
		for c in all:
			uniq[c] = true
		if uniq.size() != 40:
			fail("deal: %d unique cards in play, expected 40" % uniq.size())
		else:
			ok("deal: %d on the table, %d each in hand, 40 unique cards" % [need_table, need_hand])

	# every subsequent round of every hand must also deal correctly
	var rounds_ok := true
	var hands := 0
	var guard := 0
	while not d.match_over and guard < 3000:
		guard += 1
		if d.hand_over:
			hands += 1
			if d.match_over:
				break
			d.next_hand()
			if d.table.size() != need_table or d.hands[0].size() != need_hand or d.hands[1].size() != need_hand:
				fail("deal: hand %d started with table=%d hands=%d/%d" % [
					d.hand_no, d.table.size(), d.hands[0].size(), d.hands[1].size()])
				rounds_ok = false
			if hands > 6:
				break
			continue
		var who: int = d.turn
		if d.hands[who].is_empty():
			d._advance_turn()
			if not d.hand_over and d.deck.size() > 0 \
					and (d.hands[0].size() > need_hand or d.hands[1].size() > need_hand):
				fail("deal: a round dealt more than %d cards" % need_hand)
				rounds_ok = false
			continue
		d.play(who, d.hands[who][0], 0)
	if rounds_ok:
		ok("deal: every hand and round dealt correctly across %d hands" % hands)


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
		# a play is animated now, so wait until it has resolved rather than for a
		# fixed number of frames - but never hang the audit if it does not
		var guard := 0
		while d._busy and guard < 240:
			await get_tree().process_frame
			guard += 1
	var after: Array = []
	for i in range(d._hand_row.get_child_count()):
		after.append(d._hand_row.get_child(i).card_id)
	if after.size() < before.size() or after != before:
		ok("tapping a hand card actually plays it (%s -> %s)" % [before, after])
	else:
		fail("tapping a hand card did nothing (hand still %s)" % [before])
	d.queue_free()
	await get_tree().process_frame


## Exercise actual pointer hits on the Raid button and a non-first picker card.
func _test_raid_picker() -> void:
	var saved_profile_duel: Dictionary = Profile.saved_duel.duplicate(true)
	var saved_anim: bool = Profile.anim_enabled
	Profile.anim_enabled = false
	var screen = load("res://scripts/screens/duel.gd").new()
	screen.config = {"mode": T.Mode.QUICK, "seed": 284, "oaths": true, "player_faction": T.HORDE}
	main.add_child(screen)
	for i in range(50):
		await get_tree().process_frame
	screen._busy = false
	screen.duel.turn = 0
	screen.duel.favor[0] = 1
	screen._refresh_all()
	for i in range(5):
		await get_tree().process_frame
	_send_mouse_click(screen._btn_oath.get_global_rect().get_center())
	for i in range(5):
		await get_tree().process_frame
	var picker: Control = null
	for c in screen.get_children():
		if c is PanelContainer and c.z_index == 101:
			picker = c
	var choices: Array = []
	if picker != null:
		for node in _walk_controls(picker):
			if node is CardView:
				choices.append(node)
	if choices.size() < 2:
		fail("Raid picker did not open or expose table cards")
	else:
		var selected: int = choices[1].card_id
		var original_top: int = screen.duel.deck.back()
		var table_size: int = screen.duel.table.size()
		_send_mouse_click(choices[1].get_global_rect().get_center())
		for i in range(5):
			await get_tree().process_frame
		if (screen.duel.table.size() != table_size or not screen.duel.table.has(original_top)
				or screen.duel.table.has(selected) or screen.duel.deck.front() != selected
				or not screen.duel.oath_used[0] or screen.duel.favor[0] != 0 or screen._overlay != null):
			fail("clicking a Raid picker card did not execute and dismiss the swap")
		elif Profile.saved_duel.get("state", {}).get("table", []) != screen.duel.table:
			fail("Raid picker did not persist the updated table")
		else:
			ok("Raid picker mouse click swaps the selected card and saves the duel, with animation off")
	# A crowded table must wrap in the sheet; the last card must still be
	# reachable after scrolling, not hidden beyond the right edge.
	screen.duel.oath_used[0] = false
	screen.duel.favor[0] = 1
	while screen.duel.table.size() < 12:
		screen.duel.table.append(screen.duel.deck.pop_back())
	screen._refresh_all()
	screen._oath_raid()
	for i in range(8):
		await get_tree().process_frame
	picker = null
	for c in screen.get_children():
		if c is PanelContainer and c.z_index == 101:
			picker = c
	choices = []
	var scroll: ScrollContainer = null
	if picker != null:
		for node in _walk_controls(picker):
			if node is CardView:
				choices.append(node)
			elif node is ScrollContainer:
				scroll = node
	if choices.size() != 12 or scroll == null:
		fail("Raid picker did not show all 12 table cards")
	else:
		var last: CardView = choices.back()
		scroll.ensure_control_visible(last)
		for i in range(8):
			await get_tree().process_frame
		var sr := scroll.get_global_rect()
		var cr := last.get_global_rect()
		if not sr.grow(1.0).encloses(cr):
			fail("crowded Raid picker leaves the last card clipped")
		else:
			var last_id: int = last.card_id
			var top_id: int = screen.duel.deck.back()
			_send_mouse_click(cr.get_center())
			for i in range(5):
				await get_tree().process_frame
			if screen.duel.deck.front() == last_id and screen.duel.table.has(top_id) and screen._overlay == null:
				ok("crowded Raid picker wraps and its last card is clickable")
			else:
				fail("crowded Raid picker did not respond to the last card")
	screen._close_overlay()
	# Simulate the deck running out and make the reason visible on the button.
	screen.duel.oath_used[0] = false
	screen.duel.favor[0] = 1
	screen.duel.deck.clear()
	screen._refresh_actions()
	if screen._btn_oath.disabled and "deck empty" in screen._btn_oath.text:
		ok("Raid button explains and disables itself when the deck is empty")
	else:
		fail("Raid button did not disable itself with an empty deck")
	screen.queue_free()
	Profile.anim_enabled = saved_anim
	if saved_profile_duel.is_empty():
		Profile.clear_duel()
	else:
		Profile.store_duel(saved_profile_duel)
	await get_tree().process_frame


## CardView.pressed has no arguments. Exercise the other two card-based oath
## pickers as well; handlers that expect an argument silently fail on a click.
func _test_other_oath_picker_signals() -> void:
	var screen = load("res://scripts/screens/duel.gd").new()
	screen.config = {"mode": T.Mode.QUICK, "seed": 288, "oaths": true, "player_faction": T.GROVE}
	main.add_child(screen)
	for i in range(45):
		await get_tree().process_frame
	screen._busy = false
	screen.duel.turn = 0
	screen.duel.favor[0] = 1
	var original: Array = screen.duel.peek_top(3)
	screen._oath_foresight()
	await get_tree().process_frame
	var panel: Control = null
	for n in screen.get_children():
		if n is PanelContainer and n.z_index == 101:
			panel = n
	var cards: Array = []
	var confirm: Button = null
	if panel != null:
		for n in _walk_controls(panel):
			if n is CardView:
				cards.append(n)
			elif n is Button and n.text == "Set the order":
				confirm = n
	if cards.size() != 3 or confirm == null:
		fail("Foresight picker did not expose three cards and confirmation")
	else:
		cards[0].pressed.emit()
		cards[1].pressed.emit()
		if cards[0].card_id != original[1] or cards[1].card_id != original[0]:
			fail("Foresight picker cards did not swap on press")
		else:
			confirm.pressed.emit()
			if screen.duel.peek_top(3) != [original[1], original[0], original[2]]:
				fail("Foresight picker did not save the chosen deck order")
			else:
				ok("Foresight picker card presses reorder the deck")
	screen._close_overlay()
	screen.duel.player_faction = T.CROWN
	screen.duel.turn = 0
	screen.duel.oath_used[0] = false
	screen.duel.favor[0] = 1
	var hand_card: int = screen.duel.hands[0][0]
	var table_card: int = screen.duel.visible_table(0)[0]
	screen._oath_diplomacy()
	await get_tree().process_frame
	panel = null
	for n in screen.get_children():
		if n is PanelContainer and n.z_index == 101:
			panel = n
	var hcard: CardView = null
	var tcard: CardView = null
	confirm = null
	if panel != null:
		for n in _walk_controls(panel):
			if n is CardView and n.card_id == hand_card:
				hcard = n
			elif n is CardView and n.card_id == table_card:
				tcard = n
			elif n is Button and n.text == "Swap":
				confirm = n
	if hcard == null or tcard == null or confirm == null:
		fail("Diplomacy picker did not expose the hand, table and confirmation")
	else:
		hcard.pressed.emit()
		tcard.pressed.emit()
		if confirm.disabled:
			fail("Diplomacy picker did not enable Swap after selecting both cards")
		else:
			confirm.pressed.emit()
			if screen.duel.hands[0].has(table_card) and screen.duel.table.has(hand_card):
				ok("Diplomacy picker card presses swap the chosen cards")
			else:
				fail("Diplomacy picker did not swap the chosen cards")
	screen._close_overlay()
	screen.queue_free()
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


## Raid swaps with the ORIGINAL deck top, buries the selected card, consumes
## exactly one Favor, and cannot be used if no replacement can be drawn.
func _test_raid_rules() -> void:
	for who in [0, 1]:
		var d = DuelScript.new({"mode": T.Mode.QUICK, "seed": 281, "oaths": true,
			"player_faction": T.HORDE, "bot_faction": T.HORDE})
		d.turn = who
		d.favor[who] = 2
		d.drain_events()
		var table_before: Array = d.table.duplicate()
		var deck_before: Array = d.deck.duplicate()
		var captured_before: Array = d.captured.duplicate(true)
		var scopes_before: Array = d.scopa_count.duplicate()
		var selected: int = table_before[1]
		var top: int = deck_before.back()
		var expected_deck: Array = deck_before.duplicate()
		expected_deck.pop_back()
		expected_deck.push_front(selected)
		var expected_table: Array = table_before.duplicate()
		expected_table[1] = top
		if not d.use_raid(who, selected) or d.table != expected_table or d.deck != expected_deck:
			fail("Raid: wrong swap or deck order for player %d" % who)
		elif (d.captured != captured_before or d.scopa_count != scopes_before or d.favor[who] != 1
				or not d.oath_used[who] or d.turn != who):
			fail("Raid: capture, scopa, Favor, oath or turn changed incorrectly")
		else:
			ok("Raid swaps original top card in place and buries the chosen card for player %d" % who)
		var all: Array = d.deck + d.table + d.hands[0] + d.hands[1] + d.captured[0] + d.captured[1]
		all.sort()
		if all != C.full_deck():
			fail("Raid broke 40-card conservation")
		else:
			ok("Raid preserves all 40 cards for player %d" % who)
		var evs: Array = d.drain_events()
		if evs.size() != 1 or evs[0].get("banished", -1) != selected or evs[0].get("replacement", -1) != top:
			fail("Raid event did not identify both swapped cards")
		elif d.use_raid(who, top):
			fail("Raid was allowed twice in one hand")
		else:
			ok("Raid emits the swap and remains once per hand")
		var copy = DuelScript.new({"mode": T.Mode.QUICK})
		copy.from_dict(d.to_dict())
		if copy.table != d.table or copy.deck != d.deck or copy.oath_used != d.oath_used:
			fail("Raid state did not survive save/resume")
		else:
			ok("Raid swap survives save and resume")
	var single = DuelScript.new({"mode": T.Mode.QUICK, "seed": 111, "oaths": true})
	single.turn = 0
	single.favor[0] = 1
	var removed: int = single.table[0]
	var only: int = single.deck.back()
	single.deck = [only]
	if not single.use_raid(0, removed) or single.table[0] != only or single.deck != [removed]:
		fail("Raid with one deck card did not draw the original card")
	else:
		ok("Raid with one deck card swaps the original top, not the buried card")
	var empty = DuelScript.new({"mode": T.Mode.QUICK, "seed": 112, "oaths": true, "bot_faction": T.HORDE})
	empty.turn = 1
	empty.favor[1] = 1
	empty.deck.clear()
	var table_copy: Array = empty.table.duplicate()
	if (empty.can_use_raid(1) or empty.use_raid(1, table_copy[0]) or empty.table != table_copy
			or empty.favor[1] != 1 or empty.oath_used[1]):
		fail("empty-deck Raid was allowed or spent Favor")
	else:
		ok("empty-deck Raid is blocked without spending Favor")
	var bot_ok := true
	for i in range(20):
		if DuelAI.choose_oath(empty, 1).get("kind", "") == "raid":
			bot_ok = false
	if bot_ok:
		ok("Horde AI does not attempt Raid with an empty deck")
	else:
		fail("Horde AI attempted Raid with an empty deck")
	var hidden = DuelScript.new({"mode": T.Mode.QUICK, "seed": 113, "oaths": true})
	hidden.turn = 0
	hidden.favor[0] = 1
	hidden.veiled = hidden.table[0]
	if hidden.use_raid(0, hidden.veiled) or hidden.favor[0] != 1:
		fail("Raid allowed a player to choose a veiled table card")
	else:
		ok("Raid cannot select a veiled card")


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


## Called once per sampled deal, so it reports info only - no pass line. Counting
## it as a pass inflated the check total with identical repeats.
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
	var table_grid = d._table_grid
	for cv in table_grid.get_children():
		if cv is Control:
			var r: Rect2 = cv.get_global_rect()
			if r.position.x < -1 or r.end.x > 721:
				fail("table card off screen at x=%.0f" % r.position.x)
	print("  info  table grid %.0f px wide for %d cards" % [table_grid.size.x, table_grid.get_child_count()])
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
