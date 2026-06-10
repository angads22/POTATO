/*
 * Audio — tones on Windows, terminal bell elsewhere. Pulled in with
 * `using static PotatoSlicer.Audio;` so call sites read `Snd(freq, dur)`.
 */
using System;

namespace PotatoSlicer
{
    static class Audio
    {
        public static bool Enabled = true;

        public static void Snd(int freq, int dur)
        {
            if (!Enabled) return;
            try
            {
                if (OperatingSystem.IsWindows()) Console.Beep(freq, dur);
                else Console.Beep();
            }
            catch { /* no console / no audio device */ }
        }
    }
}
