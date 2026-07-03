// swift-tools-version: 6.0

import PackageDescription

let package = Package(
    name: "codex-plus",
    platforms: [
        .macOS(.v14)
    ],
    products: [
        .library(name: "CodexPlusCore", targets: ["CodexPlusCore"]),
        .executable(name: "CodexPlusApp", targets: ["CodexPlusApp"]),
        .executable(name: "CodexPlusCoreTests", targets: ["CodexPlusCoreTests"])
    ],
    targets: [
        .target(
            name: "CodexPlusCore",
            linkerSettings: [
                .linkedFramework("IOKit")
            ]
        ),
        .executableTarget(
            name: "CodexPlusApp",
            dependencies: ["CodexPlusCore"],
            linkerSettings: [
                .linkedFramework("Carbon"),
                .linkedFramework("AppKit")
            ]
        ),
        .executableTarget(
            name: "CodexPlusCoreTests",
            dependencies: ["CodexPlusCore"],
            path: "Tests/CodexPlusCoreTests"
        )
    ]
)
