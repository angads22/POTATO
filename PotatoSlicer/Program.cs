/*
 * ════════════════════════════════════════════════════════════════
 *   SLICE IT!  ·  The Potato Cutting Championship
 *   A full-scale C# console rhythm-action game.
 *
 *   Requirements : .NET 8.0 (or .NET 6.0+)
 *   Run with     : dotnet run   (from the PotatoSlicer/ folder)
 *   Controls     : SPACE = cut  ·  ESC = quit to menu
 * ════════════════════════════════════════════════════════════════
 */

using System;
using System.Diagnostics;
using System.IO;
using System.Threading;

namespace PotatoSlicer
{
    // ──────────────────────────────────────────────────────────────
    //  CutQuality  —  result of a single cut attempt
    // ──────────────────────────────────────────────────────────────
    enum CutQuality { Miss, Poor, Good, Great, Perfect }

    // ──────────────────────────────────────────────────────────────
    //  Knife  —  affects bar speed and zone widths
    //
    //  Cps : bar speed in characters-per-second
    //  Ph/Gh/Gd : half-widths of Perfect / Great / Good zones
    //             (effective half = max(min, floor(base / potatoHardness)))
    // ──────────────────────────────────────────────────────────────
    sealed class Knife
    {
        public string       Name, Desc;
        public double       Cps;
        public int          Ph, Gh, Gd;
        public int          Price;
        public ConsoleColor Color;

        public Knife(string n, string d, double cps,
                     int ph, int gh, int gd, int price, ConsoleColor col)
        { Name=n; Desc=d; Cps=cps; Ph=ph; Gh=gh; Gd=gd; Price=price; Color=col; }
    }

    // ──────────────────────────────────────────────────────────────
    //  Potato  —  the thing being cut
    //
    //  Hard    : hardness multiplier (>1.0 = smaller effective zones)
    //  Chaotic : bar randomly reverses direction (sweet potato behaviour)
    // ──────────────────────────────────────────────────────────────
    sealed class Potato
    {
        public string       Name, Quip, Fact;
        public int          Cuts;      // cuts required to complete
        public int          Base;      // base points per perfect cut
        public double       Hard;
        public bool         Chaotic;
        public ConsoleColor Color;
        public string[]     Art;       // 5-line ASCII art

        public Potato(string name, string quip, string fact,
                      int cuts, int pts, double hard, bool chaotic,
                      ConsoleColor col, string[] art)
        { Name=name; Quip=quip; Fact=fact; Cuts=cuts; Base=pts;
          Hard=hard; Chaotic=chaotic; Color=col; Art=art; }
    }

    // ──────────────────────────────────────────────────────────────
    //  Game  —  all state and logic
    // ──────────────────────────────────────────────────────────────
    sealed class Game
    {
        // ── Layout constants ──────────────────────────────────────
        const int BAR   = 50;   // bar width in characters
        const int CTR   = 25;   // bar centre index
        const int SCR_W = 74;   // width used for centring text
        const int POTS  = 5;    // potatoes per stage
        const int LIVES = 3;    // misses allowed per run
        const int GOLD  = 6;    // index of the golden potato in pots[]
        const double GOLD_CHANCE = 0.07;   // chance a draw becomes golden

        // ── Stage definitions ─────────────────────────────────────
        static readonly string[] SN = {
            "Training Kitchen",   "Dinner Party",        "Street Food Stall",
            "Restaurant Kitchen", "TV Competition",      "World Championship"
        };
        static readonly string[] ST = {
            "\"Let's see if you can hold a knife.\"",
            "\"The Hendersons arrive in 20 minutes.\"",
            "\"Fries don't cut themselves.\"",
            "\"Table 7 ordered 12 minutes ago.\"",
            "\"The cameras are live. Don't blink.\"",
            "\"THE. WORLD. IS. WATCHING.\""
        };
        // Bar speed multiplier per stage (applied to knife Cps)
        static readonly double[] SM = { 1.00, 1.15, 1.30, 1.50, 1.70, 2.00 };
        // Potato ID pools per stage (random draw without weights)
        static readonly int[][] SP = {
            new int[]{ 0, 0, 0, 0 },
            new int[]{ 0, 0, 1, 1 },
            new int[]{ 0, 1, 2, 2 },
            new int[]{ 1, 2, 3, 3 },
            new int[]{ 1, 3, 4, 4, 5 },
            new int[]{ 0, 1, 2, 3, 4, 5 }
        };

        // ── Player state ──────────────────────────────────────────
        int    score, coins, combo, maxCombo, stage;
        bool   fever;   int fvStr;
        bool   quit;
        int    lives;                             // run ends at 0
        bool   dead;
        int    hiScore;  bool newBest;
        bool   sound = true;
        int    cP, cGr, cGd, cPo, cMs, cTotal;  // cut-quality counters
        double rxnSum;                            // sum of decision times (ms)
        int    stageBase;                         // score at start of stage

        // ── Data arrays ───────────────────────────────────────────
        Knife[]  knives;
        bool[]   kOwned;
        int      kEq;       // equipped knife index
        Potato[] pots;
        Random   rng = new Random();

        // ────────────────────────────────────────────────────────
        //  Constructor  —  all static game data defined here
        // ────────────────────────────────────────────────────────
        public Game()
        {
            //            name            desc                                       cps  ph  gh  gd  price  colour
            knives = new Knife[] {
                new Knife("Butter Knife",   "Not food-safe. You're brave.",           25,  5,  9, 13,   0,  ConsoleColor.Gray),
                new Knife("Paring Knife",   "Small and honest.",                      35,  5,  9, 13,   0,  ConsoleColor.White),
                new Knife("Chef's Knife",   "The workhorse of every kitchen.",        45,  6, 10, 14,   0,  ConsoleColor.Yellow),
                new Knife("Santoku",        "Japanese geometry. Wider sweet spot.",   55,  8, 12, 16,  80,  ConsoleColor.Cyan),
                new Knife("Cleaver",        "Overkill. Profoundly satisfying.",       38,  9, 12, 15, 100,  ConsoleColor.Red),
                new Knife("Gyuto",          "Pro-grade Japanese knife. Fast.",        70,  7, 11, 15, 200,  ConsoleColor.Magenta),
                new Knife("Damascus Steel", "300 folded layers. Bar is a blur.",      90,  9, 13, 17, 350,  ConsoleColor.DarkYellow),
            };
            kOwned = new bool[knives.Length];
            kOwned[0] = kOwned[1] = kOwned[2] = true;   // first three unlocked
            kEq = 2;                                     // Chef's Knife default

            pots = new Potato[] {

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

              // ── 3: Purple ────────────────────────────────────────────────────────
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
                }),

              // ── 4: Fingerling ────────────────────────────────────────────────────
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
                }),

              // ── 5: King Edward VII ───────────────────────────────────────────────
              new Potato("King Edward VII",
                "Victorian era, 1902. Three cuts. Absolutely insufferable.",
                "Named after King Edward VII; one of the oldest still-grown British varieties.",
                3, 120, 1.25, false, ConsoleColor.White,
                new string[]{
                  "  .==========.",
                  " / || || || || \\",
                  "|  ||  ~~  ||  |",
                  " \\ || || || || /",
                  "  `=========='"
                }),

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
            };
        }

        // ────────────────────────────────────────────────────────
        //  Run  —  entry point
        // ────────────────────────────────────────────────────────
        public void Run()
        {
            Console.OutputEncoding = System.Text.Encoding.UTF8;
            Console.CursorVisible  = false;
            TryResize(84, 46);
            LoadHi();
            ShowTitle();
            MainMenu();
        }

        static void TryResize(int w, int h)
        {
            try
            {
                if (Console.WindowWidth  < w) Console.WindowWidth  = w;
                if (Console.WindowHeight < h) Console.WindowHeight = h;
            }
            catch { /* some terminals don't support resize */ }
        }

        // ────────────────────────────────────────────────────────
        //  TITLE SCREEN
        // ────────────────────────────────────────────────────────
        void ShowTitle()
        {
            Console.Clear();
            Console.WriteLine();
            Ink(ConsoleColor.Yellow);
            Ctr(@" ___  _    _  ___  ___     _  _____  _ ");
            Ctr(@"/ __|| |  | |/ __|| __|   | ||_   _|| |");
            Ctr(@"\__ \| |__| |\__ \| _|    | |  | |  | |");
            Ctr(@"|___/|____|_||___/|___|   |_|  |_|  |_|");
            Console.WriteLine();
            Ink(ConsoleColor.White);    Ctr("==========================================");
            Ink(ConsoleColor.Cyan);     Ctr("   THE POTATO CUTTING CHAMPIONSHIP   ");
            Ink(ConsoleColor.White);    Ctr("==========================================");
            Console.WriteLine();
            Ink(ConsoleColor.DarkGray); Ctr("A game about knives, starch, and questionable life choices.");
            Console.WriteLine();
            Ink(ConsoleColor.Gray);     Ctr("Press any key to continue...");
            Console.ResetColor();
            Console.ReadKey(true);
        }

        // ────────────────────────────────────────────────────────
        //  MAIN MENU
        // ────────────────────────────────────────────────────────
        void MainMenu()
        {
            for (;;)
            {
                Console.Clear();
                Ink(ConsoleColor.Yellow); Ctr("=== SLICE IT! ==="); Console.WriteLine();
                Ink(ConsoleColor.White);
                Console.WriteLine("  [1]  New Game");
                Console.WriteLine("  [2]  How to Play");
                Console.WriteLine("  [3]  Sound: " + (sound ? "ON" : "OFF"));
                Console.WriteLine("  [4]  Quit");
                Console.WriteLine();
                Ink(ConsoleColor.Gray);
                Console.WriteLine("  Knife: " + knives[kEq].Name);
                if (hiScore > 0)
                    Console.WriteLine("  Best : " + hiScore + "   (" + GetRank(hiScore) + ")");
                Console.ResetColor();

                ConsoleKey k = Console.ReadKey(true).Key;
                if (k == ConsoleKey.D1 || k == ConsoleKey.NumPad1) NewGame();
                else if (k == ConsoleKey.D2 || k == ConsoleKey.NumPad2) HowToPlay();
                else if (k == ConsoleKey.D3 || k == ConsoleKey.NumPad3) sound = !sound;
                else if (k == ConsoleKey.D4 || k == ConsoleKey.NumPad4)
                { Console.CursorVisible = true; Environment.Exit(0); }
            }
        }

        void HowToPlay()
        {
            Console.Clear();
            Ink(ConsoleColor.Cyan);    Ctr("HOW TO PLAY"); Console.WriteLine();
            Ink(ConsoleColor.White);
            Console.WriteLine("  A bar sweeps left and right. Press [SPACE] to cut.");
            Console.WriteLine("  The closer the bar is to centre, the higher your score.");
            Console.WriteLine();
            Console.WriteLine("  ZONES (centre outward):");
            Ink(ConsoleColor.White);   Console.WriteLine("    \u2588\u2588 PERFECT   Dead centre.   100% base points.");
            Ink(ConsoleColor.Green);   Console.WriteLine("    \u2593\u2593 GREAT     Close.          75% base points.  Builds combo.");
            Ink(ConsoleColor.Yellow);  Console.WriteLine("    \u2591\u2591 GOOD      Decent.         50% base points.  Keeps combo.");
            Ink(ConsoleColor.DarkRed); Console.WriteLine("    .. POOR      Off.            10% base points.  Breaks combo.");
            Ink(ConsoleColor.Red);     Console.WriteLine("       MISS      Way off.          0 points.");
            Console.WriteLine();
            Ink(ConsoleColor.Cyan);
            Console.WriteLine("  COMBO :  Chain GOOD+ cuts. Bonus = +5%/level, cap at x20 (= +100%).");
            Console.WriteLine("  FEVER :  5 GREAT+ in a row -> 2x multiplier until streak breaks.");
            Console.WriteLine("  LIVES :  You have 3. Every MISS costs one. Lose all -> GAME OVER.");
            Console.WriteLine("  QUICK :  A GOOD+ cut inside 1.5 seconds earns a +25% bonus.");
            Console.WriteLine();
            Ink(ConsoleColor.Yellow);
            Console.WriteLine("  Some potatoes need multiple cuts: DICE = 2, JULIENNE = 3.");
            Console.WriteLine("  Harder potatoes have smaller sweet spots but award more points.");
            Console.WriteLine();
            Ink(ConsoleColor.Magenta);
            Console.WriteLine("  SWEET POTATO: Bar randomly reverses direction mid-sweep.");
            Console.WriteLine("  This is because Ipomoea batatas is a morning glory, not a");
            Console.WriteLine("  nightshade (Solanum tuberosum). The game is aware of this.");
            Console.WriteLine();
            Ink(ConsoleColor.Yellow);
            Console.WriteLine("  GOLDEN POTATO: ~7% chance to replace any potato. 500 base points,");
            Console.WriteLine("  tiny sweet spot, and it drops 15 bonus coins when finished.");
            Console.WriteLine();
            Ink(ConsoleColor.DarkCyan);
            Console.WriteLine("  GAME SCIENCE:");
            Console.WriteLine("    pts        = basePts x qualMult x comboBonus x feverBonus");
            Console.WriteLine("    comboBonus = 1.0 + min(combo, 20) x 0.05   [cap 2.0 at combo=20]");
            Console.WriteLine("    feverBonus = 2.0 if >=5 consecutive GREAT+, else 1.0");
            Console.WriteLine("    quickBonus = +25% if decision < 1500 ms and quality >= GOOD");
            Console.WriteLine("    zoneHalf   = max(minWidth, floor(knifeHalf / potatoHardness))");
            Console.WriteLine("    chaos time (sweet potato) ~ Uniform(0.4, 2.0) seconds");
            Console.WriteLine();
            Ink(ConsoleColor.DarkGray);
            Console.WriteLine("  Bar speed is shown live in chars/sec during each cut.");
            Console.WriteLine("  Decision time (ms from bar-start to SPACE) is tracked per cut.");
            Console.WriteLine();
            Ctr("Press any key to go back...");
            Console.ResetColor();
            Console.ReadKey(true);
        }

        // ────────────────────────────────────────────────────────
        //  NEW GAME
        // ────────────────────────────────────────────────────────
        void NewGame()
        {
            score = 0; coins = 40; combo = 0; maxCombo = 0;
            fever = false; fvStr = 0; quit = false;
            lives = LIVES; dead = false; newBest = false;
            cP = cGr = cGd = cPo = cMs = cTotal = 0; rxnSum = 0.0;

            for (int s = 0; s < SN.Length; s++)
            {
                stage = s;
                if (quit) break;
                StageIntro();
                if (quit) break;
                stageBase = score;
                PlayStage();
                if (quit) break;
                if (dead) { GameOver(); return; }
                int ce = StageResult();
                coins += ce;
                if (s < SN.Length - 1 && !quit)
                    RunShop();
            }
            if (!quit) Victory();
        }

        // ────────────────────────────────────────────────────────
        //  STAGE INTRO
        // ────────────────────────────────────────────────────────
        void StageIntro()
        {
            Console.Clear();
            Ink(ConsoleColor.Yellow); Ctr(">> STAGE " + (stage+1) + " / " + SN.Length + " <<"); Console.WriteLine();
            Ink(ConsoleColor.White);  Ctr(SN[stage].ToUpper());
            Ink(ConsoleColor.Gray);   Ctr(ST[stage]);
            Console.WriteLine();
            Ink(ConsoleColor.DarkGray);
            double eff = SM[stage] * knives[kEq].Cps;
            Console.WriteLine("  Speed multiplier : " + SM[stage].ToString("F2") + "x  (" + eff.ToString("F0") + " chars/sec with current knife)");
            Console.WriteLine("  Potatoes to cut  : " + POTS);
            Console.WriteLine("  Your knife       : " + knives[kEq].Name);
            Console.WriteLine("  Lives remaining  : " + new string('♥', lives));
            Console.WriteLine();
            Console.WriteLine("  [SPACE] Start   [ESC] Quit to menu");
            Console.ResetColor();
            for (;;)
            {
                ConsoleKey k = Console.ReadKey(true).Key;
                if (k == ConsoleKey.Spacebar) return;
                if (k == ConsoleKey.Escape)   { quit = true; return; }
            }
        }

        // ────────────────────────────────────────────────────────
        //  STAGE LOOP
        // ────────────────────────────────────────────────────────
        void PlayStage()
        {
            int[] pool = SP[stage];
            for (int i = 0; i < POTS; i++)
            {
                if (quit || dead) return;
                int id = rng.NextDouble() < GOLD_CHANCE
                    ? GOLD
                    : pool[rng.Next(pool.Length)];
                DoCutSequence(pots[id], i + 1);
                if (!quit && !dead) Thread.Sleep(250);
            }
        }

        // ────────────────────────────────────────────────────────
        //  POTATO CUTTING SEQUENCE
        // ────────────────────────────────────────────────────────
        void DoCutSequence(Potato p, int num)
        {
            Knife  k  = knives[kEq];
            double sm = SM[stage];

            // Effective zone half-widths: base / hardness, with enforced minimums
            int ph = Math.Max(2, (int)Math.Round(k.Ph / p.Hard));
            int gh = Math.Max(4, (int)Math.Round(k.Gh / p.Hard));
            int gd = Math.Max(6, (int)Math.Round(k.Gd / p.Hard));

            for (int cut = 0; cut < p.Cuts; cut++)
            {
                if (quit) return;

                DrawPlayfield(p, num, cut, k, ph, gh, gd);
                int barRow = Console.CursorTop;
                Console.WriteLine();   // row 0 : animated bar
                Console.WriteLine();   // row 1 : live speed / countdown
                Console.WriteLine();   // row 2 : spacer

                CutQuality q; double rxn;
                AnimBar(p, k, sm, ph, gh, gd, barRow, out q, out rxn);
                if (quit) return;

                int pts = CalcPts(q, p.Base);
                // Quick-cut bonus: a scoring cut inside 1.5s earns +25%
                bool quick = rxn < 1500.0 &&
                             (q == CutQuality.Perfect || q == CutQuality.Great || q == CutQuality.Good);
                if (quick) pts += pts / 4;
                UpdStats(q);
                score  += pts;
                cTotal++;
                rxnSum += rxn;

                Console.SetCursorPosition(0, barRow + 3);
                PrintResult(q, pts, rxn, quick);

                if (q == CutQuality.Miss)
                {
                    lives--;
                    Ink(ConsoleColor.Red);
                    Ctr(lives > 0 ? "-1 life!  (" + new string('♥', lives) + " left)" : "OUT OF LIVES!");
                    Console.ResetColor();
                    if (lives <= 0) { Snd(150, 400); Thread.Sleep(1200); dead = true; return; }
                }
                Thread.Sleep(850);
            }

            if (p == pots[GOLD])
            {
                coins += 15;
                Ink(ConsoleColor.Yellow); Ctr("The golden potato drops 15 bonus coins!");
                Console.ResetColor();
            }

            Console.WriteLine();
            Ink(ConsoleColor.DarkGray); Console.Write("  Fact: ");
            Console.ResetColor(); Console.WriteLine(p.Fact);
            Thread.Sleep(1700);
        }

        // ────────────────────────────────────────────────────────
        //  STATIC SCREEN LAYOUT  (drawn once per cut)
        // ────────────────────────────────────────────────────────
        void DrawPlayfield(Potato p, int num, int cut, Knife k, int ph, int gh, int gd)
        {
            Console.Clear();

            // Header
            Ink(ConsoleColor.DarkGray); Console.Write("  S" + (stage+1) + "/" + SN.Length + " " + SN[stage] + "   ");
            Ink(ConsoleColor.Yellow);   Console.Write("Score: " + score + "   ");
            Ink(ConsoleColor.Cyan);     Console.Write("Combo: x" + Math.Max(1, combo) + "   ");
            Ink(ConsoleColor.DarkGray); Console.Write("Coins: " + coins + "   ");
            Ink(ConsoleColor.Red);      Console.Write(new string('♥', lives));
            if (fever) { Ink(ConsoleColor.Magenta); Console.Write("   [FEVER 2x]"); }
            Console.ResetColor(); Console.WriteLine(); Console.WriteLine();

            // Potato art
            Ink(p.Color);
            foreach (string line in p.Art) Ctr(line);
            Console.WriteLine();

            // Name + cut label
            Ink(p.Color);
            string lbl = p.Cuts > 1
                ? "  " + p.Name + "  (cut " + (cut+1) + " of " + p.Cuts + ")"
                : "  " + p.Name + "  ";
            Ctr(lbl);
            Ink(ConsoleColor.DarkGray); Ctr(p.Quip);
            Console.WriteLine();

            // Cut type
            string ct = p.Cuts == 1 ? "SLICE" : p.Cuts == 2 ? "DICE" : "JULIENNE";
            if (p.Chaotic) ct += "  [SWEET POTATO — chaotic bar!]";
            Ink(ConsoleColor.Gray); Ctr("[ " + ct + " ]"); Console.WriteLine();

            // Zone legend
            Console.Write("  ");
            Ink(ConsoleColor.White);   Console.Write("\u2588\u2588 PERFECT  ");
            Ink(ConsoleColor.Green);   Console.Write("\u2593\u2593 GREAT  ");
            Ink(ConsoleColor.Yellow);  Console.Write("\u2591\u2591 GOOD  ");
            Ink(ConsoleColor.DarkRed); Console.Write(".. POOR/MISS");
            Console.ResetColor(); Console.WriteLine(); Console.WriteLine();

            // Knife + zone info
            Ink(k.Color);   Console.Write("  Knife: " + k.Name + "   ");
            Ink(ConsoleColor.DarkGray); Console.WriteLine(k.Desc);
            Console.Write("  Zones  ");
            Ink(ConsoleColor.White);  Console.Write("PERFECT +-" + ph + "  ");
            Ink(ConsoleColor.Green);  Console.Write("GREAT +-" + gh + "  ");
            Ink(ConsoleColor.Yellow); Console.Write("GOOD +-" + gd);
            Console.ResetColor(); Console.WriteLine(); Console.WriteLine();

            // Controls
            Ink(ConsoleColor.Gray); Ctr("[SPACE] Cut   [ESC] Quit to menu"); Console.WriteLine();

            // Progress dots
            Console.Write("  ");
            for (int i = 1; i <= POTS; i++)
            {
                if      (i < num)  Ink(ConsoleColor.Green);
                else if (i == num) Ink(p.Color);
                else               Ink(ConsoleColor.DarkGray);
                Console.Write(i < num ? "\u25cf " : i == num ? "\u25c6 " : "\u25cb ");
            }
            Console.ResetColor(); Console.WriteLine(); Console.WriteLine();
        }

        // ────────────────────────────────────────────────────────
        //  ANIMATED BAR
        //  Blocks until SPACE, ESC, or 5-second timeout.
        //  Writes result to out parameters.
        // ────────────────────────────────────────────────────────
        void AnimBar(Potato p, Knife k, double stageMult,
                     int ph, int gh, int gd, int barRow,
                     out CutQuality quality, out double rxnMs)
        {
            double cps  = k.Cps * stageMult;   // effective chars per second
            double pos  = 0.0;
            double dir  = 1.0;

            // Schedule first chaos flip for sweet potato
            double nextChaos = p.Chaotic ? 0.8 + rng.NextDouble() * 1.2 : double.MaxValue;

            // Drain any queued keypresses
            while (Console.KeyAvailable) Console.ReadKey(true);

            Stopwatch sw   = Stopwatch.StartNew();
            double    prev = 0.0;

            quality = CutQuality.Miss;
            rxnMs   = 5000.0;

            for (;;)
            {
                double t  = sw.Elapsed.TotalSeconds;
                double dt = t - prev;
                prev = t;

                // Update position (frame-rate independent via elapsed time)
                pos += dir * cps * dt;
                if (pos >= BAR - 1) { pos = BAR - 1.001; dir = -1.0; }
                if (pos <= 0.0    ) { pos = 0.001;        dir =  1.0; }

                // Sweet potato: random direction reversal
                if (p.Chaotic && t > nextChaos)
                {
                    dir       = -dir;
                    nextChaos = t + 0.4 + rng.NextDouble() * 1.6;
                }

                // Draw bar and live stats
                try
                {
                    Console.SetCursorPosition(0, barRow);
                    DrawBar((int)pos, ph, gh, gd, false, -1);

                    Console.SetCursorPosition(0, barRow + 1);
                    Ink(ConsoleColor.DarkGray);
                    string info = "  Speed: " + cps.ToString("F0") + " chars/sec  |  Timeout: " +
                                  Math.Max(0.0, 5.0 - t).ToString("F1") + "s          ";
                    Console.Write(info);
                    Console.ResetColor();
                }
                catch { /* cursor ops fail when output is redirected */ }

                // Input
                if (Console.KeyAvailable)
                {
                    ConsoleKeyInfo key = Console.ReadKey(true);

                    if (key.Key == ConsoleKey.Spacebar)
                    {
                        rxnMs   = sw.Elapsed.TotalMilliseconds;
                        quality = EvalCut((int)pos, ph, gh, gd);
                        try
                        {
                            Console.SetCursorPosition(0, barRow);
                            DrawBar((int)pos, ph, gh, gd, true, (int)pos);
                        }
                        catch { }
                        return;
                    }
                    if (key.Key == ConsoleKey.Escape)
                    {
                        if (ConfirmQuit(barRow))
                        {
                            quit    = true;
                            quality = CutQuality.Miss;
                            rxnMs   = 0.0;
                            return;
                        }
                        // Resume: restart the sweep so the 5s timeout is fair
                        sw.Restart();
                        prev = 0.0;
                    }
                }

                if (t > 5.0) return;    // timeout → Miss (defaults already set)
                Thread.Sleep(14);       // ~70 fps
            }
        }

        // Asks before abandoning the run. Prompt overwrites the info line,
        // which the next animation frame repaints.
        bool ConfirmQuit(int barRow)
        {
            try { Console.SetCursorPosition(0, barRow + 1); } catch { }
            Ink(ConsoleColor.Red);
            Console.Write("  Abandon this run? All progress is lost. [Y/N]              ");
            Console.ResetColor();
            for (;;)
            {
                ConsoleKey k = Console.ReadKey(true).Key;
                if (k == ConsoleKey.Y) return true;
                if (k == ConsoleKey.N || k == ConsoleKey.Escape) return false;
            }
        }

        // ────────────────────────────────────────────────────────
        //  BAR RENDERER
        //  frozen=true: draws a frozen cut marker at cp instead of moving cursor
        // ────────────────────────────────────────────────────────
        void DrawBar(int cursor, int ph, int gh, int gd, bool frozen, int cp)
        {
            Console.Write("  [");
            for (int x = 0; x < BAR; x++)
            {
                int dist = Math.Abs(x - CTR);

                if (!frozen && x == cursor)
                {
                    Console.BackgroundColor = ConsoleColor.White;
                    Console.ForegroundColor = ConsoleColor.Black;
                    Console.Write("|");
                    Console.ResetColor();
                }
                else if (frozen && x == cp)
                {
                    Console.BackgroundColor = ConsoleColor.DarkCyan;
                    Console.ForegroundColor = ConsoleColor.White;
                    Console.Write("X");
                    Console.ResetColor();
                }
                else if (dist <= ph) { Ink(ConsoleColor.White);    Console.Write('\u2588'); } // full block
                else if (dist <= gh) { Ink(ConsoleColor.Green);    Console.Write('\u2593'); } // dark shade
                else if (dist <= gd) { Ink(ConsoleColor.Yellow);   Console.Write('\u2591'); } // light shade
                else                 { Ink(ConsoleColor.DarkGray); Console.Write('.'); }
            }
            Ink(ConsoleColor.Gray); Console.Write("]"); Console.ResetColor();
        }

        static CutQuality EvalCut(int pos, int ph, int gh, int gd)
        {
            int d = Math.Abs(pos - CTR);
            if (d <= ph)     return CutQuality.Perfect;
            if (d <= gh)     return CutQuality.Great;
            if (d <= gd)     return CutQuality.Good;
            if (d <= gd + 4) return CutQuality.Poor;
            return CutQuality.Miss;
        }

        // ────────────────────────────────────────────────────────
        //  SCORING
        //  pts = basePts x qualMult x comboBonus x feverBonus
        //  comboBonus ramps linearly: +5%/level, hard cap at combo=20
        // ────────────────────────────────────────────────────────
        int CalcPts(CutQuality q, int basePts)
        {
            double qm;
            switch (q)
            {
                case CutQuality.Perfect: qm = 1.00; break;
                case CutQuality.Great:   qm = 0.75; break;
                case CutQuality.Good:    qm = 0.50; break;
                case CutQuality.Poor:    qm = 0.10; break;
                default:                 qm = 0.00; break;
            }
            double cm = 1.0 + Math.Min(combo, 20) * 0.05;  // +5%/combo, cap 2.0
            double fm = fever ? 2.0 : 1.0;
            return (int)(basePts * qm * cm * fm);
        }

        void UpdStats(CutQuality q)
        {
            // Combo tracking
            if (q == CutQuality.Perfect || q == CutQuality.Great || q == CutQuality.Good)
            { combo++; if (combo > maxCombo) maxCombo = combo; }
            else combo = 0;

            // Fever tracking (5 consecutive GREAT+)
            if (q == CutQuality.Perfect || q == CutQuality.Great)
            { fvStr++; if (fvStr >= 5) fever = true; }
            else { fvStr = 0; fever = false; }

            // Quality counters
            switch (q)
            {
                case CutQuality.Perfect: cP++;  break;
                case CutQuality.Great:   cGr++; break;
                case CutQuality.Good:    cGd++; break;
                case CutQuality.Poor:    cPo++; break;
                default:                 cMs++; break;
            }
        }

        // ────────────────────────────────────────────────────────
        //  CUT RESULT DISPLAY  (written below the bar rows)
        // ────────────────────────────────────────────────────────
        void PrintResult(CutQuality q, int pts, double rxn, bool quick)
        {
            string lbl; ConsoleColor col;
            switch (q)
            {
                case CutQuality.Perfect: lbl = "  *** PERFECT! ***  "; col = ConsoleColor.White;      Snd(1200, 120); break;
                case CutQuality.Great:   lbl = "   ** GREAT! **     "; col = ConsoleColor.Green;      Snd(900, 100);  break;
                case CutQuality.Good:    lbl = "      GOOD           "; col = ConsoleColor.Yellow;    Snd(700, 80);   break;
                case CutQuality.Poor:    lbl = "      poor...        "; col = ConsoleColor.DarkYellow; Snd(300, 80);  break;
                default:                 lbl = "      MISS           "; col = ConsoleColor.Red;        Snd(150, 200); break;
            }
            Ink(col); Ctr(lbl);
            if (pts > 0)      { Ink(ConsoleColor.Yellow);   Ctr("+ " + pts + " pts"); }
            if (quick)        { Ink(ConsoleColor.Green);    Ctr("QUICK CUT! +25% bonus"); }
            if (combo > 2)    { Ink(ConsoleColor.Cyan);     Ctr("Combo x" + combo + "!"); }
            if (fever)        { Ink(ConsoleColor.Magenta);  Ctr("[ FEVER: 2x points! ]"); }
            if (rxn < 4999.0) { Ink(ConsoleColor.DarkGray); Ctr("Decision time: " + rxn.ToString("F0") + " ms"); }
            Console.ResetColor();
        }

        // ────────────────────────────────────────────────────────
        //  STAGE RESULT SCREEN  —  returns coins earned
        // ────────────────────────────────────────────────────────
        int StageResult()
        {
            int stagePts    = score - stageBase;
            int coinsEarned = Math.Max(15, stagePts / 20);

            Console.Clear();
            Ink(ConsoleColor.Yellow);
            Ctr("==  STAGE " + (stage+1) + " COMPLETE  ==");
            Ctr(SN[stage].ToUpper()); Console.WriteLine();

            Ink(ConsoleColor.White);
            Console.WriteLine("  Stage score   : " + stagePts);
            Console.WriteLine("  Total score   : " + score);
            Console.WriteLine("  Coins earned  : +" + coinsEarned);
            Console.WriteLine("  Best combo    : x" + maxCombo);
            Console.WriteLine();

            Ink(ConsoleColor.Gray);
            Console.WriteLine("  PERFECT: " + cP + "   GREAT: " + cGr + "   GOOD: " + cGd +
                               "   POOR: " + cPo + "   MISS: " + cMs);
            if (cTotal > 0)
            {
                double acc = (double)(cP + cGr + cGd) / cTotal * 100.0;
                double avg = rxnSum / cTotal;
                Console.WriteLine("  Accuracy: " + acc.ToString("F1") + "%   " +
                                   "Avg decision time: " + avg.ToString("F0") + " ms");
            }
            Console.WriteLine();
            Ink(ConsoleColor.DarkGray); Ctr("Press any key to continue...");
            Console.ResetColor();
            Console.ReadKey(true);
            return coinsEarned;
        }

        // ────────────────────────────────────────────────────────
        //  KNIFE SHOP
        // ────────────────────────────────────────────────────────
        void RunShop()
        {
            for (;;)
            {
                Console.Clear();
                Ink(ConsoleColor.Cyan);
                Ctr("+---------------------+");
                Ctr("|  K N I F E  S H O P  |");
                Ctr("+---------------------+");
                Console.WriteLine();
                Ink(ConsoleColor.Yellow); Console.WriteLine("  Coins: " + coins); Console.WriteLine();

                for (int i = 0; i < knives.Length; i++)
                {
                    Knife kn = knives[i];
                    bool  ow = kOwned[i];
                    bool  eq = (kEq == i);

                    string tag = eq ? " [EQUIPPED]"
                               : ow ? " [press to equip]"
                                    : " [BUY: " + kn.Price + "c]";

                    Ink(ow ? kn.Color : ConsoleColor.DarkGray);
                    Console.WriteLine("  [" + (i+1) + "] " + kn.Name + tag);
                    Ink(ConsoleColor.DarkGray);
                    Console.WriteLine("       " + kn.Desc);
                    Console.WriteLine("       Speed: " + kn.Cps.ToString("F0") + " c/s  |  " +
                                      "PERFECT +-" + kn.Ph + "  |  GOOD +-" + kn.Gd);
                    Console.WriteLine();
                }

                Ink(ConsoleColor.Gray);
                Console.WriteLine("  [1-7] Buy or equip   [SPACE] Continue to next stage");
                Console.ResetColor();

                ConsoleKeyInfo ki = Console.ReadKey(true);
                if (ki.Key == ConsoleKey.Spacebar || ki.Key == ConsoleKey.Escape) return;

                int idx = ki.KeyChar - '1';
                if (idx < 0 || idx >= knives.Length) continue;

                if (kOwned[idx])
                {
                    kEq = idx;
                    Ink(ConsoleColor.Green); Ctr("Equipped: " + knives[idx].Name + "!");
                    Thread.Sleep(600);
                }
                else if (coins >= knives[idx].Price)
                {
                    coins      -= knives[idx].Price;
                    kOwned[idx] = true;
                    kEq         = idx;
                    Ink(ConsoleColor.Green); Ctr("Purchased & equipped: " + knives[idx].Name + "!");
                    Snd(1000, 80);
                    Thread.Sleep(800);
                }
                else
                {
                    Ink(ConsoleColor.Red); Ctr("Not enough coins!");
                    Thread.Sleep(600);
                }
                Console.ResetColor();
            }
        }

        // ────────────────────────────────────────────────────────
        //  VICTORY SCREEN
        // ────────────────────────────────────────────────────────
        void Victory()
        {
            SaveBest();
            Snd(900, 100); Snd(1100, 100); Snd(1400, 200);
            Console.Clear(); Console.WriteLine();
            Ink(ConsoleColor.Yellow);
            Ctr("##########################################");
            Ctr("#                                        #");
            Ctr("#    [ TROPHY ]   WORLD  CHAMPION!      #");
            Ctr("#                                        #");
            Ctr("##########################################");
            Console.WriteLine();
            Ink(ConsoleColor.White); Ctr("FINAL SCORE: " + score);
            if (newBest)          { Ink(ConsoleColor.Green);    Ctr("*** NEW HIGH SCORE! ***"); }
            else if (hiScore > 0) { Ink(ConsoleColor.DarkGray); Ctr("Best: " + hiScore); }
            Console.WriteLine();

            FinalStats();
            Console.WriteLine();
            Ink(ConsoleColor.Cyan); Ctr("RANK: " + GetRank(score));
            Console.WriteLine();
            Ink(ConsoleColor.DarkGray); Ctr("Press any key to return to menu...");
            Console.ResetColor();
            Console.ReadKey(true);
        }

        // ────────────────────────────────────────────────────────
        //  GAME OVER SCREEN  —  shown when all lives are lost
        // ────────────────────────────────────────────────────────
        void GameOver()
        {
            SaveBest();
            Snd(400, 150); Snd(300, 150); Snd(150, 400);
            Console.Clear(); Console.WriteLine();
            Ink(ConsoleColor.Red);
            Ctr("##########################################");
            Ctr("#                                        #");
            Ctr("#         G A M E    O V E R            #");
            Ctr("#                                        #");
            Ctr("##########################################");
            Console.WriteLine();
            Ink(ConsoleColor.Gray);
            Ctr("You ran out of lives in stage " + (stage+1) + ": " + SN[stage] + ".");
            Console.WriteLine();
            Ink(ConsoleColor.White); Ctr("FINAL SCORE: " + score);
            if (newBest)          { Ink(ConsoleColor.Green);    Ctr("*** NEW HIGH SCORE! ***"); }
            else if (hiScore > 0) { Ink(ConsoleColor.DarkGray); Ctr("Best: " + hiScore); }
            Console.WriteLine();

            FinalStats();
            Console.WriteLine();
            Ink(ConsoleColor.Cyan); Ctr("RANK: " + GetRank(score));
            Console.WriteLine();
            Ink(ConsoleColor.DarkGray); Ctr("Press any key to return to menu...");
            Console.ResetColor();
            Console.ReadKey(true);
        }

        void FinalStats()
        {
            Ink(ConsoleColor.Gray);
            Console.WriteLine("  PERFECT  : " + cP);
            Console.WriteLine("  GREAT    : " + cGr);
            Console.WriteLine("  GOOD     : " + cGd);
            Console.WriteLine("  POOR     : " + cPo);
            Console.WriteLine("  MISS     : " + cMs);
            Console.WriteLine("  MAX COMBO: x" + maxCombo);
            if (cTotal > 0)
            {
                double acc = (double)(cP + cGr + cGd) / cTotal * 100.0;
                double avg = rxnSum / cTotal;
                Console.WriteLine("  ACCURACY : " + acc.ToString("F1") + "%");
                Console.WriteLine("  AVG DT   : " + avg.ToString("F0") + " ms  (mean decision time per cut)");
            }
        }

        static string GetRank(int s)
        {
            if (s >= 35000) return "S+  LEGENDARY POTATO MASTER";
            if (s >= 25000) return "S   WORLD CHAMPION";
            if (s >= 18000) return "A+  EXECUTIVE CHEF";
            if (s >= 12000) return "A   HEAD CHEF";
            if (s >= 7000)  return "B+  SOUS CHEF";
            if (s >= 4000)  return "B   LINE COOK";
            if (s >= 2000)  return "C   HOME COOK";
            return                 "D   You tried. Potatoes are hard.";
        }

        // ────────────────────────────────────────────────────────
        //  High score persistence  —  plain text file next to the binary
        // ────────────────────────────────────────────────────────
        static string HiPath => Path.Combine(AppContext.BaseDirectory, "highscore.txt");

        void LoadHi()
        {
            try
            {
                if (File.Exists(HiPath))
                    int.TryParse(File.ReadAllText(HiPath).Trim(), out hiScore);
            }
            catch { /* unreadable file -> no high score */ }
        }

        void SaveBest()
        {
            if (score <= hiScore) return;
            hiScore = score;
            newBest = true;
            try { File.WriteAllText(HiPath, hiScore.ToString()); }
            catch { /* read-only install dir -> score not persisted */ }
        }

        // ────────────────────────────────────────────────────────
        //  Sound  —  tones on Windows, terminal bell elsewhere
        // ────────────────────────────────────────────────────────
        void Snd(int freq, int dur)
        {
            if (!sound) return;
            try
            {
                if (OperatingSystem.IsWindows()) Console.Beep(freq, dur);
                else Console.Beep();
            }
            catch { /* no console / no audio device */ }
        }

        // ────────────────────────────────────────────────────────
        //  Helpers
        // ────────────────────────────────────────────────────────
        void Ink(ConsoleColor c) => Console.ForegroundColor = c;

        void Ctr(string s)
        {
            int pad = Math.Max(0, (SCR_W - s.Length) / 2);
            Console.WriteLine(new string(' ', pad) + s);
        }
    }

    // ──────────────────────────────────────────────────────────────
    //  Entry point
    // ──────────────────────────────────────────────────────────────
    class Program
    {
        static void Main() => new Game().Run();
    }
}
