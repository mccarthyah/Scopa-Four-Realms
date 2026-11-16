# Scopa: Four Realms

A mobile-first fantasy reimagining of **Scopa**, built for **Godot 4.7.2** (GDScript).
Verified green on **4.7.2 and 4.4.1** — requires 4.4 or newer.
Your turn is three taps; a duel is four minutes; the depth is still Scopa's — matching ranks, setting up
sums, denying captures, and sweeping the table for a scopa.

```
40-card deck      ranks 1–10 × four factions
                 Forge (Coins) · Grove (Cups) · Horde (Swords) · Crown (Batons)
the Runestone    the 7 of Forge — the settebello
```

---

## Run it

1. Install **Godot 4.7.2** (or any 4.4+; standard build, no C# needed).
2. Open `project.godot` → press **F5**.
3. The viewport is a 720×1280 portrait phone canvas that stretches to any window; the window opens at
   540×960 for desktop testing.

The project ships on the **GL Compatibility** renderer deliberately: the Vulkan
paths can hard-lock a virtualised or GPU-poor machine instead of failing, and a
2D card game gains nothing from them.

**Safe health check — no window, no GPU context, so it cannot freeze a VM:**

```bash
GODOT=/path/to/godot ./safe-check.sh          # import + boot + 57 self-tests
GODOT=/path/to/godot ./safe-check.sh log      # the log from a frozen run
```

Every run prints an environment block (Godot version, renderer, GPU adapter,
display server, viewport) at the top of `user://logs/godot.log`. See
`CRASH_REPORT.md` for where that log lives on each platform.

Export presets for **Android / iOS / Web / Linux** are in `export_presets.cfg` — Godot recognises all
four presets; you supply the export templates and SDK paths in *Project → Export*.

### Controls

| Action | Touch / Mouse |
|---|---|
| Select a card | tap it (cards you can capture with glow gold) |
| Confirm / capture | tap the same card again, or tap a glowing table card |
| Choose among several capture sets | tap the table card that belongs to the set you want |
| Spend Favor on your Oath | tap the Oath button above your hand |
| Hint · Pile · Menu | the buttons beside your hand |

Turn timer: **26 s**, with a 5-second audible countdown; if it expires the game auto-plays a good move
for you (it says so, and never shames you).

---

## What's implemented

Everything in the brief, playable end to end:

| Spec | In the build |
|---|---|
| 40-card Scopa deck, four factions, Rank-large faces, Runestone | ✅ fully procedural card art (no image assets) |
| Standard capture rules: rank match **or** a sum to your rank, 10s only match 10s | ✅ with all legal sets enumerated and choosable |
| Deal 3 + 3, 4 on the table, redeal in rounds, last capturer sweeps the rest | ✅ |
| Scopa scores 1 (not on the final play of a deal, per Scopa rules) | ✅ plus a full-screen celebration |
| 20–30 s turn timer, legal captures highlighted, dramatic scopa clear | ✅ 26 s timer, pulsing gold rings, particle burst, screen shake, held beat |
| **Quick Duel** — one hand, ~4 min | ✅ |
| **Ranked Duel** — best of three, first to 11 Renown | ✅ with a per-hand score sheet |
| Traditional scoring renamed: Loot · Treasury · Runestone · Banner · Glory | ✅ auto-scored live, with a live Primiera/Banner meter |
| Running **Renown** total | ✅ split bar in the HUD |
| **Faction Oaths**, 1 Favor for a scopa or any 7, once per hand | ✅ all four, with dedicated picker UI |
| **Classic Mode** (Oaths off) | ✅ toggle on the title screen |
| Two **public quests** per duel, bonus Renown | ✅ 8 quests, rolled per match, evaluated at hand end |
| **Campaign** with boss twists | ✅ 4 bosses: veiled table card, late-game fury, double treasure, Banner ties |
| **Daily Puzzle** — fixed deal, goal in N moves | ✅ 3 deals, rotates by date, each solver-verified |
| **Async duels** | ✅ foundation: the duel serialises exactly (verified) and a mid-hand duel resumes from the title screen. Needs a transport (see *Next*) |
| Cosmetics only | ✅ card backs, board themes, saved in the profile; no card power anywhere |

### Oaths (implemented exactly as specified)

| Faction | Oath | Effect |
|---|---|---|
| Dwarves · Forge | **Deep Delve** | Draw 1 card, then bury 1 card from your hand on the bottom of the deck |
| Elves · Grove | **Foresight** | Look at the top 3 cards and reorder them |
| Orcs · Horde | **Raid** | Discard a table card to the bottom of the deck — not captured, no scopa |
| Humans · Crown | **Diplomacy** | Swap 1 hand card with 1 table card; no capture triggered |

Faction identity beyond the Oath is deliberately light: **Forge** counts double against the Forge boss's
vault, **Grove** peers at the deck, **Horde** never loses a tie on Loot/Treasury, **Crown** takes Banner
ties. Those are tie-breakers and flavour, never card power.

### Scoring

| Renown point | Awarded for |
|---|---|
| **Loot** | most captured cards |
| **Treasury** | most Forge cards |
| **Runestone** | whoever holds the 7 of Forge |
| **Banner** | best Primiera (7 = 21, 6 = 18, Ace = 16, faces = 10, best card per faction) |
| **Glory** | 1 per scopa |

Every hand ends with a score sheet that shows the piles, the faction tallies, the Primiera totals, which
player took each point, plus the two quests. Ranked tracks the running Renown toward 11.

### Quests

Claim the Runestone · Two Sweeps · Grove Tribute · Raise the Banner · Horde Raid · Fool's Errand ·
Lucky Sevens · Empty Halls — two are drawn per duel, both players can chase them, completing one pays
bonus Renown.

### Campaign

| Boss | Twist |
|---|---|
| **The Veiled Warden** (Grove) | one table card is veiled — you can't see or take it until the table thins |
| **Grasha Ironjaw** (Horde) | from the sixth play of a hand, her scopas score 2 Glory |
| **Thane Brund** (Forge) | his Forge cards count double toward the Treasury |
| **Regent Aurelia** (Crown) | she wins the Banner on a Primiera tie |

Beating a boss marks it cleared on the campaign sheet (saved in your profile).

### Daily Puzzle

Three fixed deals rotate daily (stable per date):

1. **Sweep the Hall** — empty the table for a scopa in 3 moves.
2. **Gather the Runestone** — capture the 7 of Forge in 2 moves (the Runestone can never fall to a sum).
3. **Golden Banner** — finish with Primiera over 40.

Every puzzle is **solver-verified** by the automated audit, so no daily deal can be impossible. Beating
one marks it solved for the day on the title screen.

---

## Design notes

* **The rule that keeps it Scopa.** No cards, effects, or purchases touch the 40-card deck — both players
  always draw from the same probabilities. Oaths spend a resource you earn by playing well, and they are
  utility: a card swap, a peek, a banish. None of them add a point directly.
* **Favor is the incentive to play real Scopa.** You earn it for scopas and for capturing 7s, which are
  exactly the two things good Scopa players already chase — the ability layer teaches the base game.
* **Sum captures are the skill ceiling,** so they are surfaced, never hidden: a selected card shows
  *every* legal set, and choosing among them (which cards you deny the opponent) is the decision.
* **One-thumb portrait layout:** opponent and Renown at the top, table in the middle, your hand at the
  bottom under the Oath button. Nothing important sits under a thumb.
* **Readable cards at arm's length:** the rank number is the largest element on the card, faction art is
  texture behind it, and the faction name is a strip along the bottom.
* **Cosmetics, never power:** card backs and board themes are profile flags; the deck is untouched.

---

## Project layout

```
project.godot            portrait 720×1280 canvas, GL Compatibility, autoloads
scenes/main.tscn         single root node; every screen is built in code
scripts/
  tables.gd              factions, ranks, Primiera values, Oaths, quests, bosses, puzzles
  profile.gd             (autoload) save/load stats, cosmetics, puzzle day, mid-hand duel
  sfx.gd                 (autoload) pooled AudioStreamPlayers
  main.gd                router: title ⇄ duel
  game/
    cards.gd             card ids, capture-group enumeration, Primiera
    duel.gd              the full rules engine — pure logic, no UI, serialisable
    ai.gd                heuristic opponent + hint engine (4 play styles)
  ui/
    ui.gd                palette, fonts, widget factories
    card_view.gd         procedurally drawn cards (rank-first layout, four faction emblems)
    background.gd        painted sky, motes, vignette
    fx.gd                bursts, floating text, shake, flashes
  screens/
    title.gd             masthead, faction picker, modes, cosmetics, codex, resume
    duel.gd              HUD, table, hand, Oath sheets, score sheet, celebrations
  audit.gd               headless self-test + layout audit (dev only)
audio/                   generated WAVs: deal, capture, scopa, favor, oath, win, lose, tick…
fonts/                   Cinzel (display) and Alegreya Sans (text), both OFL
```

Open `screenshots/card_sheet.html` in a browser (or the workspace previewer) for a static sheet of the
card design — it mirrors the geometry and palette that `card_view.gd` draws.

**No art or audio assets were downloaded into the game** — cards, emblems, felt, background and the
sound effects are all generated (vector draw calls / synthesised WAVs), so the repository is 2 MB and
everything is tweakable in one place.

Everything a script needs is resolved with an explicit `const X := preload(...)` and a matching
`class_name`, and the UI fonts are loaded lazily with a fallback — so a bare checkout parses and boots
correctly on its *first* run, before Godot has built any import or global-class cache.

The engine in `duel.gd` is UI-free and JSON-serialisable: `to_dict()` / `from_dict()` round-trip a hand
exactly (asserted in the audit), which is what the resume feature and async duels are built on.

---

## Automated verification

The project ships with a headless audit that plays the game thousands of times and measures the layout:

```bash
godot --headless --path . -- --audit
```

It asserts (39 checks, all passing — verified across five consecutive runs):

* card conservation (40 unique cards across deck, table, hands and piles) at deal **and** after 300
  complete AI-vs-AI games in Quick and Ranked modes,
* capture maths: rank matches, sum sets (3+2+2 = 7), tens only matching tens, no duplicate sets,
* turns alternate and every game reaches a terminal state,
* all three daily puzzles are solvable within their move limits (brute-force solver),
* a duel serialises and restores exactly, the restored duel keeps playing, and a mid-hand snapshot
  survives a real disk round-trip through the profile (JSON hands numbers back as floats, so
  `from_dict()` coerces every card id back to an int),
* resume works through the actual title screen: save, return to menu, press *Resume*, table matches,
* every screen builds headless at 720×1280 with no control overflowing its parent or the viewport —
  checked before and during play, and across eight extra deals covering all four factions,
* all four Oath sheets, the pile view, the pause menu, the score sheet and the Classic toggle,
* AI move choice stays under 8 ms (it measures ~30 µs).

Latest run: 300 AI games (318 scopas), layout clean, **failures=0** — including a real save/resume round-trip through the profile files
(including the JSON int/float coercion that a naive snapshot loses) and all four Oath sheets.

The audit is excluded from exported builds (`exclude_filter` in `export_presets.cfg`).

---

## Next steps

* **Async duels / real PvP:** the state dict is already a complete duel snapshot — wrap it in a small
  turn-based service (or a GodotSteam / WebRTC backend) and swap the local AI call in `duel.gd`'s
  `_run_bot` for a submitted move.
* **Cosmetics store:** card backs and board themes are already data-driven (`Profile.card_back`,
  `BOARD_THEMES`); add a shop screen and more variants, plus scopa animation and emote sets.
* **Ranked ladder, daily quest rotation, battle-pass cosmetics:** all profile-level data, no rule changes.
* **Localisation:** every string is inline English; extract to a `tr()` CSV when the rules are frozen.

---

## Credits

Cinzel and Alegreya Sans are licensed under the SIL Open Font License (Google Fonts).
Scopa is a traditional Italian game; this is an unaffiliated fan reimagining.
