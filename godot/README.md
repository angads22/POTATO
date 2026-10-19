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
│   ├── farm/                  # Spudling Acres economy core (FarmEconomy, FarmClock, FarmView, FarmMigration)
│   ├── world/                 # Farm + town scenes (controllers, fields, critters, HUD, Farm Book)
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
  - The farm save (schema 4, debounced writes, a 30 s heartbeat that settles the farm from any
    scene) and the migration of older farm saves
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

### Spudling Acres (the farm) and the town

**What it is.** Spudling Acres is a cozy farm you check in on, not a farm you
have to babysit. You own a few fenced fields (six, plus a Greenhouse late on),
each growing one crop at a time. Little potato helpers, the **Spudlings**,
pick and replant while you're away, and when you come back a note (from Pip,
once you've hired your first Spudling) tells you what happened. Nothing rots,
wilts or expires: a ripe crop waits for you forever. The numbers keep going
up; the game is choosing *how* they go up.

**A visit in three clicks** (30 to 90 seconds, sound on or off, trackpad
friendly):

1. Open **[4] Potato Farm** from the main menu. Its row already says how many
   fields are ripe and how many coins are waiting, and Enter reopens whatever
   you played last.
2. **Pip's note** sums up your absence. Click **Collect** (or press Enter /
   Space): every ripe field is harvested and replanted at once.
3. If you were away a while, a **butterfly** arrives a few seconds later:
   click it (or press G) for a small gift. Then make one decision (press Q for
   your pinned goal, change a field's plan, or buy something in the **Farm
   Book**) and close the game. It saves as you go and again when the window
   loses focus.

**Controls**

| Action | Keyboard | Mouse / trackpad |
|---|---|---|
| Walk | WASD / arrows | Not needed: everything is clickable from anywhere |
| Tend a field (harvest + replant, or plant) | E / Space while standing in it | Click a ripe or empty field |
| Field card (plan, Spudling, sprinkler, replant) | F in the field, 1–7 from anywhere, or E at its hut | Click a growing field, its sign or its hut |
| Tend every field (needs the Copper Hoe) | T | Tend All button |
| Collect, on Pip's note | Enter / Space | Collect button |
| Farm Book | B, then ←/→ or 1–6 for tabs, ↑/↓ rows, Enter buys, P pins | Book button, the farmhouse, or the town's seed stall and tool shed |
| Buy the Next Goal | Q | Click the goal card at the top |
| Catch a butterfly | G, or walk into it | Click it, or its "Butterfly!" chip |
| Zoom (whole farm ↔ close-up) | Z | Mouse wheel, two-finger scroll, pinch, or the zoom button |
| Sound on / off | M (also on the main menu) | Sound button |
| Close / leave | Esc closes whatever is open; Esc twice goes back to the menu | ✕ on a panel, the menu button |

Every button is at least 44 px. Nothing needs dragging, double-clicking,
right-clicking or hovering, and every sound has an on-screen twin (a ring on
ripe fields, an orange popup when you are short of coins), so the farm plays
fine muted in a classroom.

**Getting more out of the farm.** No choice below is right for everyone;
that's the point.

- **Plant for your schedule.** Short crops earn more per minute but need you
  there to replant them. Long crops earn more per harvest and fill a long
  absence. The field card shows the clock time each crop would be ready, so
  pick the one that ripens just before you'll be back: before the bell, before
  dinner, before bed. Planting costs seed; Russet is always free.
- **Spudlings or your own hands.** A hut puts a Spudling on that field. They
  start shortly after you stop playing and work for as long as your farmhouse
  allows (a bigger farmhouse means a longer shift). The crop you left in the
  ground is still yours: they give you a little while to come back for it,
  then pick it at full value. On crops they plant themselves they keep a share
  as wages. Huts shine if you're away for long stretches; long crops shine if
  you come back on time.
- **Read the Farm Book.** Every purchase shows what it adds while you're here,
  what it adds while you're away, and how long it takes to pay for itself *for
  the way you play* (the farm keeps a log of your recent visits). It never
  picks for you. **Pin** what you're saving for and Q buys it once you can
  afford it.
- **Grow toward the next Catalog page.** New crops unlock in the **Seed
  Catalog** when you've shipped enough of the earlier ones. Coins can't buy a
  page, so sometimes the best move is growing what the next page asks for.
- **Place sprinklers.** A sprinkler sits on the fence between two fields and
  speeds up both. It helps most where faster growth lets a crop fit a gap it
  used to miss. Moving one is free. The Greenhouse grows faster still.
- **More land or deeper land.** The next field, or **Soil** (a little more
  from every crop, forever), or a **Prize Strain** (a lot more from the one
  crop you grow most; each tier hangs a ribbon on the farmhouse wall).
- **Today's Market Favorite.** One crop a day pays extra if you plant it that
  day, even if you harvest it tomorrow. The chip at the top shows today's and
  tomorrow's.

**The rest of the game helps.** The coin wallet is shared with the kitchen,
Concert and SPUD BLASTER. Once your farm is started, every run also brings a
**Farm Picnic** bonus worth a few minutes of your farm's output, Prize Strains
raise the kitchen's golden-potato odds, and the middle knives need Chef XP,
which comes from kitchen and Concert runs.

**The town** is through the farm's east gate: the knife stand, the
championship kitchen (E or a click starts a run), the **Concert Hall**
bandstand (the walk-up way into Concert mode), and two farm storefronts. The
seed stall opens the Farm Book's Catalog and the tool shed its Tools tab.

**Where it runs.** The farm is part of the desktop builds (Windows, macOS,
Linux). It does not run in a browser: on a Chromebook you can only play the
web edition, which is Concert mode.

#### For developers

- The economy is `scripts/farm/` (`FarmEconomy`, a pure static core with an
  injected clock, plus `FarmClock`, `FarmView` and `FarmMigration`); the
  scenes are `scripts/world/` (`FarmController`, `FarmHud`, `FarmBook`,
  `FarmField`, `FarmCritters`, `TownController` on a shared `WorldController`
  / `WorldHUD`). Save schema 4, migrations, the save/heartbeat plumbing and
  the rules for touching any of it are in the farm sections of
  [`../CLAUDE.md`](../CLAUDE.md).
- Every balance number lives in `resources/game_data/farm.json`. Tune it with
  the simulator, run from `godot/`:
  `godot --headless --path . -s tests/farm/farm_sim.gd -- --all`.
  [`tests/farm/BALANCE.md`](tests/farm/BALANCE.md) has the evidence behind the
  current values, and `FarmBalanceTest` is the CI gate.

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
bins rotten potatoes — and more drive the boss, Concert, the farm scene,
the town stalls and the FPS arena, and two more check the farm's balance and
save migration. On the headless server nothing is rendered or played, but the
beat clock still runs (3x fast in the kitchen tests). Give each farm, town and
migration run a fresh `user://` (for example `XDG_DATA_HOME=$(mktemp -d)`):

```bash
godot --headless --path godot res://tests/SmokeTest.tscn --quit-after 4000
# two stage clears + FEVER on the beat — prints "SMOKE OK — score=..."

godot --headless --path godot res://tests/BossSmokeTest.tscn --quit-after 2000
# strikes the Colossal Spud on beats 1 and 3 until it falls — "BOSS SMOKE OK"

godot --headless --path godot res://tests/ConcertSmokeTest.tscn --quit-after 6000
# chart determinism, then a whole song with chops, holds and bins — "CONCERT SMOKE OK"

godot --headless --path godot res://tests/FarmSmokeTest.tscn --quit-after 600
# drives Spudling Acres with synthetic keys and clicks plus time travel: Tend,
# Collect, Spudlings, the Catalog, sprinklers, butterflies, the Farm Book —
# prints "FARM SMOKE OK"

godot --headless --path godot res://tests/TownSmokeTest.tscn --quit-after 600
# the town stalls and storefronts on a frozen farm clock — prints "TOWN SMOKE OK"

godot --headless --path godot res://tests/FarmBalanceTest.tscn --quit-after 6000
# profile bots play the real farm economy for simulated weeks: milestones, feel,
# strategy diversity, invariants (about 1-2 min) — prints "FARM BALANCE OK"

godot --headless --path godot res://tests/FarmMigrationTest.tscn --quit-after 3000
# schema 1/2/3 -> 4 farm saves, refunds, slots, saving, heartbeat, Farm Picnic —
# prints "FARM MIGRATION OK"

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
- ✅ Data-driven balance: knives, potatoes, achievements and the whole farm
  economy (`farm.json`) in `resources/game_data/*.json`
- ✅ Spudling Acres: six fenced fields plus a Greenhouse, whole-field Tend and
  per-field plans, Spudlings that work while you're away (offline settle),
  Pip's note + Collect, the Seed Catalog, the Farm Book with per-schedule
  paybacks, fence sprinklers, Soil, Prize Strains, the Market Favorite and
  butterflies. Older farm saves migrate automatically (1→2→3→4 chain).
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
- ✅ Headless smoke tests (championship, boss, concert, farm, town, FPS), the
  farm balance gate and the farm save-migration test, all in CI

## Next Steps

1. **Town content** — New buildings/activities belong on the town map (the
   Concert Hall shows the pattern: geometry in `TownBackground`, an entry in
   `TownController`'s `stations` list, clickable and [E]-able)
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
