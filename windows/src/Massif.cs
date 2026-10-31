// Port of Sources/wallframes/Massif.swift; keep the two in step.
//
// The summit, far off, as terrain: a massif some 25 km away, modeled as a
// heightfield and seen in perspective from the cabin's hill. A crest of
// peaks with the highest a horn, cols between them, worn by erosion into
// ribs and gullies; faces that turn to the light or away from it; snow that
// lies on the gentler slopes above the snow line and in the hollows, while
// steep rock stays dark. The shape is fixed per seed; for each pixel this
// keeps what lighting it needs (the surface's normal, height and distance),
// and the renderer lights it per frame.

using System;
using System.Linq;
using System.Threading.Tasks;

sealed class Massif
{
    // In km. The eye stands on the cabin's hill; the snow line moves over the
    // summit from its foot to its top (Season.SnowLine, Forecast.Ground).
    public const float Eye = 1.25f, Foot = 1.0f, Peak = 3.5f;
    const float Curve = 1f / (2 * 6371);  // the Earth's curve: a drop of z²/2R

    public readonly int Row0, Rows;
    public readonly float[] Silhouette;  // [x * sub + s] its top line, y
    public readonly float[] Normal;      // [(r * width + x) * 3] facing, averaged over the pixel
    public readonly float[] Alt;         // [r * width + x] height, km
    public readonly float[] Dist;        // how far off, km
    public readonly float[] Drift;       // km the snow line shifts down here: + in hollows, where snow gathers, − on ribs it blows off

    /// For a screen `width`×`height` with the eye level at `horizonY`. Only
    /// what shows above `hidden` (per column, the range in front) is kept.
    public Massif(int width, int height, uint seed, float horizonY, float[] hidden, int sub)
    {
        float W = width, H = height;
        float f = 2.4f * H;  // px per unit of tangent: a long lens, as mountains are seen
        // The summit stands left of the middle, across from the cabin.
        var shape = new Shape(seed, (0.40f * W - W / 2) / f * 26, 26);

        // March each column's rays out from the eye, front to back. A sample
        // that rises above everything nearer shows in the rows it uncovers;
        // those rows take its normal, height and distance, weighted by how
        // much of each row it covers, so edges inside it are smooth too.
        int top = (int)Math.Max(horizonY - 0.30f * H, 0), bottom = Math.Min((int)(hidden.Max() + 3), height);
        int span = bottom - top;
        var acc = new float[width * span * 7];  // by column: weight, normal xyz, alt, dist, drift
        float zNear = 5, zFar = 60;
        float fine = 0.75f / f;  // the shortest step, as a share of the distance: under a pixel up a steep face
        // How fast, in km per km along a ray, the envelope can rise, the land's
        // coarse form, and the land itself: at most 0.57, 2.4 and 3.9 over six
        // seeds, measured in 20 m steps; with a margin.
        float envelopeRise = 0.8f, coarseRise = 3, landRise = 5;
        float peakTop = Shape.Base + Shape.Span * 1.2f + 0.05f;  // the highest it can be
        const int rays = 2;  // per pixel
        var tops = new float[width * rays];
        Parallel.For(0, width, x =>
        {
            float floor = Math.Min(hidden[x] + 3, (float)bottom);
            for (int k = 0; k < rays; k++)
            {
                float u = ((x + (k + 0.5f) / rays) - W / 2) / f;
                float ymin = floor, z = zNear;
                float lastZ = -1, lastH = 0;  // the last full sample on this ray
                float back = z, cap = float.PositiveInfinity;  // where this step began; how long steps may be
                while (z < zFar)
                {
                    float wx = u * z, drop = z * z * Curve;
                    // How high a sample must reach to show above what's covered:
                    // ruled out from its envelope if it can be, then its coarse
                    // form, then in full.
                    float need = Eye + drop + (horizonY - ymin) * z / f;
                    float gap = need - shape.Bound(wx, z), rise = envelopeRise;
                    float pace = 0;  // up a face that shows: about a row per step
                    if (gap <= 0)
                    {
                        Shape.Coarse c = shape.CoarseAt(wx, z);
                        gap = need - Shape.Ceiling(c);
                        rise = coarseRise;
                        if (gap <= 0)
                        {
                            float hh, low;
                            shape.Height(c, out hh, out low);
                            gap = need - hh;
                            rise = landRise;
                            if (gap < 0)
                            {
                                float y = horizonY - f * (hh - Eye - drop) / z;
                                if (ymin - y > 1.5f && z - back > 0.02f * fine * z)
                                {
                                    // It overshot a steep rise: back down, and up it in
                                    // steps of about a row.
                                    cap = (z - back) * Math.Max(1.2f / (ymin - y), 0.1f);
                                    z = back + cap;
                                    continue;
                                }
                                // Its slope across, and along the ray (from the last
                                // sample if it's close), for its facing.
                                float e = 2 * z / f;
                                float nx = -(shape.HeightAt(wx + e, z) - hh) / e;
                                float along = z - lastZ <= 2 * fine * z
                                    ? (hh - lastH) / (z - lastZ) : (shape.HeightAt(wx + u * e, z + e) - hh) / e;
                                float nz = -along - u * nx;
                                float len = Col.Sqrt(nx * nx + 1 + nz * nz);
                                // Snow gathers in the hollows and blows off the ribs, and
                                // lies in patches.
                                float drift = 4 * (low - hh) + 0.05f * Col.Fbm2(wx / 0.3f, z / 0.3f, 3, shape.Seed ^ 0x1f83d9ab);
                                float w0 = 1f / rays;
                                int r0 = Math.Max((int)y, top), r1 = Math.Min((int)Math.Ceiling(ymin), bottom);
                                for (int r = r0; r < r1; r++)
                                {
                                    float cover = Math.Min(r + 1, ymin) - Math.Max(r, y);
                                    if (cover <= 0) continue;
                                    int o = (x * span + r - top) * 7;
                                    float wt = cover * w0;
                                    acc[o] += wt;
                                    acc[o + 1] += wt * nx / len;
                                    acc[o + 2] += wt / len;
                                    acc[o + 3] += wt * nz / len;
                                    acc[o + 4] += wt * hh;
                                    acc[o + 5] += wt * z;
                                    acc[o + 6] += wt * drift;
                                }
                                ymin = y;
                                gap = 0;
                                cap = float.PositiveInfinity;
                                // How fast it climbs the screen along the ray, px per km.
                                float up = ((along - 2 * z * Curve) * z - (hh - Eye - drop)) * f / (z * z);
                                if (up > 0) pace = 0.9f / up;
                            }
                            lastZ = z;
                            lastH = hh;
                        }
                    }
                    // Past this, even the highest peak would hide behind what's covered.
                    if (ymin < horizonY - f * (peakTop - Eye - drop) / z) break;
                    // Step as far as the land can't close the gap in: long strides
                    // through open air, short ones up a face.
                    float climb = 2 * z * Curve + (horizonY - ymin) / f;  // how fast that height rises
                    back = z;
                    z += Math.Min(Math.Max(Math.Max(fine * z, gap / Math.Max(rise - climb, 0.1f)), Math.Min(pace, 40 * fine * z)), cap);
                }
                tops[x * rays + k] = ymin;
            }
        });
        // Its top line at the scene's samples, between the rays.
        var sil = new float[width * sub];
        for (int i = 0; i < width * sub; i++)
        {
            float t = (i + 0.5f) / sub * rays - 0.5f;  // in rays
            int j = Math.Min(Math.Max((int)Math.Floor(t), 0), width * rays - 2);
            sil[i] = Col.Lerp(tops[j], tops[j + 1], t - j);
        }
        // Keep only the rows it shows in.
        int first = Math.Max((int)sil.Min() - 1, top);
        Row0 = first;
        Rows = bottom - first;
        Normal = new float[Rows * width * 3];
        Alt = new float[Rows * width];
        Dist = new float[Rows * width];
        Drift = new float[Rows * width];
        for (int i = 0; i < Rows * width; i++)
        {
            int o = ((i % width) * span + first - top + i / width) * 7;
            float wt = acc[o];
            if (wt <= 0) continue;
            Normal[i * 3] = acc[o + 1] / wt;
            Normal[i * 3 + 1] = acc[o + 2] / wt;
            Normal[i * 3 + 2] = acc[o + 3] / wt;
            Alt[i] = acc[o + 4] / wt;
            Dist[i] = acc[o + 5] / wt;
            Drift[i] = acc[o + 6] / wt;
        }
        Silhouette = sil;
    }

    /// The massif's form: where its crest runs and its peaks stand.
    sealed class Shape
    {
        public readonly uint Seed;
        readonly float xs, zs;  // the summit, km across and away
        readonly float[] crestAt, lineAt;  // by km across from the summit, tabulated: −80…80 every 10 m

        public Shape(uint seed, float xs, float zs)
        {
            Seed = seed;
            this.xs = xs;
            this.zs = zs;
            // Lesser peaks along the crest, either side of the summit.
            var rng = new SplitMix((ulong)Col.Hash32(seed ^ 0x3c6ef372) | 1);
            var px = new float[7];
            var ph = new float[7];
            var pw = new float[7];
            px[0] = 0; ph[0] = 1; pw[0] = 4.5f;
            int n = 1;
            foreach (float side in new float[] { -1, 1 })
            {
                float at = 0;
                for (int i = 0; i < 3; i++)
                {
                    at += 3 + 4 * rng.Unit();
                    px[n] = side * at;
                    ph[n] = 0.5f + 0.3f * rng.Unit() - 0.04f * at / 4;
                    pw[n] = 2.5f + 2 * rng.Unit();
                    n++;
                }
            }
            crestAt = new float[16001];
            lineAt = new float[16001];
            for (int i = 0; i <= 16000; i++)
            {
                float dx = i / 100f - 80;
                float c = 0.3f * Falloff(Math.Abs(dx) / 14);
                for (int q = 0; q < n; q++) c = Math.Max(c, ph[q] * Falloff(Math.Abs(dx - px[q]) / pw[q]));
                crestAt[i] = c;
                lineAt[i] = zs + 0.12f * dx + 2.5f * Col.Fbm(dx / 16, 2, seed ^ 0x510e527f);
            }
        }

        /// The massif's envelope here: highest along its crest line, at the
        /// peaks on it, each a pointed cusp, with a lower ridge joining them;
        /// falling away on both sides, steeply near the crest and more gently
        /// toward its foot, as real mountain profiles do; broader under taller
        /// peaks. The crest runs a little askew to the view, and wanders.
        float Envelope(float x, float z)
        {
            float t = Math.Min(Math.Max((x - xs + 80) * 100, 0), 15999.99f);
            int i = (int)t;
            float fr = t - i;
            float c = Col.Lerp(crestAt[i], crestAt[i + 1], fr), line = Col.Lerp(lineAt[i], lineAt[i + 1], fr);
            float reach = (z < line ? 4 : 5) + 6 * c;
            return c * Falloff(Math.Abs(z - line) / reach);
        }

        /// Much like e^−d, a cusp at 0 falling away concave, but in plain
        /// arithmetic, so this port's terrain comes out the same to the last
        /// bit.
        static float Falloff(float d)
        {
            float t = 1 + d / 2.3f;
            return 1 / (t * t * t);
        }

        public static readonly float Base = Foot - 0.2f, Span = Peak - Foot + 0.2f;

        /// The highest the terrain can be here, from the envelope alone.
        public float Bound(float x, float z)
        {
            float env = Envelope(x, z);
            return Base + Span * (0.45f * env + 0.75f * Col.Sqrt(env)) + 0.05f;
        }

        /// The land here to its first three octaves: its form before the detail.
        public struct Coarse { public float A, B, Sum, Weight, P, Q; }

        public Coarse CoarseAt(float x, float z)
        {
            // The ridges stand out more, for their height, on the lower parts.
            float env = Envelope(x, z);
            var c = new Coarse { A = Base + Span * 0.45f * env, B = Span * 0.75f * Col.Sqrt(env), Sum = 0, Weight = 1, P = x / 4, Q = z / 4 };
            Ridges(ref c, 0, 3);
            return c;
        }

        /// The highest its finer octaves can take it.
        public static float Ceiling(Coarse c) { return c.A + c.B * (c.Sum + 0.248046875f) / Norm; }

        /// The terrain's height, km, and the same without its finer detail.
        public void Height(Coarse c, out float h, out float low)
        {
            Coarse d = c;
            Ridges(ref d, 3, 10);
            h = c.A + c.B * d.Sum / Norm;
            low = c.A + c.B * c.Sum / Norm;
        }

        public float HeightAt(float x, float z)
        {
            float h, low;
            Height(CoarseAt(x, z), out h, out low);
            return h;
        }

        const float Norm = 1.998046875f;  // the octaves' weights, 1 + ½ + … + ½⁹

        /// Ridged multifractal (Musgrave) in 2-D, octaves `from` to `to`:
        /// creased octaves, each weighted by the one before, so sharp crests
        /// branch into ribs and gullies, and detail gathers on the crests as on
        /// real ranges. Sums to 0…1 over all ten, divided by `Norm`.
        void Ridges(ref Coarse c, int from, int to)
        {
            float amp = 1;
            for (int i = 0; i < from; i++) amp *= 0.5f;
            for (int k = from; k < to; k++)
            {
                float r = 1 - Math.Abs(Col.ValueNoise2(c.P, c.Q, unchecked(Seed + (uint)k * 1013)));
                r = r * r * c.Weight;
                c.Weight = Col.Clamp01(r * 1.6f);
                c.Sum += amp * r;
                amp *= 0.5f;
                float p = 1.6f * c.P - 1.2f * c.Q, q = 1.2f * c.P + 1.6f * c.Q;  // turned 37° and doubled, so no grid shows
                c.P = p;
                c.Q = q;
            }
        }
    }
}
