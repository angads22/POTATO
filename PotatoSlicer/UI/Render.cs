/*
 * Render — shared console-drawing helpers and layout constants.
 *
 * Game files pull these in with `using static PotatoSlicer.Render;` so the
 * call sites read `Ctr(...)`, `Ink(...)`, `DrawBar(...)` exactly as before.
 */
using System;

namespace PotatoSlicer
{
    static class Layout
    {
        public const int BAR   = 50;   // bar width in characters
        public const int CTR    = 25;   // bar centre index
        public const int SCR_W  = 74;   // width used for centring text
    }

    static class Render
    {
        public static void Ink(ConsoleColor c) => Console.ForegroundColor = c;

        public static void Ctr(string s)
        {
            int pad = Math.Max(0, (Layout.SCR_W - s.Length) / 2);
            Console.WriteLine(new string(' ', pad) + s);
        }

        // Bar renderer. frozen=true draws a frozen cut marker at cp instead of
        // the moving cursor.
        public static void DrawBar(int cursor, int ph, int gh, int gd, bool frozen, int cp)
        {
            Console.Write("  [");
            for (int x = 0; x < Layout.BAR; x++)
            {
                int dist = Math.Abs(x - Layout.CTR);

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
                else if (dist <= ph) { Ink(ConsoleColor.White);    Console.Write('█'); } // full block
                else if (dist <= gh) { Ink(ConsoleColor.Green);    Console.Write('▓'); } // dark shade
                else if (dist <= gd) { Ink(ConsoleColor.Yellow);   Console.Write('░'); } // light shade
                else                 { Ink(ConsoleColor.DarkGray); Console.Write('.'); }
            }
            Ink(ConsoleColor.Gray); Console.Write("]"); Console.ResetColor();
        }
    }
}
