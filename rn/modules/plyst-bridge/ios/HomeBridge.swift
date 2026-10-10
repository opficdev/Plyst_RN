//
//  HomeBridge.swift
//  PlystBridge
//
//  Created by opfic on 10/10/26.
//

import Foundation

/// 브리지에서 해석한 클립 종류를 네이티브 호스트에 전달합니다. 알 수 없는 문자열은 초기화에 실패합니다.
public enum HomeBridgeClipKind: String, Sendable {
    /// JavaScript가 요청한 텍스트 클립의 상세 화면을 나타냅니다.
    case text
    /// JavaScript가 요청한 이미지 클립의 상세 화면을 나타냅니다.
    case image
}

/// 네이티브 호스트가 구현합니다. 브리지가 검증한 화면 이동 요청을 받습니다.
public protocol HomeBridgeNavigator: AnyObject, Sendable {
    /// 브리지가 유효한 식별자와 종류로 호출합니다. 호스트가 클립 상세 화면을 표시합니다.
    @MainActor func openClip(
        id: UUID,
        kind: HomeBridgeClipKind
    )
    /// 브리지가 JavaScript의 요청을 전달하면 호스트가 검색 화면을 표시합니다.
    @MainActor func openSearch()
}

/// 호스트가 화면 이동 대상을 등록하고 검색 표시 상태를 전달하는 진입점입니다.
@MainActor
public enum HomeBridge {
    private static weak var navigator: (any HomeBridgeNavigator)?
    private static var registration: (id: UUID, emit: @Sendable (Bool) -> Void)?
    private static var isSearchVisible = false

    /// 호스트가 화면 이동 대상을 약한 참조로 등록합니다. 기존 대상은 교체됩니다.
    public static func register(_ navigator: any HomeBridgeNavigator) {
        self.navigator = navigator
    }

    /// 호스트가 자신의 등록을 해제합니다. 등록된 대상과 다른 객체이면 무시합니다.
    public static func unregister(_ navigator: any HomeBridgeNavigator) {
        if self.navigator === navigator { self.navigator = nil }
    }

    static func openClip(
        id: UUID,
        kind: HomeBridgeClipKind
    ) {
        navigator?.openClip(id: id, kind: kind)
    }

    static func openSearch() {
        navigator?.openSearch()
    }

    static func register(
        id: UUID,
        emit: @escaping @Sendable (Bool) -> Void
    ) {
        registration = (id, emit)
        emit(isSearchVisible)
    }

    static func unregister(id: UUID) {
        if registration?.id == id { registration = nil }
    }

    /// 호스트가 검색 화면을 열거나 닫을 때 호출합니다. 수신 대상이 없어도 최신 상태를 보관합니다.
    public static func searchVisibilityChanged(_ isVisible: Bool) {
        isSearchVisible = isVisible
        registration?.emit(isVisible)
    }
}
