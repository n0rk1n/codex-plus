// swift-tools-version: 6.0

import PackageDescription

let package = Package(
    name: "codex-plus",
    platforms: [
        .macOS(.v14)
    ],
    products: [
        .executable(name: "CodexPlusApp", targets: ["CodexPlusApp"])
    ],
    targets: [
        .target(
            name: "CodexPlusCore"
        ),
        .executableTarget(
            name: "CodexPlusApp",
            dependencies: ["CodexPlusCore"],
            linkerSettings: [
                .linkedFramework("Carbon"),
                .linkedFramework("AppKit"),
                .linkedFramework("IOKit")
            ]
        ),
        .executableTarget(
            name: "CodexPlusCoreTests",
            dependencies: ["CodexPlusCore"],
            path: "Tests/CodexPlusCoreTests"
        )
    ]
)
