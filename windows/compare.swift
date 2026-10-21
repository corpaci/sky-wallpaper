// compare.swift SWIFT_DIR CSHARP_DIR — pixel-compare two frame sets by file
// name, plus their manifest schedules. Used by parity.sh; macOS only.
// Exits 1 if any channel differs by more than 2 or more than 1% of channel
// values differ at all: float rounding may nudge the odd value by one step,
// but a real divergence between the renderers shows up as more.

import Foundation
import ImageIO

func pixels(_ path: String) -> (Int, Int, [UInt8]) {
    guard let src = CGImageSourceCreateWithURL(URL(fileURLWithPath: path) as CFURL, nil),
          let image = CGImageSourceCreateImageAtIndex(src, 0, nil) else { fatalError("cannot decode \(path)") }
    let (w, h) = (image.width, image.height)
    var buf = [UInt8](repeating: 0, count: w * h * 4)
    let ctx = CGContext(data: &buf, width: w, height: h, bitsPerComponent: 8, bytesPerRow: w * 4,
                        space: CGColorSpace(name: CGColorSpace.sRGB)!,
                        bitmapInfo: CGImageAlphaInfo.noneSkipLast.rawValue)!
    ctx.draw(image, in: CGRect(x: 0, y: 0, width: w, height: h))
    return (w, h, buf)
}

func schedule(_ dir: String) -> [String] {
    let text = (try? String(contentsOfFile: dir + "/manifest.txt", encoding: .utf8)) ?? ""
    return text.split(separator: "\n").filter { !$0.hasPrefix("#") }.map { String($0) }
}

let args = CommandLine.arguments
guard args.count == 3 else { fatalError("usage: compare.swift SWIFT_DIR CSHARP_DIR") }
let (a, b) = (args[1], args[2])
var ok = true

if schedule(a) != schedule(b) {
    print("schedules differ:\n  swift: \(schedule(a))\n  c#:    \(schedule(b))")
    ok = false
}
let names = (try? FileManager.default.contentsOfDirectory(atPath: a))?.filter { $0.hasSuffix(".png") }.sorted() ?? []
if names.isEmpty { print("no frames in \(a)"); ok = false }
for name in names {
    let (w1, h1, p1) = pixels(a + "/" + name)
    guard FileManager.default.fileExists(atPath: b + "/" + name) else { print("\(name): missing from C# set"); ok = false; continue }
    let (w2, h2, p2) = pixels(b + "/" + name)
    guard (w1, h1) == (w2, h2) else { print("\(name): \(w1)x\(h1) vs \(w2)x\(h2)"); ok = false; continue }
    var differing = 0, worst = 0, total = 0
    for i in stride(from: 0, to: p1.count, by: 4) {
        for c in 0..<3 {
            let d = abs(Int(p1[i + c]) - Int(p2[i + c]))
            if d > 0 { differing += 1 }
            worst = max(worst, d)
            total += 1
        }
    }
    let share = Double(differing) / Double(total) * 100
    let pass = worst <= 2 && share <= 1
    ok = ok && pass
    print(String(format: "%@  %@  %.3f%% of values differ, max %d", pass ? "ok  " : "FAIL", name, share, worst))
}
print(ok ? "parity: ok" : "parity: FAILED")
exit(ok ? 0 : 1)
