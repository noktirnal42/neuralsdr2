// swift-tools-version:5.9
import PackageDescription

let package = Package(
    name: "NeuralSDR2",
    platforms: [
        .macOS(.v13)
    ],
    products: [
        .library(
            name: "NeuralSDR2Kit",
            targets: ["NeuralSDR2Kit"]
        ),
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
        // System library target for librtlsdr C binding
        .systemLibrary(
            name: "CLibRTLSDR",
            path: "src/CLibRTLSDR",
            pkgConfig: "librtlsdr",
            providers: [
                .brew(["librtlsdr"])
            ]
        ),
        // Shared library target — all SDR/DSP/UI code
        .target(
            name: "NeuralSDR2Kit",
            dependencies: ["CLibRTLSDR"],
            path: "src",
            exclude: ["TestHardware", "CLibRTLSDR", "Info.plist", "App/NeuralSDR2App.swift"],
            resources: [
                .process("Resources")
            ],
            linkerSettings: [
                .linkedLibrary("rtlsdr"),
                .linkedLibrary("m"), // math
                .linkedFramework("Accelerate"),
                .linkedFramework("CoreAudio"),
                .linkedFramework("AudioToolbox"),
                .linkedFramework("AVFoundation"),
                .linkedFramework("Metal"),
                .linkedFramework("MetalKit"),
                .linkedFramework("SceneKit"),
                .linkedFramework("MapKit"),
            .linkedFramework("CoreLocation"),
            .linkedFramework("IOKit"),
            .linkedFramework("Network")
        ]
    ),
        // GUI application executable
        .executableTarget(
            name: "NeuralSDR2",
            dependencies: ["NeuralSDR2Kit"],
            path: "Sources/NeuralSDR2App",
            linkerSettings: [
                .linkedFramework("SwiftUI")
            ]
        ),
        // CLI hardware test executable
        .executableTarget(
            name: "TestRTLSDR",
            dependencies: ["NeuralSDR2Kit", "CLibRTLSDR"],
            path: "src/TestHardware",
            linkerSettings: [
                .linkedLibrary("rtlsdr")
            ]
        ),
        .testTarget(
            name: "NeuralSDR2Tests",
            dependencies: ["NeuralSDR2Kit"],
            path: "tests"
        )
    ]
)
