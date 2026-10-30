import Foundation

/// A leafy tree, grown the way a painter builds one. First the gesture: a
/// trunk that bends a little, forking into limbs that curve upward, each
/// forking again down to twigs, every fork as thick in all as what it grew
/// from (Leonardo's rule). Then the foliage: cloud-like clumps at the ends
/// of the branches, each a cluster of round lobes so the outline scallops,
/// lit from above in a few flat tones with an uneven edge between light and
/// shadow, darker deep in the crown, gaps where branches show, stray leaves
/// breaking the silhouette. The shape is fixed per seed; the seasons move
/// through it leaf by leaf (`leafLook`).
struct LeafyTree {
    enum Kind { case broad, fruit }

    struct Clump {
        let x: Float, y: Float, r: Float
        let lobes: [(x: Float, y: Float, r: Float)]
        let depth: Float   // 0 at the crown's lit outside, 1 deep inside: darker
    }

    var wood: [Capsule] = []
    var clumps: [Clump] = []
    var tips: [(x: Float, y: Float)] = []  // twig ends, where buds swell in spring

    var crown: (x: Float, y: Float, rx: Float, ry: Float) = (0, 0, 1, 1)  // its extent, for light across it
    var species = 0  // 0 maple, 1 birch, 2 beech, 3 oak, 4 linden, 5 fruit tree (`leafPaths`)
    var bark: [Capsule] = []  // the birch's white-barked stem and limbs
    var foot: Float = 0       // where it stands

    init(x: Float, base: Float, height h: Float, seed: UInt32, kind: Kind) {
        var rng = SplitMix(state: UInt64(seed) &* 0x9e3779b97f4a7c15 | 1)
        let fruit = kind == .fruit
        let maxDepth = h > 70 ? 5 : h > 30 ? 4 : 3

        // Each species grows its own way (`growths`), and each tree its own
        // within that: some lean and curve back up toward the light, some
        // split low into two stems.
        species = fruit ? 5 : Int(seed >> 5) % 5
        let g = growths[species]
        let lean = (rng.unit() - 0.5) * (fruit ? 0.5 : 0.3)
        let bow = -lean * (0.3 + 0.9 * rng.unit())
        let trunkLength = g.trunk * (0.75 + 0.5 * rng.unit()) * h
        let r = g.thick * (0.8 + 0.45 * rng.unit()) * h
        let twin = !g.leader && rng.unit() < 0.2
        let spread = g.spread * (0.85 + 0.3 * rng.unit())
        foot = base

        // Roots spread into the ground, so the trunk widens to it in a curve.
        let flare = g.flare * (0.7 + 0.6 * rng.unit())
        for side: Float in [-1, 1] {
            let reach = 1 + 0.3 * (rng.unit() - 0.5)
            wood.append(Capsule(x0: x + side * 0.35 * r, y0: base - 1.4 * flare * r, x1: x + side * (0.8 + 0.6 * flare * reach) * r,
                                y1: base + 0.2 * r, r0: 0.6 * r, r1: 0.25 * r))
            wood.append(Capsule(x0: x + side * 0.6 * r, y0: base - 0.5 * flare * r, x1: x + side * (1.1 + 0.8 * flare * reach) * r,
                                y1: base + 0.3 * r, r0: 0.4 * r, r1: 0.18 * r))
        }
        // A stem, bending as it rises; its joints are where limbs leave it.
        func stem(_ x0: Float, _ y0: Float, _ a0: Float, _ curve: Float, _ length: Float, _ r0: Float, _ steps: Int)
            -> [(x: Float, y: Float, a: Float, r: Float)] {
            var (px, py, a, sr) = (x0, y0, a0, r0)
            var joints: [(x: Float, y: Float, a: Float, r: Float)] = []
            for _ in 0..<steps {
                a += curve / Float(steps) + (rng.unit() - 0.5) * g.crook
                let (nx, ny) = (px + sinf(a) * length / Float(steps), py - cosf(a) * length / Float(steps))
                wood.append(Capsule(x0: px, y0: py, x1: nx, y1: ny, r0: sr, r1: sr * 0.92))
                (px, py, sr) = (nx, ny, sr * 0.92)
                joints.append((px, py, a, sr))
            }
            return joints
        }

        // Branches fork down to twigs. Each bends slowly upward as it grows
        // (branches reach for light), or in birch arches out and hangs; it
        // wanders, in oak in elbows; at a fork the branches are as thick in
        // all as their parent (Leonardo).
        var forks: [(x: Float, y: Float, depth: Int)] = []
        func branch(_ x0: Float, _ y0: Float, _ a0: Float, _ length: Float, _ r0: Float, _ depth: Int) {
            var (bx, by, a, br) = (x0, y0, a0, r0)
            for _ in 0..<3 {
                a = a * g.upright + (rng.unit() - 0.5) * g.gnarl + (depth >= 3 ? g.droop * (a < 0 ? -1 : 1) : 0)
                let (nx, ny) = (bx + sinf(a) * length / 3, by - cosf(a) * length / 3)
                wood.append(Capsule(x0: bx, y0: by, x1: nx, y1: ny, r0: br, r1: br * 0.9))
                (bx, by, br) = (nx, ny, br * 0.9)
            }
            forks.append((bx, by, depth))
            guard depth < maxDepth else { tips.append((bx, by)); return }
            let n = depth == 1 ? 3 : (rng.unit() < 0.35 ? 3 : 2)
            let childR = br * (1 / Float(n)).squareRoot() * 0.97
            for k in 0..<n {
                let side: Float = n == 3 ? Float(k) - 1 : (k == 0 ? -1 : 1)
                branch(bx, by, a + side * (spread * 0.25 + 0.3 * rng.unit()) + (rng.unit() - 0.5) * 0.2,
                       length * (0.66 + 0.12 * rng.unit()), childR, depth + 1)
            }
        }

        if g.leader {
            // Birch and linden: the stem runs on up through the crown, its
            // branches leaving it one side then the other, the lower ones
            // longer and flatter, so the crown is an oval (narrow in birch).
            let bole = stem(x, base, lean, bow, trunkLength, r, 3).last!
            let steps = species == 1 ? 7 : 6
            let leader = stem(bole.x, bole.y, bole.a, -0.5 * bole.a, (0.8 - g.trunk) * h, bole.r, steps)
            for (i, j) in leader.enumerated() {
                let t = (Float(i) + 0.5) / Float(steps)
                let length = g.limb * h * sinf(.pi * (0.25 + 0.7 * t)) * (0.85 + 0.3 * rng.unit())
                var side: Float = i % 2 == 0 ? -1 : 1
                if rng.unit() < 0.25 { side = -side }
                for s in rng.unit() < 0.3 ? [side, -side] : [side] {
                    let a = j.a + s * spread * 0.5 * (1.25 - 0.5 * t) + (rng.unit() - 0.5) * 0.2
                    branch(j.x, j.y, a, length, j.r * 0.6, species == 1 ? 2 : 1)
                }
            }
            let top = leader.last!
            branch(top.x, top.y, top.a, 0.5 * g.limb * h, top.r * 0.8, 2)
        } else {
            // The others divide into limbs where the trunk ends, the lowest
            // and widest a little below the rest.
            var trunks: [[(x: Float, y: Float, a: Float, r: Float)]] = []
            if twin {
                let low = stem(x, base, lean, 0, 0.35 * trunkLength, r, 2).last!
                for side: Float in [-1, 1] {
                    trunks.append(stem(low.x, low.y, low.a + side * (0.18 + 0.12 * rng.unit()), bow, 0.75 * trunkLength, low.r * 0.72, 3))
                }
            } else {
                trunks.append(stem(x, base, lean, bow, trunkLength, r, 4))
            }
            let limbs = (fruit ? 5 : 3 + Int(rng.unit() * 2.99)) - (twin ? 1 : 0)
            for joints in trunks {
                for k in 0..<limbs {
                    let u = Float(k) / Float(limbs - 1) - 0.5
                    let j = abs(u) > 0.3 && rng.unit() < 0.6 ? joints[joints.count - 2] : joints[joints.count - 1]
                    let a = u * spread * (twin ? 0.7 : 1) + (rng.unit() - 0.5) * 0.25
                    branch(j.x, j.y, j.a * 0.6 + a, g.limb * h * (twin ? 0.85 : 1) * (0.85 + 0.3 * rng.unit()),
                           j.r * (1 / Float(limbs)).squareRoot(), 1)
                }
            }
        }
        // Birch bark is white on the stem and the big limbs; its twigs are dark.
        if species == 1 { bark = wood.filter { $0.r0 >= 0.3 * r && $0.y0 < base - 1.5 * r } }

        // The crown's extent, from the forks, to judge light and depth in it.
        let outerForks = forks.filter { $0.depth >= 2 }
        let (minX, maxX) = (outerForks.map(\.x).min() ?? x, outerForks.map(\.x).max() ?? x)
        let (minY, maxY) = (outerForks.map(\.y).min() ?? base - h, outerForks.map(\.y).max() ?? base - h / 2)
        crown = ((minX + maxX) / 2, (minY + maxY) / 2, max((maxX - minX) / 2, 1), max((maxY - minY) / 2, 1))

        // Foliage: a clump at most forks, bigger on the inner forks, so the
        // clumps fill the crown and its edge is made of the smaller ones;
        // some left out, for gaps where the branches show.
        for f in forks where rng.unit() < (f.depth == 1 ? 0.95 : 0.78) * g.fill {
            let size: Float = f.depth == 1 ? 0.14 : f.depth <= maxDepth - 2 ? 0.11 : f.depth == maxDepth - 1 ? 0.08 : 0.055
            let cr = size * g.clump * h * (0.8 + 0.4 * rng.unit())
            let (cx, cy) = (f.x + (rng.unit() - 0.5) * 0.3 * cr, f.y - 0.3 * cr)
            let (ux, uy) = ((cx - crown.x) / crown.rx, (cy - crown.y) / crown.ry)
            let outer = clamp01((ux * ux + uy * uy).squareRoot())
            var lobes: [(x: Float, y: Float, r: Float)] = []
            for _ in 0..<(f.depth < maxDepth ? 8 : 5) {
                let (a, d) = (rng.unit() * 2 * .pi, rng.unit().squareRoot() * 0.55 * cr)
                lobes.append((cx + cosf(a) * d, cy + sinf(a) * d * 0.85, cr * (0.4 + 0.25 * rng.unit())))
            }
            if outer > 0.7 {
                // A leafy fringe on the crown's edge: small lobes on the outward side.
                let out = atan2f(uy, ux)
                for _ in 0..<6 {
                    let a = out + (rng.unit() - 0.5) * 2.2
                    lobes.append((cx + cosf(a) * 0.85 * cr, cy + sinf(a) * 0.8 * cr, cr * (0.14 + 0.1 * rng.unit())))
                }
            }
            clumps.append(Clump(x: cx, y: cy, r: cr, lobes: lobes,
                                depth: clamp01(0.6 * (1 - outer) + 0.4 * clamp01(0.5 + 0.5 * uy))))
        }
        // Back to front: deep and low first, so the lit outer clumps lie over them.
        clumps.sort { $0.depth > $1.depth }
    }

    /// Paints the tree into coverage planes: the wood into `wood` (with the
    /// spruces, so it shades and catches snow like them) and the foliage into
    /// `leaf`, with each pixel's light band and height in the crown in `shade`
    /// (band << 6 | top, top 31 at the crown's top; bit 5 marks white birch
    /// bark under it, which shows when the leaves are down) and its species and
    /// distance from the crown's middle in `info` (species << 5 | outer).
    func stamp(wood woodPlane: inout [UInt8], woodLayer: Int, leaf: inout [UInt8], shade: inout [UInt8],
               info: inout [UInt8], leafLayer: Int, width: Int, height: Int, h: Float) {
        wallframes.stamp(wood, into: &woodPlane, plane: woodLayer, width: width, height: height)
        let leafOffset = leafLayer * width * height
        for c in bark {
            // White bark (bit 5 of `shade`), but old and black-fissured low on the stem.
            let rr = max(c.r0, c.r1)
            let x0 = max(Int(floorf(min(c.x0, c.x1) - rr)), 0), x1 = min(Int(ceilf(max(c.x0, c.x1) + rr)), width - 1)
            let y0 = max(Int(floorf(min(c.y0, c.y1) - rr)), 0), y1 = min(Int(ceilf(max(c.y0, c.y1) + rr)), height - 1)
            guard x0 <= x1, y0 <= y1 else { continue }
            let (dx, dy) = (c.x1 - c.x0, c.y1 - c.y0), len2 = dx * dx + dy * dy
            for py in y0...y1 {
                for px in x0...x1 {
                    let (fx, fy) = (Float(px) + 0.5 - c.x0, Float(py) + 0.5 - c.y0)
                    let t = len2 > 0 ? clamp01((fx * dx + fy * dy) / len2) : 0
                    let (ex, ey) = (fx - t * dx, fy - t * dy)
                    guard c.r0 + (c.r1 - c.r0) * t - (ex * ex + ey * ey).squareRoot() > 0 else { continue }
                    let old = 1 - smoothstep(0.05 * h, 0.16 * h, foot - Float(py))
                    if old > 0 && 0.5 + 0.5 * valueNoise2(Float(px) / (0.012 * h), Float(py) / (0.05 * h), 0x6a09e667) < old { continue }
                    shade[leafOffset + py * width + px] |= 0x20
                }
            }
        }
        let light: (x: Float, y: Float) = (-0.55, -0.83)  // from the upper left
        for c in clumps {
            let x0 = max(Int(floorf(c.x - 1.4 * c.r)), 0), x1 = min(Int(ceilf(c.x + 1.4 * c.r)), width - 1)
            let y0 = max(Int(floorf(c.y - 1.4 * c.r)), 0), y1 = min(Int(ceilf(c.y + 1.4 * c.r)), height - 1)
            guard x0 <= x1, y0 <= y1 else { continue }
            for py in y0...y1 {
                for px in x0...x1 {
                    let (fx, fy) = (Float(px) + 0.5, Float(py) + 0.5)
                    // Coverage: the union of the lobes, a scalloped edge that
                    // wobbles like leaves rather than ruled circles.
                    let leafy = 0.2 * valueNoise2(fx / (0.012 * h), fy / (0.012 * h), 0x3c6ef372)
                    var cov: Float = 0, lobeLight: Float = 0
                    for l in c.lobes {
                        let (dx, dy) = (fx - l.x, fy - l.y)
                        let d = (dx * dx + dy * dy).squareRoot()
                        let k = clamp01(l.r * (1 - leafy) - d + 0.5)
                        if k > cov { cov = k; lobeLight = (dx * light.x + dy * light.y) / max(l.r, 0.5) }
                    }
                    guard cov > 0 else { continue }
                    // Tone: the clump as one round mass, its lobes as smaller ones,
                    // an uneven terminator, darker deep inside; then flat bands.
                    let (ux, uy) = ((fx - c.x) / c.r, (fy - c.y) / c.r)
                    let mass = ux * light.x + uy * light.y
                    let wobble = 0.35 * valueNoise2(fx / (0.025 * h), fy / (0.025 * h), 0x51ed270b)
                    let whole = (fx - crown.x) / crown.rx * light.x + (fy - crown.y) / crown.ry * light.y
                    let t = 0.48 + 0.22 * whole + 0.22 * mass + 0.16 * lobeLight + wobble * 0.5 - 0.3 * c.depth
                    let band: UInt8 = t > 0.82 ? 3 : t > 0.58 ? 2 : t > 0.34 ? 1 : 0
                    let (cx, cy) = ((fx - crown.x) / crown.rx, (fy - crown.y) / crown.ry)
                    let top = UInt8(clamp01(0.5 - 0.5 * cy) * 31)
                    let outer = UInt8(clamp01((cx * cx + cy * cy).squareRoot()) * 31)
                    let i = leafOffset + py * width + px
                    let v = UInt8((cov * 255).rounded())
                    if v >= leaf[i] || cov > 0.5 {  // later clumps lie over earlier ones
                        leaf[i] = max(leaf[i], v)
                        shade[i] = band << 6 | shade[i] & 0x20 | top
                        info[i] = UInt8(species) << 5 | outer
                    }
                }
            }
        }
    }
}

/// How each species grows: its trunk's length before it divides and its
/// thickness (in tree heights), its root flare, how crooked the trunk; its
/// limbs' length, how wide they spread, how much they turn back upward
/// (1 = not at all), how much they wander, whether its twigs hang, and
/// whether its stem runs on up through the crown. Oak: short, thick and
/// crooked under wide, elbowed limbs. Birch: slender, the stem through a
/// narrow crown of hanging twigs. Beech: a straight smooth bole under a
/// broad dome. Linden: a straight stem through a tall oval. Maple between
/// them; fruit trees short and wide-armed. And its foliage: how big its
/// clumps and how many forks bear one, from birch's airy, gappy crown to
/// beech's and linden's dense ones.
private struct Growth {
    let trunk, thick, flare, crook: Float
    let limb, spread, upright, gnarl, droop: Float
    let leader: Bool
    let clump, fill: Float
}
private let growths = [
    Growth(trunk: 0.26, thick: 0.045, flare: 1.0, crook: 0.12, limb: 0.27, spread: 1.7, upright: 0.95, gnarl: 0.22, droop: 0, leader: false, clump: 1.0, fill: 1.0),
    Growth(trunk: 0.24, thick: 0.026, flare: 0.5, crook: 0.08, limb: 0.19, spread: 1.0, upright: 0.9, gnarl: 0.16, droop: 0.18, leader: true, clump: 0.6, fill: 0.75),
    Growth(trunk: 0.30, thick: 0.048, flare: 1.3, crook: 0.04, limb: 0.28, spread: 1.8, upright: 0.95, gnarl: 0.14, droop: 0, leader: false, clump: 1.0, fill: 1.08),
    Growth(trunk: 0.19, thick: 0.062, flare: 1.4, crook: 0.24, limb: 0.30, spread: 2.2, upright: 0.96, gnarl: 0.42, droop: 0, leader: false, clump: 0.9, fill: 0.88),
    Growth(trunk: 0.24, thick: 0.042, flare: 1.0, crook: 0.05, limb: 0.20, spread: 1.3, upright: 0.9, gnarl: 0.18, droop: 0, leader: true, clump: 1.0, fill: 1.05),
    Growth(trunk: 0.16, thick: 0.050, flare: 0.8, crook: 0.22, limb: 0.27, spread: 2.1, upright: 0.96, gnarl: 0.30, droop: 0, leader: false, clump: 0.9, fill: 1.0),
]

/// Each species' way through autumn, its leaves' colors in order: maple
/// through yellow and orange to scarlet, birch to gold, beech to copper and
/// russet, oak through olive and ochre to brown, linden to pale gold, the
/// fruit trees to orange and red.
let leafPaths: [[UInt32]] = [
    [0x4f8a3a, 0x9fb83c, 0xe8c43a, 0xe8792a, 0xc8382c],
    [0x4f8a3a, 0x9fb83c, 0xe8c43a, 0xe6b23a],
    [0x4f8a3a, 0x9fb83c, 0xe0b040, 0xb8622c, 0x8f4a28],
    [0x4f8a3a, 0x7f8a3a, 0xb8903a, 0x8f4a28, 0x6f4a30],
    [0x4f8a3a, 0x9fb83c, 0xe8cf6a, 0xe8cf6a],
    [0x4f8a3a, 0x9fb83c, 0xe8b830, 0xe07a2a, 0xc8442a],
]
/// And its habits: how much earlier (−) or later it turns; whether its
/// outer leaves turn first (maple, oak, linden, cherry) or its inner ones
/// (birch); whether it keeps its low dead leaves through winter (beech, oak).
private let leafHabits: [(shift: Float, outerFirst: Bool, keeps: Bool)] = [
    (0, true, false), (-0.03, false, false), (0.03, true, true), (0.04, true, true), (-0.02, true, false), (0, true, false),
]

/// How much of the season's leaf fall a species has had, 0…1.
func leafFall(_ season: Season, species: Int) -> Float { smoothstep(0.80, 0.93, season.year - leafHabits[species].shift) }

/// How a leaf pixel at (x, y) looks in a season: its color in full light,
/// and whether it's there. The seasons run through a crown as a wave, not
/// clump by clump. Autumn turns it from the top down (and from the outside in,
/// or in birch the inside out), each leaf along its species' colors; the
/// first to turn fall first, until the crown is bare, but oak and beech keep
/// their low dead leaves until spring pushes them off. In spring the buds
/// break all over at once, and the lower leaves unfold a little sooner.
/// (Zahnd et al. 2023; Koike 1990.) `shade` and `info` are what
/// `LeafyTree.stamp` wrote; `H` sets the size of the patches that run ahead.
func leafLook(shade: UInt8, info: UInt8, season: Season, x: Int, y: Int, H: Float) -> (color: RGB, presence: Float) {
    let band = Float(shade >> 6) / 3, top = Float(shade & 31) / 31
    let species = min(Int(info >> 5), leafPaths.count - 1), outer = Float(info & 31) / 31
    let habit = leafHabits[species], path = leafPaths[species]
    let yr = season.year
    // Branch by branch the wave runs a little ahead or behind; leaf by leaf, a little more.
    let patch = 0.5 + 0.5 * valueNoise2(Float(x) / (0.008 * H), Float(y) / (0.008 * H), 0x7a3c19d1)
    let leaf = unit(hash32(UInt32(x / 2) &* 0x9e3779b1 ^ UInt32(y / 2) &* 0x85ebca6b ^ 0x1eaf))
    let branch = 0.5 + 0.5 * valueNoise2(Float(x) / (0.004 * H), Float(y) / (0.004 * H), 0x2c1b3a5d)  // twig by twig

    let phase = clamp01(0.5 * (1 - top) + 0.3 * (habit.outerFirst ? 1 - outer : outer) + 0.2 * patch)  // 0 turns first
    let autumn = smoothstep(0.70, 0.86, yr - habit.shift)
    let stage = clamp01((autumn * 1.6 - phase) / 0.6 + 0.1 * (leaf - 0.5))
    let k = stage * Float(path.count - 1), i = min(Int(k), path.count - 2)
    var color = mixOklab(RGB(hex: path[i]), RGB(hex: path[i + 1]), k - Float(i))
    // Young leaves: light yellow-green, darkening into summer.
    color = mixOklab(color, RGB(hex: 0xc6e87a), yr < 0.5 ? 1 - smoothstep(0.32, 0.47, yr) : 0)

    let unfold = smoothstep(0.26, 0.38, yr)
    var present: Float = yr < 0.5 ? (unfold * 1.2 > 0.25 * top + 0.75 * leaf ? 1 : 0)
                                  : (leafFall(season, species: species) * 1.2 > 0.1 + 0.3 * phase + 0.3 * branch + 0.3 * leaf ? 0 : 1)
    // Leaves fall a few at a time all over the crown, a little sooner where
    // they turned first; some twigs hold on longer than their neighbours.
    // What oak and beech keep thins out toward the top, held twig by twig.
    let keep = 0.6 * (1 - smoothstep(0.1, 0.7, top)) * (0.3 + 0.7 * branch)
    if habit.keeps && leaf < keep && (yr > 0.85 || unfold < 0.25) {
        present = 1  // held dead through winter, bleaching
        color = mixOklab(RGB(hex: 0x9a5a30), RGB(hex: 0xc0a07a), yr > 0.85 ? smoothstep(0.85, 1, yr) * 0.4 : 0.4 + 0.6 * smoothstep(0, 0.2, yr))
    }
    if species == 5 && season.blossom > 0 {
        // Fruit blossom, before the leaves: white and pink by cluster.
        let pink = patch > 0.5
        let petals = RGB(hex: pink ? 0xffcfdb : 0xfff8f4)
        if 0.3 * (1 - top) + 0.7 * leaf < season.blossom * 1.1 { (color, present) = (petals, 1) }
    }
    return (mixOklab(color * 0.45, color * 1.12, band), present)
}
