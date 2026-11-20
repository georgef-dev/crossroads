// swift-tools-version:6.2
import PackageDescription

// CrossroadsCore holds the rules and the view logic. It uses no Apple
// framework beyond Foundation, so `swift test` runs it without a UI or real
// accounts, and on Linux as well as on the Mac.
let package = Package(
    name: "CrossroadsCore",
    platforms: [.macOS(.v26)],
    products: [
        .library(name: "CrossroadsCore", targets: ["CrossroadsCore"]),
    ],
    targets: [
        .target(name: "CrossroadsCore"),
        .testTarget(name: "CrossroadsCoreTests", dependencies: ["CrossroadsCore"]),
    ]
)
