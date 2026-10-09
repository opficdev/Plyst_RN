//
//  ToastBridgeModuleImpl.swift
//  PlystBridge
//
//  Created by opfic on 10/8/26.
//

import Foundation

@objc(ToastBridgeModuleImpl)
public final class ToastBridgeModuleImpl: NSObject, Sendable {
    private let id = UUID()
    private let emit: @Sendable (String, Bool) -> Void
    @MainActor private var isInvalidated = false

    @objc
    public init(emit: @escaping @Sendable (String, Bool) -> Void) {
        self.emit = emit
        super.init()
    }

    @objc
    public nonisolated func ready() {
        Task { @MainActor in
            guard !isInvalidated else { return }
            ToastBridge.register(id: id, emit: emit)
        }
    }

    @objc
    public nonisolated func invalidate() {
        Task { @MainActor in
            isInvalidated = true
            ToastBridge.unregister(id: id)
        }
    }
}
