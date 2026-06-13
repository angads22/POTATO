# SLICE IT! · Godot Visual Edition

A fully visual rhythm-action game: the potato cutting championship comes to life with graphics, animations, and expandable gameplay.

## Project Structure

```
godot/
├── project.godot              # Engine configuration
├── scenes/                    # Game scenes (tscn files)
│   ├── MainMenu/              # Main menu, mode select, settings
│   ├── Gameplay/              # Main gameplay scene
│   ├── Shop/                  # Knife shop, power-up menu
│   └── GameModes/             # Mode-specific scenes (championship, endless, etc.)
├── scripts/                   # GDScript source code
│   ├── core/                  # Managers (GameManager, SaveDataManager, AudioManager)
│   ├── gameplay/              # Gameplay orchestration and flow
│   ├── minigames/             # Cut mechanics (Slice, Peel, Speed, Julienne, Dodge)
│   ├── world/                 # Open-world farm + town (controllers, tiles, player, HUD)
│   ├── visuals/               # Procedural backdrops and effects
│   ├── ui/                    # Menu controllers, HUD elements
│   └── utils/                 # Helper functions, data structures
├── assets/                    # Game assets (to be populated)
│   ├── sprites/               # Potato, knife, UI sprites
│   ├── animations/            # Cut animations, transitions
│   ├── audio/                 # Music and sound effects
│   ├── fonts/                 # Custom fonts
│   └── themes/                # UI themes
└── resources/                 # Game data resources
    ├── game_data/             # Knife tables, potato recipes
    └── saves/                 # Player save files (runtime)
```

## Architecture Overview

### Core Systems (AutoLoad Singletons)

These are global managers available everywhere:

- **GameManager** — Game state, scoring, mode control, lives system
  - Tracks: stage, lives, score, combo, fever mode
  - Emits signals for UI updates
  - Controls game flow and progression

- **AudioManager** — Music and sound effects
  - Framework for SFX loading and playback
  - Volume control per bus (master, music, sfx)
  - Toggle audio on/off

- **SaveDataManager** — Persistent data
  - Leaderboard (top 10 scores)
  - Achievements
  - Unlocked knives
  - Settings (volume, graphics options)
  - Auto-save on changes

### Gameplay Flow

1. **MainMenuController** — Menu navigation
2. **GameplayController** — Orchestrates potato spawning and minigame flow
3. **MinigameBase** — Abstract base for all cut mechanics
4. **SpecificMinigames** — SliceMinigame, PeelMinigame, SpeedCutMinigame, JulienneMinigame, DodgeMinigame

### Game Modes

- **Championship** — 6-stage campaign with final boss; stage-clear bonuses
  and a life restored every other stage
- **Endless** — Infinite waves with escalating wave bonuses and golden-potato
  odds that climb the deeper you survive

### The Overworld (Farm + Town)

Two walkable maps share a `WorldController` base (movement, blockers, camera,
day-night cycle, prompts, shop overlays, economy actions) and a `WorldHUD`:

- **The farm** (`FarmController`, `scenes/Farm/FarmScene.tscn`) — three fenced
  fields of grid tiles (`FarmTile`, 12 + 20 + 27 tiles) that unlock section by
  section for escalating sums (`resources/game_data/fields.json`). Tiles start
  wild: plow them (the plow wears out after 10 uses; replacements cost more
  each time), plant, water (or place a sprinkler on a tile to auto-water its
  8 neighbours), fertilize (multi-charge), harvest — the soil stays plowed.
  The farmhouse, well and pond live here.
- **The town** (`TownController`, `scenes/Town/TownScene.tscn`) — the seed
  shop, knife stand, sell-market and tool shed around a fountain plaza, plus
  the championship kitchen (walk in to start a run). Future non-farming
  content belongs here (there's a boarded "coming soon" lot on the plaza).
- Gates on the farm's east hedge and the town's west hedge travel between the
  two; the time of day carries across.

Farm state lives in `SaveDataManager.farm` (schema 2: sparse `tiles` dict
keyed `"field:row:col"`, `sections_owned`, `plow_uses`/`plows_bought`,
`sprinkler_stock`, fertilizer charges in `items`). Schema-1 saves (fixed
`plots` array) are migrated automatically on load.

### SPUD BLASTER — 3D first-person arena (multiplayer)

A first-person potato deathmatch, reachable from the main menu ([9]). This is
a true 3D mode (the rest of the game is 2D) and everything in it is built
procedurally in code — no art assets:

- `scripts/fps/FpsNetwork.gd` (autoload `FpsNetwork`) — the session manager.
  Three modes: **offline** practice vs. target-dummy bots, **host** (an ENet
  server on UDP `7370`), and **client** (join by IP). Hosting also fires a
  background **UPnP** worker that forwards the port and reports the machine's
  public IP, so a host is reachable both on the LAN and over the internet
  ("global"). If UPnP isn't available the lobby explains the manual
  port-forward fallback. It is fully independent of the rhythm-duel
  `MultiplayerManager` (different port, different game).
- `scripts/fps/FpsLobbyController.gd` (`scenes/Fps/FpsLobby.tscn`) — host /
  join-by-IP / practice, shows the LAN + public addresses and the roster; the
  host presses ENTER to start the match for everyone.
- `scripts/fps/FpsArena.gd` (`scenes/Fps/FpsArena.tscn`) — a procedurally
  built box arena. It has a stable scene path, so it owns all the gameplay
  RPCs (movement / shots / damage / scores). The host (or, offline, the lone
  peer) is authoritative for health, frags and respawns; each peer simulates
  its own avatar and broadcasts its transform, and ENet's server relay carries
  client→client packets.
- `scripts/fps/FpsPlayer.gd` — a code-built first-person `CharacterBody3D`
  (mouse-look, WASD, jump, hitscan spud-gun). `FpsBot.gd` is the practice
  target dummy. `FpsHud.gd` draws the crosshair / health / scoreboard / timer.

Controls: WASD move · mouse look · LMB (or F) shoot · SPACE jump · ESC pause.

## Adding New Features

### Adding a New Minigame Mechanic

1. Create a new script in `scripts/minigames/` that extends `MinigameBase`
2. Implement `_on_primary_input()` and `_on_secondary_input()` with cut logic
3. Set `cut_result.quality` (PERFECT/GREAT/GOOD/MISS/FAIL)
4. Set `cut_result.score_multiplier` (0.0-1.5)
5. Call `end_minigame()` when done
6. Reference it in `GameplayController._create_minigame()`

Example:
```gdscript
extends MinigameBase

func _on_primary_input():
	# Your logic here
	cut_result.quality = "GREAT"
	cut_result.score_multiplier = 1.25
	end_minigame()
```

### Adding Visual Assets

1. **Sprites** — Place PNG files in `assets/sprites/`
   - Potatoes: `potato_russet.png`, `potato_purple.png`, etc.
   - Knife: `knife_butter.png`, `knife_damascus.png`, etc.
   - UI: buttons, backgrounds, etc.

2. **Animations** — Create AnimatedSprite2D nodes in scenes
   - Cut animations (slice_perfect, peel_great, etc.)
   - Potato split/damage animations
   - UI transitions

3. **Audio** — Place OGG files in `assets/audio/`
   - SFX: `sfx/cut_good.ogg`, `sfx/coin_collect.ogg`, etc.
   - Music: `music/menu.ogg`, `music/boss_battle.ogg`, etc.
   - AudioManager.play_sfx() and .play_music() reference these

### Adding New Game Data

Edit `resources/game_data/knives.json` and `resources/game_data/potatoes.json`:

```json
{
  "id": "damascus_steel",
  "name": "Damascus Steel",
  "base_damage": 1.3,
  "cost": 5000,
  "unlocked_at_xp": 1000
}
```

Then reference in `GameplayController._load_stage_potatoes()` or shop logic.

### Adding UI Elements

1. Create a new scene file (`.tscn`) in `scenes/`
2. Add a Control node and build your UI
3. Attach a script that extends `Control` or `Node2D`
4. Use signals to communicate with GameManager
5. Change scenes with `get_tree().change_scene_to_file()`

### Adding Achievements

In SaveDataManager:
```gdscript
GameManager.combo_changed.connect(func(combo):
	if combo >= 50:
		SaveDataManager.unlock_achievement("combo_master")
)
```

## Running the Game

### Development (Godot Editor)

```bash
# Install Godot 4.2+
# Open the godot/ folder as a project
# Press F5 to run
```

### Headless Smoke Tests

An auto-player drives a championship run — it watches the active minigame,
cuts at the centre, locks the peel in the band and bins rotten potatoes —
and two more drive the farm economy and the town stalls:

```bash
godot --headless --path godot res://tests/SmokeTest.tscn --quit-after 900
# prints "SMOKE OK — score=... lives=..." and exits 0 on success

godot --headless --path godot res://tests/FarmSmokeTest.tscn --quit-after 600
# plow/plant/water/harvest/sell, sections, sprinklers, fertilizer charges,
# drone+seeder and the schema-1 save migration — prints "FARM SMOKE OK"

godot --headless --path godot res://tests/TownSmokeTest.tscn --quit-after 600
# walks the plaza, buys/sells at every stall — prints "TOWN SMOKE OK"

godot --headless --path godot res://tests/FpsSmokeTest.tscn --quit-after 300
# boots a solo SPUD BLASTER match, shoots a target dummy, scores a frag —
# prints "FPS SMOKE OK"
```

CI runs these on every PR touching `godot/` (see `.github/workflows/godot.yml`).

### Standalone Build

```bash
# Export as standalone executable
# Godot will package as single-file binary for Windows/Linux/Mac
# Result: `PotatoSlicer-v2.0.0.exe` (or equivalent)
```

## Current Status

- ✅ Game state management with signals (score, combo, FEVER, lives)
- ✅ All five minigames playable with real cursors and visuals
  (slice, peel gauge, shrinking speed-cut, two-tap julienne, rotten dodge)
- ✅ Procedurally drawn potatoes — idle bob, split-in-two and binned-drop
  animations, golden glow, rotten stink lines (no image assets required)
- ✅ Visual feedback: quality popups, stage banners, screen shake, fever
  overlay, heart lives, combo counter that grows with the streak
- ✅ Two polished game modes: Championship (6 stages, clear bonuses,
  life regen) and Endless (waves, rising bonuses and golden odds)
- ✅ Graphics styles: Classic, Pixel Art, Hyperreal — one post-processing
  pass in `StyleManager` restyles the whole game, cycle with [G] in Settings
- ✅ Game-over screen with name entry and leaderboard submission
- ✅ Save/load persistence (JSON: leaderboard, achievements, settings, unlocks)
- ✅ Data-driven balance: knives, potatoes, items and fields in
  `resources/game_data/*.json`
- ✅ Grid-based farm: three fields bought section by section, a plow that
  wears out (and costs more each replacement), placeable sprinklers,
  multi-charge fertilizer, drone/seeder automation, schema-1 save migration
- ✅ Town map: fountain plaza with the four market stalls and the
  championship kitchen, gates between farm and town
- ✅ SPUD BLASTER: 3D first-person deathmatch arena with LAN + internet
  (UPnP) multiplayer and a solo practice mode vs. bots
- ✅ Headless smoke tests (gameplay, farm, town, FPS arena) + CI workflow
- ⏳ Audio files (framework wired, OGG assets needed)
- ⏳ Boss fight minigame
- ⏳ Particles and richer juice (squash/stretch, trails)

## Next Steps

1. **Audio** — Drop OGG files into `assets/audio/` and implement playback in AudioManager
2. **Boss** — Add a Colossal Spud minigame with an HP bar (extend `MinigameBase`)
3. **Town content** — New buildings/activities belong on the town map (the
   boarded plaza lot in `TownBackground` is the placeholder)
4. **Polish** — Particles, squash-and-stretch, juice
5. **Expansion** — New potatoes/mechanics are one JSON entry + one `MinigameBase` subclass away

## Building for Distribution

Create release workflow:
1. Tag with version: `git tag v2.0.0`
2. Export from Godot as self-contained binary
3. Publish to GitHub Releases
4. Update version in `project.godot` for next dev cycle

The framework is designed to stay expandable — add features by implementing signal handlers, extending the minigame base class, and populating the assets folder.
