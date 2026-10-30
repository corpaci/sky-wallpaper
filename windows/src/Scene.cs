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

/// A small house with a porch on the nearest hill; its window lights up
/// after sunset.
sealed class Cabin
{
    public float X, HalfWidth;
    public float Base, WallH, RoofH;     // where its walls stand, and how tall walls and roof are
    public float Porch0, Porch1;         // the porch's two ends
    public float WindowX0, WindowX1, WindowY0, WindowY1;
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

    /// Under a bright moon the night sky turns deep blue, and land and snow
    /// come out of the dark.
    public Palette Moonlit(float k)
    {
        Palette r;
        r.Zenith = Zenith + new RGB(0.004f, 0.008f, 0.024f) * k;
        r.Mid = Mid + new RGB(0.006f, 0.011f, 0.030f) * k;
        r.Horizon = Horizon + new RGB(0.009f, 0.015f, 0.034f) * k;
        r.Glow = Glow + new RGB(0.010f, 0.016f, 0.032f) * k;
        r.Land = Land + new RGB(0.002f, 0.004f, 0.009f) * k;
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
    readonly byte[] leaves;      // [((layer - 2) * height + y) * width + x] leafy trees' foliage, the wooded layers only
    readonly byte[] leafShade;   // and its light band and height in the crown (LeafyTree.StampInto)
    readonly byte[] leafInfo;    // and its species and distance from the crown's middle
    sealed class Leafy { public int L; public float X, Base, Rx; public int Species; }
    readonly List<Leafy> leafy;  // leafy trees, for their fallen leaves
    readonly int[] litterBy;     // [(layer * width + x) * 4 + k] the four leafy trees whose leaves may lie here, or -1
    readonly float[] snowLine;   // [x] the snow line's ragged edge, an offset from where the season puts it
    readonly float summitTop;    // the summit's highest point, y
    readonly float[] flowerX, flowerY, flowerR;  // on the near meadow
    readonly uint[] flowerN;
    readonly float[] flyX, flyY, flyK;           // fireflies over the near meadow, by the trees
    readonly float[] snowSlope;  // [x] its slope over ±3% of the height, so shading blends, not splits
    public readonly Cabin Cabin;
    readonly float[] flakes;     // glints of ice in the air, full frame
    readonly float[] glintPower; // drops on the wet meadow, full frame
    readonly byte[] glintHue;    // and the color each catches, 0 = violet … 255 = red
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
                    snowLine[x] = 0.010f * H * Col.Fbm(x / H * 14, 3, s ^ 0x7f4a7c15);
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

        // What stands on the land and lets the sky through between its parts
        // (trees, the porch) is drawn as 2-D coverage, one plane per layer.
        trees = new byte[Layers.Length * width * height];
        leaves = new byte[(Layers.Length - 2) * width * height];
        leafShade = new byte[leaves.Length];
        leafInfo = new byte[leaves.Length];
        leafy = new List<Leafy>();

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
                uint treeSeed = Col.Hash32(s ^ unchecked(n * 0x9e3779b1));
                if (l >= 2 && Col.Hash32(treeSeed ^ 0x2f1e8a5b) % 10 < 3)
                {
                    // Three trees in ten are leafy, bare in winter: their limbs with
                    // the spruces, their crowns in a plane of their own.
                    float lb = Terrain(layer, s, tx) + 0.04f * th;
                    var tree = new LeafyTree(tx, lb, th, treeSeed, false);
                    tree.StampInto(trees, l, leaves, leafShade, leafInfo, l - 2, width, height, th);
                    leafy.Add(new Leafy { L = l, X = tx, Base = lb, Rx = tree.CrownRx, Species = tree.Species });
                }
                else
                {
                    Stamp(Spruce(tx, Terrain(layer, s, tx) + 0.06f * th, th, treeSeed, th > 30 ? 2 : 1), trees, l, width, height);
                }
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

        // Two fruit trees on the meadow in front of the cabin.
        float[] fruitAt = { cabinX - 2.4f * cabinHalf, porch1 + 1.2f * cabinHalf }, fruitSize = { 0.045f, 0.04f };
        for (int k = 0; k < 2; k++)
        {
            float th = fruitSize[k] * H, fb = groundAt(near, fruitAt[k]) + 0.016f * H;
            var tree = new LeafyTree(fruitAt[k], fb, th, Col.Hash32(seed ^ unchecked((uint)(k + 7) * 0x27d4eb2f)), true);
            tree.StampInto(trees, near, leaves, leafShade, leafInfo, near - 2, width, height, th);
            leafy.Add(new Leafy { L = near, X = fruitAt[k], Base = fb, Rx = tree.CrownRx, Species = tree.Species });
        }
        // For each column, the four leafy trees nearest it (in crown widths),
        // whose fallen leaves may lie there.
        litterBy = Enumerable.Repeat(-1, Layers.Length * width * 4).ToArray();
        var byNear = Enumerable.Repeat(float.PositiveInfinity, Layers.Length * width * 4).ToArray();
        for (int i = 0; i < leafy.Count; i++)
        {
            Leafy t = leafy[i];
            for (int x = Math.Max((int)(t.X - 6 * t.Rx), 0); x < Math.Min((int)(t.X + 6 * t.Rx) + 1, width); x++)
            {
                int tree = i;
                float u = Math.Abs(x + 0.5f - t.X) / t.Rx;
                for (int k = (t.L * width + x) * 4; k < (t.L * width + x + 1) * 4; k++)
                {
                    if (!(u < byNear[k])) continue;
                    int pt = litterBy[k]; float pu = byNear[k];  // insert, pushing the farther ones down
                    litterBy[k] = tree; byNear[k] = u;
                    tree = pt; u = pu;
                }
            }
        }

        Cabin = new Cabin {
            X = cabinX, HalfWidth = cabinHalf, Base = cabinBase, WallH = wallH, RoofH = roofH, Porch0 = porch0, Porch1 = porch1,
            WindowX0 = cabinX - 0.55f * cabinHalf, WindowX1 = cabinX - 0.15f * cabinHalf,
            WindowY0 = cabinBase - 0.72f * wallH, WindowY1 = cabinBase - 0.38f * wallH,
        };
        summitTop = float.MaxValue;
        for (int x = 0; x < width; x++) summitTop = Math.Min(summitTop, ground[x]);

        // Flowers on the near meadow, bigger nearer; the season says which bloom.
        var flowerRng = new SplitMix(unchecked(((ulong)seed * 0xa0761d6478bd642f) | 1));
        int flowerCount = width * height / 4000;
        flowerX = new float[flowerCount]; flowerY = new float[flowerCount]; flowerR = new float[flowerCount]; flowerN = new uint[flowerCount];
        for (int i = 0; i < flowerCount; i++)
        {
            float x = flowerRng.Unit() * W;
            float gy = ground[near * width + Math.Min((int)x, width - 1)];
            float t = flowerRng.Unit();
            flowerX[i] = x; flowerY[i] = gy + 3 + t * (H - gy - 3); flowerR[i] = (0.5f + 1.1f * t) * H / 1664;
            flowerN[i] = (uint)(flowerRng.Next() >> 32);
        }
        // Fireflies, low over the meadow and along the trees.
        var flyRng = new SplitMix(unchecked(((ulong)seed * 0xe7037ed1a0b428db) | 1));
        flyX = new float[90]; flyY = new float[90]; flyK = new float[90];
        for (int i = 0; i < 90; i++)
        {
            float x = flyRng.Unit() * W;
            float gy = ground[near * width + Math.Min((int)x, width - 1)];
            float u = flyRng.Unit();
            flyX[i] = x;
            flyY[i] = gy - 0.05f * H * u * u + 0.03f * H * flyRng.Unit();
            flyK[i] = 0.4f + 0.6f * flyRng.Unit();
        }

        // Ice in the cold air after snow ("diamond dust"): tiny points that
        // catch the light, the big near ones rarer. Drawn only after snow.
        float scale = H / 1664;
        flakes = new float[width * height];
        var flakeRng = new SplitMix(unchecked(((ulong)seed * 0xd1b54a32d192ed03) | 1));
        int flakeCount = width * height / 9000;
        for (int n = 0; n < flakeCount; n++)
        {
            float fx = flakeRng.Unit() * W, fy = flakeRng.Unit() * H;
            float nearness = Col.Pow(flakeRng.Unit(), 3);
            float bright = 0.4f + 0.6f * Col.Pow(flakeRng.Unit(), 2);
            float sigma = (0.45f + 0.9f * nearness) * scale;
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

        // Glints: drops on the wet meadow, each splitting the low sun into
        // one color. Drawn only after rain.
        glintPower = new float[width * height];
        glintHue = new byte[width * height];
        var glintRng = new SplitMix(unchecked(((ulong)seed * 0x94d049bb133111eb) | 1));
        int glintCount = width * height / 1200;
        for (int n = 0; n < glintCount; n++)
        {
            float gx = glintRng.Unit() * W, gy = (0.68f + 0.32f * glintRng.Unit()) * H;
            float tint = glintRng.Unit(), mag = Col.Pow(glintRng.Unit(), 3);
            int cx = (int)gx, cy = (int)gy;
            if (cy >= height || gy <= ground[2 * width + Math.Min(cx, width - 1)] + 2) continue;
            float k = 0.35f + 1.4f * mag;
            byte hue = (byte)(tint * 255);
            PutGlint(cx, cy, k, hue);
            int arms = mag > 0.5f ? (int)(2 * scale + 1) : 1;
            for (int a = 1; a <= arms; a++)
            {
                float v = k * 0.4f / a;
                PutGlint(cx + a, cy, v, hue);
                PutGlint(cx - a, cy, v, hue);
                PutGlint(cx, cy + a, v, hue);
                PutGlint(cx, cy - a, v, hue);
            }
        }
    }

    void PutGlint(int px, int py, float v, byte hue)
    {
        if (px < 0 || px >= Width || py < 0 || py >= Height) return;
        glintPower[py * Width + px] += v;
        glintHue[py * Width + px] = hue;
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
    public static void Stamp(List<Capsule> caps, byte[] cover, int plane, int width, int height)
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

    /// Where a direction lands in the view: x, y and altitude.
    struct ScreenPoint { public float X, Y, Alt; }

    /// One frame as 8-bit sRGB, 3 bytes per pixel, dithered. `salt` varies the
    /// dither per frame. Light follows the stylized `sun`; the moon, planets,
    /// stars and Milky Way stand where `sky` puts them.
    public byte[] Render(int minute, SunModel sun, Ephemeris sky, Season season, MeteorShower meteors, Life life, uint salt, Weather w)
    {
        float sunAlt = sun.Altitude(minute);
        // A solar eclipse: the moon's disk over the sun's, as seen from here.
        // The eye hardly notices the light failing until the sun is nearly
        // covered; then the sky darkens as in twilight. From here on `alt` is
        // the sun the light comes from, `sunAlt` where it stands.
        float sunMoon = (float)sky.Moon.Angle(sky.Sun), sunRadius = (float)sky.SunRadius, moonRadius = (float)sky.MoonRadius;
        float covered = sunMoon < sunRadius + moonRadius ? DiskOverlap(moonRadius / sunRadius, sunMoon / sunRadius) : 0;
        float uncovered = Math.Max(1 - covered, 1e-4f);
        float alt = covered > 0
            ? Math.Min(sunAlt, uncovered < 0.1f ? Math.Max(6 + 6 * (float)Math.Log10(uncovered / 0.1f), -7) : 6 + 30 * (float)Math.Log10(uncovered / 0.1f))
            : sunAlt;
        float? dayPhase = sun.DayPhase(minute);
        bool evening = dayPhase.HasValue ? dayPhase.Value >= 0.5f : sun.NightPhase(minute) < 0.5f;
        float clear = 1 - w.Overcast;  // how much of the sky shows

        // The view faces the equator and spans 240°, from east-northeast to
        // west-northwest north of the equator (mirrored south of it, where the
        // sun rises on the right), so a rising or setting moon is mostly in
        // view. Altitude climbs at the same scale; on tall screens the top
        // edge passes the zenith, and the sky carries on over it.
        float ppd = W / 240;  // pixels per degree
        float viewAz = sky.Latitude >= 0 ? 180 : 0, side = sky.Latitude >= 0 ? 1 : -1;
        float w2 = W / 2, horizon = horizonY;
        Func<Vec3, ScreenPoint> screen = v =>
        {
            float a = (float)(Math.Asin(Math.Max(-1, Math.Min(1, v.Z))) * 180 / Math.PI);
            float daz = (float)(Math.Atan2(v.X, v.Y) * 180 / Math.PI) - viewAz;
            if (daz > 180) daz -= 360; else if (daz <= -180) daz += 360;
            return new ScreenPoint { X = w2 + daz * ppd, Y = horizon - a * ppd, Alt = a };
        };
        // The same direction past the zenith; its Y is above the top edge when it doesn't show.
        Func<ScreenPoint, ScreenPoint> overZenith = sp =>
        {
            float daz = (sp.X - w2) / ppd;
            return new ScreenPoint { X = w2 + (daz > 0 ? daz - 180 : daz + 180) * ppd, Y = horizon - (180 - sp.Alt) * ppd, Alt = sp.Alt };
        };

        // The moon's light turns the night sky blue and brings the snow out.
        ScreenPoint moon = screen(sky.Moon);
        float moonLit = (float)sky.MoonLit;
        // Only while it's in the picture does it dim the faint stars and the
        // Milky Way; out of it, the night stays full of stars and the land
        // keeps a little of its light.
        // In a lunar eclipse the Earth's shadow, 0.70° across the umbra and
        // 1.25° the penumbra, falls on it; in totality its light goes out.
        float shadowSep = (float)sky.MoonFromCenter.Angle(sky.Sun * -1);
        float totality = Col.Smoothstep(1.0f, 0.44f, shadowSep);
        float moonLight = Col.Pow(moonLit, 1.5f) * Col.Smoothstep(-1, 20, moon.Alt) * Col.Smoothstep(-5, -14, alt) * clear * (1 - 0.9f * totality);
        float inView = Col.Smoothstep(-8 * ppd, 0, moon.X) * Col.Smoothstep(W + 8 * ppd, W, moon.X) * Col.Smoothstep(-1, 2, moon.Alt);
        float moonShown = moonLight * inView;
        Palette pal = Palettes.At(alt, evening);
        if (moonLight > 0) pal = pal.Moonlit(moonLight * (0.35f + 0.65f * inView));
        if (w.Overcast > 0) pal = pal.Overcast(w.Overcast);
        float span = horizonY - 0.14f * H;

        // Sun: rises on its side, sets on the other; below the horizon it
        // waits at its side. Cloud and fog veil its disk and glow.
        float veil = (1 - 0.85f * w.Overcast) * (1 - 0.5f * w.Fog);
        float p = dayPhase.HasValue ? dayPhase.Value : (evening ? 1 : 0);
        float sunX = W * (0.5f + (p - 0.5f) * 0.8f * side), sunY = horizonY - sunAlt / SunModel.Peak * span;
        float sunR = 0.021f * H;
        float sunVis = Col.Smoothstep(-1.5f, 0.5f, sunAlt) * (1 - w.Overcast) * (1 - 0.5f * w.Fog);
        RGB sunColor = Col.Mix(Palettes.At(sunAlt, evening).Glow * 1.6f, new RGB(1, 0.97f, 0.9f) * 1.4f, Col.Smoothstep(2, 20, sunAlt));
        // The moon's disk in front of the drawn sun, at the drawn sun's scale,
        // turned as the real one stands on the sky; in totality the corona.
        bool hasBite = covered > 0;
        float biteX = 0, biteY = 0, biteR = 0;
        if (hasBite)
        {
            double saz = Math.Atan2(sky.Sun.X, sky.Sun.Y), sal = Math.Asin(sky.Sun.Z);
            Vec3 bt = sky.Moon - sky.Sun * sky.Moon.Dot(sky.Sun);
            float ba = (float)bt.Dot(new Vec3(Math.Cos(saz), -Math.Sin(saz), 0));
            float bb = (float)bt.Dot(new Vec3(-Math.Sin(sal) * Math.Sin(saz), -Math.Sin(sal) * Math.Cos(saz), Math.Cos(sal)));
            float bn = Math.Max(Col.Sqrt(ba * ba + bb * bb), 1e-9f), apart = sunMoon / sunRadius * sunR;
            biteX = sunX + ba / bn * apart; biteY = sunY - bb / bn * apart; biteR = moonRadius / sunRadius * sunR;
        }
        float corona = Col.Smoothstep(0.97f, 1, covered) * sunVis;
        // What's left of a low sun reads as a deep orange sickle, as in photographs.
        RGB eclipsedSun = Col.MixOklab(sunColor, new RGB(1.25f, 0.62f, 0.22f), 0.7f * (1 - Col.Smoothstep(5, 25, sunAlt)));
        float low = Col.Smoothstep(-8, -1, alt) * (1 - Col.Smoothstep(4, 20, alt));
        float day = Col.Smoothstep(0, 15, alt);
        // The glare close around the sun shrinks with what the moon leaves of it.
        float gNear = (0.44f * low + 0.28f * day) * veil * (0.2f + 0.8f * uncovered), gFar = (0.40f * low + 0.10f * day) * veil, gBand = 0.30f * low * veil;
        float rNear = 0.06f * H, rFar = 0.32f * H, bandH = 0.07f * H, bandW = 0.55f * W;

        // The moon, where it is, lit from where the sun is: pale by day; by
        // night it hides the stars behind it, and earthshine lights its dark
        // side, most in a thin crescent, when the Earth is nearly full in its sky.
        // Low over the horizon it looks bigger, as the real one seems to: up
        // to 67% wider, back to its usual size by 30°.
        float moonR = 0.013f * H * (1 + 0.67f * (1 - Col.Smoothstep(2, 30, moon.Alt)));
        float moonVis = (1 - 0.95f * w.Overcast) * (1 - 0.5f * w.Fog) * Col.Smoothstep(-1.5f, -0.5f, moon.Alt) * Col.Smoothstep(3, 5, sunMoon);
        float opaque = Col.Smoothstep(6, -6, alt);
        float moonGain = 0.3f + 0.7f * opaque;
        float haloGain = 0.05f * Col.Pow(moonLit, 1.3f) * opaque * moonVis * (1 - 0.85f * totality);
        float earthshine = 0.025f * (1 - moonLit) * (1 - moonLit) * opaque;
        RGB moonColor = RGB.Hex(0xf3efe0), moonGlow = RGB.Hex(0x9fb4d8);
        // Directions on the sky at the moon, as screen x and y (up): its north
        // (the moon's axis is within 1.5° of the ecliptic pole's), and the sun.
        double maz = Math.Atan2(sky.Moon.X, sky.Moon.Y), mal = Math.Asin(sky.Moon.Z);
        var right = new Vec3(Math.Cos(maz), -Math.Sin(maz), 0);
        var upward = new Vec3(-Math.Sin(mal) * Math.Sin(maz), -Math.Sin(mal) * Math.Cos(maz), Math.Cos(mal));
        Func<Vec3, float[]> toward = v =>
        {
            Vec3 t = v - sky.Moon * v.Dot(sky.Moon);
            double ta = t.Dot(right), tb = t.Dot(upward), tn = Math.Max(Math.Sqrt(ta * ta + tb * tb), 1e-9);
            return new[] { (float)(ta / tn), (float)(tb / tn) };
        };
        float[] toSun = toward(sky.Sun), north = toward(sky.EclipticPole);
        float[] west = { north[1], -north[0] };
        float phase = (float)(sky.MoonPhaseAngle * Math.PI / 180);
        float lightX = toSun[0] * (float)Math.Sin(phase), lightY = toSun[1] * (float)Math.Sin(phase), lightZ = (float)Math.Cos(phase);
        // The shadow's center, in moon radii (the moon is 0.26° across its radius) from the moon's.
        bool hasShadow = shadowSep < 1.6f;
        float shadowX = -toSun[0] * shadowSep / 0.26f, shadowY = -toSun[1] * shadowSep / 0.26f;
        RGB copper = RGB.Hex(0xb5502a);

        // Stars and planets: as many as the dark, the moon and the air let
        // through. About magnitude 6 at full night; by day, only Venus, faint.
        float limit = -3.5f + 9.5f * Col.Clamp01(-alt / 16) - 1.6f * moonShown;
        float contrast = 0.25f + 0.75f * Col.Smoothstep(-2, -8, alt);
        int skyRows = Math.Min(Height, (int)horizonY + 2), width = Width;
        var starPower = new float[width * skyRows];
        var starBV = new float[width * skyRows];  // B−V weighted by light, for each pixel's color
        float scale = H / 1664;
        // A point of light as a small Gaussian, its total the same wherever it
        // falls between pixels: `peak` is its height at `sigma`.
        Action<float, float, float, float, float> splat = (x, y, peak, sigma, bv) =>
        {
            int reach = (int)Math.Ceiling(3 * sigma);
            int cx = (int)Math.Floor(x), cy = (int)Math.Floor(y);
            int x0 = Math.Max(cx - reach, 0), x1 = Math.Min(cx + reach, width - 1);
            int y0 = Math.Max(cy - reach, 0), y1 = Math.Min(cy + reach, skyRows - 1);
            if (x0 > x1 || y0 > y1) return;
            float sum = 0;
            for (int py = y0; py <= y1; py++)
                for (int qx = x0; qx <= x1; qx++)
                {
                    float sdx = qx + 0.5f - x, sdy = py + 0.5f - y;
                    sum += Col.Exp(-(sdx * sdx + sdy * sdy) / (2 * sigma * sigma));
                }
            if (sum <= 0) return;
            float norm = peak * 2 * (float)Math.PI * sigma * sigma / sum;
            for (int py = y0; py <= y1; py++)
                for (int qx = x0; qx <= x1; qx++)
                {
                    float sdx = qx + 0.5f - x, sdy = py + 0.5f - y;
                    float k = Col.Exp(-(sdx * sdx + sdy * sdy) / (2 * sigma * sigma));
                    starPower[py * width + qx] += norm * k;
                    starBV[py * width + qx] += norm * k * bv;
                }
        };
        Action<Vec3, float, float> point = (v, magnitude, bv) =>
        {
            if (v.Z <= 0) return;
            ScreenPoint sp = screen(v);
            float m = magnitude + 0.25f * (NightSky.Airmass(sp.Alt) - 1);  // extinction: 0.25 magnitudes per airmass
            float seen = Col.Smoothstep(limit + 0.5f, limit - 0.5f, m) * clear * contrast;
            if (!(seen > 0)) return;
            float b = Col.Pow(10, -0.2f * (m - 1.5f));  // brightness, compressed as the eye does
            float peak = Math.Min(0.55f * b, 1) * seen, sigma = Math.Max((0.6f + 0.35f * Col.Sqrt(Math.Min(b, 9))) * scale, 0.8f);
            if (sp.X > -8 && sp.X < W + 8 && sp.Y > -8) splat(sp.X, sp.Y, peak, sigma, bv);
            ScreenPoint oz = overZenith(sp);
            if (oz.Y > -8 && oz.X > -8 && oz.X < W + 8) splat(oz.X, oz.Y, peak, sigma, bv);
        };
        if (limit > -1.6f) foreach (Star star in Star.Catalog) point(sky.FromJ2000.Apply(star.Direction), star.Magnitude, star.Bv);
        foreach (Planet planet in sky.Planets) point(planet.Direction, (float)planet.Magnitude, (float)planet.Bv);
        // A meteor shower's peak night: streaks fanning out from its real
        // radiant, more the higher it stands, few under a bright moon.
        float meteorSeen = Col.Smoothstep(-12, -18, alt) * clear * (1 - 0.7f * moonShown);
        if (meteors != null && meteorSeen > 0)
        {
            Vec3 radiant = sky.FromJ2000.Apply(meteors.Radiant);
            int count = (int)Math.Round(meteors.Count * Math.Min(Math.Max(0.3f + 0.7f * (float)radiant.Z, 0.2f), 1), MidpointRounding.AwayFromZero);
            var mrng = new SplitMix(unchecked(((ulong)salt * 0x2545f4914f6cdd1d) | 1));
            int drawn = 0;
            for (int tries = 0; tries < 400 && drawn < count; tries++)
            {
                float mz = 2 * mrng.Unit() - 1, ma = 2 * (float)Math.PI * mrng.Unit();
                float rxy = Col.Sqrt(1 - mz * mz);
                var mp = new Vec3(rxy * (float)Math.Cos(ma), rxy * (float)Math.Sin(ma), mz);
                double fromRadiant = mp.Angle(radiant);
                if (!(mp.Z > 0.2 && fromRadiant > 15 && fromRadiant < 70)) continue;
                Vec3 away = (mp * mp.Dot(radiant) - radiant).Unit;  // along the sky, away from the radiant
                double length = (3 + 8 * mrng.Unit()) * Math.PI / 180;
                ScreenPoint s0 = screen(mp), s1 = screen((mp + away * length).Unit);
                if (!(s0.X > 0 && s0.X < W && s1.X > 0 && s1.X < W && s1.Y > 0)) continue;
                float bright = (0.04f + 0.12f * mrng.Unit() * mrng.Unit()) * meteorSeen;
                int steps = Math.Max((int)(Col.Sqrt((s1.X - s0.X) * (s1.X - s0.X) + (s1.Y - s0.Y) * (s1.Y - s0.Y)) * 2), 1);
                for (int k = 0; k <= steps; k++)
                {
                    float t = (float)k / steps;
                    splat(s0.X + (s1.X - s0.X) * t, s0.Y + (s1.Y - s0.Y) * t,
                          bright * Col.Pow(Math.Max((float)Math.Sin((float)Math.PI * t), 0), 0.6f) * (0.4f + 0.6f * t), Math.Max(0.45f * scale, 0.6f), 0);
                }
                drawn++;
            }
        }
        var starColors = new RGB[256];
        for (int i = 0; i < 256; i++) starColors[i] = NightSky.StarColor(i / 255f * 2.4f - 0.4f);

        // The Milky Way and the zodiacal light, on a grid of sky directions
        // every 4 px (both are smooth at that scale), bilinear in between.
        float mwSeen = Col.Smoothstep(-11, -18, alt) * (1 - 0.85f * moonShown) * clear;
        float mwGain = 0.022f * mwSeen;
        float zlGain = 0.006f * Col.Smoothstep(-13, -19, alt) * (1 - 0.9f * moonShown) * clear;
        // Its grain: stars too faint to see one by one, crowding the band.
        if (mwSeen > 0)
        {
            foreach (Star.Grain g in Star.Grains)
            {
                Vec3 v = sky.FromJ2000.Apply(g.Direction);
                if (v.Z <= 0) continue;
                ScreenPoint sp = screen(v);
                float peak = 0.12f * g.Light * mwSeen * Col.Pow(10, -0.1f * (NightSky.Airmass(sp.Alt) - 1)), sigma = Math.Max(0.5f * scale, 0.6f);
                if (sp.X > -2 && sp.X < W + 2 && sp.Y > -2) splat(sp.X, sp.Y, peak, sigma, g.Bv);
                ScreenPoint oz = overZenith(sp);
                if (oz.Y > -2 && oz.X > -2 && oz.X < W + 2) splat(oz.X, oz.Y, peak, sigma, g.Bv);
            }
        }
        const int gs = 4;
        int gw = width / gs + 2, gh = skyRows / gs + 2;
        var glowGrid = new float[mwGain + zlGain > 0 ? gw * gh * 3 : 0];
        if (glowGrid.Length > 0)
        {
            Mat3 toGalactic = sky.ToGalactic, toEcliptic = sky.ToEcliptic;
            float sunLon = (float)sky.SunLongitude;
            RGB mwCool = RGB.Hex(0xd4ddff), mwWarm = RGB.Hex(0xffe6c8), mwPink = RGB.Hex(0xff6f96);
            RGB zlColor = RGB.Hex(0xfff0dc);
            Parallel.For(0, gh, j =>
            {
                for (int i = 0; i < gw; i++)
                {
                    float a = (horizon - j * gs) / ppd;
                    if (!(a > -1)) continue;
                    bool past = a > 90;  // over the zenith: the sky behind, upside down
                    double al = (past ? 180 - a : a) * Math.PI / 180;
                    double az = (viewAz + (i * gs - w2) / ppd + (past ? 180 : 0)) * Math.PI / 180;
                    var v = new Vec3(Math.Cos(al) * Math.Sin(az), Math.Cos(al) * Math.Cos(az), Math.Sin(al));
                    float fade = Col.Pow(10, -0.1f * (NightSky.Airmass(a) - 1));
                    var c = new RGB(0, 0, 0);
                    if (mwGain > 0)
                    {
                        Vec3 gal = toGalactic.Apply(v);
                        float[] mw = NightSky.MilkyWay((float)gal.Lon, (float)gal.Lat);
                        c = Col.Mix(mwCool, mwWarm, mw[1]) * (mw[0] * mwGain * fade) + mwPink * (mw[2] * 0.3f * mwGain * fade);
                    }
                    if (zlGain > 0)
                    {
                        Vec3 e = toEcliptic.Apply(v);
                        float dl = Math.Abs((float)e.Lon - sunLon);
                        if (dl > 180) dl = 360 - dl;
                        c = c + zlColor * (NightSky.Zodiacal(dl, (float)e.Lat) * zlGain * fade);
                    }
                    int o = (j * gw + i) * 3;
                    glowGrid[o] = c.R; glowGrid[o + 1] = c.G; glowGrid[o + 2] = c.B;
                }
            });
        }

        // Weather. Clouds drift a little through the day.
        float drift = minute * 0.002f;
        RGB iceColor = Col.Mix(new RGB(1, 1, 1), pal.Glow, 0.3f) * (0.25f + 0.75f * Col.Smoothstep(-6, 10, alt));  // glitters in the sun
        RGB fogColor = Col.MixOklab(pal.Horizon, Col.Desaturate(pal.Mid, 0.6f), 0.4f);

        // Overcast: the view from above it, a sea of clouds over the world
        // below, the ranges and the sky above it clear. It's a surface seen in
        // perspective, column by column, the near parts hiding the far: lumpy
        // billows (|noise|, with creases between, as cumulus tops go) on a slow
        // swell, a few domes rising higher, all lit from the sun's side, or the
        // moon's at night. Far off, the lumps grow too small to see and it fades
        // into haze. Cloudy days break it open: through wide gaps the world
        // below shows. Seen from the cabin's hill it's a layer: its lumpy, soft
        // base hangs just above the leafy crowns, so only the tall spruces' tops
        // fade up into it, and frays into tongues over the hills beyond, which
        // lie in its grey shade; the cabin's hill takes its soft light.
        RGB seaLit = Col.MixOklab(pal.Horizon, pal.Glow, 0.5f) * 1.3f;
        RGB seaShade = Col.MixOklab(pal.Mid, pal.Horizon, 0.5f) * 0.75f;
        RGB seaHazeColor = Col.MixOklab(pal.Horizon, seaLit, 0.4f);
        uint seaSeed = Col.Hash32(seed ^ 0x6a09e667);
        float seaLine = 0.70f * H;                  // where its far edge would meet the eye
        float seaFocal = 0.6f * H;                  // screen scale, in px per unit at depth 1
        int seaRow0 = Math.Max((int)(seaLine - 0.12f * H), 0);
        int seaRows = w.Sea > 0 ? Height - seaRow0 : 0;
        var seaTopY = new float[w.Sea > 0 ? width : 0];
        float seaSoft = 0.015f * H;
        // How much cloud there is where the sea is z deep at pixel x: 1 on
        // overcast days, open gaps on cloudy ones.
        Func<float, float, float> cloudiness = (sx, sz) =>
        {
            if (!(w.Broken > 0)) return 1;
            float su = (sx - w2) * sz / seaFocal + drift * 3;
            float open = -0.45f + 0.9f * w.Broken;  // the noise below this is a gap
            return Col.Smoothstep(open - 0.06f, open + 0.06f, Col.Fbm2(su * 0.12f, sz * 0.12f, 3, seaSeed ^ 0x85ebca6b));
        };
        var seaEdge = new float[w.Sea > 0 ? width : 0];
        for (int x = 0; x < seaEdge.Length; x++)
        {
            // Its base, over the hill: lumpy, rising and dipping along it, and
            // always above the leafy crowns (the tallest reach 0.053 of the
            // height), so only the tall spruces' tops go up into it.
            float swell = Col.Clamp01(0.5f + 0.6f * Col.Fbm(x / H * 1.6f + drift, 2, seaSeed ^ 0x1b873593));
            seaEdge[x] = ground[(Layers.Length - 1) * width + x] - (0.07f + 0.028f * swell) * H
                - 0.012f * H * Math.Abs(Col.Fbm(x / H * 9 + drift * 3, 3, seaSeed ^ 0x5bd1e995));
        }
        float seaBase = w.Sea * Col.Clamp01(1 - 2 * w.Broken);  // how solid its base is: overcast, not broken
        // The bright sea lights the cabin's hill softly from all round: the
        // meadow lifts toward the clouds' shaded grey, most at its far edge.
        float seaLift = 0.3f * w.Sea;
        var seaLight = new float[width * seaRows];
        var seaDepth = new float[width * seaRows];  // how far off, for haze and gaps
        var seaCover = new float[width * seaRows];
        if (seaRows > 0)
        {
            // Light from the sun's side, or the moon's at night; softer by moonlight.
            bool byMoon = alt < -4;
            float fromX = byMoon ? Col.Clamp01((moon.X - w2) / w2 + 1) * 2 - 1 : Col.Clamp01((sunX - w2) / w2 + 1) * 2 - 1;
            float fromUp = byMoon ? Math.Max(moon.Alt, 3) : Math.Max(sunAlt, 3);
            float sinUp = (float)Math.Sin(fromUp * (float)Math.PI / 180), cosUp = (float)Math.Cos(fromUp * (float)Math.PI / 180);
            float ln = Col.Sqrt(fromX * cosUp * fromX * cosUp + sinUp * sinUp + 0.36f * cosUp * cosUp);
            float toLightX = fromX * cosUp / ln, toLightY = sinUp / ln, toLightZ = 0.6f * cosUp / ln;  // z: away from us
            float seaContrast = byMoon ? 0.3f + 0.5f * moonLight : 1;
            Func<float, float, float> surface = (su, sz) =>
            {
                float swell = 0.25f * Col.Fbm2(su * 0.08f, sz * 0.08f, 2, seaSeed ^ 0x27d4eb2f);
                float dome = 1.8f * Math.Max(Col.Fbm2(su * 0.15f, sz * 0.15f, 2, seaSeed ^ 0x165667b1) - 0.2f, 0);
                float billow = 0, amp = 0.5f, f = 1.2f;
                for (int k = 0; k < 4; k++)
                {
                    billow += amp * Math.Abs(Col.ValueNoise2(su * f + k * 17.31f, sz * f + k * 9.77f, unchecked(seaSeed + (uint)k * 1013)));
                    amp *= 0.5f;
                    f *= 2.1f;
                }
                return 0.15f + swell + dome + 0.35f * billow * (0.3f + 0.7f * (1 - Col.Smoothstep(8, 40, sz)));
            };
            int height = Height;
            Parallel.For(0, width, x =>
            {
                float across = x + 0.5f - w2;
                int filled = height;  // rows from here down are drawn
                float crest = H;      // the surface's highest point so far
                float lastY = H * 2, lastLit = 0.5f, lastZ = 1.5f;  // the step before, nearer
                for (float z = 1.5f; z < 80; z *= 1.008f)
                {
                    float u = across * z / seaFocal + drift * 3;
                    float s = surface(u, z);
                    float y = seaLine + seaFocal * (1 - s) / z;  // the eye stands one unit above the mean surface
                    int row = Math.Max((int)Math.Ceiling(y - 0.5f), seaRow0);
                    float e = 0.02f * z;
                    float dx = (surface(u + e, z) - s) / e, dz = (surface(u, z + e) - s) / e;
                    float nl = Col.Sqrt(dx * dx + 1 + dz * dz);
                    float lambert = Math.Max((-dx * toLightX + toLightY - dz * toLightZ) / nl, 0);
                    float lit = Col.Clamp01(0.5f + seaContrast * (0.65f * lambert - 0.3f) + 0.15f * s);
                    if (row < filled)
                    {
                        // Rows between this step and the one before blend the two, so steps don't show.
                        for (int r = row; r < filled; r++)
                        {
                            float t = lastY > y ? Col.Clamp01((r + 0.5f - y) / (lastY - y)) : 0;
                            int i = (r - seaRow0) * width + x;
                            seaLight[i] = Col.Lerp(lit, lastLit, t);
                            seaDepth[i] = Col.Lerp(z, lastZ, t);
                            seaCover[i] = 1;
                        }
                        filled = row;
                        crest = y;
                    }
                    lastY = y; lastLit = lit; lastZ = z;
                }
                // The top edge, antialiased: the row above the last drawn gets the fraction it's covered.
                if (filled > seaRow0 && filled < height)
                {
                    int i = (filled - seaRow0) * width + x, above = i - width;
                    seaLight[above] = seaLight[i];
                    seaDepth[above] = seaDepth[i];
                    seaCover[above] = Col.Clamp01(filled - crest);
                }
                seaTopY[x] = crest;
            });
        }
        // Fog lakes at the feet of the hills, bright under a clear sky.
        RGB valleyColor = Col.MixOklab(pal.Horizon, pal.Mid, 0.2f) * 1.12f;

        // After rain. The rainbow stands opposite the sun: from this view,
        // which faces the sun's path, it rises at the far edge, and sinks as
        // the sun climbs, gone above 42°. It hangs in the rain over the far
        // range: in front of the summit, behind the nearer ridges. Glints
        // wherever the sun is up.
        const int bowLayer = 1;
        float bowGain = 0.38f * w.Wet * Col.Smoothstep(-0.5f, 3, alt) * (1 - Col.Smoothstep(30, 41, alt));
        float bowR = 0.78f * H;
        float bowX = sunX > 0.5f * W ? -0.22f * W : 1.22f * W;
        float bowY = horizonY + (0.12f + 0.5f * Col.Clamp01(sunAlt / 42)) * H;
        float glintGain = w.Wet * Col.Smoothstep(-2, 4, alt) * (0.6f + 0.4f * (1 - Col.Smoothstep(10, 35, alt)));
        var hues = new RGB[w.Wet > 0 ? 256 : 0];
        for (int i = 0; i < hues.Length; i++) hues[i] = Col.Spectrum(i / 255f);
        RGB snowGround = Col.MixOklab(pal.Mid, pal.Horizon, 0.5f) * 1.15f;
        var gradient = new RGB[Height];
        for (int y = 0; y < Height; y++)
        {
            float s = Col.Clamp01((y + 0.5f) / horizonY);
            gradient[y] = s < 0.55f ? Col.MixOklab(pal.Zenith, pal.Mid, s / 0.55f)
                               : Col.MixOklab(pal.Mid, pal.Horizon, Col.Pow((s - 0.55f) / 0.45f, 1.4f));
        }
        RGB fog = pal.Horizon;
        var tones = new RGB[Layers.Length];
        for (int l = 0; l < Layers.Length; l++) tones[l] = Col.MixOklab(pal.Land, fog, Layers[l].Haze);
        float mistDepth = 0.10f * H;

        // Snow takes the sky's light: white-blue by day, alpenglow pink at
        // sunrise and sunset, dim blue at night. Faces toward the sun are
        // brighter while it is up.
        RGB snowLight = Col.MixOklab(pal.Mid, pal.Glow, 0.5f) * 1.25f;
        float relief = 0.35f * Col.Smoothstep(-6, 3, alt);
        float windowLight = Col.Smoothstep(-0.5f, -5, alt);
        RGB windowColor = RGB.Hex(0xffb35c) * 1.3f;
        Cabin cabin = Cabin;
        float wx0 = cabin.WindowX0, wx1 = cabin.WindowX1, wy0 = cabin.WindowY0, wy1 = cabin.WindowY1;
        float windowX = (wx0 + wx1) / 2, windowY = (wy0 + wy1) / 2;

        // The seasons: the summit's snow line, and snow on the rocky range's
        // peaks when it's low; snow and frost on the land, and once it has
        // snowed, on branch tops and the roof; leafy trees fresh, green, in
        // autumn's colors or bare; the fruit trees in blossom, then with apples.
        float snowFoot = 0.70f * H;  // the summit's foot, behind the rocky range
        float snowAt = snowFoot - season.SnowLine * (snowFoot - summitTop);
        float rangeSnow = Col.Smoothstep(0.35f, 0.1f, season.SnowLine);
        var rangeLine = new float[width];
        Array.Copy(ground, width, rangeLine, 0, width);
        Array.Sort(rangeLine);
        float rangeTop = rangeLine[width / 5];  // its higher crests, not one outlier
        float groundSnow = Math.Max(w.Snow, season.SnowCover);
        float daylight = Col.Smoothstep(-6, 6, alt);
        float lightLevel = Col.Clamp01(Overlay.Luminance(Col.MixOklab(pal.Mid, pal.Glow, 0.3f)) * 1.4f);
        // Colors laid into the landscape take its light and its air: each is
        // drawn partway to its layer's tone, so a leaf, a flower or a bike
        // belongs to the hill it's on, and more so the farther off.
        Func<RGB, int, RGB, RGB> inTone = (col, l, tone) => Col.MixOklab(tone, col * lightLevel, 0.6f * (1 - 0.6f * Layers[l].Haze));
        Func<RGB, int, RGB> inLayer = (col, l) => inTone(col, l, tones[l]);
        RGB apple = RGB.Hex(0xc8302a);
        int snowAbove = Math.Max((int)Math.Round(2.5f * scale, MidpointRounding.AwayFromZero), 1);  // how far above a branch to look for open air: how deep the snow
        RGB snowOnTop = Col.Mix(snowGround, new RGB(1, 1, 1), 0.3f);
        RGB frostColor = Col.MixOklab(pal.Mid, new RGB(1, 1, 1), 0.55f) * 1.1f;
        float frostGlint = season.Frost * Col.Smoothstep(-2, 4, alt) * 0.7f;

        // Small things in front of the near hill: flowers in their season,
        // fireflies on warm midsummer nights.
        int near = Layers.Length - 1;
        float nearTop = float.MaxValue;
        for (int x = 0; x < width; x++) nearTop = Math.Min(nearTop, ground[near * width + x]);
        var nearOverlay = new Overlay(0, Math.Max((int)(nearTop - 0.16f * H), 0), width, Height);
        float bloom = season.Flowers * (1 - groundSnow);
        if (bloom > 0 && daylight > 0)
        {
            RGB[] colors = season.FlowerColors.Select(hex => inLayer(RGB.Hex(hex), near)).ToArray();
            for (int i = 0; i < flowerX.Length; i++)
                if (Col.Unit(flowerN[i]) < bloom) nearOverlay.Circle(flowerX[i], flowerY[i], flowerR[i], colors[(int)(flowerN[i] >> 3) % colors.Length], daylight);
        }
        float fireflyGain = season.Fireflies * Col.Smoothstep(-6, -12, alt) * (1 - w.Wet);
        if (fireflyGain > 0)
        {
            RGB flyColor = RGB.Hex(0xd4ff6a);
            for (int i = 0; i < flyX.Length; i++)
            {
                nearOverlay.Glow(flyX[i], flyY[i], Math.Max(0.9f * scale, 0.7f), flyColor * (0.5f * flyK[i] * fireflyGain));
                nearOverlay.Glow(flyX[i], flyY[i], 3.5f * scale, flyColor * (0.04f * flyK[i] * fireflyGain));
            }
        }
        // The cabin's things. The bikes stay home unless their riders are out.
        Func<uint, RGB> litNear = hex => inLayer(RGB.Hex(hex), near);
        float panelGlint = Col.Smoothstep(25, 3, alt) * Col.Smoothstep(-1, 2, alt) * (sunX < cabin.X ? 1 : 0.3f) * (1 - w.Overcast);
        Things.DrawCabin(nearOverlay, cabin, H, groundSnow, litNear, pal.Mid, panelGlint, life.BikesHome);
        // The two of them, when they're out, and whoever's visiting (Life.cs).
        Func<float, float> ridge = rx => ground[near * width + Math.Min(Math.Max((int)rx, 0), width - 1)];
        Func<float, float, float> clearing = (x0, half) =>
        {
            // The nearest place where no tree stands on the ridge, away from the cabin.
            int rows = (int)(0.04f * H);
            Func<float, bool> open = ox =>
            {
                if (!(ox > 0.04f * W && ox < 0.96f * W && Math.Abs(ox - cabin.X) > 2.5f * cabin.HalfWidth + half)) return false;
                for (int cx = (int)(ox - half); cx <= (int)(ox + half); cx += 2)
                {
                    int cgy = (int)ridge(cx);
                    for (int cy = Math.Max(cgy - rows, 0); cy < cgy; cy += 2)
                        if (trees[(near * Height + cy) * width + cx] > 40) return false;
                }
                return true;
            };
            int stepsMax = (int)(16 * cabin.HalfWidth / half);  // within four cabin widths
            for (int step = 0; step < stepsMax; step++)
            {
                foreach (float dir in new[] { 1f, -1f })
                    if (open(x0 + dir * step * half * 0.5f)) return x0 + dir * step * half * 0.5f;
            }
            return float.NaN;  // none: they stay on the meadow
        };
        life.Draw(nearOverlay, cabin, H, W, season.Year, groundSnow > 0.3f, ridge, clearing, litNear, windowLight);
        Overlay skyBirds = life.DrawSky(W, H, Col.MixOklab(pal.Land * 0.7f, pal.Mid, 0.3f));
        // Fallen leaves on the ground around the leafy trees, gathering as
        // the trees let them go, browning through winter, until snow covers
        // them or spring's grass grows over them.
        float carpetGain = (season.Year > 0.75f ? 1 : 1 - Col.Smoothstep(0.18f, 0.30f, season.Year)) * (1 - groundSnow);
        float carpetBrown = season.Year > 0.75f ? 0.3f + 0.3f * Col.Smoothstep(0.86f, 1, season.Year) : 0.6f + 0.3f * Col.Smoothstep(0, 0.2f, season.Year);
        var carpetCell = new int[Layers.Length];
        for (int l = 0; l < Layers.Length; l++)
            carpetCell[l] = Math.Max((int)Math.Round(0.0016f * H * Layers[l].Trees / Layers[near].Trees, MidpointRounding.AwayFromZero), 1);
        Overlay overNear = nearOverlay;

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
                RGB c = gradient[y] + pal.Glow * g;
                RGB air = c;  // sky without stars
                if (y < skyRows)
                {
                    if (glowGrid.Length > 0)
                    {
                        float gu = fx / gs, gv = fy / gs;
                        int i0 = (int)gu, j0 = (int)gv;
                        float fu = gu - i0, fv = gv - j0;
                        int go = (j0 * gw + i0) * 3, go2 = go + gw * 3;
                        c = c + new RGB(
                            Col.Lerp(Col.Lerp(glowGrid[go], glowGrid[go + 3], fu), Col.Lerp(glowGrid[go2], glowGrid[go2 + 3], fu), fv),
                            Col.Lerp(Col.Lerp(glowGrid[go + 1], glowGrid[go + 4], fu), Col.Lerp(glowGrid[go2 + 1], glowGrid[go2 + 4], fu), fv),
                            Col.Lerp(Col.Lerp(glowGrid[go + 2], glowGrid[go + 5], fu), Col.Lerp(glowGrid[go2 + 2], glowGrid[go2 + 5], fu), fv));
                    }
                    float sp = starPower[y * width + x];
                    if (sp > 0) c = c + starColors[(int)(Col.Clamp01((starBV[y * width + x] / sp + 0.4f) / 2.4f) * 255)] * sp;
                }
                if (sunVis > 0)
                {
                    float cov = Col.Clamp01(sunR - d + 0.5f) * sunVis;
                    if (hasBite)
                    {
                        float bd = Col.Sqrt((fx - biteX) * (fx - biteX) + (fy - biteY) * (fy - biteY));
                        float inside = Col.Clamp01(biteR - bd + 0.5f) * sunVis;
                        cov *= 1 - inside;
                        // Where it covers the sun the moon's disk shows dark against
                        // the glare; off the sun it can't be seen.
                        float bitten = inside * Col.Clamp01(sunR - d + 0.5f);
                        c = c + pal.Glow * (-(gNear * Col.Exp(-d / rNear) + 0.5f * gFar * Col.Exp(-d / rFar)) * bitten);
                        if (corona > 0)
                        {
                            // Pearly streamers around the black disk, uneven, the longest
                            // reaching out a few radii.
                            float ca = (float)Math.Atan2(fy - biteY, fx - biteX);
                            float ray = 0.55f + 0.25f * (float)Math.Sin(2 * ca + 1.3f) + 0.12f * (float)Math.Sin(5 * ca + 0.4f) + 0.08f * (float)Math.Sin(11 * ca + 2.1f);
                            float outward = Math.Max(bd - biteR, 0);
                            c = c + new RGB(0.85f, 0.88f, 1) * (corona * 0.8f * ray * Col.Exp(-outward / (sunR * (0.15f + 0.6f * ray))) * (1 - inside));
                            c = Col.Mix(c, c * 0.15f, corona * inside);
                        }
                    }
                    if (cov > 0) c = Col.Mix(c, hasBite ? eclipsedSun : sunColor, cov);
                }
                if (moonVis > 0)
                {
                    float mx = fx - moon.X, my = fy - moon.Y;
                    float md = Col.Sqrt(mx * mx + my * my);
                    RGB halo = moonGlow * (haloGain * Col.Exp(-md / (0.05f * H)));
                    c = c + halo;
                    float disk = Col.Clamp01(moonR - md + 0.5f) * moonVis;
                    if (disk > 0)
                    {
                        // A sphere lit by the sun, flat to its rim as the real
                        // moon is (Lommel–Seeliger), with its maria.
                        float ddx = mx / moonR, ddy = -my / moonR;
                        float z = Col.Sqrt(Math.Max(1 - ddx * ddx - ddy * ddy, 0));
                        float mu = Math.Max(ddx * lightX + ddy * lightY + z * lightZ, 0);
                        float lit = 2 * mu / (mu + Math.Max(z, 0.25f));  // the floor keeps the rim from flaring
                        float albedo = NightSky.MoonAlbedo(ddx * west[0] + ddy * west[1], ddx * north[0] + ddy * north[1]);
                        RGB surface = moonColor * (albedo * (lit * moonGain + earthshine));
                        if (hasShadow)
                        {
                            float sd = Col.Sqrt((ddx - shadowX) * (ddx - shadowX) + (ddy - shadowY) * (ddy - shadowY));
                            float umbra = Col.Smoothstep(2.85f, 2.55f, sd), penumbra = Col.Smoothstep(4.8f, 2.7f, sd);
                            surface = surface * ((1 - 0.5f * penumbra) * (1 - 0.97f * umbra)) + copper * (0.06f * umbra * albedo * moonGain);
                        }
                        c = Col.Mix(c, air + halo, disk * opaque) + surface * disk;
                    }
                }
                if (skyBirds != null) c = skyBirds.Over(c, x, y);
                if (w.Fog > 0)
                {
                    c = Col.Mix(c, fogColor, w.Fog * 0.6f * Col.Smoothstep(0.3f * H, horizonY, fy));
                }

                float frontTree = 0;  // how much of this pixel is tree or porch, in front
                for (int l = 0; l < Layers.Length; l++)
                {
                    if (l == near && seaBase > 0 && fy > seaEdge[x] && fy < seaEdge[x] + 0.04f * H)
                    {
                        // The base frays: soft tongues of cloud hang lower here and
                        // there, in front of the hills beyond, behind the cabin's hill.
                        float n = Col.Fbm2(fx / (0.12f * H) + drift * 2, fy / (0.02f * H), 3, seaSeed ^ 0x9e3779b9);
                        float reach = 0.04f * H * Col.Clamp01(1.6f * n);
                        if (reach > 0) c = Col.Mix(c, seaHazeColor, 0.8f * seaBase * Col.Smoothstep(seaEdge[x] + reach, seaEdge[x], fy));
                    }
                    if (l == bowLayer && bowGain > 0)
                    {
                        // Rainbow light, added: violet inside, red outside; the
                        // second bow beyond, colors reversed; brighter sky inside
                        // the first, Alexander's dark band between.
                        float bd = Col.Sqrt((fx - bowX) * (fx - bowX) + (fy - bowY) * (fy - bowY));
                        float bw = 0.05f * bowR, r2 = 1.21f * bowR, bw2 = 0.07f * bowR;
                        float u = (bd - (bowR - bw)) / (2 * bw), u2 = (bd - (r2 - bw2)) / (2 * bw2);
                        if (u > 0 && u < 1) c = c + hues[Math.Min((int)(u * 255), 255)] * (bowGain * Col.Pow((float)Math.Sin((float)Math.PI * u), 0.8f));
                        if (u2 > 0 && u2 < 1) c = c + hues[Math.Min((int)((1 - u2) * 255), 255)] * (0.38f * bowGain * Col.Pow((float)Math.Sin((float)Math.PI * u2), 0.8f));
                        if (bd < bowR - bw) c = c * (1 + 0.18f * bowGain);
                        else if (bd > bowR + bw && bd < r2 - bw2) c = c * (1 - 0.2f * bowGain);
                    }
                    int t0 = (l * width + x) * Sub;
                    float land = 0;
                    for (int s = 0; s < Sub; s++) land += Col.Clamp01(fy - top[t0 + s] + 0.5f);
                    land /= Sub;
                    float spruceCov = trees[(l * Height + y) * width + x] / 255f;  // spruces, limbs, the porch
                    // Leafy trees: their foliage as the season has it (Trees.cs).
                    float leafCov = 0;
                    RGB leafColor = new RGB(0, 0, 0);
                    bool inFruitTree = false, birch = false;
                    if (l >= 2)
                    {
                        int li = ((l - 2) * Height + y) * width + x;
                        birch = (leafShade[li] & 0x20) != 0;
                        if (leaves[li] > 0)
                        {
                            inFruitTree = leafInfo[li] >> 5 == 5;
                            float presence;
                            leafColor = Leaves.Look(leafShade[li], leafInfo[li], season, x, y, H, out presence);
                            leafCov = leaves[li] / 255f * presence;
                        }
                    }
                    float tree = Math.Max(spruceCov, leafCov);
                    float cov = Math.Max(land, tree);
                    if (cov == 0) continue;
                    Layer layer = Layers[l];
                    float gy = ground[l * width + x];
                    RGB tone = Col.Mix(tones[l], fog, layer.Mist * Col.Smoothstep(0, mistDepth, fy - gy));
                    if (l == near && seaLift > 0 && tree < 1 && fy >= gy)
                        tone = Col.MixOklab(tone, seaShade, seaLift * (0.8f + 0.2f * Col.Smoothstep(gy + 0.1f * H, gy, fy)) * (1 - tree));
                    if (tree > 0) tone = tone * (1 - 0.18f * (1 - layer.Haze) * tree);  // spruce darker than meadow
                    if (birch && spruceCov > 0)
                    {
                        // Birch bark: paper white, lit on its left, with dark lenticels across it.
                        int row = (l * Height + y) * width;
                        float across = x > 0 && x < width - 1 ? (trees[row + x + 1] - trees[row + x - 1]) / 255f : 0;
                        RGB bark = RGB.Hex(0xe6e2d8) * (0.7f + 0.3f * across);
                        if (Col.Unit(Col.Hash32(unchecked((uint)(x / 3) * 0x9e3779b1 ^ (uint)y * 0x85ebca6b ^ 0xb1c4))) < 0.14f) bark = RGB.Hex(0x2e2a26);
                        tone = Col.Mix(tone, inTone(bark, l, tone), spruceCov / tree);
                    }
                    if (leafCov > 0)
                    {
                        RGB crown = leafColor;
                        if (inFruitTree && season.Fruit > 0)
                        {
                            // Apples, on the lit side.
                            uint speck = Col.Hash32(unchecked((uint)(x / 2) * 0x9e3779b1 ^ (uint)(y / 2) * 0x85ebca6b ^ 0xb10550));
                            if (Col.Unit(speck) < 0.08f * season.Fruit) crown = apple;
                        }
                        tone = Col.Mix(tone, inTone(crown, l, tone), leafCov / tree);
                    }
                    if (l >= 2 && carpetGain > 0 && fy >= gy && tree < 1 && litterBy[(l * width + x) * 4] >= 0)
                    {
                        // Fallen leaves: a flat, ragged pool around each trunk,
                        // a leaf to each small cell, the floor tinted between;
                        // on the near meadow a few blown far out from it.
                        float amount = 0, pool = 0;  // pool: under a crown, not blown out
                        int species = 0;
                        float ragged = 0.75f + 0.5f * Col.ValueNoise2(fx / (0.01f * H), fy / (0.004f * H), 0x4b1d);
                        for (int q = 0; q < 4; q++)
                        {
                            int ti = litterBy[(l * width + x) * 4 + q];
                            if (ti < 0) continue;
                            Leafy lt = leafy[ti];
                            float gone = (season.Year > 0.75f ? Leaves.Fall(season, lt.Species) : 1) * carpetGain;
                            float lu = (fx - lt.X) / (1.5f * lt.Rx * ragged), lv = (fy - lt.Base) / ((l == near ? 0.4f : 0.15f) * lt.Rx * ragged);
                            float la = gone * Col.Exp(-(lu * lu + lv * lv));
                            pool = Math.Max(pool, la);
                            if (l == near && fy > lt.Base)
                            {
                                la = Math.Max(la, 0.15f * gone * Col.Exp(-Math.Abs(lu) / 3 - (fy - lt.Base) / (0.05f * H))
                                    * Col.Smoothstep(5.5f, 3.5f, Math.Abs(fx - lt.X) / lt.Rx));
                            }
                            if (la > amount) { amount = la; species = lt.Species; }
                        }
                        if (amount > 0.01f)
                        {
                            // Leaves lie in the light the ground has: a little brighter
                            // than it, in their own colors. Under the tree they tint the
                            // floor between them; on the near meadow they're cells seen
                            // in perspective, bigger and rounder nearer.
                            float cs = carpetCell[l];
                            float cu = fx / cs, cv = fy / (0.6f * cs), cpx = 1 / cs;
                            if (l == near)
                            {
                                float d0 = gy - horizonY, dy0 = fy - horizonY;
                                cu = (fx - w2) * d0 / (dy0 * cs);
                                cv = d0 * d0 / (0.6f * cs * dy0);
                                cpx = d0 / (dy0 * cs);
                            }
                            float iu = (float)Math.Floor(cu), iv = (float)Math.Floor(cv);
                            uint h1 = Col.Hash32(unchecked((uint)(int)iu * 0x9e3779b1 ^ (uint)(int)iv * 0x85ebca6b ^ 0x1ea7));
                            uint[] lpath = Leaves.Paths[species];
                            RGB fresh = RGB.Hex(lpath[lpath.Length - 1 - (int)(h1 >> 8) % 2]);
                            // A few leaves from a whole crown already cover a lot of floor;
                            // fresh ones are brighter and more colorful than the matted
                            // brown of winter.
                            float freshness = 1 - carpetBrown;
                            RGB floor = tone;
                            float floorLum = Math.Max(Overlay.Luminance(tone), 1e-5f), carpetSat = 0.55f + 0.35f * freshness;
                            RGB wash = OnGround(floor, floorLum, Col.MixOklab(RGB.Hex(lpath[lpath.Length - 2]), RGB.Hex(0x6a4a32), Math.Max(carpetBrown, 0.4f)),
                                                1.2f + 0.7f * freshness, lightLevel, carpetSat);
                            tone = Col.Mix(tone, wash, 0.7f * (1 - Col.Exp(-4 * pool)) * (1 - tree));
                            if (Col.Unit(h1) < 1 - Col.Exp(-4 * amount))
                            {
                                float fu = cu - iu - 0.35f - 0.3f * Col.Unit(h1 >> 4), fv = cv - iv - 0.35f - 0.3f * Col.Unit(h1 >> 12);
                                float inside = Col.Clamp01((0.34f - Col.Sqrt(fu * fu + fv * fv)) / cpx + 0.5f);
                                float brown = Col.Clamp01(carpetBrown + 0.35f * (Col.Unit(h1 >> 20) - 0.3f));
                                RGB fallen = OnGround(floor, floorLum, Col.MixOklab(fresh, RGB.Hex(0x6a4a32), brown),
                                                      1.4f + 1.2f * freshness + (0.6f + 0.6f * freshness) * Col.Unit(h1 >> 3), lightLevel, carpetSat);
                                tone = Col.Mix(tone, fallen, inside * (1 - tree));
                            }
                        }
                    }
                    if (groundSnow > 0 && tree > 0.3f)
                    {
                        // Snow settled on the tops of branches: tree here, open air just above.
                        float above = 0;
                        if (y >= snowAbove)
                        {
                            above = trees[(l * Height + y - snowAbove) * width + x] / 255f;
                            if (l >= 2) above = Math.Max(above, leaves[((l - 2) * Height + y - snowAbove) * width + x] / 255f * season.LeafFill);
                        }
                        tone = Col.Mix(tone, Col.Mix(snowOnTop, fog, layer.Haze * 0.5f), 0.85f * groundSnow * Col.Clamp01(tree - above));
                    }
                    if (groundSnow > 0 && l == near && Math.Abs(fx - cabin.X) < 1.1f * cabin.HalfWidth && land > 0)
                    {
                        // And on the roof.
                        float depth = fy - top[(l * width + x) * Sub + Sub / 2];
                        tone = Col.Mix(tone, snowOnTop, 0.9f * groundSnow * Col.Smoothstep(0.005f * H, 0.003f * H, depth));
                    }
                    if (l == 1 && rangeSnow > 0)
                    {
                        // Snow on the rocky range's higher peaks when the snow line is low.
                        float rline = rangeTop + 0.04f * H * rangeSnow + 1.5f * snowLine[x];
                        float ramount = Col.Smoothstep(rline + 3, rline - 3, fy);
                        if (ramount > 0) tone = Col.Mix(tone, Col.Mix(snowLight, fog, layer.Haze * 0.55f), ramount);
                    }
                    if (layer.Snow)
                    {
                        float sline = snowAt + snowLine[x];
                        float amount = Col.Smoothstep(sline + 3, sline - 3, fy);
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
                    if (groundSnow > 0 && !layer.Snow && fy >= gy)
                    {
                        // Snow on open ground; the trees stay dark.
                        tone = Col.Mix(tone, Col.Mix(snowGround, fog, layer.Haze * 0.5f), 0.75f * groundSnow * (1 - tree));
                    }
                    if (season.Frost > 0 && l >= 2 && fy >= gy)
                    {
                        tone = Col.Mix(tone, Col.Mix(frostColor, fog, layer.Haze * 0.5f), 0.35f * season.Frost * (1 - tree));  // hoarfrost
                    }
                    if (w.Fog > 0)
                    {
                        tone = Col.Mix(tone, fogColor, w.Fog * (0.9f - 0.12f * l));
                    }
                    if (w.Valley > 0)
                    {
                        // Fog lakes: each hill's foot sinks into bright fog; least in front.
                        float lake = Col.Smoothstep(0.004f * H, 0.05f * H, fy - gy) * (l == Layers.Length - 1 ? 0.35f : l == 0 ? 0.6f : 0.9f);
                        tone = Col.Mix(tone, valleyColor, w.Valley * lake * (1 - 0.5f * tree));
                    }
                    tone = tone + pal.Glow * (g * layer.Haze * 0.8f);  // in-scattered sun
                    if (seaRows > 0 && l >= 2)
                    {
                        if (l < Layers.Length - 1)
                            tone = Col.Mix(tone, seaShade * 0.5f, 0.45f * w.Sea);  // the hills beyond, in the clouds' shade
                        else if (fy < gy)
                            // The tall spruces' tops fade up into the clouds' base.
                            tone = Col.Mix(tone, seaHazeColor, 0.6f * seaBase * Col.Smoothstep(seaEdge[x] + 0.015f * H, seaEdge[x], fy));
                    }
                    c = cov == 1 ? tone : Col.Mix(c, tone, cov);
                    frontTree = frontTree * (1 - cov) + tree;
                }
                c = overNear.Over(c, x, y);
                if (seaRows > 0)
                {
                    // A faint haze of light over the sea's top.
                    float above = seaTopY[x] - fy;
                    if (above > 0) c = c + seaLit * (0.06f * w.Sea * Col.Exp(-above / (0.012f * H)));
                }
                if (seaRows > 0 && y >= seaRow0 && fy < seaEdge[x] + seaSoft)
                {
                    // The sea of clouds, down to its soft base, which wraps the treetops.
                    int fsi = (y - seaRow0) * width + x;
                    float frontCov = seaCover[fsi] * w.Sea * Col.Smoothstep(seaEdge[x] + seaSoft, seaEdge[x] - 0.5f * seaSoft, fy);
                    if (frontCov > 0) frontCov *= cloudiness(fx, seaDepth[fsi]);
                    if (frontCov > 0)
                    {
                        RGB frontTone = Col.MixOklab(Col.Mix(seaShade, seaLit, seaLight[fsi]), seaHazeColor, Col.Smoothstep(4, 45, seaDepth[fsi]));
                        c = Col.Mix(c, frontTone + pal.Glow * (g * 0.7f), frontCov);
                    }
                }

                if (glintGain > 0)
                {
                    // On open ground only: not on the trees or the porch.
                    float glint = glintPower[y * width + x] * (1 - Math.Min(frontTree, 1f));
                    if (glint > 0) c = c + hues[glintHue[y * width + x]] * (glint * glintGain);
                }
                if (frostGlint > 0)
                {
                    // Hoarfrost catching the low sun.
                    float fg = glintPower[y * width + x] * (1 - Math.Min(frontTree, 1f));
                    if (fg > 0) c = c + new RGB(0.9f, 0.95f, 1) * (fg * frostGlint);
                }

                if (windowLight > 0)
                {
                    float inside = Col.Clamp01(Math.Min(Math.Min(fx - wx0, wx1 - fx), Math.Min(fy - wy0, wy1 - fy)) + 0.5f);
                    c = Col.Mix(c, windowColor, inside * windowLight);
                    float wdx = fx - windowX, wdy = fy - windowY;
                    c = c + windowColor * (0.08f * windowLight * Col.Exp(-Col.Sqrt(wdx * wdx + wdy * wdy) / (0.012f * H)));
                }

                if (w.Snow > 0)
                {
                    float f = flakes[y * width + x];
                    if (f > 0.002f) c = c + iceColor * (0.6f * f * w.Snow);
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

    /// A fallen leaf's color on the floor: `k` times as bright as the floor,
    /// in its own colors (no brighter than in full light), `sat` of the way
    /// from the floor's.
    static RGB OnGround(RGB floor, float floorLum, RGB c, float k, float lightLevel, float sat)
    {
        return Col.MixOklab(floor, c * Math.Min(k * floorLum / Math.Max(Overlay.Luminance(c), 1e-5f), lightLevel), sat);
    }

    /// How much of a unit disk another disk of radius `r` covers, its center
    /// `d` away: 0…1.
    static float DiskOverlap(float r, float d)
    {
        if (d >= 1 + r) return 0;
        if (d <= Math.Abs(1 - r)) return Math.Min(r * r, 1);
        float a = (float)Math.Acos(Math.Max(-1, Math.Min(1, (d * d + 1 - r * r) / (2 * d))));
        float b = (float)Math.Acos(Math.Max(-1, Math.Min(1, (d * d + r * r - 1) / (2 * d * r))));
        return (a + r * r * b - 0.5f * Col.Sqrt((-d + 1 + r) * (d + 1 - r) * (d - 1 + r) * (d + 1 + r))) / (float)Math.PI;
    }
}
