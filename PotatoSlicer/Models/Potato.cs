/*
 * Potato — the thing being cut.
 *
 *   Hard    : hardness multiplier (>1.0 = smaller effective zones)
 *   Chaotic : bar randomly reverses direction (sweet potato behaviour)
 *   Cut     : which minigame this potato uses (default Sweep). Set via the
 *             object initializer in GameData so existing constructor calls stay
 *             unchanged.
 */
using System;

namespace PotatoSlicer
{
    sealed class Potato
    {
        public string       Name, Quip, Fact;
        public int          Cuts;      // cuts required to complete
        public int          Base;      // base points per perfect cut
        public double       Hard;
        public bool         Chaotic;
        public ConsoleColor Color;
        public string[]     Art;       // 5-line ASCII art

        public CutType      Cut = CutType.Sweep;   // minigame selector
        public bool         Hazard;                // true for the rotten potato

        public Potato(string name, string quip, string fact,
                      int cuts, int pts, double hard, bool chaotic,
                      ConsoleColor col, string[] art)
        { Name=name; Quip=quip; Fact=fact; Cuts=cuts; Base=pts;
          Hard=hard; Chaotic=chaotic; Color=col; Art=art; }
    }
}
