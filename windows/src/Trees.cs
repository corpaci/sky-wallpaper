// Port of Sources/wallframes/Trees.swift. Keep the two in step: the random
// draws must come in the same order, so the code follows the Swift line by line.

using System;
using System.Collections.Generic;
using System.Linq;

/// A leafy tree, grown the way a painter builds one. First the gesture: a
/// trunk that bends a little, forking into limbs that curve upward, each
/// forking again down to twigs, every fork as thick in all as what it grew
/// from (Leonardo's rule). Then the foliage: cloud-like clumps at the ends
/// of the branches, each a cluster of round lobes so the outline scallops,
/// lit from above in a few flat tones with an uneven edge between light and
/// shadow, darker deep in the crown, gaps where branches show, stray leaves
/// breaking the silhouette. The shape is fixed per seed; the seasons move
/// through it leaf by leaf (`Leaves.Look`).
sealed class LeafyTree
{
    public sealed class Clump
    {
        public float X, Y, R;
        public float[] Lobes;  // x, y, r for each lobe
        public float Depth;    // 0 at the crown's lit outside, 1 deep inside: darker
    }

    struct Joint { public float X, Y, A, R; }
    struct Fork { public float X, Y; public int Depth; }

    public readonly List<Capsule> Wood = new List<Capsule>();
    public List<Clump> Clumps = new List<Clump>();
    public readonly List<float[]> Tips = new List<float[]>();  // twig ends, where buds swell in spring
    public float CrownX, CrownY, CrownRx = 1, CrownRy = 1;    // its extent, for light across it
    public readonly int Species;  // 0 maple, 1 birch, 2 beech, 3 oak, 4 linden, 5 fruit tree (`Leaves.Paths`)
    public List<Capsule> Bark = new List<Capsule>();  // the birch's white-barked stem and limbs
    public readonly float Foot;   // where it stands

    public LeafyTree(float x, float b, float h, uint seed, bool fruit)
    {
        var rng = new SplitMix(unchecked(((ulong)seed * 0x9e3779b97f4a7c15) | 1));
        int maxDepth = h > 70 ? 5 : h > 30 ? 4 : 3;

        // Each species grows its own way (`Growths`), and each tree its own
        // within that: some lean and curve back up toward the light, some
        // split low into two stems.
        Species = fruit ? 5 : (int)(seed >> 5) % 5;
        Growth g = Growths[Species];
        float lean = (rng.Unit() - 0.5f) * (fruit ? 0.5f : 0.3f);
        float bow = -lean * (0.3f + 0.9f * rng.Unit());
        float trunkLength = g.Trunk * (0.75f + 0.5f * rng.Unit()) * h;
        float r = g.Thick * (0.8f + 0.45f * rng.Unit()) * h;
        bool twin = !g.Leader && rng.Unit() < 0.2f;
        float spread = g.Spread * (0.85f + 0.3f * rng.Unit());
        Foot = b;

        // Roots spread into the ground, so the trunk widens to it in a curve.
        float flare = g.Flare * (0.7f + 0.6f * rng.Unit());
        foreach (float side in new[] { -1f, 1f })
        {
            float reach = 1 + 0.3f * (rng.Unit() - 0.5f);
            Wood.Add(new Capsule(x + side * 0.35f * r, b - 1.4f * flare * r, x + side * (0.8f + 0.6f * flare * reach) * r,
                                 b + 0.2f * r, 0.6f * r, 0.25f * r));
            Wood.Add(new Capsule(x + side * 0.6f * r, b - 0.5f * flare * r, x + side * (1.1f + 0.8f * flare * reach) * r,
                                 b + 0.3f * r, 0.4f * r, 0.18f * r));
        }
        // A stem, bending as it rises; its joints are where limbs leave it.
        Func<float, float, float, float, float, float, int, List<Joint>> stem = (x0, y0, a0, curve, length, r0, steps) =>
        {
            float px = x0, py = y0, a = a0, sr = r0;
            var joints = new List<Joint>();
            for (int k = 0; k < steps; k++)
            {
                a += curve / steps + (rng.Unit() - 0.5f) * g.Crook;
                float nx = px + (float)Math.Sin(a) * length / steps, ny = py - (float)Math.Cos(a) * length / steps;
                Wood.Add(new Capsule(px, py, nx, ny, sr, sr * 0.92f));
                px = nx; py = ny; sr = sr * 0.92f;
                joints.Add(new Joint { X = px, Y = py, A = a, R = sr });
            }
            return joints;
        };

        // Branches fork down to twigs. Each bends slowly upward as it grows
        // (branches reach for light), or in birch arches out and hangs; it
        // wanders, in oak in elbows; at a fork the branches are as thick in
        // all as their parent (Leonardo).
        var forks = new List<Fork>();
        Action<float, float, float, float, float, int> branch = null;
        branch = (x0, y0, a0, length, r0, depth) =>
        {
            float bx = x0, by = y0, a = a0, br = r0;
            for (int k = 0; k < 3; k++)
            {
                a = a * g.Upright + (rng.Unit() - 0.5f) * g.Gnarl + (depth >= 3 ? g.Droop * (a < 0 ? -1 : 1) : 0);
                float nx = bx + (float)Math.Sin(a) * length / 3, ny = by - (float)Math.Cos(a) * length / 3;
                Wood.Add(new Capsule(bx, by, nx, ny, br, br * 0.9f));
                bx = nx; by = ny; br = br * 0.9f;
            }
            forks.Add(new Fork { X = bx, Y = by, Depth = depth });
            if (depth >= maxDepth) { Tips.Add(new[] { bx, by }); return; }
            int n = depth == 1 ? 3 : (rng.Unit() < 0.35f ? 3 : 2);
            float childR = br * Col.Sqrt(1f / n) * 0.97f;
            for (int k = 0; k < n; k++)
            {
                float side = n == 3 ? k - 1 : (k == 0 ? -1 : 1);
                branch(bx, by, a + side * (spread * 0.25f + 0.3f * rng.Unit()) + (rng.Unit() - 0.5f) * 0.2f,
                       length * (0.66f + 0.12f * rng.Unit()), childR, depth + 1);
            }
        };

        if (g.Leader)
        {
            // Birch and linden: the stem runs on up through the crown, its
            // branches leaving it one side then the other, the lower ones
            // longer and flatter, so the crown is an oval (narrow in birch).
            Joint bole = stem(x, b, lean, bow, trunkLength, r, 3).Last();
            int steps = Species == 1 ? 7 : 6;
            List<Joint> leader = stem(bole.X, bole.Y, bole.A, -0.5f * bole.A, (0.8f - g.Trunk) * h, bole.R, steps);
            for (int i = 0; i < leader.Count; i++)
            {
                Joint j = leader[i];
                float t = (i + 0.5f) / steps;
                float length = g.Limb * h * (float)Math.Sin((float)Math.PI * (0.25f + 0.7f * t)) * (0.85f + 0.3f * rng.Unit());
                float side = i % 2 == 0 ? -1 : 1;
                if (rng.Unit() < 0.25f) side = -side;
                float[] sides = rng.Unit() < 0.3f ? new[] { side, -side } : new[] { side };
                foreach (float s in sides)
                {
                    float a = j.A + s * spread * 0.5f * (1.25f - 0.5f * t) + (rng.Unit() - 0.5f) * 0.2f;
                    branch(j.X, j.Y, a, length, j.R * 0.6f, Species == 1 ? 2 : 1);
                }
            }
            Joint top = leader.Last();
            branch(top.X, top.Y, top.A, 0.5f * g.Limb * h, top.R * 0.8f, 2);
        }
        else
        {
            // The others divide into limbs where the trunk ends, the lowest
            // and widest a little below the rest.
            var trunks = new List<List<Joint>>();
            if (twin)
            {
                Joint low = stem(x, b, lean, 0, 0.35f * trunkLength, r, 2).Last();
                foreach (float side in new[] { -1f, 1f })
                    trunks.Add(stem(low.X, low.Y, low.A + side * (0.18f + 0.12f * rng.Unit()), bow, 0.75f * trunkLength, low.R * 0.72f, 3));
            }
            else
            {
                trunks.Add(stem(x, b, lean, bow, trunkLength, r, 4));
            }
            int limbs = (fruit ? 5 : 3 + (int)(rng.Unit() * 2.99f)) - (twin ? 1 : 0);
            foreach (List<Joint> joints in trunks)
            {
                for (int k = 0; k < limbs; k++)
                {
                    float u = (float)k / (limbs - 1) - 0.5f;
                    Joint j = Math.Abs(u) > 0.3f && rng.Unit() < 0.6f ? joints[joints.Count - 2] : joints[joints.Count - 1];
                    float a = u * spread * (twin ? 0.7f : 1) + (rng.Unit() - 0.5f) * 0.25f;
                    branch(j.X, j.Y, j.A * 0.6f + a, g.Limb * h * (twin ? 0.85f : 1) * (0.85f + 0.3f * rng.Unit()),
                           j.R * Col.Sqrt(1f / limbs), 1);
                }
            }
        }
        // Birch bark is white on the stem and the big limbs; its twigs are dark.
        if (Species == 1) Bark = Wood.Where(c => c.R0 >= 0.3f * r && c.Y0 < b - 1.5f * r).ToList();

        // The crown's extent, from the forks, to judge light and depth in it.
        var outer = forks.Where(f => f.Depth >= 2).ToList();
        float minX = outer.Count > 0 ? outer.Min(f => f.X) : x, maxX = outer.Count > 0 ? outer.Max(f => f.X) : x;
        float minY = outer.Count > 0 ? outer.Min(f => f.Y) : b - h, maxY = outer.Count > 0 ? outer.Max(f => f.Y) : b - h / 2;
        CrownX = (minX + maxX) / 2; CrownY = (minY + maxY) / 2;
        CrownRx = Math.Max((maxX - minX) / 2, 1); CrownRy = Math.Max((maxY - minY) / 2, 1);

        // Foliage: a clump at most forks, bigger on the inner forks, so the
        // clumps fill the crown and its edge is made of the smaller ones;
        // some left out, for gaps where the branches show.
        foreach (Fork f in forks)
        {
            if (!(rng.Unit() < (f.Depth == 1 ? 0.95f : 0.78f) * g.Fill)) continue;
            float size = f.Depth == 1 ? 0.14f : f.Depth <= maxDepth - 2 ? 0.11f : f.Depth == maxDepth - 1 ? 0.08f : 0.055f;
            float cr = size * g.Clump * h * (0.8f + 0.4f * rng.Unit());
            float cx = f.X + (rng.Unit() - 0.5f) * 0.3f * cr, cy = f.Y - 0.3f * cr;
            float ux = (cx - CrownX) / CrownRx, uy = (cy - CrownY) / CrownRy;
            float outward = Col.Clamp01(Col.Sqrt(ux * ux + uy * uy));
            var lobes = new List<float>();
            int count = f.Depth < maxDepth ? 8 : 5;
            for (int k = 0; k < count; k++)
            {
                float a = rng.Unit() * 2 * (float)Math.PI, d = Col.Sqrt(rng.Unit()) * 0.55f * cr;
                lobes.Add(cx + (float)Math.Cos(a) * d); lobes.Add(cy + (float)Math.Sin(a) * d * 0.85f); lobes.Add(cr * (0.4f + 0.25f * rng.Unit()));
            }
            if (outward > 0.7f)
            {
                // A leafy fringe on the crown's edge: small lobes on the outward side.
                float o = (float)Math.Atan2(uy, ux);
                for (int k = 0; k < 6; k++)
                {
                    float a = o + (rng.Unit() - 0.5f) * 2.2f;
                    lobes.Add(cx + (float)Math.Cos(a) * 0.85f * cr); lobes.Add(cy + (float)Math.Sin(a) * 0.8f * cr); lobes.Add(cr * (0.14f + 0.1f * rng.Unit()));
                }
            }
            Clumps.Add(new Clump { X = cx, Y = cy, R = cr, Lobes = lobes.ToArray(),
                                   Depth = Col.Clamp01(0.6f * (1 - outward) + 0.4f * Col.Clamp01(0.5f + 0.5f * uy)) });
        }
        // Back to front: deep and low first, so the lit outer clumps lie over them.
        Clumps = Clumps.OrderByDescending(c => c.Depth).ToList();
    }

    /// Paints the tree into coverage planes: the wood into `wood` (with the
    /// spruces, so it shades and catches snow like them) and the foliage into
    /// `leaf`, with each pixel's light band and height in the crown in `shade`
    /// (band << 6 | top, top 31 at the crown's top; bit 5 marks white birch
    /// bark under it, which shows when the leaves are down) and its species and
    /// distance from the crown's middle in `info` (species << 5 | outer).
    public void StampInto(byte[] woodPlane, int woodLayer, byte[] leaf, byte[] shade, byte[] info, int leafLayer, int width, int height, float h)
    {
        Scene.Stamp(Wood, woodPlane, woodLayer, width, height);
        int leafOffset = leafLayer * width * height;
        foreach (Capsule c in Bark)
        {
            // White bark (bit 5 of `shade`), but old and black-fissured low on the stem.
            float rr = Math.Max(c.R0, c.R1);
            int x0 = Math.Max((int)Math.Floor(Math.Min(c.X0, c.X1) - rr), 0), x1 = Math.Min((int)Math.Ceiling(Math.Max(c.X0, c.X1) + rr), width - 1);
            int y0 = Math.Max((int)Math.Floor(Math.Min(c.Y0, c.Y1) - rr), 0), y1 = Math.Min((int)Math.Ceiling(Math.Max(c.Y0, c.Y1) + rr), height - 1);
            if (x0 > x1 || y0 > y1) continue;
            float dx = c.X1 - c.X0, dy = c.Y1 - c.Y0, len2 = dx * dx + dy * dy;
            for (int py = y0; py <= y1; py++)
            {
                for (int px = x0; px <= x1; px++)
                {
                    float fx = px + 0.5f - c.X0, fy = py + 0.5f - c.Y0;
                    float t = len2 > 0 ? Col.Clamp01((fx * dx + fy * dy) / len2) : 0;
                    float ex = fx - t * dx, ey = fy - t * dy;
                    if (!(c.R0 + (c.R1 - c.R0) * t - Col.Sqrt(ex * ex + ey * ey) > 0)) continue;
                    float old = 1 - Col.Smoothstep(0.05f * h, 0.16f * h, Foot - py);
                    if (old > 0 && 0.5f + 0.5f * Col.ValueNoise2(px / (0.012f * h), py / (0.05f * h), 0x6a09e667) < old) continue;
                    shade[leafOffset + py * width + px] |= 0x20;
                }
            }
        }
        const float lightX = -0.55f, lightY = -0.83f;  // from the upper left
        foreach (Clump c in Clumps)
        {
            int x0 = Math.Max((int)Math.Floor(c.X - 1.4f * c.R), 0), x1 = Math.Min((int)Math.Ceiling(c.X + 1.4f * c.R), width - 1);
            int y0 = Math.Max((int)Math.Floor(c.Y - 1.4f * c.R), 0), y1 = Math.Min((int)Math.Ceiling(c.Y + 1.4f * c.R), height - 1);
            if (x0 > x1 || y0 > y1) continue;
            for (int py = y0; py <= y1; py++)
            {
                for (int px = x0; px <= x1; px++)
                {
                    float fx = px + 0.5f, fy = py + 0.5f;
                    // Coverage: the union of the lobes, a scalloped edge that
                    // wobbles like leaves rather than ruled circles.
                    float leafy = 0.2f * Col.ValueNoise2(fx / (0.012f * h), fy / (0.012f * h), 0x3c6ef372);
                    float cov = 0, lobeLight = 0;
                    for (int l = 0; l < c.Lobes.Length; l += 3)
                    {
                        float ldx = fx - c.Lobes[l], ldy = fy - c.Lobes[l + 1], lr = c.Lobes[l + 2];
                        float d = Col.Sqrt(ldx * ldx + ldy * ldy);
                        float k = Col.Clamp01(lr * (1 - leafy) - d + 0.5f);
                        if (k > cov) { cov = k; lobeLight = (ldx * lightX + ldy * lightY) / Math.Max(lr, 0.5f); }
                    }
                    if (!(cov > 0)) continue;
                    // Tone: the clump as one round mass, its lobes as smaller ones,
                    // an uneven terminator, darker deep inside; then flat bands.
                    float ux = (fx - c.X) / c.R, uy = (fy - c.Y) / c.R;
                    float mass = ux * lightX + uy * lightY;
                    float wobble = 0.35f * Col.ValueNoise2(fx / (0.025f * h), fy / (0.025f * h), 0x51ed270b);
                    float whole = (fx - CrownX) / CrownRx * lightX + (fy - CrownY) / CrownRy * lightY;
                    float tone = 0.48f + 0.22f * whole + 0.22f * mass + 0.16f * lobeLight + wobble * 0.5f - 0.3f * c.Depth;
                    int band = tone > 0.82f ? 3 : tone > 0.58f ? 2 : tone > 0.34f ? 1 : 0;
                    float cx = (fx - CrownX) / CrownRx, cy = (fy - CrownY) / CrownRy;
                    int top = (int)(Col.Clamp01(0.5f - 0.5f * cy) * 31);
                    int outward = (int)(Col.Clamp01(Col.Sqrt(cx * cx + cy * cy)) * 31);
                    int i = leafOffset + py * width + px;
                    byte v = (byte)Math.Round(cov * 255, MidpointRounding.AwayFromZero);
                    if (v >= leaf[i] || cov > 0.5f)  // later clumps lie over earlier ones
                    {
                        leaf[i] = Math.Max(leaf[i], v);
                        shade[i] = (byte)(band << 6 | shade[i] & 0x20 | top);
                        info[i] = (byte)(Species << 5 | outward);
                    }
                }
            }
        }
    }

    /// How each species grows: its trunk's length before it divides and its
    /// thickness (in tree heights), its root flare, how crooked the trunk; its
    /// limbs' length, how wide they spread, how much they turn back upward
    /// (1 = not at all), how much they wander, whether its twigs hang, and
    /// whether its stem runs on up through the crown. And its foliage: how big
    /// its clumps and how many forks bear one. (Trees.swift says more.)
    sealed class Growth
    {
        public float Trunk, Thick, Flare, Crook, Limb, Spread, Upright, Gnarl, Droop, Clump, Fill;
        public bool Leader;
    }

    static readonly Growth[] Growths = {
        new Growth { Trunk = 0.26f, Thick = 0.045f, Flare = 1.0f, Crook = 0.12f, Limb = 0.27f, Spread = 1.7f, Upright = 0.95f, Gnarl = 0.22f, Droop = 0, Leader = false, Clump = 1.0f, Fill = 1.0f },     // maple
        new Growth { Trunk = 0.24f, Thick = 0.026f, Flare = 0.5f, Crook = 0.08f, Limb = 0.19f, Spread = 1.0f, Upright = 0.9f, Gnarl = 0.16f, Droop = 0.18f, Leader = true, Clump = 0.6f, Fill = 0.75f }, // birch
        new Growth { Trunk = 0.30f, Thick = 0.048f, Flare = 1.3f, Crook = 0.04f, Limb = 0.28f, Spread = 1.8f, Upright = 0.95f, Gnarl = 0.14f, Droop = 0, Leader = false, Clump = 1.0f, Fill = 1.08f },    // beech
        new Growth { Trunk = 0.19f, Thick = 0.062f, Flare = 1.4f, Crook = 0.24f, Limb = 0.30f, Spread = 2.2f, Upright = 0.96f, Gnarl = 0.42f, Droop = 0, Leader = false, Clump = 0.9f, Fill = 0.88f },    // oak
        new Growth { Trunk = 0.24f, Thick = 0.042f, Flare = 1.0f, Crook = 0.05f, Limb = 0.20f, Spread = 1.3f, Upright = 0.9f, Gnarl = 0.18f, Droop = 0, Leader = true, Clump = 1.0f, Fill = 1.05f },      // linden
        new Growth { Trunk = 0.16f, Thick = 0.050f, Flare = 0.8f, Crook = 0.22f, Limb = 0.27f, Spread = 2.1f, Upright = 0.96f, Gnarl = 0.30f, Droop = 0, Leader = false, Clump = 0.9f, Fill = 1.0f },     // fruit tree
    };
}

/// The seasons in the leaves (Trees.swift: `leafPaths`, `leafLook`).
static class Leaves
{
    /// Each species' way through autumn, its leaves' colors in order: maple
    /// through yellow and orange to scarlet, birch to gold, beech to copper and
    /// russet, oak through olive and ochre to brown, linden to pale gold, the
    /// fruit trees to orange and red.
    public static readonly uint[][] Paths = {
        new uint[] { 0x4f8a3a, 0x9fb83c, 0xe8c43a, 0xe8792a, 0xc8382c },
        new uint[] { 0x4f8a3a, 0x9fb83c, 0xe8c43a, 0xe6b23a },
        new uint[] { 0x4f8a3a, 0x9fb83c, 0xe0b040, 0xb8622c, 0x8f4a28 },
        new uint[] { 0x4f8a3a, 0x7f8a3a, 0xb8903a, 0x8f4a28, 0x6f4a30 },
        new uint[] { 0x4f8a3a, 0x9fb83c, 0xe8cf6a, 0xe8cf6a },
        new uint[] { 0x4f8a3a, 0x9fb83c, 0xe8b830, 0xe07a2a, 0xc8442a },
    };
    /// And its habits: how much earlier (−) or later it turns; whether its
    /// outer leaves turn first (maple, oak, linden, cherry) or its inner ones
    /// (birch); whether it keeps its low dead leaves through winter (beech, oak).
    static readonly float[] Shift = { 0, -0.03f, 0.03f, 0.04f, -0.02f, 0 };
    static readonly bool[] OuterFirst = { true, false, true, true, true, true };
    static readonly bool[] Keeps = { false, false, true, true, false, false };

    /// How much of the season's leaf fall a species has had, 0…1.
    public static float Fall(Season season, int species) { return Col.Smoothstep(0.80f, 0.93f, season.Year - Shift[species]); }

    /// How a leaf pixel at (x, y) looks in a season: its color in full light,
    /// and whether it's there. (Trees.swift tells the dance.)
    public static RGB Look(byte shade, byte info, Season season, int x, int y, float H, out float presence)
    {
        float band = (shade >> 6) / 3f, top = (shade & 31) / 31f;
        int species = Math.Min(info >> 5, Paths.Length - 1);
        float outer = (info & 31) / 31f;
        uint[] path = Paths[species];
        float yr = season.Year;
        // Branch by branch the wave runs a little ahead or behind; leaf by leaf, a little more.
        float patch = 0.5f + 0.5f * Col.ValueNoise2(x / (0.008f * H), y / (0.008f * H), 0x7a3c19d1);
        float leaf = Col.Unit(Col.Hash32(unchecked((uint)(x / 2) * 0x9e3779b1 ^ (uint)(y / 2) * 0x85ebca6b ^ 0x1eaf)));
        float branch = 0.5f + 0.5f * Col.ValueNoise2(x / (0.004f * H), y / (0.004f * H), 0x2c1b3a5d);  // twig by twig

        float phase = Col.Clamp01(0.5f * (1 - top) + 0.3f * (OuterFirst[species] ? 1 - outer : outer) + 0.2f * patch);  // 0 turns first
        float autumn = Col.Smoothstep(0.70f, 0.86f, yr - Shift[species]);
        float stage = Col.Clamp01((autumn * 1.6f - phase) / 0.6f + 0.1f * (leaf - 0.5f));
        float k = stage * (path.Length - 1);
        int i = Math.Min((int)k, path.Length - 2);
        RGB color = Col.MixOklab(RGB.Hex(path[i]), RGB.Hex(path[i + 1]), k - i);
        // Young leaves: light yellow-green, darkening into summer.
        color = Col.MixOklab(color, RGB.Hex(0xc6e87a), yr < 0.5f ? 1 - Col.Smoothstep(0.32f, 0.47f, yr) : 0);

        float unfold = Col.Smoothstep(0.26f, 0.38f, yr);
        presence = yr < 0.5f ? (unfold * 1.2f > 0.25f * top + 0.75f * leaf ? 1 : 0)
                             : (Fall(season, species) * 1.2f > 0.1f + 0.3f * phase + 0.3f * branch + 0.3f * leaf ? 0 : 1);
        // Leaves fall a few at a time all over the crown, a little sooner where
        // they turned first; some twigs hold on longer than their neighbours.
        // What oak and beech keep thins out toward the top, held twig by twig.
        float keep = 0.6f * (1 - Col.Smoothstep(0.1f, 0.7f, top)) * (0.3f + 0.7f * branch);
        if (Keeps[species] && leaf < keep && (yr > 0.85f || unfold < 0.25f))
        {
            presence = 1;  // held dead through winter, bleaching
            color = Col.MixOklab(RGB.Hex(0x9a5a30), RGB.Hex(0xc0a07a), yr > 0.85f ? Col.Smoothstep(0.85f, 1, yr) * 0.4f : 0.4f + 0.6f * Col.Smoothstep(0, 0.2f, yr));
        }
        if (species == 5 && season.Blossom > 0)
        {
            // Fruit blossom, before the leaves: white and pink by cluster.
            bool pink = patch > 0.5f;
            RGB petals = RGB.Hex(pink ? 0xffcfdbu : 0xfff8f4u);
            if (0.3f * (1 - top) + 0.7f * leaf < season.Blossom * 1.1f) { color = petals; presence = 1; }
        }
        return Col.MixOklab(color * 0.45f, color * 1.12f, band);
    }
}
