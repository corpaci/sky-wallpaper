// Port of Sources/wallframes/Scene.swift. Keep the two in step:
// windows/parity.sh renders the same frames with both and compares pixels.

using System;
using System.Linq;
using System.Threading.Tasks;

/// A stylized sun: a sine arc between sunrise and sunset, and a deeper one
/// below the horizon at night. Altitudes in degrees, times in local minutes.
sealed class SunModel
{
    public const float Peak = 38, Depth = 40;
    public readonly int Sunrise, Sunset;

    public SunModel(int sunrise, int sunset) { Sunrise = sunrise; Sunset = sunset; }

    public float DayLength { get { return Sunset - Sunrise; } }
    public float NightLength { get { return 1440 - DayLength; } }
    public int Noon { get { return (Sunrise + Sunset) / 2; } }
    public int Midnight { get { return (Sunset + (int)NightLength / 2) % 1440; } }

    /// 0 at sunrise … 1 at sunset; null at night.
    public float? DayPhase(int minute)
    {
        float p = (minute - Sunrise) / DayLength;
        return p >= 0 && p <= 1 ? p : (float?)null;
    }

    /// 0 at sunset … 1 at sunrise; above 1 during the day.
    public float NightPhase(int minute)
    {
        return (((minute - Sunset) % 1440 + 1440) % 1440) / NightLength;
    }

    public float Altitude(int minute)
    {
        float? p = DayPhase(minute);
        if (p.HasValue) return Peak * (float)Math.Sin((float)Math.PI * p.Value);
        return -Depth * (float)Math.Sin((float)Math.PI * NightPhase(minute));
    }

    /// When the sun crosses `alt`, on the morning or the evening side.
    public int MinuteAt(float alt, bool evening)
    {
        float t;
        if (alt >= 0)
        {
            float d = DayLength * (float)Math.Asin(Math.Min(alt / Peak, 1f)) / (float)Math.PI;
            t = evening ? Sunset - d : Sunrise + d;
        }
        else
        {
            float d = NightLength * (float)Math.Asin(Math.Min(-alt / Depth, 1f)) / (float)Math.PI;
            t = evening ? Sunset + d : Sunrise - d;
        }
        return ((int)Math.Round(t, MidpointRounding.AwayFromZero) % 1440 + 1440) % 1440;
    }
}

/// The sky at one sun altitude, linear light. `Land` is the nearest ridge;
/// farther ridges fade toward `Horizon`.
struct Palette
{
    public RGB Zenith, Mid, Horizon, Glow, Land;

    public static Palette Blend(Palette p, Palette q, float t)
    {
        Palette r;
        r.Zenith = Col.MixOklab(p.Zenith, q.Zenith, t);
        r.Mid = Col.MixOklab(p.Mid, q.Mid, t);
        r.Horizon = Col.MixOklab(p.Horizon, q.Horizon, t);
        r.Glow = Col.MixOklab(p.Glow, q.Glow, t);
        r.Land = Col.MixOklab(p.Land, q.Land, t);
        return r;
    }
}

static class Palettes
{
    struct Key { public float Alt; public Palette P; }

    static Key K(float alt, uint zenith, uint mid, uint horizon, uint glow, uint land)
    {
        Key k;
        k.Alt = alt;
        k.P.Zenith = RGB.Hex(zenith);
        k.P.Mid = RGB.Hex(mid);
        k.P.Horizon = RGB.Hex(horizon);
        k.P.Glow = RGB.Hex(glow);
        k.P.Land = RGB.Hex(land);
        return k;
    }

    // Keyframes by sun altitude. Mornings run clean and cool; evenings carry
    // more haze, so their horizon goes to coral and rose. Both share the night.
    static readonly Key[] Night = {
        K(-18, 0x070b18, 0x0c1328, 0x18203f, 0x202a52, 0x04060d),
        K(-10, 0x0b1430, 0x17224a, 0x33386a, 0x4a4580, 0x070a18),
    };
    static readonly Key[] Morning = Night.Concat(new[] {
        K(-5, 0x13224f, 0x2e3f78, 0x7a6a9c, 0x9a7aa8, 0x0e1228),
        K(-1.5f, 0x1f3a75, 0x5a6fae, 0xf2a387, 0xffb38f, 0x1c1d3a),
        K(1, 0x2f5a9e, 0x8aa3d4, 0xffc08a, 0xffcf8a, 0x2a2a48),
        K(6, 0x3a72b8, 0x9fc0e4, 0xffe2b3, 0xfff0c8, 0x2f3d58),
        K(15, 0x3b80c8, 0x86bbe6, 0xd6ebf5, 0xfffaf0, 0x2c4558),
        K(35, 0x2c72c0, 0x6eaee3, 0xc4e3f4, 0xfffaf0, 0x2a4656),
    }).ToArray();
    static readonly Key[] Evening = Night.Concat(new[] {
        K(-5, 0x141f4c, 0x3a3a78, 0x9a5f8e, 0xb0688f, 0x120f26),
        K(-1.5f, 0x23336e, 0x7a5f9e, 0xff7f6a, 0xff8f6a, 0x241a38),
        K(1, 0x34528f, 0xb08fb8, 0xffa36b, 0xffb070, 0x2e2440),
        K(6, 0x3d6aa8, 0xb4c0dc, 0xffd09a, 0xffe0a8, 0x363852),
        K(15, 0x3b7cc2, 0x8fbbe2, 0xe6ecef, 0xfff6e6, 0x2e4458),
        K(35, 0x2c72c0, 0x6eaee3, 0xc4e3f4, 0xfffaf0, 0x2a4656),
    }).ToArray();

    public static Palette At(float alt, bool evening)
    {
        Key[] keys = evening ? Evening : Morning;
        if (alt <= keys[0].Alt) return keys[0].P;
        for (int i = 1; i < keys.Length; i++)
        {
            if (alt <= keys[i].Alt)
                return Palette.Blend(keys[i - 1].P, keys[i].P, (alt - keys[i - 1].Alt) / (keys[i].Alt - keys[i - 1].Alt));
        }
        return keys[keys.Length - 1].P;
    }
}

/// A layered ridge landscape under a sky. Geometry is fixed per seed; only
/// light changes between frames.
sealed class Scene
{
    sealed class Layer
    {
        public readonly float Base, Amp, Freq;  // ridge line in fractions of height; cycles per height
        public readonly float Haze;             // 0 = land color, 1 = horizon color
        public readonly float Mist;             // valley mist toward the layer's foot
        public readonly bool Ridged;            // sharp peaks instead of rolling hills

        public Layer(float b, float amp, float freq, float haze, float mist, bool ridged)
        {
            Base = b; Amp = amp; Freq = freq; Haze = haze; Mist = mist; Ridged = ridged;
        }
    }

    static readonly Layer[] Layers = {
        new Layer(0.610f, 0.085f, 1.9f, 0.72f, 0.25f, true),
        new Layer(0.672f, 0.075f, 1.5f, 0.52f, 0.30f, true),
        new Layer(0.740f, 0.065f, 1.2f, 0.34f, 0.30f, false),
        new Layer(0.815f, 0.065f, 0.95f, 0.18f, 0.24f, false),
        new Layer(0.905f, 0.055f, 0.75f, 0.00f, 0.12f, false),
    };

    public readonly int Width, Height;
    readonly float W, H;
    readonly float horizonY;  // where altitude 0 sits
    readonly float[] ridge;   // [layer * width + x] ridge-line y
    readonly float[] edge;    // [layer * width + x] 1/√(1+slope²), for antialiasing
    readonly float[] stars;   // linear RGB, full frame

    public Scene(int width, int height, uint seed)
    {
        Width = width;
        Height = height;
        W = width;
        H = height;
        horizonY = 0.64f * H;

        ridge = new float[Layers.Length * width];
        edge = new float[Layers.Length * width];
        for (int l = 0; l < Layers.Length; l++)
        {
            uint s = Col.Hash32(unchecked(seed * 0x2545f491 + (uint)l));
            for (int x = 0; x < width; x++)
            {
                float fx = x + 0.5f;
                float slope = (RidgeY(Layers[l], s, fx + 1) - RidgeY(Layers[l], s, fx - 1)) / 2;
                ridge[l * width + x] = RidgeY(Layers[l], s, fx);
                edge[l * width + x] = 1 / Col.Sqrt(1 + slope * slope);
            }
        }

        // Stars: mostly faint, a few bright, thinning toward the horizon.
        stars = new float[width * height * 3];
        var rng = new SplitMix(unchecked((ulong)seed * 0x9e3779b97f4a7c15));
        float scale = H / 1664;
        int count = width * height / 4500;
        for (int n = 0; n < count; n++)
        {
            float sx = rng.Unit() * W;
            float sy = Col.Pow(rng.Unit(), 1.3f) * horizonY * 0.98f;
            float mag = Col.Pow(rng.Unit(), 4);
            RGB tint = Col.Mix(RGB.Hex(0xc9d6ff), RGB.Hex(0xfff1d6), rng.Unit())
                * ((0.05f + 0.9f * mag) * Col.Smoothstep(horizonY, horizonY * 0.55f, sy));
            float sigma = (0.55f + 0.9f * mag) * scale;
            int reach = (int)Math.Ceiling(3 * sigma);
            int cx = (int)sx, cy = (int)sy;
            for (int py = Math.Max(cy - reach, 0); py <= Math.Min(cy + reach, height - 1); py++)
            {
                for (int px = Math.Max(cx - reach, 0); px <= Math.Min(cx + reach, width - 1); px++)
                {
                    float dx = px + 0.5f - sx, dy = py + 0.5f - sy;
                    float k = Col.Exp(-(dx * dx + dy * dy) / (2 * sigma * sigma));
                    int i = (py * width + px) * 3;
                    stars[i] += tint.R * k;
                    stars[i + 1] += tint.G * k;
                    stars[i + 2] += tint.B * k;
                }
            }
        }
    }

    float RidgeY(Layer layer, uint s, float x)
    {
        float u = (x - W / 2) / H * layer.Freq;
        float shape = layer.Ridged
            ? 0.8f * (1 - 2.4f * Math.Abs(Col.Fbm(u, 4, s))) + 0.25f * Col.Fbm(u * 7, 3, s ^ 0x5bd1e995)
            : 1.5f * Col.Fbm(u, 5, s);
        return (layer.Base - layer.Amp * shape) * H;
    }

    /// One frame as 8-bit sRGB, 3 bytes per pixel, dithered. `salt` varies the
    /// dither per frame.
    public byte[] Render(int minute, SunModel sun, uint salt)
    {
        float alt = sun.Altitude(minute);
        float? dayPhase = sun.DayPhase(minute);
        bool evening = dayPhase.HasValue ? dayPhase.Value >= 0.5f : sun.NightPhase(minute) < 0.5f;
        Palette pal = Palettes.At(alt, evening);
        float span = horizonY - 0.14f * H;

        // Sun: rises left, sets right; below the horizon it waits at its side.
        float p = dayPhase.HasValue ? dayPhase.Value : (evening ? 1 : 0);
        float sunX = W * (0.5f + (p - 0.5f) * 0.8f), sunY = horizonY - alt / SunModel.Peak * span;
        float sunR = 0.021f * H;
        float sunVis = Col.Smoothstep(-1.5f, 0.5f, alt);
        RGB sunColor = Col.Mix(pal.Glow * 1.6f, new RGB(1, 0.97f, 0.9f) * 1.4f, Col.Smoothstep(2, 20, alt));
        float low = Col.Smoothstep(-8, -1, alt) * (1 - Col.Smoothstep(4, 20, alt));
        float day = Col.Smoothstep(0, 15, alt);
        float gNear = 0.44f * low + 0.28f * day, gFar = 0.40f * low + 0.10f * day, gBand = 0.30f * low;
        float rNear = 0.06f * H, rFar = 0.32f * H, bandH = 0.07f * H, bandW = 0.55f * W;

        // Moon: crosses the night the same way, a fat crescent.
        float q = Math.Min(sun.NightPhase(minute), 1f);
        float moonVis = dayPhase.HasValue ? 0 : Col.Smoothstep(-1, -8, alt);
        float moonX = W * (0.5f + (q - 0.5f) * 0.8f), moonY = horizonY - 30 * (float)Math.Sin((float)Math.PI * q) / SunModel.Peak * span;
        float moonR = 0.017f * H;
        RGB moonColor = RGB.Hex(0xf3efe0), moonGlow = RGB.Hex(0x9fb4d8);

        float starVis = Col.Smoothstep(-4, -14, alt);
        var sky = new RGB[Height];
        for (int y = 0; y < Height; y++)
        {
            float s = Col.Clamp01((y + 0.5f) / horizonY);
            sky[y] = s < 0.55f ? Col.MixOklab(pal.Zenith, pal.Mid, s / 0.55f)
                               : Col.MixOklab(pal.Mid, pal.Horizon, Col.Pow((s - 0.55f) / 0.45f, 1.4f));
        }
        RGB fog = pal.Horizon;
        var tones = new RGB[Layers.Length];
        for (int l = 0; l < Layers.Length; l++) tones[l] = Col.MixOklab(pal.Land, fog, Layers[l].Haze);
        float mistDepth = 0.10f * H;
        int width = Width;

        var px = new byte[Width * Height * 3];
        Parallel.For(0, Height, y =>
        {
            float fy = y + 0.5f;
            for (int x = 0; x < width; x++)
            {
                float fx = x + 0.5f;
                float dx = fx - sunX, dy = fy - sunY;
                float d = Col.Sqrt(dx * dx + dy * dy);
                float g = gNear * Col.Exp(-d / rNear) + gFar * Col.Exp(-d / rFar)
                    + gBand * Col.Exp(-Math.Abs(fy - horizonY) / bandH) * Col.Exp(-Math.Abs(dx) / bandW);
                RGB c = sky[y] + pal.Glow * g;
                RGB air = c;  // sky without stars
                if (starVis > 0)
                {
                    int i = (y * width + x) * 3;
                    c = c + new RGB(stars[i], stars[i + 1], stars[i + 2]) * starVis;
                }
                if (sunVis > 0)
                {
                    float cov = Col.Clamp01(sunR - d + 0.5f) * sunVis;
                    if (cov > 0) c = Col.Mix(c, sunColor, cov);
                }
                if (moonVis > 0)
                {
                    float mx = fx - moonX, my = fy - moonY;
                    float md = Col.Sqrt(mx * mx + my * my);
                    RGB halo = moonGlow * (0.05f * moonVis * Col.Exp(-md / (0.05f * H)));
                    c = c + halo;
                    float disk = Col.Clamp01(moonR - md + 0.5f) * moonVis;
                    if (disk > 0)
                    {
                        float sx = mx - 0.45f * moonR, sy = my + 0.2f * moonR;
                        float shadow = Col.Clamp01(0.95f * moonR - Col.Sqrt(sx * sx + sy * sy) + 0.5f);
                        c = Col.Mix(c, air + halo + moonColor * 0.004f, disk);  // earthshine; hides stars
                        c = Col.Mix(c, moonColor, disk * (1 - shadow));
                    }
                }

                for (int l = 0; l < Layers.Length; l++)
                {
                    float ry = ridge[l * width + x];
                    float cov = Col.Clamp01((fy - ry) * edge[l * width + x] + 0.5f);
                    if (cov == 0) continue;
                    Layer layer = Layers[l];
                    RGB tone = Col.Mix(tones[l], fog, layer.Mist * Col.Smoothstep(0, mistDepth, fy - ry));
                    tone = tone + pal.Glow * (g * layer.Haze * 0.8f);  // in-scattered sun
                    c = cov == 1 ? tone : Col.Mix(c, tone, cov);
                }

                int o = (y * width + x) * 3;
                uint h = unchecked((uint)((y * width + x) * 3) ^ salt);
                px[o] = Quantize(c.R, h);
                px[o + 1] = Quantize(c.G, unchecked(h + 1));
                px[o + 2] = Quantize(c.B, unchecked(h + 2));
            }
        });
        return px;
    }

    /// Linear → sRGB 8-bit with a soft highlight shoulder and ±1 LSB triangular
    /// dither, so slow gradients do not band on an 8-bit panel.
    static byte Quantize(float v, uint h)
    {
        float x = Math.Max(v, 0f);
        float shoulder = x < 0.8f ? x : 0.8f + 0.2f * (1 - Col.Exp(-(x - 0.8f) / 0.2f));
        uint a = Col.Hash32(h), b = Col.Hash32(a ^ 0x68bc21eb);
        float s = Col.LinearToSrgb(shoulder) * 255 + Col.Unit(a) + Col.Unit(b) - 1;
        return (byte)Math.Min(Math.Max(Math.Round(s, MidpointRounding.AwayFromZero), 0), 255);
    }
}
