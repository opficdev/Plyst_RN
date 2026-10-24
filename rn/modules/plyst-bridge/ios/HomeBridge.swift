//
//  HomeBridge.swift
//  PlystBridge
//
//  Created by opfic on 10/10/26.
//

import Foundation

/// 호스트가 클립보드 저장 요청을 전달하는 진입점
/// ready()에서 보관된 저장 요청을 전달함
@MainActor
public enum HomeBridge {
    private static var registration: (
        id: UUID,
        requestSave: @Sendable () -> Void
    )?
    private static var isClipboardSaveRequested = false

    static func register(
        id: UUID,
        requestSave: @escaping @Sendable () -> Void
    ) {
        registration = (id, requestSave)
        if isClipboardSaveRequested {
            isClipboardSaveRequested = false
            requestSave()
        }
    }

    /// 호스트가 클립보드 저장을 요청함
    /// ready() 전에는 요청 하나를 만료 없이 보관함
    public static func requestClipboardSave() {
        guard let registration else {
            isClipboardSaveRequested = true
            return
        }
        registration.requestSave()
    }

    static func unregister(id: UUID) {
        if registration?.id == id { registration = nil }
    }
}
