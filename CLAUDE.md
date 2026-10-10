# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## What this repo is

**SLICE IT! · The Potato Cutting Championship** — a rhythm-action potato-cutting game that
exists in **three implementations** of the same game design:

- **`PotatoSlicer/`** — the original, fully playable **C# / .NET 8.0 console** game (ASCII UI).
  This is what ships in GitHub Releases as a self-contained binary with an in-game auto-updater.
- **`godot/`** — a **Godot 4.2+ / GDScript** visual remake (graphics, a fully procedural
  soundtrack, beat-locked gameplay, Concert rhythm mode, an open-world farm, and a 3D first-person
  multiplayer arena). `release.yml` also exports it (Win/Linux/macOS `SliceIt-Visual-*.zip`) into
  the same GitHub Release as the console build.
- **`web/`** — a **browser edition of Concert mode** (HTML5 canvas + WebAudio, no build step,
  no dependencies). `web/build.py` bundles it into one self-contained `SliceIt-Web.html`, which
  `release.yml` attaches to every release; `web.yml` can deploy it to GitHub Pages.

The console and Godot editions share gameplay concepts (five cut mechanics, game modes, knives,
combos, FEVER, lives, leaderboard) but **share no code**. They carry their own version constants
(console in the csproj / `Core/Updater.cs`; Godot in `project.godot`) but ship from **one `v*`
tag**, so a release bumps both in lockstep — currently `4.0.0`. Both editions' in-game updaters
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
godot --headless --path . res://tests/SmokeTest.tscn --quit-after 4000        # → "SMOKE OK"
godot --headless --path . res://tests/BossSmokeTest.tscn --quit-after 2000    # → "BOSS SMOKE OK"
godot --headless --path . res://tests/ConcertSmokeTest.tscn --quit-after 6000 # → "CONCERT SMOKE OK"
godot --headless --path . res://tests/FarmSmokeTest.tscn --quit-after 600     # → "FARM SMOKE OK"
godot --headless --path . res://tests/TownSmokeTest.tscn --quit-after 600     # → "TOWN SMOKE OK"
godot --headless --path . res://tests/FpsSmokeTest.tscn --quit-after 300      # → "FPS SMOKE OK"
```
The smoke tests are auto-players: `SmokeTest.gd` plays a championship through two stage clears
and FEVER (cuts when the beat-locked cursor is centred, locks the peel band, bins rotten
potatoes), `BossSmokeTest.gd` beats the Colossal Spud, `ConcertSmokeTest.gd` checks chart
determinism then plays a whole Concert song (chops, holds, bins), `FarmSmokeTest.gd` drives the
farm (plow/plant/harvest, sprinklers, fertilizer, save migration), `TownSmokeTest.gd` shops the
town stalls, and `FpsSmokeTest.gd` frags a target dummy in SPUD BLASTER. The kitchen/boss/concert
tests set `AudioManager.debug_time_scale = 3.0` so the silent headless beat clock runs 3x fast;
their budgets are wall-clock, with `--quit-after` as a hard frame cap. CI greps stdout for each
sentinel, so any test you add must print its own sentinel and exit. **Clear
`~/.local/share/godot/app_userdata/` between local runs** — the farm test's save-slot checks
assume a fresh `user://` (CI always has one). `tests/Screenshot.tscn` captures frames (run under
`xvfb-run … --rendering-driver opengl3`).

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

## CI (`.github/workflows/`)

- **build.yml** — `dotnet build` of the console project on every push to `main` and every PR.
- **godot.yml** — runs when `godot/**` (or the web composer port) changes: import/compile check,
  the six smoke tests, and the Godot↔web composer parity check.
- **web.yml** — runs when `web/**` changes: bundles the single file and plays a song in headless
  Chromium (landscape + portrait). Its `pages` job deploys to GitHub Pages on a manual run, or on
  pushes to `main` once the repo variable `PAGES_ENABLED` is `"true"`.
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
  settings incl. volumes/`audio_offset_ms`/bests, 3 save slots); auto-saves on change.
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

**Balance is data-driven:** knives, potatoes, farm items and the research tree live in
`resources/game_data/*.json` (`knives.json`, `potatoes.json`, `items.json`, `research.json`) — new
content is typically one JSON entry plus (for new mechanics) one `MinigameBase` subclass. Potatoes
are drawn procedurally (no sprite assets required to run).

**The overworld** is two walkable maps in `scripts/world/` sharing a `WorldController` base
(movement, blockers, camera, day-night, prompts, shop overlays, economy actions) and `WorldHUD`:
the **farm** (`FarmController` — the whole pasture is one free-form plowable grid; `FarmTile`s are
sparse, created on demand only once a cell is plowed or holds a sprinkler; plow → plant →
water/sprinkler → fertilize → harvest, soil stays plowed; `[C]` covers a plowed plot back to
grass for coins — 9 freebies, no plow refund, must replow) and the **town** (`TownController` —
seed/knife/tool stalls, the championship kitchen and the Concert Hall bandstand that enters Concert
mode; the designated home for future non-farming content). Progression runs on the farm's **Research Shed** (`research.json` nodes bought with coins +
research points: logistics/tools/crops/growth/science/water/soil/championship, incl. research-gated
crops; a PROGRESSION and an AUTOMATION track switched with [TAB], upgrades in many small tiers). The automation
track's standing orders are managed at two yard buildings — the **Seed Co-op** and **Supply Depot**,
each shuttered until its standing-order research is bought — where the player schedules which
crops/fertilizer the farm auto-restocks and how much to keep on hand (orders pay a delivery premium,
so a fully-automated farm runs at a thinner margin than buying by hand). The harvest ships on the
**market truck** at the top of the farm (load spuds, send it off, coins + RP return after a wall-clock
delay — selling no longer happens in town). Gates on the map edges travel between them. Farm state is
`SaveDataManager.farm` schema 3 (sparse `tiles` dict keyed `"col:row"`, plus `research`/
`research_points`/`truck`/`seed_order`/`fertilizer_order`); schema-1 (`plots` array) and schema-2 (`field:row:col` + `sections_owned`)
saves migrate automatically through `SaveDataManager._migrate_farm()` (a 1→2→3 chain) — migration
runs on the raw dict *before* the defaults merge. `scripts/visuals/` holds the procedural backdrops/FX.

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

## Conventions

- **Don't cross-pollinate the editions** — they're parallel implementations, not a shared core
  (except the composer/chart port above, which must stay identical).
- Console game balance → `Data/GameData.cs`; Godot game balance → `resources/game_data/*.json`.
- `Game` partials all declare `partial class Game`; keep new game-flow methods in the partial that
  matches its concern rather than growing `Game.cs` unboundedly.
- Any new Godot headless test must print a unique sentinel string and self-quit so CI can grep for it.
- Any sound goes through `AudioManager` — add a recipe to `SfxLibrary.build()` (and a `LOUDNESS`
  target) rather than shipping an audio file. Music styles are data in `SongComposer.STYLES`.
