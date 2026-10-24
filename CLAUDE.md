# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## What this repo is

**SLICE IT! · The Potato Cutting Championship** — a rhythm-action potato-cutting game that
exists in **three implementations** of the same game design:

- **`PotatoSlicer/`** — the original, fully playable **C# / .NET 8.0 console** game (ASCII UI).
  This is what ships in GitHub Releases as a self-contained binary with an in-game auto-updater.
- **`godot/`** — a **Godot 4.2+ / GDScript** visual remake (graphics, a fully procedural
  soundtrack, beat-locked gameplay, Concert rhythm mode, the Spudling Acres idle-optimization
  farm, and a 3D first-person multiplayer arena). `release.yml` also exports it (Win/Linux/macOS
  `SliceIt-Visual-*.zip`) into the same GitHub Release as the console build.
- **`web/`** — a **browser edition of Concert mode** (HTML5 canvas + WebAudio, no build step,
  no dependencies). `web/build.py` bundles it into one self-contained `SliceIt-Web.html`, which
  `release.yml` attaches to every release; `web.yml` can deploy it to GitHub Pages.

Separately, **`physics-quest/`** is an unrelated app: **Physics Quest 12**, a Prodigy-style
browser RPG for studying Grade 12 physics (Ontario SPH4U). It shares no code, versioning or
release flow with the potato game; see "Physics Quest 12" below.

The console and Godot editions share gameplay concepts (five cut mechanics, game modes, knives,
combos, FEVER, lives, leaderboard) but **share no code**. They carry their own version constants
(console in the csproj / `Core/Updater.cs`; Godot in `project.godot`) but ship from **one `v*`
tag**, so a release bumps both in lockstep — currently `4.1.0`. Both editions' in-game updaters
read the same `releases/latest`, so the tag must equal both version constants. Treat them as
separate codebases — a change in one does not propagate to the other.

**The one deliberate exception:** `web/core.js` is a line-for-line port of the Godot
`SongComposer.compose()` and `ConcertChart` (same xorshift PRNG, same tables, same decision
order), so a seed composes the identical song + chart on both — the Daily Song is shared. If you
change composition or charting in either, change the other identically and run the parity check
(below); CI fails otherwise. Rendering/synthesis (`web/audio.js` vs `scripts/audio/Synth.gd`) is
also a port but only needs to *sound* the same, not match sample-for-sample.

## Common commands

### Console edition (`PotatoSlicer/`)
```sh
cd PotatoSlicer
dotnet run                 # play the game (SPACE = cut, ESC = quit to menu)
dotnet run -- --no-update  # skip the launch-time auto-update check (use this offline / in CI)
dotnet build PotatoSlicer.csproj -c Release   # what CI runs on every push/PR
```

There is no unit-test project — the console edition is validated only by `dotnet build`.

### Godot edition (`godot/`)
```sh
# Interactive: open godot/ as a project in Godot 4.2+ and press F5
# CI uses Godot 4.2.2 specifically.

cd godot
godot --headless --import .                                             # compile check (fails on SCRIPT ERROR)
godot --headless --path . res://tests/SmokeTest.tscn --quit-after 4000          # → "SMOKE OK"
godot --headless --path . res://tests/BossSmokeTest.tscn --quit-after 2000      # → "BOSS SMOKE OK"
godot --headless --path . res://tests/ConcertSmokeTest.tscn --quit-after 6000   # → "CONCERT SMOKE OK"
godot --headless --path . res://tests/FarmSmokeTest.tscn --quit-after 600       # → "FARM SMOKE OK"
godot --headless --path . res://tests/TownSmokeTest.tscn --quit-after 600       # → "TOWN SMOKE OK"
godot --headless --path . res://tests/FarmBalanceTest.tscn --quit-after 6000    # → "FARM BALANCE OK"
godot --headless --path . res://tests/FarmMigrationTest.tscn --quit-after 3000  # → "FARM MIGRATION OK"
godot --headless --path . res://tests/FpsSmokeTest.tscn --quit-after 300        # → "FPS SMOKE OK"
godot --headless --path . -s tests/farm/farm_sim.gd -- --all  # farm balance report (not CI)
```
The smoke tests are auto-players: `SmokeTest.gd` plays a championship through two stage clears
and FEVER (cuts when the beat-locked cursor is centred, locks the peel band, bins rotten
potatoes), `BossSmokeTest.gd` beats the Colossal Spud, `ConcertSmokeTest.gd` checks chart
determinism then plays a whole Concert song (chops, holds, bins), `FarmSmokeTest.gd` drives the
Spudling Acres scene with synthetic keys/clicks and `FarmClock` time travel (Tend, Collect,
Spudlings, the Catalog, sprinklers, butterflies, the Farm Book), `TownSmokeTest.gd` uses the town
stalls on a frozen clock, and `FpsSmokeTest.gd` frags a target dummy in SPUD BLASTER.
`FarmBalanceTest.gd` (no scene, about 1–2 min) has profile bots play the real `FarmEconomy` on
`farm.json` and asserts the design's milestone windows, feel targets, strategy diversity and
economy invariants; `FarmMigrationTest.gd` checks the schema 1/2/3 → 4 chain and refunds, slots,
debounced saving, the heartbeat and the Farm Picnic. The kitchen/boss/concert tests set
`AudioManager.debug_time_scale = 3.0` so the silent headless beat clock runs 3x fast; their
budgets are wall-clock, with `--quit-after` as a hard frame cap. CI greps stdout for each
sentinel, so any test you add must print its own sentinel and exit. **Give every farm, town and
migration run a fresh `user://`** (`XDG_DATA_HOME=$(mktemp -d) godot …`, or clear
`~/.local/share/godot/app_userdata/`): their save-slot checks assume one, and CI gives each of
those steps its own. Headless farm/town input goes through `get_tree().root.push_input(ev, true)`
or `scene.handle_input(ev)` (`Input.parse_input_event` never reaches the 0x0 headless window);
set `keycode == physical_keycode` so keys aren't read as AZERTY movement aliases.
`tests/Screenshot.tscn` captures frames (run under `xvfb-run … --rendering-driver opengl3`).

### Web edition (`web/`)
```sh
python3 web/build.py                                  # → web/dist/SliceIt-Web.html (one file)
node web/tools/smoke.js web/dist/SliceIt-Web.html     # headless Chromium plays a song → "WEB SMOKE OK"
# parity with the Godot composer (CI runs this in godot.yml):
node web/tools/dump_web.js /tmp/web.json
godot --headless --path godot -s "$PWD/web/tools/dump_godot.gd" -- /tmp/godot.json
python3 web/tools/check_parity.py /tmp/godot.json /tmp/web.json   # → "WEB PARITY OK"
```
`index.html` loads `core.js` + `audio.js` as separate files (GitHub Pages / Node); `build.py`
inlines them. `window.__bot = true` turns on an in-page autoplay that the smoke test uses, and
`window.__slice()` is a read-only state probe.

### Physics Quest 12 (`physics-quest/`)
```sh
node physics-quest/tools/check_questions.js       # every skill x 400 seeds vs reference formulas → "QUESTIONS OK"
python3 physics-quest/build.py                    # → physics-quest/dist/PhysicsQuest12.html (one file)
node physics-quest/tools/smoke.js physics-quest/dist/PhysicsQuest12.html   # headless playthrough → "PHYSICS QUEST SMOKE OK"
```

## CI (`.github/workflows/`)

- **build.yml** — `dotnet build` of the console project on every push to `main` and every PR.
- **godot.yml** — runs when `godot/**` (or the web composer port) changes: import/compile check,
  the six smoke tests, the farm balance gate (`FarmBalanceTest`), the farm save-migration test,
  and the Godot↔web composer parity check. The farm, town, balance and migration steps also fail
  on any `SCRIPT ERROR` in their log (runtime ones included) and each run on a fresh `user://`
  (`XDG_DATA_HOME`). Every Godot step has `timeout-minutes: 5` (balance: 8), since the farm
  heartbeat runs settle code inside every scene.
- **web.yml** — runs when `web/**` changes: bundles the single file and plays a song in headless
  Chromium (landscape + portrait). Its `pages` job deploys to GitHub Pages on a manual run, or on
  pushes to `main` once the repo variable `PAGES_ENABLED` is `"true"`.
- **physics-quest.yml** — runs when `physics-quest/**` changes: the question checker, the
  single-file bundle, and the headless playthrough (landscape + phone).
- **release.yml** — triggered by pushing a `v*` tag (or manual `workflow_dispatch`). Publishes the
  self-contained console win-x64/linux-x64 binaries, the exported Godot Visual edition
  (`SliceIt-Visual-{win-x64,linux-x64,mac}.zip`, when `godot/export_presets.cfg` exists) and the
  bundled web edition (`SliceIt-Web.html`) into one GitHub Release. A tag push marks it `latest`,
  so both desktop editions' auto-updaters pick it up.

## Cutting a release (both editions ship from one tag)

Each in-game updater compares its `VERSION` against the latest GitHub Release tag, and both editions
read the **same** release, so all three must stay in lockstep or you get an update loop / false
"up to date":
1. Bump `VERSION` in `PotatoSlicer/Core/Updater.cs`, `<Version>` in `PotatoSlicer.csproj`, **and**
   `config/version` in `godot/project.godot` — all to the same `X.Y.Z`.
2. Commit, then `git tag vX.Y.Z && git push origin vX.Y.Z` — the tag must equal those versions.
3. release.yml builds & publishes; both editions' updaters find the new release on next launch.
   (Publishing a `latest` release auto-pushes the build to every existing user, so tag from `main`.)
   The web edition has no version constant or updater; release.yml bundles `SliceIt-Web.html`
   from whatever `web/` holds at the tag.

## Console architecture (`PotatoSlicer/`)

`Program.cs` is a one-liner: `new Game().Run(args)`. **`Game` is one `sealed partial class`** split
across files by concern — when you touch game flow, the relevant code may be in any of these:
- `Game.cs` — orchestrator: title/menu, stage loop, the cut sequence, the bar animation/scoring
  render, shop, victory/game-over. The bulk of the UI and main loop.
- `Modes/Modes.cs` — the four `GameMode` loops (Championship / Endless / TimeAttack / Daily).
- `Minigames/Minigames.cs` — the five cut mechanics' input/timing logic.
- `Progression/Progression.cs` — recipes, power-ups, boss.

Supporting (non-partial) pieces:
- `Models/` — `Enums.cs` (`CutQuality`, `CutType` = Sweep/HoldRelease/MultiTarget/ShrinkZone/Dodge,
  `GameMode`), `Knife.cs`, `Potato.cs`.
- `Data/GameData.cs` — the static knife / potato / stage tables (game balance lives here).
- `Core/` — `Scoring.cs`, `Leaderboard.cs`, `SaveData.cs`, `Updater.cs`.
- `UI/` — `Render.cs` (all console drawing) and `Audio.cs` (console beeps).

Persistence: `SaveData` serializes to **`savedata.json` next to the binary** (`AppContext.BaseDirectory`),
holding high score, coins, unlocks, leaderboard, achievements.

## Godot architecture (`godot/`)

**Autoload singletons** (declared in `project.godot`, available globally) carry cross-scene state:
- `scripts/core/GameManager.gd` — game state, score/combo/FEVER/lives, run stats (`record_cut`,
  `accuracy`, `grade`, personal bests), mode control, F11 fullscreen; emits signals UI listens to.
- `scripts/core/SaveDataManager.gd` — JSON persistence (leaderboard, achievements, unlocked knives,
  settings incl. volumes/`audio_offset_ms`/bests, 3 save slots); auto-saves on change. Also owns
  the farm save (schema 4, its migration chain, the debounced farm writer and the 30 s farm
  heartbeat) and classroom low-power mode — see the farm below.
- `scripts/core/AudioManager.gd` — **all sound, and the beat clock.** `play_sfx(name)` plays a
  synthesized SFX; `play_music(track)` / `play_song({style, bpm, seed})` composes + renders a song
  on a `WorkerThreadPool` task (cached, prefetchable, two-deck crossfades) as four synced stems
  (drums/harmony/lead/fever) whose gains `set_layer()` fades. `music_time()` / `music_beat()` is
  the clock gameplay locks to: it runs on the wall clock from the moment a song is requested (so it
  works with sound off and on the headless server — `audio_live` is false there and nothing is
  rendered), and once audio joins, drift against the real playback position is slewed out each
  frame. `pause_music()`/`resume_music()` freeze it. Verified against real PulseAudio output to
  track the heard beat within a few ms.
- Also: `Security`, `MultiplayerManager`, `FpsNetwork`, `OnlineLeaderboard`, `StyleManager`,
  `UpdateManager`.

**Audio is procedural** (`scripts/audio/`, no audio assets): `Synth.gd` (polyBLEP oscillators, FM,
ADSR, filters, drum kit, circular echo, fast PCM16 packing), `SfxLibrary.gd` (every SFX as a
recipe, loudness-normalized; add one = one entry in `build()`), `SongComposer.gd` (styles → drums,
bass, chords, contour-based melodies; `compose()` is deterministic per seed, `render()` is the
heavy worker-thread part). Its inner `Rng` must stay deterministic — don't call Godot's global
`randf()`/`randi()` from composition code (an unqualified `randf()` inside that class once did).

Main scene is `scenes/MainMenu.tscn`. Gameplay flow: `MainMenuController` → `GameplayController`
(plays the stage's song, schedules potatoes onto bar lines, picks the minigame) → a `MinigameBase`
subclass → `GameOver.tscn` (results). ESC opens `PauseOverlay` (works while the tree is paused).

**The kitchen is beat-locked.** Each stage has a song (`GameplayController.STAGE_STYLES`, tempo
`BASE_BPM * stage scale`); a potato's drop-in starts early so it *lands* on a bar line, and that
beat is the minigame's `beat_origin`. Cursors are pure functions of `AudioManager.music_beat()` —
never accumulate frame deltas. The classic sweep (`set_sweep(4.0)`) crosses the centre on beat 3,
the snare of every kitchen groove (all kitchen styles are "half-time": snare on beat 3 only).

**Minigames are the main extension point.** Every cut mechanic in `scripts/minigames/` extends
`MinigameBase.gd` and is wired into `GameplayController._create_minigame()`. To add one: subclass
`MinigameBase`, call `super.start_minigame(potato, origin_beat)`, drive visuals from `beats()` /
`sweep_cursor()` (use `change_sweep()` to change speed without a jump), express timeouts in beats,
implement `_on_primary_input()` / `_on_secondary_input()`, set `cut_result.quality`
(PERFECT/GREAT/GOOD/MISS/FAIL) and `cut_result.score_multiplier` (0.0–1.5), call `end_minigame()`,
then register it in `_create_minigame()`.

**Concert mode** (`scripts/concert/`, `scenes/Concert/`) is a note-highway rhythm mode:
`ConcertChart` derives a song's identity from a seed (`spec_for_seed`, `daily_seed`, `SETLIST`)
and builds the chart from the composed song (intro = drums, verse/chorus/finale = melody; chop /
hold / rotten / golden notes; per-difficulty `RULES`); `ConcertController` runs song select
(live previews), the conveyor, judging (±45/90/135 ms), HYPE, multipliers and FEVER, then hands the
run to the shared results screen. **Keep `ConcertChart.gd` and `SongComposer.compose()` in
lockstep with `web/core.js`.**

**Balance is data-driven** (`resources/game_data/`): kitchen knives and potatoes in `knives.json` /
`potatoes.json`, achievements in `achievements.json`, the whole farm economy in `farm.json` (below)
— new kitchen content is typically one JSON entry plus (for new mechanics) one `MinigameBase`
subclass. Potatoes are drawn procedurally (no sprite assets required to run).

**The overworld** is two walkable maps in `scripts/world/` sharing a `WorldController` base
(movement, blockers, a camera with overview/follow zoom on Z, the wheel or trackpad pan/pinch,
a real-clock night tint, clickable stations with a proximity prompt, the Farm Book drawer, the knife
stand, popups) and `WorldHUD` (all drawn UI). Every click target is registered in a
`scripts/ui/HitRegions.gd`, padded to ≥ 44 px — the trackpad rule: nothing needs drag, double-click,
right-click or hover. Input routes Pip's note (modal) → the open drawer → HUD regions → the world.
Real input on either map calls `FarmEconomy.note_input` (at most once a frame); nothing else does,
so the kitchen, the menu and an idle open window all count as "away". Both maps settle the farm
every 0.5 s; gates link them. `scripts/visuals/` holds the procedural backdrops/FX.

**Spudling Acres, the farm** (`FarmController`, `FarmHud`, `FarmBook`, `FarmField`, `FarmCritters`,
`FarmBackground`), is a cozy incremental optimization game. Six fenced fields of 12 plots plus a late
Greenhouse (index 6) are bought with deeds. One verb, **Tend**, works on a whole field: harvest the
ripe crop and replant the field's **plan** (set free in its field card, which shows each crop's
"ready at" time), or plant an empty one; a short wallet plants free Russet. Coins pay at harvest
and nothing rots. Short crops pay more per minute, long ones more per harvest, so the best plan is
the crop that ripens just before you're back. **Spudlings** (a hut per field: Pip, Dot, …) clock in
`clock.clockin_s` after your last input, work the **shift** the farmhouse tier sets, pick after a
walk (Quick Hands) and replant free, then nap. A crop standing when you left is *yours*: it gets a
grace of min(`clock.your_crop_grace_s`, its grow time) past ripe, then pays full value × your star
EV; crops they planted while you were away pay their **share**. Crops unlock through the **Seed
Catalog** (pages gated on plots *shipped*, so kitchen coins can't skip it). Every coin purchase is a
**Farm Book** row (Land · Helpers · Tools · Soil & Strains · Catalog · Stats) showing its cost,
"+X/min here · +Y/min away" and a payback for *your* logged schedule (`absences`/`presence`); there
is no auto-buyer — [Pin] sets the Next Goal and Q buys it. More levers: **fence sprinklers** (a
socket on each shared fence waters both neighbours; moving is free), the **Greenhouse**,
Copper/Iron/Gold **Hoes**, infinite **Soil**, per-crop **Prize Strains** (ribbons on the farmhouse)
and the daily **Market Favorite** (a date hash; the bonus locks at planting). **Butterflies** visit
while you're here; a welcome one follows Collect after a long absence. **Pip's note** reports an
absence and **[Collect]** hand-tends every ripe field, so a check-in is note → Collect → butterfly →
one decision. Nothing runs while the game is closed: the next `settle()` computes the absence in
closed form (**offline settle**). **Cross-mode:** the wallet is shared; kitchen, Concert and SPUD
BLASTER runs also pay a capped **Farm Picnic** (`SaveDataManager.award_picnic`); Strains raise the
kitchen's golden odds (`kitchen_golden_bonus`); santoku/chef/cleaver have Chef-XP gates
(`knives.json` `unlock_xp`); the menu's Farm row shows a `FarmEconomy.preview()` teaser. The
**town** (`TownController`) holds the knife stand, the championship kitchen, the Concert Hall
bandstand and two farm storefronts (seed stall → Book Catalog tab, tool shed → Tools tab; they sell
nothing extra). It is the home for future non-farming content.

**Farm code.** `scripts/farm/FarmEconomy.gd` is the entire economy: static and **pure** over
`(farm: Dictionary, now_ms: int, tz_s: int)` — no `Time`, nodes, audio, saving or global RNG (its
xorshift32 state is `farm.rng`). Times are integer ms and fractional coins an integer milli-coin
`carry`, so one bulk `settle()` equals many small ones (asserted, with JSON round-trips). Actions
(`tend`, `tend_all`, `collect`, `set_plan`, `replant_now`, `buy`, `place_sprinkler`,
`catch_butterfly`, …) settle first, mutate the dict and return `{ok, coins, spent, msg, events}`;
queries (`field_view`, `plan_options`, `book`, `next_goal`, `preview`, `rate_here`/`rate_away`)
never mutate. Scenes mutate farm state only through it and turn `events` into achievements, SFX and
banners. `FarmClock` is the only farm code that reads the time (`offset_ms` time travel,
`frozen_ms`, `tz_override` for tests); `FarmView` holds pure read-only scene helpers (geometry
from `farm.json`, note/report peeks); `FarmMigration` is the pure schema-3 → 4 conversion;
`scripts/utils/NumFmt.gd` formats every wallet, rate, duration and clock time. Autoloads and
`FarmEconomy` itself must not name these classes as identifiers — `load()`/`preload()` them by path
(a fresh checkout parses autoloads before the global class list exists; see commit 3000e3d).

**Farm saves.** `SaveDataManager.farm` is schema 4; `FarmEconomy.new_farm()` is its template
(seven `fields` with plan/crop/`planted_g`/`by`/`seed_paid`/`fav`/`hut`/milli-coin `carry`, plus
the clock stamps, upgrades `up`, Catalog `page`, `shipped`, income buckets, the session log, buffs,
`report`, `goal`, `rng`, `ui` and the one-time `migration` ledger). Older saves chain 1→2→3→4 in
`SaveDataManager._migrate_farm()` on the raw dict *before* the defaults merge; 3→4 is
`FarmMigration.migrate_v3` fed the frozen v3 tables in `resources/game_data/legacy/`
(`research_v3`/`items_v3`/`crops_v3.json`, via `GameData.legacy_tables()`), so balance edits never
change how an old save lands: retired gear and research come back as coins, unlocks stay, and the
raw file is copied once to `farm.schema3.json`. `FarmEconomy.normalize()` deep-fills defaults and
int-casts after every load (Godot's JSON parses numbers as floats). Scenes call
`request_farm_save()` after each action (written 2 s after the last request, forced every 10 s);
`flush_farm()` writes at once and runs on scene exit, focus-out, window close, slot switch and
before quitting; `save_farm()` writes only `farm.json`. A 30 s heartbeat `Timer`
(`PROCESS_MODE_ALWAYS`) settles a started farm from every scene and never stamps input. Scenes
that idle cheaply (menu, farm, town) call `set_low_power_ok(true)`, so losing focus drops to
`LOW_POWER_FPS` with OS low-processor mode. **Never cache `SaveDataManager.farm`** (or anything
inside it): `switch_slot()`, `load_game()` and tests replace it wholesale, so re-read it every tick.

**Farm balance.** `resources/game_data/farm.json` is the single balance source (crops, price
ladders, multipliers, the Catalog, clock rules, even the field layout). Read numbers at runtime
through `FarmEconomy.cfg()` / `crop_info()` / `cost_of()`; never hard-code a tuned value in scene
code, tests or docs. Tune with the simulator (from `godot/`):
`godot --headless --path . -s tests/farm/farm_sim.gd -- --all`, or `--profile class --days 14 --log`
for one player, or `--override '<json>'` to try a knob without editing the file. It plays the real
`FarmEconomy` with the design's profile bots (`tests/farm/FarmBot.gd`, `FarmSuite.gd`).
`tests/farm/BALANCE.md` records the evidence and why each knob sits where it does; update it with
any `farm.json` change. `FarmBalanceTest` is the CI gate.

**SPUD BLASTER** (`scripts/fps/`, menu item [9]) is a 3D first-person deathmatch — the only 3D mode
in an otherwise 2D game, built entirely in code (no art assets). `FpsNetwork` (autoload) manages the
session: offline practice vs. bots, LAN host (ENet UDP `7370`), or client-by-IP, plus a threaded
**UPnP** port-forward + public-IP lookup so a host is reachable over the internet ("global"). It is
separate from the rhythm-duel `MultiplayerManager` (`scripts/multiplayer/`, port `7369`) — don't
conflate the two. `FpsArena.gd` has a stable scene path and owns all gameplay RPCs; the host (or the
lone offline peer) is authoritative for health/frags/respawns while each peer simulates and
broadcasts its own avatar (ENet server relay carries client→client packets). `FpsPlayer`/`FpsBot`/
`FpsHud` are the avatar, practice dummy and HUD.

See `godot/README.md` and `godot/VISUALS.md` for the detailed expansion guide and current status checklist.

## Web architecture (`web/`)

`core.js` (deterministic composer + chart, Node-loadable), `audio.js` (synth, SFX, stem renderer →
`AudioBuffer`s), `index.html` (the game: one canvas, a `state` machine title → select → play →
outro → results, landscape 1280×720 or a portrait 720×1280 chute chosen from the viewport). Songs
start sample-accurately via `AudioBufferSourceNode.start(when)`; the clock is
`AudioContext.getOutputTimestamp()` interpolated with `performance.now()`, and inputs are judged at
`event.timeStamp`. Per-browser bests/settings live in `localStorage` (wrapped in try/catch).
Shareable links use a bare hash token `#s<seed>-<difficulty>`.

## Physics Quest 12 architecture (`physics-quest/`)

Plain HTML/JS, no build step, no dependencies, no assets (everything is drawn on a canvas).
- `questions.js` (Node-loadable, `window.PQ` in the browser) — `SKILLS`: each numeric skill is
  `S(id, unit, tier, name, gen)` where `gen(rng)` returns the givens `p`, `ans`, `unit`, `wrong`
  (distractors modelled on real mistakes), `steps` and `formula`. **Compute the answer from the
  values exactly as shown in the prompt** (round givens first). `makeQuestion(skill, seed)` builds
  four distinct choices; `checkTyped` accepts typed answers within 2%; `calc` is a safe evaluator
  (degrees, no `eval`). Concept questions are rows in `CONCEPTS`. Units: dyn/enm/fld/wav/mod.
- **Every numeric skill needs a matching independent formula in `REF` in
  `tools/check_questions.js`**, or the checker (and CI) fails.
- `game.js` — one IIFE: a 3×2 grid of zones (hub + one per unit, chained by gates opened by
  each boss), battles (spell → question → damage), the Codex (practice, unit tests, formula sheet,
  mistake journal), shop/bag, title, saves in `localStorage` key `physicsQuest12.save.v1`
  (wrapped in try/catch). `window.__pq()` is a read-only probe and `window.__pqDebug` has test
  helpers (`battle`, `set`, `teleport`, `mapCheck`) that the smoke test uses.

## Conventions

- **Don't cross-pollinate the editions** — they're parallel implementations, not a shared core
  (except the composer/chart port above, which must stay identical).
- Console game balance → `Data/GameData.cs`; Godot game balance → `resources/game_data/*.json`
  (the farm: `farm.json` only — then re-run the simulator and update `tests/farm/BALANCE.md`).
- `Game` partials all declare `partial class Game`; keep new game-flow methods in the partial that
  matches its concern rather than growing `Game.cs` unboundedly.
- Any new Godot headless test must print a unique sentinel string and self-quit so CI can grep for it.
- Any sound goes through `AudioManager` — add a recipe to `SfxLibrary.build()` (and a `LOUDNESS`
  target) rather than shipping an audio file. Music styles are data in `SongComposer.STYLES`.
