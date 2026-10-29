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
/// ratio (larger first) if none was; the HEIC fills the screen. macOS applies
/// it to the Space showing on that screen only. With `onlyChanges`, screens
/// already showing their file are left alone. Returns what was set.
@discardableResult
func setWallpapers(_ files: [URL], onlyChanges: Bool = false) throws -> [String] {
    let sized = files.map { url -> (url: URL, width: Int, height: Int) in
        let info = readDesktopInfo(url)
        return (url, info.width, info.height)
    }
    guard !sized.isEmpty else { return [] }
    var done: [String] = []
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
        if onlyChanges,
           NSWorkspace.shared.desktopImageURL(for: screen)?.standardizedFileURL.path == best.url.standardizedFileURL.path {
            continue
        }
        try NSWorkspace.shared.setDesktopImageURL(best.url, for: screen, options: [
            .imageScaling: NSImageScaling.scaleProportionallyUpOrDown.rawValue, .allowClipping: true,
        ])
        done.append("\(width)x\(height): \(best.url.lastPathComponent)")
    }
    return done
}

/// Keeps every desktop on today's sky. macOS can only set the Space that is
/// showing, and with full-screen apps that is often not a desktop at all; so
/// whenever you switch Spaces, wake the Mac, come back to your session or
/// change screens, each screen gets the newest sky in `dir` unless it shows
/// it already. Event-driven: no timers, asleep in between.
func follow(_ dir: URL) -> Never {
    func say(_ line: String) {
        FileHandle.standardOutput.write(Data("\(Date().formatted(.iso8601)) \(line)\n".utf8))
    }
    // sky-WIDTHxHEIGHT-yyyy-MM-dd-HHmm.heic, as daily.sh names them: the
    // newest of each size is the current sky for that size.
    func newest() -> [String: URL] {
        var best: [String: String] = [:]
        for name in (try? FileManager.default.contentsOfDirectory(atPath: dir.path)) ?? [] {
            guard name.hasPrefix("sky-"), name.hasSuffix(".heic"), name.count > 24 else { continue }
            let size = String(name.dropFirst(4).dropLast(21))
            if best[size].map({ $0.suffix(20) < name.suffix(20) }) ?? true { best[size] = name }
        }
        return best.mapValues { dir.appendingPathComponent($0) }
    }
    // A screen with no sky of its own size (new, or asleep at 00:05) gets
    // the closest one for now, and the daily job is asked to render its own;
    // at most once an hour per size, so a failing render can't loop.
    var asked: [String: Date] = [:]
    func render(_ size: String) {
        if let last = asked[size], Date().timeIntervalSince(last) < 3600 { return }
        asked[size] = Date()
        let known = dir.deletingLastPathComponent().appendingPathComponent("screens")
        let lines = ((try? String(contentsOf: known, encoding: .utf8)) ?? "").split(separator: "\n").map(String.init)
        if !lines.contains(size) {
            try? ((lines + [size]).joined(separator: "\n") + "\n").write(to: known, atomically: true, encoding: .utf8)
        }
        let job = Process()
        job.executableURL = URL(fileURLWithPath: "/bin/launchctl")
        job.arguments = ["kickstart", "gui/\(getuid())/local.sky-wallpaper"]
        do { try job.run(); say("no sky for \(size) yet; asked the daily job to render one") }
        catch { say("cannot start the daily job: \(error.localizedDescription)") }
    }
    var pending = false
    func check() {
        guard !pending else { return }
        pending = true
        // Let the switch settle first, then read what that Space shows.
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
            pending = false
            let skies = newest()
            for s in screens() where skies["\(s.width)x\(s.height)"] == nil { render("\(s.width)x\(s.height)") }
            do { try setWallpapers(Array(skies.values), onlyChanges: true).forEach { say("set \($0)") } }
            catch { say("cannot set: \(error.localizedDescription)") }
        }
    }

    // An app object, never shown, so screen changes reach this process.
    let app = NSApplication.shared
    app.setActivationPolicy(.prohibited)
    let workspace = NSWorkspace.shared.notificationCenter
    for name in [NSWorkspace.activeSpaceDidChangeNotification, NSWorkspace.didWakeNotification,
                 NSWorkspace.screensDidWakeNotification, NSWorkspace.sessionDidBecomeActiveNotification] {
        workspace.addObserver(forName: name, object: nil, queue: .main) { _ in check() }
    }
    NotificationCenter.default.addObserver(forName: NSApplication.didChangeScreenParametersNotification,
                                           object: nil, queue: .main) { _ in check() }
    say("following \(dir.path)")
    check()
    app.run()
    exit(0)
}

/// Wallpaper files the system still points at, on any Space or display.
/// NSWorkspace only sets the current Space, so others keep older files;
/// this says which are safe to delete. It reads the wallpaper store, a
/// private format: nil when that fails, and then nothing should be deleted.
func wallpapersInUse() -> Set<String>? {
    let store = FileManager.default.homeDirectoryForCurrentUser
        .appendingPathComponent("Library/Application Support/com.apple.wallpaper/Store/Index.plist")
    guard let data = try? Data(contentsOf: store),
          let root = try? PropertyListSerialization.propertyList(from: data, format: nil) else { return nil }
    var paths = Set<String>()
    func walk(_ node: Any) {
        if let dict = node as? [String: Any] {
            if let blob = dict["Configuration"] as? Data,
               let config = try? PropertyListSerialization.propertyList(from: blob, format: nil) as? [String: Any],
               let url = (config["url"] as? [String: Any])?["relative"] as? String,
               let path = URL(string: url)?.path {
                paths.insert(path)
            }
            dict.values.forEach(walk)
        } else if let array = node as? [Any] {
            array.forEach(walk)
        }
    }
    walk(root)
    return paths
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
