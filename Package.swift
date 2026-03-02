// swift-tools-version: 6.2
// The swift-tools-version declares the minimum version of Swift required to build this package.

import PackageDescription

let package = Package(
    name: "DimmerFlow",
    platforms: [
        .macOS(.v13)
    ],
    products: [
        .executable(name: "DimmerFlow", targets: ["DimmerFlow"])
    ],
    targets: [
        .target(
            name: "FocusCore"
        ),
        .target(
            name: "FocusSystem",
            dependencies: ["FocusCore"]
        ),
        .target(
            name: "FocusUI",
            dependencies: ["FocusCore", "FocusSystem"]
        ),
        .executableTarget(
            name: "DimmerFlow",
            dependencies: ["FocusCore", "FocusSystem", "FocusUI"]
        ),
    ]
)
