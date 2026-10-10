/*
 * Audio — little synthesized chimes, pulled in with
 * `using static PotatoSlicer.Audio;` so call sites read `Snd(freq, dur)`.
 *
 * Windows plays them through Console.Beep. Elsewhere Console.Beep is only the
 * terminal bell, so on Linux/macOS each phrase is rendered as a tiny WAV in
 * the temp folder and handed to the system player (paplay / pw-play / aplay
 * / afplay), falling back to the bell when none is installed.
 *
 * Notes go through a queue drained by one background thread: Snd() never
 * blocks the game loop, and notes queued back-to-back (a three-note
 * fanfare) are played in order as one phrase rather than as a chord.
 */
using System;
using System.Collections.Concurrent;
using System.Collections.Generic;
using System.Diagnostics;
using System.IO;
using System.Threading;

namespace PotatoSlicer
{
    static class Audio
    {
        public static bool Enabled = true;

        const int RATE = 22050;
        static readonly BlockingCollection<int[]> queue = new BlockingCollection<int[]>(64);
        static readonly object startLock = new object();
        static Thread worker;
        static string player;          // resolved on first use; "" = none found
        static int fileCounter;

        public static void Snd(int freq, int dur)
        {
            if (!Enabled || dur <= 0) return;
            EnsureWorker();
            queue.TryAdd(new[] { freq, dur });   // a full queue just drops the note
        }

        static void EnsureWorker()
        {
            lock (startLock)
            {
                if (worker != null) return;
                worker = new Thread(Run) { IsBackground = true, Name = "sliceit-audio" };
                worker.Start();
            }
        }

        static void Run()
        {
            foreach (int[] first in queue.GetConsumingEnumerable())
            {
                // gather the notes queued right behind this one into a phrase
                var notes = new List<int[]> { first };
                while (queue.TryTake(out int[] more, 4)) notes.Add(more);
                try { Play(notes); }
                catch { /* no audio device, player crashed, temp dir read-only… */ }
            }
        }

        static void Play(List<int[]> notes)
        {
            int total = 0;
            foreach (int[] n in notes) total += n[1];

            if (OperatingSystem.IsWindows())
            {
                foreach (int[] n in notes) Console.Beep(Math.Clamp(n[0], 37, 32767), n[1]);
                return;
            }

            if (player == null) player = FindPlayer() ?? "";
            if (player == "")
            {
                Console.Beep();
                Thread.Sleep(total);
                return;
            }

            string path = Path.Combine(Path.GetTempPath(),
                "sliceit-" + Environment.ProcessId + "-" + Interlocked.Increment(ref fileCounter) + ".wav");
            File.WriteAllBytes(path, RenderWav(notes));
            try
            {
                var psi = new ProcessStartInfo(player)
                {
                    UseShellExecute = false,
                    RedirectStandardOutput = true,
                    RedirectStandardError = true,
                    CreateNoWindow = true,
                };
                if (Path.GetFileName(player) == "aplay") psi.ArgumentList.Add("-q");
                psi.ArgumentList.Add(path);
                using (Process proc = Process.Start(psi))
                    proc?.WaitForExit(total + 3000);
            }
            finally
            {
                try { File.Delete(path); } catch { /* best effort */ }
            }
        }

        // First audio player on PATH (afplay ships with every Mac).
        static string FindPlayer()
        {
            string[] candidates = OperatingSystem.IsMacOS()
                ? new[] { "afplay" }
                : new[] { "paplay", "pw-play", "aplay" };
            string pathVar = Environment.GetEnvironmentVariable("PATH") ?? "";
            foreach (string name in candidates)
            {
                foreach (string dir in pathVar.Split(Path.PathSeparator))
                {
                    if (dir.Length == 0) continue;
                    string full = Path.Combine(dir, name);
                    if (File.Exists(full)) return full;
                }
            }
            return null;
        }

        // A soft square-ish tone per note (filtered, with short fades so the
        // phrase doesn't click), packed as a 16-bit mono WAV.
        static byte[] RenderWav(List<int[]> notes)
        {
            var samples = new List<short>();
            foreach (int[] n in notes)
            {
                int len = Math.Max(1, n[1] * RATE / 1000);
                int fade = Math.Min(len / 2, RATE / 250);   // 4 ms
                double ph = 0, inc = n[0] / (double)RATE, y = 0;
                for (int i = 0; i < len; i++)
                {
                    double v = ph < 0.5 ? 1.0 : -1.0;
                    ph += inc;
                    if (ph >= 1) ph -= 1;
                    y += 0.25 * (v - y);                     // one-pole low-pass: rounder tone
                    double env = 1.0;
                    if (i < fade) env = i / (double)fade;
                    else if (i > len - fade) env = (len - i) / (double)fade;
                    samples.Add((short)(y * env * 0.22 * short.MaxValue));
                }
            }
            using var ms = new MemoryStream();
            using var w = new BinaryWriter(ms);
            int dataLen = samples.Count * 2;
            w.Write(new[] { (byte)'R', (byte)'I', (byte)'F', (byte)'F' });
            w.Write(36 + dataLen);
            w.Write(new[] { (byte)'W', (byte)'A', (byte)'V', (byte)'E', (byte)'f', (byte)'m', (byte)'t', (byte)' ' });
            w.Write(16);                 // PCM header size
            w.Write((short)1);           // PCM
            w.Write((short)1);           // mono
            w.Write(RATE);
            w.Write(RATE * 2);           // byte rate
            w.Write((short)2);           // block align
            w.Write((short)16);          // bits
            w.Write(new[] { (byte)'d', (byte)'a', (byte)'t', (byte)'a' });
            w.Write(dataLen);
            foreach (short s in samples) w.Write(s);
            w.Flush();
            return ms.ToArray();
        }
    }
}
