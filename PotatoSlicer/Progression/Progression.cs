/*
 * Game.Progression — the depth layer: per-stage recipe orders, consumable
 * power-ups (bought in the shop, activated before a potato), Chef-XP meta
 * unlocks that persist across runs, and the end-of-stage boss potato.
 */
using System;
using System.Threading;
using static PotatoSlicer.Render;
using static PotatoSlicer.Audio;
using static PotatoSlicer.Scoring;
using static PotatoSlicer.GameData;

namespace PotatoSlicer
{
    sealed partial class Game
    {
        // ── Recipe orders (per-stage bonus objective) ─────────────
        enum RecipeKind { Clean, Perfects, StageScore, Combo }
        struct Recipe { public RecipeKind Kind; public int Target; public int Reward; public string Desc; }

        Recipe curRecipe;
        int    stagePerfectBase;   // cP snapshot at stage start
        int    stageMaxCombo;      // best combo reached this stage
        int    recipeBonusGiven;   // coins awarded by the order this stage

        // ── Power-up inventory + pending effects ──────────────────
        int  puSharp, puSlow, puLife, puShield;
        bool pendingSharp, pendingSlow, shieldActive;
        const int PRICE_SHARP = 20, PRICE_SLOW = 25, PRICE_LIFE = 40, PRICE_SHIELD = 30;

        // ────────────────────────────────────────────────────────
        //  STAGE SETUP / RECIPE
        // ────────────────────────────────────────────────────────
        void BeginStage()
        {
            stageBase        = score;
            stageClean       = true;
            stagePerfectBase = cP;
            stageMaxCombo    = 0;
            recipeBonusGiven = 0;
            NewRecipe();
        }

        void NewRecipe()
        {
            switch (rng.Next(4))
            {
                case 0:
                    curRecipe = new Recipe { Kind = RecipeKind.Clean, Target = 0, Reward = 40,
                        Desc = "Clean plate — finish the stage with NO misses" };
                    break;
                case 1:
                    int t = 2 + stage / 2;
                    curRecipe = new Recipe { Kind = RecipeKind.Perfects, Target = t, Reward = 30 + 10 * t,
                        Desc = "Precision — land " + t + " PERFECT cuts" };
                    break;
                case 2:
                    int sc = 400 + stage * 150;
                    curRecipe = new Recipe { Kind = RecipeKind.StageScore, Target = sc, Reward = 50,
                        Desc = "Big plate — score " + sc + "+ this stage" };
                    break;
                default:
                    int c = 6 + stage;
                    curRecipe = new Recipe { Kind = RecipeKind.Combo, Target = c, Reward = 40,
                        Desc = "Keep the chain — reach a x" + c + " combo" };
                    break;
            }
        }

        void CheckRecipe()
        {
            bool ok;
            switch (curRecipe.Kind)
            {
                case RecipeKind.Clean:      ok = stageClean;                                break;
                case RecipeKind.Perfects:   ok = (cP - stagePerfectBase) >= curRecipe.Target; break;
                case RecipeKind.StageScore: ok = (score - stageBase) >= curRecipe.Target;   break;
                default:                    ok = stageMaxCombo >= curRecipe.Target;          break;
            }
            if (ok) { coins += curRecipe.Reward; recipeBonusGiven = curRecipe.Reward; }
            else      recipeBonusGiven = 0;
        }

        // Completion tally (used for stats / potential future orders).
        void RecordCompleted(Potato p)
        {
            int id = Array.IndexOf(pots, p);
            if (id < 0) return;
            completed[id] = completed.TryGetValue(id, out int c) ? c + 1 : 1;
        }

        // ────────────────────────────────────────────────────────
        //  POWER-UPS  — optional activation before a potato
        // ────────────────────────────────────────────────────────
        void MaybeUsePowerUp(Potato p)
        {
            if (puSharp + puSlow + puLife + puShield == 0) return;

            Console.Clear();
            Ink(ConsoleColor.Yellow); Ctr("POWER-UPS"); Console.WriteLine();
            Ink(ConsoleColor.White);  Ctr("Coming up: " + p.Name);
            Console.WriteLine(); Console.WriteLine();
            if (puSharp > 0)  Console.WriteLine("  [1] Sharpening Stone x" + puSharp + "   — this potato's zones +50%");
            if (puSlow > 0)   Console.WriteLine("  [2] Slow-Mo x" + puSlow + "           — this potato at half speed");
            if (puLife > 0)   Console.WriteLine("  [3] Extra Life x" + puLife + "         — gain +1 life now");
            if (puShield > 0) Console.WriteLine("  [4] Combo Shield x" + puShield + "      — your next miss is forgiven");
            Console.WriteLine();
            Ink(ConsoleColor.Gray); Ctr("Press a number to use one, or [SPACE] to continue.");
            Console.ResetColor();

            for (;;)
            {
                ConsoleKey k = Console.ReadKey(true).Key;
                if (k == ConsoleKey.Spacebar || k == ConsoleKey.Escape) return;
                if ((k == ConsoleKey.D1 || k == ConsoleKey.NumPad1) && puSharp > 0)
                { puSharp--; pendingSharp = true; PuToast("Sharpening Stone ready!"); return; }
                if ((k == ConsoleKey.D2 || k == ConsoleKey.NumPad2) && puSlow > 0)
                { puSlow--; pendingSlow = true; PuToast("Slow-Mo engaged!"); return; }
                if ((k == ConsoleKey.D3 || k == ConsoleKey.NumPad3) && puLife > 0)
                { puLife--; lives++; PuToast("+1 life! (" + new string('♥', lives) + ")"); return; }
                if ((k == ConsoleKey.D4 || k == ConsoleKey.NumPad4) && puShield > 0)
                { puShield--; shieldActive = true; PuToast("Combo Shield armed!"); return; }
            }
        }

        void PuToast(string msg)
        {
            Ink(ConsoleColor.Green); Ctr(msg); Console.ResetColor();
            Snd(1000, 70);
            Thread.Sleep(650);
        }

        // Power-up purchasing — called from the knife shop's input handler.
        // Returns true if the key was a power-up action.
        bool TryBuyPowerUp(ConsoleKey k)
        {
            switch (k)
            {
                case ConsoleKey.Q: return BuyPu(ref puSharp,  PRICE_SHARP,  "Sharpening Stone");
                case ConsoleKey.W: return BuyPu(ref puSlow,   PRICE_SLOW,   "Slow-Mo");
                case ConsoleKey.E: return BuyPu(ref puLife,   PRICE_LIFE,   "Extra Life");
                case ConsoleKey.R: return BuyPu(ref puShield, PRICE_SHIELD, "Combo Shield");
            }
            return false;
        }

        bool BuyPu(ref int slot, int price, string name)
        {
            if (coins >= price) { coins -= price; slot++; Ink(ConsoleColor.Green); Ctr("Bought " + name + "!"); Snd(1000, 80); }
            else                { Ink(ConsoleColor.Red); Ctr("Not enough coins!"); }
            Console.ResetColor();
            Thread.Sleep(600);
            return true;
        }

        // ── Meta-progression: permanent knife unlocks via Chef XP ──
        void UnlockMetaKnives()
        {
            void U(string name)
            {
                if (save.UnlockedKnives.Contains(name)) return;
                save.UnlockedKnives.Add(name);
                for (int i = 0; i < knives.Length; i++)
                    if (knives[i].Name == name) kOwned[i] = true;
                newAchv.Add("Knife permanently unlocked: " + name);
            }
            if (save.ChefXp >= 150) U("Gyuto");
            if (save.ChefXp >= 400) U("Damascus Steel");
        }

        // ────────────────────────────────────────────────────────
        //  BOSS POTATO  — climax of a stage
        // ────────────────────────────────────────────────────────
        void BossFight()
        {
            Knife  k  = knives[kEq];
            double sm = CurSpeed * 1.1;
            Potato boss = pots[5];           // borrow King Edward's chunky art
            int maxHp = 10, hp = maxHp;

            Console.Clear(); Console.WriteLine();
            Ink(ConsoleColor.Red);
            Ctr("############################################");
            Ctr("#        !!  B O S S   P O T A T O  !!     #");
            Ctr("#          THE COLOSSAL SPUD               #");
            Ctr("############################################");
            Console.WriteLine();
            Ink(ConsoleColor.White); Ctr("It has " + maxHp + " HP. Whittle it down before it whittles you.");
            Ink(ConsoleColor.Gray);  Ctr("PERFECT = -3 HP   GREAT = -2   GOOD = -1   MISS = costs a life");
            Console.WriteLine();
            Ink(ConsoleColor.Gray);  Ctr("[SPACE] Begin   [ESC] Quit to menu");
            Console.ResetColor();
            for (;;)
            {
                ConsoleKey kk = Console.ReadKey(true).Key;
                if (kk == ConsoleKey.Spacebar) break;
                if (kk == ConsoleKey.Escape) { quit = true; return; }
            }

            int ph = Math.Max(2, k.Ph / 2), gh = Math.Max(4, k.Gh / 2), gd = Math.Max(6, k.Gd / 2);

            while (hp > 0 && !quit && !dead)
            {
                DrawBossField(hp, maxHp);
                int barRow = Console.CursorTop;
                Console.WriteLine(); Console.WriteLine(); Console.WriteLine();

                CutQuality q; double rxn;
                AnimBar(boss, k, sm, ph, gh, gd, barRow, out q, out rxn);
                if (quit) return;

                int dmg = q == CutQuality.Perfect ? 3 : q == CutQuality.Great ? 2 : q == CutQuality.Good ? 1 : 0;
                int pts = CalcPts(q, 200, combo, fever);
                UpdStats(q);
                score += pts; cTotal++; rxnSum += rxn;
                hp = Math.Max(0, hp - dmg);

                Console.SetCursorPosition(0, barRow + 3);
                PrintResult(q, pts, rxn, false);
                if (dmg > 0) { Ink(ConsoleColor.Red); Ctr("-" + dmg + " HP!  (" + hp + " left)"); Console.ResetColor(); }

                if (q == CutQuality.Miss)
                {
                    if (shieldActive) { shieldActive = false; Ink(ConsoleColor.Cyan); Ctr("COMBO SHIELD! Miss forgiven."); Console.ResetColor(); }
                    else
                    {
                        lives--;
                        Ink(ConsoleColor.Red);
                        Ctr(lives > 0 ? "-1 life!  (" + new string('♥', lives) + " left)" : "OUT OF LIVES!");
                        Console.ResetColor();
                        if (lives <= 0) { Snd(150, 400); Thread.Sleep(1200); dead = true; return; }
                    }
                }
                Thread.Sleep(750);
            }

            if (hp <= 0 && !dead)
            {
                score += 1000; coins += 100;
                Snd(900, 120); Snd(1200, 120); Snd(1500, 220);
                Ink(ConsoleColor.Yellow);
                Ctr("THE COLOSSAL SPUD IS VANQUISHED!");
                Ctr("+1000 points and +100 coins!");
                Console.ResetColor();
                Thread.Sleep(1800);
            }
        }

        void DrawBossField(int hp, int maxHp)
        {
            Console.Clear();
            Ink(ConsoleColor.DarkGray);
            Console.Write("  BOSS FIGHT   ");
            Ink(ConsoleColor.Yellow); Console.Write("Score: " + score + "   ");
            Ink(ConsoleColor.Cyan);   Console.Write("Combo: x" + Math.Max(1, combo) + "   ");
            Ink(ConsoleColor.Red);    Console.Write(new string('♥', Math.Max(0, lives)));
            if (fever) { Ink(ConsoleColor.Magenta); Console.Write("   [FEVER 2x]"); }
            Console.ResetColor(); Console.WriteLine(); Console.WriteLine();

            Ink(ConsoleColor.White);
            Ctr("   .====================.");
            Ctr("  / ||  ||  ||  ||  ||  \\");
            Ctr(" |  ||  (><)  ||  ||   |");
            Ctr(" |  ||  ||  ||  ||  ||  |");
            Ctr("  \\ ||  ||  ||  ||  || /");
            Ctr("   `===================='");
            Console.WriteLine();

            // HP bar
            const int w = 40;
            int filled = (int)Math.Round((double)hp / maxHp * w);
            Console.Write("  HP [");
            Ink(ConsoleColor.Red);      Console.Write(new string('█', filled));
            Ink(ConsoleColor.DarkGray); Console.Write(new string('.', w - filled));
            Ink(ConsoleColor.Gray);     Console.Write("] " + hp + "/" + maxHp);
            Console.ResetColor(); Console.WriteLine(); Console.WriteLine();

            Ink(ConsoleColor.Gray); Ctr("PERFECT -3   GREAT -2   GOOD -1    [SPACE] strike");
            Console.WriteLine();
        }
    }
}
