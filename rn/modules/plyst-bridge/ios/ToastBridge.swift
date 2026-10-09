//
//  ToastBridge.swift
//  PlystBridge
//
//  Created by opfic on 10/8/26.
//

import Foundation

@MainActor
public enum ToastBridge {
    private static var registration: (id: UUID, emit: @Sendable (String, Bool) -> Void)?
    private static var pending: (message: String, isSuccess: Bool)?

    public static func show(
        message: String,
        isSuccess: Bool
    ) {
        guard let registration else {
            pending = (message, isSuccess)
            return
        }
        registration.emit(message, isSuccess)
    }

    static func register(
        id: UUID,
        emit: @escaping @Sendable (String, Bool) -> Void
    ) {
        registration = (id, emit)
        if let request = pending {
            pending = nil
            emit(request.message, request.isSuccess)
        }
    }

    static func unregister(id: UUID) {
        if registration?.id == id { registration = nil }
    }
}
