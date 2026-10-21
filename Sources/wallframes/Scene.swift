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
    }

    static let layers = [
        Layer(base: 0.610, amp: 0.085, freq: 1.9, haze: 0.72, mist: 0.25, ridged: true),
        Layer(base: 0.672, amp: 0.075, freq: 1.5, haze: 0.52, mist: 0.30, ridged: true),
        Layer(base: 0.740, amp: 0.065, freq: 1.2, haze: 0.34, mist: 0.30, ridged: false),
        Layer(base: 0.815, amp: 0.065, freq: 0.95, haze: 0.18, mist: 0.24, ridged: false),
        Layer(base: 0.905, amp: 0.055, freq: 0.75, haze: 0.00, mist: 0.12, ridged: false),
    ]

    let width: Int, height: Int
    private let W: Float, H: Float
    private let horizonY: Float  // where altitude 0 sits
    private let ridge: [Float]   // [layer * width + x] ridge-line y
    private let edge: [Float]    // [layer * width + x] 1/√(1+slope²), for antialiasing
    private let stars: [Float]   // linear RGB, full frame

    init(width: Int, height: Int, seed: UInt32) {
        self.width = width
        self.height = height
        (W, H) = (Float(width), Float(height))
        horizonY = 0.64 * H

        let (w, h, horizon) = (W, H, horizonY)

        var ridgeY = [Float](repeating: 0, count: Self.layers.count * width)
        var edgeK = ridgeY
        for (l, layer) in Self.layers.enumerated() {
            let s = hash32(seed &* 0x2545f491 &+ UInt32(l))
            func y(_ x: Float) -> Float {
                let u = (x - w / 2) / h * layer.freq
                let shape = layer.ridged
                    ? 0.8 * (1 - 2.4 * abs(fbm(u, octaves: 4, seed: s))) + 0.25 * fbm(u * 7, octaves: 3, seed: s ^ 0x5bd1e995)
                    : 1.5 * fbm(u, octaves: 5, seed: s)
                return (layer.base - layer.amp * shape) * h
            }
            for x in 0..<width {
                let fx = Float(x) + 0.5
                let slope = (y(fx + 1) - y(fx - 1)) / 2
                ridgeY[l * width + x] = y(fx)
                edgeK[l * width + x] = 1 / (1 + slope * slope).squareRoot()
            }
        }
        ridge = ridgeY
        edge = edgeK

        // Stars: mostly faint, a few bright, thinning toward the horizon.
        var starLight = [Float](repeating: 0, count: width * height * 3)
        var rng = SplitMix(state: UInt64(seed) &* 0x9e3779b97f4a7c15)
        let scale = h / 1664
        for _ in 0..<(width * height / 4500) {
            let sx = rng.unit() * w
            let sy = powf(rng.unit(), 1.3) * horizon * 0.98
            let mag = powf(rng.unit(), 4)
            let tint = mix(RGB(hex: 0xc9d6ff), RGB(hex: 0xfff1d6), rng.unit())
                * ((0.05 + 0.9 * mag) * smoothstep(horizon, horizon * 0.55, sy))
            let sigma = (0.55 + 0.9 * mag) * scale
            let reach = Int((3 * sigma).rounded(.up))
            let (cx, cy) = (Int(sx), Int(sy))
            for py in max(cy - reach, 0)...min(cy + reach, height - 1) {
                for px in max(cx - reach, 0)...min(cx + reach, width - 1) {
                    let dx = Float(px) + 0.5 - sx, dy = Float(py) + 0.5 - sy
                    let k = expf(-(dx * dx + dy * dy) / (2 * sigma * sigma))
                    let i = (py * width + px) * 3
                    starLight[i] += tint.r * k
                    starLight[i + 1] += tint.g * k
                    starLight[i + 2] += tint.b * k
                }
            }
        }
        stars = starLight
    }

    /// One frame as 8-bit sRGB RGBX, dithered. `salt` varies the dither per frame.
    func render(minute: Int, sun: SunModel, salt: UInt32) -> [UInt8] {
        let alt = sun.altitude(minute)
        let dayPhase = sun.dayPhase(minute)
        let evening = dayPhase.map { $0 >= 0.5 } ?? (sun.nightPhase(minute) < 0.5)
        let pal = palette(alt: alt, evening: evening)
        let span = horizonY - 0.14 * H

        // Sun: rises left, sets right; below the horizon it waits at its side.
        let p = dayPhase ?? (evening ? 1 : 0)
        let sunX = W * (0.5 + (p - 0.5) * 0.8), sunY = horizonY - alt / sun.peak * span
        let sunR = 0.021 * H
        let sunVis = smoothstep(-1.5, 0.5, alt)
        let sunColor = mix(pal.glow * 1.6, RGB(1, 0.97, 0.9) * 1.4, smoothstep(2, 20, alt))
        let low = smoothstep(-8, -1, alt) * (1 - smoothstep(4, 20, alt))
        let day = smoothstep(0, 15, alt)
        let (gNear, gFar, gBand) = (0.44 * low + 0.28 * day, 0.40 * low + 0.10 * day, 0.30 * low)
        let (rNear, rFar, bandH, bandW) = (0.06 * H, 0.32 * H, 0.07 * H, 0.55 * W)

        // Moon: crosses the night the same way, a fat crescent.
        let q = min(sun.nightPhase(minute), 1)
        let moonVis = dayPhase == nil ? smoothstep(-1, -8, alt) : 0
        let moonX = W * (0.5 + (q - 0.5) * 0.8), moonY = horizonY - 30 * sinf(.pi * q) / sun.peak * span
        let moonR = 0.017 * H
        let moonColor = RGB(hex: 0xf3efe0), moonGlow = RGB(hex: 0x9fb4d8)

        let starVis = smoothstep(-4, -14, alt)
        let sky: [RGB] = (0..<height).map { y in
            let s = clamp01((Float(y) + 0.5) / horizonY)
            return s < 0.55 ? mixOklab(pal.zenith, pal.mid, s / 0.55)
                            : mixOklab(pal.mid, pal.horizon, powf((s - 0.55) / 0.45, 1.4))
        }
        let fog = pal.horizon
        let tones = Self.layers.map { mixOklab(pal.land, fog, $0.haze) }
        let layerCount = Self.layers.count, mistDepth = 0.10 * H

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
                    var c = sky[y] + pal.glow * g
                    let air = c                                        // sky without stars
                    if starVis > 0 {
                        let i = (y * width + x) * 3
                        c = c + RGB(stars[i], stars[i + 1], stars[i + 2]) * starVis
                    }
                    if sunVis > 0 {
                        let cov = clamp01(sunR - d + 0.5) * sunVis
                        if cov > 0 { c = mix(c, sunColor, cov) }
                    }
                    if moonVis > 0 {
                        let mx = fx - moonX, my = fy - moonY
                        let md = (mx * mx + my * my).squareRoot()
                        let halo = moonGlow * (0.05 * moonVis * expf(-md / (0.05 * H)))
                        c = c + halo
                        let disk = clamp01(moonR - md + 0.5) * moonVis
                        if disk > 0 {
                            let sx = mx - 0.45 * moonR, sy = my + 0.2 * moonR
                            let shadow = clamp01(0.95 * moonR - (sx * sx + sy * sy).squareRoot() + 0.5)
                            c = mix(c, air + halo + moonColor * 0.004, disk)  // earthshine; hides stars
                            c = mix(c, moonColor, disk * (1 - shadow))
                        }
                    }

                    for l in 0..<layerCount {
                        let ry = ridge[l * width + x]
                        let cov = clamp01((fy - ry) * edge[l * width + x] + 0.5)
                        if cov == 0 { continue }
                        let layer = Self.layers[l]
                        var tone = mix(tones[l], fog, layer.mist * smoothstep(0, mistDepth, fy - ry))
                        tone = tone + pal.glow * (g * layer.haze * 0.8)   // in-scattered sun
                        c = cov == 1 ? tone : mix(c, tone, cov)
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

/// Linear → sRGB 8-bit with a soft highlight shoulder and ±1 LSB triangular
/// dither, so slow gradients do not band on an 8-bit panel.
@inline(__always) private func quantize(_ v: Float, _ h: UInt32) -> UInt8 {
    let x = max(v, 0)
    let shoulder = x < 0.8 ? x : 0.8 + 0.2 * (1 - expf(-(x - 0.8) / 0.2))
    let a = hash32(h), b = hash32(a ^ 0x68bc21eb)
    let s = linearToSrgb(shoulder) * 255 + unit(a) + unit(b) - 1
    return UInt8(min(max(s.rounded(), 0), 255))
}
