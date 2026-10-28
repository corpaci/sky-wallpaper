// Port of Sources/wallframes/Scene.swift. Keep the two in step:
// windows/parity.sh renders the same frames with both and compares pixels.

using System;
using System.Collections.Generic;
using System.Linq;
using System.Threading.Tasks;

/// A thick line that tapers from R0 to R1: a trunk, branch or plank.
struct Capsule
{
    public readonly float X0, Y0, X1, Y1, R0, R1;

    public Capsule(float x0, float y0, float x1, float y1, float r0, float r1)
    {
        X0 = x0; Y0 = y0; X1 = x1; Y1 = y1; R0 = r0; R1 = r1;
    }
}

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

    /// Under a cloud deck: greyer and darker, the sky more than the land.
    public Palette Overcast(float k)
    {
        Palette r;
        r.Zenith = Grey(Zenith, 0.35f, k);
        r.Mid = Grey(Mid, 0.25f, k);
        r.Horizon = Grey(Horizon, 0.2f, k);
        r.Glow = Grey(Glow, 0.3f, k);
        r.Land = Grey(Land, 0.2f, k);
        return r;
    }

    static RGB Grey(RGB c, float dim, float k) { return Col.Desaturate(c, 0.8f * k) * (1 - dim * k); }
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

/// A layered landscape under a sky. Geometry is fixed per seed; only light
/// changes between frames.
sealed class Scene
{
    sealed class Layer
    {
        public readonly float Base, Amp, Freq;  // ridge line in fractions of height; cycles per height
        public readonly float Haze;             // 0 = land color, 1 = horizon color
        public readonly float Mist;             // valley mist toward the layer's foot
        public readonly bool Ridged;            // sharp peaks instead of rolling hills
        public readonly bool Snow;              // the summit: one massif, snow above a ragged line
        public readonly float Trees;            // pine height in fractions of height; 0 = bare
        public readonly float Forest;           // share of the ridge that is wooded, roughly

        public Layer(float b, float amp, float freq, float haze, float mist, bool ridged, bool snow, float trees, float forest)
        {
            Base = b; Amp = amp; Freq = freq; Haze = haze; Mist = mist; Ridged = ridged; Snow = snow; Trees = trees; Forest = forest;
        }
    }

    // Far to near: a snowcapped summit, a rocky middle range, then rounded
    // wooded hills. The nearest hill carries the cabin.
    static readonly Layer[] Layers = {
        new Layer(0.600f, 0.120f, 1.3f, 0.66f, 0.25f, true, true, 0, 0),
        new Layer(0.680f, 0.060f, 2.2f, 0.48f, 0.30f, true, false, 0, 0),
        new Layer(0.750f, 0.060f, 1.1f, 0.32f, 0.30f, false, false, 0.011f, 0.55f),
        new Layer(0.825f, 0.055f, 0.9f, 0.17f, 0.24f, false, false, 0.019f, 0.6f),
        new Layer(0.910f, 0.045f, 0.7f, 0.00f, 0.12f, false, false, 0.040f, 0.65f),
    };
    const int Sub = 4;  // silhouette samples per pixel column, for clean tree edges

    public readonly int Width, Height;
    readonly float W, H;
    readonly float horizonY;     // where altitude 0 sits
    readonly float[] ground;     // [layer * width + x] terrain line y, trees excluded
    readonly float[] top;        // [(layer * width + x) * Sub + s] silhouette y: land and cabin
    readonly byte[] trees;       // [(layer * height + y) * width + x] coverage of trees and porch, 0…255
    readonly float[] snowLine;   // [x] for the snowy layer
    readonly float[] snowSlope;  // [x] its slope over ±3% of the height, so shading blends, not splits
    readonly float windowX0, windowX1, windowY0, windowY1;  // the cabin's window
    readonly float[] stars;      // linear RGB, full frame
    readonly float[] flakes;     // snowflake coverage, full frame
    readonly uint seed;

    public Scene(int width, int height, uint seed)
    {
        this.seed = seed;
        Width = width;
        Height = height;
        W = width;
        H = height;
        horizonY = 0.64f * H;

        ground = new float[Layers.Length * width];
        top = new float[Layers.Length * width * Sub];
        snowLine = new float[width];
        snowSlope = new float[width];
        int near = Layers.Length - 1;
        float cabinX = 0.73f * W, cabinHalf = 0.019f * H;

        for (int l = 0; l < Layers.Length; l++)
        {
            Layer layer = Layers[l];
            uint s = Col.Hash32(unchecked(seed * 0x2545f491 + (uint)l));
            int row = l * width;
            for (int x = 0; x < width; x++) ground[row + x] = Terrain(layer, s, x + 0.5f);
            for (int i = 0; i < width * Sub; i++) top[row * Sub + i] = Terrain(layer, s, (i + 0.5f) / Sub);
            if (layer.Snow)
            {
                int r = Math.Max((int)(0.03f * H), 1);
                for (int x = 0; x < width; x++)
                {
                    snowLine[x] = (layer.Base - layer.Amp * 0.42f) * H + 0.010f * H * Col.Fbm(x / H * 14, 3, s ^ 0x7f4a7c15);
                    snowSlope[x] = (Terrain(layer, s, x + r + 0.5f) - Terrain(layer, s, x - r + 0.5f)) / (2 * r);
                }
            }
        }
        Func<int, float, float> groundAt = (l, x) => ground[l * width + Math.Min(Math.Max((int)x, 0), width - 1)];

        // The cabin: walls, pitched roof, chimney; one window.
        float cabinBase = groundAt(near, cabinX) + 0.004f * H;
        float wallH = 0.024f * H, roofH = 0.020f * H;
        for (int i = 0; i < width * Sub; i++)
        {
            float cx = (i + 0.5f) / Sub - cabinX;
            float dx = Math.Abs(cx);
            if (dx > cabinHalf * 1.08f) continue;
            float y = cabinBase - wallH - roofH + dx / (cabinHalf * 1.08f) * roofH;
            if (cx > 0.36f * cabinHalf && cx < 0.62f * cabinHalf) y = Math.Min(y, cabinBase - wallH - 0.95f * roofH);
            top[near * width * Sub + i] = Math.Min(top[near * width * Sub + i], y);
        }
        windowX0 = cabinX - 0.55f * cabinHalf;
        windowX1 = cabinX - 0.15f * cabinHalf;
        windowY0 = cabinBase - 0.72f * wallH;
        windowY1 = cabinBase - 0.38f * wallH;

        // What stands on the land and lets the sky through between its parts
        // (trees, the porch) is drawn as 2-D coverage, one plane per layer.
        trees = new byte[Layers.Length * width * height];

        // The porch, on the right: a lean-to roof on two posts, a railing with
        // balusters, and steps down to the ground.
        float porch0 = cabinX + cabinHalf, porch1 = porch0 + 0.9f * cabinHalf;
        float floorY = cabinBase - 0.10f * wallH, railY = cabinBase - 0.48f * wallH;
        float eaveX = porch1 + 0.1f * cabinHalf, eaveY0 = cabinBase - 0.95f * wallH, eaveY1 = cabinBase - 0.68f * wallH;
        Func<float, float> eave = x => eaveY0 + (eaveY1 - eaveY0) * (x - porch0) / (eaveX - porch0);
        var porch = new List<Capsule> {
            new Capsule(porch0, eaveY0, eaveX, eaveY1, 0.055f * wallH, 0.05f * wallH),
            new Capsule(porch0, floorY, porch1, floorY, 0.035f * wallH, 0.035f * wallH),
            new Capsule(porch0, railY, porch1, railY, 0.02f * wallH, 0.02f * wallH),
        };
        foreach (float px in new[] { porch0 + 0.5f * (porch1 - porch0), porch1 })
        {
            float post = 0.045f * cabinHalf;
            porch.Add(new Capsule(px, eave(px), px, groundAt(near, px) + 0.002f * H, post, post));
        }
        for (int k = 1; k < 6; k++)
        {
            float bx = porch0 + k / 6f * (porch1 - porch0);
            porch.Add(new Capsule(bx, railY, bx, floorY, 0.012f * wallH, 0.012f * wallH));
        }
        float drop = groundAt(near, porch1 + 0.3f * cabinHalf) - floorY;
        if (drop > 0.08f * wallH)
        {
            for (int k = 1; k <= 2; k++)
            {
                float sy = floorY + k / 3f * drop;
                porch.Add(new Capsule(porch1, sy, porch1 + k * 0.22f * cabinHalf, sy, 0.03f * wallH, 0.03f * wallH));
            }
        }
        Stamp(porch, trees, near, width, height);

        // Spruces in woods and clearings along the ridges, tallest in front.
        for (int l = 0; l < Layers.Length; l++)
        {
            Layer layer = Layers[l];
            if (layer.Trees <= 0) continue;
            uint s = Col.Hash32(unchecked(seed * 0x2545f491 + (uint)l));
            var rng = new SplitMix(unchecked(((ulong)s * 0x9e3779b97f4a7c15) | 1));
            float tallest = layer.Trees * H;
            float tx = -tallest;
            uint n = 0;
            while (tx < W + tallest)
            {
                float th = tallest * (0.6f + 0.7f * rng.Unit());
                float hw = th * 0.24f;
                tx += hw * (0.9f + 1.4f * rng.Unit());
                n = unchecked(n + 1);
                float wood = Col.Fbm(tx / H * 2.2f, 2, s ^ 0x9e3779b9) * 0.5f + 0.5f;
                if (wood > layer.Forest) continue;
                if (l == near && tx > cabinX - cabinHalf - 2 * hw && tx < porch1 + 0.6f * cabinHalf + 2 * hw) continue;
                Stamp(Spruce(tx, Terrain(layer, s, tx) + 0.06f * th, th, Col.Hash32(s ^ unchecked(n * 0x9e3779b1)), th > 30 ? 2 : 1),
                      trees, l, width, height);
            }
        }
        // Three tall ones by the cabin, where the branches can be seen.
        float[] heroAt = { cabinX - 3.0f * cabinHalf, cabinX - 4.9f * cabinHalf, porch1 + 2.4f * cabinHalf };
        float[] heroSize = { 0.105f, 0.075f, 0.088f };
        for (int k = 0; k < 3; k++)
        {
            float th = heroSize[k] * H;
            Stamp(Spruce(heroAt[k], groundAt(near, heroAt[k]) + 0.03f * th, th, Col.Hash32(seed ^ unchecked((uint)(k + 1) * 0x85ebca6b)), 2),
                  trees, near, width, height);
        }

        // Stars: mostly faint, a few bright, thinning toward the horizon.
        stars = new float[width * height * 3];
        var starRng = new SplitMix(unchecked((ulong)seed * 0x9e3779b97f4a7c15));
        float scale = H / 1664;
        int count = width * height / 4500;
        for (int n = 0; n < count; n++)
        {
            float sx = starRng.Unit() * W;
            float sy = Col.Pow(starRng.Unit(), 1.3f) * horizonY * 0.98f;
            float mag = Col.Pow(starRng.Unit(), 4);
            RGB tint = Col.Mix(RGB.Hex(0xc9d6ff), RGB.Hex(0xfff1d6), starRng.Unit())
                * ((0.05f + 0.9f * mag) * Col.Smoothstep(horizonY, horizonY * 0.55f, sy));
            float sigma = (0.55f + 0.9f * mag) * scale;
            int reach = (int)Math.Ceiling(3 * sigma);
            int cxs = (int)sx, cys = (int)sy;
            for (int py = Math.Max(cys - reach, 0); py <= Math.Min(cys + reach, height - 1); py++)
            {
                for (int px = Math.Max(cxs - reach, 0); px <= Math.Min(cxs + reach, width - 1); px++)
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

        // Snowflakes: soft dots, the big near ones rarer. Drawn only when it snows.
        flakes = new float[width * height];
        var flakeRng = new SplitMix(unchecked(((ulong)seed * 0xd1b54a32d192ed03) | 1));
        int flakeCount = width * height / 2200;
        for (int n = 0; n < flakeCount; n++)
        {
            float fx = flakeRng.Unit() * W, fy = flakeRng.Unit() * H;
            float nearness = Col.Pow(flakeRng.Unit(), 3);
            float bright = 0.55f + 0.45f * flakeRng.Unit();
            float sigma = (0.6f + 1.8f * nearness) * scale;
            int reach = (int)Math.Ceiling(3 * sigma);
            int cxf = (int)fx, cyf = (int)fy;
            for (int py = Math.Max(cyf - reach, 0); py <= Math.Min(cyf + reach, height - 1); py++)
            {
                for (int px = Math.Max(cxf - reach, 0); px <= Math.Min(cxf + reach, width - 1); px++)
                {
                    float dx = px + 0.5f - fx, dy = py + 0.5f - fy;
                    flakes[py * width + px] += bright * Col.Exp(-(dx * dx + dy * dy) / (2 * sigma * sigma));
                }
            }
        }
    }

    float Terrain(Layer layer, uint s, float x)
    {
        float u = (x - W / 2) / H * layer.Freq;
        float shape;
        if (layer.Snow)
        {
            // Ridged multifractal, domain-warped so crests lean, on a slow
            // swell that lifts one massif above the rest.
            float warp = 0.25f * Col.Fbm(u * 0.6f, 2, s ^ 0x27d4eb2f);
            shape = 2.4f * Col.Ridged(u + warp, 6, s) - 0.7f
                + 0.6f * Col.Fbm(u * 0.35f, 2, s ^ 0x165667b1);
        }
        else if (layer.Ridged)
        {
            shape = 0.75f * (0.8f * (1 - 2.4f * Math.Abs(Col.Fbm(u, 4, s))) + 0.25f * Col.Fbm(u * 7, 3, s ^ 0x5bd1e995));
        }
        else
        {
            shape = 1.5f * Col.Fbm(u, 3, s);  // few octaves: soft, rounded hills
        }
        return (layer.Base - layer.Amp * shape) * H;
    }

    /// A spruce as capsules. A tapering trunk carries 21 whorls (a Fibonacci
    /// number) up a cone, alternately 5 and 3 branches each, every branch turned
    /// by the golden angle from the one before, so its sideways reach (the
    /// cosine of that turn) varies the way phyllotaxis spaces real branches.
    /// Each branch rises near the top and droops near the foot, bends down
    /// toward its tip, and carries smaller copies of itself 0.382 (1/φ²) as
    /// long, `maxDepth` levels deep.
    static List<Capsule> Spruce(float x, float b, float th, uint seed, int maxDepth)
    {
        var caps = new List<Capsule>();
        var rng = new SplitMix(unchecked(((ulong)seed * 0x9e3779b97f4a7c15) | 1));
        const float golden = 2.399963f;  // 137.5° in radians
        float top = b - th;
        caps.Add(new Capsule(x, b, x, top + 0.05f * th, 0.02f * th, 0.005f * th));
        for (int k = 0; k < 21; k++)
        {
            float t = (k + 0.5f) / 21;  // up the trunk
            float y = b - th * (0.10f + 0.86f * t);
            float reach = th * (0.03f + 0.24f * Col.Pow(1 - t, 0.95f)) * (0.85f + 0.3f * rng.Unit());
            int count = k % 2 == 0 ? 5 : 3;
            for (int j = 0; j < count; j++)
            {
                float turn = (k * 8 + j) * golden + 0.3f * rng.Unit();
                float side = (float)Math.Cos(turn);
                Branch(caps, rng, x, y, reach * (0.3f + 0.7f * Math.Abs(side)), side < 0 ? -1 : 1, -0.35f + 0.6f * (1 - t),
                       0.026f * th * (1 - 0.6f * t), 0, maxDepth);
            }
        }
        caps.Add(new Capsule(x, top + 0.08f * th, x, top, 0.006f * th, 0.002f * th));  // leader
        return caps;
    }

    static void Branch(List<Capsule> caps, SplitMix rng, float x, float y, float length, float dir, float angle, float r, int depth, int maxDepth)
    {
        float px = x, py = y, a = angle;
        for (int s = 0; s < 3; s++)
        {
            float len = length / 3;
            float nx = px + dir * (float)Math.Cos(a) * len, ny = py + (float)Math.Sin(a) * len;
            float r0 = r * (1 - 0.2f * s), r1 = r * (1 - 0.2f * (s + 1));
            caps.Add(new Capsule(px, py, nx, ny, r0, r1));
            if (depth < maxDepth)
            {
                float side = s % 2 == 0 ? -1 : 1;  // twigs alternate up and down
                Branch(caps, rng, (px + nx) / 2, (py + ny) / 2, length * 0.382f * (1 - 0.25f * s), dir,
                       a + side * 0.75f + 0.15f, r0 * 0.7f, depth + 1, maxDepth);
            }
            px = nx;
            py = ny;
            a += 0.22f + 0.06f * rng.Unit();
        }
    }

    /// Antialiased coverage of capsules, kept as the maximum per pixel, into one
    /// layer's plane of `cover`.
    static void Stamp(List<Capsule> caps, byte[] cover, int plane, int width, int height)
    {
        int offset = plane * width * height;
        foreach (Capsule c in caps)
        {
            float r = Math.Max(c.R0, c.R1);
            int x0 = Math.Max((int)Math.Floor(Math.Min(c.X0, c.X1) - r - 1), 0), x1 = Math.Min((int)Math.Ceiling(Math.Max(c.X0, c.X1) + r + 1), width - 1);
            int y0 = Math.Max((int)Math.Floor(Math.Min(c.Y0, c.Y1) - r - 1), 0), y1 = Math.Min((int)Math.Ceiling(Math.Max(c.Y0, c.Y1) + r + 1), height - 1);
            if (x0 > x1 || y0 > y1) continue;
            float dx = c.X1 - c.X0, dy = c.Y1 - c.Y0, len2 = dx * dx + dy * dy;
            for (int py = y0; py <= y1; py++)
            {
                for (int px = x0; px <= x1; px++)
                {
                    float fx = px + 0.5f - c.X0, fy = py + 0.5f - c.Y0;
                    float t = len2 > 0 ? Col.Clamp01((fx * dx + fy * dy) / len2) : 0;
                    float ex = fx - t * dx, ey = fy - t * dy;
                    float cov = Col.Clamp01(c.R0 + (c.R1 - c.R0) * t - Col.Sqrt(ex * ex + ey * ey) + 0.5f);
                    byte v = (byte)Math.Round(cov * 255, MidpointRounding.AwayFromZero);
                    int i = offset + py * width + px;
                    if (v > cover[i]) cover[i] = v;
                }
            }
        }
    }

    /// One frame as 8-bit sRGB, 3 bytes per pixel, dithered. `salt` varies the
    /// dither per frame.
    public byte[] Render(int minute, SunModel sun, uint salt)
    {
        return Render(minute, sun, salt, new Weather(Sky.Clear));
    }

    public byte[] Render(int minute, SunModel sun, uint salt, Weather w)
    {
        float alt = sun.Altitude(minute);
        float? dayPhase = sun.DayPhase(minute);
        bool evening = dayPhase.HasValue ? dayPhase.Value >= 0.5f : sun.NightPhase(minute) < 0.5f;
        Palette pal = Palettes.At(alt, evening);
        if (w.Overcast > 0) pal = pal.Overcast(w.Overcast);
        float span = horizonY - 0.14f * H;

        // Sun: rises left, sets right; below the horizon it waits at its side.
        // Cloud and fog veil its disk and glow.
        float veil = (1 - 0.85f * w.Overcast) * (1 - 0.5f * w.Fog);
        float p = dayPhase.HasValue ? dayPhase.Value : (evening ? 1 : 0);
        float sunX = W * (0.5f + (p - 0.5f) * 0.8f), sunY = horizonY - alt / SunModel.Peak * span;
        float sunR = 0.021f * H;
        float sunVis = Col.Smoothstep(-1.5f, 0.5f, alt) * (1 - w.Overcast) * (1 - 0.5f * w.Fog);
        RGB sunColor = Col.Mix(pal.Glow * 1.6f, new RGB(1, 0.97f, 0.9f) * 1.4f, Col.Smoothstep(2, 20, alt));
        float low = Col.Smoothstep(-8, -1, alt) * (1 - Col.Smoothstep(4, 20, alt));
        float day = Col.Smoothstep(0, 15, alt);
        float gNear = (0.44f * low + 0.28f * day) * veil, gFar = (0.40f * low + 0.10f * day) * veil, gBand = 0.30f * low * veil;
        float rNear = 0.06f * H, rFar = 0.32f * H, bandH = 0.07f * H, bandW = 0.55f * W;

        // Moon: crosses the night the same way, a fat crescent.
        float q = Math.Min(sun.NightPhase(minute), 1f);
        float moonVis = (dayPhase.HasValue ? 0 : Col.Smoothstep(-1, -8, alt)) * (1 - 0.95f * w.Overcast);
        float moonX = W * (0.5f + (q - 0.5f) * 0.8f), moonY = horizonY - 30 * (float)Math.Sin((float)Math.PI * q) / SunModel.Peak * span;
        float moonR = 0.017f * H;
        RGB moonColor = RGB.Hex(0xf3efe0), moonGlow = RGB.Hex(0x9fb4d8);

        float starVis = Col.Smoothstep(-4, -14, alt) * (1 - w.Overcast);

        // Weather. Clouds: wide, flat shapes from 2-D noise, thinning into the
        // distance, lit on the side toward the sun (pink-edged at sunset). They
        // drift through the day. Under overcast they close into a soft deck.
        RGB cloudLit = Col.MixOklab(pal.Horizon, pal.Glow, 0.5f) * 1.15f;
        RGB cloudShade = Col.Desaturate(Col.MixOklab(pal.Mid, pal.Zenith, 0.5f), 0.5f) * 0.85f;
        float cloudEdge = 0.62f - 0.3f * w.Clouds - 0.25f * w.Overcast, cloudSoft = 0.12f + 0.3f * w.Overcast;
        float cloudStep = 0.02f * H, drift = minute * 0.002f;
        uint cloudSeed = Col.Hash32(seed ^ 0x51ed270b);
        float cloudH = H, horizon = horizonY;
        Func<float, float, float> cloud = (x, y) =>
        {
            float n = Col.Fbm2(x / cloudH * 1.6f + drift, y / cloudH * 5.5f, 5, cloudSeed) * 0.5f + 0.5f;
            return Col.Smoothstep(cloudEdge, cloudEdge + cloudSoft, n) * (1 - Col.Smoothstep(horizon * 0.75f, horizon * 1.02f, y));
        };
        RGB fogColor = Col.MixOklab(pal.Horizon, Col.Desaturate(pal.Mid, 0.6f), 0.4f);
        RGB rainColor = Col.MixOklab(pal.Horizon, new RGB(1, 1, 1), 0.25f);
        float rainCell = Math.Max(0.0065f * H, 4);
        uint rainSeed = Col.Hash32(seed ^ 0x2c1b3c6d);
        RGB flakeColor = Col.MixOklab(pal.Mid, new RGB(1, 1, 1), 0.6f);
        RGB snowGround = Col.MixOklab(pal.Mid, pal.Horizon, 0.5f) * 1.15f;
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

        // Snow takes the sky's light: white-blue by day, alpenglow pink at
        // sunrise and sunset, dim blue at night. Faces toward the sun are
        // brighter while it is up.
        RGB snowLight = Col.MixOklab(pal.Mid, pal.Glow, 0.5f) * 1.25f;
        float relief = 0.35f * Col.Smoothstep(-6, 3, alt);
        float windowLight = Col.Smoothstep(-0.5f, -5, alt);
        RGB windowColor = RGB.Hex(0xffb35c) * 1.3f;
        float wx0 = windowX0, wx1 = windowX1, wy0 = windowY0, wy1 = windowY1;
        float windowX = (wx0 + wx1) / 2, windowY = (wy0 + wy1) / 2;

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
                if (w.Clouds > 0 && fy < horizonY * 1.02f)
                {
                    float cd = cloud(fx, fy);
                    if (cd > 0)
                    {
                        float clx = sunX - fx, cly = sunY - fy;
                        float len = Math.Max(Col.Sqrt(clx * clx + cly * cly), 1);
                        float ahead = cloud(fx + clx / len * cloudStep, fy + cly / len * cloudStep);
                        float light = Col.Clamp01(0.55f + 1.8f * (cd - ahead));
                        c = Col.Mix(c, Col.Mix(cloudShade, cloudLit, light) + pal.Glow * (g * 0.6f), cd * 0.96f);
                    }
                }
                if (w.Fog > 0)
                {
                    c = Col.Mix(c, fogColor, w.Fog * 0.6f * Col.Smoothstep(0.3f * H, horizonY, fy));
                }

                for (int l = 0; l < Layers.Length; l++)
                {
                    int t0 = (l * width + x) * Sub;
                    float land = 0;
                    for (int s = 0; s < Sub; s++) land += Col.Clamp01(fy - top[t0 + s] + 0.5f);
                    land /= Sub;
                    float tree = trees[(l * Height + y) * width + x] / 255f;
                    float cov = Math.Max(land, tree);
                    if (cov == 0) continue;
                    Layer layer = Layers[l];
                    float gy = ground[l * width + x];
                    RGB tone = Col.Mix(tones[l], fog, layer.Mist * Col.Smoothstep(0, mistDepth, fy - gy));
                    if (tree > 0) tone = tone * (1 - 0.18f * (1 - layer.Haze) * tree);  // spruce darker than meadow
                    if (layer.Snow)
                    {
                        float amount = Col.Smoothstep(snowLine[x] + 3, snowLine[x] - 3, fy);
                        if (amount > 0)
                        {
                            // Snow faces turned to the sun are brighter: the face
                            // normal against the direction to the sun.
                            float slope = snowSlope[x];
                            float lx = sunX - fx, ly = sunY - fy;
                            float facing = (slope * lx - ly) / Col.Sqrt((1 + slope * slope) * (lx * lx + ly * ly));
                            RGB snow = Col.Mix(snowLight * (1 + relief * (Col.Clamp01(facing) - 0.5f) * 2), fog, layer.Haze * 0.55f);
                            tone = Col.Mix(tone, snow, amount);
                        }
                    }
                    if (w.Snow > 0 && !layer.Snow && fy >= gy)
                    {
                        // Fresh snow on open ground; the trees stay dark.
                        tone = Col.Mix(tone, Col.Mix(snowGround, fog, layer.Haze * 0.5f), 0.75f * w.Snow * (1 - tree));
                    }
                    if (w.Fog > 0)
                    {
                        tone = Col.Mix(tone, fogColor, w.Fog * (0.9f - 0.12f * l));
                    }
                    tone = tone + pal.Glow * (g * layer.Haze * 0.8f);  // in-scattered sun
                    c = cov == 1 ? tone : Col.Mix(c, tone, cov);
                }

                if (windowLight > 0)
                {
                    float inside = Col.Clamp01(Math.Min(Math.Min(fx - wx0, wx1 - fx), Math.Min(fy - wy0, wy1 - fy)) + 0.5f);
                    c = Col.Mix(c, windowColor, inside * windowLight);
                    float wdx = fx - windowX, wdy = fy - windowY;
                    c = c + windowColor * (0.08f * windowLight * Col.Exp(-Col.Sqrt(wdx * wdx + wdy * wdy) / (0.012f * H)));
                }

                if (w.Rain > 0)
                {
                    // Slanted streaks: one possible line per narrow column,
                    // broken into dashes.
                    float u = fx + fy * 0.18f;
                    float col = (float)Math.Floor(u / rainCell);
                    uint hc = Col.Hash32(unchecked((uint)(int)col ^ rainSeed));
                    float line = Col.Clamp01(0.9f - Math.Abs(u - (col + 0.2f + 0.6f * Col.Unit(hc)) * rainCell));
                    if (line > 0)
                    {
                        float dash = (float)Math.Floor((fy + Col.Unit(Col.Hash32(hc)) * 977) / (0.04f * H));
                        if (Col.Unit(Col.Hash32(hc ^ unchecked((uint)(int)dash * 0x27d4eb2f))) < 0.3f)
                            c = Col.Mix(c, rainColor, line * 0.22f * w.Rain);
                    }
                }
                if (w.Snow > 0)
                {
                    float f = flakes[y * width + x];
                    if (f > 0.002f) c = Col.Mix(c, flakeColor, Math.Min(f * w.Snow, 1f));
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
