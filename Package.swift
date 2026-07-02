// swift-tools-version: 6.0

import PackageDescription

let package = Package(
    name: "QuickAIDashboard",
    platforms: [
        .macOS(.v14)
    ],
    products: [
        .library(name: "QuickAIDashboardCore", targets: ["QuickAIDashboardCore"]),
        .executable(name: "QuickAIDashboardApp", targets: ["QuickAIDashboardApp"]),
        .executable(name: "QuickAIDashboardCoreTests", targets: ["QuickAIDashboardCoreTests"])
    ],
    targets: [
        .target(
            name: "QuickAIDashboardCore",
            linkerSettings: [
                .linkedFramework("IOKit")
            ]
        ),
        .executableTarget(
            name: "QuickAIDashboardApp",
            dependencies: ["QuickAIDashboardCore"],
            linkerSettings: [
                .linkedFramework("Carbon"),
                .linkedFramework("AppKit")
            ]
        ),
        .executableTarget(
            name: "QuickAIDashboardCoreTests",
            dependencies: ["QuickAIDashboardCore"],
            path: "Tests/QuickAIDashboardCoreTests"
        )
    ]
)
