// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "MawaqitMac",
    platforms: [.macOS(.v13)],
    products: [
        .executable(name: "MawaqitMac", targets: ["MawaqitMac"]),
    ],
    targets: [
        .executableTarget(name: "MawaqitMac", swiftSettings: [.swiftLanguageMode(.v5)]),
        .testTarget(name: "MawaqitMacTests", dependencies: ["MawaqitMac"],
            swiftSettings: [.swiftLanguageMode(.v5)]),
    ]
)
