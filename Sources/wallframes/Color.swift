import Foundation

/// Linear-light RGB. Light adds here; palettes blend in OKLab; sRGB encoding
/// happens once, at quantization.
struct RGB {
    var r: Float, g: Float, b: Float

    init(_ r: Float, _ g: Float, _ b: Float) { (self.r, self.g, self.b) = (r, g, b) }

    /// From an sRGB hex literal such as 0xffb36b.
    init(hex: UInt32) {
        self.init(srgbToLinear(Float(hex >> 16 & 0xff) / 255),
                  srgbToLinear(Float(hex >> 8 & 0xff) / 255),
                  srgbToLinear(Float(hex & 0xff) / 255))
    }

    static func + (x: RGB, y: RGB) -> RGB { RGB(x.r + y.r, x.g + y.g, x.b + y.b) }
    static func * (x: RGB, k: Float) -> RGB { RGB(x.r * k, x.g * k, x.b * k) }
}

@inline(__always) func lerp(_ a: Float, _ b: Float, _ t: Float) -> Float { a + (b - a) * t }
@inline(__always) func mix(_ x: RGB, _ y: RGB, _ t: Float) -> RGB {
    RGB(lerp(x.r, y.r, t), lerp(x.g, y.g, t), lerp(x.b, y.b, t))
}
@inline(__always) func clamp01(_ x: Float) -> Float { min(max(x, 0), 1) }
/// Hermite step; edges may be given high-to-low for a falling step.
@inline(__always) func smoothstep(_ e0: Float, _ e1: Float, _ x: Float) -> Float {
    let t = clamp01((x - e0) / (e1 - e0))
    return t * t * (3 - 2 * t)
}

func srgbToLinear(_ c: Float) -> Float { c <= 0.04045 ? c / 12.92 : powf((c + 0.055) / 1.055, 2.4) }
func linearToSrgb(_ c: Float) -> Float { c <= 0.0031308 ? c * 12.92 : 1.055 * powf(c, 1 / 2.4) - 0.055 }

/// Blend in OKLab (Björn Ottosson, 2020): perceptually even, so a navy→peach
/// sky does not pass through the gray mud that linear-RGB blending gives.
func mixOklab(_ x: RGB, _ y: RGB, _ t: Float) -> RGB {
    let a = toOklab(x), b = toOklab(y)
    return fromOklab((lerp(a.0, b.0, t), lerp(a.1, b.1, t), lerp(a.2, b.2, t)))
}

/// Toward grey at the same lightness: OKLab chroma scaled down by `t`.
func desaturate(_ c: RGB, _ t: Float) -> RGB {
    let l = toOklab(c)
    return fromOklab((l.0, l.1 * (1 - t), l.2 * (1 - t)))
}

private func toOklab(_ c: RGB) -> (Float, Float, Float) {
    let l = cbrtf(0.4122214708 * c.r + 0.5363325363 * c.g + 0.0514459929 * c.b)
    let m = cbrtf(0.2119034982 * c.r + 0.6806995451 * c.g + 0.1073969566 * c.b)
    let s = cbrtf(0.0883024619 * c.r + 0.2817188376 * c.g + 0.6299787005 * c.b)
    return (0.2104542553 * l + 0.7936177850 * m - 0.0040720468 * s,
            1.9779984951 * l - 2.4285922050 * m + 0.4505937099 * s,
            0.0259040371 * l + 0.7827717662 * m - 0.8086757660 * s)
}

private func fromOklab(_ c: (Float, Float, Float)) -> RGB {
    let l = c.0 + 0.3963377774 * c.1 + 0.2158037573 * c.2
    let m = c.0 - 0.1055613458 * c.1 - 0.0638541728 * c.2
    let s = c.0 - 0.0894841775 * c.1 - 1.2914855480 * c.2
    let (l3, m3, s3) = (l * l * l, m * m * m, s * s * s)
    return RGB(4.0767416621 * l3 - 3.3077115913 * m3 + 0.2309699292 * s3,
               -1.2684380046 * l3 + 2.6097574011 * m3 - 0.3413193965 * s3,
               -0.0041960863 * l3 - 0.7034186147 * m3 + 1.7076147010 * s3)
}

// MARK: - Deterministic noise

@inline(__always) func hash32(_ v: UInt32) -> UInt32 {
    var x = v
    x ^= x >> 16; x &*= 0x7feb352d
    x ^= x >> 15; x &*= 0x846ca68b
    x ^= x >> 16
    return x
}

@inline(__always) func unit(_ h: UInt32) -> Float { Float(h >> 8) / 16_777_216 }

/// 1-D value noise in [-1, 1] with quintic interpolation.
func valueNoise(_ u: Float, _ seed: UInt32) -> Float {
    let i = floorf(u), f = u - i
    let t = f * f * f * (f * (f * 6 - 15) + 10)
    let k = UInt32(bitPattern: Int32(i))
    let a = unit(hash32(k &* 0x9e3779b1 ^ seed)) * 2 - 1
    let b = unit(hash32((k &+ 1) &* 0x9e3779b1 ^ seed)) * 2 - 1
    return lerp(a, b, t)
}

/// Fractal sum of value noise, normalized to roughly [-1, 1].
func fbm(_ u: Float, octaves: Int, seed: UInt32) -> Float {
    var sum: Float = 0, amp: Float = 1, norm: Float = 0, freq: Float = 1
    for k in 0..<octaves {
        sum += amp * valueNoise(u * freq + Float(k) * 17.31, seed &+ UInt32(k) &* 1013)
        norm += amp
        amp *= 0.5
        freq *= 2.03
    }
    return sum / norm
}

/// 2-D value noise in [-1, 1] with quintic interpolation.
func valueNoise2(_ u: Float, _ v: Float, _ seed: UInt32) -> Float {
    let i = floorf(u), j = floorf(v)
    let fu = u - i, fv = v - j
    let tu = fu * fu * fu * (fu * (fu * 6 - 15) + 10)
    let tv = fv * fv * fv * (fv * (fv * 6 - 15) + 10)
    let ki = UInt32(bitPattern: Int32(i)), kj = UInt32(bitPattern: Int32(j))
    func corner(_ a: UInt32, _ b: UInt32) -> Float {
        unit(hash32((a &* 0x9e3779b1) ^ (b &* 0x85ebca6b) ^ seed)) * 2 - 1
    }
    let top = lerp(corner(ki, kj), corner(ki &+ 1, kj), tu)
    let bottom = lerp(corner(ki, kj &+ 1), corner(ki &+ 1, kj &+ 1), tu)
    return lerp(top, bottom, tv)
}

/// Fractal sum of 2-D value noise, normalized to roughly [-1, 1].
func fbm2(_ u: Float, _ v: Float, octaves: Int, seed: UInt32) -> Float {
    var sum: Float = 0, amp: Float = 1, norm: Float = 0, freq: Float = 1
    for k in 0..<octaves {
        sum += amp * valueNoise2(u * freq + Float(k) * 17.31, v * freq + Float(k) * 9.77, seed &+ UInt32(k) &* 1013)
        norm += amp
        amp *= 0.5
        freq *= 2.03
    }
    return sum / norm
}

/// Ridged multifractal (Musgrave): creased octaves, each weighted by the one
/// before, so detail gathers on the crests the way it does on real ranges.
/// Roughly [0, 0.8].
func ridged(_ u: Float, octaves: Int, seed: UInt32) -> Float {
    var sum: Float = 0, amp: Float = 1, norm: Float = 0, freq: Float = 1, weight: Float = 1
    for k in 0..<octaves {
        var r = 1 - abs(valueNoise(u * freq + Float(k) * 17.31, seed &+ UInt32(k) &* 1013))
        r = r * r * weight
        weight = clamp01(r * 1.6)
        sum += amp * r
        norm += amp
        amp *= 0.5
        freq *= 2.1
    }
    return sum / norm
}

struct SplitMix {
    var state: UInt64
    mutating func next() -> UInt64 {
        state &+= 0x9e3779b97f4a7c15
        var z = state
        z = (z ^ (z >> 30)) &* 0xbf58476d1ce4e5b9
        z = (z ^ (z >> 27)) &* 0x94d049bb133111eb
        return z ^ (z >> 31)
    }
    mutating func unit() -> Float { Float(next() >> 40) / 16_777_216 }
}
