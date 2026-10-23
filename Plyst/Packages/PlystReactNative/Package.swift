// swift-tools-version: 6.0

import PackageDescription

let frameworkNames = [
    "BrownfieldLib",
    "ExpoModulesJSI",
    "hermesvm",
    "PlystBridge",
    "React",
    "ReactBrownfield",
    "ReactNativeDependencies",
]

let package = Package(
    name: "PlystReactNative",
    platforms: [.iOS(.v17)],
    products: [
        .library(name: "PlystReactNative", targets: frameworkNames),
    ],
    targets: frameworkNames.map {
        .binaryTarget(name: $0, path: "Frameworks/\($0).xcframework")
    }
)
