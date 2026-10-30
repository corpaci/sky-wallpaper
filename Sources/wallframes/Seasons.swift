import Foundation

/// The time of year and the state of the ground, for one frame. Without a
/// forecast it follows the date alone: the summit's snow line rises and
/// falls with the year, and no snow or frost is invented. With one, the
/// snow line follows the day's freezing level, and snow and frost lie only
/// where the forecast has them.
struct Season {
    let year: Float        // 0…1 through the local year: from Jan 1 north of the equator, Jul 1 south of it
    var snowLine = Float(0) // on the summit: 0 at its foot … 1 at its top
    var snowCover = Float(0) // snow lying on the land, 0…1
    var frost = Float(0)   // hoarfrost on the meadow, 0…1
    var warm = true        // a warm evening, for fireflies

    init(year: Float) {
        self.year = year
        snowLine = 0.49 + 0.39 * cosf(2 * .pi * (year - 0.58))  // highest at the end of July, a cap left
    }

    /// For a date, `yyyy-MM-dd` already split, and the hemisphere.
    init(year y: Int, month: Int, day: Int, latitude: Double) {
        let start = Ephemeris.dayNumber(year: y, month: 1, day: 1, minutesUT: 0)
        let length = Ephemeris.dayNumber(year: y + 1, month: 1, day: 1, minutesUT: 0) - start
        let north = Float((Ephemeris.dayNumber(year: y, month: month, day: day, minutesUT: 720) - start) / length)
        self.init(year: latitude >= 0 ? north : (north + 0.5).truncatingRemainder(dividingBy: 1))
    }

    // Leafy trees: leaves out from early April, fresh green into May,
    // turning orange, yellow, red and brown from late September, fallen by
    // late November.
    var leafFill: Float { smoothstep(0.26, 0.36, year) * (1 - smoothstep(0.84, 0.91, year)) }
    var leafFresh: Float { bump(year, 0.26, 0.30, 0.40, 0.48) }
    var leafAutumn: Float { bump(year, 0.70, 0.76, 0.86, 0.92) }
    // Fruit trees: in blossom from mid-April to mid-May, apples from August to mid-October.
    var blossom: Float { bump(year, 0.28, 0.31, 0.36, 0.39) }
    var fruit: Float { bump(year, 0.60, 0.66, 0.75, 0.80) }

    /// How much of the meadow is in flower, 0…1: crocuses, then the spring
    /// meadow, then summer's, then heather.
    var flowers: Float {
        0.5 * bump(year, 0.22, 0.26, 0.31, 0.35) + bump(year, 0.32, 0.36, 0.45, 0.50)
            + 0.7 * bump(year, 0.46, 0.50, 0.60, 0.65) + 0.35 * bump(year, 0.62, 0.66, 0.70, 0.75)
    }

    /// The flower colors in bloom now; a flower picks one by its own number.
    var flowerColors: [UInt32] {
        year < 0.32 ? [0x9b6bd6, 0xf2f0ff, 0xf5c542]                // crocuses
            : year < 0.46 ? [0xf7d23e, 0xfbfbf7, 0xd8a7e8, 0xf7d23e]   // dandelion, daisy, lady's smock
            : year < 0.63 ? [0xe63b2e, 0x4a6fe0, 0xfbfbf7, 0xf1d04a]   // poppy, cornflower, daisy, buttercup
            : [0xb46ab8, 0xc98ad0]                                     // heather
    }

    /// Fireflies, in their weeks around midsummer, on warm evenings.
    var fireflies: Float { warm ? bump(year, 0.45, 0.47, 0.53, 0.56) : 0 }
}

/// Rises from a to b, holds, falls from c to d.
func bump(_ x: Float, _ a: Float, _ b: Float, _ c: Float, _ d: Float) -> Float {
    smoothstep(a, b, x) * (1 - smoothstep(c, d, x))
}
