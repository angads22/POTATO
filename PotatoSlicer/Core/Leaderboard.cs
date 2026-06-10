/*
 * Leaderboard — a local top-10 table stored as leaderboard.json next to the
 * binary. Replaces the old single highscore.txt. Best-effort file access.
 */
using System;
using System.Collections.Generic;
using System.IO;
using System.Linq;
using System.Text.Json;

namespace PotatoSlicer
{
    sealed class LbEntry
    {
        public string Name { get; set; } = "AAA";
        public int    Score { get; set; }
        public string Mode { get; set; } = "";
        public string Rank { get; set; } = "";
    }

    static class Leaderboard
    {
        const int CAP = 10;
        static string FilePath => Path.Combine(AppContext.BaseDirectory, "leaderboard.json");

        public static List<LbEntry> Load()
        {
            try
            {
                if (File.Exists(FilePath))
                    return JsonSerializer.Deserialize<List<LbEntry>>(File.ReadAllText(FilePath)) ?? new List<LbEntry>();
            }
            catch { }
            return new List<LbEntry>();
        }

        static void Save(List<LbEntry> entries)
        {
            try
            {
                File.WriteAllText(FilePath,
                    JsonSerializer.Serialize(entries, new JsonSerializerOptions { WriteIndented = true }));
            }
            catch { }
        }

        public static bool Qualifies(int score)
        {
            if (score <= 0) return false;
            var l = Load();
            return l.Count < CAP || score > l.Min(e => e.Score);
        }

        // Inserts an entry, trims to the top CAP, and returns its 1-based
        // placement (0 if it did not make the cut).
        public static int Add(string name, int score, string mode, string rank)
        {
            var l = Load();
            var entry = new LbEntry { Name = name, Score = score, Mode = mode, Rank = rank };
            l.Add(entry);
            l = l.OrderByDescending(e => e.Score).Take(CAP).ToList();
            Save(l);
            int idx = l.IndexOf(entry);
            return idx < 0 ? 0 : idx + 1;
        }
    }
}
