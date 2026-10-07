// swift-tools-version: 6.0

import PackageDescription

let frameworkNames = [
    "BrownfieldLib",
    "ExpoFileSystem",
    "ExpoFont",
    "ExpoImage",
    "ExpoModulesCore",
    "ExpoModulesJSI",
    "ExpoModulesWorklets",
    "hermesvm",
    "libavif",
    "PlystBridge",
    "React",
    "ReactBrownfield",
    "ReactNativeDependencies",
    "SDWebImage",
    "SDWebImageAVIFCoder",
    "SDWebImageSVGCoder",
    "SDWebImageWebPCoder",
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
