//
//  ScreenBridgeModuleImpl.swift
//  PlystBridge
//
//  Created by opfic on 10/8/26.
//

import Foundation

@objc(ScreenBridgeModuleImpl)
public final class ScreenBridgeModuleImpl: NSObject, Sendable {
    @MainActor private var isInvalidated = false

    @objc
    public nonisolated func close() {
        Task { @MainActor in
            guard !isInvalidated else { return }
            ScreenBridge.close()
        }
    }

    @objc
    public nonisolated func invalidate() {
        Task { @MainActor in
            isInvalidated = true
        }
    }
}
