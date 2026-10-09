//
//  ScreenBridgeModuleImpl.swift
//  PlystBridge
//
//  Created by opfic on 10/8/26.
//

import Foundation

@objc(ScreenBridgeModuleImpl)
public final class ScreenBridgeModuleImpl: NSObject, Sendable {
    private let id = UUID()
    private let emit: @Sendable () -> Void
    @MainActor private var isInvalidated = false

    @objc
    public init(emit: @escaping @Sendable () -> Void) {
        self.emit = emit
        super.init()
    }

    @objc
    public nonisolated func ready() {
        Task { @MainActor in
            guard !isInvalidated else { return }
            ScreenBridge.register(id: id, emit: emit)
        }
    }

    @objc
    public nonisolated func setSaveEnabled(_ isEnabled: Bool) {
        Task { @MainActor in
            guard !isInvalidated else { return }
            ScreenBridge.setSaveEnabled(isEnabled)
        }
    }

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
            ScreenBridge.unregister(id: id)
        }
    }
}
