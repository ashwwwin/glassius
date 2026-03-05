// swift-tools-version: 6.0

import PackageDescription

let package = Package(
    name: "GlassiusCam",
    platforms: [
        .macOS(.v13)
    ],
    products: [
        .executable(name: "GlassiusCam", targets: ["GlassiusCam"])
    ],
    targets: [
        .executableTarget(
            name: "GlassiusCam",
            path: "Sources"
        )
    ]
)
