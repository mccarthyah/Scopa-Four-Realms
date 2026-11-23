# Four Realms

A mobile-first fantasy card game, inspired by the traditional Italian game **Scopa**, built for **Godot 4.7.2** (GDScript).
Verified green on **4.7.2 and 4.4.1** — requires 4.4 or newer.
Your turn is three taps; a duel is four minutes; the depth comes from matching ranks, setting up
sums, denying captures, and clearing the table for a sweep.

```
40-card deck      ranks 1–10 × four factions
                 Forge (Coins) · Grove (Cups) · Horde (Swords) · Crown (Batons)
the Runestone    the 7 of Forge
```

---

## Run it

1. Install **Godot 4.7.2** (or any 4.4+; standard build, no C# needed).
2. Open `project.godot` → press **F5**.
3. The 540×960 base canvas adapts to portrait and landscape; the desktop window opens at
   540×960 unless a saved orientation preference requests a different shape.

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
| Play a card | tap it once by default |
| Optional confirmation | enable Settings → Two-tap play, then tap a card to select it and tap it again or tap a highlighted capture |
| Choose among several capture sets | choose the complete group in the capture picker |
| Spend Favor on your Oath | tap the Oath button above your hand |
| Hint · Pile · Menu | the buttons beside your hand |

Turn timer: **26 s**, with a 5-second audible countdown; if it expires the game auto-plays a good move
for you (it says so, and never shames you).

---

## What's implemented

Everything in the brief, playable end to end:

| Spec | In the build |
|---|---|
| 40-card deck, four factions, Rank-large faces, Runestone | ✅ supplied faction artwork for all 40 faces, with a shared pre-rendered atlas |
| Standard capture rules: rank match **or** a sum to your rank, 10s only match 10s | ✅ with all legal sets enumerated and choosable |
| **Fifteen Duel** variant (first version) | ✅ separate game type: only totals of 15 capture, a card never takes its own value. Chosen per match, never mixed inside one |
| Deal 3 + 3, 4 on the table, redeal in rounds, last capturer collects the rest | ✅ |
| A sweep scores 1 (not on the final play of a hand) | ✅ plus a full-screen celebration |
| 20–30 s turn timer, legal captures highlighted, dramatic sweep clear | ✅ 26 s timer, pulsing gold rings, particle burst, screen shake, held beat |
| **Quick Duel** — one hand, ~4 min | ✅ |
| **Ranked Duel** — best of three, first to 11 Renown | ✅ with a per-hand score sheet |
| Traditional scoring renamed: Loot · Treasury · Runestone · Banner · Glory | ✅ auto-scored live, with a live Banner meter |
| Running **Renown** total | ✅ split bar in the HUD |
| **Faction Oaths**, 1 Favor for a sweep or any 7, once per hand | ✅ all four, with dedicated picker UI |
| **Classic Mode** (Oaths off) | ✅ toggle in the title-screen Settings dialog |
| Two **public quests** per duel, bonus Renown | ✅ 8 quests, rolled per match, evaluated at hand end |
| **Campaign** with boss twists | ✅ 4 bosses: veiled table card, late-game fury, double treasure, Banner ties |
| **Daily Puzzle** — fixed deal, goal in N moves | ✅ 3 hand-authored deals, rotates by date; audit checks solvability |
| **Async duels** | ✅ foundation: the duel serialises exactly (verified) and a mid-hand duel resumes from the title screen. Needs a transport (see *Next*) |
| Cosmetics only | ✅ card backs, board themes, saved in the profile; no card power anywhere |
| **Card animation**, all optional | ✅ played cards spin 360° onto the field, captures flash a ring on every matched card, the opponent's hand sits face down above the playfield and thins as it plays. Slower play is a switch; **every** animation can be turned off in settings |

### Window sizes and orientation

The home screen offers Continue, New Game, Puzzle, Codex, Settings and About.
Its six actions and complete record panel fit in portrait and landscape.
Continue is available when a saved duel exists. New Game contains the faction
picker and Duel, Fifteen, Ranked and Campaign. Both touch and mouse activate
menu entries; swiping across an entry cancels its tap. Handheld layouts account
for display safe areas.

The portrait duel uses a compact logo above the status and playfield on taller
screens. The landscape duel puts status, quests and the opponent hand on the
left. The wider playfield sits above a bottom row containing the player hand
and action buttons. Landscape text uses larger, readable sizes. New Game shows
a short faction-power summary in a fixed-size panel. The same match, faction
selection and open sheet
survive a window resize or device rotation.

In **Settings → Orientation**, choose **Auto**, **Landscape Left**, **Landscape
Right** or **Portrait**. The preference is saved. On supported Android and iOS
devices, Auto requests the orientation sensor and the other choices request that
device orientation. Device and OS rotation restrictions may still apply. On
Windows, Linux and macOS, Auto follows the window shape; forced choices make and
maintain a landscape- or portrait-shaped window while it is windowed. Left and
Right have the same landscape shape on desktop; they do not rotate the operating system's display.
Forcing a desktop orientation returns a maximized/full-screen window to windowed
mode so it can be resized. Choosing Auto leaves the current window size alone.
Godot's embedded Game panel is controlled by the editor and cannot be resized
by the game. The orientation picker is disabled with a note in embedded mode;
stop the game, open the Game tab's embedding options, turn off **Embed Game on
Next Play**, and run again in a separate window to test forced desktop sizes.
In the Web build, orientation is controlled by the browser, so the choice is
disabled and the layout follows the browser window instead.

Stretch must be configured under the keys Godot reads:

    window/stretch/mode="canvas_items"
    window/stretch/aspect="expand"

Putting these under `display/window/size/stretch/*` silently disables stretch.
The layout, orientation preference and resize paths are covered by the audit.

### Table layout

However many cards are on the felt, they all fit on it. The layout is solved
rather than delegated to a container: for each possible column count it computes
the largest card that fits both the width and the height, keeps the best, then
wraps the cards into rows and centres the block (with a short final row centred
too). Cards shrink as the table crowds and grow back as it empties.

At 540 wide the felt is 516 x 293, giving:

| Cards | Grid | Card size |
|---|---|---|
| 1-3 | 1 row | 148 x 208 |
| 4 | 1 row | 124 x 175 |
| 5-8 | 2 rows | 102 x 143 |
| 9-10 | 2 rows | 98 x 138 |
| 11-14 | 2 rows | 81 x 113 down to 69 x 96 |
| 15-16 | 3 rows | 67 x 94 |

This used to be a single-row `HBoxContainer` with a 112 px minimum card width, so
a fifth card hung off both sides of the screen. A resize re-solves the layout, so
maximising the window grows the cards instead of leaving them at the old size.

### Card corners

Cards have the curved corners of a real playing card — about 5% of the short side,
which matches a real card's 5.5%, and it scales with the card so a small card in
the opponent's hand has the same proportions as a playfield card. The corners are
anti-aliased, since a curve drawn without AA is visibly jagged, and the selection
rings and shadow follow the card's own curve rather than a fixed one.

The menu, HUD, buttons, faction tiles, and the felt now use pre-rendered,
stretchable nine-slice frames. Their rounded, gilded corners also appear in
low-spec mode without runtime texture baking, GPU readback, or tessellating every
panel each frame. Special-purpose fallback primitives still use cheap square
corners in low-spec mode; the card shapes and rings remain independently rounded.
`python3 tools/build_ui_frames.py` rebuilds the small static frame textures.

### Animation settings

Title screen → *Settings* → *Animation*. Nothing here changes the rules, and the game is fully
playable with it all switched off — the same moves resolve on the same frames,
just instantly (a measured play: ~1.7 s animated, 66 ms off).

| Setting | Effect |
|---|---|
| All animation | Master switch |
| Card spin | A played card turns a full 360° **about its own centre**, face up the whole way, as it travels to the playfield. An opponent's card is drawn small in their hand (half a playfield card) and **scales up to full playfield size** during the spin |
| Slower play | Holds the beat before and after a play so captures stay readable |
| Match cue | A gold ring flashes on every card involved in a capture before they leave the table |

The spin is a real rotation of the card's drawing context about its centre — the
art stays face up throughout, so it reads as a spin and not a flip. It rotates in
place via `draw_set_transform`, so it costs one angle tween on a software
rasteriser rather than a render-to-texture pass. An audit check asserts
geometrically that the card's centre is a fixed point at every angle and that the
corners stay equidistant (a rigid rotation, no squash).

### Fifteen Duel

A ruleset variant, selected as its **own game type** on the title screen — it is
never mixed into a Classic or Ranked match. The deck, deal, Oaths, quests and
scoring are identical; only the capture rule changes.

* Your card plus the cards you take must total **exactly 15**.
* A card may **never** capture a card of its own value — the rank match that
  Classic allows does not exist here.
* With **A, 3, 4, 7** on the table, playing a **4** takes `4+7` *or* `A+3+7`,
  your choice. The 4 on the table is untouchable.
* A single card can complete a 15: a **5 takes a lone 10**, a 6 takes a 9, a 7
  takes an 8. Two 10s can never be taken by a 10.
* Three fives (`5+5+5`) are a legal 15.

**Scoring is identical to Classic** — Loot, Treasury, Runestone, Banner, Glory,
Renown, Favor and the Oaths all work exactly as they do in the standard game.
Only the capture rule changes. This is enforced by an audit check that scores the
same captured piles under both rulesets and requires byte-identical results.

When a card you have selected could not capture, the status line says so
explicitly ("matching a value never captures — only cards totalling 15") so the
variant's rule never reads as a broken tap.

### Oaths (implemented exactly as specified)

| Faction | Oath | Effect |
|---|---|---|
| Dwarves · Forge | **Deep Delve** | Draw 1 card, then bury 1 card from your hand on the bottom of the deck |
| Elves · Grove | **Foresight** | Look at the top 3 cards and reorder them |
| Orcs · Horde | **Raid** | Put a table card on the deck bottom and replace it with the top card; no capture or sweep. Unavailable if the deck is empty |
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
| **Banner** | best Banner total (7 = 21, 6 = 18, Ace = 16, faces = 10, best card per faction) |
| **Glory** | 1 per sweep |

Every hand ends with a score sheet that shows the piles, the faction tallies, the Banner totals, which
player took each point, plus the two quests. Ranked tracks the running Renown toward 11.

### Quests

Claim the Runestone · Two Sweeps · Grove Tribute · Raise the Banner · Horde Raid · Fool's Errand ·
Lucky Sevens · Empty Halls — two are drawn per duel. Completing one earns the player bonus Renown. The AI scores from the hand rules.

### Campaign

| Boss | Twist |
|---|---|
| **The Veiled Warden** (Grove) | one table card per hand is veiled — you can't see or take it until the table thins to two cards; once the veil lifts it stays lifted |
| **Grasha Ironjaw** (Horde) | from the sixth play of a hand, her sweeps score 2 Glory |
| **Thane Brund** (Forge) | his Forge cards count double toward the Treasury |
| **Regent Aurelia** (Crown) | she wins the Banner on a Banner tie |

Beating a boss marks it cleared on the campaign sheet (saved in your profile).

### Daily Puzzle

Three fixed deals rotate daily (stable per date):

1. **Sweep the Hall** — empty the table for a sweep in 3 moves.
2. **Gather the Runestone** — capture the 7 of Forge in 2 moves (the Runestone can never fall to a sum).
3. **Golden Banner** — finish with a Banner total over 40.

The automated audit searches each hand-authored puzzle for a solution within its move limit. Beating
one marks it solved for the day on the title screen.

---

## Design notes

* **A shared deck.** No cards, effects, or purchases touch the 40-card deck — both players
  always draw from the same probabilities. Oaths spend a resource you earn by playing well, and they are
  utility: a card swap, a peek, a banish. None of them add a point directly.
* **Favor rewards smart play.** You earn it for sweeps and for capturing 7s; the ability layer teaches the base game.
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
project.godot            portrait 540×960 canvas, GL Compatibility, autoloads
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
    card_view.gd         card interactions; shared image atlas, vector fallback
    card_art.gd          card atlas mapping and vector fallback
    background.gd        single-quad fantasy landscape, aspect-cover cropped
    fx.gd                bursts, floating text, shake, flashes
  screens/
    title.gd             masthead, faction picker, modes, cosmetics, codex, resume
    duel.gd              HUD, table, hand, Oath sheets, score sheet, celebrations
  audit.gd               headless self-test + layout audit (dev only)
assets/cards/            pre-rendered card faces, backs and lightweight effects atlases
assets/ui/               pre-rendered nine-slice frames for the menu, HUD and felt
assets/suits/            static painted suit emblems
tools/                   offline atlas generators and original card sheets
audio/                   generated WAVs: deal, capture, scopa, favor, oath, win, lose, tick…
fonts/                   Cinzel (display) and Alegreya Sans (text), both OFL
```

The menu and duel use static AI-generated fantasy landscapes and faction-tile
art inspired by the supplied layout references. The original supplied card
atlas remains in use for every card. No currencies or progression shown in the
reference mockups were added as fake controls.

The 40 supplied faces and three existing backs share one imported static atlas
on **all** renderers. The source sheets are retained under `tools/card_sources/`,
which Godot ignores so the full-resolution sheets are not packed into the game.
Selection, spin and highlights remain live. On software renderers, highlights,
felt sigils and Favor pips use a second static atlas. To reduce texture switches,
separate card shadows are omitted on that path while the card atlas is present;
full-quality visuals and the vector fallback retain their shadows. If the card atlas is missing,
the old vector artwork is used as a fallback. There is **no runtime atlas baking
or GPU readback**.

To rebuild the card atlas offline, install Python 3 with Pillow, NumPy and
`opencv-python`, then run `python3 tools/build_image_card_atlas.py`. Pass `--check`
to verify the shipped atlas against the source sheets without overwriting it.
The three backs are retained separately in the source folder; regenerate those
only if needed with `godot --path . -s res://tools/generate_card_atlas.gd` on a
working display. The effect atlas is separately generated with
`godot --path . -s res://tools/generate_effect_atlas.gd`. Re-import changed PNGs
in Godot. `screenshots/card_sheet.html` is the **old vector-design mockup**, not
the current card faces.

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

The audit checks, among other things:

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
* the Veiled Warden's twist: 60 complete hidden-table deals are played move by move, asserting the
  veil is set at the deal, never hides a card the player can also see, and never returns once it has
  lifted (one veiled card per hand),
* AI move choice stays under 8 ms (it measures ~30 µs).

Latest run: 300 AI games (318 sweeps), layout clean, **failures=0** — including a real save/resume round-trip through the profile files
(including the JSON int/float coercion that a naive snapshot loses) and all four Oath sheets.

The audit is excluded from exported builds (`exclude_filter` in `export_presets.cfg`).

---

## Next steps

* **Async duels / real PvP:** the state dict is already a complete duel snapshot — wrap it in a small
  turn-based service (or a GodotSteam / WebRTC backend) and swap the local AI call in `duel.gd`'s
  `_run_bot` for a submitted move.
* **Cosmetics store:** card backs and board themes are already data-driven (`Profile.card_back`,
  `BOARD_THEMES`); add a shop screen and more variants, plus sweep animation and emote sets.
* **Ranked ladder, daily quest rotation, battle-pass cosmetics:** all profile-level data, no rule changes.
* **Localisation:** every string is inline English; extract to a `tr()` CSV when the rules are frozen.

---

## Credits

Cinzel and Alegreya Sans are licensed under the SIL Open Font License (Google Fonts).
Scopa is a traditional Italian game; this is an unaffiliated fan reimagining.

### TestFlight builds

See [docs/TESTFLIGHT.md](docs/TESTFLIGHT.md) for the manually triggered iOS
build workflow, required Apple signing secrets, and optional TestFlight upload.
Apple-signed TestFlight uploads have succeeded; physical iOS testing is still required.
