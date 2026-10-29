// Port of Sources/wallframes/Color.swift, in C# 5 so the compiler that ships
// with Windows (.NET Framework 4.x csc.exe) builds it. Keep the two in step:
// windows/parity.sh renders the same frames with both and compares pixels.

using System;
using System.Linq;

/// Linear-light RGB. Light adds here; palettes blend in OKLab; sRGB encoding
/// happens once, at quantization.
struct RGB
{
    public float R, G, B;

    public RGB(float r, float g, float b) { R = r; G = g; B = b; }

    /// From an sRGB hex literal such as 0xffb36b.
    public static RGB Hex(uint hex)
    {
        return new RGB(Col.SrgbToLinear(((hex >> 16) & 0xff) / 255f),
                       Col.SrgbToLinear(((hex >> 8) & 0xff) / 255f),
                       Col.SrgbToLinear((hex & 0xff) / 255f));
    }

    public static RGB operator +(RGB x, RGB y) { return new RGB(x.R + y.R, x.G + y.G, x.B + y.B); }
    public static RGB operator *(RGB x, float k) { return new RGB(x.R * k, x.G * k, x.B * k); }
}

static class Col
{
    public static float Lerp(float a, float b, float t) { return a + (b - a) * t; }

    public static RGB Mix(RGB x, RGB y, float t)
    {
        return new RGB(Lerp(x.R, y.R, t), Lerp(x.G, y.G, t), Lerp(x.B, y.B, t));
    }

    public static float Clamp01(float x) { return Math.Min(Math.Max(x, 0f), 1f); }

    /// Hermite step; edges may be given high-to-low for a falling step.
    public static float Smoothstep(float e0, float e1, float x)
    {
        float t = Clamp01((x - e0) / (e1 - e0));
        return t * t * (3 - 2 * t);
    }

    public static float Pow(float x, float y) { return (float)Math.Pow(x, y); }
    public static float Exp(float x) { return (float)Math.Exp(x); }
    public static float Sqrt(float x) { return (float)Math.Sqrt(x); }

    // .NET Framework has no Math.Cbrt, and Math.Pow is NaN for negative bases.
    static float Cbrt(float x) { return x < 0 ? -(float)Math.Pow(-x, 1.0 / 3) : (float)Math.Pow(x, 1.0 / 3); }

    public static float SrgbToLinear(float c) { return c <= 0.04045f ? c / 12.92f : Pow((c + 0.055f) / 1.055f, 2.4f); }
    public static float LinearToSrgb(float c) { return c <= 0.0031308f ? c * 12.92f : 1.055f * Pow(c, 1f / 2.4f) - 0.055f; }

    /// Blend in OKLab (Björn Ottosson, 2020): perceptually even, so a navy→peach
    /// sky does not pass through the gray mud that linear-RGB blending gives.
    public static RGB MixOklab(RGB x, RGB y, float t)
    {
        float[] a = ToOklab(x), b = ToOklab(y);
        return FromOklab(Lerp(a[0], b[0], t), Lerp(a[1], b[1], t), Lerp(a[2], b[2], t));
    }

    static readonly RGB[] spectrumStops = new uint[] { 0x8b5cf6, 0x3b82f6, 0x22d3ee, 0x34d399, 0xfde047, 0xfb923c, 0xef4444 }
        .Select(RGB.Hex).ToArray();

    /// The visible spectrum from violet (0) to red (1), blended in OKLab: the
    /// colors of a rainbow's band, or of light split by a drop.
    public static RGB Spectrum(float t)
    {
        float x = Clamp01(t) * (spectrumStops.Length - 1);
        int i = Math.Min((int)x, spectrumStops.Length - 2);
        return MixOklab(spectrumStops[i], spectrumStops[i + 1], x - i);
    }

    /// Toward grey at the same lightness: OKLab chroma scaled down by `t`.
    public static RGB Desaturate(RGB c, float t)
    {
        float[] l = ToOklab(c);
        return FromOklab(l[0], l[1] * (1 - t), l[2] * (1 - t));
    }

    static float[] ToOklab(RGB c)
    {
        float l = Cbrt(0.4122214708f * c.R + 0.5363325363f * c.G + 0.0514459929f * c.B);
        float m = Cbrt(0.2119034982f * c.R + 0.6806995451f * c.G + 0.1073969566f * c.B);
        float s = Cbrt(0.0883024619f * c.R + 0.2817188376f * c.G + 0.6299787005f * c.B);
        return new[] {
            0.2104542553f * l + 0.7936177850f * m - 0.0040720468f * s,
            1.9779984951f * l - 2.4285922050f * m + 0.4505937099f * s,
            0.0259040371f * l + 0.7827717662f * m - 0.8086757660f * s,
        };
    }

    static RGB FromOklab(float L, float a, float b)
    {
        float l = L + 0.3963377774f * a + 0.2158037573f * b;
        float m = L - 0.1055613458f * a - 0.0638541728f * b;
        float s = L - 0.0894841775f * a - 1.2914855480f * b;
        float l3 = l * l * l, m3 = m * m * m, s3 = s * s * s;
        return new RGB(4.0767416621f * l3 - 3.3077115913f * m3 + 0.2309699292f * s3,
                       -1.2684380046f * l3 + 2.6097574011f * m3 - 0.3413193965f * s3,
                       -0.0041960863f * l3 - 0.7034186147f * m3 + 1.7076147010f * s3);
    }

    // Deterministic noise. Wrapping arithmetic is the point here.

    public static uint Hash32(uint v)
    {
        unchecked
        {
            uint x = v;
            x ^= x >> 16; x *= 0x7feb352d;
            x ^= x >> 15; x *= 0x846ca68b;
            x ^= x >> 16;
            return x;
        }
    }

    public static float Unit(uint h) { return (h >> 8) / 16777216f; }

    /// 1-D value noise in [-1, 1] with quintic interpolation.
    public static float ValueNoise(float u, uint seed)
    {
        float i = (float)Math.Floor(u), f = u - i;
        float t = f * f * f * (f * (f * 6 - 15) + 10);
        unchecked
        {
            uint k = (uint)(int)i;
            float a = Unit(Hash32((k * 0x9e3779b1) ^ seed)) * 2 - 1;
            float b = Unit(Hash32(((k + 1) * 0x9e3779b1) ^ seed)) * 2 - 1;
            return Lerp(a, b, t);
        }
    }

    /// Fractal sum of value noise, normalized to roughly [-1, 1].
    public static float Fbm(float u, int octaves, uint seed)
    {
        float sum = 0, amp = 1, norm = 0, freq = 1;
        for (int k = 0; k < octaves; k++)
        {
            sum += amp * ValueNoise(u * freq + k * 17.31f, unchecked(seed + (uint)k * 1013));
            norm += amp;
            amp *= 0.5f;
            freq *= 2.03f;
        }
        return sum / norm;
    }

    /// 2-D value noise in [-1, 1] with quintic interpolation.
    public static float ValueNoise2(float u, float v, uint seed)
    {
        float i = (float)Math.Floor(u), j = (float)Math.Floor(v);
        float fu = u - i, fv = v - j;
        float tu = fu * fu * fu * (fu * (fu * 6 - 15) + 10);
        float tv = fv * fv * fv * (fv * (fv * 6 - 15) + 10);
        unchecked
        {
            uint ki = (uint)(int)i, kj = (uint)(int)j;
            float top = Lerp(Corner(ki, kj, seed), Corner(ki + 1, kj, seed), tu);
            float bottom = Lerp(Corner(ki, kj + 1, seed), Corner(ki + 1, kj + 1, seed), tu);
            return Lerp(top, bottom, tv);
        }
    }

    static float Corner(uint a, uint b, uint seed)
    {
        return Unit(Hash32(unchecked((a * 0x9e3779b1) ^ (b * 0x85ebca6b) ^ seed))) * 2 - 1;
    }

    /// Fractal sum of 2-D value noise, normalized to roughly [-1, 1].
    public static float Fbm2(float u, float v, int octaves, uint seed)
    {
        float sum = 0, amp = 1, norm = 0, freq = 1;
        for (int k = 0; k < octaves; k++)
        {
            sum += amp * ValueNoise2(u * freq + k * 17.31f, v * freq + k * 9.77f, unchecked(seed + (uint)k * 1013));
            norm += amp;
            amp *= 0.5f;
            freq *= 2.03f;
        }
        return sum / norm;
    }

    /// Ridged multifractal (Musgrave): creased octaves, each weighted by the one
    /// before, so detail gathers on the crests the way it does on real ranges.
    /// Roughly [0, 0.8].
    public static float Ridged(float u, int octaves, uint seed)
    {
        float sum = 0, amp = 1, norm = 0, freq = 1, weight = 1;
        for (int k = 0; k < octaves; k++)
        {
            float r = 1 - Math.Abs(ValueNoise(u * freq + k * 17.31f, unchecked(seed + (uint)k * 1013)));
            r = r * r * weight;
            weight = Clamp01(r * 1.6f);
            sum += amp * r;
            norm += amp;
            amp *= 0.5f;
            freq *= 2.1f;
        }
        return sum / norm;
    }
}

sealed class SplitMix
{
    ulong state;

    public SplitMix(ulong state) { this.state = state; }

    public ulong Next()
    {
        unchecked
        {
            state += 0x9e3779b97f4a7c15;
            ulong z = state;
            z = (z ^ (z >> 30)) * 0xbf58476d1ce4e5b9;
            z = (z ^ (z >> 27)) * 0x94d049bb133111eb;
            return z ^ (z >> 31);
        }
    }

    public float Unit() { return (Next() >> 40) / 16777216f; }
}
