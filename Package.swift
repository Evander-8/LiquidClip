// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "LiquidClip",
    platforms: [
        .macOS(.v13)
    ],
    products: [
        .executable(name: "LiquidClip", targets: ["LiquidClip"])
    ],
    dependencies: [],
    targets: [
        .executableTarget(
            name: "LiquidClip",
            dependencies: [],
            path: "Sources/LiquidClip"
        )
    ]
)
