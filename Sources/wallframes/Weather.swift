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
