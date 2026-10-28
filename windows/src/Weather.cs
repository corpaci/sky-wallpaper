// Port of Sources/wallframes/Weather.swift. Keep the two in step.

using System;

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
