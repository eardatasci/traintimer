// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "TrainTimerCore",
    platforms: [.macOS(.v14)],
    products: [
        .library(name: "TrainTimerCore", targets: ["TrainTimerCore"]),
    ],
    targets: [
        .target(name: "TrainTimerCore"),
        .testTarget(
            name: "TrainTimerCoreTests",
            dependencies: ["TrainTimerCore"],
            resources: [.copy("Fixtures")]
        ),
    ]
)
