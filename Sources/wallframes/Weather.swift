import Foundation

/// What the sky is doing in one frame.
enum Sky: String, CaseIterable {
    case clear, cloudy, overcast, rain, snow, fog
}

/// The renderer's knobs for a `Sky`, each 0…1. The renderer only reads these,
/// so what a class looks like is tuned here, in one place.
///
/// Grey weather isn't mirrored, and no cloud ever covers the sky; the scene
/// shows what's beyond the weather. Overcast is the view from above it, a
/// sea of clouds over the world below; cloudy, the same sea broken open, the
/// hills showing through. Fog lies low in the far valleys. Rain is the
/// moment after: wet light, a rainbow opposite the sun, colored glints on the
/// grass. Snow is the clear morning after: fresh snow, and ice glittering in
/// the air.
struct Weather {
    var overcast: Float = 0  // greys and dims the palette, veils sun, moon and stars
    var sea: Float = 0       // a sea of clouds below, ranges breaking through
    var broken: Float = 0    // how much of the sea is open, showing the world below
    var valley: Float = 0    // fog lakes at the feet of the far hills
    var wet: Float = 0       // after rain: rainbow opposite a low sun, glints on the grass
    var snow: Float = 0      // fresh snow on open ground, and ice glittering in the air
    var fog: Float = 0       // haze that swallows far layers first

    init(_ sky: Sky) {
        switch sky {
        case .clear: break
        case .cloudy: (sea, broken) = (1, 0.5)
        case .overcast: sea = 1
        case .rain: (overcast, wet, fog) = (0.05, 1, 0.1)
        case .snow: (snow, fog) = (1, 0.1)
        case .fog: (valley, fog) = (1, 0.08)
        }
    }
}

/// One day's hourly sky from the Open-Meteo forecast API (open-meteo.com:
/// free, no key, no account). A request carries only the date and the
/// coordinates rounded to 0.1°, about 10 km.
struct Forecast {
    let hours: [Sky]  // local hours 0…23
    // For the seasons, when the response has them, by local hour:
    let temperature: [Float]?    // °C at 2 m
    let snowDepth: [Float]?      // m of snow lying
    let freezingLevel: [Float]?  // m above sea level

    static func url(latitude: Double, longitude: Double, date: String) -> URL {
        let lat = (latitude * 10).rounded() / 10, lon = (longitude * 10).rounded() / 10
        return URL(string: "https://api.open-meteo.com/v1/forecast?latitude=\(lat)&longitude=\(lon)"
                   + "&hourly=weather_code,cloud_cover,temperature_2m,snow_depth,freezing_level_height"
                   + "&timezone=auto&start_date=\(date)&end_date=\(date)")!
    }

    /// The hours of `date` from a response body; nil unless all 24 are there.
    init?(json: Data, date: String) {
        guard let root = try? JSONSerialization.jsonObject(with: json) as? [String: Any],
              let hourly = root["hourly"] as? [String: Any],
              let times = hourly["time"] as? [String],
              let codes = hourly["weather_code"] as? [Any], codes.count == times.count,
              let covers = hourly["cloud_cover"] as? [Any], covers.count == times.count
        else { return nil }
        var hours = [Sky?](repeating: nil, count: 24)
        var index = [Int](repeating: -1, count: 24)  // response row of each local hour
        for (i, time) in times.enumerated() where time.hasPrefix(date + "T") {
            guard let hour = Int(time.dropFirst(date.count + 1).prefix(2)), (0..<24).contains(hour) else { continue }
            hours[hour] = Forecast.sky(code: codes[i] as? Int, cover: covers[i] as? Int)
            index[hour] = i
        }
        guard hours.allSatisfy({ $0 != nil }) else { return nil }
        self.hours = hours.map { $0! }
        func series(_ name: String) -> [Float]? {  // all 24 hours, or none
            guard let values = hourly[name] as? [Any], values.count == times.count else { return nil }
            let v = index.map { values[$0] as? Double }
            return v.allSatisfy { $0 != nil } ? v.map { Float($0!) } : nil
        }
        temperature = series("temperature_2m")
        snowDepth = series("snow_depth")
        freezingLevel = series("freezing_level_height")
    }

    /// The day's ground for `season`'s date, at a local hour: the snow line
    /// from the freezing level (on a summit from 1000 to 3500 m, the snow
    /// lying about 200 m below it), snow where the forecast has it, and
    /// hoarfrost on freezing mornings.
    func ground(_ season: Season, hour: Int) -> Season {
        var s = season
        if let level = freezingLevel {
            let median = level.sorted()[12]
            s.snowLine = min(max((median - 200 - 1000) / 2500, 0.03), 0.88)
        }
        if let depth = snowDepth { s.snowCover = smoothstep(0.005, 0.04, depth[hour]) }
        if let t = temperature {
            s.frost = hour < 11 ? smoothstep(0.5, -3, t[hour]) * (1 - s.snowCover) : 0
            s.warm = t[hour] >= 14
        }
        return s
    }

    /// Fetches and returns the raw body too, so it can be kept for reference.
    static func fetch(latitude: Double, longitude: Double, date: String) -> (Forecast, Data)? {
        var body: Data?
        let done = DispatchSemaphore(value: 0)
        URLSession.shared.dataTask(with: URLRequest(url: url(latitude: latitude, longitude: longitude, date: date),
                                                    timeoutInterval: 30)) { data, response, _ in
            if (response as? HTTPURLResponse)?.statusCode == 200 { body = data }
            done.signal()
        }.resume()
        done.wait()
        guard let body, let forecast = Forecast(json: body, date: date) else { return nil }
        return (forecast, body)
    }

    /// The WMO weather code decides fog, snow and rain; cloud cover the rest.
    static func sky(code: Int?, cover: Int?) -> Sky {
        switch code ?? -1 {
        case 45, 48: return .fog
        case 71...77, 85, 86: return .snow
        case 51...67, 80...82, 95...99: return .rain
        default: break
        }
        if let cover { return cover < 30 ? .clear : cover < 75 ? .cloudy : .overcast }
        switch code ?? 0 {
        case 0, 1: return .clear
        case 2: return .cloudy
        default: return .overcast
        }
    }
}
