import Foundation

// Where the sun, moon, planets and stars stand, for one place and moment.
// Sun, moon and planets follow Paul Schlyter's "How to compute planetary
// positions" (stjarnhimlen.se/comp/ppcomp.html): an arcminute or two for the
// sun and moon, a few for the planets, well under a pixel here. Directions
// are unit vectors in the observer's frame: x east, y north, z up.

private let rad = Double.pi / 180

struct Vec3 {
    var x, y, z: Double
    init(_ x: Double, _ y: Double, _ z: Double) { (self.x, self.y, self.z) = (x, y, z) }
    /// From longitude (or right ascension) and latitude (or declination), degrees.
    init(lon: Double, lat: Double) {
        self.init(cos(lat * rad) * cos(lon * rad), cos(lat * rad) * sin(lon * rad), sin(lat * rad))
    }

    static func + (a: Vec3, b: Vec3) -> Vec3 { Vec3(a.x + b.x, a.y + b.y, a.z + b.z) }
    static func - (a: Vec3, b: Vec3) -> Vec3 { Vec3(a.x - b.x, a.y - b.y, a.z - b.z) }
    static func * (a: Vec3, k: Double) -> Vec3 { Vec3(a.x * k, a.y * k, a.z * k) }
    func dot(_ b: Vec3) -> Double { x * b.x + y * b.y + z * b.z }
    func cross(_ b: Vec3) -> Vec3 { Vec3(y * b.z - z * b.y, z * b.x - x * b.z, x * b.y - y * b.x) }
    var length: Double { dot(self).squareRoot() }
    var unit: Vec3 { self * (1 / length) }
    /// Angle to another direction in degrees, exact for small angles too.
    func angle(_ b: Vec3) -> Double { atan2(cross(b).length, dot(b)) / rad }
    var lon: Double { atan2(y, x) / rad }
    var lat: Double { atan2(z, (x * x + y * y).squareRoot()) / rad }
}

/// A rotation, as three rows.
struct Mat3 {
    var r0, r1, r2: Vec3
    func apply(_ v: Vec3) -> Vec3 { Vec3(r0.dot(v), r1.dot(v), r2.dot(v)) }
    var transposed: Mat3 {
        Mat3(r0: Vec3(r0.x, r1.x, r2.x), r1: Vec3(r0.y, r1.y, r2.y), r2: Vec3(r0.z, r1.z, r2.z))
    }
    static func * (m: Mat3, n: Mat3) -> Mat3 {
        let t = n.transposed
        return Mat3(r0: t.apply(m.r0), r1: t.apply(m.r1), r2: t.apply(m.r2))
    }
    /// Turns vectors by `deg` about the x or z axis.
    static func rotX(_ deg: Double) -> Mat3 {
        let (c, s) = (cos(deg * rad), sin(deg * rad))
        return Mat3(r0: Vec3(1, 0, 0), r1: Vec3(0, c, -s), r2: Vec3(0, s, c))
    }
    static func rotZ(_ deg: Double) -> Mat3 {
        let (c, s) = (cos(deg * rad), sin(deg * rad))
        return Mat3(r0: Vec3(c, -s, 0), r1: Vec3(s, c, 0), r2: Vec3(0, 0, 1))
    }
}

/// Equatorial J2000 → galactic (IAU, as in the Hipparcos catalogue).
let galactic = Mat3(r0: Vec3(-0.0548755604, -0.8734370902, -0.4838350155),
                            r1: Vec3(0.4941094279, -0.4448296300, 0.7469822445),
                            r2: Vec3(-0.8676661490, -0.1980763734, 0.4559837762))

/// Elements of an orbit, of date: node N, inclination i, argument of
/// perihelion w and mean anomaly M in degrees; semi-major axis a;
/// eccentricity e.
private struct Orbit {
    let N, i, w, a, e, M: Double

    /// Position in the ecliptic frame, in units of `a`.
    func position() -> Vec3 {
        let m = M * rad
        var E = m + e * sin(m) * (1 + e * cos(m))
        for _ in 0..<5 { E -= (E - e * sin(E) - m) / (1 - e * cos(E)) }
        let xv = a * (cos(E) - e), yv = a * (1 - e * e).squareRoot() * sin(E)
        let r = (xv * xv + yv * yv).squareRoot(), vw = atan2(yv, xv) + w * rad
        let (n, inc) = (N * rad, i * rad)
        return Vec3(r * (cos(n) * cos(vw) - sin(n) * sin(vw) * cos(inc)),
                    r * (sin(n) * cos(vw) + cos(n) * sin(vw) * cos(inc)),
                    r * sin(vw) * sin(inc))
    }
}

/// The sky for one place and moment.
struct Ephemeris {
    struct Planet {
        let name: String
        let direction: Vec3   // horizontal
        let magnitude: Double
        let bv: Double        // color index, as for stars
    }

    let latitude: Double
    let fromJ2000: Mat3        // equatorial J2000 → horizontal
    let toGalactic: Mat3       // horizontal → galactic
    let toEcliptic: Mat3       // horizontal → ecliptic of date
    let sun: Vec3              // horizontal directions
    let moon: Vec3             // as seen from here: parallax shifts it up to 1°
    let moonFromCenter: Vec3   // as seen from the Earth's center, for eclipse geometry
    let moonRadius: Double     // apparent, degrees, from here
    let sunRadius: Double      // apparent, degrees
    let sunLongitude: Double   // ecliptic, degrees
    let moonPhaseAngle: Double // sun–moon–observer, degrees: 0 full, 180 new
    let eclipticPole: Vec3     // horizontal; the moon's axis stays within 1.5° of it
    let planets: [Planet]

    /// Schlyter's day number: days since 2000 Jan 0.0 UT.
    static func dayNumber(year: Int, month: Int, day: Int, minutesUT: Double) -> Double {
        // Days from the civil calendar (Howard Hinnant's algorithm), from 1970-01-01.
        let y = month <= 2 ? year - 1 : year
        let era = (y >= 0 ? y : y - 399) / 400
        let yoe = y - era * 400
        let doy = (153 * ((month + 9) % 12) + 2) / 5 + day - 1
        let days = era * 146097 + yoe * 365 + yoe / 4 - yoe / 100 + doy - 719468
        return Double(days - 10956) + minutesUT / 1440
    }

    init(latitude: Double, longitude: Double, d: Double) {
        self.latitude = latitude
        let ecl = 23.4393 - 3.563e-7 * d
        let toEquator = Mat3.rotX(ecl)

        let sunOrbit = Orbit(N: 0, i: 0, w: 282.9404 + 4.70935e-5 * d, a: 1,
                             e: 0.016709 - 1.151e-9 * d, M: 356.0470 + 0.9856002585 * d)
        let sunEcl = sunOrbit.position()  // geocentric, AU

        // The moon, with the largest perturbations by the sun.
        let mo = Orbit(N: 125.1228 - 0.0529538083 * d, i: 5.1454, w: 318.0634 + 0.1643573223 * d,
                       a: 60.2666, e: 0.054900, M: 115.3654 + 13.0649929509 * d)
        let raw = mo.position()
        let (Ms, Mm) = (sunOrbit.M, mo.M)
        let D = Mm + mo.w + mo.N - Ms - sunOrbit.w, F = Mm + mo.w
        func s(_ deg: Double) -> Double { sin(deg * rad) }
        let dLon = -1.274 * s(Mm - 2 * D) + 0.658 * s(2 * D) - 0.186 * s(Ms) - 0.059 * s(2 * Mm - 2 * D)
            - 0.057 * s(Mm - 2 * D + Ms) + 0.053 * s(Mm + 2 * D) + 0.046 * s(2 * D - Ms) + 0.041 * s(Mm - Ms)
            - 0.035 * s(D) - 0.031 * s(Mm + Ms) - 0.015 * s(2 * F - 2 * D) + 0.011 * s(Mm - 4 * D)
        let dLat = -0.173 * s(F - 2 * D) - 0.055 * s(Mm - F - 2 * D) - 0.046 * s(Mm + F - 2 * D)
            + 0.033 * s(F + 2 * D) + 0.017 * s(2 * Mm + F)
        let dist = raw.length - 0.58 * cos((Mm - 2 * D) * rad) - 0.46 * cos(2 * D * rad)
        let moonEcl = Vec3(lon: raw.lon + dLon, lat: raw.lat + dLat) * dist  // Earth radii

        // Sidereal time, then equatorial of date → horizontal.
        let lst = 280.46061837 + 360.98564736629 * (d - 1.5) + longitude
        let (ct, st, cp, sp) = (cos(lst * rad), sin(lst * rad), cos(latitude * rad), sin(latitude * rad))
        let toHorizon = Mat3(r0: Vec3(-st, ct, 0), r1: Vec3(-sp * ct, -sp * st, cp), r2: Vec3(cp * ct, cp * st, sp))
        let fromEcliptic = toHorizon * toEquator
        // Precession since J2000, as a turn about the ecliptic pole.
        let precess = toEquator * Mat3.rotZ(3.82394e-5 * d) * Mat3.rotX(-ecl)

        fromJ2000 = toHorizon * precess
        toGalactic = galactic * precess.transposed * toHorizon.transposed
        toEcliptic = fromEcliptic.transposed
        sun = fromEcliptic.apply(sunEcl).unit
        moonFromCenter = fromEcliptic.apply(moonEcl).unit
        let fromHere = fromEcliptic.apply(moonEcl) - Vec3(0, 0, 1)  // the observer stands one Earth radius up
        moon = fromHere.unit
        moonRadius = asin(0.2725 / fromHere.length) / rad
        sunRadius = 0.2666 / sunEcl.length
        sunLongitude = sunEcl.lon
        let earthRadiiPerAU = 23454.8
        moonPhaseAngle = (sunEcl * earthRadiiPerAU - moonEcl).angle(moonEcl * -1)
        eclipticPole = fromEcliptic.apply(Vec3(0, 0, 1))

        // Planets: heliocentric orbits, Jupiter and Saturn perturbing each other.
        let mj = 19.8950 + 0.0830853001 * d, ms = 316.9670 + 0.0334442282 * d
        let orbits: [(String, Orbit, Double)] = [
            ("Mercury", Orbit(N: 48.3313 + 3.24587e-5 * d, i: 7.0047 + 5.00e-8 * d, w: 29.1241 + 1.01444e-5 * d,
                              a: 0.387098, e: 0.205635 + 5.59e-10 * d, M: 168.6562 + 4.0923344368 * d), 0.93),
            ("Venus", Orbit(N: 76.6799 + 2.46590e-5 * d, i: 3.3946 + 2.75e-8 * d, w: 54.8910 + 1.38374e-5 * d,
                            a: 0.723330, e: 0.006773 - 1.302e-9 * d, M: 48.0052 + 1.6021302244 * d), 0.82),
            ("Mars", Orbit(N: 49.5574 + 2.11081e-5 * d, i: 1.8497 - 1.78e-8 * d, w: 286.5016 + 2.92961e-5 * d,
                           a: 1.523688, e: 0.093405 + 2.516e-9 * d, M: 18.6021 + 0.5240207766 * d), 1.36),
            ("Jupiter", Orbit(N: 100.4542 + 2.76854e-5 * d, i: 1.3030 - 1.557e-7 * d, w: 273.8777 + 1.64505e-5 * d,
                              a: 5.20256, e: 0.048498 + 4.469e-9 * d, M: mj), 0.83),
            ("Saturn", Orbit(N: 113.6634 + 2.38980e-5 * d, i: 2.4886 - 1.081e-7 * d, w: 339.3939 + 2.97661e-5 * d,
                             a: 9.55475, e: 0.055546 - 9.499e-9 * d, M: ms), 1.04),
        ]
        var planets: [Planet] = []
        for (name, orbit, bv) in orbits {
            var helio = orbit.position()
            if name == "Jupiter" {
                let dl = -0.332 * s(2 * mj - 5 * ms - 67.6) - 0.056 * s(2 * mj - 2 * ms + 21) + 0.042 * s(3 * mj - 5 * ms + 21)
                    - 0.036 * s(mj - 2 * ms) + 0.022 * cos((mj - ms) * rad) + 0.023 * s(2 * mj - 3 * ms + 52)
                    - 0.016 * s(mj - 5 * ms - 69)
                helio = Vec3(lon: helio.lon + dl, lat: helio.lat) * helio.length
            } else if name == "Saturn" {
                let dl = 0.812 * s(2 * mj - 5 * ms - 67.6) - 0.229 * cos((2 * mj - 4 * ms - 2) * rad)
                    + 0.119 * s(mj - 2 * ms - 3) + 0.046 * s(2 * mj - 6 * ms - 69) + 0.014 * s(mj - 3 * ms + 32)
                let db = -0.020 * cos((2 * mj - 4 * ms - 2) * rad) + 0.018 * s(2 * mj - 6 * ms - 49)
                helio = Vec3(lon: helio.lon + dl, lat: helio.lat + db) * helio.length
            }
            let geo = helio + sunEcl
            let (r, R, sd) = (helio.length, geo.length, sunEcl.length)
            let fv = acos(max(-1, min(1, (r * r + R * R - sd * sd) / (2 * r * R)))) / rad  // phase angle
            let base = 5 * log10(r * R)
            let mag: Double
            switch name {
            case "Mercury": mag = -0.36 + base + 0.027 * fv + 2.2e-13 * pow(fv, 6)
            case "Venus": mag = -4.34 + base + 0.013 * fv + 4.2e-7 * pow(fv, 3)
            case "Mars": mag = -1.51 + base + 0.016 * fv
            case "Jupiter": mag = -9.25 + base + 0.014 * fv
            default: mag = -9.0 + base + 0.044 * fv  // Saturn, rings left out
            }
            planets.append(Planet(name: name, direction: fromEcliptic.apply(geo).unit, magnitude: mag, bv: bv))
        }
        self.planets = planets
    }

    /// Illuminated fraction of the moon's disk.
    var moonLit: Double { (1 + cos(moonPhaseAngle * rad)) / 2 }
}

/// The Yale Bright Star Catalogue down to magnitude 5.5 (`Stars.swift`).
struct Star {
    let direction: Vec3  // equatorial J2000
    let magnitude: Float
    let bv: Float

    static let catalog: [Star] = brightStarData.split(separator: "\n").map { line in
        let f = line.split(separator: " ").map { Double($0)! }
        return Star(direction: Vec3(lon: f[0], lat: f[1]), magnitude: Float(f[2]), bv: Float(f[3]))
    }

    /// The Milky Way's grain: 90,000 points too faint to see one by one,
    /// most near the great star clouds, the rest along the band, as bright as
    /// `milkyWay` is where they fall (so dust dims them). `light` is 0…1.5.
    static let grain: [(direction: Vec3, light: Float, bv: Float)] = {
        var rng = SplitMix(state: 0x6d2b79f5a1b2c3d4)
        let toJ2000 = galactic.transposed
        return (0..<90000).map { _ in
            let pick = rng.unit(), u = 2 * rng.unit() - 1
            let l: Float = pick < 0.3 ? 14 * u : pick < 0.42 ? 30 + 12 * u : pick < 0.54 ? 77 + 14 * u
                : pick < 0.62 ? -60 + 18 * u : 180 * u
            let (u1, u2) = (max(rng.unit(), 1e-6), rng.unit())
            let normal = (-2 * logf(u1)).squareRoot() * cosf(2 * .pi * u2)  // Box–Muller
            let b = normal * (2.5 + 4.5 * (0.5 + 0.5 * cosf(l * .pi / 180)))
            let light = (0.25 + 0.75 * powf(rng.unit(), 4)) * min(powf(milkyWay(l, b).light, 1.3), 3) / 2
            return (toJ2000.apply(Vec3(lon: Double(l), lat: Double(b))), light, 1.4 * rng.unit())
        }
    }()
}

/// The day's eclipse, if one is seen from here: a solar one with the sun
/// up, or a lunar one with the moon up and in the Earth's umbra (the
/// penumbra alone barely shows) while the sun is down. Its local minute of
/// greatest phase as seen from here, found to the minute.
func eclipse(year: Int, month: Int, day: Int, utcOffset: Int, latitude: Double, longitude: Double) -> (minute: Int, solar: Bool)? {
    func depth(_ minute: Int) -> (solar: Double, lunar: Double) {  // > 0 when eclipsed and seen
        let sky = Ephemeris(latitude: latitude, longitude: longitude,
                            d: Ephemeris.dayNumber(year: year, month: month, day: day, minutesUT: Double(minute - utcOffset)))
        let solar = sky.sun.z > 0 ? sky.sunRadius + sky.moonRadius - sky.moon.angle(sky.sun) : -1
        let lunar = sky.moon.z > 0 && sky.sun.z < 0 ? 0.70 + 0.26 - sky.moonFromCenter.angle(sky.sun * -1) : -1
        return (solar, lunar)
    }
    var best: (minute: Int, solar: Bool, depth: Double)?
    for coarse in stride(from: 0, to: 1440, by: 10) {
        let d = depth(coarse)
        guard max(d.solar, d.lunar) > -0.3 else { continue }  // near enough to look closer
        for minute in max(coarse - 10, 0)...min(coarse + 10, 1439) {
            let d = depth(minute)
            for (solar, x) in [(true, d.solar), (false, d.lunar)] where x > 0 && x > (best?.depth ?? 0) {
                best = (minute, solar, x)
            }
        }
    }
    return best.map { ($0.minute, $0.solar) }
}
