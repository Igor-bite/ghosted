// swift-tools-version:5.9
import PackageDescription

let package = Package(
    name: "VanishCore",
    platforms: [.macOS(.v13)],
    products: [.library(name: "VanishCore", targets: ["VanishCore"])],
    targets: [
        .target(name: "VanishCore"),
        .testTarget(name: "VanishCoreTests", dependencies: ["VanishCore"]),
    ]
)
