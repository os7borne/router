// swift-tools-version:5.9
import PackageDescription
let package = Package(
    name: "Router",
    platforms: [.macOS(.v13)],
    dependencies: [.package(url: "https://github.com/sparkle-project/Sparkle", from: "2.6.4")],
    targets: [
        .executableTarget(
            name: "Router",
            dependencies: [.product(name: "Sparkle", package: "Sparkle")],
            path: "Sources/Router",
            // Lets the app find Sparkle.framework inside Router.app/Contents/Frameworks.
            linkerSettings: [.unsafeFlags(["-Xlinker", "-rpath", "-Xlinker", "@executable_path/../Frameworks"])]
        )
    ]
)
