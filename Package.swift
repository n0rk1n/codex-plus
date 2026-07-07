// swift-tools-version: 6.2

import PackageDescription

let package = Package(
    name: "codex-plus",
    platforms: [
        .macOS(.v26)
    ],
    products: [
        .executable(name: "CodexPlusApp", targets: ["CodexPlusApp"])
    ],
    targets: [
        .target(
            name: "CodexPlusCore",
            linkerSettings: [
                .linkedLibrary("sqlite3")
            ]
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
            name: "CodexPlusCoreLegacyTests",
            dependencies: ["CodexPlusCore", "CodexPlusApp"],
            path: "Tests/CodexPlusCoreTests"
        ),
        .testTarget(
            name: "CodexPlusCoreTests",
            dependencies: ["CodexPlusCore"],
            path: "Tests/CodexPlusCoreXCTests"
        )
    ]
)
