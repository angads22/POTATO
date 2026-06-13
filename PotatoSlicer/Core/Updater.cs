/*
 * Updater — version check and self-update against GitHub Releases.
 *
 * The standalone binary checks the repo's latest release on launch (and on
 * demand from the menu) and swaps itself for the new build. A running
 * executable can be renamed but not deleted or overwritten, so the update
 * parks the old image under a .old* name and cleans those up next start.
 */
using System;
using System.Diagnostics;
using System.IO;
using System.Net.Http;
using System.Text.Json;
using System.Threading;
using static PotatoSlicer.Render;

namespace PotatoSlicer
{
    static class Updater
    {
        public const string VERSION = "2.5.0";          // must match the release tag (v2.5.0)
        public const string REPO    = "angads22/POTATO";

        const string LatestUrl = "https://api.github.com/repos/" + REPO + "/releases/latest";

        // ────────────────────────────────────────────────────────
        //  AUTO-UPDATE ON LAUNCH
        //  Quietly checks for a newer release; if one exists it is
        //  installed and the game restarts itself. Any failure
        //  (offline, no releases yet) silently drops into the game.
        //  The restarted process gets --no-update so a release tag
        //  that mismatches VERSION can't cause a restart loop.
        // ────────────────────────────────────────────────────────
        public static void AutoUpdateOnLaunch()
        {
            if (RunningFromSource()) return;
            try
            {
                using (HttpClient http = NewClient(6))
                using (JsonDocument doc = JsonDocument.Parse(
                           http.GetStringAsync(LatestUrl).GetAwaiter().GetResult()))
                {
                    string tag = doc.RootElement.GetProperty("tag_name").GetString() ?? "";
                    if (tag.TrimStart('v', 'V') == VERSION) return;
                    string name;
                    string url = FindAssetUrl(doc, out name);
                    if (url == null) return;

                    Console.Clear();
                    Console.WriteLine();
                    Ink(ConsoleColor.Yellow); Ctr("A new version is available: " + tag);
                    Ink(ConsoleColor.Gray);   Ctr("Updating automatically...");
                    Console.ResetColor();
                    InstallBinary(http, url);
                    Ink(ConsoleColor.Green);  Ctr("Updated! Restarting...");
                    Console.ResetColor();
                    Thread.Sleep(900);
                    Process.Start(new ProcessStartInfo(Environment.ProcessPath, "--no-update")
                                  { UseShellExecute = false });
                    Environment.Exit(0);
                }
            }
            catch { /* offline or no release yet — just play */ }
        }

        // ────────────────────────────────────────────────────────
        //  INTERACTIVE CHECK  (menu option)
        // ────────────────────────────────────────────────────────
        public static void CheckInteractive()
        {
            Console.Clear();
            Ink(ConsoleColor.Cyan); Ctr("CHECK FOR UPDATES"); Console.WriteLine();
            Ink(ConsoleColor.Gray);
            Console.WriteLine("  Installed version : v" + VERSION);
            Console.WriteLine("  Checking github.com/" + REPO + " ...");
            Console.WriteLine();
            Console.ResetColor();
            try
            {
                using (HttpClient http = NewClient(15))
                using (JsonDocument doc = JsonDocument.Parse(
                           http.GetStringAsync(LatestUrl).GetAwaiter().GetResult()))
                {
                    string tag = doc.RootElement.GetProperty("tag_name").GetString() ?? "";
                    if (tag.TrimStart('v', 'V') == VERSION)
                    {
                        Ink(ConsoleColor.Green);
                        Console.WriteLine("  You are up to date (v" + VERSION + ").");
                    }
                    else
                    {
                        Ink(ConsoleColor.Yellow);
                        Console.WriteLine("  New version available: " + tag + "   (installed: v" + VERSION + ")");
                        Console.WriteLine();
                        OfferInstall(http, doc, tag);
                    }
                }
            }
            catch (Exception ex)
            {
                Ink(ConsoleColor.Red);
                Console.WriteLine("  Update check failed: " + ex.Message);
                Ink(ConsoleColor.Gray);
                Console.WriteLine("  (No internet access, or no releases published yet.)");
            }
            Console.WriteLine();
            Ink(ConsoleColor.DarkGray); Ctr("Press any key to go back...");
            Console.ResetColor();
            Console.ReadKey(true);
        }

        // Removes renamed-aside binaries left behind by previous updates
        public static void CleanupOldBinaries()
        {
            try
            {
                string exe = Environment.ProcessPath ?? "";
                if (exe.Length == 0) return;
                string dir = Path.GetDirectoryName(exe);
                if (dir == null) return;
                foreach (string f in Directory.GetFiles(dir, Path.GetFileName(exe) + ".old*"))
                    try { File.Delete(f); } catch { /* still locked — next launch gets it */ }
            }
            catch { /* directory unreadable — nothing to clean */ }
        }

        // ────────────────────────────────────────────────────────
        //  Internals
        // ────────────────────────────────────────────────────────
        static HttpClient NewClient(int timeoutSec)
        {
            HttpClient http = new HttpClient();
            http.DefaultRequestHeaders.UserAgent.ParseAdd("PotatoSlicer/" + VERSION);
            http.Timeout = TimeSpan.FromSeconds(timeoutSec);
            return http;
        }

        static void OfferInstall(HttpClient http, JsonDocument doc, string tag)
        {
            if (RunningFromSource())
            {
                Ink(ConsoleColor.Gray);
                Console.WriteLine("  You are running from source — update with: git pull");
                return;
            }

            string name;
            string url = FindAssetUrl(doc, out name);
            if (url == null)
            {
                Ink(ConsoleColor.Red);
                Console.WriteLine("  The release has no downloadable build for this platform.");
                return;
            }

            Ink(ConsoleColor.White);
            Console.WriteLine("  Download and install " + name + "? [Y/N]");
            Console.ResetColor();
            if (Console.ReadKey(true).Key != ConsoleKey.Y) return;

            Console.WriteLine("  Downloading...");
            InstallBinary(http, url);

            Ink(ConsoleColor.Green);
            Console.WriteLine("  Updated to " + tag + "!  Restart the game to play the new version.");
        }

        // Running via `dotnet run` rather than as a published binary?
        static bool RunningFromSource()
        {
            string exe = Environment.ProcessPath ?? "";
            return exe.Length == 0 || Path.GetFileNameWithoutExtension(exe) == "dotnet";
        }

        static string FindAssetUrl(JsonDocument doc, out string name)
        {
            string want = OperatingSystem.IsWindows() ? "win-x64.exe" : "linux-x64";
            foreach (JsonElement a in doc.RootElement.GetProperty("assets").EnumerateArray())
            {
                string an = a.GetProperty("name").GetString() ?? "";
                if (an.EndsWith(want)) { name = an; return a.GetProperty("browser_download_url").GetString(); }
            }
            name = null;
            return null;
        }

        static void InstallBinary(HttpClient http, string url)
        {
            string exe  = Environment.ProcessPath;
            byte[] data = http.GetByteArrayAsync(url).GetAwaiter().GetResult();

            string fresh = exe + ".new";
            File.WriteAllBytes(fresh, data);
            if (!OperatingSystem.IsWindows())
                File.SetUnixFileMode(fresh,
                    UnixFileMode.UserRead  | UnixFileMode.UserWrite  | UnixFileMode.UserExecute |
                    UnixFileMode.GroupRead | UnixFileMode.GroupExecute |
                    UnixFileMode.OtherRead | UnixFileMode.OtherExecute);

            // A running exe can be renamed but not deleted or overwritten.
            // If .old is still locked (second update without a restart, so
            // .old IS the running image), park it under a unique name.
            string old = exe + ".old";
            try { if (File.Exists(old)) File.Delete(old); }
            catch { old = exe + ".old" + Environment.TickCount64; }
            File.Move(exe, old);
            File.Move(fresh, exe);
        }
    }
}
