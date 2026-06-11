/*
 * GameData — all static game-content tables in one place. Pulled into Game with
 * `using static PotatoSlicer.GameData;` so the stage arrays (SN/ST/SM/SP) read
 * unqualified exactly as they did when they lived on the Game class.
 */
using System;

namespace PotatoSlicer
{
    static class GameData
    {
        // ── Stage definitions ─────────────────────────────────────
        public static readonly string[] SN = {
            "Training Kitchen",   "Dinner Party",        "Street Food Stall",
            "Restaurant Kitchen", "TV Competition",      "World Championship"
        };
        public static readonly string[] ST = {
            "\"Let's see if you can hold a knife.\"",
            "\"The Hendersons arrive in 20 minutes.\"",
            "\"Fries don't cut themselves.\"",
            "\"Table 7 ordered 12 minutes ago.\"",
            "\"The cameras are live. Don't blink.\"",
            "\"THE. WORLD. IS. WATCHING.\""
        };
        // Bar speed multiplier per stage (applied to knife Cps)
        public static readonly double[] SM = { 1.00, 1.15, 1.30, 1.50, 1.70, 2.00 };
        // Potato ID pools per stage (random draw without weights)
        //   IDs: 0 Russet · 1 Yukon · 2 Sweet · 3 Purple · 4 Fingerling
        //        5 King Edward · 6 Golden (bonus only) · 7 Rotten (hazard)
        public static readonly int[][] SP = {
            new int[]{ 0, 0, 0, 0 },
            new int[]{ 0, 0, 1, 1 },
            new int[]{ 0, 1, 2, 2, 7 },
            new int[]{ 1, 2, 3, 3, 7 },
            new int[]{ 1, 3, 4, 4, 5, 7 },
            new int[]{ 0, 1, 2, 3, 4, 5, 7 }
        };

        // ── Knives ────────────────────────────────────────────────
        //            name            desc                                       cps  ph  gh  gd  price  colour
        public static Knife[] BuildKnives() => new Knife[] {
            new Knife("Butter Knife",   "Not food-safe. You're brave.",           25,  5,  9, 13,   0,  ConsoleColor.Gray),
            new Knife("Paring Knife",   "Small and honest.",                      35,  5,  9, 13,   0,  ConsoleColor.White),
            new Knife("Chef's Knife",   "The workhorse of every kitchen.",        45,  6, 10, 14,   0,  ConsoleColor.Yellow),
            new Knife("Santoku",        "Japanese geometry. Wider sweet spot.",   55,  8, 12, 16,  80,  ConsoleColor.Cyan),
            new Knife("Cleaver",        "Overkill. Profoundly satisfying.",       38,  9, 12, 15, 100,  ConsoleColor.Red),
            new Knife("Gyuto",          "Pro-grade Japanese knife. Fast.",        70,  7, 11, 15, 200,  ConsoleColor.Magenta),
            new Knife("Damascus Steel", "300 folded layers. Bar is a blur.",      90,  9, 13, 17, 350,  ConsoleColor.DarkYellow),
        };

        // ── Potatoes ──────────────────────────────────────────────
        public static Potato[] BuildPotatoes() => new Potato[] {

          // ── 0: Russet ─────────────────────────────────────────────────────────
          new Potato("Russet Potato",
            "The classic. Beige and dependable.",
            "Idaho Russets are ~20% starch by dry mass — highest of any common variety.",
            1, 100, 1.00, false, ConsoleColor.DarkYellow,
            new string[]{
              "    .------.",
              "   / ~~~~~~ \\",
              "  | (  __  ) |",
              "   \\ ~~~~~~ /",
              "    `------'"
            }),

          // ── 1: Yukon Gold ────────────────────────────────────────────────────
          new Potato("Yukon Gold",
            "Buttery, waxy, and proudly Canadian.",
            "Bred in Guelph, Ontario (1966). Low starch, high moisture — holds shape when cooked.",
            1, 130, 1.15, false, ConsoleColor.Yellow,
            new string[]{
              "    .-----.",
              "   / ** ** \\",
              "  |  *****  |",
              "   \\ ** ** /",
              "    `-----'"
            }),

          // ── 2: Sweet Potato ──────────────────────────────────────────────────
          new Potato("Sweet Potato",
            "Not a real potato. The bar is aware of this and is upset.",
            "Actually Ipomoea batatas (morning glory family) — not a nightshade. ~6% sugar raw.",
            2, 150, 1.20, true, ConsoleColor.DarkRed,
            new string[]{
              "   .--------.",
              "  / ~~~ ~~~  \\",
              " |  (>__<)    |",
              "  \\ ~~~~~~  /",
              "   `-------'"
            }),

          // ── 3: Purple (HoldRelease — "peel") ──────────────────────────────────
          new Potato("Purple Potato",
            "Mysterious. Possibly enchanted. Same starch content.",
            "Coloured by anthocyanins — the same antioxidant compound found in blueberries.",
            1, 180, 1.30, false, ConsoleColor.Magenta,
            new string[]{
              "    .-----.",
              "   /* * * *\\",
              "  |* * * * *|",
              "   \\* * * */",
              "    `-----'"
            }) { Cut = CutType.HoldRelease },

          // ── 4: Fingerling (ShrinkZone — "speed cut") ──────────────────────────
          new Potato("Fingerling",
            "Tiny. Smug. It has decided to be difficult about this.",
            "Grown in shallow soil to stay small. High skin-to-flesh ratio — prized for roasting.",
            1, 280, 1.60, false, ConsoleColor.Cyan,
            new string[]{
              "   .-.",
              "  /   \\",
              " | ( ) |",
              "  \\   /",
              "   `-'"
            }) { Cut = CutType.ShrinkZone },

          // ── 5: King Edward VII (MultiTarget — real "julienne") ────────────────
          new Potato("King Edward VII",
            "Victorian era, 1902. Three cuts, two taps each. Absolutely insufferable.",
            "Named after King Edward VII; one of the oldest still-grown British varieties.",
            3, 120, 1.25, false, ConsoleColor.White,
            new string[]{
              "  .==========.",
              " / || || || || \\",
              "|  ||  ~~  ||  |",
              " \\ || || || || /",
              "  `=========='"
            }) { Cut = CutType.MultiTarget },

          // ── 6: Golden Potato (rare bonus — never drawn from stage pools) ────
          new Potato("GOLDEN POTATO",
            "It glows. It hums. Do not let it get away.",
            "Luxury spuds are real: La Bonnotte potatoes have sold for ~500 EUR per kilo.",
            1, 500, 1.50, false, ConsoleColor.Yellow,
            new string[]{
              "    .-$$$$-.",
              "   /  $$$$  \\",
              "  |  $ ** $  |",
              "   \\  $$$$  /",
              "    `-$$$$-'"
            }),

          // ── 7: Rotten Potato (Dodge — do NOT slice!) ──────────────────────────
          new Potato("Rotten Potato",
            "Something is deeply wrong with this one. Bin it. Do not slice.",
            "Potato glycoalkaloids (solanine) concentrate in green/spoiled spuds — genuinely toxic.",
            1, 110, 1.40, false, ConsoleColor.DarkGreen,
            new string[]{
              "    .------.",
              "   / x  x   \\",
              "  | ~ rot ~  |",
              "   \\  ~~~~  /",
              "    `--..--'"
            }) { Cut = CutType.Dodge, Hazard = true },
        };
    }
}
