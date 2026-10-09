//
//  ScreenBridge.swift
//  PlystBridge
//
//  Created by opfic on 10/8/26.
//

import Foundation

public protocol ScreenBridgeCloser: AnyObject, Sendable {
    @MainActor func close()
    @MainActor func setSaveEnabled(_ isEnabled: Bool)
}

@MainActor
public enum ScreenBridge {
    private static weak var closer: (any ScreenBridgeCloser)?
    private static var registration: (id: UUID, emit: @Sendable () -> Void)?

    public static func register(_ closer: any ScreenBridgeCloser) {
        self.closer = closer
    }

    public static func unregister(_ closer: any ScreenBridgeCloser) {
        if self.closer === closer { self.closer = nil }
    }

    static func close() {
        closer?.close()
    }

    static func setSaveEnabled(_ isEnabled: Bool) {
        closer?.setSaveEnabled(isEnabled)
    }

    static func register(
        id: UUID,
        emit: @escaping @Sendable () -> Void
    ) {
        registration = (id, emit)
    }

    static func unregister(id: UUID) {
        if registration?.id == id { registration = nil }
    }

    public static func save() {
        registration?.emit()
    }
}
