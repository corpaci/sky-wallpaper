// Port of Sources/wallframes/Weather.swift. Keep the two in step.

using System;
using System.Globalization;
using System.Linq;
using System.Net;

/// What the sky is doing in one frame.
enum Sky { Clear, Cloudy, Overcast, Rain, Snow, Fog }

/// The renderer's knobs for a `Sky`, each 0…1. The renderer only reads these,
/// so what a class looks like is tuned here, in one place.
///
/// Grey weather isn't mirrored, and no cloud ever covers the sky; the scene
/// shows what's beyond the weather. Overcast is the view from above it, a
/// sea of clouds over the world below; cloudy, the same sea broken open, the
/// hills showing through. Fog lies low in the far valleys. Rain is the
/// moment after: wet light, a rainbow opposite the sun, colored glints on the
/// grass. Snow is the clear morning after: fresh snow, and ice glittering in
/// the air.
sealed class Weather
{
    public readonly float Overcast;  // greys and dims the palette, veils sun, moon and stars
    public readonly float Sea;       // a sea of clouds below, ranges breaking through
    public readonly float Broken;    // how much of the sea is open, showing the world below
    public readonly float Valley;    // fog lakes at the feet of the far hills
    public readonly float Wet;       // after rain: rainbow opposite a low sun, glints on the grass
    public readonly float Snow;      // fresh snow on open ground, and ice glittering in the air
    public readonly float Fog;       // haze that swallows far layers first

    public Weather(Sky sky)
    {
        switch (sky)
        {
            case Sky.Cloudy: Sea = 1; Broken = 0.5f; break;
            case Sky.Overcast: Sea = 1; break;
            case Sky.Rain: Overcast = 0.05f; Wet = 1; Fog = 0.1f; break;
            case Sky.Snow: Snow = 1; Fog = 0.1f; break;
            case Sky.Fog: Valley = 1; Fog = 0.08f; break;
        }
    }

    public static string Name(Sky sky) { return sky.ToString().ToLowerInvariant(); }

    public static bool TryParse(string name, out Sky sky)
    {
        foreach (Sky s in Enum.GetValues(typeof(Sky)))
        {
            if (Name(s) == name) { sky = s; return true; }
        }
        sky = Sky.Clear;
        return false;
    }
}

/// One day's hourly sky from the Open-Meteo forecast API (open-meteo.com:
/// free, no key, no account). A request carries only the date and the
/// coordinates rounded to 0.1°, about 10 km.
sealed class Forecast
{
    public readonly Sky[] Hours;  // local hours 0…23
    // For the seasons, when the response has them, by local hour:
    public float[] Temperature;    // °C at 2 m
    public float[] SnowDepth;      // m of snow lying
    public float[] FreezingLevel;  // m above sea level

    Forecast(Sky[] hours) { Hours = hours; }

    public static string Url(double latitude, double longitude, string date)
    {
        return "https://api.open-meteo.com/v1/forecast?latitude=" + Tenth(latitude) + "&longitude=" + Tenth(longitude)
            + "&hourly=weather_code,cloud_cover,temperature_2m,snow_depth,freezing_level_height"
            + "&timezone=auto&start_date=" + date + "&end_date=" + date;
    }

    static string Tenth(double v)
    {
        return (Math.Round(v * 10, MidpointRounding.AwayFromZero) / 10).ToString("R", CultureInfo.InvariantCulture);
    }

    /// The response body, or null if the request fails.
    public static string Fetch(double latitude, double longitude, string date)
    {
        ServicePointManager.SecurityProtocol |= SecurityProtocolType.Tls12;  // off by default on .NET 4.x
        try
        {
            using (var client = new WebClient())
            {
                client.Headers[HttpRequestHeader.UserAgent] = "sky-wallpaper";
                return client.DownloadString(Url(latitude, longitude, date));
            }
        }
        catch (WebException) { return null; }
    }

    /// The hours of `date` from a response body; null unless all 24 are there.
    /// Reads only the three flat arrays it needs, so no JSON library is involved.
    public static Forecast Parse(string json, string date)
    {
        int hourly = json.IndexOf("\"hourly\":{", StringComparison.Ordinal);
        if (hourly < 0) return null;
        string[] times = Values(json, hourly, "time"), codes = Values(json, hourly, "weather_code"), covers = Values(json, hourly, "cloud_cover");
        if (times == null || codes == null || covers == null || codes.Length != times.Length || covers.Length != times.Length) return null;
        var hours = new Sky?[24];
        var index = Enumerable.Repeat(-1, 24).ToArray();  // response row of each local hour
        for (int i = 0; i < times.Length; i++)
        {
            if (times[i].Length < date.Length + 3 || !times[i].StartsWith(date + "T", StringComparison.Ordinal)) continue;
            int hour;
            if (!int.TryParse(times[i].Substring(date.Length + 1, 2), NumberStyles.Integer, CultureInfo.InvariantCulture, out hour) || hour < 0 || hour > 23) continue;
            hours[hour] = SkyOf(Int(codes[i]), Int(covers[i]));
            index[hour] = i;
        }
        if (hours.Any(h => !h.HasValue)) return null;
        var f = new Forecast(hours.Select(h => h.Value).ToArray());
        Func<string, float[]> series = name =>  // all 24 hours, or none
        {
            string[] values = Values(json, hourly, name);
            if (values == null || values.Length != times.Length) return null;
            var v = new float[24];
            for (int h = 0; h < 24; h++)
            {
                double d;
                if (!double.TryParse(values[index[h]], NumberStyles.Float, CultureInfo.InvariantCulture, out d)) return null;
                v[h] = (float)d;
            }
            return v;
        };
        f.Temperature = series("temperature_2m");
        f.SnowDepth = series("snow_depth");
        f.FreezingLevel = series("freezing_level_height");
        return f;
    }

    /// The day's ground for `season`'s date, at a local hour: the snow line
    /// from the freezing level (on a summit from 1000 to 3500 m, the snow
    /// lying about 200 m below it), snow where the forecast has it, and
    /// hoarfrost on freezing mornings.
    public Season Ground(Season season, int hour)
    {
        Season s = season;
        if (FreezingLevel != null)
        {
            float median = FreezingLevel.OrderBy(v => v).ElementAt(12);
            s.SnowLine = Math.Min(Math.Max((median - 200 - 1000) / 2500, 0.03f), 0.88f);
        }
        if (SnowDepth != null) s.SnowCover = Col.Smoothstep(0.005f, 0.04f, SnowDepth[hour]);
        if (Temperature != null)
        {
            s.Frost = hour < 11 ? Col.Smoothstep(0.5f, -3, Temperature[hour]) * (1 - s.SnowCover) : 0;
            s.Warm = Temperature[hour] >= 14;
        }
        return s;
    }

    static string[] Values(string json, int from, string key)
    {
        string open = "\"" + key + "\":[";
        int start = json.IndexOf(open, from, StringComparison.Ordinal);
        if (start < 0) return null;
        start += open.Length;
        int end = json.IndexOf(']', start);
        if (end < 0) return null;
        string body = json.Substring(start, end - start).Trim();
        return body.Length == 0 ? new string[0] : body.Split(',').Select(s => s.Trim().Trim('"')).ToArray();
    }

    static int? Int(string s)
    {
        int v;
        return int.TryParse(s, NumberStyles.Integer, CultureInfo.InvariantCulture, out v) ? v : (int?)null;
    }

    /// The WMO weather code decides fog, snow and rain; cloud cover the rest.
    public static Sky SkyOf(int? code, int? cover)
    {
        int c = code ?? -1;
        if (c == 45 || c == 48) return Sky.Fog;
        if ((c >= 71 && c <= 77) || c == 85 || c == 86) return Sky.Snow;
        if ((c >= 51 && c <= 67) || (c >= 80 && c <= 82) || (c >= 95 && c <= 99)) return Sky.Rain;
        if (cover.HasValue) return cover.Value < 30 ? Sky.Clear : cover.Value < 75 ? Sky.Cloudy : Sky.Overcast;
        c = code ?? 0;
        return c == 0 || c == 1 ? Sky.Clear : c == 2 ? Sky.Cloudy : Sky.Overcast;
    }
}
