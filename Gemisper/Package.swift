// swift-tools-version:5.9
import PackageDescription

let package = Package(
    name: "Gemisper",
    platforms: [.macOS(.v13)],
    products: [
        .executable(
            name: "Gemisper",
            targets: ["Gemisper"]
        )
    ],
    dependencies: [
        .package(url: "https://github.com/jpsim/YAMS.git", from: "5.0.0"),
    ],
    targets: [
        .executableTarget(
            name: "Gemisper",
            dependencies: [
                .product(name: "Yams", package: "yams"),
            ],
            swiftSettings: [
                .enableExperimentalFeature("StrictConcurrency"),
            ],
            linkerSettings: [
                .linkedFramework("AVFoundation"),
                .linkedFramework("Carbon"),
                .linkedFramework("ApplicationServices"),
            ]
        )
    ]
)
