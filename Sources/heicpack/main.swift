// heicpack — pack still images into a time-of-day (h24) dynamic wallpaper.
//
//   heicpack MANIFEST -o OUT.heic [--quality 0.95]
//   heicpack --inspect FILE.heic...
//   heicpack --screens | --set FILE.heic... | --in-use | --follow DIR
//   heicpack --save FILE | --restore FILE
//
// The manifest has one line per switch time, `HH:MM  path  [flags]`, in local
// wall-clock time; each image shows from its time until the next one. Flags:
// `primary` (the still Finder and Settings show), `light` and `dark` (the
// stills macOS uses for its Light/Dark options). `#` starts a comment; paths
// are relative to the manifest and may repeat (the image is stored once).
//
// Format: macOS reads XMP `apple_desktop:h24` on the first image, a base64
// binary plist {ti: [{t: fraction of day, i: image index}], ap: {l, d}}.
// Namespace and the l/d keys verified against /System/Library/Desktop
// Pictures/Sonoma.heic on macOS 26.6; ti/t/i and local-clock `t` follow the
// wallpapper project's encoder, since macOS ships its own h24 wallpapers as
// on-demand downloads with nothing to inspect on disk.

import Foundation
import ImageIO
import UniformTypeIdentifiers

let usage = """
    usage: heicpack MANIFEST -o OUT.heic [--quality 0.1–1.0, default 0.95]
           heicpack --inspect FILE.heic...
           heicpack --screens                each screen's size in pixels
           heicpack --set FILE.heic...       each screen gets the file for its size
           heicpack --in-use                 wallpaper files any Space still points at
           heicpack --follow DIR             keep each desktop on DIR's newest sky
           heicpack --save FILE | --restore FILE   remember / put back the wallpapers
    """

let desktopNS = "http://ns.apple.com/namespace/1.0/" as CFString
let desktopPrefix = "apple_desktop" as CFString
let knownFlags: Set<String> = ["primary", "light", "dark"]

func fail(_ msg: String) -> Never {
    FileHandle.standardError.write(Data("heicpack: \(msg)\n".utf8))
    exit(1)
}

func parseClock(_ s: String) -> Int? {
    let parts = s.split(separator: ":")
    guard parts.count == 2, let h = Int(parts[0]), let m = Int(parts[1]),
          (0..<24).contains(h), (0..<60).contains(m) else { return nil }
    return h * 60 + m
}

func clock(_ minute: Int) -> String { String(format: "%02d:%02d", minute / 60 % 24, minute % 60) }

// MARK: - Manifest

struct Entry {
    let minute: Int
    let path: String
    let flags: Set<String>
    let line: Int
}

func parseManifest(_ text: String) -> [Entry] {
    var entries: [Entry] = []
    for (n, raw) in text.components(separatedBy: .newlines).enumerated() {
        var line = String(raw.prefix { $0 != "#" }).trimmingCharacters(in: .whitespaces)
        if line.isEmpty { continue }
        let at = "manifest line \(n + 1)"
        guard let gap = line.firstIndex(where: \.isWhitespace) else { fail("\(at): want `HH:MM path [flags]`") }
        guard let minute = parseClock(String(line[..<gap])) else { fail("\(at): bad time '\(line[..<gap])', want HH:MM") }
        line = line[gap...].trimmingCharacters(in: .whitespaces)
        // Flags come off the end, so paths may contain spaces.
        var flags = Set<String>()
        while let space = line.lastIndex(where: \.isWhitespace),
              case let word = String(line[line.index(after: space)...]), knownFlags.contains(word) {
            flags.insert(word)
            line = line[..<space].trimmingCharacters(in: .whitespaces)
        }
        entries.append(Entry(minute: minute, path: line, flags: flags, line: n + 1))
    }
    return entries
}

func validate(_ entries: [Entry]) {
    guard entries.count >= 2 else { fail("need at least two entries, found \(entries.count)") }
    var seen: [Int: Int] = [:]
    for e in entries {
        if let prev = seen[e.minute] { fail("line \(e.line): \(clock(e.minute)) already used on line \(prev)") }
        seen[e.minute] = e.line
    }
    for flag in knownFlags.sorted() {
        let lines = entries.filter { $0.flags.contains(flag) }.map(\.line)
        if lines.count > 1 { fail("`\(flag)` is on lines \(lines); use it at most once") }
    }
    let light = entries.contains { $0.flags.contains("light") }
    let dark = entries.contains { $0.flags.contains("dark") }
    if light != dark { fail("mark both a `light` and a `dark` image, or neither") }
}

// MARK: - Reading back

struct DesktopInfo {
    var count = 0, width = 0, height = 0
    var tags: [String: Any] = [:]  // apple_desktop tag name → decoded plist
}

func readDesktopInfo(_ url: URL) -> DesktopInfo {
    guard let src = CGImageSourceCreateWithURL(url as CFURL, nil) else { fail("cannot open \(url.path)") }
    var info = DesktopInfo()
    info.count = CGImageSourceGetCount(src)
    let props = CGImageSourceCopyPropertiesAtIndex(src, 0, nil) as? [CFString: Any]
    info.width = props?[kCGImagePropertyPixelWidth] as? Int ?? 0
    info.height = props?[kCGImagePropertyPixelHeight] as? Int ?? 0
    guard let meta = CGImageSourceCopyMetadataAtIndex(src, 0, nil),
          let tags = CGImageMetadataCopyTags(meta) as? [CGImageMetadataTag] else { return info }
    for tag in tags where CGImageMetadataTagCopyPrefix(tag) as String? == "apple_desktop" {
        guard let name = CGImageMetadataTagCopyName(tag) as String? else { continue }
        let b64 = CGImageMetadataTagCopyValue(tag) as? String ?? ""
        let value = Data(base64Encoded: b64).flatMap { try? PropertyListSerialization.propertyList(from: $0, format: nil) }
        info.tags[name] = value ?? "<undecodable: \(b64.prefix(40))…>"
    }
    return info
}

func describe(_ url: URL) {
    let info = readDesktopInfo(url)
    print("\(url.path): \(info.count) image(s), \(info.width)x\(info.height)")
    if info.tags.isEmpty { print("  no apple_desktop metadata: a plain still") }
    for (name, value) in info.tags.sorted(by: { $0.key < $1.key }) {
        switch (name, value) {
        case ("h24", let d as [String: Any]):
            print("  h24, local clock:")
            for item in d["ti"] as? [[String: Any]] ?? [] {
                let t = item["t"] as? Double ?? .nan
                print("    \(t.isNaN ? "??:??" : clock(Int((t * 1440).rounded())))  image \(item["i"] ?? "?")")
            }
            if let ap = d["ap"] as? [String: Any] { print("  light: image \(ap["l"] ?? "?"), dark: image \(ap["d"] ?? "?")") }
        case ("apr", let d as [String: Any]):
            print("  apr: light image \(d["l"] ?? "?"), dark image \(d["d"] ?? "?")")
        default:
            print("  \(name): \(value)")
        }
    }
}

// MARK: - Packing

func pack(manifest: URL, output: URL, quality: Double) {
    guard let text = try? String(contentsOf: manifest, encoding: .utf8) else { fail("cannot read \(manifest.path)") }
    let entries = parseManifest(text)
    validate(entries)

    // File order: primary first, then first appearance; repeats share an index.
    var order = entries.filter { $0.flags.contains("primary") }.map(\.path)
    for e in entries where !order.contains(e.path) { order.append(e.path) }
    let index = Dictionary(uniqueKeysWithValues: order.enumerated().map { ($1, $0) })

    let base = manifest.deletingLastPathComponent()
    let images: [CGImage] = order.map { path in
        let url = path.hasPrefix("/") ? URL(fileURLWithPath: path) : base.appendingPathComponent(path)
        guard let src = CGImageSourceCreateWithURL(url as CFURL, nil),
              let image = CGImageSourceCreateImageAtIndex(src, 0, nil) else { fail("cannot decode \(url.path)") }
        return image
    }
    let (w, h) = (images[0].width, images[0].height)
    for (path, image) in zip(order, images) where image.width != w || image.height != h {
        fail("\(path) is \(image.width)x\(image.height) but \(order[0]) is \(w)x\(h); frames must match")
    }

    var plist: [String: Any] = [
        "ti": entries.sorted { $0.minute < $1.minute }.map {
            ["t": Double($0.minute) / 1440, "i": index[$0.path]!] as [String: Any]
        },
    ]
    if let light = entries.first(where: { $0.flags.contains("light") }),
       let dark = entries.first(where: { $0.flags.contains("dark") }) {
        plist["ap"] = ["l": index[light.path]!, "d": index[dark.path]!]
    }
    guard let data = try? PropertyListSerialization.data(fromPropertyList: plist, format: .binary, options: 0)
    else { fail("cannot encode the h24 plist") }

    let meta = CGImageMetadataCreateMutable()
    guard CGImageMetadataRegisterNamespaceForPrefix(meta, desktopNS, desktopPrefix, nil),
          let tag = CGImageMetadataTagCreate(desktopNS, desktopPrefix, "h24" as CFString, .string,
                                             data.base64EncodedString() as CFString),
          CGImageMetadataSetTagWithPath(meta, nil, "apple_desktop:h24" as CFString, tag)
    else { fail("cannot build XMP metadata") }

    // Write beside the target, then move: a half-written wallpaper never exists.
    let partial = output.deletingLastPathComponent().appendingPathComponent(".\(output.lastPathComponent).partial")
    guard let dest = CGImageDestinationCreateWithURL(partial as CFURL, UTType.heic.identifier as CFString, images.count, nil)
    else { fail("this Mac cannot write HEIC to \(partial.path)") }
    let options = [kCGImageDestinationLossyCompressionQuality: quality] as CFDictionary
    CGImageDestinationAddImageAndMetadata(dest, images[0], meta, options)
    for image in images.dropFirst() { CGImageDestinationAddImage(dest, image, options) }
    guard CGImageDestinationFinalize(dest) else { fail("HEIC encoding failed") }
    do {
        if FileManager.default.fileExists(atPath: output.path) { try FileManager.default.removeItem(at: output) }
        try FileManager.default.moveItem(at: partial, to: output)
    } catch { fail("cannot move into place: \(error.localizedDescription)") }

    // Read it back the way macOS will before calling it done.
    let back = readDesktopInfo(output)
    guard back.count == images.count,
          let ti = (back.tags["h24"] as? [String: Any])?["ti"] as? [[String: Any]], ti.count == entries.count,
          ti.allSatisfy({ ($0["i"] as? Int).map { $0 < back.count } ?? false })
    else { fail("wrote \(output.path) but the read-back check failed; do not install it") }
    let bytes = (try? FileManager.default.attributesOfItem(atPath: output.path)[.size] as? Int) ?? 0
    print(String(format: "%@: %d images, %d switch times, %dx%d, %.1f MB",
                 output.path, back.count, ti.count, w, h, Double(bytes) / 1e6))
}

// MARK: - Main

var args = CommandLine.arguments.dropFirst()
switch args.first {
case "--inspect":
    guard args.count > 1 else { fail(usage) }
    args.dropFirst().forEach { describe(URL(fileURLWithPath: $0)) }
    exit(0)
case "--screens":
    screens().forEach { print("\($0.width)x\($0.height)") }
    exit(0)
case "--set":
    guard args.count > 1 else { fail("--set needs at least one file") }
    do { try setWallpapers(args.dropFirst().map { URL(fileURLWithPath: $0) }).forEach { print($0) } }
    catch { fail("cannot set the wallpaper: \(error.localizedDescription)") }
    exit(0)
case "--follow":
    guard args.count == 2, let dir = args.last else { fail(usage) }
    follow(URL(fileURLWithPath: dir))
case "--in-use":
    guard let paths = wallpapersInUse() else { fail("cannot read the wallpaper store") }
    paths.sorted().forEach { print($0) }
    exit(0)
case "--save", "--restore":
    guard args.count == 2, let file = args.last.map({ URL(fileURLWithPath: $0) }) else { fail(usage) }
    if args.first == "--save" { saveWallpapers(to: file) } else { restoreWallpapers(from: file) }
    exit(0)
default:
    break
}
var manifestPath: String?, outputPath: String?, quality = 0.95
while let arg = args.popFirst() {
    switch arg {
    case "-o", "--output":
        guard let path = args.popFirst() else { fail("-o needs a path") }
        outputPath = path
    case "-q", "--quality":
        guard let q = args.popFirst().flatMap(Double.init), (0.1...1).contains(q) else { fail("--quality wants 0.1–1.0") }
        quality = q
    case "-h", "--help":
        print(usage)
        exit(0)
    default:
        guard manifestPath == nil, !arg.hasPrefix("-") else { fail("unexpected argument \(arg)\n\(usage)") }
        manifestPath = arg
    }
}
guard let manifestPath, let outputPath else { fail(usage) }
pack(manifest: URL(fileURLWithPath: manifestPath), output: URL(fileURLWithPath: outputPath), quality: quality)
