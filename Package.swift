// swift-tools-version:5.9
import PackageDescription

let package = Package(
    name: "NeuralSDR2",
    platforms: [
        .macOS(.v13)
    ],
    products: [
        .executable(
            name: "NeuralSDR2",
            targets: ["NeuralSDR2"]
        ),
        .executable(
            name: "TestRTLSDR",
            targets: ["TestRTLSDR"]
        )
    ],
    dependencies: [],
    targets: [
        .executableTarget(
            name: "NeuralSDR2",
            dependencies: [],
            path: "src",
            exclude: ["TestHardware"],
            resources: [
                .process("Resources")
            ]
        ),
        .executableTarget(
            name: "TestRTLSDR",
            dependencies: [],
            path: "src/TestHardware",
            resources: []
        ),
        .testTarget(
            name: "NeuralSDR2Tests",
            dependencies: ["NeuralSDR2"],
            path: "tests"
        )
    ]
)
