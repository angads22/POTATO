/*
 * Scoring — pure cut-evaluation and point math. Kept free of game state so it
 * is easy to reason about (and unit-test later). Pulled in with
 * `using static PotatoSlicer.Scoring;`.
 *
 *   pts        = basePts x qualMult x comboBonus x feverBonus
 *   comboBonus = 1.0 + min(combo, 20) x 0.05   [cap 2.0 at combo=20]
 *   feverBonus = 2.0 when in fever, else 1.0
 */
using System;

namespace PotatoSlicer
{
    static class Scoring
    {
        // Map a bar position to a quality band given the three zone half-widths.
        public static CutQuality EvalCut(int pos, int ph, int gh, int gd)
        {
            int d = Math.Abs(pos - Layout.CTR);
            if (d <= ph)     return CutQuality.Perfect;
            if (d <= gh)     return CutQuality.Great;
            if (d <= gd)     return CutQuality.Good;
            if (d <= gd + 4) return CutQuality.Poor;
            return CutQuality.Miss;
        }

        public static int CalcPts(CutQuality q, int basePts, int combo, bool fever)
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

        public static string GetRank(int s)
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
    }
}
