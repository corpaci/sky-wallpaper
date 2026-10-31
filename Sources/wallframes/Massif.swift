import Foundation

/// The summit, far off, as terrain: a massif some 25 km away, modeled as a
/// heightfield and seen in perspective from the cabin's hill. A crest of
/// peaks with the highest a horn, cols between them, worn by erosion into
/// ribs and gullies; faces that turn to the light or away from it; snow that
/// lies on the gentler slopes above the snow line and in the hollows, while
/// steep rock stays dark. The shape is fixed per seed; for each pixel this
/// keeps what lighting it needs (the surface's normal, height and distance),
/// and the renderer lights it per frame.
struct Massif {
    // In km. The eye stands on the cabin's hill; the snow line moves over the
    // summit from its foot to its top (Season.snowLine, Forecast.ground).
    static let eye: Float = 1.25, foot: Float = 1.0, peak: Float = 3.5
    static let curve: Float = 1 / (2 * 6371)  // the Earth's curve: a drop of z²/2R

    let row0: Int, rows: Int
    let silhouette: [Float]  // [x * sub + s] its top line, y
    let normal: [Float]      // [(r * width + x) * 3] facing, averaged over the pixel
    let alt: [Float]         // [r * width + x] height, km
    let dist: [Float]        // how far off, km
    let drift: [Float]       // km the snow line shifts down here: + in hollows, where snow gathers, − on ribs it blows off

    /// For a screen `width`×`height` with the eye level at `horizonY`. Only
    /// what shows above `hidden` (per column, the range in front) is kept.
    init(width: Int, height: Int, seed: UInt32, horizonY: Float, hidden: [Float], sub: Int) {
        let (W, H) = (Float(width), Float(height))
        let f = 2.4 * H  // px per unit of tangent: a long lens, as mountains are seen
        // The summit stands left of the middle, across from the cabin.
        let shape = Shape(seed: seed, xs: (0.40 * W - W / 2) / f * 26, zs: 26)

        // March each column's rays out from the eye, front to back. A sample
        // that rises above everything nearer shows in the rows it uncovers;
        // those rows take its normal, height and distance, weighted by how
        // much of each row it covers, so edges inside it are smooth too.
        let top = Int(max(horizonY - 0.30 * H, 0)), bottom = min(Int(hidden.max()! + 3), height)
        let span = bottom - top
        var acc = [Float](repeating: 0, count: width * span * 7)  // by column: weight, normal xyz, alt, dist, drift
        let (zNear, zFar) = (Float(5), Float(60))
        let fine = 0.75 / f  // the shortest step, as a share of the distance: under a pixel up a steep face
        // How fast, in km per km along a ray, the envelope can rise, the land's
        // coarse form, and the land itself: at most 0.57, 2.4 and 3.9 over six
        // seeds, measured in 20 m steps; with a margin.
        let (envelopeRise, coarseRise, landRise) = (Float(0.8), Float(3), Float(5))
        let peakTop = Shape.base + Shape.span * 1.2 + 0.05  // the highest it can be
        let rays = 2  // per pixel
        var tops = [Float](repeating: H, count: width * rays)
        acc.withUnsafeMutableBufferPointer { a in
            tops.withUnsafeMutableBufferPointer { s in
                let (a, s) = (a.baseAddress!, s.baseAddress!)
                DispatchQueue.concurrentPerform(iterations: width) { x in
                    let floor = min(hidden[x] + 3, Float(bottom))
                    for k in 0..<rays {
                        let u = ((Float(x) + (Float(k) + 0.5) / Float(rays)) - W / 2) / f
                        var ymin = floor, z = zNear
                        var last: (z: Float, h: Float) = (-1, 0)  // the last full sample on this ray
                        var (back, cap) = (z, Float.infinity)  // where this step began; how long steps may be
                        while z < zFar {
                            let wx = u * z, drop = z * z * Self.curve
                            // How high a sample must reach to show above what's covered:
                            // ruled out from its envelope if it can be, then its coarse
                            // form, then in full.
                            let need = Self.eye + drop + (horizonY - ymin) * z / f
                            var (gap, rise) = (need - shape.bound(wx, z), envelopeRise)
                            var pace: Float = 0  // up a face that shows: about a row per step
                            if gap <= 0 {
                                let c = shape.coarse(wx, z)
                                (gap, rise) = (need - shape.ceiling(c), coarseRise)
                                if gap <= 0 {
                                    let h = shape.height(c)
                                    (gap, rise) = (need - h.h, landRise)
                                    if gap < 0 {
                                        let y = horizonY - f * (h.h - Self.eye - drop) / z
                                        if ymin - y > 1.5 && z - back > 0.02 * fine * z {
                                            // It overshot a steep rise: back down, and up it in
                                            // steps of about a row.
                                            cap = (z - back) * max(1.2 / (ymin - y), 0.1)
                                            z = back + cap
                                            continue
                                        }
                                        // Its slope across, and along the ray (from the last
                                        // sample if it's close), for its facing.
                                        let e = 2 * z / f
                                        let nx = -(shape.height(wx + e, z).h - h.h) / e
                                        let along = z - last.z <= 2 * fine * z
                                            ? (h.h - last.h) / (z - last.z) : (shape.height(wx + u * e, z + e).h - h.h) / e
                                        let nz = -along - u * nx
                                        let len = (nx * nx + 1 + nz * nz).squareRoot()
                                        // Snow gathers in the hollows and blows off the ribs, and
                                        // lies in patches.
                                        let drift = 4 * (h.low - h.h) + 0.05 * fbm2(wx / 0.3, z / 0.3, octaves: 3, seed: shape.seed ^ 0x1f83d9ab)
                                        let w0 = 1 / Float(rays)
                                        for r in stride(from: max(Int(y), top), to: min(Int(ymin.rounded(.up)), bottom), by: 1) {
                                            let cover = min(Float(r + 1), ymin) - max(Float(r), y)
                                            guard cover > 0 else { continue }
                                            let o = (x * span + r - top) * 7, wt = cover * w0
                                            a[o] += wt
                                            a[o + 1] += wt * nx / len
                                            a[o + 2] += wt / len
                                            a[o + 3] += wt * nz / len
                                            a[o + 4] += wt * h.h
                                            a[o + 5] += wt * z
                                            a[o + 6] += wt * drift
                                        }
                                        (ymin, gap, cap) = (y, 0, .infinity)
                                        // How fast it climbs the screen along the ray, px per km.
                                        let up = ((along - 2 * z * Self.curve) * z - (h.h - Self.eye - drop)) * f / (z * z)
                                        if up > 0 { pace = 0.9 / up }
                                    }
                                    last = (z, h.h)
                                }
                            }
                            // Past this, even the highest peak would hide behind what's covered.
                            if ymin < horizonY - f * (peakTop - Self.eye - drop) / z { break }
                            // Step as far as the land can't close the gap in: long strides
                            // through open air, short ones up a face.
                            let climb = 2 * z * Self.curve + (horizonY - ymin) / f  // how fast that height rises
                            back = z
                            z += min(max(fine * z, gap / max(rise - climb, 0.1), min(pace, 40 * fine * z)), cap)
                        }
                        s[x * rays + k] = ymin
                    }
                }
            }
        }
        // Its top line at the scene's samples, between the rays.
        var sil = [Float](repeating: H, count: width * sub)
        for i in 0..<(width * sub) {
            let t = (Float(i) + 0.5) / Float(sub) * Float(rays) - 0.5  // in rays
            let j = min(max(Int(floorf(t)), 0), width * rays - 2)
            sil[i] = lerp(tops[j], tops[j + 1], t - Float(j))
        }
        // Keep only the rows it shows in.
        let first = max(Int(sil.min()!) - 1, top)
        row0 = first
        rows = bottom - first
        var (nrm, al, di, dr) = ([Float](repeating: 0, count: rows * width * 3), [Float](repeating: 0, count: rows * width),
                                 [Float](repeating: 0, count: rows * width), [Float](repeating: 0, count: rows * width))
        for i in 0..<(rows * width) {
            let o = ((i % width) * span + first - top + i / width) * 7
            let wt = acc[o]
            guard wt > 0 else { continue }
            (nrm[i * 3], nrm[i * 3 + 1], nrm[i * 3 + 2]) = (acc[o + 1] / wt, acc[o + 2] / wt, acc[o + 3] / wt)
            (al[i], di[i], dr[i]) = (acc[o + 4] / wt, acc[o + 5] / wt, acc[o + 6] / wt)
        }
        silhouette = sil
        normal = nrm
        alt = al
        dist = di
        drift = dr
    }

    /// The massif's form: where its crest runs and its peaks stand.
    struct Shape {
        let seed: UInt32
        let xs: Float, zs: Float  // the summit, km across and away
        let peaks: [(x: Float, h: Float, w: Float)]
        private let crestAt: [Float], lineAt: [Float]  // by km across from the summit, tabulated: −80…80 every 10 m

        init(seed: UInt32, xs: Float, zs: Float) {
            (self.seed, self.xs, self.zs) = (seed, xs, zs)
            // Lesser peaks along the crest, either side of the summit.
            var rng = SplitMix(state: UInt64(hash32(seed ^ 0x3c6ef372)) | 1)
            var p: [(x: Float, h: Float, w: Float)] = [(0, 1, 4.5)]
            for side: Float in [-1, 1] {
                var at: Float = 0
                for _ in 0..<3 {
                    at += 3 + 4 * rng.unit()
                    p.append((side * at, 0.5 + 0.3 * rng.unit() - 0.04 * at / 4, 2.5 + 2 * rng.unit()))
                }
            }
            peaks = p
            var (c, l) = ([Float](repeating: 0, count: 16001), [Float](repeating: 0, count: 16001))
            for i in 0...16000 {
                let dx = Float(i) / 100 - 80
                c[i] = 0.3 * Shape.falloff(abs(dx) / 14)
                for q in p { c[i] = max(c[i], q.h * Shape.falloff(abs(dx - q.x) / q.w)) }
                l[i] = zs + 0.12 * dx + 2.5 * fbm(dx / 16, octaves: 2, seed: seed ^ 0x510e527f)
            }
            (crestAt, lineAt) = (c, l)
        }

        /// The massif's envelope here: highest along its crest line, at the
        /// peaks on it, each a pointed cusp, with a lower ridge joining them;
        /// falling away on both sides, steeply near the crest and more gently
        /// toward its foot, as real mountain profiles do; broader under taller
        /// peaks. The crest runs a little askew to the view, and wanders.
        func envelope(_ x: Float, _ z: Float) -> Float {
            let t = min(max((x - xs + 80) * 100, 0), 15999.99)
            let i = Int(t), fr = t - Float(i)
            let (c, line) = (lerp(crestAt[i], crestAt[i + 1], fr), lerp(lineAt[i], lineAt[i + 1], fr))
            let reach = (z < line ? 4 : 5) + 6 * c
            return c * Shape.falloff(abs(z - line) / reach)
        }

        /// Much like e^−d, a cusp at 0 falling away concave, but in plain
        /// arithmetic, so the Windows port's terrain comes out the same to the
        /// last bit.
        static func falloff(_ d: Float) -> Float {
            let t = 1 + d / 2.3
            return 1 / (t * t * t)
        }

        static let (base, span) = (Massif.foot - 0.2, Massif.peak - Massif.foot + 0.2)

        /// The highest the terrain can be here, from the envelope alone.
        func bound(_ x: Float, _ z: Float) -> Float {
            let env = envelope(x, z)
            return Shape.base + Shape.span * (0.45 * env + 0.75 * env.squareRoot()) + 0.05
        }

        /// The land here to its first three octaves: its form before the detail.
        struct Coarse { let a, b: Float; var sum, weight, p, q: Float }

        func coarse(_ x: Float, _ z: Float) -> Coarse {
            // The ridges stand out more, for their height, on the lower parts.
            let env = envelope(x, z)
            var c = Coarse(a: Shape.base + Shape.span * 0.45 * env, b: Shape.span * 0.75 * env.squareRoot(),
                           sum: 0, weight: 1, p: x / 4, q: z / 4)
            ridges(&c, 0, 3)
            return c
        }

        /// The highest its finer octaves can take it.
        func ceiling(_ c: Coarse) -> Float { c.a + c.b * (c.sum + 0.248046875) / Shape.norm }

        /// The terrain's height, km, and the same without its finer detail.
        func height(_ c: Coarse) -> (h: Float, low: Float) {
            var d = c
            ridges(&d, 3, 10)
            return (c.a + c.b * d.sum / Shape.norm, c.a + c.b * c.sum / Shape.norm)
        }

        func height(_ x: Float, _ z: Float) -> (h: Float, low: Float) { height(coarse(x, z)) }

        static let norm: Float = 1.998046875  // the octaves' weights, 1 + ½ + … + ½⁹

        /// Ridged multifractal (Musgrave) in 2-D, octaves `from` to `to`:
        /// creased octaves, each weighted by the one before, so sharp crests
        /// branch into ribs and gullies, and detail gathers on the crests as on
        /// real ranges. Sums to 0…1 over all ten, divided by `norm`.
        func ridges(_ c: inout Coarse, _ from: Int, _ to: Int) {
            var amp: Float = 1
            for _ in 0..<from { amp *= 0.5 }
            for k in from..<to {
                var r = 1 - abs(valueNoise2(c.p, c.q, seed &+ UInt32(k) &* 1013))
                r = r * r * c.weight
                c.weight = clamp01(r * 1.6)
                c.sum += amp * r
                amp *= 0.5
                (c.p, c.q) = (1.6 * c.p - 1.2 * c.q, 1.2 * c.p + 1.6 * c.q)  // turned 37° and doubled, so no grid shows
            }
        }
    }
}
