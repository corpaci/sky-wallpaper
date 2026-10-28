// wallframes — render one day of landscape frames for a dynamic wallpaper.
//
//   wallframes [--size 2560x1664] [--seed 7] [--out frames] [--dry-run]
//              [--sunrise 07:20 --sunset 17:55 | --lat 48.2 --lon 16.4
//               [--date yyyy-MM-dd] [--utc-offset MINUTES]]
//
// Writes one PNG per frame plus manifest.txt, the input heicpack expects.
// Frames sit at fixed sun altitudes, so they bunch up around sunrise and
// sunset, where the sky changes fastest. With --lat/--lon the day's real
// sunrise and sunset are computed (for today unless --date says otherwise);
// otherwise the fixed times apply. --dry-run prints the schedule only.

import Foundation
import ImageIO
import UniformTypeIdentifiers

let usage = """
    usage: wallframes [--size WIDTHxHEIGHT] [--seed N] [--out DIR] [--dry-run]
                      [--sunrise HH:MM --sunset HH:MM | --lat DEG --lon DEG
                       [--date yyyy-MM-dd] [--utc-offset MINUTES]]
    """

func fail(_ msg: String) -> Never {
    FileHandle.standardError.write(Data("wallframes: \(msg)\n".utf8))
    exit(1)
}

func parseClock(_ s: String) -> Int? {
    let parts = s.split(separator: ":")
    guard parts.count == 2, let h = Int(parts[0]), let m = Int(parts[1]),
          (0..<24).contains(h), (0..<60).contains(m) else { return nil }
    return h * 60 + m
}

func clock(_ minute: Int) -> String { String(format: "%02d:%02d", minute / 60, minute % 60) }

func writePNG(_ rgbx: [UInt8], width: Int, height: Int, to url: URL) {
    guard let provider = CGDataProvider(data: Data(rgbx) as CFData),
          let image = CGImage(width: width, height: height, bitsPerComponent: 8, bitsPerPixel: 32,
                              bytesPerRow: width * 4, space: CGColorSpace(name: CGColorSpace.sRGB)!,
                              bitmapInfo: CGBitmapInfo(rawValue: CGImageAlphaInfo.noneSkipLast.rawValue),
                              provider: provider, decode: nil, shouldInterpolate: false, intent: .defaultIntent),
          let dest = CGImageDestinationCreateWithURL(url as CFURL, UTType.png.identifier as CFString, 1, nil)
    else { fail("cannot write \(url.path)") }
    CGImageDestinationAddImage(dest, image, nil)
    guard CGImageDestinationFinalize(dest) else { fail("cannot write \(url.path)") }
}

var width = 2560, height = 1664, sunrise = 7 * 60 + 20, sunset = 17 * 60 + 55
var seed: UInt32 = 7, outDir = "frames", dryRun = false
var latitude: Double?, longitude: Double?, date: String?, utcOffset: Int?
var args = CommandLine.arguments.dropFirst()
while let flag = args.popFirst() {
    if flag == "-h" || flag == "--help" { print(usage); exit(0) }
    if flag == "--dry-run" { dryRun = true; continue }
    guard let value = args.popFirst() else { fail("\(flag) needs a value\n\(usage)") }
    switch flag {
    case "--size":
        let wh = value.split(separator: "x").compactMap { Int($0) }
        guard wh.count == 2, wh.allSatisfy({ (64...16384).contains($0) }) else { fail("--size wants WIDTHxHEIGHT") }
        (width, height) = (wh[0], wh[1])
    case "--sunrise":
        guard let m = parseClock(value) else { fail("--sunrise wants HH:MM") }
        sunrise = m
    case "--sunset":
        guard let m = parseClock(value) else { fail("--sunset wants HH:MM") }
        sunset = m
    case "--seed":
        guard let s = UInt32(value) else { fail("--seed wants a whole number") }
        seed = s
    case "--out": outDir = value
    case "--lat":
        guard let v = Double(value), (-90...90).contains(v) else { fail("--lat wants degrees north, -90 to 90") }
        latitude = v
    case "--lon":
        guard let v = Double(value), (-180...180).contains(v) else { fail("--lon wants degrees east, -180 to 180") }
        longitude = v
    case "--date": date = value
    case "--utc-offset":
        guard let v = Int(value), (-14 * 60...14 * 60).contains(v) else { fail("--utc-offset wants minutes, e.g. 60") }
        utcOffset = v
    default: fail("unknown flag \(flag)\n\(usage)")
    }
}
var dayNote = ""
if latitude != nil || longitude != nil {
    guard let latitude, let longitude else { fail("--lat and --lon go together") }
    let today = Calendar.current.dateComponents([.year, .month, .day], from: Date())
    let day = date ?? String(format: "%04d-%02d-%02d", today.year!, today.month!, today.day!)
    guard let d = Daylight(latitude: latitude, longitude: longitude, date: day, utcOffset: utcOffset)
    else { fail("--date wants yyyy-MM-dd") }
    (sunrise, sunset) = (d.sunrise, d.sunset)
    dayNote = " on \(day) at \(latitude), \(longitude)" + (d.note.map { " (\($0))" } ?? "")
}
guard sunset - sunrise >= 120 else { fail("sunset must be at least two hours after sunrise") }

struct Frame {
    let label: String
    let minute: Int
    var flags: [String] = []
}

let sun = SunModel(sunrise: sunrise, sunset: sunset)
let morning: [(String, Float)] = [("night-end", -14), ("blue-hour", -7), ("dawn", -3),
                                  ("sunrise", 0.5), ("golden", 5), ("morning", 14)]
let evening: [(String, Float)] = [("afternoon", 14), ("golden-eve", 5), ("sunset", 0.5),
                                  ("dusk", -3), ("blue-hour-eve", -7), ("night", -14)]
var frames = [Frame(label: "midnight", minute: sun.midnight, flags: ["dark"]),
              Frame(label: "noon", minute: sun.noon, flags: ["light"])]
frames += morning.map { Frame(label: $0.0, minute: sun.minute(at: $0.1, evening: false)) }
frames += evening.map { Frame(label: $0.0, minute: sun.minute(at: $0.1, evening: true), flags: $0.0 == "sunset" ? ["primary"] : []) }
frames.sort { $0.minute < $1.minute }
for (a, b) in zip(frames, frames.dropFirst()) where a.minute == b.minute {
    fail("\(a.label) and \(b.label) both land on \(clock(a.minute)); day or night too short for this schedule")
}

let header = "# wallframes \(width)x\(height), sunrise \(clock(sunrise)), sunset \(clock(sunset))\(dayNote), seed \(seed)"
if dryRun {
    print(header)
    for frame in frames { print("\(clock(frame.minute))  \(frame.label)") }
    exit(0)
}

let dir = URL(fileURLWithPath: outDir)
do { try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true) }
catch { fail("cannot create \(dir.path): \(error.localizedDescription)") }

let start = Date()
let scene = Scene(width: width, height: height, seed: seed)
print(String(format: "scene %dx%d, seed %u: %.2fs", width, height, seed, Date().timeIntervalSince(start)))

var manifest = """
    \(header)
    # HH:MM  file  [primary] [light] [dark]

    """
for (i, frame) in frames.enumerated() {
    let t0 = Date()
    let name = String(format: "%02d-%@.png", i, frame.label)
    let pixels = scene.render(minute: frame.minute, sun: sun, salt: hash32(UInt32(i) &+ seed))
    writePNG(pixels, width: width, height: height, to: dir.appendingPathComponent(name))
    manifest += "\(clock(frame.minute))  \(name)\(frame.flags.isEmpty ? "" : "  " + frame.flags.joined(separator: " "))\n"
    print(String(format: "%@  %@  sun %+5.1f°  %.2fs", clock(frame.minute), name,
                 sun.altitude(frame.minute), Date().timeIntervalSince(t0)))
}
do { try manifest.write(to: dir.appendingPathComponent("manifest.txt"), atomically: true, encoding: .utf8) }
catch { fail("cannot write manifest: \(error.localizedDescription)") }
print("\(frames.count) frames → \(dir.path)/manifest.txt")
