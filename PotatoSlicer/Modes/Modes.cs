/*
 * Game.Modes — mode selection, the per-mode run loops, end-of-run bookkeeping
 * (best scores, leaderboard, achievements), and the Leaderboard/Achievements
 * browse screens. Championship and Daily share RunCampaign; Endless and Time
 * Attack have their own loops but reuse the same stage/cut machinery.
 */
using System;
using System.Collections.Generic;
using System.Diagnostics;
using static PotatoSlicer.Render;
using static PotatoSlicer.Audio;
using static PotatoSlicer.Scoring;
using static PotatoSlicer.GameData;

namespace PotatoSlicer
{
    sealed partial class Game
    {
        // Completion tally (potato id -> times finished this run). Feeds the
        // recipe-order checks in Game.Progression.
        readonly Dictionary<int, int> completed = new Dictionary<int, int>();

        // Wall clock for Time Attack (null outside that mode).
        Stopwatch taClock;

        // Achievement catalogue: id -> human label.
        static readonly (string Id, string Label)[] AchvList =
        {
            ("first_fever", "Feeling the Heat — trigger FEVER mode"),
            ("combo20",     "Chain Reaction — reach a x20 combo"),
            ("clean_stage", "Surgical — clear a stage with no misses"),
            ("dodge_rot",   "Health Inspector — bin a rotten potato"),
            ("golden",      "Midas Touch — finish a golden potato"),
            ("score10k",    "Five-Figure Fry — score 10,000+ in a run"),
            ("champion",    "World Champion — win the Championship"),
        };

        // ────────────────────────────────────────────────────────
        //  NEW GAME — choose a mode, then play it
        // ────────────────────────────────────────────────────────
        void NewGameFlow()
        {
            if (!ChooseMode()) return;        // ESC backed out
            ResetRun();
            switch (mode)
            {
                case GameMode.Endless:    RunEndless();       break;
                case GameMode.TimeAttack: RunTimeAttack();    break;
                case GameMode.Daily:      RunCampaign(true);  break;
                default:                  RunCampaign(false); break;
            }
        }

        bool ChooseMode()
        {
            for (;;)
            {
                Console.Clear();
                Ink(ConsoleColor.Yellow); Ctr("=== CHOOSE A MODE ==="); Console.WriteLine();
                Ink(ConsoleColor.White);
                Console.WriteLine("  [1]  Championship    6 stages, knife shop, win the title.");
                Console.WriteLine("  [2]  Endless         Infinite stages, ever faster. Survive.");
                Console.WriteLine("  [3]  Time Attack     60 seconds. Cut as much as you can.");
                Console.WriteLine("  [4]  Daily Challenge  Same seed for everyone, today only.");
                Console.WriteLine();
                Ink(ConsoleColor.Gray);
                Console.WriteLine("  Best scores:");
                Console.WriteLine("    Championship : " + save.BestFor("Championship"));
                Console.WriteLine("    Endless      : " + save.BestFor("Endless"));
                Console.WriteLine("    Time Attack  : " + save.BestFor("Time Attack"));
                Console.WriteLine("    Daily (" + DailySeedString() + ") : " + save.BestFor(DailyModeName()));
                Console.WriteLine();
                Console.WriteLine("  [ESC] Back");
                Console.ResetColor();

                switch (Console.ReadKey(true).Key)
                {
                    case ConsoleKey.D1: case ConsoleKey.NumPad1: mode = GameMode.Championship; return true;
                    case ConsoleKey.D2: case ConsoleKey.NumPad2: mode = GameMode.Endless;      return true;
                    case ConsoleKey.D3: case ConsoleKey.NumPad3: mode = GameMode.TimeAttack;   return true;
                    case ConsoleKey.D4: case ConsoleKey.NumPad4: mode = GameMode.Daily;        return true;
                    case ConsoleKey.Escape: return false;
                }
            }
        }

        void ResetRun()
        {
            score = 0; coins = 40; combo = 0; maxCombo = 0;
            fever = false; fvStr = 0; quit = false;
            lives = LIVES; dead = false; newBest = false;
            cP = cGr = cGd = cPo = cMs = cTotal = 0; rxnSum = 0.0;
            everFever = dodgedRotten = gotGolden = anyCleanStage = false;
            lastPlace = 0; newAchv.Clear(); completed.Clear();
            taClock = null;
            // Daily uses a date-seeded RNG so every player gets the same run.
            rng = mode == GameMode.Daily ? new Random(DailySeed()) : new Random();
        }

        // ── Daily seed helpers ────────────────────────────────────
        static int    DailySeed()       { var d = DateTime.Now; return d.Year * 10000 + d.Month * 100 + d.Day; }
        static string DailySeedString() => DateTime.Now.ToString("yyyy-MM-dd");
        static string DailyModeName()   => "Daily " + DailySeedString();

        string ModeName() => mode switch
        {
            GameMode.Endless    => "Endless",
            GameMode.TimeAttack => "Time Attack",
            GameMode.Daily      => DailyModeName(),
            _                   => "Championship",
        };

        // ────────────────────────────────────────────────────────
        //  CAMPAIGN  (Championship + Daily share this)
        // ────────────────────────────────────────────────────────
        void RunCampaign(bool daily)
        {
            for (int s = 0; s < SN.Length; s++)
            {
                stage = s;
                if (quit) break;
                BeginStage();
                StageIntro();
                if (quit) break;
                PlayStage();
                if (quit) break;
                if (dead) { GameOver(); return; }
                if (stage == SN.Length - 1)        // World Championship boss climax
                {
                    BossFight();
                    if (quit) break;
                    if (dead) { GameOver(); return; }
                }
                if (stageClean) anyCleanStage = true;
                CheckRecipe();
                coins += StageResult();
                if (s < SN.Length - 1 && !quit) RunShop();
            }
            if (!quit) Victory();
        }

        // ────────────────────────────────────────────────────────
        //  ENDLESS — stages keep coming, faster each time
        // ────────────────────────────────────────────────────────
        void RunEndless()
        {
            for (int s = 0; ; s++)
            {
                stage = s;
                if (quit) break;
                BeginStage();
                StageIntro();
                if (quit) break;
                PlayStage();
                if (quit) break;
                if (dead) { GameOver(); return; }
                if ((s + 1) % 5 == 0)              // a boss every 5 stages
                {
                    BossFight();
                    if (quit) break;
                    if (dead) { GameOver(); return; }
                }
                if (stageClean) anyCleanStage = true;
                CheckRecipe();
                coins += StageResult();
                if (!quit) RunShop();
            }
        }

        // ────────────────────────────────────────────────────────
        //  TIME ATTACK — 60 seconds, cut as much as possible
        // ────────────────────────────────────────────────────────
        void RunTimeAttack()
        {
            TimeAttackIntro();
            if (quit) return;

            stageBase = score; stageClean = true;
            taClock = Stopwatch.StartNew();
            int n = 0;
            while (!quit && !dead && taClock.Elapsed.TotalSeconds < 60.0)
            {
                // Speed ramps with elapsed time (stage index drives CurSpeed).
                stage = (int)(taClock.Elapsed.TotalSeconds / 12.0);
                int[] pool = CurPool;
                int id = rng.NextDouble() < GOLD_CHANCE ? GOLD : pool[rng.Next(pool.Length)];
                DoCutSequence(pots[id], ++n);
            }
            taClock = null;
            if (!quit) TimeUp();
        }

        void TimeAttackIntro()
        {
            Console.Clear();
            Ink(ConsoleColor.Yellow); Ctr(">> TIME ATTACK <<"); Console.WriteLine();
            Ink(ConsoleColor.White); Ctr("60 seconds. Cut as many potatoes as you can.");
            Ink(ConsoleColor.Gray);  Ctr("Misses still cost lives. Speed ramps over time.");
            Console.WriteLine();
            Ink(ConsoleColor.Gray); Console.WriteLine("  [SPACE] Start   [ESC] Quit to menu");
            Console.ResetColor();
            for (;;)
            {
                ConsoleKey k = Console.ReadKey(true).Key;
                if (k == ConsoleKey.Spacebar) return;
                if (k == ConsoleKey.Escape) { quit = true; return; }
            }
        }

        void TimeUp()
        {
            FinishRun(false);
            Snd(900, 120); Snd(700, 160);
            Console.Clear(); Console.WriteLine();
            Ink(ConsoleColor.Yellow);
            Ctr("##########################################");
            Ctr("#            T I M E   U P !             #");
            Ctr("##########################################");
            Console.WriteLine();
            Ink(ConsoleColor.White); Ctr("FINAL SCORE: " + score);
            if (newBest) { Ink(ConsoleColor.Green); Ctr("*** NEW TIME ATTACK BEST! ***"); }
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
        //  END-OF-RUN BOOKKEEPING
        // ────────────────────────────────────────────────────────
        void FinishRun(bool victory = false)
        {
            if (score > hiScore) { hiScore = score; newBest = true; }
            save.RecordBest(ModeName(), score);
            save.LifetimeCoins += coins;
            save.ChefXp        += score / 100;
            UnlockMetaKnives();
            CheckAchievements(victory);
            save.Save();

            if (Leaderboard.Qualifies(score))
            {
                string name = EnterName();
                lastPlace = Leaderboard.Add(name, score, ModeName(), GetRank(score));
            }
        }

        void CheckAchievements(bool victory)
        {
            void Try(string id) { if (save.Unlock(id)) newAchv.Add(LabelFor(id)); }

            if (everFever)                                          Try("first_fever");
            if (maxCombo >= 20)                                     Try("combo20");
            if (anyCleanStage)                                      Try("clean_stage");
            if (dodgedRotten)                                       Try("dodge_rot");
            if (gotGolden)                                          Try("golden");
            if (score >= 10000)                                    Try("score10k");
            if (victory && (mode == GameMode.Championship || mode == GameMode.Daily)) Try("champion");
        }

        static string LabelFor(string id)
        {
            foreach (var a in AchvList) if (a.Id == id) return a.Label;
            return id;
        }

        void ShowNewAchievements()
        {
            if (newAchv.Count == 0) return;
            Console.WriteLine();
            Ink(ConsoleColor.Magenta); Ctr("* ACHIEVEMENT UNLOCKED *");
            Ink(ConsoleColor.White);
            foreach (string a in newAchv) Ctr(a);
            Console.ResetColor();
        }

        // Arcade-style name entry (cursor is otherwise hidden during play).
        string EnterName()
        {
            Console.Clear(); Console.WriteLine();
            Ink(ConsoleColor.Yellow); Ctr("NEW LEADERBOARD SCORE!"); Console.WriteLine();
            Ink(ConsoleColor.White);  Ctr("Score: " + score + "   (" + ModeName() + ")"); Console.WriteLine();
            Ink(ConsoleColor.Gray);   Ctr("Type your name, then press [ENTER]:"); Console.ResetColor();
            Console.WriteLine(); Console.WriteLine();
            int row = Console.CursorTop;
            string name = "";
            for (;;)
            {
                try
                {
                    Console.SetCursorPosition(0, row);
                    Ink(ConsoleColor.Cyan);
                    Console.Write("        > " + name + "_                              ");
                    Console.ResetColor();
                }
                catch { }
                ConsoleKeyInfo ki = Console.ReadKey(true);
                if (ki.Key == ConsoleKey.Enter) break;
                if (ki.Key == ConsoleKey.Backspace) { if (name.Length > 0) name = name.Substring(0, name.Length - 1); }
                else if (!char.IsControl(ki.KeyChar) && name.Length < 12) name += ki.KeyChar;
            }
            name = name.Trim();
            return name.Length == 0 ? "YOU" : name;
        }

        // ────────────────────────────────────────────────────────
        //  BROWSE SCREENS
        // ────────────────────────────────────────────────────────
        void LeaderboardScreen()
        {
            Console.Clear();
            Ink(ConsoleColor.Yellow); Ctr("=== LEADERBOARD — TOP 10 ==="); Console.WriteLine();
            var l = Leaderboard.Load();
            if (l.Count == 0)
            {
                Ink(ConsoleColor.DarkGray); Ctr("No scores yet. Be the first!");
            }
            else
            {
                Ink(ConsoleColor.Gray);
                Console.WriteLine("    #   NAME           SCORE   MODE");
                int i = 1;
                foreach (var e in l)
                {
                    Ink(i == 1 ? ConsoleColor.Yellow : ConsoleColor.White);
                    Console.WriteLine("   " + i.ToString().PadLeft(2) + "   " +
                                      (e.Name ?? "").PadRight(12) + "  " +
                                      e.Score.ToString().PadLeft(6) + "   " + e.Mode);
                    i++;
                }
            }
            Console.WriteLine();
            Ink(ConsoleColor.Gray); Ctr("Press any key to go back...");
            Console.ResetColor();
            Console.ReadKey(true);
        }

        void AchievementsScreen()
        {
            Console.Clear();
            Ink(ConsoleColor.Yellow); Ctr("=== ACHIEVEMENTS ==="); Console.WriteLine();
            int got = 0;
            foreach (var a in AchvList)
            {
                bool have = save.Has(a.Id);
                if (have) got++;
                Ink(have ? ConsoleColor.Green : ConsoleColor.DarkGray);
                Console.WriteLine("   [" + (have ? "x" : " ") + "] " + a.Label);
            }
            Console.WriteLine();
            Ink(ConsoleColor.Gray); Ctr(got + " / " + AchvList.Length + " unlocked");
            Console.WriteLine();
            Ctr("Press any key to go back...");
            Console.ResetColor();
            Console.ReadKey(true);
        }

        // ── Meta unlocks (knives bought across runs with Chef XP) ──
        void ApplyMetaUnlocks()
        {
            foreach (string nm in save.UnlockedKnives)
                for (int i = 0; i < knives.Length; i++)
                    if (knives[i].Name == nm) kOwned[i] = true;
        }
    }
}
