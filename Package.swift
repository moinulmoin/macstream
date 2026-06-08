// swift-tools-version: 6.0

import Foundation
import PackageDescription

let enableHaishinKitRTMP = ProcessInfo.processInfo.environment["MAC_STREAM_ENABLE_HAISHINKIT"] == "1"
let enableMLX = ProcessInfo.processInfo.environment["MAC_STREAM_ENABLE_MLX"] == "1"

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

let macStreamCoreDependencies: [Target.Dependency] =
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
    (enableHaishinKitRTMP ? [.define("MAC_STREAM_HAS_HAISHINKIT")] : [])
    + (enableMLX ? [.define("MAC_STREAM_HAS_MLX")] : [])

let package = Package(
    name: "MacStream",
    platforms: [
        .macOS("26.0")
    ],
    products: [
        .executable(name: "MacStream", targets: ["MacStream"]),
        .library(name: "MacStreamCore", targets: ["MacStreamCore"])
    ],
    dependencies: packageDependencies,
    targets: [
        .target(
            name: "MacStreamCore",
            dependencies: macStreamCoreDependencies,
            swiftSettings: optionalFeatureSwiftSettings
        ),
        .executableTarget(
            name: "MacStream",
            dependencies: ["MacStreamCore"]
        ),
        .testTarget(
            name: "MacStreamCoreTests",
            dependencies: ["MacStreamCore"],
            swiftSettings: optionalFeatureSwiftSettings
        )
    ]
)
