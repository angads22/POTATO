/*
 * ════════════════════════════════════════════════════════════════
 *   SLICE IT!  ·  The Potato Cutting Championship
 *   A full-scale C# console rhythm-action game.
 *
 *   Requirements : .NET 8.0 (or .NET 6.0+)
 *   Run with     : dotnet run   (from the PotatoSlicer/ folder)
 *   Controls     : SPACE = cut  ·  ESC = quit to menu
 *
 *   Source layout:
 *     Models/    — Knife, Potato, PowerUp, enums
 *     Data/      — GameData (knife/potato/stage tables)
 *     Core/      — Scoring, SaveData, Leaderboard
 *     UI/        — Render (drawing), Audio (sound)
 *     Minigames/ — one file per cut mechanic
 *     Game.*.cs  — the orchestrator (split by concern)
 * ════════════════════════════════════════════════════════════════
 */
namespace PotatoSlicer
{
    class Program
    {
        static void Main() => new Game().Run();
    }
}
