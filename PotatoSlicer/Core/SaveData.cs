/*
 * SaveData — persistent profile stored as savedata.json next to the binary.
 * Holds per-mode best scores, unlocked achievements, and lifetime/meta
 * progression. All file access is best-effort: a missing or corrupt file just
 * yields a fresh profile (same tolerance as the original highscore loader).
 */
using System;
using System.Collections.Generic;
using System.IO;
using System.Text.Json;

namespace PotatoSlicer
{
    sealed class SaveData
    {
        public Dictionary<string, int> Best { get; set; } = new Dictionary<string, int>();
        public List<string> Achievements    { get; set; } = new List<string>();
        public List<string> UnlockedKnives  { get; set; } = new List<string>();  // meta-unlocked by name
        public int LifetimeCoins { get; set; }
        public int ChefXp        { get; set; }

        static string FilePath => Path.Combine(AppContext.BaseDirectory, "savedata.json");

        public static SaveData Load()
        {
            try
            {
                if (File.Exists(FilePath))
                    return JsonSerializer.Deserialize<SaveData>(File.ReadAllText(FilePath)) ?? new SaveData();
            }
            catch { /* unreadable / corrupt -> fresh profile */ }
            return new SaveData();
        }

        public void Save()
        {
            try
            {
                File.WriteAllText(FilePath,
                    JsonSerializer.Serialize(this, new JsonSerializerOptions { WriteIndented = true }));
            }
            catch { /* read-only install dir -> not persisted */ }
        }

        public int BestFor(string mode) => Best.TryGetValue(mode, out int v) ? v : 0;

        public int OverallBest()
        {
            int b = 0;
            foreach (int v in Best.Values) if (v > b) b = v;
            return b;
        }

        // Returns true if this is a new personal best for the mode.
        public bool RecordBest(string mode, int score)
        {
            if (score > BestFor(mode)) { Best[mode] = score; return true; }
            return false;
        }

        public bool Has(string id) => Achievements.Contains(id);

        // Returns true if this call newly unlocked the achievement.
        public bool Unlock(string id)
        {
            if (Achievements.Contains(id)) return false;
            Achievements.Add(id);
            return true;
        }
    }
}
