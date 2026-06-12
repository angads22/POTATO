# SLICE IT! · The Potato Cutting Championship

A visual rhythm-action game about knives, starch, and questionable life choices.
Press SPACE when the bar hits the centre to slice, dice, and julienne your way through
six stages, from the Training Kitchen to the World Championship. Earn coins, buy better
knives, chain combos, and chase FEVER mode.

> **New:** We've completely rebuilt the game in [Godot](https://godotengine.org) with full graphics and animations! The classic console version is still available in `PotatoSlicer/`.

## Features

- **Open-world potato farm (visual edition):** walk your chef potato around a
  scrolling homestead — plant seeds, draw water from the well, harvest crops
  (they keep growing in real time even while the game is closed), sell at the
  market, and buy knives that multiply your slicing score. Day-night cycle
  with fireflies included.
- **One economy:** slicing runs bank coins to the farm wallet
  (golden-potato coins + score/20), the farm grows and sells potatoes, and
  the knife stand feeds power back into the kitchen
- **Four game modes:** Championship (6-stage campaign), Endless (infinite, ever-faster,
  a boss every 5 stages), Time Attack (60 seconds), and a date-seeded Daily Challenge
  that plays the same for everyone on a given day
- **Five cut mechanics** — not every spud is a simple slice:
  - *Slice/Dice* — the classic sweeping bar, press SPACE at centre
  - *Peel* (Purple) — tap to start a rising fill, tap again to lock it
  - *Speed Cut* (Fingerling) — the sweet spot shrinks; commit fast
  - *Julienne* (King Edward) — land two quick taps, scored as the worse
  - *Rotten Potato* — a hazard: do **not** slice it, press **X** to bin it
- **Boss potato** — the Colossal Spud caps the Championship (and recurs in Endless) with a HP bar
- **Power-ups** — buy Sharpening Stone, Slow-Mo, Extra Life, and Combo Shield in the shop,
  then activate them before a potato
- **Stage orders** — each stage sets a bonus objective (clean plate, precision, score, combo)
- **Knife shop** — earn coins and upgrade from Butter Knife to Damascus Steel; the two
  pro knives also unlock permanently once you bank enough Chef XP across runs
- **Combo and FEVER multipliers**, plus a +25% quick-cut bonus for fast decisions
- **3 lives per run** — every MISS costs one, and losing them all ends the run
- **Rare golden potato** (~7% chance) worth 500 base points and bonus coins
- **Top-10 leaderboard** and **achievements**, both persisted between sessions
- **Sound effects** (toggle in the menu)
- **Auto-updates** — the standalone app checks the latest GitHub release on
  launch and updates itself, then restarts (skip with `--no-update`);
  there's also a manual "Check for Updates" in the menu

## Play Now

### Visual Edition (Godot) — in development

A fully featured visual remake in Godot Engine with graphics, animations, and a framework built for expansion.

```sh
# Install Godot 4.2+
# Open godot/ as a project and press F5 to run
```

Binaries coming soon. See [`godot/README.md`](godot/README.md) for development and expansion guide.

### Classic Console Edition

Download the standalone build for your platform from the
[latest release](https://github.com/angads22/POTATO/releases/latest):

- `PotatoSlicer-win-x64.exe` — Windows: download and double-click
- `PotatoSlicer-linux-x64` — Linux: `chmod +x` then run

Updating later is built in: choose **Check for Updates** in the main menu.

Or run from source:
```sh
# Requires .NET 8.0 SDK
cd PotatoSlicer
dotnet run
```

## Project Versions

### Console Edition (`PotatoSlicer/`)
- C# .NET 8.0
- Console-based UI with ASCII art
- Fully playable with auto-update capability
- Version in `PotatoSlicer/Core/Updater.cs`

### Visual Edition (`godot/`)
- Godot 4.2+ with GDScript
- Modular architecture for expandability
- Framework ready for sprites, animations, and features
- See [`godot/README.md`](godot/README.md) for development guide

## Cutting a Release (Console Edition)

1. Bump the `VERSION` constant in `PotatoSlicer/Core/Updater.cs` and `<Version>` in the csproj.
2. Tag the commit to match and push: `git tag v1.2.0 && git push origin v1.2.0`.
3. The Release workflow builds the binaries and publishes the GitHub Release
   that the in-game updater looks for.

## Controls

- `SPACE` — cut / lock / strike / advance menus
- `X` — bin a rotten potato (do **not** press `SPACE` on it!)
- `1`–`4` — activate a power-up at the pre-cut prompt
- In the shop: `1`–`7` knives, `Q`/`W`/`E`/`R` power-ups, `SPACE` to continue
- `ESC` — quit to menu
- On the farm (visual edition): `WASD`/arrows to walk, `E` to interact,
  `1`–`7` in shops, `A` to sell everything at the market

## Project Layout

```
POTATO/
├── PotatoSlicer/          # Console version (C# .NET 8.0)
│   ├── Models/            # Knife, Potato, enums
│   ├── Data/              # GameData tables
│   ├── Core/              # Scoring, SaveData, Leaderboard, Updater
│   ├── UI/                # Render helpers, Audio
│   ├── Minigames/         # Cut mechanics
│   ├── Modes/             # Game mode loops
│   ├── Progression/       # Recipes, power-ups, boss
│   └── Game.cs            # Orchestrator
├── godot/                 # Visual version (Godot 4.2+ / GDScript)
│   ├── scripts/           # Core managers, gameplay, minigames, UI
│   ├── scenes/            # Godot scenes (menu, gameplay, shop)
│   ├── assets/            # Sprites, animations, audio (to be added)
│   └── resources/         # Game data, saves
└── builds/                # Standalone binaries (console version)
