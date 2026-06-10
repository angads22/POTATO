# SLICE IT! · The Potato Cutting Championship

A C# console rhythm-action game about knives, starch, and questionable life choices.
A bar sweeps across the screen — press SPACE when it hits the centre to slice, dice,
and julienne your way through six stages, from the Training Kitchen to the World
Championship. Earn coins, buy better knives, chain combos, and chase FEVER mode.

## Features

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

## Requirements

- [.NET 8.0 SDK](https://dotnet.microsoft.com/download/dotnet/8.0) (or .NET 6.0+)

## Run

```sh
cd PotatoSlicer
dotnet run
```

## Controls

- `SPACE` — cut / lock / strike / advance menus
- `X` — bin a rotten potato (do **not** press `SPACE` on it!)
- `1`–`4` — activate a power-up at the pre-cut prompt
- In the shop: `1`–`7` knives, `Q`/`W`/`E`/`R` power-ups, `SPACE` to continue
- `ESC` — quit to menu

## Source layout

The game is split by concern under `PotatoSlicer/`:

- `Models/` — `Knife`, `Potato`, enums
- `Data/` — `GameData` (knife / potato / stage tables)
- `Core/` — `Scoring`, `SaveData`, `Leaderboard`
- `UI/` — `Render` (drawing helpers), `Audio` (sound)
- `Minigames/` — the five cut mechanics
- `Modes/` — mode select and the per-mode run loops
- `Progression/` — recipe orders, power-ups, meta-unlocks, boss fight
- `Game.cs` — the orchestrator that ties it together
