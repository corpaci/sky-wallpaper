import Foundation

/// A stylized sun: a sine arc between sunrise and sunset, and a deeper one
/// below the horizon at night. Altitudes in degrees, times in local minutes.
struct SunModel {
    let sunrise: Int, sunset: Int
    let peak: Float = 38, depth: Float = 40

    var dayLength: Float { Float(sunset - sunrise) }
    var nightLength: Float { 1440 - dayLength }
    var noon: Int { (sunrise + sunset) / 2 }
    var midnight: Int { (sunset + Int(nightLength) / 2) % 1440 }

    /// 0 at sunrise … 1 at sunset; nil at night.
    func dayPhase(_ minute: Int) -> Float? {
        let p = Float(minute - sunrise) / dayLength
        return (0...1).contains(p) ? p : nil
    }

    /// 0 at sunset … 1 at sunrise; above 1 during the day.
    func nightPhase(_ minute: Int) -> Float {
        Float(((minute - sunset) % 1440 + 1440) % 1440) / nightLength
    }

    func altitude(_ minute: Int) -> Float {
        if let p = dayPhase(minute) { return peak * sinf(.pi * p) }
        return -depth * sinf(.pi * nightPhase(minute))
    }

    /// When the sun crosses `alt`, on the morning or the evening side.
    func minute(at alt: Float, evening: Bool) -> Int {
        let t: Float
        if alt >= 0 {
            let d = dayLength * asinf(min(alt / peak, 1)) / .pi
            t = evening ? Float(sunset) - d : Float(sunrise) + d
        } else {
            let d = nightLength * asinf(min(-alt / depth, 1)) / .pi
            t = evening ? Float(sunset) + d : Float(sunrise) - d
        }
        return (Int(t.rounded()) % 1440 + 1440) % 1440
    }
}

/// The sky at one sun altitude, linear light. `land` is the nearest ridge;
/// farther ridges fade toward `horizon`.
struct Palette {
    var zenith, mid, horizon, glow, land: RGB

    static func blend(_ p: Palette, _ q: Palette, _ t: Float) -> Palette {
        Palette(zenith: mixOklab(p.zenith, q.zenith, t), mid: mixOklab(p.mid, q.mid, t),
                horizon: mixOklab(p.horizon, q.horizon, t), glow: mixOklab(p.glow, q.glow, t),
                land: mixOklab(p.land, q.land, t))
    }

    /// Under a cloud deck: greyer and darker, the sky more than the land.
    func overcast(_ k: Float) -> Palette {
        func grey(_ c: RGB, _ dim: Float) -> RGB { desaturate(c, 0.8 * k) * (1 - dim * k) }
        return Palette(zenith: grey(zenith, 0.35), mid: grey(mid, 0.25), horizon: grey(horizon, 0.2),
                       glow: grey(glow, 0.3), land: grey(land, 0.2))
    }

    /// Under a bright moon the night sky turns deep blue, and land and snow
    /// come out of the dark.
    func moonlit(_ k: Float) -> Palette {
        Palette(zenith: zenith + RGB(0.004, 0.008, 0.024) * k, mid: mid + RGB(0.006, 0.011, 0.030) * k,
                horizon: horizon + RGB(0.009, 0.015, 0.034) * k, glow: glow + RGB(0.010, 0.016, 0.032) * k,
                land: land + RGB(0.002, 0.004, 0.009) * k)
    }
}

private func key(_ alt: Float, _ zenith: UInt32, _ mid: UInt32, _ horizon: UInt32,
                 _ glow: UInt32, _ land: UInt32) -> (alt: Float, palette: Palette) {
    (alt, Palette(zenith: RGB(hex: zenith), mid: RGB(hex: mid), horizon: RGB(hex: horizon),
                  glow: RGB(hex: glow), land: RGB(hex: land)))
}

// Keyframes by sun altitude. Mornings run clean and cool; evenings carry
// more haze, so their horizon goes to coral and rose. Both share the night.
private let nightKeys = [
    key(-18, 0x070b18, 0x0c1328, 0x18203f, 0x202a52, 0x04060d),
    key(-10, 0x0b1430, 0x17224a, 0x33386a, 0x4a4580, 0x070a18),
]
private let morningKeys = nightKeys + [
    key(-5, 0x13224f, 0x2e3f78, 0x7a6a9c, 0x9a7aa8, 0x0e1228),
    key(-1.5, 0x1f3a75, 0x5a6fae, 0xf2a387, 0xffb38f, 0x1c1d3a),
    key(1, 0x2f5a9e, 0x8aa3d4, 0xffc08a, 0xffcf8a, 0x2a2a48),
    key(6, 0x3a72b8, 0x9fc0e4, 0xffe2b3, 0xfff0c8, 0x2f3d58),
    key(15, 0x3b80c8, 0x86bbe6, 0xd6ebf5, 0xfffaf0, 0x2c4558),
    key(35, 0x2c72c0, 0x6eaee3, 0xc4e3f4, 0xfffaf0, 0x2a4656),
]
private let eveningKeys = nightKeys + [
    key(-5, 0x141f4c, 0x3a3a78, 0x9a5f8e, 0xb0688f, 0x120f26),
    key(-1.5, 0x23336e, 0x7a5f9e, 0xff7f6a, 0xff8f6a, 0x241a38),
    key(1, 0x34528f, 0xb08fb8, 0xffa36b, 0xffb070, 0x2e2440),
    key(6, 0x3d6aa8, 0xb4c0dc, 0xffd09a, 0xffe0a8, 0x363852),
    key(15, 0x3b7cc2, 0x8fbbe2, 0xe6ecef, 0xfff6e6, 0x2e4458),
    key(35, 0x2c72c0, 0x6eaee3, 0xc4e3f4, 0xfffaf0, 0x2a4656),
]

func palette(alt: Float, evening: Bool) -> Palette {
    let keys = evening ? eveningKeys : morningKeys
    if alt <= keys[0].alt { return keys[0].palette }
    for (a, b) in zip(keys, keys.dropFirst()) where alt <= b.alt {
        return .blend(a.palette, b.palette, (alt - a.alt) / (b.alt - a.alt))
    }
    return keys[keys.count - 1].palette
}

/// A layered ridge landscape under a sky. Geometry is fixed per seed; only
/// light changes between frames.
struct Scene {
    struct Layer {
        let base, amp, freq: Float  // ridge line in fractions of height; cycles per height
        let haze: Float             // 0 = land color, 1 = horizon color
        let mist: Float             // valley mist toward the layer's foot
        let ridged: Bool            // sharp peaks instead of rolling hills
        let snow: Bool              // the summit: one massif, snow above a ragged line
        let trees: Float            // pine height in fractions of height; 0 = bare
        let forest: Float           // share of the ridge that is wooded, roughly
    }

    // Far to near: a snowcapped summit, a rocky middle range, then rounded
    // wooded hills. The nearest hill carries the cabin.
    static let layers = [
        Layer(base: 0.600, amp: 0.120, freq: 1.3, haze: 0.66, mist: 0.25, ridged: true, snow: true, trees: 0, forest: 0),
        Layer(base: 0.680, amp: 0.060, freq: 2.2, haze: 0.48, mist: 0.30, ridged: true, snow: false, trees: 0, forest: 0),
        Layer(base: 0.750, amp: 0.060, freq: 1.1, haze: 0.32, mist: 0.30, ridged: false, snow: false, trees: 0.011, forest: 0.55),
        Layer(base: 0.825, amp: 0.055, freq: 0.9, haze: 0.17, mist: 0.24, ridged: false, snow: false, trees: 0.019, forest: 0.6),
        Layer(base: 0.910, amp: 0.045, freq: 0.7, haze: 0.00, mist: 0.12, ridged: false, snow: false, trees: 0.040, forest: 0.65),
    ]
    static let sub = 4  // silhouette samples per pixel column, for clean tree edges

    /// A small house with a porch on the nearest hill; its window lights up
    /// after sunset.
    struct Cabin {
        let x, halfWidth: Float
        let window: (x0: Float, x1: Float, y0: Float, y1: Float)
    }

    let width: Int, height: Int
    private let W: Float, H: Float
    private let horizonY: Float   // where altitude 0 sits
    private let ground: [Float]   // [layer * width + x] terrain line y, trees excluded
    private let top: [Float]      // [(layer * width + x) * sub + s] silhouette y: land and cabin
    private let trees: [UInt8]    // [(layer * height + y) * width + x] coverage of trees and porch, 0…255
    private let snowLine: [Float] // [x] for the snowy layer
    private let snowSlope: [Float] // [x] its slope over ±3% of the height, so shading blends, not splits
    private let cabin: Cabin
    private let flakes: [Float]   // snowflake coverage, full frame
    private let glintPower: [Float] // drops on the wet meadow, full frame
    private let glintHue: [UInt8]   // and the color each catches, 0 = violet … 255 = red
    private let seed: UInt32

    init(width: Int, height: Int, seed: UInt32) {
        self.width = width
        self.height = height
        (W, H) = (Float(width), Float(height))
        horizonY = 0.64 * H

        let (w, h, sub) = (W, H, Self.sub)

        func terrain(_ layer: Layer, _ s: UInt32, _ x: Float) -> Float {
            let u = (x - w / 2) / h * layer.freq
            let shape: Float
            if layer.snow {
                // Ridged multifractal, domain-warped so crests lean, on a slow
                // swell that lifts one massif above the rest.
                let warp = 0.25 * fbm(u * 0.6, octaves: 2, seed: s ^ 0x27d4eb2f)
                shape = 2.4 * ridged(u + warp, octaves: 6, seed: s) - 0.7
                    + 0.6 * fbm(u * 0.35, octaves: 2, seed: s ^ 0x165667b1)
            } else if layer.ridged {
                shape = 0.75 * (0.8 * (1 - 2.4 * abs(fbm(u, octaves: 4, seed: s))) + 0.25 * fbm(u * 7, octaves: 3, seed: s ^ 0x5bd1e995))
            } else {
                shape = 1.5 * fbm(u, octaves: 3, seed: s)  // few octaves: soft, rounded hills
            }
            return (layer.base - layer.amp * shape) * h
        }

        var groundY = [Float](repeating: 0, count: Self.layers.count * width)
        var topY = [Float](repeating: 0, count: Self.layers.count * width * sub)
        var snow = [Float](repeating: 0, count: width)
        var slopes = [Float](repeating: 0, count: width)
        let near = Self.layers.count - 1
        let cabinX = 0.73 * w, cabinHalf = 0.019 * h

        for (l, layer) in Self.layers.enumerated() {
            let s = hash32(seed &* 0x2545f491 &+ UInt32(l))
            let row = l * width
            for x in 0..<width { groundY[row + x] = terrain(layer, s, Float(x) + 0.5) }
            for i in 0..<(width * sub) { topY[row * sub + i] = terrain(layer, s, (Float(i) + 0.5) / Float(sub)) }
            if layer.snow {
                let r = max(Int(0.03 * h), 1)
                for x in 0..<width {
                    snow[x] = (layer.base - layer.amp * 0.42) * h + 0.010 * h * fbm(Float(x) / h * 14, octaves: 3, seed: s ^ 0x7f4a7c15)
                    slopes[x] = (terrain(layer, s, Float(x + r) + 0.5) - terrain(layer, s, Float(x - r) + 0.5)) / Float(2 * r)
                }
            }
        }
        func groundAt(_ l: Int, _ x: Float) -> Float { groundY[l * width + min(max(Int(x), 0), width - 1)] }

        // The cabin: walls, pitched roof, chimney; one window.
        let base = groundAt(near, cabinX) + 0.004 * h
        let (wallH, roofH) = (0.024 * h, 0.020 * h)
        for i in 0..<(width * sub) {
            let dx = abs((Float(i) + 0.5) / Float(sub) - cabinX)
            guard dx <= cabinHalf * 1.08 else { continue }
            var y = base - wallH - roofH + dx / (cabinHalf * 1.08) * roofH
            let cx = (Float(i) + 0.5) / Float(sub) - cabinX
            if cx > 0.36 * cabinHalf && cx < 0.62 * cabinHalf { y = min(y, base - wallH - 0.95 * roofH) }
            topY[(near * width) * sub + i] = min(topY[(near * width) * sub + i], y)
        }

        // What stands on the land and lets the sky through between its parts
        // (trees, the porch) is drawn as 2-D coverage, one plane per layer.
        var cover = [UInt8](repeating: 0, count: Self.layers.count * width * height)

        // The porch, on the right: a lean-to roof on two posts, a railing with
        // balusters, and steps down to the ground.
        let porch0 = cabinX + cabinHalf, porch1 = porch0 + 0.9 * cabinHalf
        let floorY = base - 0.10 * wallH, railY = base - 0.48 * wallH
        let (eaveX, eaveY0, eaveY1) = (porch1 + 0.1 * cabinHalf, base - 0.95 * wallH, base - 0.68 * wallH)
        func eave(_ x: Float) -> Float { eaveY0 + (eaveY1 - eaveY0) * (x - porch0) / (eaveX - porch0) }
        var porch = [
            Capsule(x0: porch0, y0: eaveY0, x1: eaveX, y1: eaveY1, r0: 0.055 * wallH, r1: 0.05 * wallH),
            Capsule(x0: porch0, y0: floorY, x1: porch1, y1: floorY, r0: 0.035 * wallH, r1: 0.035 * wallH),
            Capsule(x0: porch0, y0: railY, x1: porch1, y1: railY, r0: 0.02 * wallH, r1: 0.02 * wallH),
        ]
        for px in [porch0 + 0.5 * (porch1 - porch0), porch1] {
            let post = 0.045 * cabinHalf
            porch.append(Capsule(x0: px, y0: eave(px), x1: px, y1: groundAt(near, px) + 0.002 * h, r0: post, r1: post))
        }
        for k in 1..<6 {
            let bx = porch0 + Float(k) / 6 * (porch1 - porch0)
            porch.append(Capsule(x0: bx, y0: railY, x1: bx, y1: floorY, r0: 0.012 * wallH, r1: 0.012 * wallH))
        }
        let drop = groundAt(near, porch1 + 0.3 * cabinHalf) - floorY
        if drop > 0.08 * wallH {
            for k in 1...2 {
                let sy = floorY + Float(k) / 3 * drop
                porch.append(Capsule(x0: porch1, y0: sy, x1: porch1 + Float(k) * 0.22 * cabinHalf, y1: sy, r0: 0.03 * wallH, r1: 0.03 * wallH))
            }
        }
        stamp(porch, into: &cover, plane: near, width: width, height: height)

        // Spruces in woods and clearings along the ridges, tallest in front.
        for (l, layer) in Self.layers.enumerated() where layer.trees > 0 {
            let s = hash32(seed &* 0x2545f491 &+ UInt32(l))
            var rng = SplitMix(state: UInt64(s) &* 0x9e3779b97f4a7c15 | 1)
            let tallest = layer.trees * h
            var (tx, n): (Float, UInt32) = (-tallest, 0)
            while tx < w + tallest {
                let th = tallest * (0.6 + 0.7 * rng.unit())
                let hw = th * 0.24
                tx += hw * (0.9 + 1.4 * rng.unit())
                n &+= 1
                let wood = fbm(tx / h * 2.2, octaves: 2, seed: s ^ 0x9e3779b9) * 0.5 + 0.5
                if wood > layer.forest { continue }
                if l == near && tx > cabinX - cabinHalf - 2 * hw && tx < porch1 + 0.6 * cabinHalf + 2 * hw { continue }
                let tree = spruce(x: tx, base: terrain(layer, s, tx) + 0.06 * th, height: th,
                                  seed: hash32(s ^ (n &* 0x9e3779b1)), depth: th > 30 ? 2 : 1)
                stamp(tree, into: &cover, plane: l, width: width, height: height)
            }
        }
        // Three tall ones by the cabin, where the branches can be seen.
        for (k, (at, size)) in [(cabinX - 3.0 * cabinHalf, Float(0.105)), (cabinX - 4.9 * cabinHalf, 0.075),
                                (porch1 + 2.4 * cabinHalf, 0.088)].enumerated() {
            let th = size * h
            stamp(spruce(x: at, base: groundAt(near, at) + 0.03 * th, height: th,
                         seed: hash32(seed ^ (UInt32(k + 1) &* 0x85ebca6b)), depth: 2),
                  into: &cover, plane: near, width: width, height: height)
        }

        cabin = Cabin(x: cabinX, halfWidth: cabinHalf,
                      window: (cabinX - 0.55 * cabinHalf, cabinX - 0.15 * cabinHalf,
                               base - 0.72 * wallH, base - 0.38 * wallH))

        ground = groundY
        top = topY
        trees = cover
        snowLine = snow
        snowSlope = slopes

        // Snowflakes: soft dots, the big near ones rarer. Drawn only when it snows.
        let scale = h / 1664
        var flakeCover = [Float](repeating: 0, count: width * height)
        var flakeRng = SplitMix(state: UInt64(seed) &* 0xd1b54a32d192ed03 | 1)
        for _ in 0..<(width * height / 2200) {
            let fx = flakeRng.unit() * w, fy = flakeRng.unit() * h
            let near = powf(flakeRng.unit(), 3)
            let bright = 0.55 + 0.45 * flakeRng.unit()
            let sigma = (0.6 + 1.8 * near) * scale
            let reach = Int((3 * sigma).rounded(.up))
            let (cx, cy) = (Int(fx), Int(fy))
            for py in max(cy - reach, 0)...min(cy + reach, height - 1) {
                for px in max(cx - reach, 0)...min(cx + reach, width - 1) {
                    let dx = Float(px) + 0.5 - fx, dy = Float(py) + 0.5 - fy
                    flakeCover[py * width + px] += bright * expf(-(dx * dx + dy * dy) / (2 * sigma * sigma))
                }
            }
        }
        flakes = flakeCover

        // Glints: drops on the wet meadow, each splitting the low sun into
        // one color. Drawn only after rain.
        var power = [Float](repeating: 0, count: width * height)
        var tints = [UInt8](repeating: 0, count: width * height)
        var glintRng = SplitMix(state: UInt64(seed) &* 0x94d049bb133111eb | 1)
        for _ in 0..<(width * height / 1200) {
            let gx = glintRng.unit() * w, gy = (0.68 + 0.32 * glintRng.unit()) * h
            let tint = glintRng.unit(), mag = powf(glintRng.unit(), 3)
            let (cx, cy) = (Int(gx), Int(gy))
            guard cy < height, gy > groundY[2 * width + min(cx, width - 1)] + 2 else { continue }
            let k = 0.35 + 1.4 * mag
            func put(_ px: Int, _ py: Int, _ v: Float) {
                guard px >= 0, px < width, py >= 0, py < height else { return }
                power[py * width + px] += v
                tints[py * width + px] = UInt8(tint * 255)
            }
            put(cx, cy, k)
            for a in 1...(mag > 0.5 ? Int(2 * scale + 1) : 1) {
                let v = k * 0.4 / Float(a)
                put(cx + a, cy, v); put(cx - a, cy, v); put(cx, cy + a, v); put(cx, cy - a, v)
            }
        }
        glintPower = power
        glintHue = tints
        self.seed = seed
    }

    /// One frame as 8-bit sRGB RGBX, dithered. `salt` varies the dither per
    /// frame. Light follows the stylized `sun`; the moon, planets, stars and
    /// Milky Way stand where `sky` puts them.
    func render(minute: Int, sun: SunModel, sky: Ephemeris, salt: UInt32, weather w: Weather = Weather(.clear)) -> [UInt8] {
        let alt = sun.altitude(minute)
        let dayPhase = sun.dayPhase(minute)
        let evening = dayPhase.map { $0 >= 0.5 } ?? (sun.nightPhase(minute) < 0.5)
        let clear = 1 - w.overcast  // how much of the sky shows

        // The view faces the equator and spans 180° from east to west, so the
        // sun rises on the left north of the equator and on the right south
        // of it. Altitude climbs at the same scale.
        let ppd = W / 180  // pixels per degree
        let viewAz: Float = sky.latitude >= 0 ? 180 : 0, side: Float = sky.latitude >= 0 ? 1 : -1
        let (w2, horizon) = (W / 2, horizonY)
        func screen(_ v: Vec3) -> (x: Float, y: Float, alt: Float) {
            let a = Float(asin(max(-1, min(1, v.z))) * 180 / .pi)
            var daz = Float(atan2(v.x, v.y) * 180 / .pi) - viewAz
            if daz > 180 { daz -= 360 } else if daz <= -180 { daz += 360 }
            return (w2 + daz * ppd, horizon - a * ppd, a)
        }

        // The moon's light turns the night sky blue and brings the snow out.
        let moon = screen(sky.moon), moonLit = Float(sky.moonLit)
        let moonLight = powf(moonLit, 1.5) * smoothstep(-1, 20, moon.alt) * smoothstep(-5, -14, alt) * clear
        var pal = palette(alt: alt, evening: evening)
        if moonLight > 0 { pal = pal.moonlit(moonLight) }
        if w.overcast > 0 { pal = pal.overcast(w.overcast) }
        let span = horizonY - 0.14 * H

        // Sun: rises on its side, sets on the other; below the horizon it
        // waits at its side. Cloud and fog veil its disk and glow.
        let veil = (1 - 0.85 * w.overcast) * (1 - 0.5 * w.fog)
        let p = dayPhase ?? (evening ? 1 : 0)
        let sunX = W * (0.5 + (p - 0.5) * 0.8 * side), sunY = horizonY - alt / sun.peak * span
        let sunR = 0.021 * H
        let sunVis = smoothstep(-1.5, 0.5, alt) * (1 - w.overcast) * (1 - 0.5 * w.fog)
        let sunColor = mix(pal.glow * 1.6, RGB(1, 0.97, 0.9) * 1.4, smoothstep(2, 20, alt))
        let low = smoothstep(-8, -1, alt) * (1 - smoothstep(4, 20, alt))
        let day = smoothstep(0, 15, alt)
        let (gNear, gFar, gBand) = ((0.44 * low + 0.28 * day) * veil, (0.40 * low + 0.10 * day) * veil, 0.30 * low * veil)
        let (rNear, rFar, bandH, bandW) = (0.06 * H, 0.32 * H, 0.07 * H, 0.55 * W)

        // The moon, where it is, lit from where the sun is: pale by day; by
        // night it hides the stars behind it, and earthshine lights its dark
        // side, most in a thin crescent, when the Earth is nearly full in its sky.
        let moonR = 0.013 * H
        let moonVis = (1 - 0.95 * w.overcast) * (1 - 0.5 * w.fog) * smoothstep(-1.5, -0.5, moon.alt)
        let opaque = smoothstep(6, -6, alt)
        let moonGain = 0.3 + 0.7 * opaque
        let haloGain = 0.05 * powf(moonLit, 1.3) * opaque * moonVis
        let earthshine = 0.025 * (1 - moonLit) * (1 - moonLit) * opaque
        let moonColor = RGB(hex: 0xf3efe0), moonGlow = RGB(hex: 0x9fb4d8)
        // Directions on the sky at the moon, as screen x and y (up): its north
        // (the moon's axis is within 1.5° of the ecliptic pole's), and the sun.
        let (maz, mal) = (atan2(sky.moon.x, sky.moon.y), asin(sky.moon.z))
        let right = Vec3(cos(maz), -sin(maz), 0), upward = Vec3(-sin(mal) * sin(maz), -sin(mal) * cos(maz), cos(mal))
        func toward(_ v: Vec3) -> (x: Float, y: Float) {
            let t = v - sky.moon * v.dot(sky.moon)
            let (a, b) = (t.dot(right), t.dot(upward)), n = max((a * a + b * b).squareRoot(), 1e-9)
            return (Float(a / n), Float(b / n))
        }
        let toSun = toward(sky.sun), north = toward(sky.eclipticPole), west = (x: north.y, y: -north.x)
        let phase = Float(sky.moonPhaseAngle * .pi / 180)
        let light = (x: toSun.x * sinf(phase), y: toSun.y * sinf(phase), z: cosf(phase))

        // Stars and planets: as many as the dark, the moon and the air let
        // through. About magnitude 6 at full night; by day, only Venus, faint.
        let limit = -3.5 + 9.5 * clamp01(-alt / 16) - 1.6 * moonLight
        let contrast = 0.25 + 0.75 * smoothstep(-2, -8, alt)
        let skyRows = min(height, Int(horizonY) + 2)
        var starPower = [Float](repeating: 0, count: width * skyRows)
        var starTint = [UInt8](repeating: 0, count: width * skyRows)
        let scale = H / 1664
        /// A point of light as a small Gaussian, its total the same wherever
        /// it falls between pixels: `peak` is its height at `sigma`.
        func splat(_ x: Float, _ y: Float, _ peak: Float, _ sigma: Float, _ bv: Float) {
            let reach = Int((3 * sigma).rounded(.up))
            let (cx, cy) = (Int(floorf(x)), Int(floorf(y)))
            let (x0, x1, y0, y1) = (max(cx - reach, 0), min(cx + reach, width - 1), max(cy - reach, 0), min(cy + reach, skyRows - 1))
            guard x0 <= x1, y0 <= y1 else { return }
            var sum: Float = 0
            for py in y0...y1 {
                for px in x0...x1 {
                    let dx = Float(px) + 0.5 - x, dy = Float(py) + 0.5 - y
                    sum += expf(-(dx * dx + dy * dy) / (2 * sigma * sigma))
                }
            }
            guard sum > 0 else { return }
            let norm = peak * 2 * .pi * sigma * sigma / sum
            let tint = UInt8(clamp01((bv + 0.4) / 2.4) * 255)
            for py in y0...y1 {
                for px in x0...x1 {
                    let dx = Float(px) + 0.5 - x, dy = Float(py) + 0.5 - y
                    let k = expf(-(dx * dx + dy * dy) / (2 * sigma * sigma))
                    starPower[py * width + px] += norm * k
                    if k > 0.3 { starTint[py * width + px] = tint }
                }
            }
        }
        func point(_ v: Vec3, _ magnitude: Float, _ bv: Float) {
            guard v.z > 0 else { return }
            let s = screen(v)
            let m = magnitude + 0.25 * (airmass(s.alt) - 1)  // extinction: 0.25 magnitudes per airmass
            let seen = smoothstep(limit + 0.5, limit - 0.5, m) * clear * contrast
            guard seen > 0, s.x > -8, s.x < W + 8, s.y > -8 else { return }
            let b = powf(10, -0.22 * (m - 1.5))  // brightness, compressed as the eye does
            splat(s.x, s.y, min(0.32 * b, 0.9) * seen, max((0.5 + 0.28 * min(b, 9).squareRoot()) * scale, 0.6), bv)
        }
        if limit > -1.6 { for star in Star.catalog { point(sky.fromJ2000.apply(star.direction), star.magnitude, star.bv) } }
        for planet in sky.planets { point(planet.direction, Float(planet.magnitude), Float(planet.bv)) }
        let starColors = (0..<256).map { starColor(Float($0) / 255 * 2.4 - 0.4) }

        // The Milky Way and the zodiacal light, on a grid of sky directions
        // every 4 px (both are smooth at that scale), bilinear in between.
        let mwSeen = smoothstep(-11, -18, alt) * (1 - 0.85 * moonLight) * clear
        let mwGain = 0.02 * mwSeen
        let zlGain = 0.006 * smoothstep(-13, -19, alt) * (1 - 0.9 * moonLight) * clear
        // Its grain: stars too faint to see one by one, crowding the band.
        if mwSeen > 0 {
            for g in Star.grain {
                let v = sky.fromJ2000.apply(g.direction)
                guard v.z > 0 else { continue }
                let s = screen(v)
                guard s.x > -2, s.x < W + 2, s.y > -2 else { continue }
                splat(s.x, s.y, 0.08 * g.light * mwSeen * powf(10, -0.1 * (airmass(s.alt) - 1)), max(0.5 * scale, 0.6), g.bv)
            }
        }
        let gs = 4, gw = width / gs + 2, gh = skyRows / gs + 2
        var glowGrid = [Float](repeating: 0, count: mwGain + zlGain > 0 ? gw * gh * 3 : 0)
        if !glowGrid.isEmpty {
            let (toGalactic, toEcliptic, sunLon) = (sky.toGalactic, sky.toEcliptic, Float(sky.sunLongitude))
            let mwCool = RGB(hex: 0xc4d0ff), mwWarm = RGB(hex: 0xffe3c4), zlColor = RGB(hex: 0xfff0dc)
            glowGrid.withUnsafeMutableBufferPointer { buf in
                let g = buf.baseAddress!
                DispatchQueue.concurrentPerform(iterations: gh) { j in
                    for i in 0..<gw {
                        let a = (horizon - Float(j * gs)) / ppd
                        guard a > -1 else { continue }
                        let al = Double(min(a, 90)) * .pi / 180, az = Double(viewAz + (Float(i * gs) - w2) / ppd) * .pi / 180
                        let v = Vec3(cos(al) * sin(az), cos(al) * cos(az), sin(al))
                        let fade = powf(10, -0.1 * (airmass(a) - 1))
                        var c = RGB(0, 0, 0)
                        if mwGain > 0 {
                            let gal = toGalactic.apply(v)
                            let (mw, warm) = milkyWay(Float(gal.lon), Float(gal.lat))
                            c = mix(mwCool, mwWarm, warm) * (mw * mwGain * fade)
                        }
                        if zlGain > 0 {
                            let e = toEcliptic.apply(v)
                            var dl = abs(Float(e.lon) - sunLon)
                            if dl > 180 { dl = 360 - dl }
                            c = c + zlColor * (zodiacal(dl, Float(e.lat)) * zlGain * fade)
                        }
                        let o = (j * gw + i) * 3
                        (g[o], g[o + 1], g[o + 2]) = (c.r, c.g, c.b)
                    }
                }
            }
        }

        // Weather. Clouds: wide, flat shapes from 2-D noise, thinning into the
        // distance, lit on the side toward the sun (pink-edged at sunset). They
        // drift through the day. Under overcast they close into a soft deck.
        let cloudLit = mixOklab(pal.horizon, pal.glow, 0.5) * 1.15
        let cloudShade = desaturate(mixOklab(pal.mid, pal.zenith, 0.5), 0.5) * 0.85
        let cloudEdge = 0.62 - 0.3 * w.clouds - 0.25 * w.overcast, cloudSoft = 0.12 + 0.3 * w.overcast
        let (cloudStep, cloudSeed, drift) = (0.02 * H, hash32(seed ^ 0x51ed270b), Float(minute) * 0.002)
        let h = H
        func cloud(_ x: Float, _ y: Float) -> Float {
            let n = fbm2(x / h * 1.6 + drift, y / h * 5.5, octaves: 5, seed: cloudSeed) * 0.5 + 0.5
            return smoothstep(cloudEdge, cloudEdge + cloudSoft, n) * (1 - smoothstep(horizon * 0.75, horizon * 1.02, y))
        }
        let fogColor = mixOklab(pal.horizon, desaturate(pal.mid, 0.6), 0.4)
        let flakeColor = mixOklab(pal.mid, RGB(1, 1, 1), 0.6)
        let snowGround = mixOklab(pal.mid, pal.horizon, 0.5) * 1.15

        // The sea of clouds, seen from above, just below the far ranges. Its
        // top is rounded humps with creases between (|noise|, as cumulus tops
        // go); inside, billows shrink toward the horizon, each lit on top and
        // shaded beneath; a faint haze of light hangs over it.
        let seaLit = mixOklab(pal.horizon, pal.glow, 0.5) * 1.3
        let seaShade = mixOklab(pal.mid, pal.horizon, 0.5) * 0.8
        let seaSeed = hash32(seed ^ 0x6a09e667)
        let seaTop: [Float] = w.sea > 0 ? (0..<width).map { x in
            let u = (Float(x) + 0.5) / h
            return (0.716 - 0.03 * abs(fbm(u * 3 + drift, octaves: 3, seed: seaSeed))
                    - 0.008 * abs(fbm(u * 11 + drift, octaves: 2, seed: seaSeed ^ 0x9e3779b9))) * h
        } : []
        // Fog lakes at the feet of the hills, bright under a clear sky.
        let valleyColor = mixOklab(pal.horizon, pal.mid, 0.2) * 1.12

        // After rain. The rainbow stands opposite the sun: from this view,
        // which faces the sun's path, it rises at the far edge, and sinks as
        // the sun climbs, gone above 42°. Glints wherever the sun is up.
        let bowGain = 0.38 * w.wet * smoothstep(-0.5, 3, alt) * (1 - smoothstep(30, 41, alt))
        let bowR = 0.78 * H
        let bowX = sunX > 0.5 * W ? -0.22 * W : 1.22 * W
        let bowY = horizonY + (0.12 + 0.5 * clamp01(alt / 42)) * H
        let glintGain = w.wet * smoothstep(-2, 4, alt) * (0.6 + 0.4 * (1 - smoothstep(10, 35, alt)))
        let hues: [RGB] = w.wet > 0 ? (0..<256).map { spectrum(Float($0) / 255) } : []
        let gradient: [RGB] = (0..<height).map { y in
            let s = clamp01((Float(y) + 0.5) / horizonY)
            return s < 0.55 ? mixOklab(pal.zenith, pal.mid, s / 0.55)
                            : mixOklab(pal.mid, pal.horizon, powf((s - 0.55) / 0.45, 1.4))
        }
        let fog = pal.horizon
        let tones = Self.layers.map { mixOklab(pal.land, fog, $0.haze) }
        let layerCount = Self.layers.count, mistDepth = 0.10 * H, sub = Self.sub

        // Snow takes the sky's light: white-blue by day, alpenglow pink at
        // sunrise and sunset, dim blue at night. Faces toward the sun are
        // brighter while it is up.
        let snowLight = mixOklab(pal.mid, pal.glow, 0.5) * 1.25
        let relief = 0.35 * smoothstep(-6, 3, alt)
        let windowLight = smoothstep(-0.5, -5, alt)
        let windowColor = RGB(hex: 0xffb35c) * 1.3
        let (wx0, wx1, wy0, wy1) = cabin.window
        let (windowX, windowY) = ((wx0 + wx1) / 2, (wy0 + wy1) / 2)

        var out = [UInt8](repeating: 255, count: width * height * 4)
        out.withUnsafeMutableBufferPointer { buf in
            let px = buf.baseAddress!
            DispatchQueue.concurrentPerform(iterations: height) { y in
                let fy = Float(y) + 0.5
                for x in 0..<width {
                    let fx = Float(x) + 0.5
                    let dx = fx - sunX, dy = fy - sunY
                    let d = (dx * dx + dy * dy).squareRoot()
                    let g = gNear * expf(-d / rNear) + gFar * expf(-d / rFar)
                        + gBand * expf(-abs(fy - horizonY) / bandH) * expf(-abs(dx) / bandW)
                    var c = gradient[y] + pal.glow * g
                    let air = c                                        // sky without stars
                    if y < skyRows {
                        if !glowGrid.isEmpty {
                            let u = fx / Float(gs), v = fy / Float(gs)
                            let (i0, j0) = (Int(u), Int(v))
                            let (fu, fv) = (u - Float(i0), v - Float(j0))
                            let o = (j0 * gw + i0) * 3, o2 = o + gw * 3
                            func at(_ k: Int) -> Float {
                                lerp(lerp(glowGrid[o + k], glowGrid[o + 3 + k], fu), lerp(glowGrid[o2 + k], glowGrid[o2 + 3 + k], fu), fv)
                            }
                            c = c + RGB(at(0), at(1), at(2))
                        }
                        let s = starPower[y * width + x]
                        if s > 0 { c = c + starColors[Int(starTint[y * width + x])] * s }
                    }
                    if sunVis > 0 {
                        let cov = clamp01(sunR - d + 0.5) * sunVis
                        if cov > 0 { c = mix(c, sunColor, cov) }
                    }
                    if moonVis > 0 {
                        let mx = fx - moon.x, my = fy - moon.y
                        let md = (mx * mx + my * my).squareRoot()
                        let halo = moonGlow * (haloGain * expf(-md / (0.05 * H)))
                        c = c + halo
                        let disk = clamp01(moonR - md + 0.5) * moonVis
                        if disk > 0 {
                            // A sphere lit by the sun, flat to its rim as the real
                            // moon is (Lommel–Seeliger), with its maria.
                            let dx = mx / moonR, dy = -my / moonR
                            let z = max(1 - dx * dx - dy * dy, 0).squareRoot()
                            let mu = max(dx * light.x + dy * light.y + z * light.z, 0)
                            let lit = 2 * mu / (mu + max(z, 0.25))  // the floor keeps the rim from flaring
                            let albedo = moonAlbedo(dx * west.x + dy * west.y, dx * north.x + dy * north.y)
                            c = mix(c, air + halo, disk * opaque) + moonColor * (albedo * (lit * moonGain + earthshine) * disk)
                        }
                    }
                    if w.clouds > 0 && fy < horizonY * 1.02 {
                        let d = cloud(fx, fy)
                        if d > 0 {
                            let (lx, ly) = (sunX - fx, sunY - fy)
                            let len = max((lx * lx + ly * ly).squareRoot(), 1)
                            let ahead = cloud(fx + lx / len * cloudStep, fy + ly / len * cloudStep)
                            let light = clamp01(0.55 + 1.8 * (d - ahead))
                            c = mix(c, mix(cloudShade, cloudLit, light) + pal.glow * (g * 0.6), d * 0.96)
                        }
                    }
                    if w.fog > 0 {
                        c = mix(c, fogColor, w.fog * 0.6 * smoothstep(0.3 * H, horizonY, fy))
                    }

                    var frontTree: Float = 0  // how much of this pixel is tree or porch, in front
                    for l in 0..<layerCount {
                        if l == layerCount - 1 && w.sea > 0 {
                            // The sea of clouds, over everything but the cabin's hill.
                            let above = seaTop[x] - fy
                            if above > 0 {
                                c = c + seaLit * (0.08 * w.sea * expf(-above / (0.012 * H)))
                            }
                            let cov = clamp01(-above / 4 + 0.5) * w.sea
                            if cov > 0 {
                                let depth = clamp01(-above / (0.28 * H))
                                let k = 1.8 - depth  // billows grow toward the viewer
                                let (u, v) = (fx / H * 6 * k + drift, fy / H * 13 * k)
                                let n = fbm2(u, v, octaves: 3, seed: seaSeed)
                                let up = fbm2(u, v - 0.18, octaves: 3, seed: seaSeed)
                                let puff = smoothstep(-0.25, 0.3, n)        // lumps, with creases between
                                let lit = clamp01(0.5 + 2.2 * (n - up))     // thinner above: a lit top
                                let light = clamp01(0.98 - 0.45 * depth) * (0.45 + 0.3 * puff + 0.3 * lit)
                                c = mix(c, mix(seaShade, seaLit, light) + pal.glow * (g * 0.7), cov)
                            }
                        }
                        let t0 = (l * width + x) * sub
                        var land: Float = 0
                        for s in 0..<sub { land += clamp01(fy - top[t0 + s] + 0.5) }
                        land /= Float(sub)
                        let tree = Float(trees[(l * height + y) * width + x]) / 255
                        let cov = max(land, tree)
                        if cov == 0 { continue }
                        let layer = Self.layers[l]
                        let gy = ground[l * width + x]
                        var tone = mix(tones[l], fog, layer.mist * smoothstep(0, mistDepth, fy - gy))
                        if tree > 0 { tone = tone * (1 - 0.18 * (1 - layer.haze) * tree) }  // spruce darker than meadow
                        if layer.snow {
                            let amount = smoothstep(snowLine[x] + 3, snowLine[x] - 3, fy)
                            if amount > 0 {
                                // Snow faces turned to the sun are brighter: the face
                                // normal against the direction to the sun.
                                let slope = snowSlope[x]
                                let (lx, ly) = (sunX - fx, sunY - fy)
                                let facing = (slope * lx - ly) / ((1 + slope * slope) * (lx * lx + ly * ly)).squareRoot()
                                let snow = mix(snowLight * (1 + relief * (clamp01(facing) - 0.5) * 2), fog, layer.haze * 0.55)
                                tone = mix(tone, snow, amount)
                            }
                        }
                        if w.snow > 0 && !layer.snow && fy >= gy {
                            // Fresh snow on open ground; the trees stay dark.
                            tone = mix(tone, mix(snowGround, fog, layer.haze * 0.5), 0.75 * w.snow * (1 - tree))
                        }
                        if w.fog > 0 {
                            tone = mix(tone, fogColor, w.fog * (0.9 - 0.12 * Float(l)))
                        }
                        if w.valley > 0 {
                            // Fog lakes: each hill's foot sinks into bright fog; least in front.
                            let lake = smoothstep(0.004 * H, 0.05 * H, fy - gy) * (l == layerCount - 1 ? 0.35 : l == 0 ? 0.6 : 0.9)
                            tone = mix(tone, valleyColor, w.valley * lake * (1 - 0.5 * tree))
                        }
                        tone = tone + pal.glow * (g * layer.haze * 0.8)   // in-scattered sun
                        c = cov == 1 ? tone : mix(c, tone, cov)
                        frontTree = frontTree * (1 - cov) + tree
                    }

                    if bowGain > 0 {
                        // Rainbow light, added: violet inside, red outside; the second
                        // bow beyond, colors reversed; brighter sky inside the first,
                        // Alexander's dark band between. It fades into the near hills.
                        let d = ((fx - bowX) * (fx - bowX) + (fy - bowY) * (fy - bowY)).squareRoot()
                        let fade = 1 - smoothstep(horizonY + 0.05 * H, horizonY + 0.32 * H, fy)
                        let bw = 0.05 * bowR, r2 = 1.21 * bowR, bw2 = 0.07 * bowR
                        let u = (d - (bowR - bw)) / (2 * bw), u2 = (d - (r2 - bw2)) / (2 * bw2)
                        if u > 0 && u < 1 { c = c + hues[min(Int(u * 255), 255)] * (bowGain * powf(sinf(.pi * u), 0.8) * fade) }
                        if u2 > 0 && u2 < 1 { c = c + hues[min(Int((1 - u2) * 255), 255)] * (0.38 * bowGain * powf(sinf(.pi * u2), 0.8) * fade) }
                        if d < bowR - bw { c = c * (1 + 0.18 * bowGain * fade) }
                        else if d > bowR + bw && d < r2 - bw2 { c = c * (1 - 0.2 * bowGain * fade) }
                    }
                    if glintGain > 0 {
                        // On open ground only: not on the trees or the porch.
                        let p = glintPower[y * width + x] * (1 - min(frontTree, 1))
                        if p > 0 { c = c + hues[Int(glintHue[y * width + x])] * (p * glintGain) }
                    }

                    if windowLight > 0 {
                        let inside = clamp01(min(min(fx - wx0, wx1 - fx), min(fy - wy0, wy1 - fy)) + 0.5)
                        c = mix(c, windowColor, inside * windowLight)
                        let wdx = fx - windowX, wdy = fy - windowY
                        c = c + windowColor * (0.08 * windowLight * expf(-(wdx * wdx + wdy * wdy).squareRoot() / (0.012 * H)))
                    }

                    if w.snow > 0 {
                        let f = flakes[y * width + x]
                        if f > 0.002 { c = mix(c, flakeColor, min(f * w.snow, 1)) }
                    }

                    let o = (y * width + x) * 4
                    let h = UInt32(truncatingIfNeeded: (y &* width &+ x) &* 3) ^ salt
                    px[o] = quantize(c.r, h)
                    px[o + 1] = quantize(c.g, h &+ 1)
                    px[o + 2] = quantize(c.b, h &+ 2)
                }
            }
        }
        return out
    }
}

/// A thick line that tapers from `r0` to `r1`: a trunk, branch or plank.
struct Capsule {
    let x0, y0, x1, y1, r0, r1: Float
}

/// A spruce as capsules. A tapering trunk carries 21 whorls (a Fibonacci
/// number) up a cone, alternately 5 and 3 branches each, every branch turned
/// by the golden angle from the one before, so its sideways reach (the
/// cosine of that turn) varies the way phyllotaxis spaces real branches.
/// Each branch rises near the top and droops near the foot, bends down
/// toward its tip, and carries smaller copies of itself 0.382 (1/φ²) as
/// long, `depth` levels deep.
func spruce(x: Float, base: Float, height th: Float, seed: UInt32, depth maxDepth: Int) -> [Capsule] {
    var caps: [Capsule] = []
    var rng = SplitMix(state: UInt64(seed) &* 0x9e3779b97f4a7c15 | 1)
    let golden: Float = 2.399963  // 137.5° in radians

    func branch(_ x: Float, _ y: Float, _ length: Float, _ dir: Float, _ angle: Float, _ r: Float, _ depth: Int) {
        var (px, py, a) = (x, y, angle)
        for s in 0..<3 {
            let len = length / 3
            let nx = px + dir * cosf(a) * len, ny = py + sinf(a) * len
            let r0 = r * (1 - 0.2 * Float(s)), r1 = r * (1 - 0.2 * Float(s + 1))
            caps.append(Capsule(x0: px, y0: py, x1: nx, y1: ny, r0: r0, r1: r1))
            if depth < maxDepth {
                let side: Float = s % 2 == 0 ? -1 : 1  // twigs alternate up and down
                branch((px + nx) / 2, (py + ny) / 2, length * 0.382 * (1 - 0.25 * Float(s)), dir,
                       a + side * 0.75 + 0.15, r0 * 0.7, depth + 1)
            }
            (px, py) = (nx, ny)
            a += 0.22 + 0.06 * rng.unit()
        }
    }

    let top = base - th
    caps.append(Capsule(x0: x, y0: base, x1: x, y1: top + 0.05 * th, r0: 0.02 * th, r1: 0.005 * th))
    for k in 0..<21 {
        let t = (Float(k) + 0.5) / 21  // up the trunk
        let y = base - th * (0.10 + 0.86 * t)
        let reach = th * (0.03 + 0.24 * powf(1 - t, 0.95)) * (0.85 + 0.3 * rng.unit())
        for j in 0..<(k % 2 == 0 ? 5 : 3) {
            let turn = Float(k * 8 + j) * golden + 0.3 * rng.unit()
            let side = cosf(turn)
            branch(x, y, reach * (0.3 + 0.7 * abs(side)), side < 0 ? -1 : 1, -0.35 + 0.6 * (1 - t),
                   0.026 * th * (1 - 0.6 * t), 0)
        }
    }
    caps.append(Capsule(x0: x, y0: top + 0.08 * th, x1: x, y1: top, r0: 0.006 * th, r1: 0.002 * th))  // leader
    return caps
}

/// Antialiased coverage of capsules, kept as the maximum per pixel, into one
/// layer's plane of `cover`.
func stamp(_ caps: [Capsule], into cover: inout [UInt8], plane: Int, width: Int, height: Int) {
    let offset = plane * width * height
    for c in caps {
        let r = max(c.r0, c.r1)
        let x0 = max(Int(floorf(min(c.x0, c.x1) - r - 1)), 0), x1 = min(Int(ceilf(max(c.x0, c.x1) + r + 1)), width - 1)
        let y0 = max(Int(floorf(min(c.y0, c.y1) - r - 1)), 0), y1 = min(Int(ceilf(max(c.y0, c.y1) + r + 1)), height - 1)
        guard x0 <= x1, y0 <= y1 else { continue }
        let dx = c.x1 - c.x0, dy = c.y1 - c.y0, len2 = dx * dx + dy * dy
        for py in y0...y1 {
            for px in x0...x1 {
                let fx = Float(px) + 0.5 - c.x0, fy = Float(py) + 0.5 - c.y0
                let t = len2 > 0 ? clamp01((fx * dx + fy * dy) / len2) : 0
                let ex = fx - t * dx, ey = fy - t * dy
                let cov = clamp01(c.r0 + (c.r1 - c.r0) * t - (ex * ex + ey * ey).squareRoot() + 0.5)
                let v = UInt8((cov * 255).rounded())
                let i = offset + py * width + px
                if v > cover[i] { cover[i] = v }
            }
        }
    }
}

/// Linear → sRGB 8-bit with a soft highlight shoulder and ±1 LSB triangular
/// dither, so slow gradients do not band on an 8-bit panel.
@inline(__always) private func quantize(_ v: Float, _ h: UInt32) -> UInt8 {
    let x = max(v, 0)
    let shoulder = x < 0.8 ? x : 0.8 + 0.2 * (1 - expf(-(x - 0.8) / 0.2))
    let a = hash32(h), b = hash32(a ^ 0x68bc21eb)
    let s = linearToSrgb(shoulder) * 255 + unit(a) + unit(b) - 1
    return UInt8(min(max(s.rounded(), 0), 255))
}
