// swift-tools-version: 6.0

import PackageDescription

let package = Package(
    name: "QuickAIDashboard",
    platforms: [
        .macOS(.v14)
    ],
    products: [
        .library(name: "QuickAIDashboardCore", targets: ["QuickAIDashboardCore"]),
        .executable(name: "QuickAIDashboardApp", targets: ["QuickAIDashboardApp"])
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
        .testTarget(
            name: "QuickAIDashboardCoreTests",
            dependencies: ["QuickAIDashboardCore"]
        )
    ]
)
