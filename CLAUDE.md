# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## What this repo is

**SLICE IT! · The Potato Cutting Championship** — a rhythm-action potato-cutting game that
exists in **two independent implementations** of the same game design:

- **`PotatoSlicer/`** — the original, fully playable **C# / .NET 8.0 console** game (ASCII UI).
  This is what ships in GitHub Releases as a self-contained binary with an in-game auto-updater.
- **`godot/`** — a **Godot 4.2+ / GDScript** visual remake (graphics, animations, an open-world
  farm). Still in development; no binaries shipped yet.

The two share gameplay concepts (five cut mechanics, four game modes, knives, combos, FEVER,
lives, leaderboard) but **share no code** and version independently (console `1.1.0` in the
csproj / `Core/Updater.cs`; Godot `2.4.0` in `project.godot`). Treat them as two codebases —
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
```
The smoke tests are auto-players, not assertions: `SmokeTest.gd` drives a full championship run
(cuts at centre, locks the peel band, bins rotten potatoes), `FarmSmokeTest.gd` drives the farm
(plow/plant/harvest, sections, sprinklers, fertilizer, save migration) and `TownSmokeTest.gd`
shops the town stalls. CI greps stdout for the `SMOKE OK` / `FARM SMOKE OK` / `TOWN SMOKE OK`
sentinel strings, so any test you add must print its own sentinel and exit.
`tests/Screenshot.tscn` exists for capturing frames.

## CI (`.github/workflows/`)

- **build.yml** — `dotnet build` of the console project on every push to `main` and every PR.
- **godot.yml** — runs only when `godot/**` changes: import/compile check + the three smoke tests.
- **release.yml** — triggered by pushing a `v*` tag (or manual `workflow_dispatch`). Publishes
  self-contained single-file win-x64 and linux-x64 binaries and attaches them to a GitHub Release.

## Cutting a console release

The in-game updater compares the running `VERSION` constant against the latest GitHub Release tag,
so these must stay in lockstep or you get an update loop / false "up to date":
1. Bump `VERSION` in `PotatoSlicer/Core/Updater.cs` **and** `<Version>` in `PotatoSlicer.csproj`.
2. Commit, then `git tag vX.Y.Z && git push origin vX.Y.Z` — the tag must equal `VERSION`.
3. release.yml builds and publishes; the updater finds the new release on next launch.

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

**Balance is data-driven:** knives, potatoes, farm items and field/section geometry live in
`resources/game_data/*.json` (`knives.json`, `potatoes.json`, `items.json`, `fields.json`) — new
content is typically one JSON entry plus (for new mechanics) one `MinigameBase` subclass. Potatoes
are drawn procedurally (no sprite assets required to run).

**The overworld** is two walkable maps in `scripts/world/` sharing a `WorldController` base
(movement, blockers, camera, day-night, prompts, shop overlays, economy actions) and `WorldHUD`:
the **farm** (`FarmController` — three fenced fields of `FarmTile` grid tiles bought section by
section; plow → plant → water/sprinkler → fertilize → harvest, soil stays plowed) and the **town**
(`TownController` — seed/knife/market/tool stalls plus the championship kitchen; the designated
home for future non-farming content). Gates on the map edges travel between them. Farm state is
`SaveDataManager.farm` schema 2 (sparse `tiles` dict keyed `"field:row:col"`); schema-1 saves with
a fixed `plots` array migrate automatically in `SaveDataManager._migrate_farm()` — migration runs
on the raw dict *before* the defaults merge. `scripts/visuals/` holds the procedural backdrops/FX.

See `godot/README.md` and `godot/VISUALS.md` for the detailed expansion guide and current status checklist.

## Conventions

- **Don't cross-pollinate the two editions** — they're parallel implementations, not a shared core.
- Console game balance → `Data/GameData.cs`; Godot game balance → `resources/game_data/*.json`.
- `Game` partials all declare `partial class Game`; keep new game-flow methods in the partial that
  matches its concern rather than growing `Game.cs` unboundedly.
- Any new Godot headless test must print a unique sentinel string and self-quit so CI can grep for it.
