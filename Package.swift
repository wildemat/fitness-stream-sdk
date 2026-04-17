// swift-tools-version: 5.9

import PackageDescription

let package = Package(
    name: "FitnessStreamSDK",
    platforms: [.iOS(.v16), .watchOS(.v9)],
    products: [
        .library(name: "FitnessStreamCore", targets: ["FitnessStreamCore"]),
    ],
    targets: [
        .target(name: "FitnessStreamCore"),
        .testTarget(
            name: "FitnessStreamCoreTests",
            dependencies: ["FitnessStreamCore"]
        ),
    ]
)
