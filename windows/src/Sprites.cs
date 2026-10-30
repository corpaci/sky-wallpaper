// Port of Sources/wallframes/Sprites.swift. Keep the two in step.

using System;

/// A small painting over one layer of the landscape: shapes laid one over
/// another in order, antialiased, into a patch of premultiplied RGBA. The
/// renderer puts it in front of its layer, so nearer layers still cover it.
sealed class Overlay
{
    public readonly int X0, Y0, Width, Height;
    readonly float[] rgba;

    /// Covers frame pixels x0..<x1, y0..<y1.
    public Overlay(int x0, int y0, int x1, int y1)
    {
        X0 = x0; Y0 = y0; Width = Math.Max(x1 - x0, 0); Height = Math.Max(y1 - y0, 0);
        rgba = new float[Width * Height * 4];
    }

    /// Lays `color` over what's there, as much as `coverage` gives at each
    /// pixel center inside the box.
    void Paint(float bx0, float by0, float bx1, float by1, RGB color, float alpha, Func<float, float, float> coverage)
    {
        int ix0 = Math.Max((int)Math.Floor(bx0) - X0, 0), ix1 = Math.Min((int)Math.Ceiling(bx1) - X0, Width - 1);
        int iy0 = Math.Max((int)Math.Floor(by0) - Y0, 0), iy1 = Math.Min((int)Math.Ceiling(by1) - Y0, Height - 1);
        if (ix0 > ix1 || iy0 > iy1) return;
        for (int py = iy0; py <= iy1; py++)
        {
            for (int px = ix0; px <= ix1; px++)
            {
                float a = coverage(px + X0 + 0.5f, py + Y0 + 0.5f) * alpha;
                if (!(a > 0)) continue;
                int i = (py * Width + px) * 4;
                rgba[i] = color.R * a + rgba[i] * (1 - a);
                rgba[i + 1] = color.G * a + rgba[i + 1] * (1 - a);
                rgba[i + 2] = color.B * a + rgba[i + 2] * (1 - a);
                rgba[i + 3] = a + rgba[i + 3] * (1 - a);
            }
        }
    }

    public void Circle(float cx, float cy, float r, RGB color, float alpha = 1)
    {
        Paint(cx - r - 1, cy - r - 1, cx + r + 1, cy + r + 1, color, alpha,
              (x, y) => Col.Clamp01(r - Col.Sqrt((x - cx) * (x - cx) + (y - cy) * (y - cy)) + 0.5f));
    }

    /// An ellipse with radii rx, ry, turned by `angle` radians.
    public void Ellipse(float cx, float cy, float rx, float ry, float angle, RGB color, float alpha = 1)
    {
        float c = (float)Math.Cos(angle), s = (float)Math.Sin(angle), r = Math.Max(rx, ry);
        Paint(cx - r - 1, cy - r - 1, cx + r + 1, cy + r + 1, color, alpha, (x, y) =>
        {
            float u = (x - cx) * c + (y - cy) * s, v = -(x - cx) * s + (y - cy) * c;
            float k = Col.Sqrt((u / rx) * (u / rx) + (v / ry) * (v / ry));
            return Col.Clamp01((1 - k) * Math.Min(rx, ry) + 0.5f);
        });
    }

    /// A tapered stroke: a limb, a pole, a plank.
    public void Stroke(Capsule cap, RGB color, float alpha = 1)
    {
        float r = Math.Max(cap.R0, cap.R1);
        float dx = cap.X1 - cap.X0, dy = cap.Y1 - cap.Y0, len2 = dx * dx + dy * dy;
        Paint(Math.Min(cap.X0, cap.X1) - r - 1, Math.Min(cap.Y0, cap.Y1) - r - 1, Math.Max(cap.X0, cap.X1) + r + 1, Math.Max(cap.Y0, cap.Y1) + r + 1,
              color, alpha, (x, y) =>
              {
                  float fx = x - cap.X0, fy = y - cap.Y0;
                  float t = len2 > 0 ? Col.Clamp01((fx * dx + fy * dy) / len2) : 0;
                  float ex = fx - t * dx, ey = fy - t * dy;
                  return Col.Clamp01(cap.R0 + (cap.R1 - cap.R0) * t - Col.Sqrt(ex * ex + ey * ey) + 0.5f);
              });
    }

    public void Line(float x0, float y0, float x1, float y1, float width, RGB color, float alpha = 1)
    {
        Stroke(new Capsule(x0, y0, x1, y1, width / 2, width / 2), color, alpha);
    }

    /// A filled polygon, its corners in order as x, y pairs.
    public void Polygon(float[] p, RGB color, float alpha = 1)
    {
        int n = p.Length / 2;
        if (n < 3) return;
        float minX = float.MaxValue, minY = float.MaxValue, maxX = float.MinValue, maxY = float.MinValue;
        for (int i = 0; i < n; i++)
        {
            minX = Math.Min(minX, p[2 * i]); maxX = Math.Max(maxX, p[2 * i]);
            minY = Math.Min(minY, p[2 * i + 1]); maxY = Math.Max(maxY, p[2 * i + 1]);
        }
        Paint(minX - 1, minY - 1, maxX + 1, maxY + 1, color, alpha, (x, y) =>
        {
            bool inside = false;
            float d = float.MaxValue;
            int j = n - 1;
            for (int i = 0; i < n; i++)
            {
                float ax = p[2 * j], ay = p[2 * j + 1], bx = p[2 * i], by = p[2 * i + 1];
                if ((by > y) != (ay > y) && x < (ax - bx) * (y - by) / (ay - by) + bx) inside = !inside;
                float ex = ax - bx, ey = ay - by, len2 = ex * ex + ey * ey;
                float t = len2 > 0 ? Col.Clamp01(((x - bx) * ex + (y - by) * ey) / len2) : 0;
                float qx = x - bx - t * ex, qy = y - by - t * ey;
                d = Math.Min(d, Col.Sqrt(qx * qx + qy * qy));
                j = i;
            }
            return Col.Clamp01(inside ? 0.5f + d : 0.5f - d);
        });
    }

    /// Light added, not laid over: a glow that doesn't hide what's behind it.
    public void Glow(float cx, float cy, float sigma, RGB color)
    {
        float reach = 3 * sigma;
        int ix0 = Math.Max((int)Math.Floor(cx - reach) - X0, 0), ix1 = Math.Min((int)Math.Ceiling(cx + reach) - X0, Width - 1);
        int iy0 = Math.Max((int)Math.Floor(cy - reach) - Y0, 0), iy1 = Math.Min((int)Math.Ceiling(cy + reach) - Y0, Height - 1);
        if (ix0 > ix1 || iy0 > iy1) return;
        for (int py = iy0; py <= iy1; py++)
        {
            for (int px = ix0; px <= ix1; px++)
            {
                float dx = px + X0 + 0.5f - cx, dy = py + Y0 + 0.5f - cy;
                float k = Col.Exp(-(dx * dx + dy * dy) / (2 * sigma * sigma));
                int i = (py * Width + px) * 4;
                rgba[i] += color.R * k;
                rgba[i + 1] += color.G * k;
                rgba[i + 2] += color.B * k;
            }
        }
    }

    /// Lays this patch over `c` at frame pixel (x, y).
    public RGB Over(RGB c, int x, int y)
    {
        int px = x - X0, py = y - Y0;
        if (px < 0 || px >= Width || py < 0 || py >= Height) return c;
        int i = (py * Width + px) * 4;
        float a = rgba[i + 3];
        return new RGB(c.R * (1 - a) + rgba[i], c.G * (1 - a) + rgba[i + 1], c.B * (1 - a) + rgba[i + 2]);
    }

    /// Luminance of linear RGB.
    public static float Luminance(RGB c) { return 0.2126f * c.R + 0.7152f * c.G + 0.0722f * c.B; }
}
