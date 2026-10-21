// swift-tools-version:5.9
import PackageDescription

let package = Package(
    name: "wallpaper",
    platforms: [.macOS(.v14)],
    targets: [
        .executableTarget(name: "wallframes"),
        .executableTarget(name: "heicpack"),
    ]
)
