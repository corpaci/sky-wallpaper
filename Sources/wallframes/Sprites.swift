import Foundation

/// A small painting over one layer of the landscape: shapes laid one over
/// another in order, antialiased, into a patch of premultiplied RGBA. The
/// renderer puts it in front of its layer, so nearer layers still cover it.
struct Overlay {
    let x0: Int, y0: Int, width: Int, height: Int
    private(set) var rgba: [Float]

    /// Covers frame pixels x0..<x1, y0..<y1.
    init(x0: Int, y0: Int, x1: Int, y1: Int) {
        (self.x0, self.y0, width, height) = (x0, y0, max(x1 - x0, 0), max(y1 - y0, 0))
        rgba = [Float](repeating: 0, count: width * height * 4)
    }

    /// Lays `color` over what's there, as much as `coverage` gives at each
    /// pixel center inside the box.
    private mutating func paint(_ bx0: Float, _ by0: Float, _ bx1: Float, _ by1: Float,
                                _ color: RGB, _ alpha: Float, _ coverage: (Float, Float) -> Float) {
        let (ix0, ix1) = (max(Int(floorf(bx0)) - x0, 0), min(Int(ceilf(bx1)) - x0, width - 1))
        let (iy0, iy1) = (max(Int(floorf(by0)) - y0, 0), min(Int(ceilf(by1)) - y0, height - 1))
        guard ix0 <= ix1, iy0 <= iy1 else { return }
        for py in iy0...iy1 {
            for px in ix0...ix1 {
                let a = coverage(Float(px + x0) + 0.5, Float(py + y0) + 0.5) * alpha
                guard a > 0 else { continue }
                let i = (py * width + px) * 4
                rgba[i] = color.r * a + rgba[i] * (1 - a)
                rgba[i + 1] = color.g * a + rgba[i + 1] * (1 - a)
                rgba[i + 2] = color.b * a + rgba[i + 2] * (1 - a)
                rgba[i + 3] = a + rgba[i + 3] * (1 - a)
            }
        }
    }

    mutating func circle(_ cx: Float, _ cy: Float, _ r: Float, _ color: RGB, alpha: Float = 1) {
        paint(cx - r - 1, cy - r - 1, cx + r + 1, cy + r + 1, color, alpha) { x, y in
            clamp01(r - ((x - cx) * (x - cx) + (y - cy) * (y - cy)).squareRoot() + 0.5)
        }
    }

    /// An ellipse with radii rx, ry, turned by `angle` radians.
    mutating func ellipse(_ cx: Float, _ cy: Float, _ rx: Float, _ ry: Float, _ angle: Float, _ color: RGB, alpha: Float = 1) {
        let (c, s, r) = (cosf(angle), sinf(angle), max(rx, ry))
        paint(cx - r - 1, cy - r - 1, cx + r + 1, cy + r + 1, color, alpha) { x, y in
            let (u, v) = ((x - cx) * c + (y - cy) * s, -(x - cx) * s + (y - cy) * c)
            let k = ((u / rx) * (u / rx) + (v / ry) * (v / ry)).squareRoot()
            return clamp01((1 - k) * min(rx, ry) + 0.5)
        }
    }

    /// A tapered stroke: a limb, a pole, a plank.
    mutating func capsule(_ c: Capsule, _ color: RGB, alpha: Float = 1) {
        let r = max(c.r0, c.r1)
        let dx = c.x1 - c.x0, dy = c.y1 - c.y0, len2 = dx * dx + dy * dy
        paint(min(c.x0, c.x1) - r - 1, min(c.y0, c.y1) - r - 1, max(c.x0, c.x1) + r + 1, max(c.y0, c.y1) + r + 1,
              color, alpha) { x, y in
            let (fx, fy) = (x - c.x0, y - c.y0)
            let t = len2 > 0 ? clamp01((fx * dx + fy * dy) / len2) : 0
            let (ex, ey) = (fx - t * dx, fy - t * dy)
            return clamp01(c.r0 + (c.r1 - c.r0) * t - (ex * ex + ey * ey).squareRoot() + 0.5)
        }
    }

    mutating func line(_ x0: Float, _ y0: Float, _ x1: Float, _ y1: Float, _ width: Float, _ color: RGB, alpha: Float = 1) {
        capsule(Capsule(x0: x0, y0: y0, x1: x1, y1: y1, r0: width / 2, r1: width / 2), color, alpha: alpha)
    }

    /// A filled polygon, its corners in order.
    mutating func polygon(_ p: [(x: Float, y: Float)], _ color: RGB, alpha: Float = 1) {
        guard p.count >= 3 else { return }
        let xs = p.map(\.x), ys = p.map(\.y)
        paint(xs.min()! - 1, ys.min()! - 1, xs.max()! + 1, ys.max()! + 1, color, alpha) { x, y in
            var inside = false, d = Float.greatestFiniteMagnitude
            var j = p.count - 1
            for i in 0..<p.count {
                let (a, b) = (p[j], p[i])
                if (b.y > y) != (a.y > y) && x < (a.x - b.x) * (y - b.y) / (a.y - b.y) + b.x { inside.toggle() }
                let (ex, ey) = (a.x - b.x, a.y - b.y), len2 = ex * ex + ey * ey
                let t = len2 > 0 ? clamp01(((x - b.x) * ex + (y - b.y) * ey) / len2) : 0
                let (qx, qy) = (x - b.x - t * ex, y - b.y - t * ey)
                d = min(d, (qx * qx + qy * qy).squareRoot())
                j = i
            }
            return clamp01(inside ? 0.5 + d : 0.5 - d)
        }
    }

    /// Light added, not laid over: a glow that doesn't hide what's behind it.
    mutating func glow(_ cx: Float, _ cy: Float, _ sigma: Float, _ color: RGB) {
        let reach = 3 * sigma
        let (ix0, ix1) = (max(Int(floorf(cx - reach)) - x0, 0), min(Int(ceilf(cx + reach)) - x0, width - 1))
        let (iy0, iy1) = (max(Int(floorf(cy - reach)) - y0, 0), min(Int(ceilf(cy + reach)) - y0, height - 1))
        guard ix0 <= ix1, iy0 <= iy1 else { return }
        for py in iy0...iy1 {
            for px in ix0...ix1 {
                let dx = Float(px + x0) + 0.5 - cx, dy = Float(py + y0) + 0.5 - cy
                let k = expf(-(dx * dx + dy * dy) / (2 * sigma * sigma))
                let i = (py * width + px) * 4
                rgba[i] += color.r * k
                rgba[i + 1] += color.g * k
                rgba[i + 2] += color.b * k
            }
        }
    }

    /// Lays this patch over `c` at frame pixel (x, y).
    @inline(__always) func over(_ c: RGB, _ x: Int, _ y: Int) -> RGB {
        let (px, py) = (x - x0, y - y0)
        guard px >= 0, px < width, py >= 0, py < height else { return c }
        let i = (py * width + px) * 4
        let a = rgba[i + 3]
        return RGB(c.r * (1 - a) + rgba[i], c.g * (1 - a) + rgba[i + 1], c.b * (1 - a) + rgba[i + 2])
    }
}

/// Luminance of linear RGB.
@inline(__always) func luminance(_ c: RGB) -> Float { 0.2126 * c.r + 0.7152 * c.g + 0.0722 * c.b }
