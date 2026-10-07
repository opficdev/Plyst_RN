//
//  RNBrownfieldHost.swift
//  RNBrownfield
//
//  Created by opfic on 10/7/26.
//

import BrownfieldLib
import ReactBrownfield
import UIKit

@MainActor
public enum RNBrownfieldHost {
    public static func start() {
        let adapter = ReactNativeBrownfield.shared
        adapter.bundle = ReactNativeBundle
        adapter.ensureExpoModulesProvider()
        adapter.startReactNative(onBundleLoaded: nil)
    }

    public static func makeViewController(moduleName: String) -> UIViewController {
        ReactNativeViewController(moduleName: moduleName)
    }
}
