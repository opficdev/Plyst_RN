// swift-tools-version: 6.0
//
//  Package.swift
//  RNBrownfield
//
//  Created by opfic on 10/7/26.
//

import PackageDescription

let package = Package(
    name: "RNBrownfield",
    platforms: [.iOS(.v17)],
    products: [
        .library(name: "RNBrownfield", targets: ["RNBrownfield"]),
    ],
    targets: [
        .target(
            name: "RNBrownfield",
            dependencies: [
                "BrownfieldLib",
                "ReactBrownfield",
                "React",
                "ReactNativeDependencies",
                "hermesvm",
                "ExpoModulesCore",
                "ExpoModulesJSI",
                "ExpoFileSystem",
                "ExpoFont",
                "ExpoImage",
                "ExpoModulesWorklets",
                "SDWebImage",
                "SDWebImageAVIFCoder",
                "SDWebImageSVGCoder",
                "SDWebImageWebPCoder",
                "libavif",
            ]
        ),
        .binaryTarget(name: "BrownfieldLib", path: "Frameworks/BrownfieldLib.xcframework"),
        .binaryTarget(name: "ReactBrownfield", path: "Frameworks/ReactBrownfield.xcframework"),
        .binaryTarget(name: "React", path: "Frameworks/React.xcframework"),
        .binaryTarget(name: "ReactNativeDependencies", path: "Frameworks/ReactNativeDependencies.xcframework"),
        .binaryTarget(name: "hermesvm", path: "Frameworks/hermesvm.xcframework"),
        .binaryTarget(name: "ExpoModulesCore", path: "Frameworks/ExpoModulesCore.xcframework"),
        .binaryTarget(name: "ExpoModulesJSI", path: "Frameworks/ExpoModulesJSI.xcframework"),
        .binaryTarget(name: "ExpoFileSystem", path: "Frameworks/ExpoFileSystem.xcframework"),
        .binaryTarget(name: "ExpoFont", path: "Frameworks/ExpoFont.xcframework"),
        .binaryTarget(name: "ExpoImage", path: "Frameworks/ExpoImage.xcframework"),
        .binaryTarget(name: "ExpoModulesWorklets", path: "Frameworks/ExpoModulesWorklets.xcframework"),
        .binaryTarget(name: "SDWebImage", path: "Frameworks/SDWebImage.xcframework"),
        .binaryTarget(name: "SDWebImageAVIFCoder", path: "Frameworks/SDWebImageAVIFCoder.xcframework"),
        .binaryTarget(name: "SDWebImageSVGCoder", path: "Frameworks/SDWebImageSVGCoder.xcframework"),
        .binaryTarget(name: "SDWebImageWebPCoder", path: "Frameworks/SDWebImageWebPCoder.xcframework"),
        .binaryTarget(name: "libavif", path: "Frameworks/libavif.xcframework"),
    ]
)
