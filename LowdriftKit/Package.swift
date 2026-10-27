// swift-tools-version: 5.9
//
// LowdriftKit holds everything in Lowdrift that does not need UIKit, SwiftUI or
// AVFoundation: the procedural sound engine, preset definitions, on-device
// settings and the playback state machine. Keeping it platform-neutral lets the
// DSP and logic tests run with `swift test` on any machine with a Swift
// toolchain, in addition to running inside Xcode.

import PackageDescription

let package = Package(
    name: "LowdriftKit",
    platforms: [.iOS(.v17), .macOS(.v14)],
    products: [
        .library(name: "LowdriftKit", targets: ["LowdriftCore", "LowdriftDSP"]),
        // Developer tool: renders presets to WAV files for listening and tuning.
        .executable(name: "lowdrift-render", targets: ["LowdriftRender"]),
    ],
    targets: [
        // Lock-free 32-bit atomics used for the UI → audio thread hand-off.
        .target(name: "LDAtomics"),
        .target(name: "LowdriftDSP", dependencies: ["LDAtomics"]),
        .target(name: "LowdriftCore", dependencies: ["LowdriftDSP"]),
        // Offline measurement helpers (FFT, band levels, loudness) for tests and the render tool.
        .target(name: "LowdriftAnalysis", dependencies: ["LowdriftDSP"]),
        .executableTarget(
            name: "LowdriftRender",
            dependencies: ["LowdriftDSP", "LowdriftCore", "LowdriftAnalysis"]
        ),
        .testTarget(
            name: "LowdriftDSPTests",
            dependencies: ["LowdriftDSP", "LowdriftCore", "LowdriftAnalysis"]
        ),
        .testTarget(name: "LowdriftCoreTests", dependencies: ["LowdriftCore", "LowdriftDSP"]),
    ]
)
