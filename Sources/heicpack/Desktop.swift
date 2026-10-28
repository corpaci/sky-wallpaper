// The Mac's wallpaper, per screen, through NSWorkspace: what the daily job
// uses to put a freshly packed HEIC up, and to put the old one back.

import AppKit

/// Each screen with its size in pixels (points × backing scale).
func screens() -> [(screen: NSScreen, width: Int, height: Int)] {
    NSScreen.screens.map { s in
        (s, Int((s.frame.width * s.backingScaleFactor).rounded()), Int((s.frame.height * s.backingScaleFactor).rounded()))
    }
}

/// Screens are told apart by display id; that survives a reboot, unlike order.
func displayID(_ screen: NSScreen) -> String {
    (screen.deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? NSNumber)?.stringValue ?? "?"
}

/// Sets each screen to the wallpaper made for its size, or the closest aspect
/// ratio (larger first) if none was; the HEIC fills the screen.
func setWallpapers(_ files: [URL]) {
    let sized = files.map { url -> (url: URL, width: Int, height: Int) in
        let info = readDesktopInfo(url)
        return (url, info.width, info.height)
    }
    guard !sized.isEmpty else { fail("--set needs at least one file") }
    for (screen, width, height) in screens() {
        let aspect = log(Double(width) / Double(height))
        let best = sized.min { a, b in
            func key(_ f: (url: URL, width: Int, height: Int)) -> (Int, Double, Int) {
                ((f.width, f.height) == (width, height) ? 0 : 1,
                 (abs(log(Double(f.width) / Double(f.height)) - aspect) * 1000).rounded() / 1000,
                 -f.width * f.height)
            }
            return key(a) < key(b)
        }!
        do {
            try NSWorkspace.shared.setDesktopImageURL(best.url, for: screen, options: [
                .imageScaling: NSImageScaling.scaleProportionallyUpOrDown.rawValue, .allowClipping: true,
            ])
        } catch { fail("cannot set the wallpaper on \(width)x\(height): \(error.localizedDescription)") }
        print("\(width)x\(height): \(best.url.lastPathComponent)")
    }
}

/// Current wallpapers, one `display-id<TAB>path` line per screen.
func saveWallpapers(to file: URL) {
    let lines = screens().compactMap { s in
        NSWorkspace.shared.desktopImageURL(for: s.screen).map { "\(displayID(s.screen))\t\($0.path)" }
    }
    do { try (lines.joined(separator: "\n") + "\n").write(to: file, atomically: true, encoding: .utf8) }
    catch { fail("cannot write \(file.path): \(error.localizedDescription)") }
}

/// Puts back what `saveWallpapers` recorded, where the screen and file still exist.
func restoreWallpapers(from file: URL) {
    guard let text = try? String(contentsOf: file, encoding: .utf8) else { fail("cannot read \(file.path)") }
    var saved: [String: String] = [:]
    for line in text.split(separator: "\n") {
        let f = line.split(separator: "\t", maxSplits: 1).map(String.init)
        if f.count == 2 { saved[f[0]] = f[1] }
    }
    for s in screens() {
        guard let path = saved[displayID(s.screen)] else { print("\(s.width)x\(s.height): nothing saved"); continue }
        guard FileManager.default.fileExists(atPath: path) else { print("\(s.width)x\(s.height): \(path) is gone"); continue }
        do { try NSWorkspace.shared.setDesktopImageURL(URL(fileURLWithPath: path), for: s.screen, options: [:]) }
        catch { fail("cannot restore \(path): \(error.localizedDescription)") }
        print("\(s.width)x\(s.height): restored \(path)")
    }
}
