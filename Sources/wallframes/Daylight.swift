import Foundation

/// Sunrise and sunset for one place and day, from NOAA's general solar
/// position equations: good to a minute or two outside the polar circles.
/// Times are local minutes after midnight for the given UTC offset.
///
/// The renderer needs every frame on its own minute, so the day is held
/// between 3 and 21 hours, centred on solar noon; `note` says when the real
/// sky did something else (polar night or day, or a clamp).
struct Daylight {
    let sunrise: Int, sunset: Int
    let note: String?

    init(latitude: Double, longitude: Double, dayOfYear n: Int, daysInYear: Int, utcOffset: Int) {
        let g = 2 * Double.pi / Double(daysInYear) * Double(n - 1)
        let eqTime = 229.18 * (0.000075 + 0.001868 * cos(g) - 0.032077 * sin(g)
                               - 0.014615 * cos(2 * g) - 0.040849 * sin(2 * g))
        let decl = 0.006918 - 0.399912 * cos(g) + 0.070257 * sin(g) - 0.006758 * cos(2 * g)
            + 0.000907 * sin(2 * g) - 0.002697 * cos(3 * g) + 0.00148 * sin(3 * g)
        let lat = latitude * .pi / 180
        let noon = 720 - 4 * longitude - eqTime + Double(utcOffset)
        // 90.833°: the sun's centre below the horizon at first light, refraction included.
        let c = cos(90.833 * .pi / 180) / (cos(lat) * cos(decl)) - tan(lat) * tan(decl)

        var half: Double, note: String?
        if c > 1 { (half, note) = (90, "polar night") }
        else if c < -1 { (half, note) = (630, "polar day") }
        else { (half, note) = (4 * acos(c) * 180 / .pi, nil) }
        if half < 90 || half > 630 {
            half = min(max(half, 90), 630)
            note = "day held to \(Int(half / 30)) h"
        }
        var rise = Int((noon - half).rounded()), set = Int((noon + half).rounded())
        if rise < 0 { (rise, set, note) = (0, set - rise, note ?? "shifted into the day") }
        if set > 1439 { (rise, set, note) = (rise - (set - 1439), 1439, note ?? "shifted into the day") }
        (sunrise, sunset, self.note) = (rise, set, note)
    }

    /// For a calendar date (`yyyy-MM-dd`), in this Mac's time zone unless an
    /// offset in minutes is given.
    init?(latitude: Double, longitude: Double, date: String, utcOffset: Int?) {
        var utc = Calendar(identifier: .gregorian)
        utc.timeZone = TimeZone(identifier: "UTC")!
        let parts = date.split(separator: "-").compactMap { Int($0) }
        guard parts.count == 3,
              let day = utc.date(from: DateComponents(year: parts[0], month: parts[1], day: parts[2], hour: 12)),
              utc.component(.month, from: day) == parts[1],
              let n = utc.ordinality(of: .day, in: .year, for: day),
              let days = utc.range(of: .day, in: .year, for: day)?.count
        else { return nil }
        let offset = utcOffset ?? TimeZone.current.secondsFromGMT(for: day) / 60
        self.init(latitude: latitude, longitude: longitude, dayOfYear: n, daysInYear: days, utcOffset: offset)
    }
}
