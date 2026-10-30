import Foundation

/// The cabin's small things, painted in front of its hill: solar panels on
/// the roof, and the two bikes by the porch when their riders are home.
/// `lit` gives a color as it looks in this frame's light and air.
func drawCabinThings(_ o: inout Overlay, cabin: Scene.Cabin, H: Float, snow: Float,
                     lit: (UInt32) -> RGB, sky: RGB, glint: Float, bikesHome: Bool) {
    let (cx, hw, b, wallH, roofH) = (cabin.x, cabin.halfWidth, cabin.base, cabin.wallH, cabin.roofH)
    let snowy = snow > 0.3

    // Solar panels down the roof's left slope, three of them, glinting when the sun is low.
    if !snowy {
        let (ax, ay, ex, ey) = (cx, b - wallH - roofH, cx - 1.08 * hw, b - wallH)
        let panel = mix(lit(0x1d2f57), sky * 0.5, 0.25)
        for (t0, t1) in [(Float(0.18), Float(0.40)), (0.42, 0.64), (0.66, 0.88)] {
            let (x0, y0, x1, y1) = (ax + (ex - ax) * t0, ay + (ey - ay) * t0, ax + (ex - ax) * t1, ay + (ey - ay) * t1)
            o.polygon([(x0, y0 + 0.12 * roofH), (x1, y1 + 0.12 * roofH), (x1, y1 + 0.42 * roofH), (x0, y0 + 0.42 * roofH)], panel)
            if glint > 0 { o.line(x0, y0 + 0.14 * roofH, x1, y1 + 0.14 * roofH, 0.06 * roofH, RGB(1, 0.95, 0.85) * glint) }
        }
    }

    // The bikes, leaning by the porch: hers green, his orange.
    guard bikesHome else { return }
    let r = 0.2 * wallH, gy = b + 0.004 * H
    for (k, color) in [UInt32(0x3f9a4a), 0xe8792b].enumerated() {
        let (rx, ry) = (cabin.porch0 + 0.15 * hw + Float(k) * 0.55 * r, gy - r + Float(k) * 0.25 * r)
        let (fx, cxr) = (rx + 2.6 * r, rx + 1.15 * r)
        let (sx, sy, hx, hy) = (rx + 0.95 * r, ry - 1.25 * r, rx + 2.2 * r, ry - 1.25 * r)
        let tyre = lit(0x1c1c1c), frame = lit(color), t = 0.13 * r
        for wx in [rx, fx] {
            for i in 0..<16 {
                let (a0, a1) = (Float(i) * .pi / 8, Float(i + 1) * .pi / 8)
                o.line(wx + r * cosf(a0), ry + r * sinf(a0), wx + r * cosf(a1), ry + r * sinf(a1), 0.12 * r, tyre)
            }
        }
        for (x0, y0, x1, y1) in [(rx, ry, sx, sy), (rx, ry, cxr, ry), (cxr, ry, sx, sy), (sx, sy, hx, hy), (cxr, ry, hx, hy), (hx, hy, fx, ry)] {
            o.line(x0, y0, x1, y1, t, frame)
        }
        o.line(sx - 0.2 * r, sy - 0.15 * r, sx + 0.25 * r, sy - 0.15 * r, 0.14 * r, tyre)   // saddle
        o.line(hx, hy, hx + 0.15 * r, hy - 0.3 * r, t, tyre)                                // handlebar
    }
}
