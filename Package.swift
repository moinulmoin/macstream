// swift-tools-version: 6.0

import Foundation
import PackageDescription

let enableHaishinKitRTMP = ProcessInfo.processInfo.environment["OPEN_CUE_ENABLE_HAISHINKIT"] == "1"
let enableMLX = ProcessInfo.processInfo.environment["OPEN_CUE_ENABLE_MLX"] == "1"

let packageDependencies: [Package.Dependency] =
    (enableHaishinKitRTMP
     ? [
        .package(url: "https://github.com/HaishinKit/HaishinKit.swift", from: "2.2.0")
     ]
     : [])
    + (enableMLX
       ? [
        .package(url: "https://github.com/ml-explore/mlx-swift-lm", from: "3.31.3")
       ]
       : [])

let openCueCoreDependencies: [Target.Dependency] =
    (enableHaishinKitRTMP
     ? [
        .product(name: "HaishinKit", package: "HaishinKit.swift"),
        .product(name: "RTMPHaishinKit", package: "HaishinKit.swift")
     ]
     : [])
    + (enableMLX
       ? [
        .product(name: "MLXLLM", package: "mlx-swift-lm"),
        .product(name: "MLXLMCommon", package: "mlx-swift-lm"),
        .product(name: "MLXHuggingFace", package: "mlx-swift-lm")
       ]
       : [])

let optionalFeatureSwiftSettings: [SwiftSetting] =
    (enableHaishinKitRTMP ? [.define("OPEN_CUE_HAS_HAISHINKIT")] : [])
    + (enableMLX ? [.define("OPEN_CUE_HAS_MLX")] : [])

let package = Package(
    name: "OpenCue",
    platforms: [
        .macOS("26.0")
    ],
    products: [
        .executable(name: "OpenCue", targets: ["OpenCue"]),
        .library(name: "OpenCueCore", targets: ["OpenCueCore"])
    ],
    dependencies: packageDependencies,
    targets: [
        .target(
            name: "OpenCueCore",
            dependencies: openCueCoreDependencies,
            swiftSettings: optionalFeatureSwiftSettings
        ),
        .executableTarget(
            name: "OpenCue",
            dependencies: ["OpenCueCore"]
        ),
        .testTarget(
            name: "OpenCueCoreTests",
            dependencies: ["OpenCueCore"],
            swiftSettings: optionalFeatureSwiftSettings
        )
    ]
)
