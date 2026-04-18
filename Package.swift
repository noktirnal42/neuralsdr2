// swift-tools-version:5.9
import PackageDescription
import Foundation

let package = Package(
    name: "NeuralSDR2",
    platforms: [
        .macOS(.v13)
    ],
    products: [
        .executable(
            name: "NeuralSDR2",
            targets: ["NeuralSDR2"]
        )
    ],
    dependencies: [
        // No external Swift package dependencies yet
    ],
    targets: [
        .executableTarget(
            name: "NeuralSDR2",
            dependencies: [],
            path: "src",
            sources: [
                "App/NeuralSDR2App.swift",
                "UI/Main/ContentView.swift",
                "Hardware/RTLSDRDevice.swift"
            ],
            resources: [
                .process("Resources")
            ]
        ),
        .testTarget(
            name: "NeuralSDR2Tests",
            dependencies: ["NeuralSDR2"],
            path: "tests"
        )
    ],
    cSettings: [
        .headerSearchPath("../Hardware"),
        .define("DEBUG", .when(configuration: .debug))
    ]
)
