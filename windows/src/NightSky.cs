// Port of Sources/wallframes/NightSky.swift, in C# 5. Keep the two in step.
//
// What the night sky looks like, given where things are (Astronomy.cs).

using System;

static class NightSky
{
    /// Air the light crosses, in zenith thicknesses (Rozenberg's fit): 1
    /// overhead, about 10 at 5°, 40 at the horizon.
    public static float Airmass(float alt)
    {
        float s = (float)Math.Sin(Math.Max(alt, 0) * (float)Math.PI / 180);
        return 1 / (s + 0.025f * Col.Exp(-11 * s));
    }

    static readonly float[] starBv = { -0.33f, -0.15f, 0, 0.4f, 0.65f, 1.05f, 1.6f };
    static readonly uint[] starHex = { 0x9bb0ff, 0xaabfff, 0xcad7ff, 0xf8f7ff, 0xfff4ea, 0xffd2a1, 0xffcc6f };

    /// A star's color from its B−V index, after Mitchell Charity's colors by
    /// spectral class: a little more saturated than the eye sees it, at unit
    /// luminance, so color never changes brightness.
    public static RGB StarColor(float bv)
    {
        float b = Math.Min(Math.Max(bv, starBv[0]), starBv[starBv.Length - 1]);
        int i = 0;
        while (i < starBv.Length - 2 && b > starBv[i + 1]) i++;
        RGB c = Col.MixOklab(RGB.Hex(starHex[i]), RGB.Hex(starHex[i + 1]), (b - starBv[i]) / (starBv[i + 1] - starBv[i]));
        float y = 0.2126f * c.R + 0.7152f * c.G + 0.0722f * c.B;
        RGB vivid = Col.Mix(new RGB(y, y, y), c, 1.3f);
        return new RGB(Math.Max(vivid.R, 0), Math.Max(vivid.G, 0), Math.Max(vivid.B, 0)) * (1 / y);
    }

    static float Sq(float x) { return x * x; }

    /// Value noise over the sky in galactic degrees, seamless across l = ±180°:
    /// features about `k` degrees across, `stretch` times longer along the plane.
    static float SkyNoise(float l, float b, float k, int octaves, uint seed, float stretch = 1)
    {
        float kl = k * stretch;
        float a = Col.Fbm2(l / kl, b / k, octaves, seed);
        if (l <= 150) return a;
        return Col.Lerp(a, Col.Fbm2((l - 360) / kl, b / k, octaves, seed), Col.Smoothstep(150, 180, l));
    }

    /// A soft patch of sky around galactic (cl, cb), widths in degrees.
    static float Patch(float l, float b, float cl, float cb, float wl, float wb)
    {
        float dl = l - cl;
        if (dl > 180) dl -= 360; else if (dl < -180) dl += 360;
        return Col.Exp(-(dl / wl) * (dl / wl) - ((b - cb) / wb) * ((b - cb) / wb));
    }

    // The Milky Way's great star clouds, where they are: galactic l and b,
    // widths, brightness.
    static readonly float[,] starClouds = {
        { 0, -3, 14, 7, 0.60f },        // the bulge, around the center
        { 2, -4, 6, 3.5f, 0.90f },      // Large Sagittarius Star Cloud
        { 12, -1, 2.5f, 1.6f, 0.55f },  // Small Sagittarius Star Cloud
        { 27, -2.5f, 3.5f, 2.5f, 0.65f }, // Scutum Star Cloud
        { 48, -1, 7, 2.5f, 0.40f },     // Aquila
        { 77, 1.5f, 9, 3.5f, 0.55f },   // Cygnus
        { 125, 0, 15, 3, 0.25f },       // Cassiopeia
        { -28, -1, 9, 3, 0.30f },       // Norma
        { -50, -0.5f, 9, 3, 0.40f },    // Centaurus
        { -73, -1, 10, 3.5f, 0.50f },   // Carina
    };
    // Glowing gas bright enough to tint the band pink, where it is.
    static readonly float[,] nebulae = {
        { 6.0f, -1.2f, 0.6f, 1.0f },      // Lagoon
        { 7.0f, -0.3f, 0.4f, 0.6f },      // Trifid
        { 15.1f, -0.7f, 0.4f, 0.6f },     // Omega
        { 17.0f, 0.8f, 0.5f, 0.5f },      // Eagle
        { 85.6f, -1.0f, 1.4f, 0.8f },     // North America
        { -72.4f, -0.6f, 1.0f, 0.8f },    // Carina
        { -153.7f, -2.1f, 0.8f, 0.5f },   // Rosette
        { -151.0f, -19.4f, 0.6f, 0.5f },  // Orion
    };

    /// The Milky Way at galactic longitude `l` (−180…180°) and latitude `b`.
    /// The sky is bent first, so the band meanders and every edge frays. Then
    /// a band, widest toward the center, and the great star clouds where they
    /// are, mottled at every scale; then dust in front of them. Returns the
    /// light (about 0…4), how warm it is (the bulge, and light reddened by
    /// dust), and the pink of glowing gas.
    public static float[] MilkyWay(float l0, float b0)
    {
        if (Math.Abs(b0) >= 50) return new float[] { 0, 0, 0 };
        float l = l0 + 3 * SkyNoise(l0, b0, 24, 3, 0x9e3779b9);
        float b = b0 + 2 * SkyNoise(l0, b0, 8, 4, 0x7f4a7c15);
        float toward = 0.5f + 0.5f * (float)Math.Cos(l * (float)Math.PI / 180);  // 1 toward the center, 0 away
        float width = 3 + 3.5f * toward + 1.2f * SkyNoise(l0, 0, 30, 2, 0x165667b1);
        float light = (0.16f + 0.36f * toward * toward) * Col.Exp(-Sq(b / width) / 2)  // the band
            + (0.08f + 0.14f * toward) * Col.Exp(-Sq(b / (3 * width)) / 2);         // its faint outer glow
        for (int i = 0; i < starClouds.GetLength(0); i++)
            light += starClouds[i, 4] * Patch(l, b, starClouds[i, 0], starClouds[i, 1], starClouds[i, 2], starClouds[i, 3]);
        light *= 0.6f + 0.8f * Col.Smoothstep(-0.5f, 0.6f, SkyNoise(l, b, 2.5f, 5, 0x2f6b9d1e));
        // Dust: the Great Rift from Cygnus down to Sagittarius, the dark clouds
        // of Ophiuchus north of the center, the Coalsack, and wisps and lanes
        // drawn out along the plane.
        float clouds = SkyNoise(l, b, 2.2f, 5, 0x5a1c3e77);
        float lane = Col.Pow(1 - Math.Abs(SkyNoise(l, b, 3, 4, 0x27d4eb2f, 3)), 10);
        float wisps = SkyNoise(l, b, 2, 5, 0x3c6ef372, 3);
        float path = 1 + 2.5f * Col.Smoothstep(40, -5, l) + 1.5f * SkyNoise(l0, 0, 14, 2, 0x85ebca6b);
        float rift = Col.Smoothstep(95, 70, l) * Col.Smoothstep(-25, -5, l) * Col.Exp(-Sq((b - path) / 2.4f));
        float ophiuchus = Col.Smoothstep(-25, -10, l) * Col.Smoothstep(18, 4, l) * Col.Smoothstep(2, 6, b) * Col.Smoothstep(24, 10, b);
        float dust = rift * (0.5f + 0.7f * Col.Smoothstep(-0.15f, 0.15f, clouds))
            + 0.9f * ophiuchus * Col.Smoothstep(0.15f, 0.35f, clouds)
            + 0.85f * Patch(l, b, -59.5f, -0.5f, 3, 2.5f)  // the Coalsack
            + Col.Exp(-Sq(b / 6)) * (0.35f * lane + 0.6f * Col.Smoothstep(0.15f, 0.4f, wisps));
        float through = Col.Exp(-2.2f * dust);
        float pink = 0;
        for (int i = 0; i < nebulae.GetLength(0); i++)
            pink += nebulae[i, 3] * Patch(l0, b0, nebulae[i, 0], nebulae[i, 1], nebulae[i, 2], nebulae[i, 2]);
        float warm = Col.Clamp01(0.6f * Patch(l, b, 0, -3, 14, 8) + 0.2f * (1 - through));
        return new float[] { light * through, warm, pink * through };
    }

    /// The zodiacal light: sunlight on dust in the planets' plane, a soft cone
    /// along the ecliptic, brighter toward the sun. `dl` is the angle from the
    /// sun along the ecliptic, `beta` the ecliptic latitude, in degrees.
    public static float Zodiacal(float dl, float beta)
    {
        float e = Math.Max(dl, 20), width = 8 + 0.15f * e;
        return Col.Pow(30 / e, 1.5f) * Col.Exp(-(beta / width) * (beta / width));
    }

    // The near side's great maria and two bright craters, in the moon's own
    // frame: x toward Mare Crisium (west in our sky), y north, both −1…1.
    static readonly float[,] maria = {
        { -0.68f, 0.30f, 0.34f, 0.42f, 0.30f },   // Oceanus Procellarum
        { -0.62f, -0.02f, 0.29f, 0.29f, 0.28f },
        { -0.80f, 0.55f, 0.20f, 0.16f, 0.26f },
        { -0.27f, 0.52f, 0.34f, 0.29f, 0.32f },   // Imbrium
        { -0.05f, 0.80f, 0.52f, 0.08f, 0.26f },   // Frigoris
        { 0.25f, 0.44f, 0.21f, 0.20f, 0.32f },    // Serenitatis
        { 0.45f, 0.14f, 0.25f, 0.21f, 0.32f },    // Tranquillitatis
        { 0.79f, 0.28f, 0.09f, 0.13f, 0.34f },    // Crisium
        { 0.66f, -0.13f, 0.16f, 0.20f, 0.28f },   // Fecunditatis
        { 0.52f, -0.27f, 0.10f, 0.10f, 0.26f },   // Nectaris
        { -0.22f, -0.36f, 0.23f, 0.17f, 0.26f },  // Nubium
        { -0.55f, -0.41f, 0.12f, 0.12f, 0.28f },  // Humorum
        { -0.35f, -0.08f, 0.22f, 0.18f, 0.24f },  // Insularum, Cognitum
        { 0.05f, 0.22f, 0.12f, 0.09f, 0.24f },    // Vaporum
    };
    static readonly float[,] craters = {
        { -0.14f, -0.69f, 0.035f, 0.35f },  // Tycho
        { -0.33f, 0.17f, 0.025f, 0.20f },   // Copernicus
    };

    /// How bright the moon's surface is at (x, y), relative to the highlands.
    public static float MoonAlbedo(float x, float y)
    {
        float dark = 0, bright = 0;
        float edge = Col.Fbm2(x * 4, y * 4, 2, 0x1b873593);  // ragged shores
        for (int i = 0; i < maria.GetLength(0); i++)
        {
            float u = (x - maria[i, 0]) / maria[i, 2], v = (y - maria[i, 1]) / maria[i, 3];
            dark = Math.Max(dark, maria[i, 4] * (1 - Col.Smoothstep(0.6f, 1.2f, Col.Sqrt(u * u + v * v) + 0.3f * edge)));
        }
        for (int i = 0; i < craters.GetLength(0); i++)
        {
            float r2 = ((x - craters[i, 0]) * (x - craters[i, 0]) + (y - craters[i, 1]) * (y - craters[i, 1])) / (craters[i, 2] * craters[i, 2]);
            bright += craters[i, 3] * Col.Exp(-r2);
        }
        return 1 - dark + bright + 0.05f * Col.Fbm2(x * 6, y * 6, 3, 0x3c6ef372);
    }
}
