// swift-tools-version: 6.0

import PackageDescription

let package = Package(
    name: "PlystCore",
    platforms: [.iOS(.v17)],
    products: [
        .library(name: "PlystCore", type: .dynamic, targets: ["PlystCore"]),
    ],
    targets: [
        .binaryTarget(name: "PlystCoreFFI", path: "Frameworks/PlystCoreFFI.xcframework"),
        .target(name: "PlystCore", dependencies: ["PlystCoreFFI"]),
    ]
)
