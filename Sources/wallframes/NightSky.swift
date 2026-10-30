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
    let vivid = mix(RGB(y, y, y), c, 1.3)
    return RGB(max(vivid.r, 0), max(vivid.g, 0), max(vivid.b, 0)) * (1 / y)
}

/// Value noise over the sky in galactic degrees, seamless across l = ±180°:
/// features about `k` degrees across, `stretch` times longer along the plane.
private func skyNoise(_ l: Float, _ b: Float, _ k: Float, _ octaves: Int, _ seed: UInt32, stretch: Float = 1) -> Float {
    let kl = k * stretch
    let a = fbm2(l / kl, b / k, octaves: octaves, seed: seed)
    guard l > 150 else { return a }
    return lerp(a, fbm2((l - 360) / kl, b / k, octaves: octaves, seed: seed), smoothstep(150, 180, l))
}

/// A soft patch of sky around galactic (cl, cb), widths in degrees.
private func patch(_ l: Float, _ b: Float, _ cl: Float, _ cb: Float, _ wl: Float, _ wb: Float) -> Float {
    var dl = l - cl
    if dl > 180 { dl -= 360 } else if dl < -180 { dl += 360 }
    return expf(-(dl / wl) * (dl / wl) - ((b - cb) / wb) * ((b - cb) / wb))
}

// The Milky Way's great star clouds, where they are: galactic l and b,
// widths, brightness.
private let starClouds: [(l: Float, b: Float, wl: Float, wb: Float, k: Float)] = [
    (0, -3, 14, 7, 0.60),       // the bulge, around the center
    (2, -4, 6, 3.5, 0.90),      // Large Sagittarius Star Cloud
    (12, -1, 2.5, 1.6, 0.55),   // Small Sagittarius Star Cloud
    (27, -2.5, 3.5, 2.5, 0.65), // Scutum Star Cloud
    (48, -1, 7, 2.5, 0.40),     // Aquila
    (77, 1.5, 9, 3.5, 0.55),    // Cygnus
    (125, 0, 15, 3, 0.25),      // Cassiopeia
    (-28, -1, 9, 3, 0.30),      // Norma
    (-50, -0.5, 9, 3, 0.40),    // Centaurus
    (-73, -1, 10, 3.5, 0.50),   // Carina
]
// Glowing gas bright enough to tint the band pink, where it is.
private let nebulae: [(l: Float, b: Float, r: Float, k: Float)] = [
    (6.0, -1.2, 0.6, 1.0),      // Lagoon
    (7.0, -0.3, 0.4, 0.6),      // Trifid
    (15.1, -0.7, 0.4, 0.6),     // Omega
    (17.0, 0.8, 0.5, 0.5),      // Eagle
    (85.6, -1.0, 1.4, 0.8),     // North America
    (-72.4, -0.6, 1.0, 0.8),    // Carina
    (-153.7, -2.1, 0.8, 0.5),   // Rosette
    (-151.0, -19.4, 0.6, 0.5),  // Orion
]

/// The Milky Way at galactic longitude `l` (−180…180°) and latitude `b`.
/// The sky is bent first, so the band meanders and every edge frays. Then
/// a band, widest toward the center, and the great star clouds where they
/// are, mottled at every scale; then dust in front of them. Returns the
/// light (about 0…4), how warm it is (the bulge, and light reddened by
/// dust), and the pink of glowing gas.
func milkyWay(_ l0: Float, _ b0: Float) -> (light: Float, warm: Float, pink: Float) {
    guard abs(b0) < 50 else { return (0, 0, 0) }
    func sq(_ x: Float) -> Float { x * x }
    let l = l0 + 3 * skyNoise(l0, b0, 24, 3, 0x9e3779b9)
    let b = b0 + 2 * skyNoise(l0, b0, 8, 4, 0x7f4a7c15)
    let toward = 0.5 + 0.5 * cosf(l * .pi / 180)  // 1 toward the center, 0 away
    let width = 3 + 3.5 * toward + 1.2 * skyNoise(l0, 0, 30, 2, 0x165667b1)
    var light = (0.16 + 0.36 * toward * toward) * expf(-sq(b / width) / 2)  // the band
        + (0.08 + 0.14 * toward) * expf(-sq(b / (3 * width)) / 2)           // its faint outer glow
    for c in starClouds { light += c.k * patch(l, b, c.l, c.b, c.wl, c.wb) }
    light *= 0.6 + 0.8 * smoothstep(-0.5, 0.6, skyNoise(l, b, 2.5, 5, 0x2f6b9d1e))
    // Dust: the Great Rift from Cygnus down to Sagittarius, the dark clouds
    // of Ophiuchus north of the center, the Coalsack, and wisps and lanes
    // drawn out along the plane.
    let clouds = skyNoise(l, b, 2.2, 5, 0x5a1c3e77)
    let lane = powf(1 - abs(skyNoise(l, b, 3, 4, 0x27d4eb2f, stretch: 3)), 10)
    let wisps = skyNoise(l, b, 2, 5, 0x3c6ef372, stretch: 3)
    let path = 1 + 2.5 * smoothstep(40, -5, l) + 1.5 * skyNoise(l0, 0, 14, 2, 0x85ebca6b)
    let rift = smoothstep(95, 70, l) * smoothstep(-25, -5, l) * expf(-sq((b - path) / 2.4))
    let ophiuchus = smoothstep(-25, -10, l) * smoothstep(18, 4, l) * smoothstep(2, 6, b) * smoothstep(24, 10, b)
    let dust = rift * (0.5 + 0.7 * smoothstep(-0.15, 0.15, clouds))
        + 0.9 * ophiuchus * smoothstep(0.15, 0.35, clouds)
        + 0.85 * patch(l, b, -59.5, -0.5, 3, 2.5)  // the Coalsack
        + expf(-sq(b / 6)) * (0.35 * lane + 0.6 * smoothstep(0.15, 0.4, wisps))
    let through = expf(-2.2 * dust)
    var pink: Float = 0
    for n in nebulae { pink += n.k * patch(l0, b0, n.l, n.b, n.r, n.r) }
    let warm = clamp01(0.6 * patch(l, b, 0, -3, 14, 8) + 0.2 * (1 - through))
    return (light * through, warm, pink * through)
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

/// The major meteor showers: peak date, radiant (J2000, degrees), and how
/// many streaks a frame shows at the peak with the radiant high.
let meteorShowers: [(name: String, month: Int, day: Int, ra: Double, dec: Double, count: Int)] = [
    ("Quadrantids", 1, 3, 230, 49, 8),
    ("Lyrids", 4, 22, 271, 34, 3),
    ("Eta Aquariids", 5, 6, 338, -1, 4),
    ("Perseids", 8, 12, 48, 58, 9),
    ("Orionids", 10, 21, 95, 16, 4),
    ("Leonids", 11, 17, 152, 22, 3),
    ("Geminids", 12, 14, 112, 33, 10),
]

/// The shower whose peak night a local date and minute fall in: from noon
/// on its peak date to noon the day after.
func meteorShower(month: Int, day: Int, minute: Int) -> (radiant: Vec3, count: Int)? {
    for s in meteorShowers {
        let evening = month == s.month && day == s.day && minute >= 720
        let next = Ephemeris.dayNumber(year: 2001, month: s.month, day: s.day + 1, minutesUT: 0)
            == Ephemeris.dayNumber(year: 2001, month: month, day: day, minutesUT: 0)  // the day after, any month length
        if evening || (next && minute < 720) { return (Vec3(lon: s.ra, lat: s.dec), s.count) }
    }
    return nil
}
