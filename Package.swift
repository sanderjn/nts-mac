// swift-tools-version:6.0
import PackageDescription

let package = Package(
    name: "NTS",
    platforms: [
        .macOS(.v14)
    ],
    targets: [
        .target(
            name: "NTSCore"
        ),
        .executableTarget(
            name: "NTS",
            dependencies: ["NTSCore"]
        ),
        // `swift test` is inert without full Xcode, so the parsing checks are a
        // plain executable: `swift run Check`.
        .executableTarget(
            name: "Check",
            dependencies: ["NTSCore"],
            resources: [.copy("Fixtures")]
        ),
        // Talks to a real Cast device: `swift run CastProbe` lists them,
        // `swift run CastProbe "<name>" [seconds]` plays Channel 1 on one,
        // `swift run CastProbe "<name>" volume [level]` reads or sets its volume.
        .executableTarget(
            name: "CastProbe",
            dependencies: ["NTSCore"]
        )
    ]
)
