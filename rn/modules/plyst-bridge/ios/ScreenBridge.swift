//
//  ScreenBridge.swift
//  PlystBridge
//
//  Created by opfic on 10/8/26.
//

public protocol ScreenBridgeCloser: AnyObject, Sendable {
    @MainActor func close()
}

@MainActor
public enum ScreenBridge {
    private static weak var closer: (any ScreenBridgeCloser)?

    public static func register(_ closer: any ScreenBridgeCloser) {
        self.closer = closer
    }

    public static func unregister(_ closer: any ScreenBridgeCloser) {
        if self.closer === closer { self.closer = nil }
    }

    static func close() {
        closer?.close()
    }
}
