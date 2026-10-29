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
        RGB vivid = Col.Mix(new RGB(y, y, y), c, 1.6f);
        return new RGB(Math.Max(vivid.R, 0), Math.Max(vivid.G, 0), Math.Max(vivid.B, 0)) * (1 / y);
    }

    static float Sq(float x) { return x * x; }

    static float BandNoise(float l, float b, float k, uint seed)  // seamless across l = ±180°
    {
        float a = Col.Fbm2(l / k, b / k, 4, seed);
        if (l <= 150) return a;
        return Col.Lerp(a, Col.Fbm2((l - 360) / k, b / k, 4, seed), Col.Smoothstep(150, 180, l));
    }

    /// The Milky Way's glow at galactic longitude `l` (−180…180°) and latitude
    /// `b`: a band widest and brightest toward the center in Sagittarius, star
    /// clouds along it, and dust: the Great Rift from Cygnus down to
    /// Sagittarius, the Coalsack, fine lanes. Returns brightness, about 0…1.5,
    /// and the share of it that is the bulge's warmer light.
    public static float[] MilkyWay(float l, float b)
    {
        if (Math.Abs(b) >= 40) return new float[] { 0, 0 };
        float toward = 0.5f + 0.5f * (float)Math.Cos(l * (float)Math.PI / 180);  // 1 toward the center, 0 away
        float along = 0.22f + 0.55f * toward * toward
            + 0.35f * Col.Exp(-Sq((l - 75) / 16))   // Cygnus
            + 0.30f * Col.Exp(-Sq((l + 72) / 22))   // Carina and Crux
            + 0.12f * Col.Exp(-Sq((l - 135) / 30)); // Cassiopeia and Perseus
        float clouds = 0.5f + 0.5f * BandNoise(l, b, 7, 0x2f6b9d1e);
        float disk = along * Col.Exp(-Sq(b / (4.5f + 4 * toward)) / 2) * (0.55f + 0.9f * clouds);
        float bulge = 0.8f * Col.Exp(-Sq(l / 13) - Sq(b / 9)) * (0.7f + 0.6f * clouds);
        float lanes = 0.5f + 0.5f * BandNoise(l, b, 2.5f, 0x5a1c3e77);
        float rift = Col.Smoothstep(95, 72, l) * Col.Smoothstep(-30, -8, l)
            * Col.Exp(-Sq((b - 1 - 3 * Col.Smoothstep(40, 0, l)) / (1.6f + 1.2f * lanes)));
        float coalsack = Col.Exp(-(Sq(l + 59.5f) + Sq(b + 0.5f)) / 10);
        float dust = Col.Clamp01(0.6f * rift * (0.6f + 0.6f * lanes) + 0.7f * coalsack
                                 + 0.3f * Col.Smoothstep(0.62f, 0.85f, lanes) * Col.Exp(-Sq(b / 5)));
        float total = disk + bulge;
        return new float[] { total * (1 - dust), bulge / Math.Max(total, 1e-6f) };
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
