// Port of Sources/wallframes/Weather.swift. Keep the two in step.

using System;
using System.Globalization;
using System.Linq;
using System.Net;

/// What the sky is doing in one frame.
enum Sky { Clear, Cloudy, Overcast, Rain, Snow, Fog }

/// The renderer's knobs for a `Sky`, each 0…1. The renderer only reads these,
/// so what a class looks like is tuned here, in one place.
sealed class Weather
{
    public readonly float Clouds;    // cover of drifting clouds in the sky
    public readonly float Overcast;  // a grey deck: dims and greys the palette, hides sun and stars
    public readonly float Rain;      // streak density
    public readonly float Snow;      // flake density; also whitens the ground under the pines
    public readonly float Fog;       // haze that swallows far layers first

    public Weather(Sky sky)
    {
        switch (sky)
        {
            case Sky.Cloudy: Clouds = 0.5f; Overcast = 0.1f; break;
            case Sky.Overcast: Clouds = 0.95f; Overcast = 0.75f; Fog = 0.1f; break;
            case Sky.Rain: Clouds = 1; Overcast = 0.9f; Rain = 1; Fog = 0.35f; break;
            case Sky.Snow: Clouds = 1; Overcast = 0.6f; Snow = 1; Fog = 0.3f; break;
            case Sky.Fog: Overcast = 0.35f; Fog = 1; break;
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

    Forecast(Sky[] hours) { Hours = hours; }

    public static string Url(double latitude, double longitude, string date)
    {
        return "https://api.open-meteo.com/v1/forecast?latitude=" + Tenth(latitude) + "&longitude=" + Tenth(longitude)
            + "&hourly=weather_code,cloud_cover&timezone=auto&start_date=" + date + "&end_date=" + date;
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
        for (int i = 0; i < times.Length; i++)
        {
            if (times[i].Length < date.Length + 3 || !times[i].StartsWith(date + "T", StringComparison.Ordinal)) continue;
            int hour;
            if (!int.TryParse(times[i].Substring(date.Length + 1, 2), NumberStyles.Integer, CultureInfo.InvariantCulture, out hour) || hour < 0 || hour > 23) continue;
            hours[hour] = SkyOf(Int(codes[i]), Int(covers[i]));
        }
        if (hours.Any(h => !h.HasValue)) return null;
        return new Forecast(hours.Select(h => h.Value).ToArray());
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
