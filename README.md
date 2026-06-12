# SLICE IT! · The Potato Cutting Championship

[![Latest release](https://img.shields.io/github/v/release/angads22/POTATO?label=latest%20release&color=gold)](https://github.com/angads22/POTATO/releases/latest)
[![All releases](https://img.shields.io/badge/releases-all%20versions-8B5A2B)](https://github.com/angads22/POTATO/releases)

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
- **Farm expansion:** the field starts half-tilled — clear and till new plots
  one at a time, with prices that climb as your farm grows
- **Tools & auto-farming:** the tool shed sells permanent gear — a Sprinkler
  Network that auto-waters, a Spud-Bot that harvests ready crops, and an
  Auto-Seeder that replants from your seed pouch — chain all three for a
  self-running farm while you tend the field
- **Growth enhancers:** consumable Compost, Super Grow, and Miracle Mulch —
  stand by a growing crop and press `F` to work one into the soil for faster
  growth (and bonus yield from the good stuff)
- **LAN multiplayer:** host a game on your local network and a friend joins
  by entering your IP — both players cut the same potato sequence in parallel,
  with live score and lives shown for your opponent in the HUD
- **Global leaderboard:** every run submits your score to a shared online
  leaderboard (requires a free Supabase project — see `OnlineLeaderboard.gd`)
- **Two polished game modes:** Championship (6-stage campaign with stage-clear
  bonuses and a life back every other stage) and Endless (infinite waves with
  rising wave bonuses and golden-potato odds that climb as you survive)
- **Three graphics styles (visual edition):** switch the whole game's look in
  Settings with `[G]` — *Classic* (the hand-drawn original), *Pixel Art*
  (chunky retro mosaic with scanlines), or *Hyperreal* (cinematic colour
  grade with bloom, vignette, and film grain)
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
- **Top-10 local leaderboard** and **global online leaderboard**, both surfaced in-game
- **Sound effects** (toggle in the menu)
- **Auto-updates, both editions** — the visual edition checks the latest
  GitHub release on launch and has a **Check for Updates** screen in the
  menu (`[7]`) that downloads the new build and restarts itself; the console
  edition auto-updates on launch as before (skip with `--no-update`)

## Play Now

### Visual Edition (Godot) — the full game

Download from the [latest release](https://github.com/angads22/POTATO/releases/latest), unzip, and play:

- [`SliceIt-Visual-win-x64.zip`](https://github.com/angads22/POTATO/releases/latest/download/SliceIt-Visual-win-x64.zip) — Windows: unzip and double-click `SliceIt.exe`
- [`SliceIt-Visual-linux-x64.zip`](https://github.com/angads22/POTATO/releases/latest/download/SliceIt-Visual-linux-x64.zip) — Linux: unzip, `chmod +x SliceIt.x86_64`, run
- [`SliceIt-Visual-mac.zip`](https://github.com/angads22/POTATO/releases/latest/download/SliceIt-Visual-mac.zip) — macOS: unzip and open `SliceIt.app`
  > **macOS note:** the app is unsigned. Right-click → Open the first time to bypass Gatekeeper,
  > or run `xattr -cr SliceIt.app` in Terminal.

Or run from source: install Godot 4.2+, open `godot/` as a project, press F5.
See [`godot/README.md`](godot/README.md) for the development and expansion guide.

### Classic Console Edition

**Newest release: [v2.3.0](https://github.com/angads22/POTATO/releases/latest)** — download the standalone build for your platform:

- [`PotatoSlicer-win-x64.exe`](https://github.com/angads22/POTATO/releases/latest/download/PotatoSlicer-win-x64.exe) — Windows: download and double-click
- [`PotatoSlicer-linux-x64`](https://github.com/angads22/POTATO/releases/latest/download/PotatoSlicer-linux-x64) — Linux: `chmod +x` then run

Every past version is archived on the [releases page](https://github.com/angads22/POTATO/releases).
The game checks the latest release on launch and **updates itself automatically**
(skip with `--no-update`); there's also a manual **Check for Updates** in the menu.

Or run from source:
```sh
# Requires .NET 8.0 SDK
cd PotatoSlicer
dotnet run
```

## Setting Up the Global Leaderboard

The online leaderboard is opt-in and free to self-host on [Supabase](https://supabase.com):

1. Create a free Supabase project and run this SQL in the editor:
   ```sql
   create table sliceit_scores (
     id         bigserial primary key,
     name       text not null,
     score      integer not null,
     mode       text not null,
     knife      text,
     created_at timestamptz default now()
   );
   alter table sliceit_scores enable row level security;
   create policy "anyone can insert" on sliceit_scores for insert to anon with check (true);
   create policy "anyone can read"   on sliceit_scores for select to anon using (true);
   ```
2. Copy your **Project URL** and **anon public key** from Settings → API.
3. Paste them into `SUPABASE_URL` and `SUPABASE_KEY` in `godot/scripts/online/OnlineLeaderboard.gd`.

The game works fully without this — scores stay local when the constants are left as placeholders.

## LAN Multiplayer

From the main menu choose **[4] Multiplayer**:

1. One player picks **Host** — their LAN IP is shown on screen.
2. The other picks **Join** and types that IP.
3. Both are dropped into a Championship run with the same potato sequence.
   Your score and your opponent's appear side-by-side in the HUD.

Works over any shared local network (Wi-Fi or wired LAN, same subnet).
No port-forwarding needed for play within a single network.

## Project Versions

### Console Edition (`PotatoSlicer/`)
- C# .NET 8.0
- Console-based UI with ASCII art
- Fully playable with auto-update capability
- Version in `PotatoSlicer/Core/Updater.cs`

### Visual Edition (`godot/`)
- Godot 4.2+ with GDScript
- Modular architecture for expandability
- Exports for Windows, Linux, and macOS
- See [`godot/README.md`](godot/README.md) for development guide

## Release History

Every iteration is downloadable from the [releases page](https://github.com/angads22/POTATO/releases):

| Version | What changed |
|---------|--------------|
| [v2.3.0](https://github.com/angads22/POTATO/releases/tag/v2.3.0) **(newest)** | In-game updater for the visual edition — check, download, and restart from the menu |
| [v2.2.0](https://github.com/angads22/POTATO/releases/tag/v2.2.0) | macOS build, LAN multiplayer, global leaderboard, 3 graphics styles, streamlined modes, farm expansion + auto-farming tools + growth enhancers |
| [v2.1.0](https://github.com/angads22/POTATO/releases/tag/v2.1.0) | Visual edition ships as a standalone app (kitchen, open-world farm, day-night cycle) |
| [v1.1.0](https://github.com/angads22/POTATO/releases/tag/v1.1.0) | Standalone single-file binaries, auto-update on launch, in-game update checker |
| [v1.0.2](https://github.com/angads22/POTATO/releases/tag/v1.0.2) | Overhaul: five cut mechanics, four modes, boss fight, shop, power-ups, stage orders |
| [v1.0.1](https://github.com/angads22/POTATO/releases/tag/v1.0.1) | Lives system, golden potato, high score, quick-cut bonus, sound effects |
| [v1.0.0](https://github.com/angads22/POTATO/releases/tag/v1.0.0) | Initial release |

## Cutting a Release

1. Bump `VERSION` in `PotatoSlicer/Core/Updater.cs`, `<Version>` in the csproj,
   **and** `config/version` in `godot/project.godot` — both in-game updaters compare
   against the release tag, so all three must match it.
2. Tag the commit and push: `git tag v2.4.0 && git push origin v2.4.0`.
3. The Release workflow builds console binaries and exports all three Godot builds
   (Win/Linux/macOS), then publishes the GitHub Release.

## Controls

- `SPACE` — cut / lock / strike / advance menus
- `X` — bin a rotten potato (do **not** press `SPACE` on it!)
- `1`–`4` — activate a power-up at the pre-cut prompt
- In the shop: `1`–`7` knives, `Q`/`W`/`E`/`R` power-ups, `SPACE` to continue
- `ESC` — quit to menu
- On the farm (visual edition): `WASD`/arrows to walk, `E` to interact,
  `F` to apply a growth enhancer to the nearest crop,
  `1`–`7` in shops, `A` to sell everything at the market
- In the multiplayer lobby: `1` Host, `2` Join (type IP then `ENTER`), `ESC` Back

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
│   ├── scripts/
│   │   ├── core/          # GameManager, SaveDataManager, AudioManager
│   │   ├── gameplay/      # GameplayController, PotatoVisual, KnifeVisual
│   │   ├── minigames/     # Slice, Peel, SpeedCut, Julienne, Dodge
│   │   ├── multiplayer/   # MultiplayerManager (ENet LAN), LobbyController
│   │   ├── online/        # OnlineLeaderboard (Supabase REST)
│   │   ├── ui/            # MainMenu, GameHUD, GameOver
│   │   ├── utils/         # GameData, Fx helpers
│   │   ├── visuals/       # KitchenBackground, RingFx
│   │   └── world/         # FarmController, FarmBackground, FarmerVisual
│   ├── scenes/            # Godot scenes (menu, gameplay, farm, lobby)
│   ├── assets/            # Sprites, animations, audio (to be added)
│   └── resources/         # Game data, saves
└── builds/                # Standalone binaries (console version)
```
