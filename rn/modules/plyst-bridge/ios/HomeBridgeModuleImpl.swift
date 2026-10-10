//
//  HomeBridgeModuleImpl.swift
//  PlystBridge
//
//  Created by opfic on 10/10/26.
//

import Foundation

/// Objective-C++ 모듈이 JavaScript의 화면 이동 요청과 검색 상태 구독을 전달합니다.
@objc(HomeBridgeModuleImpl)
public final class HomeBridgeModuleImpl: NSObject, Sendable {
    private let id = UUID()
    private let emit: @Sendable (Bool) -> Void
    @MainActor private var isInvalidated = false

    /// Objective-C++ 모듈이 검색 표시 상태 전송 함수를 전달합니다. ready() 전에는 호출하지 않습니다.
    @objc
    public init(emit: @escaping @Sendable (Bool) -> Void) {
        self.emit = emit
        super.init()
    }

    /// JavaScript가 구독한 뒤 호출합니다. 현재 상태를 한 번 전달합니다. 무효화된 모듈은 무시합니다.
    @objc
    public nonisolated func ready() {
        Task { @MainActor in
            guard !isInvalidated else { return }
            HomeBridge.register(id: id, emit: emit)
        }
    }

    /// JavaScript가 상세 화면을 요청합니다. 잘못된 식별자나 종류와 무효화 이후의 호출은 조용히 무시합니다.
    @objc(openClip:kind:)
    public nonisolated func openClip(
        _ identifier: String,
        kind: String
    ) {
        guard let id = UUID(uuidString: identifier), let kind = HomeBridgeClipKind(rawValue: kind) else { return }
        Task { @MainActor in
            guard !isInvalidated else { return }
            HomeBridge.openClip(id: id, kind: kind)
        }
    }

    /// JavaScript가 검색 화면을 요청합니다. 등록된 호스트가 없거나 무효화된 모듈이면 무시합니다.
    @objc
    public nonisolated func openSearch() {
        Task { @MainActor in
            guard !isInvalidated else { return }
            HomeBridge.openSearch()
        }
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
