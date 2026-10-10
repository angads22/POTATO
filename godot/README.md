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

- **AudioManager** — every sound in the game, plus the beat clock
  - `play_sfx(name)`: synthesized SFX on a voice pool (`SFX` bus)
  - `play_music(track)` / `play_song({style, bpm, seed})`: procedurally
    composed songs, rendered on a worker thread, cached, crossfaded
  - four synced stems per song (drums / harmony / lead / fever) with
    `set_layer()` fades — FEVER and Concert's arrangement use them
  - `music_time()` / `music_beat()`: the clock gameplay locks to (works with
    the sound off and on the headless CI server, too)
  - Master / Music / SFX volumes, a safety limiter, a little room reverb

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

### Audio: everything is synthesized (`scripts/audio/`)

There are no audio files. `Synth.gd` is a small software synthesizer
(polyBLEP saw/square, triangle, 2-operator FM, noise, ADSR, pitch and filter
envelopes, a drum kit, a circular echo). `SfxLibrary.gd` builds every sound
effect from it at boot — chops are a noise transient plus a woody body, game
over is a sad trombone — each loudness-normalized. `SongComposer.gd` writes
music: a style (key, mode, progressions, drum/bass/comping patterns,
instruments) plus a seed gives an 8-bar song whose melody follows
contour-shaped 2-bar motifs (A A' B A'') snapped onto the chords. The same
seed always composes the same song.

| Where | Style | Tempo |
|-------|-------|-------|
| Menu | kitchen funk | 104 |
| Championship stages 1–6 | lo-fi → jazz → funk → disco → game show → epic | 132, rising ~8% a stage |
| Boss | harmonic-minor brass | the final stage's tempo |
| Farm / town | country uke + whistle / oom-pah accordion | 92 / 120 |
| SPUD BLASTER / lobbies | driving minor / four-on-the-floor | 140 / 118 |

### Beat-locked gameplay

Kitchen songs are "half-time": the snare lands on beat 3 of every bar, and
that is exactly where the slice cursor crosses the centre. Potatoes drop in
to land on bar lines, golden spuds sweep double-time, the speed-cut zone
shrinks one beat at a time, julienne is "chop on 3, chop on 1", the peel
gauge fills over one bar, and the boss strikes on the kick and the snare.
Minigame cursors are pure functions of `AudioManager.music_beat()` relative
to the minigame's `beat_origin` — never accumulated frame deltas.

### Game Modes

- **Championship** — 6-stage campaign with final boss; stage-clear bonuses
  and a life restored every other stage
- **Endless** — Infinite waves with escalating wave bonuses and golden-potato
  odds that climb the deeper you survive
- **Concert** (`scripts/concert/`) — a note-highway rhythm mode. `ConcertChart`
  turns a seed into a song (style, tempo, title) and a chart (intro on the
  drums, then the melody; chop / hold / rotten / golden notes; Easy / Normal /
  Hard), with a Daily Song seeded by the UTC date and a fixed setlist.
  `ConcertController` runs song select with live previews, the conveyor,
  judging (±45/90/135 ms), HYPE, a x1–x4 multiplier and FEVER. The web
  edition (`../web/`) ports `ConcertChart` + `SongComposer.compose()` 1:1, so
  a seed is the same song in the browser.

### The Overworld (Farm + Town)

Two walkable maps share a `WorldController` base (movement, blockers, camera,
day-night cycle, prompts, shop overlays, economy actions) and a `WorldHUD`:

- **The farm** (`FarmController`, `scenes/Farm/FarmScene.tscn`) — the whole
  pasture is one free-form plowable grid (no fenced fields). `FarmTile`s are
  sparse: one is created on demand only when you plow a cell or drop a
  sprinkler there. Plow the grass (the plow wears out after 10 uses;
  replacements cost more each time), plant, water (or place a sprinkler to
  auto-water the tiles around it — now a real spatial puzzle), fertilize
  (multi-charge), harvest — the soil stays plowed. A plowed plot you no longer
  want can be **covered back over** with `[C]` (9 free covers, then a small
  coin fee); the plow isn't refunded and there's no undo, so the cell must be
  plowed again to farm it. Progression runs on the
  **Research Shed** — a node-based skill-tree map (arrow keys navigate, [E]
  buys the highlighted node, [TAB] swaps the PROGRESSION / AUTOMATION tracks)
  where coins + research points buy logistics/tools/crops/growth/science/water/
  soil/championship upgrades plus cross-branch capstones
  (`resources/game_data/research.json`, ~80+ nodes, incl. research-gated crops,
  science nodes that lower seed costs / earn research per harvest, a water line
  that grows the watering can and a soil line that speeds growth, and
  championship nodes that earn research from runs / raise golden odds). Upgrades
  come in many small tiers so the tree stretches out rather than handing over
  big jumps. The harvest ships from the **market truck** by the top hedge (load it,
  send it off, coins + research points return after a wall-clock delay). The
  **automation** track (drip irrigation, harvester/seeder drones, auto-dispatch,
  standing orders) is the long, expensive apex of the tree, and its purchase
  orders aren't free money: the **Seed Co-op** and **Supply Depot** — two yard
  buildings that stay shuttered until the matching standing-order research is
  bought — let the player schedule *which* crops/fertilizer the farm restocks
  and how much to keep on hand, and every order pays a delivery premium over the
  hands-on shop price. The farmhouse, well and pond live here too.
- **The town** (`TownController`, `scenes/Town/TownScene.tscn`) — the seed
  shop, knife stand and tool shed around a fountain plaza, plus the
  championship kitchen (walk in to start a run). Selling moved to the farm's
  truck, so there's no market stall here. Future non-farming content belongs
  here (there's a boarded "coming soon" lot on the plaza).
- Gates on the farm's east hedge and the town's west hedge travel between the
  two; the time of day carries across.

Farm state lives in `SaveDataManager.farm` (schema 3: sparse `tiles` dict
keyed `"col:row"`, `research`/`research_points`, the `truck`,
`plow_uses`/`plows_bought`, `cover_freebies`, `sprinkler_stock`, fertilizer
charges in `items`).
Schema-1 (`plots` array) and schema-2 (`field:row:col` + `sections_owned`)
saves are migrated automatically on load through a 1→2→3 chain.

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
2. In `start_minigame(potato, origin_beat)` call `super` and set up a sweep
   with `set_sweep(beats_per_pass)` if you use a cursor
3. Drive everything from `beats()` / `sweep_cursor()`; express timeouts in beats
4. Implement `_on_primary_input()` and `_on_secondary_input()` with cut logic
5. Set `cut_result.quality` (PERFECT/GREAT/GOOD/MISS/FAIL) and
   `cut_result.score_multiplier` (0.0-1.5), then call `end_minigame()`
6. Reference it in `GameplayController._create_minigame()`

Example:
```gdscript
extends MinigameBase

var cursor := 0.0

func start_minigame(potato: Dictionary, origin_beat: float = -1.0e9):
	super.start_minigame(potato, origin_beat)
	set_sweep(4.0)  # centre crossings on beat 3

func _process(_delta):
	if is_active:
		cursor = sweep_cursor()
		if beats() > 12.0:
			cut_result.quality = "MISS"
			end_minigame()
		queue_redraw()

func _on_primary_input():
	var q := judge(absf(sweep_cursor() - 0.5), 0.02, 0.05, 0.11)
	cut_result.quality = q
	cut_result.score_multiplier = multiplier_for(q)
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

3. **Audio** — there are no audio files: add a sound as a recipe in
   `SfxLibrary.build()` (plus a `LOUDNESS` target) and play it with
   `AudioManager.play_sfx("name")`. A new musical style is one entry in
   `SongComposer.STYLES`; a new named track is one entry in
   `AudioManager.TRACKS`.

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
cuts when the beat-locked cursor is centred, locks the peel in the band and
bins rotten potatoes — and more drive the boss, Concert, the farm economy,
the town stalls and the FPS arena. On the headless server nothing is
rendered or played, but the beat clock still runs (3x fast in these tests):

```bash
godot --headless --path godot res://tests/SmokeTest.tscn --quit-after 4000
# two stage clears + FEVER on the beat — prints "SMOKE OK — score=..."

godot --headless --path godot res://tests/BossSmokeTest.tscn --quit-after 2000
# strikes the Colossal Spud on beats 1 and 3 until it falls — "BOSS SMOKE OK"

godot --headless --path godot res://tests/ConcertSmokeTest.tscn --quit-after 6000
# chart determinism, then a whole song with chops, holds and bins — "CONCERT SMOKE OK"

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
# release.yml exports Windows / Linux / macOS builds on every v* tag
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
- ✅ Three independent save files — create and switch between slots from Settings
  ([1]/[2]/[3]); each slot is its own folder under `user://potato_game/slotN/`,
  and a pre-slots save migrates into slot 1 automatically
- ✅ Data-driven balance: knives, potatoes, items and the research tree in
  `resources/game_data/*.json`
- ✅ Open-grid farm: the whole pasture is free-form plowable (sparse,
  on-demand tiles), a plow that wears out (and costs more each replacement),
  placeable sprinklers, multi-charge fertilizer, and a Research Shed
  (node-based skill-tree map; coins + research points →
  logistics/tools/crops/growth/championship + cross-branch capstones,
  research-gated crops, drone/seeder automation) feeding a market truck that ships the
  harvest. Schema-1/2 saves migrate automatically (1→2→3 chain).
- ✅ Town map: fountain plaza with the seed/knife/tool stalls and the
  championship kitchen, gates between farm and town
- ✅ SPUD BLASTER: 3D first-person deathmatch arena with LAN + internet
  (UPnP) multiplayer and a solo practice mode vs. bots
- ✅ Procedural audio: synthesized SFX for every action and a composed
  soundtrack for every scene (no audio files), with volumes and calibration
- ✅ Beat-locked kitchen: potatoes land on bar lines, cuts land on the snare,
  tempo climbs per stage, FEVER adds a layer to the song
- ✅ Concert rhythm mode with seeded songs, a Daily Song and a web edition
- ✅ Colossal Spud boss fight, particles, squash-and-stretch, screen shake
- ✅ Pause menu, graded results screen, personal bests, F11 fullscreen
- ✅ Headless smoke tests (championship, boss, concert, farm, town, FPS) + CI

## Next Steps

1. **Town content** — New buildings/activities belong on the town map (the
   boarded plaza lot in `TownBackground` is the placeholder) — a Concert
   stage there would tie the new mode into the overworld
2. **Concert** — an online Daily Song leaderboard (the seed is already shared
   with the web edition), longer song forms (verse/chorus variations)
3. **Farm ambience** — day/night variations of the farm theme, rain
4. **Expansion** — New potatoes/mechanics are one JSON entry + one `MinigameBase` subclass away

## Building for Distribution

Create release workflow:
1. Tag with version: `git tag v2.0.0`
2. Export from Godot as self-contained binary
3. Publish to GitHub Releases
4. Update version in `project.godot` for next dev cycle

The framework is designed to stay expandable — add features by implementing signal handlers, extending the minigame base class, and populating the assets folder.
