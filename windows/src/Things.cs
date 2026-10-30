// Port of Sources/wallframes/Things.swift. Keep the two in step.

using System;

static class Things
{
    /// The cabin's small things, painted in front of its hill: solar panels on
    /// the roof, and the two bikes by the porch when their riders are home.
    /// `lit` gives a color as it looks in this frame's light and air.
    public static void DrawCabin(Overlay o, Cabin cabin, float H, float snow, Func<uint, RGB> lit, RGB sky, float glint, bool bikesHome)
    {
        float cx = cabin.X, hw = cabin.HalfWidth, b = cabin.Base, wallH = cabin.WallH, roofH = cabin.RoofH;
        bool snowy = snow > 0.3f;

        // Solar panels down the roof's left slope, three of them, glinting when the sun is low.
        if (!snowy)
        {
            float ax = cx, ay = b - wallH - roofH, ex = cx - 1.08f * hw, ey = b - wallH;
            RGB panel = Col.Mix(lit(0x1d2f57), sky * 0.5f, 0.25f);
            float[][] spans = { new[] { 0.18f, 0.40f }, new[] { 0.42f, 0.64f }, new[] { 0.66f, 0.88f } };
            foreach (float[] t in spans)
            {
                float x0 = ax + (ex - ax) * t[0], y0 = ay + (ey - ay) * t[0], x1 = ax + (ex - ax) * t[1], y1 = ay + (ey - ay) * t[1];
                o.Polygon(new[] { x0, y0 + 0.12f * roofH, x1, y1 + 0.12f * roofH, x1, y1 + 0.42f * roofH, x0, y0 + 0.42f * roofH }, panel);
                if (glint > 0) o.Line(x0, y0 + 0.14f * roofH, x1, y1 + 0.14f * roofH, 0.06f * roofH, new RGB(1, 0.95f, 0.85f) * glint);
            }
        }

        // The bikes, leaning by the porch: hers green, his orange.
        if (!bikesHome) return;
        float r = 0.2f * wallH, gy = b + 0.004f * H;
        uint[] colors = { 0x3f9a4a, 0xe8792b };
        for (int k = 0; k < 2; k++)
        {
            float rx = cabin.Porch0 + 0.15f * hw + k * 0.55f * r, ry = gy - r + k * 0.25f * r;
            float fx = rx + 2.6f * r, cxr = rx + 1.15f * r;
            float sx = rx + 0.95f * r, sy = ry - 1.25f * r, hx = rx + 2.2f * r, hy = ry - 1.25f * r;
            RGB tyre = lit(0x1c1c1c), frame = lit(colors[k]);
            float t = 0.13f * r;
            foreach (float wx in new[] { rx, fx })
            {
                for (int i = 0; i < 16; i++)
                {
                    float a0 = i * (float)Math.PI / 8, a1 = (i + 1) * (float)Math.PI / 8;
                    o.Line(wx + r * (float)Math.Cos(a0), ry + r * (float)Math.Sin(a0), wx + r * (float)Math.Cos(a1), ry + r * (float)Math.Sin(a1), 0.12f * r, tyre);
                }
            }
            float[][] tubes = { new[] { rx, ry, sx, sy }, new[] { rx, ry, cxr, ry }, new[] { cxr, ry, sx, sy },
                                new[] { sx, sy, hx, hy }, new[] { cxr, ry, hx, hy }, new[] { hx, hy, fx, ry } };
            foreach (float[] l in tubes) o.Line(l[0], l[1], l[2], l[3], t, frame);
            o.Line(sx - 0.2f * r, sy - 0.15f * r, sx + 0.25f * r, sy - 0.15f * r, 0.14f * r, tyre);  // saddle
            o.Line(hx, hy, hx + 0.15f * r, hy - 0.3f * r, t, tyre);                                // handlebar
        }
    }
}
