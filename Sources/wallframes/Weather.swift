import Foundation

/// What the sky is doing in one frame.
enum Sky: String, CaseIterable {
    case clear, cloudy, overcast, rain, snow, fog
}

/// The renderer's knobs for a `Sky`, each 0…1. The renderer only reads these,
/// so what a class looks like is tuned here, in one place.
struct Weather {
    var clouds: Float = 0    // cover of drifting clouds in the sky
    var overcast: Float = 0  // a grey deck: dims and greys the palette, hides sun and stars
    var rain: Float = 0      // streak density
    var snow: Float = 0      // flake density; also whitens the ground under the pines
    var fog: Float = 0       // haze that swallows far layers first

    init(_ sky: Sky) {
        switch sky {
        case .clear: break
        case .cloudy: (clouds, overcast) = (0.5, 0.1)
        case .overcast: (clouds, overcast, fog) = (0.95, 0.75, 0.1)
        case .rain: (clouds, overcast, rain, fog) = (1, 0.9, 1, 0.35)
        case .snow: (clouds, overcast, snow, fog) = (1, 0.6, 1, 0.3)
        case .fog: (overcast, fog) = (0.35, 1)
        }
    }
}

/// One day's hourly sky from the Open-Meteo forecast API (open-meteo.com:
/// free, no key, no account). A request carries only the date and the
/// coordinates rounded to 0.1°, about 10 km.
struct Forecast {
    let hours: [Sky]  // local hours 0…23

    static func url(latitude: Double, longitude: Double, date: String) -> URL {
        let lat = (latitude * 10).rounded() / 10, lon = (longitude * 10).rounded() / 10
        return URL(string: "https://api.open-meteo.com/v1/forecast?latitude=\(lat)&longitude=\(lon)"
                   + "&hourly=weather_code,cloud_cover&timezone=auto&start_date=\(date)&end_date=\(date)")!
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
        for (i, time) in times.enumerated() where time.hasPrefix(date + "T") {
            guard let hour = Int(time.dropFirst(date.count + 1).prefix(2)), (0..<24).contains(hour) else { continue }
            hours[hour] = Forecast.sky(code: codes[i] as? Int, cover: covers[i] as? Int)
        }
        guard hours.allSatisfy({ $0 != nil }) else { return nil }
        self.hours = hours.map { $0! }
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
