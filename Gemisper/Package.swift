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
    dependencies: [],
    targets: [
        .executableTarget(
            name: "Gemisper",
            dependencies: [],

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
