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

- **Championship** — 6-stage campaign with final boss
- **Endless** — Infinite potatoes, boss every 5 stages
- **Time Attack** — Score as much as possible in 60 seconds
- **Daily Challenge** — Seeded, same for everyone on the same day

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

### Standalone Build

```bash
# Export as standalone executable
# Godot will package as single-file binary for Windows/Linux/Mac
# Result: `PotatoSlicer-v2.0.0.exe` (or equivalent)
```

## Framework Features Ready to Implement

- ✅ Game state management with signals
- ✅ Modular minigame system
- ✅ Save/load persistence
- ✅ Audio framework
- ✅ Menu navigation
- ⏳ Sprite and animation system (assets needed)
- ⏳ Visual feedback (particles, screen shake, popups)
- ⏳ Leaderboard UI display
- ⏳ Shop UI and knife/power-up selection
- ⏳ Boss fight minigame
- ⏳ Combo/fever visual effects

## Next Steps

1. **Assets** — Create or source sprites for potatoes, knives, UI
2. **Scenes** — Build out the visual scenes (menu, gameplay, shop) with the sprite assets
3. **Animations** — Add cut animations and transitions
4. **Audio** — Add music and sound effects
5. **Polish** — Screen shake, particles, camera effects
6. **Expansion** — New modes, potatoes, knives, mechanics

## Building for Distribution

Create release workflow:
1. Tag with version: `git tag v2.0.0`
2. Export from Godot as self-contained binary
3. Publish to GitHub Releases
4. Update version in `project.godot` for next dev cycle

The framework is designed to stay expandable — add features by implementing signal handlers, extending the minigame base class, and populating the assets folder.
