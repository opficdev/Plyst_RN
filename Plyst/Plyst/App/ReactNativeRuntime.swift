//
//  ReactNativeRuntime.swift
//  Plyst
//
//  Created by opfic on 10/7/26.
//

import BrownfieldLib
import ReactBrownfield
import UIKit

@MainActor
enum ReactNativeRuntime {
    static func start(launchOptions: [UIApplication.LaunchOptionsKey: Any]?) {
        ReactNativeBrownfield.shared.bundle = ReactNativeBundle
        ReactNativeBrownfield.shared.ensureExpoModulesProvider()
        ReactNativeBrownfield.shared.startReactNative(
            launchOptions: launchOptions,
            preloadBundle: false,
            onBundleLoaded: nil
        )
    }

    #if DEBUG
    static func makeDebugViewController() -> UIViewController {
        ReactNativeViewController(moduleName: "PlystRN", initialProperties: nil)
    }
    #endif
}
