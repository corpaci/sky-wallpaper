import Foundation

/// Who's out at a frame's minute: the two who live in the cabin, now and
/// then, and wild visitors, rarely. Each day's plan is fixed by its number,
/// so all its frames tell one story; the minute, the light, the season and
/// the weather decide what of it shows.
struct Life {
    enum Outing: String, CaseIterable {
        case stroll, run, hike, ski, stargaze, rainWalk = "rain-walk", ride
        case kite, picnic, flowers, garden, snowman, pumpkins, skydive, farHike = "far-hike"
    }
    enum Animal: Equatable { case deer, bear, fox, hare, hedgehog, roofBirds, swallows, geese, buzzard }
    struct Visit {
        let animal: Animal
        let at: Float      // along the near hill, in cabin widths from the cabin (− left)
        let facing: Float  // +1 right, −1 left
        let seed: UInt32
    }

    var outing: Outing?
    var at: Float = 0      // where the two are, in cabin widths from the cabin (− left)
    var facing: Float = 1
    var visits: [Visit] = []
    var seed: UInt32 = 0
    var snowman = false    // the one they built today, standing by the porch
    var lanterns = false   // their carved pumpkins by the steps, lit after dark
    var bikesHome: Bool { outing != .ride }
    /// Whether they're up in the sky or far off on the range behind, above
    /// the near hill's usual patch.
    var skyward: Bool { outing == .kite || outing == .skydive || outing == .farHike }
    // Their places by the cabin, in cabin widths: the vegetable bed left of
    // it, the snowman and the pumpkins right of the porch steps.
    static let gardenAt: Float = -0.95, snowmanAt: Float = 1.3, pumpkinsAt: Float = 1.45

    init() {}

    /// `day` numbers the date; `starNight` says a meteor shower peaks tonight.
    /// `extras` holds the bits of the --extra words given (see Extras).
    /// `force` makes it a day for that outing, whatever the season (--outing).
    init(day: Int, seed: UInt32, minute: Int, sun: SunModel, season: Season, sky: Sky, starNight: Bool, extras: UInt32 = 0,
         force: Outing? = nil) {
        self.seed = hash32(UInt32(truncatingIfNeeded: day) &* 0x9e3779b1 ^ seed)
        var rng = SplitMix(state: UInt64(self.seed) &* 0x9e3779b97f4a7c15 | 1)
        let alt = sun.altitude(minute), phase = sun.dayPhase(minute) ?? -1, year = season.year
        let snowy = season.snowCover > 0.3 || sky == .snow, wet = sky == .rain
        let evening = minute > sun.noon
        func within(_ a: Float, _ b: Float) -> Bool { phase >= a && phase <= b }
        func during(_ a: Float, _ b: Float) -> Bool { year > a && year < b }
        func side() -> Float { rng.unit() < 0.5 ? -1 : 1 }
        let later = phase > 0.7 || (phase < 0 && evening)  // after midday, through the evening

        // The two of them: out on about one day in four, more on a meteor
        // night (they never miss one) or a rainy day (they like walking in it).
        // Some outings keep to their season: kites in spring and autumn wind,
        // the garden and the meadow's flowers in spring, picnics and a tandem
        // skydive in summer, a snowman when there's snow.
        let planRoll = rng.unit(), kindRoll = rng.unit(), where_ = rng.unit()
        let way = side()
        var plan: Outing?
        if let force {
            plan = force
        } else if starNight {
            plan = .stargaze
        } else if wet && planRoll < 0.45 {
            plan = .rainWalk
        } else if planRoll < 0.25 {
            let choices: [(Outing, Float)] = snowy
                ? [(.ski, 0.45), (.stroll, 0.25), (.snowman, 0.3)]
                : [(.hike, 0.25), (.stroll, 0.3), (.run, 0.15), (.ride, during(0.25, 0.8) ? 0.15 : 0), (.stargaze, 0.1),
                   (.farHike, during(0.3, 0.8) ? 0.12 : 0), (.kite, during(0.18, 0.36) || during(0.7, 0.84) ? 0.25 : 0),
                   (.garden, during(0.24, 0.36) ? 0.5 : 0), (.flowers, during(0.26, 0.5) ? 0.45 : 0),
                   (.picnic, during(0.36, 0.7) ? 0.4 : 0), (.skydive, during(0.42, 0.68) ? 0.08 : 0)]
            var k = kindRoll * choices.reduce(0) { $0 + $1.1 }
            plan = choices.first { k -= $0.1; return k < 0 }?.0 ?? choices[0].0
        }
        let starry = sky != .rain && sky != .snow && sky != .fog
        switch plan {
        case .stroll?: if within(0.78, 0.98) { outing = wet ? .rainWalk : .stroll; at = way * (1.6 + 1.2 * where_) }
        case .run?: if within(0.04, 0.18) && !snowy { outing = wet ? .rainWalk : .run; at = way * (2.5 + 2 * where_) }
        case .hike?: if within(0.3, 0.7) { outing = wet ? .rainWalk : .hike; at = way < 0 ? -(7 + 6 * where_) : 5.5 + 2 * where_ }
        case .ski?: if within(0.3, 0.7) { outing = .ski; at = -(4 + 8 * where_) }
        case .ride?: if within(0.3, 0.75) && !wet { outing = .ride; at = way * (2.5 + 3.5 * where_) }
        case .rainWalk?: if within(0.25, 0.8) && wet { outing = .rainWalk; at = way * (1.5 + where_) }
        case .stargaze?: if alt < -12 && (minute >= 20 * 60 + 30 || minute < 60) && starry { outing = .stargaze; at = way * (2 + 4 * where_) }
        case .kite?: if within(0.3, 0.93) { outing = wet ? .rainWalk : .kite; at = way * (2 + 3 * where_) }
        case .picnic?: if within(0.35, 0.65) { outing = wet ? .rainWalk : .picnic; at = way * (1.8 + 2 * where_) }
        case .flowers?: if within(0.3, 0.93) { outing = wet ? .rainWalk : .flowers; at = way * (1.6 + 2.4 * where_) }
        case .garden?: if within(0.08, 0.6) && !wet { outing = .garden; at = Life.gardenAt }
        case .snowman?:
            if within(0.3, 0.7) && snowy { outing = .snowman; at = Life.snowmanAt }
            snowman = later && snowy
        case .skydive?: if within(0.3, 0.7) && starry && sky != .overcast { outing = .skydive; at = way * (2 + 5 * where_) }
        case .farHike?: if within(0.3, 0.7) { outing = wet ? .rainWalk : .farHike; at = way * (3 + 8 * where_) }
        case .pumpkins?, nil: break
        }
        // Pumpkins: carved on the last Saturday before the end of October (by
        // the local year), then lit by the steps every evening through the
        // first of November. Day 1, 2000-01-01, was a Saturday.
        let sinceSaturday = ((day - 1) % 7 + 7) % 7
        func carvingWeek(_ y: Float) -> Bool { y >= 0.806 && y < 0.8252 }
        let carvingDay = force == .pumpkins || (sinceSaturday == 0 && carvingWeek(year))
        if carvingDay && within(0.6, 0.93) && !wet { outing = .pumpkins; at = Life.pumpkinsAt }
        lanterns = carvingDay ? later : sinceSaturday > 0 && carvingWeek(year - Float(sinceSaturday) / 365.25) && year < 0.8355
        // Extra 0. Its own stream of draws, so the visitors stay as they were.
        if extras & 1 != 0 && outing == nil {
            var busy = SplitMix(state: UInt64(self.seed ^ 0x6a09e667) &* 0x9e3779b97f4a7c15 | 1)
            let skip = busy.unit(), gaze = busy.unit(), w1 = busy.unit(), w2 = busy.unit(), w3 = busy.unit(), w4 = busy.unit()
            let dir: Float = busy.unit() < 0.5 ? -1 : 1
            let twilight = phase < 0 && alt > -4
            if (phase >= 0 && phase < 0.25) || (twilight && !evening) {
                if skip < 0.7 || skip >= 0.9 { outing = wet ? .rainWalk : snowy ? .stroll : .run; at = dir * (2.5 + 2 * w1) }
            } else if phase >= 0.25 && phase <= 0.75 {
                if skip < 0.9 {
                    if snowy { outing = .ski; at = -(4 + 8 * w2) }
                    else { outing = wet ? .rainWalk : .hike; at = dir < 0 ? -(7 + 6 * w2) : 5.5 + 2 * w2 }
                }
            } else if phase > 0.75 || (twilight && evening) {
                outing = wet ? .rainWalk : .stroll; at = dir * (1.6 + 1.2 * w3)
            } else if gaze < 0.75 && alt < -12 && (minute >= 20 * 60 + 30 || minute < 60) && starry {
                outing = .stargaze; at = dir * (2 + 4 * w4)
            }
        }
        if outing == .rainWalk && at == 0 { at = way * (1.5 + where_) }
        facing = side()

        // Visitors, each on its own days and at its own hours (at one end of
        // the day: `dusk` says which), kept apart from the two (on their far
        // side) and from each other.
        func visit(_ animal: Animal, _ chance: Float, _ near: Float, _ far: Float, when: (_ dusk: Bool) -> Bool) {
            let roll = rng.unit(), spot = rng.unit(), dir = side(), s = UInt32(truncatingIfNeeded: rng.next())
            let dusk = rng.unit() < 0.5
            guard roll < chance, when(dusk), visits.count < 2 else { return }
            var x = dir * (near + (far - near) * spot)
            if let o = outing, o != .skydive, o != .farHike, (x > 0) == (at > 0), abs(x - at) < 3 { x = -x }
            if visits.contains(where: { abs($0.at - x) < 2.5 }) { x += x > 0 ? 3 : -3 }
            visits.append(Visit(animal: animal, at: x, facing: side(), seed: s))
        }
        let spring = year > 0.17 && year < 0.27, autumn = year > 0.74 && year < 0.86
        let warm = year > 0.35 && year < 0.83
        visit(.bear, 0.05, 8, 13) { _ in warm && within(0.4, 0.92) && !wet }           // with her cubs, far off
        visit(.deer, 0.2, 4, 12) { dusk in alt > -6 && alt < 6 && evening == dusk }     // at the wood's edge at dawn or dusk
        visit(.fox, 0.08, 3, 10) { _ in alt > -9 && alt < 1 && evening }
        visit(.hare, 0.15, 2, 8) { dusk in alt > -3 && alt < 9 && evening == dusk }
        visit(.hedgehog, 0.2, 0.7, 1.4) { _ in year > 0.28 && year < 0.8 && alt < -3 && alt > -13 && evening }  // under the lit window
        visit(.swallows, 0.35, 0, 4) { _ in year > 0.35 && year < 0.66 && within(0.75, 0.95) }
        visit(.roofBirds, 0.2, 0, 0) { _ in (year < 0.2 || year > 0.9) && within(0.1, 0.55) }
        visit(.geese, 0.3, 0, 0) { _ in (spring || autumn) && within(0.1, 0.55) }       // migrating
        visit(.buzzard, 0.2, 0, 0) { _ in alt > 15 && !wet }
    }
}

// MARK: - Drawing

/// How one of the two is dressed and made.
private struct Look {
    var skin: UInt32, hair: UInt32, top: UInt32, legs: UInt32, shoes: UInt32
    var longHair = false, glasses = false, sunglasses = false, coat = false, shorts = false
    var skirt: UInt32?, scarf: UInt32?, hat: UInt32?, pack: UInt32?
}

private enum Pose { case walk(Float), run, ski, sit(pointing: Bool), kneel, ride }

/// Her: mostly green and black-and-white, shoulder-length hair, glasses,
/// flowing skirts in spring and autumn. Him: green and orange, a comfy green
/// hat in winter, sunglasses in summer. Backpacks when they're far from home.
private func looks(year: Float, snowy: Bool, far: Bool) -> (her: Look, him: Look) {
    let winter = snowy || year < 0.2 || year > 0.88, summer = year > 0.42 && year < 0.7
    let green: UInt32 = 0x3f8a52, black: UInt32 = 0x222226, white: UInt32 = 0xf2f2ee, orange: UInt32 = 0xe8792b
    var her = Look(skin: 0xf0c8a6, hair: 0x3a2a22, top: green, legs: black, shoes: white, longHair: true, glasses: true)
    var him = Look(skin: 0xdcae88, hair: 0x5a3c26, top: orange, legs: green, shoes: 0x3a2e26)
    if winter {
        (her.coat, her.scarf, her.shoes) = (true, white, black)
        him.hat = 0x4f9a52
    } else if summer {
        (her.top, her.legs, her.shorts) = (white, green, true)
        (him.shorts, him.sunglasses) = (true, true)
    } else {
        her.skirt = black
    }
    if far { (her.pack, him.pack) = (white, 0x2f6a3a) }
    return (her, him)
}

private func person(_ o: inout Overlay, _ x: Float, _ y: Float, _ P: Float, _ f: Float, _ pose: Pose,
                    _ look: Look, _ lit: (UInt32) -> RGB, armTo: (Float, Float)? = nil) {
    func at(_ dx: Float, _ up: Float) -> (Float, Float) { (x + f * dx * P, y - up * P) }
    func line(_ a: (Float, Float), _ b: (Float, Float), _ w: Float, _ c: RGB) { o.line(a.0, a.1, b.0, b.1, w * P, c) }
    var hip = at(0, 0.48), shoulder = at(0.02, 0.78), head = at(0.04, 0.9)
    var legs: [[(Float, Float)]], arms: [[(Float, Float)]]
    switch pose {
    case .walk(let s):
        legs = [[hip, at(-0.06 * s, 0.25), at(-0.13 * s, 0.02)], [hip, at(0.07 * s, 0.25), at(0.13 * s, 0.02)]]
        arms = [[shoulder, at(0.07 * s, 0.63), at(0.11 * s, 0.5)], [shoulder, at(-0.06 * s, 0.63), at(-0.1 * s, 0.5)]]
    case .run:
        (hip, shoulder, head) = (at(0, 0.47), at(0.09, 0.76), at(0.13, 0.87))
        legs = [[hip, at(-0.1, 0.3), at(-0.24, 0.2)], [hip, at(0.15, 0.3), at(0.13, 0.03)]]
        arms = [[shoulder, at(-0.06, 0.62), at(0.02, 0.55)], [shoulder, at(0.14, 0.64), at(0.2, 0.74)]]
    case .ski:
        (hip, shoulder, head) = (at(-0.02, 0.42), at(0.08, 0.72), at(0.12, 0.84))
        legs = [[hip, at(0.06, 0.22), at(-0.08, 0.03)], [hip, at(0.12, 0.24), at(0.1, 0.03)]]
        arms = [[shoulder, at(-0.02, 0.58), at(-0.12, 0.48)], [shoulder, at(0.14, 0.6), at(0.18, 0.5)]]
    case .sit(let pointing):
        (hip, shoulder, head) = (at(0, 0.08), at(-0.08, 0.38), at(-0.09, 0.5))
        legs = [[hip, at(0.2, 0.2), at(0.34, 0.03)], [hip, at(0.22, 0.17), at(0.37, 0.02)]]
        arms = [[shoulder, at(-0.12, 0.22), at(-0.16, 0.1)],
                pointing ? [shoulder, at(0.04, 0.5), at(0.12, 0.64)] : [shoulder, at(0.06, 0.26), at(0.14, 0.2)]]
    case .kneel:
        // One knee down, reaching to the ground in front.
        (hip, shoulder, head) = (at(0, 0.3), at(0.13, 0.57), at(0.18, 0.68))
        legs = [[hip, at(-0.02, 0.04), at(-0.22, 0.03)], [hip, at(0.2, 0.25), at(0.19, 0.02)]]
        arms = [[shoulder, at(0.2, 0.4), at(0.3, 0.2)], [shoulder, at(0.24, 0.43), at(0.35, 0.22)]]
    case .ride:
        // On a bike's saddle, feet on the pedals, hands on the bars (see `bike`).
        (hip, shoulder, head) = (at(0, 0.7), at(0.16, 0.97), at(0.22, 1.09))
        legs = [[hip, at(0.13, 0.5), at(-0.03, 0.33)], [hip, at(0.21, 0.5), at(0.17, 0.25)]]
        arms = [[shoulder, at(0.28, 0.87), at(0.39, 0.74)], [shoulder, at(0.3, 0.86), at(0.41, 0.73)]]
    }
    if let to = armTo { arms[1] = [shoulder, ((shoulder.0 + to.0) / 2 + f * 0.04 * P, (shoulder.1 + to.1) / 2), to] }
    let sitting: Bool = { if case .sit = pose { return true } else { return false } }()
    let upright: Bool = { switch pose { case .walk, .run, .ski: return true; default: return false } }()

    func leg(_ j: [(Float, Float)], _ shade: Float) {
        let skin = lit(look.skin) * shade, cloth = lit(look.legs) * shade
        line(j[0], j[1], 0.08, look.shorts ? skin : cloth)
        line(j[1], j[2], 0.075, look.shorts ? skin : cloth)
        if look.shorts { line(j[0], ((j[0].0 + j[1].0) / 2, (j[0].1 + j[1].1) / 2), 0.1, cloth) }
        o.ellipse(j[2].0 + f * 0.03 * P, j[2].1 - 0.01 * P, 0.055 * P, 0.028 * P, 0, lit(look.shoes) * shade)
    }
    func arm(_ j: [(Float, Float)], _ shade: Float) {
        line(j[0], j[1], 0.065, lit(look.top) * shade)
        line(j[1], j[2], 0.055, (look.shorts ? lit(look.skin) : lit(look.top)) * shade)  // short sleeves in summer
        o.circle(j[2].0, j[2].1, 0.03 * P, lit(look.skin) * shade)
    }

    // Back to front: the far arm and leg (in shadow), the pack, the body, the near ones, the head.
    if let pack = look.pack, upright { line(at(-0.12, 0.74), at(-0.13, 0.55), 0.17, lit(pack)) }
    arm(arms[0], 0.8)
    leg(legs[0], 0.8)
    line((hip.0, hip.1 - 0.04 * P), shoulder, 0.2, lit(look.top))
    if look.coat && upright {
        o.polygon([at(-0.09, 0.76), at(0.11, 0.76), at(0.15, 0.3), at(-0.15, 0.3)], lit(look.top))
    }
    if let skirt = look.skirt {
        if sitting {
            o.polygon([at(-0.1, 0.18), at(0.0, 0.06), at(0.28, 0.13), at(0.24, 0.26)], lit(skirt))
        } else if case .ride = pose {
            o.polygon([at(-0.07, 0.82), at(0.08, 0.84), at(0.24, 0.5), at(-0.04, 0.55)], lit(skirt))
        } else if case .kneel = pose {
            o.polygon([at(-0.07, 0.42), at(0.08, 0.44), at(0.24, 0.2), at(-0.04, 0.08)], lit(skirt))
        } else {
            // It flows back as she walks; a white band at its hem.
            let hem = [at(-0.22, 0.28), at(-0.1, 0.26), at(0.02, 0.29), at(0.14, 0.27)]
            o.polygon([at(-0.09, 0.56), at(0.09, 0.56)] + hem.reversed(), lit(skirt))
            for (a, b) in zip(hem, hem.dropFirst()) { line(a, b, 0.03, lit(0xf2f2ee)) }
        }
    }
    leg(legs[1], 1)
    if let scarf = look.scarf { line(at(-0.06, 0.8), at(0.09, 0.81), 0.07, lit(scarf)); line(at(-0.04, 0.8), at(-0.08, 0.64), 0.05, lit(scarf)) }
    if look.pack != nil && upright { line(at(0.0, 0.77), at(0.05, 0.58), 0.025, lit(0x222226)) }  // its strap
    arm(arms[1], 1)

    let (hx, hy) = head
    if look.longHair { o.line(hx - f * 0.05 * P, hy - 0.02 * P, hx - f * 0.07 * P, hy + 0.15 * P, 0.15 * P, lit(look.hair)) }
    o.circle(hx, hy, 0.095 * P, lit(look.skin))
    if let hat = look.hat {
        o.ellipse(hx - f * 0.01 * P, hy - 0.04 * P, 0.105 * P, 0.08 * P, 0, lit(hat))
        o.line(hx - f * 0.1 * P, hy - 0.005 * P, hx + f * 0.09 * P, hy - 0.005 * P, 0.045 * P, lit(hat) * 1.15)  // the folded cuff
        o.circle(hx - f * 0.02 * P, hy - 0.135 * P, 0.035 * P, lit(0xf2f2ee))
    } else {
        o.ellipse(hx - f * 0.025 * P, hy - 0.035 * P, 0.1 * P, 0.07 * P, 0, lit(look.hair))
    }
    if look.glasses {
        o.line(hx + f * 0.025 * P, hy - 0.005 * P, hx + f * 0.1 * P, hy - 0.005 * P, 0.024 * P, lit(0x1c1c1c))
        o.line(hx + f * 0.025 * P, hy - 0.005 * P, hx - f * 0.04 * P, hy - 0.02 * P, 0.016 * P, lit(0x1c1c1c))
    }
    if look.sunglasses { o.line(hx + f * 0.03 * P, hy - 0.005 * P, hx + f * 0.1 * P, hy - 0.005 * P, 0.045 * P, lit(0x141414)) }
}

/// One umbrella over the two of them, its panels every color.
private func umbrella(_ o: inout Overlay, _ cx: Float, _ rimY: Float, _ r: Float, _ lit: (UInt32) -> RGB) {
    let colors: [UInt32] = [0xd8433a, 0xf08a2c, 0xf2c94c, 0x5aa65a, 0x3f7fd0, 0x8a5ad0]
    func dome(_ x: Float) -> Float { rimY - 0.55 * r * max(1 - ((x - cx) / r) * ((x - cx) / r), 0).squareRoot() }
    for i in 0..<6 {
        let (xa, xb) = (cx - r + 2 * r * Float(i) / 6, cx - r + 2 * r * Float(i + 1) / 6), xm = (xa + xb) / 2
        o.polygon([(xa, rimY), (xa, dome(xa)), (xm, dome(xm)), (xb, dome(xb)), (xb, rimY), (xm, rimY - 0.07 * r)], lit(colors[i]))
    }
    o.line(cx, rimY - 0.55 * r, cx, rimY - 0.68 * r, 0.04 * r, lit(0x222226))
}

private func deer(_ o: inout Overlay, _ x: Float, _ y: Float, _ s: Float, _ f: Float, grazing: Bool, antlers: Bool,
                  spots: Bool, coat: RGB, light: RGB) {
    func at(_ dx: Float, _ up: Float) -> (Float, Float) { (x + f * dx * s, y - up * s) }
    func line(_ a: (Float, Float), _ b: (Float, Float), _ w: Float, _ c: RGB) { o.line(a.0, a.1, b.0, b.1, w * s, c) }
    line(at(-0.28, 0.52), at(-0.3, 0), 0.045, coat * 0.75)
    line(at(0.22, 0.5), at(0.2, 0), 0.045, coat * 0.75)
    let body = at(0, 0.6)
    o.ellipse(body.0, body.1, 0.36 * s, 0.15 * s, 0, coat)
    line(at(-0.24, 0.52), at(-0.22, 0), 0.05, coat)
    line(at(0.26, 0.5), at(0.28, 0), 0.05, coat)
    let rump = at(-0.35, 0.63)
    o.ellipse(rump.0, rump.1, 0.05 * s, 0.07 * s, 0, light)
    let head = grazing ? at(0.5, 0.12) : at(0.43, 0.96)
    line(at(0.27, 0.66), grazing ? at(0.46, 0.2) : at(0.39, 0.9), 0.11, coat)
    o.ellipse(head.0 + f * 0.03 * s, head.1 + 0.01 * s, 0.1 * s, 0.055 * s, f * (grazing ? 1.1 : 0.45), coat)
    o.ellipse(head.0 - f * 0.05 * s, head.1 - 0.06 * s, 0.025 * s, 0.05 * s, -f * 0.5, coat)
    if antlers {
        let base = (head.0 - f * 0.03 * s, head.1 - 0.05 * s)
        for (dx, up) in [(Float(-0.1), Float(0.32)), (0.08, 0.3)] {
            let tip = (base.0 + f * dx * s, base.1 - up * s), mid = (base.0 + f * dx * 0.5 * s, base.1 - up * 0.5 * s)
            o.line(base.0, base.1, tip.0, tip.1, 0.025 * s, light * 0.8)
            o.line(mid.0, mid.1, mid.0 + f * 0.09 * s, mid.1 - 0.06 * s, 0.02 * s, light * 0.8)
        }
    }
    if spots {
        for (dx, up) in [(Float(-0.18), Float(0.66)), (-0.06, 0.68), (0.08, 0.66), (-0.12, 0.58), (0.02, 0.6), (0.15, 0.6)] {
            let p = at(dx, up)
            o.circle(p.0, p.1, 0.02 * s, light)
        }
    }
}

private func bear(_ o: inout Overlay, _ x: Float, _ y: Float, _ s: Float, _ f: Float, _ fur: RGB, _ muzzle: RGB) {
    func at(_ dx: Float, _ up: Float) -> (Float, Float) { (x + f * dx * s, y - up * s) }
    func line(_ a: (Float, Float), _ b: (Float, Float), _ w: Float, _ c: RGB) { o.line(a.0, a.1, b.0, b.1, w * s, c) }
    line(at(-0.3, 0.3), at(-0.32, 0.02), 0.13, fur * 0.75)
    line(at(0.28, 0.3), at(0.3, 0.02), 0.13, fur * 0.75)
    let body = at(0, 0.42), hump = at(0.18, 0.55)
    o.ellipse(body.0, body.1, 0.48 * s, 0.24 * s, 0, fur)
    o.circle(hump.0, hump.1, 0.18 * s, fur)
    line(at(-0.26, 0.3), at(-0.24, 0.02), 0.14, fur)
    line(at(0.32, 0.3), at(0.36, 0.02), 0.14, fur)
    let head = at(0.55, 0.45), snout = at(0.68, 0.41), ear1 = at(0.49, 0.57), ear2 = at(0.58, 0.58)
    o.circle(ear1.0, ear1.1, 0.045 * s, fur)
    o.circle(ear2.0, ear2.1, 0.045 * s, fur)
    o.circle(head.0, head.1, 0.14 * s, fur)
    o.ellipse(snout.0, snout.1, 0.08 * s, 0.055 * s, 0, muzzle)
    let nose = at(0.75, 0.42)
    o.circle(nose.0, nose.1, 0.025 * s, fur * 0.4)
}

private func fox(_ o: inout Overlay, _ x: Float, _ y: Float, _ s: Float, _ f: Float, _ fur: RGB, _ white: RGB, _ dark: RGB) {
    func at(_ dx: Float, _ up: Float) -> (Float, Float) { (x + f * dx * s, y - up * s) }
    func line(_ a: (Float, Float), _ b: (Float, Float), _ w: Float, _ c: RGB) { o.line(a.0, a.1, b.0, b.1, w * s, c) }
    line(at(-0.15, 0.14), at(-0.16, 0), 0.03, dark)
    line(at(0.13, 0.14), at(0.15, 0), 0.03, dark)
    line(at(-0.17, 0.17), at(-0.35, 0.07), 0.08, fur)  // the brush, white-tipped
    let tip = at(-0.37, 0.06), body = at(0, 0.18), head = at(0.22, 0.25), chest = at(0.16, 0.16)
    o.circle(tip.0, tip.1, 0.035 * s, white)
    o.ellipse(body.0, body.1, 0.19 * s, 0.065 * s, 0, fur)
    o.ellipse(chest.0, chest.1, 0.05 * s, 0.04 * s, 0, white)
    o.ellipse(head.0, head.1, 0.06 * s, 0.045 * s, 0, fur)
    o.polygon([at(0.25, 0.27), at(0.34, 0.22), at(0.25, 0.2)], fur)
    o.polygon([at(0.17, 0.27), at(0.19, 0.35), at(0.23, 0.28)], fur * 0.85)
}

private func hare(_ o: inout Overlay, _ x: Float, _ y: Float, _ s: Float, _ f: Float, _ fur: RGB, _ tail: RGB) {
    func at(_ dx: Float, _ up: Float) -> (Float, Float) { (x + f * dx * s, y - up * s) }
    let body = at(0, 0.09), head = at(0.08, 0.18), ear1 = at(0.05, 0.28), ear2 = at(0.08, 0.28), white = at(-0.1, 0.08)
    o.ellipse(ear1.0, ear1.1, 0.018 * s, 0.07 * s, -f * 0.35, fur * 0.85)
    o.ellipse(body.0, body.1, 0.1 * s, 0.085 * s, 0, fur)
    o.circle(head.0, head.1, 0.05 * s, fur)
    o.ellipse(ear2.0, ear2.1, 0.018 * s, 0.07 * s, -f * 0.15, fur)
    o.circle(white.0, white.1, 0.025 * s, tail)
}

private func hedgehog(_ o: inout Overlay, _ x: Float, _ y: Float, _ s: Float, _ f: Float, _ spines: RGB, _ face: RGB) {
    let (bx, by) = (x, y - 0.045 * s)
    o.ellipse(bx, by, 0.09 * s, 0.05 * s, 0, spines)
    for k in 0..<5 {
        let a = Float.pi * (0.15 + 0.7 * Float(k) / 4)
        o.circle(bx - cosf(a) * 0.07 * s, by - sinf(a) * 0.035 * s, 0.009 * s, spines * 1.5)
    }
    o.ellipse(x + f * 0.085 * s, y - 0.025 * s, 0.035 * s, 0.022 * s, 0, face)
    o.circle(x + f * 0.12 * s, y - 0.025 * s, 0.009 * s, spines * 0.3)
}

/// A pumpkin on the ground at (x, y), `r` its half-height: a carved one
/// shows its face, lit from inside by `glow`.
private func pumpkin(_ o: inout Overlay, _ x: Float, _ y: Float, _ r: Float, carved: Bool, glow: Float, _ lit: (UInt32) -> RGB) {
    let cy = y - 0.8 * r
    o.ellipse(x, cy, 1.2 * r, 0.82 * r, 0, lit(0xd0601c))
    o.ellipse(x, cy, 0.75 * r, 0.8 * r, 0, lit(0xe8792b))  // its ribs
    o.ellipse(x, cy, 0.3 * r, 0.78 * r, 0, lit(0xf08c3c))
    o.line(x, cy - 0.7 * r, x + 0.12 * r, cy - 1.05 * r, 0.2 * r, lit(0x4a6a2a))  // the stem
    guard carved else { return }
    let face = lit(0x2a1408) + RGB(hex: 0xffa030) * (1.3 * glow)
    for s: Float in [-1, 1] {
        o.polygon([(x + s * 0.5 * r, cy - 0.1 * r), (x + s * 0.18 * r, cy - 0.1 * r), (x + s * 0.34 * r, cy - 0.42 * r)], face)
    }
    o.polygon([(x - 0.62 * r, cy + 0.16 * r), (x + 0.62 * r, cy + 0.16 * r), (x + 0.36 * r, cy + 0.5 * r), (x - 0.36 * r, cy + 0.5 * r)], face)
    if glow > 0 { o.glow(x, cy, 1.8 * r, RGB(hex: 0xff8a2a) * (0.12 * glow)) }
}

/// A snowman, facing `f`: two balls, stick arms, and when `done` its head,
/// a carrot nose, coal eyes, a hat and his green scarf.
private func snowmanFigure(_ o: inout Overlay, _ x: Float, _ y: Float, _ P: Float, _ f: Float, done: Bool, snow: RGB,
                           _ lit: (UInt32) -> RGB) {
    let coal = lit(0x1c1c22), stick = lit(0x5a3c26)
    for s: Float in [-1, 1] {
        o.line(x + s * 0.1 * P, y - 0.5 * P, x + s * 0.32 * P, y - 0.66 * P, 0.025 * P, stick)
        o.line(x + s * 0.25 * P, y - 0.61 * P, x + s * 0.29 * P, y - 0.73 * P, 0.018 * P, stick)
    }
    o.circle(x, y - 0.19 * P, 0.21 * P, snow * 0.92)
    o.circle(x + f * 0.01 * P, y - 0.48 * P, 0.15 * P, snow * 0.96)
    for up: Float in [0.42, 0.52] { o.circle(x + f * 0.11 * P, y - up * P, 0.018 * P, coal) }
    guard done else { return }
    let (hx, hy) = (x + f * 0.015 * P, y - 0.7 * P)
    o.circle(hx, hy, 0.105 * P, snow)
    o.line(x - 0.12 * P, y - 0.6 * P, x + 0.12 * P, y - 0.61 * P, 0.05 * P, lit(0x4f9a52))
    o.line(x - f * 0.06 * P, y - 0.6 * P, x - f * 0.1 * P, y - 0.46 * P, 0.04 * P, lit(0x4f9a52))
    o.polygon([(hx + f * 0.06 * P, hy - 0.02 * P), (hx + f * 0.24 * P, hy + 0.01 * P), (hx + f * 0.06 * P, hy + 0.025 * P)], lit(0xf08a2c))
    o.circle(hx + f * 0.04 * P, hy - 0.04 * P, 0.016 * P, coal)
    o.circle(hx + f * 0.085 * P, hy - 0.035 * P, 0.014 * P, coal)
    o.polygon([(hx - 0.07 * P, hy - 0.08 * P), (hx + 0.07 * P, hy - 0.08 * P), (hx + 0.06 * P, hy - 0.21 * P), (hx - 0.06 * P, hy - 0.21 * P)], lit(0x2a2a30))
    o.line(hx - 0.11 * P, hy - 0.08 * P, hx + 0.11 * P, hy - 0.08 * P, 0.025 * P, lit(0x2a2a30))
}

/// A diamond kite at (kx, ky), panels every color, on a sagging line from
/// the hand at (hx, hy); its tail streams on downwind (toward `f`) with bows.
private func kite(_ o: inout Overlay, _ hx: Float, _ hy: Float, _ kx: Float, _ ky: Float, _ P: Float, _ f: Float,
                  _ lit: (UInt32) -> RGB) {
    let thin = max(0.012 * P, 0.6)
    var last = (hx, hy)
    for i in 1...16 {
        let t = Float(i) / 16
        let p = (hx + (kx - hx) * t, hy + (ky - hy) * t + 1.2 * P * t * (1 - t))
        o.line(last.0, last.1, p.0, p.1, thin, lit(0xe8e4da))
        last = p
    }
    let (c, s) = (cosf(f * 0.35), sinf(f * 0.35))
    func at(_ u: Float, _ v: Float) -> (Float, Float) { (kx + (u * c - v * s) * P, ky + (u * s + v * c) * P) }
    let (top, right, bottom, left, mid) = (at(0, -0.38), at(0.28, -0.1), at(0, 0.5), at(-0.28, -0.1), at(0, -0.1))
    for (a, b, color) in [(top, right, UInt32(0xd8433a)), (right, bottom, 0xf2c94c), (bottom, left, 0x3f7fd0), (left, top, 0x5aa65a)] {
        o.polygon([mid, a, b], lit(color))
    }
    o.line(top.0, top.1, bottom.0, bottom.1, 0.02 * P, lit(0x3a2e26))
    o.line(left.0, left.1, right.0, right.1, 0.02 * P, lit(0x3a2e26))
    last = bottom
    for i in 1...10 {
        let p = (bottom.0 + f * 0.11 * P * Float(i), bottom.1 + 0.12 * P * Float(i) + 0.05 * P * sinf(Float(i) * 1.3))
        o.line(last.0, last.1, p.0, p.1, thin, lit(0xf2f2ee))
        if i % 3 == 0 {
            let bow = lit(i == 6 ? 0xf2c94c : 0xd8433a)
            o.polygon([p, (p.0 - 0.06 * P, p.1 - 0.04 * P), (p.0 - 0.06 * P, p.1 + 0.04 * P)], bow)
            o.polygon([p, (p.0 + 0.06 * P, p.1 - 0.04 * P), (p.0 + 0.06 * P, p.1 + 0.04 * P)], bow)
        }
        last = p
    }
}

/// Their vegetable bed, standing on the ground at (x, y): bare through
/// winter (or under snow), sprouting in spring, lettuce and tomatoes on
/// stakes through summer, pumpkins swelling until they're taken to carve.
private func garden(_ o: inout Overlay, _ x: Float, _ y: Float, _ P: Float, year: Float, snow: RGB?, _ lit: (UInt32) -> RGB) {
    let half = 0.5 * P, top = y - 0.13 * P
    o.polygon([(x - half, top), (x + half, top), (x + half, y), (x - half, y)], lit(0x7a5434))
    o.line(x - half, top, x + half, top, 0.05 * P, lit(0x3a2a1e))
    for s: Float in [-1, 1] { o.line(x + s * half, top - 0.03 * P, x + s * half, y, 0.05 * P, lit(0x5a3c26)) }
    if let snow {
        o.ellipse(x, top - 0.01 * P, 1.05 * half, 0.06 * P, 0, snow)
        return
    }
    let grow = smoothstep(0.27, 0.48, year)
    guard grow > 0 && year < 0.86 else { return }
    let leaf = mix(lit(0x4f8a3a), lit(0x9a8a4a), smoothstep(0.74, 0.82, year))  // yellowing in autumn
    for k in 0..<6 {
        let px = x - half + (Float(k) + 0.5) / 3 * half
        if k % 2 == 0 {
            o.ellipse(px, top - 0.04 * P * grow, (0.03 + 0.05 * grow) * P, (0.02 + 0.045 * grow) * P, 0, leaf)
        } else {
            let h = (0.06 + 0.4 * grow) * P
            if year > 0.33 { o.line(px + 0.03 * P, top, px + 0.03 * P, top - 0.5 * P, 0.02 * P, lit(0x8a6a44)) }
            o.line(px, top, px, top - h, (0.02 + 0.05 * grow) * P, leaf)
            o.ellipse(px - 0.03 * P, top - 0.55 * h, 0.05 * P * grow + 0.01 * P, 0.03 * P, 0.5, leaf)
            o.ellipse(px + 0.04 * P, top - 0.8 * h, 0.05 * P * grow + 0.01 * P, 0.03 * P, -0.5, leaf)
            if year > 0.55 && year < 0.76 {
                for (dx, up) in [(Float(-0.04), Float(0.4)), (0.045, 0.6), (-0.03, 0.78)] {
                    o.circle(px + dx * P, top - up * h, 0.028 * P, lit(0xd8302a))
                }
            }
        }
    }
    if year > 0.58 && year < 0.81 {
        for (dx, s) in [(Float(-0.5), Float(1)), (0.45, -1)] {
            o.line(x + dx * half, top - 0.01 * P, x + (dx + s * 0.35) * half, top - 0.02 * P, 0.02 * P, leaf)
            pumpkin(&o, x + dx * half, top + 0.01 * P, (0.04 + 0.07 * smoothstep(0.58, 0.7, year)) * P, carved: false, glow: 0, lit)
        }
    }
}

/// A bunch of flowers held at (hx, hy), wrapped in white paper.
private func bouquet(_ o: inout Overlay, _ hx: Float, _ hy: Float, _ P: Float, _ f: Float, _ lit: (UInt32) -> RGB) {
    let heads: [(Float, Float, UInt32)] = [(-0.06, 0.2, 0xf7d23e), (0.0, 0.25, 0xfbfbf7), (0.06, 0.21, 0xd8a7e8),
                                           (-0.03, 0.29, 0xe63b2e), (0.04, 0.3, 0x4a6fe0), (0.09, 0.26, 0xf7d23e)]
    for (dx, up, _) in heads { o.line(hx, hy, hx + f * dx * P, hy - up * P, 0.012 * P, lit(0x4f8a3a)) }
    for (dx, up, color) in heads { o.circle(hx + f * dx * P, hy - up * P, 0.035 * P, lit(color)) }
    o.polygon([(hx - 0.05 * P, hy - 0.12 * P), (hx + 0.07 * P, hy - 0.12 * P), (hx + f * 0.01 * P, hy + 0.05 * P)], lit(0xf2efe6))
}

/// A wine glass with red in it, its stem held at (x, y).
private func glass(_ o: inout Overlay, _ x: Float, _ y: Float, _ P: Float, _ lit: (UInt32) -> RGB) {
    o.line(x, y - 0.02 * P, x, y + 0.04 * P, 0.012 * P, lit(0xdfe6ea))
    o.polygon([(x - 0.035 * P, y - 0.09 * P), (x + 0.035 * P, y - 0.09 * P), (x + 0.02 * P, y - 0.02 * P), (x - 0.02 * P, y - 0.02 * P)], lit(0x8a1a2a))
    o.line(x - 0.038 * P, y - 0.11 * P, x + 0.038 * P, y - 0.11 * P, 0.015 * P, lit(0xdfe6ea))
}

/// A bird on the wing, seen from the side or below: two wings bent at the
/// wrist, `flap` lifting their tips.
func flyingBird(_ o: inout Overlay, _ x: Float, _ y: Float, _ span: Float, _ flap: Float, _ broad: Float, _ color: RGB) {
    let tip = span / 2, wrist = 0.22 * span
    let pts: [(Float, Float)] = [(x - tip, y - flap * 0.3 * span), (x - wrist, y - 0.04 * span), (x, y + 0.03 * span),
                                 (x + wrist, y - 0.04 * span), (x + tip, y - flap * 0.3 * span)]
    for (a, b) in zip(pts, pts.dropFirst()) { o.line(a.0, a.1, b.0, b.1, broad * span, color) }
    o.ellipse(x, y + 0.03 * span, 0.06 * span, 0.04 * span, 0, color)
}

extension Life {
    /// Paints the two, their garden and their things, and their visitors
    /// onto the near hill's patch. `ground` gives the hill's top at x;
    /// `clearing` the nearest x near another where no tree stands on the
    /// ridge, for a figure that should show against the sky, or NaN when
    /// there's none near. `snow` is snow's color on things. `distant`
    /// finds a spot on the range behind, near x, where a figure that tall
    /// shows against the sky; `distantLit` gives a color as it looks there.
    func draw(_ o: inout Overlay, cabin: Scene.Cabin, H: Float, width: Float, year: Float, snowy: Bool,
              ground: (Float) -> Float, clearing: (Float, Float) -> Float, lit: (UInt32) -> RGB, snow: RGB, lamp: Float,
              distant: (Float, Float) -> (x: Float, y: Float)?, distantLit: (UInt32) -> RGB) {
        let P = 0.7 * cabin.wallH, unit = 2 * cabin.halfWidth
        func place(_ at: Float) -> Float { min(max(cabin.x + at * unit, 0.04 * width), 0.96 * width) }
        var rng = SplitMix(state: UInt64(seed) &* 0x2545f4914f6cdd1d | 1)

        // Their things: the vegetable bed, a snowman, the pumpkins lit by the steps.
        let gx = place(Life.gardenAt)
        garden(&o, gx, ground(gx) + 0.006 * H, P, year: year, snow: snowy ? snow : nil, lit)
        if snowman {
            let x = place(Life.snowmanAt)
            snowmanFigure(&o, x, ground(x) + 0.008 * H, P, 1, done: true, snow: snow, lit)
        }
        if lanterns {
            for (dx, r) in [(Float(0.6), Float(0.13)), (0.85, 0.1), (1.12, 0.15)] {
                let x = cabin.porch1 + dx * cabin.halfWidth
                pumpkin(&o, x, ground(x) + 0.006 * H, r * P, carved: true, glow: lamp, lit)
            }
        }

        for v in visits {
            var r = SplitMix(state: UInt64(v.seed) | 1)
            let x = place(v.at), f = v.facing
            switch v.animal {
            case .deer:
                // A doe or two; a spotted fawn in early summer; a stag with antlers from August to March.
                let y = ground(x) + 0.012 * H
                let coat = lit(year > 0.3 && year < 0.75 ? 0x9a5c38 : 0x6f5c4c), light = lit(0xe8dcc8)
                let stag = (year > 0.6 || year < 0.2) && r.unit() < 0.4
                deer(&o, x, y, P * (stag ? 1.1 : 1), f, grazing: r.unit() < 0.5, antlers: stag, spots: false, coat: coat, light: light)
                if year > 0.4 && year < 0.62 {
                    deer(&o, x - f * 0.55 * P, y + 0.004 * H, 0.62 * P, f, grazing: false, antlers: false, spots: true, coat: coat, light: light)
                } else if !stag && r.unit() < 0.6 {
                    deer(&o, x + f * 0.75 * P, y + 0.003 * H, 0.95 * P, -f, grazing: true, antlers: false, spots: false, coat: coat, light: light)
                }
            case .bear:
                let y = ground(x) + 0.01 * H, fur = lit(0x4b3426), muzzle = lit(0x8a6a4a)
                bear(&o, x, y, P, f, fur, muzzle)
                bear(&o, x - f * 0.85 * P, y + 0.002 * H, 0.42 * P, f, fur, muzzle)
                bear(&o, x - f * 1.25 * P, y - 0.001 * H, 0.4 * P, f, fur, muzzle)
            case .fox:
                fox(&o, x, ground(x) + 0.01 * H, P, f, lit(0xc8642a), lit(0xf0ece4), lit(0x2a1e18))
            case .hare:
                // White in winter, as the mountain hare turns.
                hare(&o, x, ground(x) + 0.014 * H, P, f, lit(snowy ? 0xeef0f2 : 0x8e7454), lit(0xf4f4f0))
            case .hedgehog:
                let y = cabin.base + 0.008 * H
                let warm = lit(0x6a5444) + RGB(hex: 0xffb35c) * (0.12 * lamp)
                hedgehog(&o, x, y, P, f, warm, lit(0xc8a882) + RGB(hex: 0xffb35c) * (0.12 * lamp))
                if year > 0.55 {  // her hoglets, in late summer
                    for k in 1...3 { hedgehog(&o, x - f * (0.14 + 0.12 * Float(k)) * P, y + 0.002 * H * Float(k % 2), 0.55 * P, f, warm, warm * 1.4) }
                }
            case .roofBirds:
                // Tits and a robin on the roof's ridge and slope.
                let apexY = cabin.base - cabin.wallH - cabin.roofH
                for k in 0..<3 {
                    let t = 0.1 + 0.25 * Float(k) + 0.05 * r.unit(), s: Float = k % 2 == 0 ? 1 : -1
                    let (bx, by) = (cabin.x + s * t * 1.08 * cabin.halfWidth, apexY + t * cabin.roofH - 0.03 * P)
                    let body = lit(k == 1 ? 0xd8703a : 0xe0c040)
                    o.circle(bx, by, 0.045 * P, body)
                    o.circle(bx + s * 0.04 * P, by - 0.035 * P, 0.03 * P, lit(k == 1 ? 0x6a5444 : 0x1c1c22))
                    o.line(bx - s * 0.04 * P, by, bx - s * 0.1 * P, by + 0.02 * P, 0.025 * P, lit(0x4a5a6a))
                }
            case .swallows:
                // Swallows hawking for insects over the treetops in the evening.
                for _ in 0..<7 {
                    let (bx, by) = (x + (r.unit() - 0.5) * 8 * P, ground(x) - (3 + 2.5 * r.unit()) * P)
                    flyingBird(&o, bx, by, 0.32 * P, 0.6 * r.unit() - 0.3, 0.1, lit(0x1e2430))
                }
            case .geese, .buzzard:
                break  // in the sky (drawSky)
            }
        }

        guard let outing else { return }
        let far = abs(at) > 5
        let (her, him) = looks(year: year, snowy: snowy, far: far)
        let f = facing, s = 2 * rng.unit() - 1
        switch outing {
        case .stroll, .rainWalk, .hike:
            // Side by side, walking; on a hike along the ridge if there's a gap in the trees, with packs.
            let gap = outing == .hike ? clearing(place(at), 0.6 * P) : .nan
            let x = gap.isNaN ? place(at) : gap
            let y = gap.isNaN ? ground(x) + 0.008 * H : ground(x) + 0.002 * H
            if outing == .rainWalk {
                // Close together under his umbrella.
                let rimY = y - 1.05 * P, hand = (x, y - 0.7 * P)
                person(&o, x - f * 0.14 * P, y - 0.002 * H, P, f, .walk(s), her, lit)
                person(&o, x + f * 0.14 * P, y, P * 1.05, f, .walk(-s), him, lit, armTo: hand)
                o.line(x, rimY - 0.2 * P, x, hand.1, 0.025 * P, lit(0x222226))
                umbrella(&o, x, rimY, 0.44 * P, lit)
            } else {
                person(&o, x - f * 0.22 * P, y - 0.002 * H, P, f, .walk(s), her, lit)
                person(&o, x + f * 0.22 * P, y, P * 1.05, f, .walk(-s), him, lit)
            }
        case .run:
            let x = place(at), y = ground(x) + 0.01 * H
            person(&o, x - f * 0.5 * P, y - 0.002 * H, P, f, .run, her, lit)
            person(&o, x + f * 0.3 * P, y, P * 1.05, f, .run, him, lit)
        case .ski:
            // Cross-country, one behind the other, on her green skis and his orange ones.
            let x = place(at), y = ground(x) + 0.02 * H
            for (dx, look, ski, scale) in [(Float(-0.7), her, UInt32(0x3f8a52), Float(1)), (0.5, him, 0xe8792b, 1.05)] {
                let px = x + f * dx * P, sP = P * scale
                o.line(px - f * 0.5 * sP, y, px + f * 0.55 * sP, y, 0.035 * sP, lit(ski))
                o.line(px + f * 0.55 * sP, y, px + f * 0.63 * sP, y - 0.05 * sP, 0.035 * sP, lit(ski))
                person(&o, px, y - 0.02 * sP, sP, f, .ski, look, lit)
                o.line(px - f * 0.12 * sP, y - 0.5 * sP, px - f * 0.32 * sP, y, 0.02 * sP, lit(0x3a3a3a))
                o.line(px + f * 0.18 * sP, y - 0.52 * sP, px + f * 0.02 * sP, y, 0.02 * sP, lit(0x3a3a3a))
            }
        case .stargaze:
            // On a blanket on the ridge, against the stars: she points, he
            // reads a star chart on his knees by a red torch, which keeps
            // their eyes dark-adapted, and the telescope looks up.
            let gap = clearing(place(at), 1.2 * P)
            let x = gap.isNaN ? place(at) : gap, y = ground(x) + (gap.isNaN ? 0.01 : 0.002) * H
            o.ellipse(x + f * 0.1 * P, y - 0.015 * P, 0.65 * P, 0.05 * P, 0, lit(0x8a3a3a))
            person(&o, x - f * 0.3 * P, y, P, f, .sit(pointing: true), her, lit)
            person(&o, x + f * 0.15 * P, y, P * 1.05, f, .sit(pointing: false), him, lit)
            let tx = x + f * 0.85 * P
            for dx in [Float(-0.13), 0.02, 0.14] { o.line(tx, y - 0.42 * P, tx + f * dx * P, y, 0.02 * P, lit(0x3a3a3a)) }
            o.line(tx - f * 0.12 * P, y - 0.36 * P, tx + f * 0.14 * P, y - 0.64 * P, 0.07 * P, lit(0xd8d8d0))
            let hx = x + f * 0.15 * P, hP = 1.05 * P  // him
            let red = RGB(0.6, 0.04, 0.01)
            o.line(hx + f * 0.05 * hP, y - 0.25 * hP, hx + f * 0.21 * hP, y - 0.33 * hP, 0.025 * hP, lit(0xe8e2d4) + red * 0.35)  // the chart
            o.glow(hx + f * 0.08 * hP, y - 0.3 * hP, 0.012 * P, red * 0.5)  // the torch
            o.glow(hx + f * 0.13 * hP, y - 0.3 * hP, 0.09 * P, red * 0.06)
        case .ride:
            // Along the ridge, one behind the other: hers green, his orange.
            let x = place(at), y = ground(x) + 0.01 * H
            for (dx, look, color, scale) in [(Float(-0.75), her, UInt32(0x3f9a4a), Float(1)), (0.65, him, 0xe8792b, 1.05)] {
                let sP = P * scale, r = sP / 3.5, px = x + f * dx * P
                bike(&o, px - f * 0.95 * r, y - r, r, f, color, lit)
                person(&o, px, y, sP, f, .ride, look, lit)
            }
        case .kite:
            // On the meadow: he holds the line, she points it out.
            let x = place(at), y = ground(x) + 0.008 * H, hand = (x + f * 0.42 * P, y - 0.98 * P)
            person(&o, x - f * 0.3 * P, y - 0.002 * H, P, f, .walk(0.2), her, lit, armTo: (x - f * 0.12 * P, y - 1.0 * P))
            person(&o, x + f * 0.22 * P, y, P * 1.05, f, .walk(-0.2), him, lit, armTo: hand)
            kite(&o, hand.0, hand.1, x + f * 3.4 * P, y - 6.4 * P, P, f, lit)
        case .picnic:
            // On a checked blanket on the ridge, facing each other: bread,
            // apples, a basket and a bottle of red between them, a glass each.
            let gap = clearing(place(at), 1.3 * P)
            let x = gap.isNaN ? place(at) : gap, y = ground(x) + (gap.isNaN ? 0.01 : 0.002) * H
            for i in 0..<14 {
                for row in 0..<2 {
                    let (xa, xb) = (x - 1.05 * P + 0.15 * P * Float(i), x - 0.9 * P + 0.15 * P * Float(i))
                    let (ya, yb) = (y - 0.06 * P + 0.03 * P * Float(row), y - 0.03 * P + 0.03 * P * Float(row))
                    o.polygon([(xa, ya), (xb, ya), (xb, yb), (xa, yb)], lit((i + row) % 2 == 0 ? 0xd8433a : 0xf2efe6))
                }
            }
            let bx = x - f * 0.22 * P
            o.polygon([(bx - 0.11 * P, y - 0.2 * P), (bx + 0.11 * P, y - 0.2 * P), (bx + 0.09 * P, y - 0.05 * P), (bx - 0.09 * P, y - 0.05 * P)], lit(0x9a6a3a))
            o.line(bx - 0.1 * P, y - 0.13 * P, bx + 0.1 * P, y - 0.13 * P, 0.015 * P, lit(0x7a5030))
            for i in 0..<8 {  // its handle
                let (a0, a1) = (Float(i) * .pi / 8, Float(i + 1) * .pi / 8)
                o.line(bx + 0.09 * P * cosf(a0), y - 0.2 * P - 0.1 * P * sinf(a0), bx + 0.09 * P * cosf(a1), y - 0.2 * P - 0.1 * P * sinf(a1),
                       0.018 * P, lit(0x7a5030))
            }
            let wx = x + f * 0.03 * P
            o.line(wx, y - 0.07 * P, wx, y - 0.21 * P, 0.07 * P, lit(0x1f4a2a))
            o.line(wx, y - 0.21 * P, wx, y - 0.33 * P, 0.03 * P, lit(0x1f4a2a))
            o.line(wx, y - 0.11 * P, wx, y - 0.16 * P, 0.072 * P, lit(0xf2efe6))  // its label
            o.ellipse(x + f * 0.22 * P, y - 0.09 * P, 0.11 * P, 0.035 * P, -f * 0.25, lit(0xd8a05a))  // a loaf
            for dx: Float in [0.38, 0.45] { o.circle(x + f * dx * P, y - 0.1 * P, 0.038 * P, lit(0xc8302a)) }
            let (herGlass, hisGlass) = ((x - f * 0.47 * P, y - 0.48 * P), (x + f * 0.48 * P, y - 0.5 * P))
            person(&o, x - f * 0.78 * P, y, P, f, .sit(pointing: false), her, lit, armTo: herGlass)
            person(&o, x + f * 0.8 * P, y, P * 1.05, -f, .sit(pointing: false), him, lit, armTo: hisGlass)
            glass(&o, herGlass.0, herGlass.1, P, lit)
            glass(&o, hisGlass.0, hisGlass.1, P, lit)
        case .flowers:
            // On the meadow: he kneels for one more, she carries the bouquet.
            let x = place(at), y = ground(x) + 0.008 * H, hand = (x - f * 0.1 * P, y - 0.56 * P)
            for (dx, color) in [(Float(0.62), UInt32(0xd8a7e8)), (0.95, 0xfbfbf7), (1.1, 0xe63b2e), (1.25, 0xf7d23e)] {
                o.line(x + f * dx * P, y, x + f * dx * P, y - 0.12 * P, 0.012 * P, lit(0x4f8a3a))
                o.circle(x + f * dx * P, y - 0.12 * P, 0.03 * P, lit(color))
            }
            person(&o, x + f * 0.42 * P, y, P * 1.05, f, .kneel, him, lit)
            let pick = (x + f * (0.42 + 0.35 * 1.05) * P, y - 0.22 * 1.05 * P)
            o.line(pick.0, pick.1, pick.0 + f * 0.02 * P, pick.1 - 0.1 * P, 0.012 * P, lit(0x4f8a3a))
            o.circle(pick.0 + f * 0.02 * P, pick.1 - 0.1 * P, 0.03 * P, lit(0xf7d23e))
            person(&o, x - f * 0.3 * P, y - 0.002 * H, P, f, .walk(s), her, lit, armTo: hand)
            bouquet(&o, hand.0, hand.1, P, f, lit)
        case .garden:
            // Planting the bed: she kneels with a seedling, he waters from the green can.
            let x = place(at), y = ground(x) + 0.008 * H
            person(&o, x - f * 0.55 * P, y, P, f, .kneel, her, lit)
            let sprout = (x - f * (0.55 - 0.35) * P, y - 0.22 * P)
            o.ellipse(sprout.0 - 0.02 * P, sprout.1 - 0.04 * P, 0.03 * P, 0.015 * P, 0.6, lit(0x5aa65a))
            o.ellipse(sprout.0 + 0.02 * P, sprout.1 - 0.04 * P, 0.03 * P, 0.015 * P, -0.6, lit(0x5aa65a))
            let hand = (x + f * 0.64 * P, y - 0.55 * P)
            person(&o, x + f * 0.86 * P, y, P * 1.05, -f, .walk(0.15), him, lit, armTo: hand)
            let (cx, cy) = (hand.0 - f * 0.06 * P, hand.1 + 0.08 * P)
            o.line(cx + f * 0.02 * P, cy - 0.04 * P, cx - f * 0.24 * P, cy - 0.1 * P, 0.025 * P, lit(0x3f8a52))  // the spout
            o.polygon([(cx - 0.08 * P, cy - 0.06 * P), (cx + 0.08 * P, cy - 0.06 * P), (cx + 0.07 * P, cy + 0.06 * P), (cx - 0.07 * P, cy + 0.06 * P)],
                      lit(0x3f8a52))
            o.line(cx - f * 0.02 * P, cy - 0.06 * P, hand.0, hand.1, 0.02 * P, lit(0x2f6a3a))  // the handle
            for i in 1...4 {
                let t = Float(i)
                o.circle(cx - f * (0.25 + 0.015 * t) * P, cy - 0.08 * P + 0.045 * P * t, 0.012 * P, lit(0xa8d0f0))
            }
        case .snowman:
            // Building it: she sets its head on, he rolls one more ball.
            let x = place(at), y = ground(x) + 0.008 * H, ball = x + 0.98 * P
            snowmanFigure(&o, x, y, P, 1, done: false, snow: snow, lit)
            person(&o, x - 0.42 * P, y - 0.002 * H, P, 1, .walk(0.3), her, lit, armTo: (x - 0.1 * P, y - 0.72 * P))
            o.circle(x - 0.02 * P, y - 0.72 * P, 0.105 * P, snow)
            o.circle(ball, y - 0.15 * P, 0.15 * P, snow * 0.92)
            person(&o, x + 1.32 * P, y, P * 1.05, -1, .run, him, lit, armTo: (ball + 0.12 * P, y - 0.22 * P))
        case .pumpkins:
            // Carving them on the grass by the porch.
            let x = place(at), y = ground(x) + 0.008 * H
            pumpkin(&o, x - 0.12 * P, y, 0.13 * P, carved: true, glow: 0, lit)
            pumpkin(&o, x + 0.17 * P, y, 0.1 * P, carved: false, glow: 0, lit)
            person(&o, x - 0.55 * P, y - 0.002 * H, P, 1, .kneel, her, lit)
            person(&o, x + 0.6 * P, y, P * 1.05, -1, .kneel, him, lit)
            let hand = (x + (0.6 - 0.35 * 1.05) * P, y - 0.22 * 1.05 * P)
            o.line(hand.0, hand.1, hand.0 - 0.08 * P, hand.1 - 0.03 * P, 0.02 * P, lit(0xc8c8c8))  // his knife
        case .skydive:
            // A tandem jump, coming down over the hill under a canopy in
            // their colors: him behind, her in front, legs up for landing.
            let x = place(at), hy = ground(x) - 8 * P
            let (cx, R) = (x + f * 0.15 * P, 1.5 * P), cy = hy - 2.4 * P + R
            func edge(_ a: Float, _ r: Float) -> (Float, Float) { (cx + r * sinf(a), cy - r * cosf(a)) }
            for a: Float in [-0.8, -0.4, 0, 0.4, 0.8] {
                let e = edge(a, R - 0.3 * P)
                o.line(e.0, e.1, x, hy - 0.6 * P, max(0.01 * P, 0.5), lit(0x4a4a50))
            }
            for i in 0..<7 {
                let (a0, a1) = (-0.8 + 1.6 * Float(i) / 7, -0.8 + 1.6 * Float(i + 1) / 7)
                o.polygon([edge(a0, R), edge(a1, R), edge(a1, R - 0.3 * P), edge(a0, R - 0.3 * P)],
                          lit([UInt32(0xe8792b), 0xf2f2ee, 0x3f8a52][i % 3]))
            }
            person(&o, x - f * 0.08 * P, hy - 0.1 * P, P * 1.05, f, .sit(pointing: false), him, lit)
            person(&o, x + f * 0.08 * P, hy, P, f, .sit(pointing: true), her, lit)
        case .farHike:
            // Two specks with packs on the range behind, up on its crest.
            let tiny = 0.2 * P
            if let spot = distant(place(at), 1.2 * tiny) {
                let (her, him) = looks(year: year, snowy: snowy, far: true)
                person(&o, spot.x - f * 0.3 * tiny, spot.y + 0.03 * tiny, tiny, f, .walk(s), her, distantLit)
                person(&o, spot.x + f * 0.3 * tiny, spot.y + 0.03 * tiny, tiny * 1.05, f, .walk(-s), him, distantLit)
            }
        }
    }

    /// The birds in the sky: a skein of geese in a V on their way, or a
    /// buzzard circling on a thermal. They fly behind the hills, `ui` times
    /// their usual size (Scene's --scale).
    func drawSky(width: Float, H: Float, ui: Float, color: RGB) -> Overlay? {
        for v in visits where v.animal == .geese || v.animal == .buzzard {
            var r = SplitMix(state: UInt64(v.seed) | 1)
            let x = (0.15 + 0.7 * r.unit()) * width, y = (0.22 + 0.2 * r.unit()) * H
            if v.animal == .buzzard {
                let span = 0.016 * H * ui
                var o = Overlay(x0: Int(x - span), y0: Int(y - span), x1: Int(x + span) + 1, y1: Int(y + span) + 1)
                flyingBird(&o, x, y, span, -0.1, 0.16, color)
                o.ellipse(x, y + 0.08 * span, 0.06 * span, 0.12 * span, 0, color)  // its fanned tail
                return o
            }
            let n = 7 + Int(r.unit() * 8), gap = 0.009 * H * ui, span = 0.0065 * H * ui, f = v.facing
            let reach = Float(n / 2 + 1) * gap
            var o = Overlay(x0: Int(x - 1.2 * reach - span), y0: Int(y - 0.6 * reach - span),
                            x1: Int(x + 1.2 * reach + span) + 1, y1: Int(y + 0.6 * reach + span) + 1)
            for i in 0..<n {
                let rank = Float((i + 1) / 2), arm: Float = i % 2 == 0 ? 1 : -1
                let bx = x + f * (0.5 * reach - rank * gap), by = y + arm * rank * gap * 0.42 + (r.unit() - 0.5) * 0.15 * gap
                flyingBird(&o, bx, by, span * (0.9 + 0.2 * r.unit()), 1.2 * r.unit() - 0.4, 0.13, color)
            }
            return o
        }
        return nil
    }
}
