// swift-tools-version:5.9
import PackageDescription
let package = Package(
    name: "Router",
    platforms: [.macOS(.v13)],
    targets: [.executableTarget(name: "Router", path: "Sources/Router")]
)
