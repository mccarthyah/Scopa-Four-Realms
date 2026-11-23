# Four Realms — engineering assessment

**Scope:** whole repository at `4f770fa` (`arena/2ab8a780-scopa-four-realms`), 2026-11-23.
**Method:** static review of all 9,517 lines of GDScript, asset/export config, CI and docs, plus a
full parse and lint of every script with a real GDScript 4 parser.

**Limits of this assessment.** No Godot binary was available in this environment (the release-asset
host is blocked, and `github.com` only serves the redirect), and the sandbox has no GPU or display.
So nothing here reports observed *runtime* behaviour: layout, drawing, audio and frame timing are
**unverified**. Every claim below is either (a) read directly off the source with a line reference,
or (b) the output of a language-level tool. Findings that depend on runtime behaviour say so.

---

## Verdict

This is an unusually disciplined codebase for a solo Godot project. The rules engine is pure,
UI-free and JSON-serialisable; state validation at the persistence boundary is stricter than most
shipped games; and the audit suite genuinely plays the game (300 AI-vs-AI deals, brute-forced puzzle
solvability, layout-overflow measurement, touch/mouse input simulation). The documentation is
honest about past failures instead of hiding them.

The weak spots are not in the engine — they are at the **edges**: a campaign twist that contradicts
its own documentation, a UI animation queue that never trims, input/pause handling that assumes a
desktop, and the fact that none of the excellent verification work runs automatically.

| Area | Grade | Note |
|---|---|---|
| Rules engine (`game/`) | **A** | Pure, serialisable, RNG-state-accurate, validated round-trip |
| Persistence | **A−** | Atomic writes, strict `valid_save`, legacy-save path; no profile version key |
| Verification (`audit.gd`) | **A−** | 49 test functions; **now executed**, 150 assertions, 0 failures against a headless 4.7.2 build. Top grade withheld: the suite had a latent parse error for the whole audit, so it was never actually running (see *Execution*) |
| UI / screens | **B** | Correct and accessible; four modules extracted (score sheet, oath pickers, card anim, puzzle verdict) take `screens/duel.gd` to 2,063 lines. Still no positional lookups or dead hooks; the hand-summary orchestrator stays, and the file is still the largest screen. A real-device iPad portrait bug was found after this pass — see *Execution* |
| Platform (Android/iOS) | **A−** | Back gesture, pause-safe clock, mute, real Android icons; still no pause-on-background |
| Release hygiene | **A** | LICENSE, OFL text, icons on all targets, dev files and dead art excluded |
| Tooling / CI | **A** | lint + audit on every push, Godot pinned by SHA-256; both jobs now observed green on GitHub (PR #1) |
| Lint cleanliness | **A** | 0 syntax errors, 0 lint findings |

Grades above reflect the state after the P1 and P2 work below was completed; the
findings themselves are kept in place as the record of what was wrong and why.

---

## Execution — what changed when the audit actually ran

The first pass of this assessment graded the test suite on reading it. It has since
been run for real, against a headless Godot 4.7.2 built from the `4.7.2-stable`
source (`4.7.2.stable.custom_build`, built with `x11=no vulkan=no opengl3=no`; see
`tools/godot/BUILD.md`). Reading the suite hid three things:

1. **`scripts/audit.gd` did not parse.** `var veil_was_set := d.veiled >= 0` cannot
   infer a type, because `d` is untyped and the comparison yields a `Variant`. The
   entire self-test therefore failed to load, and `safe-check.sh` step 3 could
   never have passed. `gdparse` did not catch it: type inference is not a
   parse-time check. Fixed (`6000d3b`).
2. **The Veiled Warden's veil was capturable by the Warden.** `visible_table(who)`
   hid the veiled card only from player 0, so the bot still saw it and could take
   it inside a capture group; `veiled` was then left pointing at a card no longer
   on the table. Reproduced on 3 of 60 seeded deals. Fixed (`b58fb2c`), and
   `veil_lifted` is now serialised so a resumed duel cannot re-veil.
3. **`safe-check.sh` could not pass with a non-fontconfig build.** It treated every
   `ERROR` line as an import failure, including Godot's "compiled without
   fontconfig" capability notice. Fixed (`9d98f0a`).

It was also committed without the executable bit, despite documenting
`./safe-check.sh` as its own entry point (`52ce991`).

Result after the fixes:

```
$ GODOT=/tmp/gbin/godot ./safe-check.sh
[1/3] Importing assets        ok — 51 assets, no errors
[2/3] Booting the game        ok — main loop running, stage -> title
[3/3] Running the self-test   ok — 150 checks passed, 0 failures
ALL HEADLESS CHECKS PASSED.
```

### One more thing running it found: the suite ran twice

The tally itself was wrong at first, and the reason is worth recording. `run()`
ended at 193 checks. It should have ended at 147, because **the whole suite was
executing twice**.

`_test_display_scaling()` builds a probe instance of `scripts/main.gd` to measure
the landscape stage. `main._ready()` starts the audit, and it did so
unconditionally — so that probe launched a *second* complete run from inside a
test. Both runs appended to stdout, so the log looked like one long pass, while
the counters had quietly restarted: the "193" was one run's 46 checks plus the
other run's 147, and the number in `=== AUDIT COMPLETE ===` had always been
just the last one.

`_ready()` now takes an audit only when no other `Main` owns it. Fixed in the
same pass that made the suite print its own count — the count is what exposed it.

### Confirmed independently in CI

The same suite also passes on GitHub, on the *published* binary rather than the
hand-built one — which is the check that matters, because that is what the
workflow will keep running:

```
CI run 45101839204 (PR #1), commit 26ce17d
  ✓ GDScript parse + lint   (gdparse + gdlint, all files)
  ✓ Headless audit          Download and verify Godot · Import assets ·
                            Run the audit
```

Both steps run under `set -euo pipefail`, so `sha256sum -c` passing means the
downloaded archive really did match the pinned
`cadd3204...329e4`, and the `grep -q 'failures=0'` passing means the audit
reported zero failures. That closes the last unverified claim the first pass of
this assessment made — that the CI workflow would work if it ever ran.

What this does **and does not** prove. It proves the rules engine, the AI, the
save/resume round-trip, and that every screen builds and lays out without
overflow at 720×1280 — all without a GPU. It says nothing about rendering: no
window, no shader compilation, no draw call was exercised, and the run reports
`adapter: (none — headless/dummy)`.

### And one thing running it *could not* find: the iPad portrait bars

Reported from a real iPad, which is exactly the class of bug a headless suite is
blind to: landscape looked right, portrait left a dead strip down each side of
the table.

`scripts/main.gd:_layout_stage()` has three cases — tall, wide, and a bounded
column in between. The middle case was keyed on `_is_wide()`, defined as
`v.x > v.y * 0.72`, and clamped the stage to `min(DESIGN_WIDTH, v.x)` = 540. With
`canvas_items` + `expand`, an iPad portrait does not stay at its device
resolution: it scales by `min(dw/540, dh/960)`, and on a 4:3 iPad that is
exactly **720×960**. A ratio of 0.750 clears the 0.72 threshold, so those
devices fell into the desktop rule and got a 540 px column — **90 px unused on
each side**. iPads of other aspect ratios (10.9" at 667×960, Pro 11 at
671×960) sat below 0.72 and filled correctly, which is why it read as one
model doing something strange rather than one rule doing it to all of them.

The rule now clamps only when the window is genuinely wider than it is tall:

```gdscript
var w: float = minf(DESIGN_WIDTH, v.x) if v.x > v.y else v.x
```

Landscape is unchanged (still capped at 1760 for desktop widths); every portrait
iPad now fills its canvas. Three assertions cover the reported devices
(768×1024, 810×1080, 1024×1366), and they were checked in both directions: they
fail with the old line, naming the 90 px strip, and pass with the new one. A
first attempt at that test mounted a probe `Main` and read its current screen —
it passed against the bug, because `_layout_stage()` early-returns for the title
screen, so the clamp was never reached. The test now calls `_layout_stage()`
directly on a bare `Control` and reads the offsets it sets.

The lesson is worth keeping in the document: the headless suite proves the rules,
the AI and the layout arithmetic, and it can only cover a display bug once
somebody has described the symptom well enough to name the device. **A windowed
run is still the only way to see the game.**

---

## Verified facts

```
Parser   gdtoolkit 4.5.0 (GDScript 4 grammar)
Parse    19/19 files OK — but see *Execution*: one type-inference error only
         surfaced at load time, where gdparse does not look
Lint     0 findings (was 307 before the P2 lint pass)
Assets   card atlas 1664×1752 ✔ matches 8×208 × 6×292
         effect atlas 1040×388 ✔ matches EffectAtlas.WIDTH/HEIGHT
         all 12 UI nine-slice frames 96×96 (switches 144×76) ✔
Runtime  Godot 4.7.2 headless — import 51 assets, boot clean, 150 assertions, 0 failures
```

Reproduce:

```bash
python3 -m venv .venv && .venv/bin/pip install gdtoolkit
.venv/bin/gdparse $(find scripts tools -name '*.gd')
.venv/bin/gdlint scripts tools/*.gd | grep -v max-line-length
```

---

## P1 — player-visible defects

### 1. The Veiled Warden's veil lifts and immediately falls again

`scripts/game/duel.gd:250-251`

```gdscript
_reveal_if_thin()      # table.size() <= 2 -> push reveal, veiled = -1
_maybe_hide_table()    # veiled < 0 and table.size() > 1 -> hide a NEW card
```

`_maybe_hide_table()` (`:141-143`) is called unconditionally after every play. As soon as
`_reveal_if_thin()` (`:158-161`) lifts the veil and the table still holds more than one card, the
engine immediately conceals a different card. The player is told "The veil lifts" on the same move
that a new card vanishes.

The README (`:239`) promises: *"one table card is veiled — you can't see or take it **until the
table thins**"*. The code does not do that.

**Why the audit missed it:** `_test_veiled_capture()` (`scripts/audit.gd:2317-2330`) assigns
`duel.veiled` by hand and plays a single move. No test ever deals a full `hidden_table` campaign
hand, so the reveal/re-hide oscillation is never exercised.

**Fix:** make the veil one-way for the hand.

```gdscript
var veil_lifted := false   # reset in start_hand()

func _maybe_hide_table() -> void:
    if campaign.get("twist_kind", "") == "hidden_table" and veiled < 0 \
            and not veil_lifted and table.size() > 1:
        veiled = table[rng.randi() % table.size()]

func _reveal_if_thin() -> void:
    if veiled >= 0 and table.size() <= 2:
        _push({"t": "reveal", "card": veiled})
        veiled = -1
        veil_lifted = true
```

Then add the missing audit: play one full `CAMPAIGNS[0]` deal with `DuelAI` and assert that after the
`reveal` event no subsequent `table` change reduces the player's visible set without a `play`.

### 2. The toast queue never trims

`scripts/screens/duel.gd:1687-1689`

```gdscript
while _toast_box.get_child_count() > 3:
    _toast_box.get_child(0).queue_free()
    break
```

Two bugs in three lines. The `break` makes the `while` an `if`, so at most one toast is retired per
new toast. And `queue_free()` is deferred, so the child is still counted by `get_child_count()`
inside the loop body. Every toast is a `PanelContainer` carrying its own tween, added over a
~4-minute duel — the box only ever grows.

**Fix:**

```gdscript
while _toast_box.get_child_count() > 3:
    _remove_now(_toast_box.get_child(0))
```

`_remove_now()` already exists (`:1914`) and does the detach-then-defer that the rest of this file
documents at length. This is the one place that pattern was not used.

### 3. Browsing a sheet spends the player's turn clock

`scripts/screens/duel.gd:2271-2281` gates the timer on `is_my_turn(0) and not _busy`. `_busy` is set
in exactly four places (`:1066`, `:1149`, `:1927`, `:2226`) — all animation or summary paths. Opening
an `_oath_sheet()` (`:1793`) does **not** set `_busy` and does not pause the tree; only the pause
menu and in-game settings call `_pause_for_menu()` (`:1884`).

So opening *Rules & scoring*, *Captured piles*, the *Raid* picker, or the *Diplomacy* picker mid-turn
lets the 26-second clock run down behind the panel, and the game auto-plays a move the player may not
have wanted. On a phone, reading the rules is a normal thing to do.

**Fix:** set `_busy = true` on open and restore on close for the informational/interactive sheets, or
gate the timer on `_overlay == null`:

```gdscript
if duel.is_my_turn(0) and not duel.hand_over and not _busy and _overlay == null:
```

Then assert it: open `_show_rules()`, wait 2 s of wall clock, confirm `_turn_time` is unchanged.

### 4. A suspended app can burn the turn timer in one frame

`scripts/screens/duel.gd:2272` integrates raw `_process` delta into `_turn_time`. Android/iOS
suspension, or a long GC/compile hitch, can hand `_process` an unusually large delta; `_turn_time`
then jumps past zero and `_auto_play()` fires on the first frame back. There is no
`NOTIFICATION_APPLICATION_PAUSED` handler anywhere (`grep` for `NOTIFICATION_*` returns nothing in
`scripts/`).

**Fix:** clamp — `_turn_time -= minf(delta, 0.25)` — and pause the tree on
`NOTIFICATION_APPLICATION_PAUSED`.

---

## P2 — robustness, platform and release

### 5. No hardware back button on Android

`grep -rn "GO_BACK\|ui_cancel\|NOTIFICATION_WM"` over `scripts/` returns nothing. Pressing back
mid-duel terminates the activity with no pause, no confirmation and no visible resume affordance
(the save *is* written per move, so "Continue" recovers it, but the player is dropped out of the app
without being told). Expected behaviour is back → pause sheet, back again → menu.

**Fix:** in `scripts/screens/duel.gd`, override `_notification(what)` for
`NOTIFICATION_WM_GO_BACK_REQUEST`, closing the top sheet if one is open and otherwise calling
`_open_menu()`. On the title screen, back should open the About/Quit confirm.

### 6. Starting a new duel leaves the previous save in place

`scripts/screens/title.gd:728-736` (`_launch`) never calls `Profile.clear_duel()`. The save is only
cleared on match end (`scripts/screens/duel.gd:2145`) or on *Concede* (`:2188`). Because
`_save_state()` runs only when a card is played (`:1133`, `:1450`, `:2070`), this sequence leaks:

1. Duel A is in progress (save on disk).
2. Return to the menu without conceding via any path that is not the Concede button.
3. Start Duel B and quit before making a move — nothing has overwritten the file.
4. *Continue* now resumes the abandoned Duel A.

**Fix:** `Profile.clear_duel()` at the top of `_launch()` (it is not used by the resume path —
`_resume_duel()` at `:745` emits `start_duel` directly).

### 7. Nothing verifies the game except a human

`.github/workflows/` contains exactly one file, `testflight.yml` — a manually dispatched iOS build.
No workflow runs `gdparse`, `gdlint`, or `godot --headless -- --audit`, on push or on PR. The
README's strongest claim ("300 AI games … failures=0", `:365`) is therefore a statement about
somebody's laptop, and every future change is unprotected.

This is the single highest-leverage improvement in this document: the expensive part (the audit)
already exists.

**Add** `.github/workflows/verify.yml`:

```yaml
name: verify
on:
  push:
  pull_request:
jobs:
  lint:
    runs-on: ubuntu-latest
    steps:
      - uses: actions/checkout@v4
      - uses: actions/setup-python@v5
        with: { python-version: '3.11' }
      - run: pip install gdtoolkit==4.*
      - run: gdparse $(find scripts tools -name '*.gd')
      - run: gdlint scripts tools/*.gd   # after the .gdlintrc in finding 12
  audit:
    runs-on: ubuntu-latest
    steps:
      - uses: actions/checkout@v4
      - name: Godot
        run: |
          curl -fsSL -o g.zip "https://github.com/godotengine/godot-builds/releases/download/4.4.1-stable/Godot_v4.4.1-stable_linux.x86_64.zip"
          unzip -q g.zip && chmod +x Godot_v4.4.1-stable_linux.x86_64
      - run: ./Godot_v4.4.1-stable_linux.x86_64 --headless --path . --import
      - run: ./Godot_v4.4.1-stable_linux.x86_64 --headless --path . -- --audit
```

Pin the Godot download by SHA-256 (the iOS workflow already does this properly — reuse that
pattern).

**What actually landed** (`.github/workflows/verify.yml`) differs from the sketch above: it pins
4.7.2 with a verified SHA-256 rather than 4.4.1, runs `gdlint` over every script (not a glob that
misses subdirectories), and **does not upload any artifact**. The audit log stays in the step output,
which is enough to read a failure without keeping a stored copy to expire.

One assertion in it exists because the rest are not enough on their own: it requires **at least 150
checks**. `failures=0` is equally true of a suite that ran a third of its tests, and a parse error in
`audit.gd` is the concrete way that happened here. If a test is ever removed deliberately, the floor
comes down in the same commit.

### 8. No LICENSE, and no OFL text for the bundled fonts

There is no `LICENSE` file at the repository root, and `fonts/` contains three `.ttf` files with no
accompanying license text. Cinzel and Alegreya Sans are SIL Open Font License 1.1; the OFL requires
the license to travel with the font, and the README itself notes this ("both OFL") without shipping
the text. The repo is public and builds are distributed via TestFlight.

**Fix:** add `LICENSE` (project) and `fonts/OFL.txt` covering both families, and reference them from
the README's Credits section.

### 9. The Android launcher icon is unset

`export_presets.cfg:51-53`:

```ini
launcher_icons/main_192x192=""
launcher_icons/adaptive_foreground_432x432=""
launcher_icons/adaptive_background_432x432=""
```

iOS is configured (`:147`, `icons/icon_1024x1024`), Android is not, so the APK ships Godot's default
icon — which is the first thing a store reviewer and every user sees. `assets/icon/four-realms-iphone-icon.png`
is 1254×1254 and can be resampled for the three Android slots.

### 10. Dev files and a dead 3.8 MB asset ship inside the PCK

`exclude_filter` is `"scripts/audit.gd"` in all four presets (`:15`, `:78`, `:122`, `:173`). Godot
exports everything else in the project tree, so the binaries include `tools/*.py`, `tools/*.gd`,
`docs/`, `screenshots/*.html`, `README.md`, `CRASH_REPORT.md`, `*.sh` — and
`assets/branding/four_realms_scenic.png` (3.8 MB), which no script or scene references (`grep`
across `.gd`, `.tscn`, `.cfg` returns nothing).

**Fix:** extend the filter in all four presets, e.g.
`exclude_filter="scripts/audit.gd,tools/*,docs/*,screenshots/*,*.md,*.sh,assets/branding/four_realms_scenic.png"`
and delete the unused scenic image. That is ~4 MB off every download for no visual change.

### 11. There is no way to mute the game

`Sfx.enabled` exists (`scripts/sfx.gd:21`) and is never assigned anywhere. `settings_panel.gd` offers
Classic, Two-tap, Orientation, Card backs, Table felt and four animation toggles — no audio control,
no volume slider. A mobile card game that clicks and chimes with no mute is a routine review
complaint and a courtesy issue (trains, offices).

**Fix:** one toggle row in `_classic_panel`-style plus a master `-inf` on the `Master` bus; persist as
`Profile.sound_on`. The pooled-player design already supports it — set `_players[i].stream_paused`.

### 12. The lint baseline is 307 findings, so nobody can run the linter

With the default 100-character limit, `gdlint` reports 224 line-length violations, all on *code*
lines. Add `.gdlintrc` reflecting the project's actual conventions rather than reformatting ~224
lines for no behavioural gain:

```ini
[MAIN]
max-line-length = 140
max-file-lines = 1000
max-public-methods = 24
```

Then either exempt `scripts/audit.gd` (`max-file-lines`) or split it (see finding 13), so the gate in
finding 7 starts green and stays meaningful.

---

## P3 — maintainability

### 13. Three files carry 65% of the project

`audit.gd` 2,878 · `screens/duel.gd` 2,296 · `title.gd` 1,029 — against 9,517 total.

`screens/duel.gd` mixes five concerns: layout surgery, card animation, modal sheets, oath pickers and
score presentation. The cleanest seams, in order of payoff (all four are now extracted — see the
status note below):

| Extract | Lines (approx.) | Target |
|---|---|---|
| Oath pickers (Deep Delve, Foresight, Raid, Diplomacy) | 1258–1440 | `scripts/ui/oath_pickers.gd` |
| Score sheet + puzzle verdict | 1926–2133 | `scripts/ui/score_sheet.gd` |
| Card flight / match rings / pile flight | 1520–1655 | `scripts/ui/card_anim.gd` |

`scripts/game/duel.gd` also trips `max-public-methods` at gdtoolkit's default of 20. It has 24, and
`.gdlintrc` sets the project's limit to 40, so `gdlint` passes — but the point stands that the state
getters used only by the screen (`groups_for`, `deck_low`, `blocked_by_quindici`, `oath_title`,
`primiera_total`) could collapse behind two or three query objects. Not done: it is an API
redesign across the engine and the screen, and the limit that flagged it has been raised.

**Status: score sheet and oath pickers extracted.** The score sheet moved to
`scripts/ui/score_sheet.gd`, and the four Oath bottom sheets to
`scripts/ui/oath_pickers.gd`; `screens/duel.gd` is 2,332 → 2,135 lines. The oath
pickers did need the interface work predicted above: they take the screen as one
object and call a five-method contract (`duel`, `open_sheet`, `toast`, `finish`,
`close`, `refresh`) rather than six callbacks, and the contract is documented at
the top of the module so it cannot drift into layout internals.

Also out: card flight and match rings (`scripts/ui/card_anim.gd`) and the puzzle
verdict (`scripts/ui/puzzle_verdict.gd`). `screens/duel.gd` is now 2,063 lines,
down from 2,332.

Still in the screen, deliberately: the hand-summary sheet itself. It owns the
async timer, the `play_again` signal and the scene transitions, so it is
orchestration — moving it would mean moving the screen's control flow, not its
presentation. That is the honest end of this item.

### 14. Duplicated logic between engine and screen

- `screens/duel.gd:1782 _CountFaction()` reimplements `game/duel.gd:516 _count_faction()`.
- `screens/duel.gd:1480 _quest_by_key()` reimplements a lookup over `T.QUESTS` that the engine
  already performs in `_eval_quests`; the fallback `{"name": k, "reward": 1}` silently invents data
  if a key ever drifts.

Move both into `Cards`/`Tables` as statics and call them from both sides.

**Status: fixed.** Both now live in `scripts/tables.gd` (`count_faction`,
`quest_by_key`); the engine's `_count_faction` is a one-line delegation and the
screen's copy is deleted. `quest_by_key` returns `{}` rather than inventing a
quest, so a drifted key shows up as a missing name instead of a free point.

### 15. Positional child access will break silently

`screens/duel.gd:424`:

```gdscript
_layout_parts.Actions.get_child(3).text = "Menu" if wide else "☰"
```

The menu button is the fourth child built in `_build_actions()` (`:584-610`). Insert a button above it
— a very plausible future change — and this line relabels the wrong control with no error. The other
three action buttons already have member fields; give this one the same treatment (`_btn_menu`,
`:606`).

**Status: fixed.** `_btn_menu` exists and `_relayout` uses it.

### 16. Dead code and no-op hooks

| Location | Issue |
|---|---|
| `screens/duel.gd:34` `_top_pile` | declared, never read or written |
| `screens/duel.gd:60` `_pile_chip` | declared, never used |
| `screens/duel.gd:81/2290` `_timeouts` | incremented, never read |
| `screens/duel.gd:51/578` `_favor_label` | created and positioned, never given text |
| `screens/duel.gd:2285-2286` | `if _bg != null: pass` |
| `screens/duel.gd:2022` | `quests_title.free()` on a node never parented — works, reads as a bug; build it inside the branch |
| `screens/duel.gd:1584` | `_mark_match(..., from_hand)` — argument unused |
| `title.gd:776` | `_campaign_row(c, idx)` — `idx` unused |
| `ui.gd:138-175` `freeze()` | 38-line SubViewport + **GPU readback** helper, zero callers, carries a large warning comment |
| `background.gd:16/20` | `set_accents()` and `set_quiet()` are empty; two call sites believe they do something (`screens/duel.gd:120`, `:2269`; `title.gd:59`) |
| `profile.gd:263` `mark_puzzle_solved()` | unused; `record_match()` writes the same fields |

The `set_quiet()` case is the interesting one: `_process` (`screens/duel.gd:2265-2270`) measures FPS
and reports "background animations paused", but the background has no animations and the method is
empty — the log line asserts something that did not happen.

**Status: all of the above is fixed.** The dead fields, `_timeouts`, `_favor_label`,
`freeze()`, its `_BoxPainter`, `set_quiet()` and `mark_puzzle_solved()` are gone;
`set_accents()` keeps its signature because two screens call it, but no longer
pretends to redraw; the FPS log now reports the frame rate without claiming work
it did not do; the quests title is built inside its branch; and the menu button
has a member field, so `_relayout` no longer reaches for `get_child(3)`.

### 17. Style findings worth fixing cheaply

- `class-definitions-order` (45) — constants/vars/signals before functions would clear most of it.
- `duplicated-load` (22, all in `audit.gd`) — hoist to one `const DuelScreen := preload(...)`.
- `class-variable-name` (4) — `_CountFaction`-style casing: functions are `_snake_case`.
- `function-variable-name` (2) — `screens/duel.gd:845` `MAX_CH` is a local, not a constant.

**Status: all four are gone.** `.gdlintrc` was written with the project's own
limits (200-char lines, 3,500-line files, 40 public methods) and the 307 findings
cleared to zero in the P2 lint pass; `gdlint` is clean across the tree, and CI
runs it.

### 18. Documentation drift

`safe-check.sh` and `README.md:24` say "**57 self-tests**". `scripts/audit.gd` now contains 125
`ok()` assertions plus 192 failure branches across 60+ test functions. The number is stale in two
places, which makes the suite look smaller than it is — worth correcting, and worth printing the real
count from `run()`.

---

## What is genuinely good (and worth protecting)

1. **The engine is UI-free and honestly pure.** `game/duel.gd` has no `Node`, no `Control`, no
   timers — it can be driven headlessly, which is why the audit can play 300 games in seconds.
2. **Persistence is defensive in the right places.** `to_dict()`/`from_dict()` round-trip the RNG
   state (`:749-751`); `valid_save()` (`:622`) checks 25+ fields including *card uniqueness across
   deck, table, hands and piles* (`:664-672`) — that is a real anti-corruption boundary, not a
   `typeof() == DICTIONARY` gesture. The JSON int/float coercion is handled and asserted
   (`audit.gd:2333-2371`), including a legacy unversioned save (`:2097-2112`).
3. **Atomic writes.** `_write_json()` (`profile.gd:111-120`) writes `.tmp` then renames.
4. **The audit measures the game, not just the code.** Layout overflow at 720×1280 and across
   rotations, touch/mouse/swipe disambiguation, puzzle solvability by brute force, AI latency
   (<8 ms budget), atlas rect arithmetic, and the card-spin geometry as a *rigid* transform.
5. **The renderer decision is documented with its failure mode.** `gl_compatibility`, Vulkan
   fallback disabled, and `CRASH_REPORT.md` explains why — this pattern (choose the boring path and
   write down what it prevents) is what keeps a hobby project shippable.
6. **Every animation is genuinely optional** and the settings plumbing proves it
   (`anim_on()`/`_beat()` collapse waits rather than skipping logic).

---

## Suggested sequence

**Now (half a day):** 1 (veil), 2 (toast), 3 (timer behind sheets), 5 (back button), 6 (stale save),
9 (Android icon), 8 (LICENSE + OFL), 10 (export filter + dead asset).

**Next (one day):** 7 (CI: parse + lint + audit), 12 (`.gdlintrc`), live smoke-test the audit on
Linux in CI so finding 1's regression is caught automatically, 11 (mute).

**Then (ongoing):** 13 (extract oath pickers and score sheet out of `screens/duel.gd`), 14, 15, 16,
17, 18.

Everything above is reversible and independently testable; none of it touches the 40-card deck, the
capture rules or the scoring maths.
