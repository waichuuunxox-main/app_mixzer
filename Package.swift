// swift-tools-version: 6.2
// The swift-tools-version declares the minimum version of Swift required to build this package.

import PackageDescription

let package = Package(
    name: "app_mixzer",
    platforms: [
        .macOS(.v14),
        .iOS(.v17),
    ],
    products: [
        // Products define the executables and libraries a package produces, making them visible to other packages.
        .library(
            name: "app_mixzer",
            targets: ["app_mixzer"]
        ),
        // Export reusable SwiftUI guidelines UI & loader
        .library(
            name: "GuidelinesUI",
            targets: ["GuidelinesUI"]
        ),
    ],
    dependencies: [
        // Optional: add Yams for robust YAML parsing
        .package(url: "https://github.com/jpsim/Yams.git", from: "5.0.0"),
    ],
    targets: [
        // Targets are the basic building blocks of a package, defining a module or a test suite.
        // Targets can depend on other targets in this package and products from dependencies.
        .target(
            name: "app_mixzer",
            dependencies: [
                // Use Yams for YAML parsing
                .product(name: "Yams", package: "Yams"),
            ],
            resources: [
                .copy("Resources/guidelines.yml"),
                .copy("Resources/kworb_top10.json")
            ]
        ),
        // Executable target to check guidelines consistency using Swift + Yams
        .executableTarget(
            name: "guidelines-check",
            dependencies: [
                .product(name: "Yams", package: "Yams"),
            ],
            path: "Sources/guidelines-check",
            resources: [
                .copy("Resources/guidelines.yml")
            ]
        ),
        // Minimal App target so we can run a SwiftUI App for manual testing
        .executableTarget(
            name: "AppRunner",
            dependencies: [
                .target(name: "app_mixzer"),
                .target(name: "GuidelinesUI"),
            ],
            path: "Sources/AppRunner"
        ),
        // SwiftUI library target exposing a Guidelines loader + SwiftUI view
        .target(
            name: "GuidelinesUI",
            dependencies: [
                .product(name: "Yams", package: "Yams"),
            ],
            resources: [
                .copy("Resources/guidelines.yml")
            ]
        ),
        .testTarget(
            name: "app_mixzerTests",
            dependencies: ["app_mixzer"]
        ),
    ]
)
