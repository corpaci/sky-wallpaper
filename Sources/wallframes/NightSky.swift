import Foundation

// What the night sky looks like, given where things are (Astronomy.swift).

/// Air the light crosses, in zenith thicknesses (Rozenberg's fit): 1
/// overhead, about 10 at 5°, 40 at the horizon.
func airmass(_ alt: Float) -> Float {
    let s = sinf(max(alt, 0) * .pi / 180)
    return 1 / (s + 0.025 * expf(-11 * s))
}

private let starStops: [(bv: Float, hex: UInt32)] = [
    (-0.33, 0x9bb0ff), (-0.15, 0xaabfff), (0, 0xcad7ff), (0.4, 0xf8f7ff),
    (0.65, 0xfff4ea), (1.05, 0xffd2a1), (1.6, 0xffcc6f),
]

/// A star's color from its B−V index, after Mitchell Charity's colors by
/// spectral class: a little more saturated than the eye sees it, at unit
/// luminance, so color never changes brightness.
func starColor(_ bv: Float) -> RGB {
    let b = min(max(bv, starStops[0].bv), starStops[starStops.count - 1].bv)
    var i = 0
    while i < starStops.count - 2 && b > starStops[i + 1].bv { i += 1 }
    let (s0, s1) = (starStops[i], starStops[i + 1])
    let c = mixOklab(RGB(hex: s0.hex), RGB(hex: s1.hex), (b - s0.bv) / (s1.bv - s0.bv))
    let y = 0.2126 * c.r + 0.7152 * c.g + 0.0722 * c.b
    let vivid = mix(RGB(y, y, y), c, 1.6)
    return RGB(max(vivid.r, 0), max(vivid.g, 0), max(vivid.b, 0)) * (1 / y)
}

/// The Milky Way's glow at galactic longitude `l` (−180…180°) and latitude
/// `b`: a band widest and brightest toward the center in Sagittarius, star
/// clouds along it, and dust: the Great Rift from Cygnus down to
/// Sagittarius, the Coalsack, fine lanes. Returns brightness, about 0…1.5,
/// and the share of it that is the bulge's warmer light.
func milkyWay(_ l: Float, _ b: Float) -> (Float, Float) {
    guard abs(b) < 40 else { return (0, 0) }
    func sq(_ x: Float) -> Float { x * x }
    func noise(_ k: Float, _ seed: UInt32) -> Float {  // seamless across l = ±180°
        let a = fbm2(l / k, b / k, octaves: 4, seed: seed)
        guard l > 150 else { return a }
        return lerp(a, fbm2((l - 360) / k, b / k, octaves: 4, seed: seed), smoothstep(150, 180, l))
    }
    let toward = 0.5 + 0.5 * cosf(l * .pi / 180)  // 1 toward the center, 0 away
    let along = 0.22 + 0.55 * toward * toward
        + 0.35 * expf(-sq((l - 75) / 16))   // Cygnus
        + 0.30 * expf(-sq((l + 72) / 22))   // Carina and Crux
        + 0.12 * expf(-sq((l - 135) / 30))  // Cassiopeia and Perseus
    let clouds = 0.5 + 0.5 * noise(7, 0x2f6b9d1e)
    let disk = along * expf(-sq(b / (4.5 + 4 * toward)) / 2) * (0.55 + 0.9 * clouds)
    let bulge = 0.8 * expf(-sq(l / 13) - sq(b / 9)) * (0.7 + 0.6 * clouds)
    let lanes = 0.5 + 0.5 * noise(2.5, 0x5a1c3e77)
    let rift = smoothstep(95, 72, l) * smoothstep(-30, -8, l)
        * expf(-sq((b - 1 - 3 * smoothstep(40, 0, l)) / (1.6 + 1.2 * lanes)))
    let coalsack = expf(-(sq(l + 59.5) + sq(b + 0.5)) / 10)
    let dust = clamp01(0.6 * rift * (0.6 + 0.6 * lanes) + 0.7 * coalsack
                       + 0.3 * smoothstep(0.62, 0.85, lanes) * expf(-sq(b / 5)))
    let total = disk + bulge
    return (total * (1 - dust), bulge / max(total, 1e-6))
}

/// The zodiacal light: sunlight on dust in the planets' plane, a soft cone
/// along the ecliptic, brighter toward the sun. `dl` is the angle from the
/// sun along the ecliptic, `beta` the ecliptic latitude, in degrees.
func zodiacal(_ dl: Float, _ beta: Float) -> Float {
    let e = max(dl, 20), width = 8 + 0.15 * e
    return powf(30 / e, 1.5) * expf(-(beta / width) * (beta / width))
}

// The near side's great maria and two bright craters, in the moon's own
// frame: x toward Mare Crisium (west in our sky), y north, both −1…1.
private let maria: [(x: Float, y: Float, rx: Float, ry: Float, k: Float)] = [
    (-0.68, 0.30, 0.34, 0.42, 0.30),   // Oceanus Procellarum
    (-0.62, -0.02, 0.29, 0.29, 0.28),
    (-0.80, 0.55, 0.20, 0.16, 0.26),
    (-0.27, 0.52, 0.34, 0.29, 0.32),   // Imbrium
    (-0.05, 0.80, 0.52, 0.08, 0.26),   // Frigoris
    (0.25, 0.44, 0.21, 0.20, 0.32),    // Serenitatis
    (0.45, 0.14, 0.25, 0.21, 0.32),    // Tranquillitatis
    (0.79, 0.28, 0.09, 0.13, 0.34),    // Crisium
    (0.66, -0.13, 0.16, 0.20, 0.28),   // Fecunditatis
    (0.52, -0.27, 0.10, 0.10, 0.26),   // Nectaris
    (-0.22, -0.36, 0.23, 0.17, 0.26),  // Nubium
    (-0.55, -0.41, 0.12, 0.12, 0.28),  // Humorum
    (-0.35, -0.08, 0.22, 0.18, 0.24),  // Insularum, Cognitum
    (0.05, 0.22, 0.12, 0.09, 0.24),    // Vaporum
]
private let craters: [(x: Float, y: Float, r: Float, k: Float)] = [
    (-0.14, -0.69, 0.035, 0.35),  // Tycho
    (-0.33, 0.17, 0.025, 0.20),   // Copernicus
]

/// How bright the moon's surface is at (x, y), relative to the highlands.
func moonAlbedo(_ x: Float, _ y: Float) -> Float {
    var dark: Float = 0, bright: Float = 0
    let edge = fbm2(x * 4, y * 4, octaves: 2, seed: 0x1b873593)  // ragged shores
    for m in maria {
        let u = (x - m.x) / m.rx, v = (y - m.y) / m.ry
        dark = max(dark, m.k * (1 - smoothstep(0.6, 1.2, (u * u + v * v).squareRoot() + 0.3 * edge)))
    }
    for c in craters {
        let r2 = ((x - c.x) * (x - c.x) + (y - c.y) * (y - c.y)) / (c.r * c.r)
        bright += c.k * expf(-r2)
    }
    return 1 - dark + bright + 0.05 * fbm2(x * 6, y * 6, octaves: 3, seed: 0x3c6ef372)
}
