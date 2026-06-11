# SLICE IT! · The Potato Cutting Championship

A C# console rhythm-action game about knives, starch, and questionable life choices.
A bar sweeps across the screen — press SPACE when it hits the centre to slice, dice,
and julienne your way through six stages, from the Training Kitchen to the World
Championship. Earn coins, buy better knives, chain combos, and chase FEVER mode.

## Features

- 6 stages of increasing speed, 7 potato varieties (each with real potato facts)
- Knife shop: earn coins per stage and upgrade from Butter Knife to Damascus Steel
- Combo and FEVER multipliers, plus a +25% quick-cut bonus for fast decisions
- 3 lives per run — every MISS costs one, and losing them all ends the run
- Rare golden potato (~7% chance) worth 500 base points and bonus coins
- Persistent high score, shown on the main menu with your best rank
- Sound effects (toggle in the menu)
- Auto-updates: the standalone app checks the latest GitHub release on
  launch and updates itself, then restarts (skip with `--no-update`);
  there's also a manual "Check for Updates" in the menu

## Download (no .NET required)

Grab the standalone build for your platform from the
[latest release](https://github.com/angads22/POTATO/releases/latest):

- `PotatoSlicer-win-x64.exe` — Windows: download and double-click
- `PotatoSlicer-linux-x64` — Linux: `chmod +x` then run

Updating later is built in: choose **Check for Updates** in the main menu.

## Run from source

Requires the [.NET 8.0 SDK](https://dotnet.microsoft.com/download/dotnet/8.0).

```sh
cd PotatoSlicer
dotnet run
```

## Cutting a release

1. Bump the `VERSION` constant in `PotatoSlicer/Program.cs` and `<Version>` in the csproj.
2. Tag the commit to match and push: `git tag v1.2.0 && git push origin v1.2.0`.
3. The Release workflow builds the binaries and publishes the GitHub Release
   that the in-game updater looks for.

## Controls

- `SPACE` — cut
- `ESC` — quit to menu
