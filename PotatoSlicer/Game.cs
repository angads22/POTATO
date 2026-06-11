/*
 * Game — all run/player state and the top-level flow (menus, stage loop,
 * shop, results). Pure helpers live in Scoring / Render / Audio / GameData and
 * are pulled in with `using static` so the call sites stay terse.
 */
using System;
using System.Diagnostics;
using System.IO;
using System.Threading;
using static PotatoSlicer.Render;
using static PotatoSlicer.Audio;
using static PotatoSlicer.Scoring;
using static PotatoSlicer.GameData;

namespace PotatoSlicer
{
    sealed partial class Game
    {
        // ── Layout / rules constants ──────────────────────────────
        const int POTS  = 5;    // potatoes per stage
        const int LIVES = 3;    // misses allowed per run
        const int GOLD  = 6;    // index of the golden potato in pots[]
        const double GOLD_CHANCE = 0.07;   // chance a draw becomes golden

        // ── Player state ──────────────────────────────────────────
        int    score, coins, combo, maxCombo, stage;
        bool   fever;   int fvStr;
        bool   quit;
        int    lives;                             // run ends at 0
        bool   dead;
        int    hiScore;  bool newBest;
        int    cP, cGr, cGd, cPo, cMs, cTotal;  // cut-quality counters
        double rxnSum;                            // sum of decision times (ms)
        int    stageBase;                         // score at start of stage
        bool   stageClean;                        // no misses this stage (recipe/achv)
        bool   everFever, dodgedRotten, gotGolden, anyCleanStage;  // achievement flags

        // ── Mode + profile ────────────────────────────────────────
        GameMode mode = GameMode.Championship;
        SaveData save = new SaveData();
        int      lastPlace;                        // leaderboard placement this run
        System.Collections.Generic.List<string> newAchv = new System.Collections.Generic.List<string>();

        // Stage accessors — clamp to the defined tables so Endless / Time
        // Attack can run past the last defined stage, scaling speed beyond it.
        int    StageCap     => SN.Length - 1;
        string CurStageName => SN[Math.Min(stage, StageCap)];
        string CurStageTag  => ST[Math.Min(stage, StageCap)];
        double CurSpeed     => SM[Math.Min(stage, StageCap)] * (1.0 + 0.08 * Math.Max(0, stage - StageCap));
        int[]  CurPool      => SP[Math.Min(stage, StageCap)];
        bool   IsEndless    => mode == GameMode.Endless;

        // ── Data arrays ───────────────────────────────────────────
        Knife[]  knives;
        bool[]   kOwned;
        int      kEq;       // equipped knife index
        Potato[] pots;
        Random   rng = new Random();

        // ────────────────────────────────────────────────────────
        //  Constructor  —  content comes from GameData
        // ────────────────────────────────────────────────────────
        public Game()
        {
            knives = BuildKnives();
            kOwned = new bool[knives.Length];
            kOwned[0] = kOwned[1] = kOwned[2] = true;   // first three unlocked
            kEq = 2;                                     // Chef's Knife default

            pots = BuildPotatoes();
        }

        // ────────────────────────────────────────────────────────
        //  Run  —  entry point
        // ────────────────────────────────────────────────────────
        public void Run()
        {
            Console.OutputEncoding = System.Text.Encoding.UTF8;
            Console.CursorVisible  = false;
            TryResize(84, 46);
            save = SaveData.Load();
            LoadHi();                                  // legacy highscore.txt seed
            hiScore = Math.Max(hiScore, save.OverallBest());
            ApplyMetaUnlocks();                        // unlock meta-purchased knives
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
                Console.WriteLine("  [3]  Leaderboard");
                Console.WriteLine("  [4]  Achievements");
                Console.WriteLine("  [5]  Sound: " + (Audio.Enabled ? "ON" : "OFF"));
                Console.WriteLine("  [6]  Quit");
                Console.WriteLine();
                Ink(ConsoleColor.Gray);
                Console.WriteLine("  Knife: " + knives[kEq].Name + "   Chef XP: " + save.ChefXp);
                if (hiScore > 0)
                    Console.WriteLine("  Best : " + hiScore + "   (" + GetRank(hiScore) + ")");
                Console.ResetColor();

                ConsoleKey k = Console.ReadKey(true).Key;
                if (k == ConsoleKey.D1 || k == ConsoleKey.NumPad1) NewGameFlow();
                else if (k == ConsoleKey.D2 || k == ConsoleKey.NumPad2) HowToPlay();
                else if (k == ConsoleKey.D3 || k == ConsoleKey.NumPad3) LeaderboardScreen();
                else if (k == ConsoleKey.D4 || k == ConsoleKey.NumPad4) AchievementsScreen();
                else if (k == ConsoleKey.D5 || k == ConsoleKey.NumPad5) Audio.Enabled = !Audio.Enabled;
                else if (k == ConsoleKey.D6 || k == ConsoleKey.NumPad6)
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
            Ink(ConsoleColor.White);   Console.WriteLine("    ██ PERFECT   Dead centre.   100% base points.");
            Ink(ConsoleColor.Green);   Console.WriteLine("    ▓▓ GREAT     Close.          75% base points.  Builds combo.");
            Ink(ConsoleColor.Yellow);  Console.WriteLine("    ░░ GOOD      Decent.         50% base points.  Keeps combo.");
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
            Ink(ConsoleColor.Green);
            Console.WriteLine("  CUT TYPES — not every spud is a simple slice:");
            Ink(ConsoleColor.White);
            Console.WriteLine("    PEEL (Purple)      : tap [SPACE] to start a rising fill, tap");
            Console.WriteLine("                          again to lock it at the centre.");
            Console.WriteLine("    SPEED CUT (Finger) : the sweet spot SHRINKS — commit fast.");
            Console.WriteLine("    JULIENNE (K.Edward): land TWO quick taps; scored as the worse.");
            Ink(ConsoleColor.Red);
            Console.WriteLine("    ROTTEN POTATO      : do NOT press [SPACE]! Press [X] to bin it.");
            Console.WriteLine("                          Slicing it costs a life.");
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
        //  STAGE INTRO
        // ────────────────────────────────────────────────────────
        void StageIntro()
        {
            Console.Clear();
            string total = IsEndless ? "∞" : SN.Length.ToString();
            Ink(ConsoleColor.Yellow); Ctr(">> STAGE " + (stage+1) + " / " + total + " <<"); Console.WriteLine();
            Ink(ConsoleColor.White);  Ctr(CurStageName.ToUpper());
            Ink(ConsoleColor.Gray);   Ctr(CurStageTag);
            Console.WriteLine();
            Ink(ConsoleColor.DarkGray);
            double eff = CurSpeed * knives[kEq].Cps;
            Console.WriteLine("  Speed multiplier : " + CurSpeed.ToString("F2") + "x  (" + eff.ToString("F0") + " chars/sec with current knife)");
            Console.WriteLine("  Potatoes to cut  : " + POTS);
            Console.WriteLine("  Your knife       : " + knives[kEq].Name);
            Console.WriteLine("  Lives remaining  : " + new string('♥', lives));
            Ink(ConsoleColor.Cyan);
            Console.WriteLine("  Stage order      : " + curRecipe.Desc + "  (+" + curRecipe.Reward + "c)");
            if (puSharp + puSlow + puLife + puShield > 0)
            {
                Ink(ConsoleColor.Green);
                Console.WriteLine("  Power-ups        : Sharpen x" + puSharp + "  Slow x" + puSlow +
                                  "  Life x" + puLife + "  Shield x" + puShield);
            }
            Ink(ConsoleColor.DarkGray);
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
            int[] pool = CurPool;
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
            double sm = CurSpeed;

            MaybeUsePowerUp(p);                       // optional pre-cut activation
            double sharp = pendingSharp ? 1.5 : 1.0;
            if (pendingSlow) sm *= 0.5;

            // Effective zone half-widths: base / hardness (×sharp), enforced minimums
            int ph = Math.Max(2, (int)Math.Round(k.Ph * sharp / p.Hard));
            int gh = Math.Max(4, (int)Math.Round(k.Gh * sharp / p.Hard));
            int gd = Math.Max(6, (int)Math.Round(k.Gd * sharp / p.Hard));

            for (int cut = 0; cut < p.Cuts; cut++)
            {
                if (quit) return;

                DrawPlayfield(p, num, cut, k, ph, gh, gd);
                int barRow = Console.CursorTop;
                Console.WriteLine();   // row 0 : animated bar
                Console.WriteLine();   // row 1 : live speed / countdown
                Console.WriteLine();   // row 2 : spacer

                CutQuality q; double rxn;
                DispatchCut(p, k, sm, ph, gh, gd, barRow, out q, out rxn);
                if (quit) return;

                int pts = CalcPts(q, p.Base, combo, fever);
                // Quick-cut bonus: a scoring cut inside 1.5s earns +25%
                bool quick = rxn < 1500.0 &&
                             (q == CutQuality.Perfect || q == CutQuality.Great || q == CutQuality.Good);
                if (quick) pts += pts / 4;
                int comboBefore = combo;
                UpdStats(q);
                score  += pts;
                cTotal++;
                rxnSum += rxn;

                Console.SetCursorPosition(0, barRow + 3);
                PrintResult(q, pts, rxn, quick);

                if (q == CutQuality.Miss)
                {
                    if (shieldActive)
                    {
                        shieldActive = false;
                        combo = comboBefore;          // forgiven — keep the chain
                        if (cMs > 0) cMs--;           // and don't log the miss
                        Ink(ConsoleColor.Cyan); Ctr("COMBO SHIELD! Miss forgiven.");
                        Console.ResetColor();
                    }
                    else
                    {
                        lives--;
                        stageClean = false;
                        Ink(ConsoleColor.Red);
                        Ctr(lives > 0 ? "-1 life!  (" + new string('♥', lives) + " left)" : "OUT OF LIVES!");
                        Console.ResetColor();
                        if (lives <= 0) { Snd(150, 400); Thread.Sleep(1200); dead = true; return; }
                    }
                }
                Thread.Sleep(850);
            }
            pendingSharp = false; pendingSlow = false;   // consumed by this potato

            if (p == pots[GOLD])
            {
                coins += 15;
                gotGolden = true;
                Ink(ConsoleColor.Yellow); Ctr("The golden potato drops 15 bonus coins!");
                Console.ResetColor();
            }
            RecordCompleted(p);   // recipe-order tally

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
            string hdrTotal = IsEndless ? "∞" : SN.Length.ToString();
            Ink(ConsoleColor.DarkGray); Console.Write("  S" + (stage+1) + "/" + hdrTotal + " " + CurStageName + "   ");
            Ink(ConsoleColor.Yellow);   Console.Write("Score: " + score + "   ");
            Ink(ConsoleColor.Cyan);     Console.Write("Combo: x" + Math.Max(1, combo) + "   ");
            Ink(ConsoleColor.DarkGray); Console.Write("Coins: " + coins + "   ");
            Ink(ConsoleColor.Red);      Console.Write(new string('♥', lives));
            if (fever) { Ink(ConsoleColor.Magenta); Console.Write("   [FEVER 2x]"); }
            if (taClock != null)
            { Ink(ConsoleColor.Green); Console.Write("   Time: " + Math.Max(0.0, 60.0 - taClock.Elapsed.TotalSeconds).ToString("F0") + "s"); }
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

            // Cut type label (depends on the minigame this potato uses)
            string ct;
            switch (p.Cut)
            {
                case CutType.HoldRelease: ct = "PEEL — tap to start, tap to lock";       break;
                case CutType.MultiTarget: ct = "JULIENNE — two quick taps";              break;
                case CutType.ShrinkZone:  ct = "SPEED CUT — the sweet spot is shrinking"; break;
                case CutType.Dodge:       ct = "ROTTEN — do NOT slice!";                 break;
                default:                  ct = p.Cuts == 1 ? "SLICE" : p.Cuts == 2 ? "DICE" : "JULIENNE"; break;
            }
            if (p.Chaotic) ct += "  [SWEET POTATO — chaotic bar!]";
            Ink(p.Cut == CutType.Dodge ? ConsoleColor.Red : ConsoleColor.Gray);
            Ctr("[ " + ct + " ]"); Console.WriteLine();

            // Zone legend
            Console.Write("  ");
            Ink(ConsoleColor.White);   Console.Write("██ PERFECT  ");
            Ink(ConsoleColor.Green);   Console.Write("▓▓ GREAT  ");
            Ink(ConsoleColor.Yellow);  Console.Write("░░ GOOD  ");
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

            // Controls (per mechanic)
            string controls = p.Cut == CutType.Dodge
                ? "[X] Bin it   [ESC] Quit to menu"
                : "[SPACE] Cut   [ESC] Quit to menu";
            Ink(ConsoleColor.Gray); Ctr(controls); Console.WriteLine();

            // Progress dots
            Console.Write("  ");
            for (int i = 1; i <= POTS; i++)
            {
                if      (i < num)  Ink(ConsoleColor.Green);
                else if (i == num) Ink(p.Color);
                else               Ink(ConsoleColor.DarkGray);
                Console.Write(i < num ? "● " : i == num ? "◆ " : "○ ");
            }
            Console.ResetColor(); Console.WriteLine(); Console.WriteLine();
        }

        // ────────────────────────────────────────────────────────
        //  ANIMATED BAR
        //  Blocks until SPACE, ESC, or 5-second timeout.
        //  Writes result to out parameters.
        // ────────────────────────────────────────────────────────
        //  shrinkPerSec > 0 makes the sweet spots contract over time (the
        //  ShrinkZone mechanic). At 0 the bar behaves exactly as before.
        void AnimBar(Potato p, Knife k, double stageMult,
                     int ph, int gh, int gd, int barRow,
                     out CutQuality quality, out double rxnMs,
                     double shrinkPerSec = 0.0)
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

                // Current (possibly shrunk) zone half-widths. Linear contraction
                // down to a 35% floor so the cut never becomes impossible.
                int cph = ph, cgh = gh, cgd = gd;
                if (shrinkPerSec > 0.0)
                {
                    double f = Math.Max(0.35, 1.0 - shrinkPerSec * t);
                    cph = Math.Max(1,       (int)Math.Round(ph * f));
                    cgh = Math.Max(cph + 1, (int)Math.Round(gh * f));
                    cgd = Math.Max(cgh + 1, (int)Math.Round(gd * f));
                }

                // Update position (frame-rate independent via elapsed time)
                pos += dir * cps * dt;
                if (pos >= Layout.BAR - 1) { pos = Layout.BAR - 1.001; dir = -1.0; }
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
                    DrawBar((int)pos, cph, cgh, cgd, false, -1);

                    Console.SetCursorPosition(0, barRow + 1);
                    Ink(ConsoleColor.DarkGray);
                    string info = "  Speed: " + cps.ToString("F0") + " chars/sec  |  Timeout: " +
                                  Math.Max(0.0, 5.0 - t).ToString("F1") + "s" +
                                  (shrinkPerSec > 0.0 ? "  |  ZONE SHRINKING!" : "") + "          ";
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
                        quality = EvalCut((int)pos, cph, cgh, cgd);
                        try
                        {
                            Console.SetCursorPosition(0, barRow);
                            DrawBar((int)pos, cph, cgh, cgd, true, (int)pos);
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
        //  STAT TRACKING  (combo / fever / counters)
        // ────────────────────────────────────────────────────────
        void UpdStats(CutQuality q)
        {
            // Combo tracking
            if (q == CutQuality.Perfect || q == CutQuality.Great || q == CutQuality.Good)
            { combo++; if (combo > maxCombo) maxCombo = combo; if (combo > stageMaxCombo) stageMaxCombo = combo; }
            else combo = 0;

            // Fever tracking (5 consecutive GREAT+)
            if (q == CutQuality.Perfect || q == CutQuality.Great)
            { fvStr++; if (fvStr >= 5) { fever = true; everFever = true; } }
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
            Ctr(CurStageName.ToUpper()); Console.WriteLine();

            Ink(ConsoleColor.White);
            Console.WriteLine("  Stage score   : " + stagePts);
            Console.WriteLine("  Total score   : " + score);
            Console.WriteLine("  Coins earned  : +" + coinsEarned);
            Console.WriteLine("  Best combo    : x" + maxCombo);
            if (recipeBonusGiven > 0)
            { Ink(ConsoleColor.Green);    Console.WriteLine("  Order COMPLETE: +" + recipeBonusGiven + "c  (" + curRecipe.Desc + ")"); }
            else
            { Ink(ConsoleColor.DarkGray); Console.WriteLine("  Order failed  : " + curRecipe.Desc); }
            Ink(ConsoleColor.White);
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

                Ink(ConsoleColor.Cyan); Console.WriteLine("  POWER-UPS (carry into cuts):");
                Ink(ConsoleColor.White);
                Console.WriteLine("    [Q] Sharpening Stone " + PRICE_SHARP + "c (have x" + puSharp + ")  — zones +50% for one potato");
                Console.WriteLine("    [W] Slow-Mo " + PRICE_SLOW + "c (have x" + puSlow + ")          — half speed for one potato");
                Console.WriteLine("    [E] Extra Life " + PRICE_LIFE + "c (have x" + puLife + ")        — +1 life when used");
                Console.WriteLine("    [R] Combo Shield " + PRICE_SHIELD + "c (have x" + puShield + ")     — forgive one miss");
                Console.WriteLine();
                Ink(ConsoleColor.Gray);
                Console.WriteLine("  [1-7] Knives   [Q/W/E/R] Power-ups   [SPACE] Continue");
                Console.ResetColor();

                ConsoleKeyInfo ki = Console.ReadKey(true);
                if (ki.Key == ConsoleKey.Spacebar || ki.Key == ConsoleKey.Escape) return;
                if (TryBuyPowerUp(ki.Key)) continue;

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
            FinishRun(true);
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
            if (lastPlace > 0) { Ink(ConsoleColor.Yellow); Ctr("Leaderboard placement: #" + lastPlace); }
            ShowNewAchievements();
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
            FinishRun();
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
            Ctr("You ran out of lives in stage " + (stage+1) + ": " + CurStageName + ".");
            Console.WriteLine();
            Ink(ConsoleColor.White); Ctr("FINAL SCORE: " + score);
            if (newBest)          { Ink(ConsoleColor.Green);    Ctr("*** NEW HIGH SCORE! ***"); }
            else if (hiScore > 0) { Ink(ConsoleColor.DarkGray); Ctr("Best: " + hiScore); }
            Console.WriteLine();

            FinalStats();
            Console.WriteLine();
            Ink(ConsoleColor.Cyan); Ctr("RANK: " + GetRank(score));
            if (lastPlace > 0) { Ink(ConsoleColor.Yellow); Ctr("Leaderboard placement: #" + lastPlace); }
            ShowNewAchievements();
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
    }
}
