# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## What this repo is

**SLICE IT! · The Potato Cutting Championship** — a rhythm-action potato-cutting game that
exists in **two independent implementations** of the same game design:

- **`PotatoSlicer/`** — the original, fully playable **C# / .NET 8.0 console** game (ASCII UI).
  This is what ships in GitHub Releases as a self-contained binary with an in-game auto-updater.
- **`godot/`** — a **Godot 4.2+ / GDScript** visual remake (graphics, animations, an open-world
  farm, and a 3D first-person multiplayer arena). `release.yml` now also exports it (Win/Linux/macOS
  `SliceIt-Visual-*.zip`) into the same GitHub Release as the console build.

The two share gameplay concepts (five cut mechanics, four game modes, knives, combos, FEVER,
lives, leaderboard) but **share no code**. They carry their own version constants (console in the
csproj / `Core/Updater.cs`; Godot in `project.godot`) but ship from **one `v*` tag**, so a release
bumps both in lockstep — currently `3.0.0`. Both editions' in-game updaters read the same
`releases/latest`, so the tag must equal both version constants. Treat them as two codebases —
a change in one does not propagate to the other.

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
godot --headless --import .                                          # compile check (fails on SCRIPT ERROR)
godot --headless --path . res://tests/SmokeTest.tscn --quit-after 900      # gameplay smoke test → prints "SMOKE OK"
godot --headless --path . res://tests/FarmSmokeTest.tscn --quit-after 600  # farm smoke test → prints "FARM SMOKE OK"
godot --headless --path . res://tests/TownSmokeTest.tscn --quit-after 600  # town smoke test → prints "TOWN SMOKE OK"
godot --headless --path . res://tests/FpsSmokeTest.tscn --quit-after 300   # FPS arena smoke test → prints "FPS SMOKE OK"
```
The smoke tests are auto-players, not assertions: `SmokeTest.gd` drives a full championship run
(cuts at centre, locks the peel band, bins rotten potatoes), `FarmSmokeTest.gd` drives the farm
(plow/plant/harvest, sections, sprinklers, fertilizer, save migration), `TownSmokeTest.gd`
shops the town stalls, and `FpsSmokeTest.gd` boots a solo SPUD BLASTER match and shoots a target
dummy to score a frag. CI greps stdout for the `SMOKE OK` / `FARM SMOKE OK` / `TOWN SMOKE OK` /
`FPS SMOKE OK` sentinel strings, so any test you add must print its own sentinel and exit.
`tests/Screenshot.tscn` exists for capturing frames.

## CI (`.github/workflows/`)

- **build.yml** — `dotnet build` of the console project on every push to `main` and every PR.
- **godot.yml** — runs only when `godot/**` changes: import/compile check + the four smoke tests
  (championship, farm, town, FPS arena).
- **release.yml** — triggered by pushing a `v*` tag (or manual `workflow_dispatch`). Publishes the
  self-contained console win-x64/linux-x64 binaries **and**, when `godot/export_presets.cfg` is
  present, the exported Godot Visual edition (`SliceIt-Visual-{win-x64,linux-x64,mac}.zip`) into one
  GitHub Release. A tag push marks it `latest`, so both editions' auto-updaters pick it up.

## Cutting a release (both editions ship from one tag)

Each in-game updater compares its `VERSION` against the latest GitHub Release tag, and both editions
read the **same** release, so all three must stay in lockstep or you get an update loop / false
"up to date":
1. Bump `VERSION` in `PotatoSlicer/Core/Updater.cs`, `<Version>` in `PotatoSlicer.csproj`, **and**
   `config/version` in `godot/project.godot` — all to the same `X.Y.Z`.
2. Commit, then `git tag vX.Y.Z && git push origin vX.Y.Z` — the tag must equal those versions.
3. release.yml builds & publishes; both editions' updaters find the new release on next launch.
   (Publishing a `latest` release auto-pushes the build to every existing user, so tag from `main`.)

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

Three **autoload singletons** (declared in `project.godot`, available globally) carry all cross-scene state:
- `scripts/core/GameManager.gd` — game state, score/combo/FEVER/lives, mode control; emits signals
  (e.g. `combo_changed`) that UI listens to.
- `scripts/core/SaveDataManager.gd` — JSON persistence (leaderboard, achievements, unlocked knives,
  settings); auto-saves on change.
- `scripts/core/AudioManager.gd` — SFX/music playback and per-bus volume (framework wired; OGG assets pending).

Main scene is `scenes/MainMenu.tscn`. Gameplay flow: `MainMenuController` → `GameplayController`
(spawns potatoes, picks the minigame) → a `MinigameBase` subclass.

**Minigames are the main extension point.** Every cut mechanic in `scripts/minigames/` extends
`MinigameBase.gd` and is wired into `GameplayController._create_minigame()`. To add one: subclass
`MinigameBase`, implement `_on_primary_input()` / `_on_secondary_input()`, set `cut_result.quality`
(PERFECT/GREAT/GOOD/MISS/FAIL) and `cut_result.score_multiplier` (0.0–1.5), call `end_minigame()`,
then register it in `_create_minigame()`.

**Balance is data-driven:** knives, potatoes, farm items and the research tree live in
`resources/game_data/*.json` (`knives.json`, `potatoes.json`, `items.json`, `research.json`) — new
content is typically one JSON entry plus (for new mechanics) one `MinigameBase` subclass. Potatoes
are drawn procedurally (no sprite assets required to run).

**The overworld** is two walkable maps in `scripts/world/` sharing a `WorldController` base
(movement, blockers, camera, day-night, prompts, shop overlays, economy actions) and `WorldHUD`:
the **farm** (`FarmController` — the whole pasture is one free-form plowable grid; `FarmTile`s are
sparse, created on demand only once a cell is plowed or holds a sprinkler; plow → plant →
water/sprinkler → fertilize → harvest, soil stays plowed) and the **town** (`TownController` —
seed/knife/tool stalls plus the championship kitchen; the designated home for future non-farming
content). Progression runs on the farm's **Research Shed** (`research.json` nodes bought with coins +
research points: logistics/tools/crops/growth, incl. research-gated crops) and the **market truck**
at the top of the farm (load spuds, send it off, coins + RP return after a wall-clock delay — selling
no longer happens in town). Gates on the map edges travel between them. Farm state is
`SaveDataManager.farm` schema 3 (sparse `tiles` dict keyed `"col:row"`, plus `research`/
`research_points`/`truck`); schema-1 (`plots` array) and schema-2 (`field:row:col` + `sections_owned`)
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

## Conventions

- **Don't cross-pollinate the two editions** — they're parallel implementations, not a shared core.
- Console game balance → `Data/GameData.cs`; Godot game balance → `resources/game_data/*.json`.
- `Game` partials all declare `partial class Game`; keep new game-flow methods in the partial that
  matches its concern rather than growing `Game.cs` unboundedly.
- Any new Godot headless test must print a unique sentinel string and self-quit so CI can grep for it.
