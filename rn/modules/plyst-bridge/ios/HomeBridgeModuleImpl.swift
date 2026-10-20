//
//  HomeBridgeModuleImpl.swift
//  PlystBridge
//
//  Created by opfic on 10/10/26.
//

import Foundation

/// Objective-C++ 모듈이 JavaScript의 저장 요청 구독과 기기 종류 조회를 전달합니다.
@objc(HomeBridgeModuleImpl)
public final class HomeBridgeModuleImpl: NSObject, Sendable {
    private let id = UUID()
    private let requestSave: @Sendable () -> Void
    @MainActor private var isInvalidated = false

    /// Objective-C++ 모듈이 저장 요청 전송 함수를 전달합니다. ready() 전에는 호출하지 않습니다.
    @objc
    public init(requestSave: @escaping @Sendable () -> Void) {
        self.requestSave = requestSave
        super.init()
    }

    /// JavaScript가 구독한 뒤 호출합니다. 보관된 저장 요청을 전달합니다. 무효화된 모듈은 무시합니다.
    @objc
    public nonisolated func ready() {
        Task { @MainActor in
            guard !isInvalidated else { return }
            HomeBridge.register(id: id, requestSave: requestSave)
        }
    }

    /// JavaScript가 iPhone Duo 여부를 동기로 읽습니다. 등록과 관계없으므로 ready() 전에도 호출할 수 있습니다.
    @objc
    public nonisolated func isDuoDevice() -> Bool {
        DeviceModel.isDuo
    }

    /// 네이티브 모듈이 종료될 때 호출합니다. 자신의 이벤트 등록을 해제하고 이후 요청을 무시합니다.
    @objc
    public nonisolated func invalidate() {
        Task { @MainActor in
            isInvalidated = true
            HomeBridge.unregister(id: id)
        }
    }
}
