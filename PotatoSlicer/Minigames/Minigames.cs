/*
 * Game.Minigames — the per-cut challenges. Each returns one (CutQuality, rxnMs)
 * so the scoring/lives/combo flow in DoCutSequence is identical regardless of
 * which mechanic ran. DispatchCut picks the mechanic from the potato's CutType.
 *
 *   Sweep        : classic bar (AnimBar) — the default
 *   ShrinkZone   : AnimBar with contracting sweet spots
 *   HoldRelease  : "peel" — tap to start a rising fill, tap again to lock it
 *   MultiTarget  : "julienne" — two quick taps, scored as the worse of the two
 *   Dodge        : "rotten" — pressing SPACE is WRONG; press [X] to bin it
 */
using System;
using System.Diagnostics;
using System.Threading;
using static PotatoSlicer.Render;
using static PotatoSlicer.Audio;
using static PotatoSlicer.Scoring;

namespace PotatoSlicer
{
    sealed partial class Game
    {
        // ────────────────────────────────────────────────────────
        //  DISPATCHER — route to the right mechanic
        // ────────────────────────────────────────────────────────
        void DispatchCut(Potato p, Knife k, double sm,
                         int ph, int gh, int gd, int barRow,
                         out CutQuality q, out double rxn)
        {
            switch (p.Cut)
            {
                case CutType.ShrinkZone:
                    AnimBar(p, k, sm, ph, gh, gd, barRow, out q, out rxn, 0.18);
                    break;
                case CutType.HoldRelease:
                    HoldReleaseCut(k, sm, ph, gh, gd, barRow, out q, out rxn);
                    break;
                case CutType.MultiTarget:
                    MultiTargetCut(k, sm, ph, gh, gd, barRow, out q, out rxn);
                    break;
                case CutType.Dodge:
                    DodgeCut(barRow, out q, out rxn);
                    break;
                default:
                    AnimBar(p, k, sm, ph, gh, gd, barRow, out q, out rxn);
                    break;
            }
        }

        // ────────────────────────────────────────────────────────
        //  HOLD & RELEASE  ("peel")
        //  A fill gauge rises left→right. Tap SPACE to start it, tap again to
        //  lock. Locking near centre = Perfect; overfilling past the bar = Miss.
        // ────────────────────────────────────────────────────────
        void HoldReleaseCut(Knife k, double sm, int ph, int gh, int gd,
                            int barRow, out CutQuality q, out double rxn)
        {
            q = CutQuality.Miss; rxn = 5000.0;
            double fillCps = k.Cps * sm * 0.55;   // a touch slower than a sweep

            while (Console.KeyAvailable) Console.ReadKey(true);

            // Phase 1: wait for the player to start the fill.
            bool started = false;
            while (!started)
            {
                try
                {
                    Console.SetCursorPosition(0, barRow);
                    DrawBar(0, ph, gh, gd, false, -1);
                    Console.SetCursorPosition(0, barRow + 1);
                    Ink(ConsoleColor.DarkGray);
                    Console.Write("  PEEL: tap [SPACE] to start the peel...                       ");
                    Console.ResetColor();
                }
                catch { }
                if (Console.KeyAvailable)
                {
                    ConsoleKey kk = Console.ReadKey(true).Key;
                    if (kk == ConsoleKey.Spacebar) started = true;
                    else if (kk == ConsoleKey.Escape)
                    {
                        if (ConfirmQuit(barRow)) { quit = true; q = CutQuality.Miss; rxn = 0.0; return; }
                    }
                }
                Thread.Sleep(14);
            }

            // Phase 2: the fill rises; tap again to lock it.
            Stopwatch sw = Stopwatch.StartNew();
            for (;;)
            {
                double t    = sw.Elapsed.TotalSeconds;
                double fill = fillCps * t;

                if (fill >= Layout.BAR - 1)   // overcooked — let it run off the end
                {
                    rxn = sw.Elapsed.TotalMilliseconds;
                    q   = CutQuality.Miss;
                    try { Console.SetCursorPosition(0, barRow); DrawBar(Layout.BAR - 1, ph, gh, gd, true, Layout.BAR - 1); } catch { }
                    return;
                }

                try
                {
                    Console.SetCursorPosition(0, barRow);
                    DrawBar((int)fill, ph, gh, gd, false, -1);
                    Console.SetCursorPosition(0, barRow + 1);
                    Ink(ConsoleColor.DarkGray);
                    Console.Write("  PEEL rising — tap [SPACE] to lock it at the centre!          ");
                    Console.ResetColor();
                }
                catch { }

                if (Console.KeyAvailable)
                {
                    ConsoleKey kk = Console.ReadKey(true).Key;
                    if (kk == ConsoleKey.Spacebar)
                    {
                        rxn = sw.Elapsed.TotalMilliseconds;
                        q   = EvalCut((int)fill, ph, gh, gd);
                        try { Console.SetCursorPosition(0, barRow); DrawBar((int)fill, ph, gh, gd, true, (int)fill); } catch { }
                        return;
                    }
                    if (kk == ConsoleKey.Escape)
                    {
                        if (ConfirmQuit(barRow)) { quit = true; q = CutQuality.Miss; rxn = 0.0; return; }
                        sw.Restart();
                    }
                }
                Thread.Sleep(14);
            }
        }

        // ────────────────────────────────────────────────────────
        //  MULTI-TARGET  ("julienne")
        //  The bar sweeps continuously; land TWO taps. The cut is scored as the
        //  worse of the two, so only all-on-target earns a Perfect.
        // ────────────────────────────────────────────────────────
        void MultiTargetCut(Knife k, double sm, int ph, int gh, int gd,
                           int barRow, out CutQuality q, out double rxn)
        {
            const int need = 2;
            q = CutQuality.Miss; rxn = 6000.0;

            double cps = k.Cps * sm;
            double pos = 0.0, dir = 1.0, prev = 0.0;

            while (Console.KeyAvailable) Console.ReadKey(true);
            Stopwatch sw = Stopwatch.StartNew();

            CutQuality worst = CutQuality.Perfect;
            int got = 0; double lastRxn = 6000.0;

            for (;;)
            {
                double t  = sw.Elapsed.TotalSeconds;
                double dt = t - prev; prev = t;

                pos += dir * cps * dt;
                if (pos >= Layout.BAR - 1) { pos = Layout.BAR - 1.001; dir = -1.0; }
                if (pos <= 0.0)            { pos = 0.001;              dir =  1.0; }

                try
                {
                    Console.SetCursorPosition(0, barRow);
                    DrawBar((int)pos, ph, gh, gd, false, -1);
                    Console.SetCursorPosition(0, barRow + 1);
                    Ink(ConsoleColor.DarkGray);
                    Console.Write("  JULIENNE: tap " + (got + 1) + "/" + need +
                                  "  |  Timeout: " + Math.Max(0.0, 6.0 - t).ToString("F1") + "s        ");
                    Console.ResetColor();
                }
                catch { }

                if (Console.KeyAvailable)
                {
                    ConsoleKey kk = Console.ReadKey(true).Key;
                    if (kk == ConsoleKey.Spacebar)
                    {
                        CutQuality qq = EvalCut((int)pos, ph, gh, gd);
                        if ((int)qq < (int)worst) worst = qq;
                        got++; lastRxn = sw.Elapsed.TotalMilliseconds;
                        Snd(700 + got * 120, 60);
                        if (got >= need)
                        {
                            rxn = lastRxn; q = worst;
                            try { Console.SetCursorPosition(0, barRow); DrawBar((int)pos, ph, gh, gd, true, (int)pos); } catch { }
                            return;
                        }
                    }
                    else if (kk == ConsoleKey.Escape)
                    {
                        if (ConfirmQuit(barRow)) { quit = true; q = CutQuality.Miss; rxn = 0.0; return; }
                        sw.Restart(); prev = 0.0; got = 0; worst = CutQuality.Perfect;
                    }
                }

                if (t > 6.0) { rxn = lastRxn; q = got > 0 ? worst : CutQuality.Miss; return; }
                Thread.Sleep(14);
            }
        }

        // ────────────────────────────────────────────────────────
        //  DODGE  ("rotten potato")
        //  Pressing SPACE here is the WRONG move (you sliced a rotten spud).
        //  Press [X] to bin it — fast = Perfect, otherwise Great. Hesitating
        //  past the timer spoils your station (Poor).
        // ────────────────────────────────────────────────────────
        void DodgeCut(int barRow, out CutQuality q, out double rxn)
        {
            q = CutQuality.Poor; rxn = 4000.0;
            while (Console.KeyAvailable) Console.ReadKey(true);
            Stopwatch sw = Stopwatch.StartNew();

            for (;;)
            {
                double t = sw.Elapsed.TotalSeconds;
                try
                {
                    bool on = ((int)(t * 4)) % 2 == 0;
                    Console.SetCursorPosition(0, barRow);
                    Ink(on ? ConsoleColor.Red : ConsoleColor.DarkRed);
                    Console.Write("  !! ROTTEN — DO NOT SLICE !!   press [X] to bin it            ");
                    Console.ResetColor();
                    Console.SetCursorPosition(0, barRow + 1);
                    Ink(ConsoleColor.DarkGray);
                    Console.Write("  Timeout: " + Math.Max(0.0, 4.0 - t).ToString("F1") +
                                  "s  (hesitate and it spoils your station)        ");
                    Console.ResetColor();
                }
                catch { }

                if (Console.KeyAvailable)
                {
                    ConsoleKey kk = Console.ReadKey(true).Key;
                    if (kk == ConsoleKey.X)
                    {
                        rxn = sw.Elapsed.TotalMilliseconds;
                        q   = rxn < 1500.0 ? CutQuality.Perfect : CutQuality.Great;
                        dodgedRotten = true;
                        Snd(1000, 90);
                        return;
                    }
                    if (kk == ConsoleKey.Spacebar)   // sliced the rotten one — bad
                    {
                        rxn = sw.Elapsed.TotalMilliseconds;
                        q   = CutQuality.Miss;
                        Snd(150, 220);
                        return;
                    }
                    if (kk == ConsoleKey.Escape)
                    {
                        if (ConfirmQuit(barRow)) { quit = true; q = CutQuality.Miss; rxn = 0.0; return; }
                        sw.Restart();
                    }
                }

                if (t > 4.0) { q = CutQuality.Poor; rxn = 4000.0; return; }
                Thread.Sleep(14);
            }
        }
    }
}
