// swift-tools-version: 6.2
import PackageDescription

// PigeonCore is the app's portable, dependency-free logic: where you are on a saved route, whether
// you have left it, and how much help each drive gives. It builds on Apple platforms and on Linux,
// so its tests run without Xcode (tools/swift.sh test, and CI's `core` job).
let package = Package(
    name: "PigeonCore",
    platforms: [.iOS("26.0"), .macOS("15.0")],
    products: [
        .library(name: "PigeonCore", targets: ["PigeonCore"]),
    ],
    targets: [
        .target(name: "PigeonCore"),
        .testTarget(name: "PigeonCoreTests", dependencies: ["PigeonCore"]),
    ],
    swiftLanguageModes: [.v6]
)
