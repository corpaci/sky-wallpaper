// sky — the Windows side of the dynamic wallpaper. One source, two builds:
// sky.exe (console, for people and the installer) and sky-apply.exe
// (windowless, for Task Scheduler, so nothing flashes at switch time).
//
//   sky render [--size WxH]... [--seed N] [--dry-run] --out DIR
//              [--sunrise HH:MM --sunset HH:MM | --lat DEG --lon DEG [--date yyyy-MM-dd] [--utc-offset MIN]]
//   sky tick [--force]   what the scheduled task runs: render today if needed,
//                        keep the task's switch times current, set the frame
//   sky apply DIR        set each monitor to the frame for the current local time
//   sky frame DIR HH:MM [WxH]   print the frame a monitor that size shows then
//   sky schedule DIR     print the switch times, one HH:MM per line
//   sky monitors         list monitors and their pixel sizes
//   sky save FILE        remember the current wallpapers
//   sky restore FILE     put them back
//
// render without --size renders one frame set per connected monitor size,
// into DIR\WxH\ (PNGs plus a manifest.txt in the same format heicpack reads).

using System;
using System.Collections.Generic;
using System.Diagnostics;
using System.Globalization;
using System.IO;
using System.Linq;

sealed class UsageException : Exception
{
    public UsageException(string message) : base(message) { }
}

/// One rendered size: its frames by switch minute, read from manifest.txt.
sealed class FrameSet
{
    public int Width, Height;
    public List<KeyValuePair<int, string>> Entries;  // sorted by minute; full paths

    static readonly string[] flags = { "primary", "light", "dark" };

    /// Every DIR\WxH\manifest.txt under `root`.
    public static List<FrameSet> LoadAll(string root)
    {
        var sets = new List<FrameSet>();
        if (!Directory.Exists(root)) throw new UsageException("no frames at " + root);
        foreach (string dir in Directory.GetDirectories(root))
        {
            int w, h;
            if (!Program.ParseSize(Path.GetFileName(dir), out w, out h)) continue;
            string manifest = Path.Combine(dir, "manifest.txt");
            if (!File.Exists(manifest)) continue;
            var set = new FrameSet { Width = w, Height = h, Entries = new List<KeyValuePair<int, string>>() };
            foreach (string raw in File.ReadAllLines(manifest))
            {
                string line = raw.Split('#')[0].Trim();
                if (line == "") continue;
                int gap = line.IndexOfAny(new[] { ' ', '\t' });
                int minute;
                if (gap < 0 || !Program.ParseClock(line.Substring(0, gap), out minute))
                    throw new UsageException(manifest + ": bad line: " + raw);
                string path = line.Substring(gap).Trim();
                for (bool more = true; more; )
                {
                    more = false;
                    foreach (string flag in flags)
                    {
                        if (path.EndsWith(" " + flag, StringComparison.Ordinal) || path.EndsWith("\t" + flag, StringComparison.Ordinal))
                        {
                            path = path.Substring(0, path.Length - flag.Length).Trim();
                            more = true;
                        }
                    }
                }
                set.Entries.Add(new KeyValuePair<int, string>(minute, Path.GetFullPath(Path.Combine(dir, path))));
            }
            if (set.Entries.Count == 0) continue;
            set.Entries.Sort((a, b) => a.Key.CompareTo(b.Key));
            sets.Add(set);
        }
        if (sets.Count == 0) throw new UsageException("no WxH\\manifest.txt under " + root);
        return sets;
    }

    /// The frame showing at `minute`: the last switch at or before it,
    /// wrapping to yesterday's last switch before the first one.
    public string FrameAt(int minute)
    {
        string frame = Entries[Entries.Count - 1].Value;
        foreach (var e in Entries) if (e.Key <= minute) frame = e.Value;
        return frame;
    }

    /// The exact size if rendered, else the closest aspect ratio, larger first.
    public static FrameSet Closest(List<FrameSet> sets, int width, int height)
    {
        double aspect = Math.Log((double)width / height);
        return sets.OrderBy(s => s.Width == width && s.Height == height ? 0 : 1)
                   .ThenBy(s => Math.Round(Math.Abs(Math.Log((double)s.Width / s.Height) - aspect), 3))
                   .ThenByDescending(s => s.Width * s.Height)
                   .First();
    }
}

static class Program
{
    const string Usage = @"usage: sky render [--size WxH]... [--seed N] [--dry-run] --out DIR
           [--sunrise HH:MM --sunset HH:MM | --lat DEG --lon DEG [--date yyyy-MM-dd] [--utc-offset MIN]]
       sky apply DIR | sky frame DIR HH:MM [WxH] | sky schedule DIR | sky task-xml DIR
       sky tick [--force] | sky monitors | sky save FILE | sky restore FILE";

    [STAThread]
    static int Main(string[] args)
    {
        try
        {
            return Run(args);
        }
        catch (UsageException e)
        {
            Fail(e.Message);
            return 2;
        }
        catch (Exception e)
        {
            Fail(e.ToString());
            return 1;
        }
    }

    /// Errors go to stderr and to sky.log beside the exe: the windowless build
    /// has no console, and a scheduled task's failures are otherwise silent.
    static void Fail(string message)
    {
        Console.Error.WriteLine("sky: " + message);
        try
        {
            string log = Path.Combine(AppDomain.CurrentDomain.BaseDirectory, "sky.log");
            if (File.Exists(log) && new FileInfo(log).Length > 64 * 1024) File.Delete(log);
            File.AppendAllText(log, DateTime.Now.ToString("s") + " " + message + Environment.NewLine);
        }
        catch (IOException) { }
        catch (UnauthorizedAccessException) { }
    }

    static int Run(string[] args)
    {
        if (args.Length == 0 || args[0] == "-h" || args[0] == "--help") { Console.WriteLine(Usage); return args.Length == 0 ? 2 : 0; }
        var rest = args.Skip(1).ToList();
        switch (args[0])
        {
            case "render":
                return Render(rest);
            case "apply":
                Desktop.BeDpiAware();
                foreach (string line in Desktop.Apply(FrameSet.LoadAll(One(rest, "apply DIR")), Now())) Console.WriteLine(line);
                return 0;
            case "frame":
            {
                if (rest.Count < 2 || rest.Count > 3) throw new UsageException("usage: sky frame DIR HH:MM [WxH]");
                int minute, w, h;
                if (!ParseClock(rest[1], out minute)) throw new UsageException("bad time " + rest[1]);
                var sets = FrameSet.LoadAll(rest[0]);
                w = sets[0].Width;
                h = sets[0].Height;
                if (rest.Count == 3 && !ParseSize(rest[2], out w, out h)) throw new UsageException("bad size " + rest[2]);
                Console.WriteLine(FrameSet.Closest(sets, w, h).FrameAt(minute));
                return 0;
            }
            case "schedule":
                foreach (var e in FrameSet.LoadAll(One(rest, "schedule DIR"))[0].Entries) Console.WriteLine(Clock(e.Key));
                return 0;
            case "tick":
                if (rest.Count > 1 || (rest.Count == 1 && rest[0] != "--force")) throw new UsageException("usage: sky tick [--force]");
                return Tick(rest.Count == 1);
            case "task-xml":
                Console.Write(SkyTask.Xml(Today(), FrameSet.LoadAll(One(rest, "task-xml DIR"))[0].Entries.Select(e => e.Key),
                    Environment.UserDomainName + "\\" + Environment.UserName, Path.Combine(AppDomain.CurrentDomain.BaseDirectory, "sky-apply.exe"), true));
                return 0;
            case "monitors":
                Desktop.BeDpiAware();
                foreach (Monitor m in Desktop.Monitors()) Console.WriteLine("{0}x{1}  {2}", m.Width, m.Height, m.Id);
                return 0;
            case "save":
                Desktop.BeDpiAware();
                Desktop.Save(One(rest, "save FILE"));
                return 0;
            case "restore":
                Desktop.BeDpiAware();
                foreach (string line in Desktop.Restore(One(rest, "restore FILE"))) Console.WriteLine(line);
                return 0;
            default:
                throw new UsageException("unknown command " + args[0] + Environment.NewLine + Usage);
        }
    }

    static string Today() { return DateTime.Now.ToString("yyyy-MM-dd", CultureInfo.InvariantCulture); }

    /// What the scheduled task runs. Renders today's frames if they are
    /// missing (or --force), into a new folder (Windows caches wallpapers by
    /// path); re-registers the task when the frames changed, so tomorrow's
    /// triggers match today's sky; then sets the current frame and drops
    /// older frames. Reads config.txt beside the exe: lat, lon, weather
    /// (yes|no), seed, or sunrise and sunset when there is no location.
    static int Tick(bool force)
    {
        string app = AppDomain.CurrentDomain.BaseDirectory;
        var config = new Dictionary<string, string>();
        foreach (string line in File.ReadAllLines(Path.Combine(app, "config.txt")))
        {
            int eq = line.IndexOf('=');
            if (eq > 0) config[line.Substring(0, eq).Trim()] = line.Substring(eq + 1).Trim();
        }
        Func<string, string, string> get = (name, fallback) => config.ContainsKey(name) ? config[name] : fallback;
        bool located = config.ContainsKey("lat") && config.ContainsKey("lon");

        // A new day, a new sky: the moon and stars move even when the times stay fixed.
        string key = Today();
        string dir = Directory.GetDirectories(app, "frames-" + key + "-*")
            .Where(d => Directory.GetFiles(d, "manifest.txt", SearchOption.AllDirectories).Length > 0)
            .OrderByDescending(d => d, StringComparer.Ordinal).FirstOrDefault();
        if (dir == null || force)
        {
            dir = Path.Combine(app, "frames-" + key + "-" + DateTime.Now.ToString("HHmmss", CultureInfo.InvariantCulture));
            var args = new List<string> { "--seed", get("seed", "7"), "--out", dir };
            args.AddRange(located
                ? new[] { "--lat", config["lat"], "--lon", config["lon"] }
                : new[] { "--sunrise", get("sunrise", "07:20"), "--sunset", get("sunset", "17:55") });
            bool weather = located && get("weather", "yes") == "yes";
            if (!weather) Render(args);
            else
            {
                try { Render(args.Concat(new[] { "--weather" }).ToList()); }
                catch (UsageException e)
                {
                    Fail(e.Message + "; rendering without weather");
                    if (Directory.Exists(dir)) Directory.Delete(dir, true);
                    Render(args);
                }
            }
        }
        List<FrameSet> sets = FrameSet.LoadAll(dir);

        string registered = Path.Combine(app, "task.txt");
        if (!File.Exists(registered) || File.ReadAllText(registered) != dir)
        {
            var minutes = sets[0].Entries.Select(e => e.Key).ToList();
            string user = System.Security.Principal.WindowsIdentity.GetCurrent().Name, exe = Path.Combine(app, "sky-apply.exe"), error;
            if (!SkyTask.Register(SkyTask.Xml(Today(), minutes, user, exe, true), out error))
            {
                // Event triggers can be refused on locked-down machines; unlock and logon still catch up.
                Fail("no wake trigger (" + error + "); the frame catches up at unlock instead");
                if (!SkyTask.Register(SkyTask.Xml(Today(), minutes, user, exe, false), out error))
                    throw new InvalidOperationException("cannot register the scheduled task: " + error);
            }
            File.WriteAllText(registered, dir);
        }

        Desktop.BeDpiAware();
        foreach (string line in Desktop.Apply(sets, Now())) Console.WriteLine(line);
        foreach (string old in Directory.GetDirectories(app, "frames-*"))
        {
            if (string.Equals(old, dir, StringComparison.OrdinalIgnoreCase)) continue;
            try { Directory.Delete(old, true); }
            catch (IOException) { }  // still on screen somewhere; next tick
        }
        return 0;
    }

    static string One(List<string> rest, string form)
    {
        if (rest.Count != 1) throw new UsageException("usage: sky " + form);
        return rest[0];
    }

    static int Now()
    {
        DateTime t = DateTime.Now;
        return t.Hour * 60 + t.Minute;
    }

    public static bool ParseClock(string s, out int minute)
    {
        minute = 0;
        string[] parts = s.Split(':');
        int h, m;
        if (parts.Length != 2 || !int.TryParse(parts[0], out h) || !int.TryParse(parts[1], out m)) return false;
        if (h < 0 || h > 23 || m < 0 || m > 59) return false;
        minute = h * 60 + m;
        return true;
    }

    public static bool ParseSize(string s, out int width, out int height)
    {
        width = height = 0;
        string[] parts = s.Split('x');
        return parts.Length == 2 && int.TryParse(parts[0], out width) && int.TryParse(parts[1], out height)
            && width >= 64 && width <= 16384 && height >= 64 && height <= 16384;
    }

    static string Clock(int minute) { return string.Format("{0:D2}:{1:D2}", minute / 60, minute % 60); }

    static string Num(double v) { return v.ToString("R", CultureInfo.InvariantCulture); }

    static double Degrees(string s, double limit, string error)
    {
        double v;
        if (!double.TryParse(s, NumberStyles.Float, CultureInfo.InvariantCulture, out v) || Math.Abs(v) > limit)
            throw new UsageException(error);
        return v;
    }

    static string Header(int width, int height, int sunrise, int sunset, string dayNote, uint seed)
    {
        return string.Format("# sky {0}x{1}, sunrise {2}, sunset {3}{4}, seed {5}", width, height, Clock(sunrise), Clock(sunset), dayNote, seed);
    }

    sealed class Frame
    {
        public string Label;
        public int Minute;
        public string Flags = "";
        public Sky Sky = Sky.Clear;

        public string Name { get { return Label + (Sky == Sky.Clear ? "" : "-" + Weather.Name(Sky)); } }
    }

    static int Render(List<string> args)
    {
        var sizes = new List<int[]>();
        int sunrise = 7 * 60 + 20, sunset = 17 * 60 + 55;
        uint seed = 7;
        string outDir = null, date = null, forecastFile = null;
        bool dryRun = false, fetchWeather = false;
        double? latitude = null, longitude = null;
        int? utcOffset = null;
        Sky? forcedSky = null;
        for (int i = 0; i < args.Count; i++)
        {
            string flag = args[i];
            if (flag == "--dry-run") { dryRun = true; continue; }
            if (flag == "--weather") { fetchWeather = true; continue; }
            if (i + 1 >= args.Count) throw new UsageException(flag + " needs a value");
            string value = args[++i];
            int w, h;
            switch (flag)
            {
                case "--size":
                    if (!ParseSize(value, out w, out h)) throw new UsageException("--size wants WIDTHxHEIGHT");
                    sizes.Add(new[] { w, h });
                    break;
                case "--sunrise":
                    if (!ParseClock(value, out sunrise)) throw new UsageException("--sunrise wants HH:MM");
                    break;
                case "--sunset":
                    if (!ParseClock(value, out sunset)) throw new UsageException("--sunset wants HH:MM");
                    break;
                case "--seed":
                    if (!uint.TryParse(value, out seed)) throw new UsageException("--seed wants a whole number");
                    break;
                case "--out":
                    outDir = value;
                    break;
                case "--lat":
                    latitude = Degrees(value, 90, "--lat wants degrees north, -90 to 90");
                    break;
                case "--lon":
                    longitude = Degrees(value, 180, "--lon wants degrees east, -180 to 180");
                    break;
                case "--date":
                    date = value;
                    break;
                case "--sky":
                    Sky s;
                    if (!Weather.TryParse(value, out s))
                        throw new UsageException("--sky wants one of: clear, cloudy, overcast, rain, snow, fog");
                    forcedSky = s;
                    break;
                case "--forecast":
                    forecastFile = value;
                    break;
                case "--utc-offset":
                    int offset;
                    if (!int.TryParse(value, NumberStyles.Integer, CultureInfo.InvariantCulture, out offset) || Math.Abs(offset) > 14 * 60)
                        throw new UsageException("--utc-offset wants minutes, e.g. 60");
                    utcOffset = offset;
                    break;
                default:
                    throw new UsageException("unknown flag " + flag + Environment.NewLine + Usage);
            }
        }
        string dayNote = "";
        string day = date ?? DateTime.Now.ToString("yyyy-MM-dd", CultureInfo.InvariantCulture);
        if (latitude.HasValue || longitude.HasValue)
        {
            if (!latitude.HasValue || !longitude.HasValue) throw new UsageException("--lat and --lon go together");
            Daylight d = Daylight.For(latitude.Value, longitude.Value, day, utcOffset);
            if (d == null) throw new UsageException("--date wants yyyy-MM-dd");
            sunrise = d.Sunrise;
            sunset = d.Sunset;
            dayNote = " on " + day + " at " + Num(latitude.Value) + ", " + Num(longitude.Value) + (d.Note == null ? "" : " (" + d.Note + ")");
        }
        if (outDir == null && !dryRun) throw new UsageException("render needs --out DIR");
        if (sunset - sunrise < 120) throw new UsageException("sunset must be at least two hours after sunrise");

        // Where and when the night sky is seen.
        DateTime skyDay;
        if (!DateTime.TryParseExact(day, "yyyy-MM-dd", CultureInfo.InvariantCulture, DateTimeStyles.None, out skyDay))
            throw new UsageException("--date wants yyyy-MM-dd");
        int skyOffset = utcOffset.HasValue ? utcOffset.Value : (int)TimeZoneInfo.Local.GetUtcOffset(skyDay.AddHours(12)).TotalMinutes;
        double skyLatitude = latitude.HasValue ? latitude.Value : 45;
        double skyLongitude = longitude.HasValue ? longitude.Value : skyOffset / 4.0;
        if (sizes.Count == 0 && dryRun) sizes.Add(new[] { 2560, 1664 });
        if (sizes.Count == 0)
        {
            Desktop.BeDpiAware();
            foreach (Monitor m in Desktop.Monitors())
                if (!sizes.Any(s => s[0] == m.Width && s[1] == m.Height)) sizes.Add(new[] { m.Width, m.Height });
            if (sizes.Count == 0) throw new UsageException("no monitors found; pass --size WxH");
        }

        // Frames sit at fixed sun altitudes, so they bunch up around sunrise
        // and sunset, where the sky changes fastest.
        var sun = new SunModel(sunrise, sunset);
        var frames = new List<Frame> {
            new Frame { Label = "midnight", Minute = sun.Midnight, Flags = "dark" },
            new Frame { Label = "noon", Minute = sun.Noon, Flags = "light" },
        };
        string[] morning = { "night-end", "blue-hour", "dawn", "sunrise", "golden", "morning" };
        string[] evening = { "afternoon", "golden-eve", "sunset", "dusk", "blue-hour-eve", "night" };
        float[] morningAlt = { -14, -7, -3, 0.5f, 5, 14 };
        float[] eveningAlt = { 14, 5, 0.5f, -3, -7, -14 };
        for (int i = 0; i < morning.Length; i++)
            frames.Add(new Frame { Label = morning[i], Minute = sun.MinuteAt(morningAlt[i], false) });
        for (int i = 0; i < evening.Length; i++)
            frames.Add(new Frame { Label = evening[i], Minute = sun.MinuteAt(eveningAlt[i], true), Flags = evening[i] == "sunset" ? "primary" : "" });
        frames = frames.OrderBy(f => f.Minute).ToList();
        for (int i = 1; i < frames.Count; i++)
            if (frames[i].Minute == frames[i - 1].Minute)
                throw new UsageException(frames[i - 1].Label + " and " + frames[i].Label + " both land on " + Clock(frames[i].Minute) + "; day or night too short for this schedule");

        // The sky turns 15° an hour. A frame at 00:00 keeps the small hours on
        // this day's moon, and at night no frame shows for more than two hours.
        if (frames[0].Minute > 0) frames.Insert(0, new Frame { Label = "hour-00", Minute = 0 });
        var nightFrames = new List<Frame>();
        for (int i = 0; i < frames.Count; i++)
        {
            int end = i + 1 < frames.Count ? frames[i + 1].Minute : 1440;
            int gap = end - frames[i].Minute;
            if (gap <= 120 || !(sun.Altitude((frames[i].Minute + gap / 2) % 1440) < -6)) continue;
            int parts = (gap + 119) / 120;
            for (int k = 1; k < parts; k++)
            {
                int m = frames[i].Minute + gap * k / parts;
                nightFrames.Add(new Frame { Label = string.Format("night-{0:D2}{1:D2}", m / 60, m % 60), Minute = m });
            }
        }
        frames = frames.Concat(nightFrames).OrderBy(f => f.Minute).ToList();
        if (forcedSky.HasValue) foreach (Frame f in frames) f.Sky = forcedSky.Value;

        // Weather: each frame takes its hour's sky, plus one more frame on every
        // hour the sky changes, so the change shows on time.
        Forecast forecast = null;
        string forecastBody = null;
        if (fetchWeather || forecastFile != null)
        {
            if (forcedSky.HasValue) throw new UsageException("--sky and a forecast don't mix");
            if (forecastFile != null)
            {
                forecast = File.Exists(forecastFile) ? Forecast.Parse(File.ReadAllText(forecastFile), day) : null;
                if (forecast == null) throw new UsageException(forecastFile + ": no complete hourly forecast for " + day);
            }
            else
            {
                if (!latitude.HasValue) throw new UsageException("--weather needs --lat and --lon");
                forecastBody = Forecast.Fetch(latitude.Value, longitude.Value, day);
                forecast = forecastBody == null ? null : Forecast.Parse(forecastBody, day);
                if (forecast == null) throw new UsageException("no forecast for " + day + " from api.open-meteo.com");
            }
        }
        if (forecast != null)
        {
            foreach (Frame f in frames) f.Sky = forecast.Hours[f.Minute / 60];
            for (int hour = 1; hour < 24; hour++)
            {
                if (forecast.Hours[hour] == forecast.Hours[hour - 1] || frames.Any(f => f.Minute == hour * 60)) continue;
                frames.Add(new Frame { Label = string.Format("hour-{0:D2}", hour), Minute = hour * 60, Sky = forecast.Hours[hour] });
            }
            frames = frames.OrderBy(f => f.Minute).ToList();
        }
        string skyNote = forecast != null ? ", hourly weather" : forcedSky.HasValue ? ", sky " + Weather.Name(forcedSky.Value) : "";

        if (dryRun)
        {
            Console.WriteLine(Header(sizes[0][0], sizes[0][1], sunrise, sunset, dayNote, seed) + skyNote);
            foreach (Frame f in frames) Console.WriteLine(Clock(f.Minute) + "  " + f.Name);
            return 0;
        }

        Directory.CreateDirectory(outDir);
        if (forecastBody != null) File.WriteAllText(Path.Combine(outDir, "forecast.json"), forecastBody);
        foreach (int[] size in sizes)
        {
            int width = size[0], height = size[1];
            string dir = Path.Combine(outDir, width + "x" + height);
            Directory.CreateDirectory(dir);
            var clock = Stopwatch.StartNew();
            var scene = new Scene(width, height, seed);
            Console.WriteLine("scene {0}x{1}, seed {2}: {3:F2}s", width, height, seed, clock.Elapsed.TotalSeconds);
            var manifest = new List<string> {
                Header(width, height, sunrise, sunset, dayNote, seed) + skyNote,
                "# HH:MM  file  [primary] [light] [dark]",
            };
            for (int i = 0; i < frames.Count; i++)
            {
                clock.Restart();
                Frame f = frames[i];
                string name = string.Format("{0:D2}-{1}.png", i, f.Name);
                // The sky as it stands halfway through the time this frame shows.
                int end = i + 1 < frames.Count ? frames[i + 1].Minute : 1440;
                var sky = new Ephemeris(skyLatitude, skyLongitude,
                                        Ephemeris.DayNumber(skyDay.Year, skyDay.Month, skyDay.Day, (f.Minute + end) / 2.0 - skyOffset));
                byte[] pixels = scene.Render(f.Minute, sun, sky, Col.Hash32(unchecked((uint)i + seed)), new Weather(f.Sky));
                Png.Write(Path.Combine(dir, name), pixels, width, height);
                manifest.Add(Clock(f.Minute) + "  " + name + (f.Flags == "" ? "" : "  " + f.Flags));
                Console.WriteLine("{0}  {1}  sun {2:+0.0;-0.0} deg  moon {3,3:F0}% {4:+0.0;-0.0} deg  {5:F2}s", Clock(f.Minute), name,
                                  sun.Altitude(f.Minute), sky.MoonLit * 100, Math.Asin(sky.Moon.Z) * 180 / Math.PI, clock.Elapsed.TotalSeconds);
            }
            File.WriteAllLines(Path.Combine(dir, "manifest.txt"), manifest);
            Console.WriteLine("{0} frames -> {1}", frames.Count, Path.GetFullPath(dir));
        }
        return 0;
    }
}
