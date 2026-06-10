/*
 * Knife — affects bar speed and zone widths.
 *
 *   Cps      : bar speed in characters-per-second
 *   Ph/Gh/Gd : half-widths of Perfect / Great / Good zones
 *              (effective half = max(min, round(base / potatoHardness)))
 */
using System;

namespace PotatoSlicer
{
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
}
