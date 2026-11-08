//
//  ReactNativeRuntime.swift
//  Plyst
//
//  Created by opfic on 10/7/26.
//

import ReactBrownfield
import UIKit

@MainActor
enum ReactNativeRuntime {
    static func start(launchOptions: [UIApplication.LaunchOptionsKey: Any]?) {
        // Debug에서 Metro가 없으면 앱에 넣은 번들을 읽음
        ReactNativeBrownfield.shared.preferEmbeddedBundleInDebug = true
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
