// Prints sky quantities at known events, one "name value" line each, for
// tests/astronomy.sh to check. The C# twin is Check.cs.
import Foundation

func at(_ y: Int, _ m: Int, _ d: Int, _ hour: Double, lat: Double = 0, lon: Double = 0) -> Ephemeris {
    Ephemeris(latitude: lat, longitude: lon, d: Ephemeris.dayNumber(year: y, month: m, day: d, minutesUT: hour * 60))
}
func planet(_ e: Ephemeris, _ name: String) -> Ephemeris.Planet { e.planets.first { $0.name == name }! }
func say(_ name: String, _ v: Double) { print(name, String(format: "%.3f", v)) }
/// The extreme of f over hourly steps from day0 for `days` days, and when:
/// the day of the month, with the hour as a fraction.
func extreme(_ y: Int, _ m: Int, _ day0: Int, days: Int, max: Bool, _ f: (Ephemeris) -> Double) -> (Double, Double) {
    var best = (max ? -1e9 : 1e9, 0.0)
    for h in 0..<(days * 24) {
        let v = f(at(y, m, day0, Double(h)))
        if max ? v > best.0 : v < best.0 { best = (v, Double(day0) + Double(h) / 24) }
    }
    return best
}

// Total solar eclipse, 2024-04-08, totality at Dallas around 18:42 UT.
let dallas = at(2024, 4, 8, 18.7, lat: 32.78, lon: -96.80)
say("solar-eclipse-dallas-sep", dallas.sun.angle(dallas.moon))
say("solar-eclipse-dallas-phase", dallas.moonPhaseAngle)
// Total lunar eclipse, 2025-09-07, greatest at 18:11 UT: moon opposite the sun.
let lunar = at(2025, 9, 7, 18 + 11.0 / 60)
say("lunar-eclipse-from-antisun", 180 - lunar.sun.angle(lunar.moonFromCenter))
say("lunar-eclipse-lit", lunar.moonLit)
// Great conjunction, 2020-12-21: Jupiter and Saturn 0.1° apart.
let js = extreme(2020, 12, 19, days: 5, max: false) { planet($0, "Jupiter").direction.angle(planet($0, "Saturn").direction) }
say("jupiter-saturn-min-sep", js.0); say("jupiter-saturn-day", js.1)
// Venus and Jupiter, 2023-03-01/02: about 0.5° apart. (Day -2 of March is 26 February.)
let vj = extreme(2023, 3, -2, days: 6, max: false) { planet($0, "Venus").direction.angle(planet($0, "Jupiter").direction) }
say("venus-jupiter-min-sep", vj.0); say("venus-jupiter-day", vj.1)
// Mercury's greatest eastern elongation, 2024-03-24: 18.7°.
let me = extreme(2024, 3, 14, days: 20, max: true) { planet($0, "Mercury").direction.angle($0.sun) }
say("mercury-max-elongation", me.0); say("mercury-max-elongation-day", me.1)
// Mars at opposition, 2025-01-16.
let mo = extreme(2025, 1, 6, days: 20, max: true) { planet($0, "Mars").direction.angle($0.sun) }
say("mars-opposition-day", mo.1)
// Jupiter at opposition, 2023-11-03: magnitude -2.9.
say("jupiter-opposition-mag", planet(at(2023, 11, 3, 0), "Jupiter").magnitude)
// Venus at greatest brilliancy, 2025-02-14: magnitude -4.6 (refs: -4.6 to -4.9).
say("venus-brilliancy-mag", planet(at(2025, 2, 14, 18), "Venus").magnitude)

// The sun at published sunrise and sunset (tests/daylight.sh): its center
// stands 0.833° below the horizon then, refraction included.
func sunAlt(_ e: Ephemeris) -> Double { asin(e.sun.z) * 180 / .pi }
say("sun-berlin-rise", sunAlt(at(2025, 12, 21, 7 + 15.0 / 60, lat: 52.52, lon: 13.40)))
say("sun-berlin-set", sunAlt(at(2026, 6, 21, 19 + 33.0 / 60, lat: 52.52, lon: 13.40)))
say("sun-madrid-set", sunAlt(at(2025, 12, 21, 16 + 51.0 / 60, lat: 40.42, lon: -3.70)))
say("sun-sydney-rise", sunAlt(at(2025, 12, 20, 18 + 40.0 / 60, lat: -33.87, lon: 151.21)))
say("sun-quito-rise", sunAlt(at(2026, 3, 20, 11 + 18.0 / 60, lat: -0.18, lon: -78.47)))

// Stars: Polaris stands at about the latitude; the galactic center lands at l = b = 0.
let berlin = at(2026, 10, 29, 21, lat: 52.52, lon: 13.40)
let polaris = Star.catalog.min { $0.direction.angle(Vec3(0, 0, 1)) < $1.direction.angle(Vec3(0, 0, 1)) }!
say("polaris-alt-berlin", asin(berlin.fromJ2000.apply(polaris.direction).z) * 180 / .pi)
let gc = berlin.toGalactic.apply(berlin.fromJ2000.apply(Vec3(lon: 266.405, lat: -28.936)))
say("galactic-center-l", gc.lon); say("galactic-center-b", gc.lat)
say("stars", Double(Star.catalog.count))

// The eclipse finder: the minute of greatest eclipse seen from a place, in
// hours UT, and whether it's solar (1) or lunar (0); -1 on a day without one.
func eclipseSeen(_ name: String, _ y: Int, _ m: Int, _ d: Int, lat: Double, lon: Double) {
    let e = eclipse(year: y, month: m, day: d, utcOffset: 0, latitude: lat, longitude: lon)
    say(name + "-ut", e.map { Double($0.minute) / 60 } ?? -1)
    say(name + "-solar", e.map { $0.solar ? 1 : 0 } ?? -1)
}
eclipseSeen("eclipse-dallas-2024", 2024, 4, 8, lat: 32.78, lon: -96.80)
eclipseSeen("eclipse-berlin-2028", 2028, 12, 31, lat: 52.52, lon: 13.40)
eclipseSeen("eclipse-berlin-none", 2026, 10, 29, lat: 52.52, lon: 13.40)

