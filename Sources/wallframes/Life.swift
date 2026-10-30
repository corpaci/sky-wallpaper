import Foundation

/// Who's out at a frame's minute: the two who live in the cabin, now and
/// then, and wild visitors, rarely. Each day's plan is fixed by its number,
/// so all its frames tell one story; the minute, the light, the season and
/// the weather decide what of it shows.
struct Life {
    enum Outing: Equatable { case stroll, run, hike, ski, stargaze, rainWalk, ride }
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
    var bikesHome: Bool { outing != .ride }

    init() {}

    /// `day` numbers the date; `starNight` says a meteor shower peaks tonight.
    init(day: Int, seed: UInt32, minute: Int, sun: SunModel, season: Season, sky: Sky, starNight: Bool) {
        self.seed = hash32(UInt32(truncatingIfNeeded: day) &* 0x9e3779b1 ^ seed)
        var rng = SplitMix(state: UInt64(self.seed) &* 0x9e3779b97f4a7c15 | 1)
        let alt = sun.altitude(minute), phase = sun.dayPhase(minute) ?? -1, year = season.year
        let snowy = season.snowCover > 0.3 || sky == .snow, wet = sky == .rain
        let evening = minute > sun.noon
        func within(_ a: Float, _ b: Float) -> Bool { phase >= a && phase <= b }
        func side() -> Float { rng.unit() < 0.5 ? -1 : 1 }

        // The two of them: out on about one day in four, more on a meteor
        // night (they never miss one) or a rainy day (they like walking in it).
        let planRoll = rng.unit(), kindRoll = rng.unit(), where_ = rng.unit()
        let way = side()
        var plan: Outing?
        if starNight {
            plan = .stargaze
        } else if wet && planRoll < 0.45 {
            plan = .rainWalk
        } else if planRoll < 0.25 {
            let choices: [(Outing, Float)] = snowy
                ? [(.ski, 0.6), (.stroll, 0.4)]
                : [(.hike, 0.3), (.stroll, 0.3), (.run, 0.15), (.ride, year > 0.25 && year < 0.8 ? 0.15 : 0), (.stargaze, 0.1)]
            var k = kindRoll * choices.reduce(0) { $0 + $1.1 }
            plan = choices.first { k -= $0.1; return k < 0 }?.0 ?? choices[0].0
        }
        let starry = sky != .rain && sky != .snow && sky != .fog
        switch plan {
        case .stroll?: if within(0.78, 0.98) { outing = wet ? .rainWalk : .stroll; at = way * (1.6 + 1.2 * where_) }
        case .run?: if within(0.04, 0.18) && !snowy { outing = wet ? .rainWalk : .run; at = way * (2.5 + 2 * where_) }
        case .hike?: if within(0.3, 0.7) { outing = wet ? .rainWalk : .hike; at = way < 0 ? -(7 + 6 * where_) : 5.5 + 2 * where_ }
        case .ski?: if within(0.3, 0.7) { outing = .ski; at = -(4 + 8 * where_) }
        case .ride?: if within(0.3, 0.75) && !wet { outing = .ride }
        case .rainWalk?: if within(0.25, 0.8) && wet { outing = .rainWalk; at = way * (1.5 + where_) }
        case .stargaze?: if alt < -12 && (minute >= 20 * 60 + 30 || minute < 60) && starry { outing = .stargaze; at = way * (2 + 4 * where_) }
        case nil: break
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
            if outing != nil && outing != .ride && (x > 0) == (at > 0) && abs(x - at) < 3 { x = -x }
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

private enum Pose { case walk(Float), run, ski, sit(pointing: Bool) }

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
    }
    if let to = armTo { arms[1] = [shoulder, ((shoulder.0 + to.0) / 2 + f * 0.04 * P, (shoulder.1 + to.1) / 2), to] }
    let sitting: Bool = { if case .sit = pose { return true } else { return false } }()

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
    if let pack = look.pack, !sitting { line(at(-0.12, 0.74), at(-0.13, 0.55), 0.17, lit(pack)) }
    arm(arms[0], 0.8)
    leg(legs[0], 0.8)
    line((hip.0, hip.1 - 0.04 * P), shoulder, 0.2, lit(look.top))
    if look.coat && !sitting {
        o.polygon([at(-0.09, 0.76), at(0.11, 0.76), at(0.15, 0.3), at(-0.15, 0.3)], lit(look.top))
    }
    if let skirt = look.skirt {
        if sitting {
            o.polygon([at(-0.1, 0.18), at(0.0, 0.06), at(0.28, 0.13), at(0.24, 0.26)], lit(skirt))
        } else {
            // It flows back as she walks; a white band at its hem.
            let hem = [at(-0.22, 0.28), at(-0.1, 0.26), at(0.02, 0.29), at(0.14, 0.27)]
            o.polygon([at(-0.09, 0.56), at(0.09, 0.56)] + hem.reversed(), lit(skirt))
            for (a, b) in zip(hem, hem.dropFirst()) { line(a, b, 0.03, lit(0xf2f2ee)) }
        }
    }
    leg(legs[1], 1)
    if let scarf = look.scarf { line(at(-0.06, 0.8), at(0.09, 0.81), 0.07, lit(scarf)); line(at(-0.04, 0.8), at(-0.08, 0.64), 0.05, lit(scarf)) }
    if look.pack != nil && !sitting { line(at(0.0, 0.77), at(0.05, 0.58), 0.025, lit(0x222226)) }  // its strap
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
    /// Paints the two and their visitors onto the near hill's patch. `ground`
    /// gives the hill's top at x; `clearing` the nearest x near another where
    /// no tree stands on the ridge, for a figure that should show against the
    /// sky, or NaN when there's none near.
    func draw(_ o: inout Overlay, cabin: Scene.Cabin, H: Float, width: Float, year: Float, snowy: Bool,
              ground: (Float) -> Float, clearing: (Float, Float) -> Float, lit: (UInt32) -> RGB, lamp: Float) {
        let P = 0.7 * cabin.wallH, unit = 2 * cabin.halfWidth
        func place(_ at: Float) -> Float { min(max(cabin.x + at * unit, 0.04 * width), 0.96 * width) }
        var rng = SplitMix(state: UInt64(seed) &* 0x2545f4914f6cdd1d | 1)

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

        guard let outing, outing != .ride else { return }
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
            // On a blanket on the ridge, against the stars: she points, his
            // red headlamp keeps their eyes dark-adapted, the telescope looks up.
            let gap = clearing(place(at), 1.2 * P)
            let x = gap.isNaN ? place(at) : gap, y = ground(x) + (gap.isNaN ? 0.01 : 0.002) * H
            o.ellipse(x + f * 0.1 * P, y - 0.015 * P, 0.65 * P, 0.05 * P, 0, lit(0x8a3a3a))
            person(&o, x - f * 0.3 * P, y, P, f, .sit(pointing: true), her, lit)
            person(&o, x + f * 0.15 * P, y, P * 1.05, f, .sit(pointing: false), him, lit)
            let tx = x + f * 0.85 * P
            for dx in [Float(-0.13), 0.02, 0.14] { o.line(tx, y - 0.42 * P, tx + f * dx * P, y, 0.02 * P, lit(0x3a3a3a)) }
            o.line(tx - f * 0.12 * P, y - 0.36 * P, tx + f * 0.14 * P, y - 0.64 * P, 0.07 * P, lit(0xd8d8d0))
            let lampX = x + f * (0.15 - 0.09 * 1.05) * P, lampY = y - 0.5 * 1.05 * P
            o.glow(lampX, lampY, 0.025 * P, RGB(0.6, 0.04, 0.01))
            o.glow(lampX, lampY, 0.12 * P, RGB(0.04, 0.003, 0.001))
        case .ride:
            break
        }
    }

    /// The birds in the sky: a skein of geese in a V on their way, or a
    /// buzzard circling on a thermal. They fly behind the hills.
    func drawSky(width: Float, H: Float, color: RGB) -> Overlay? {
        for v in visits where v.animal == .geese || v.animal == .buzzard {
            var r = SplitMix(state: UInt64(v.seed) | 1)
            let x = (0.15 + 0.7 * r.unit()) * width, y = (0.22 + 0.2 * r.unit()) * H
            if v.animal == .buzzard {
                let span = 0.016 * H
                var o = Overlay(x0: Int(x - span), y0: Int(y - span), x1: Int(x + span) + 1, y1: Int(y + span) + 1)
                flyingBird(&o, x, y, span, -0.1, 0.16, color)
                o.ellipse(x, y + 0.08 * span, 0.06 * span, 0.12 * span, 0, color)  // its fanned tail
                return o
            }
            let n = 7 + Int(r.unit() * 8), gap = 0.009 * H, span = 0.0065 * H, f = v.facing
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
