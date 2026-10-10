//
//  HomeBridgeModuleImplTests.swift
//  PlystTests
//
//  Created by opfic on 10/10/26.
//

import Foundation
import PlystBridge
import XCTest

final class HomeBridgeModuleImplTests: XCTestCase {
    private let navigator = HomeBridgeNavigatorSpy()
    private let other = HomeBridgeNavigatorSpy()

    override func setUp() async throws {
        try await super.setUp()
        await resetBridge()
    }

    override func tearDown() async throws {
        await resetBridge()
        try await super.tearDown()
    }

    func testOpenClipForwardsTypedTextAndImage() async {
        let id = UUID()
        let text = expectation(description: "텍스트 상세 화면")
        let image = expectation(description: "이미지 상세 화면")
        await MainActor.run { [navigator] in
            navigator.onOpenClip = { received, kind in
                XCTAssertEqual(received, id)
                switch kind {
                case .text: text.fulfill()
                case .image: image.fulfill()
                @unknown default:
                    XCTFail("알 수 없는 클립 종류입니다.")
                }
            }
            HomeBridge.register(navigator)
        }
        let module = HomeBridgeModuleImpl { _ in }

        module.openClip(id.uuidString, kind: "text")
        await fulfillment(of: [text], timeout: 2)
        module.openClip(id.uuidString, kind: "image")

        await fulfillment(of: [image], timeout: 2)
    }

    func testInvalidIdentifierAndUnknownKindAreIgnored() async {
        let unexpected = expectation(description: "잘못된 상세 화면 요청 미전달")
        unexpected.isInverted = true
        await MainActor.run { [navigator] in
            navigator.onOpenClip = { _, _ in unexpected.fulfill() }
            HomeBridge.register(navigator)
        }
        let module = HomeBridgeModuleImpl { _ in }

        module.openClip("invalid", kind: "text")
        module.openClip(UUID().uuidString, kind: "unknown")

        await fulfillment(of: [unexpected], timeout: 0.1)
    }

    func testOpenSearchCallsRegisteredNavigator() async {
        let completion = expectation(description: "검색 화면 표시")
        await MainActor.run { [navigator] in
            navigator.onOpenSearch = { completion.fulfill() }
            HomeBridge.register(navigator)
        }

        HomeBridgeModuleImpl { _ in }.openSearch()

        await fulfillment(of: [completion], timeout: 2)
    }

    func testRequestsWithoutNavigatorDoNothing() async {
        let unexpected = expectation(description: "등록 해제 이후 화면 이동 없음")
        unexpected.isInverted = true
        await MainActor.run { [navigator] in
            navigator.onOpenClip = { _, _ in unexpected.fulfill() }
            navigator.onOpenSearch = { unexpected.fulfill() }
            HomeBridge.register(navigator)
            HomeBridge.unregister(navigator)
        }
        let module = HomeBridgeModuleImpl { _ in }

        module.openClip(UUID().uuidString, kind: "text")
        module.openSearch()

        await fulfillment(of: [unexpected], timeout: 0.1)
    }

    func testUnregisteringDifferentNavigatorPreservesRegistration() async {
        let completion = expectation(description: "등록된 검색 화면 표시")
        await MainActor.run { [navigator, other] in
            navigator.onOpenSearch = { completion.fulfill() }
            HomeBridge.register(navigator)
            HomeBridge.unregister(other)
        }

        HomeBridgeModuleImpl { _ in }.openSearch()

        await fulfillment(of: [completion], timeout: 2)
    }

    func testNavigatorIsHeldWeakly() async {
        await MainActor.run {
            weak var reference: HomeBridgeNavigatorSpy?
            do {
                let navigator = HomeBridgeNavigatorSpy()
                reference = navigator
                HomeBridge.register(navigator)
                XCTAssertNotNil(reference)
            }
            XCTAssertNil(reference)
        }
    }

    func testReadyEmitsInitialFalseOnce() async {
        let completion = expectation(description: "초기 검색 표시 상태")
        completion.assertForOverFulfill = true
        let module = HomeBridgeModuleImpl { isVisible in
            XCTAssertFalse(isVisible)
            completion.fulfill()
        }

        module.ready()

        await fulfillment(of: [completion], timeout: 2)
    }

    func testVisibilityBeforeReadyStoresLatestValueAndEmitsOnce() async {
        let spy = HomeBridgeVisibilitySpy()
        let module = HomeBridgeModuleImpl { isVisible in
            MainActor.assumeIsolated { spy.values.append(isVisible) }
        }

        await HomeBridge.searchVisibilityChanged(false)
        await HomeBridge.searchVisibilityChanged(true)
        await MainActor.run {
            XCTAssertTrue(spy.values.isEmpty)
            module.ready()
        }
        await MainActor.run {}

        await MainActor.run { XCTAssertEqual(spy.values, [true]) }
    }

    func testVisibilityChangesAfterReadyEmitInOrder() async {
        let spy = HomeBridgeVisibilitySpy()
        let module = HomeBridgeModuleImpl { isVisible in
            MainActor.assumeIsolated { spy.values.append(isVisible) }
        }
        await MainActor.run { module.ready() }
        await MainActor.run {}

        await HomeBridge.searchVisibilityChanged(true)
        await HomeBridge.searchVisibilityChanged(false)
        await HomeBridge.searchVisibilityChanged(true)

        await MainActor.run { XCTAssertEqual(spy.values, [false, true, false, true]) }
    }

    func testInvalidatedModuleDoesNotEmitOrRegisterAgain() async {
        let spy = HomeBridgeVisibilitySpy()
        let module = HomeBridgeModuleImpl { isVisible in
            MainActor.assumeIsolated { spy.values.append(isVisible) }
        }
        await MainActor.run { module.ready() }
        await MainActor.run { module.invalidate() }
        await MainActor.run {}

        await HomeBridge.searchVisibilityChanged(true)
        await MainActor.run { module.ready() }
        await MainActor.run {}
        await HomeBridge.searchVisibilityChanged(false)

        await MainActor.run { XCTAssertEqual(spy.values, [false]) }
    }

    func testInvalidatingPreviousInstancePreservesCurrentRegistration() async {
        let previousSpy = HomeBridgeVisibilitySpy()
        let currentSpy = HomeBridgeVisibilitySpy()
        let previous = HomeBridgeModuleImpl { isVisible in
            MainActor.assumeIsolated { previousSpy.values.append(isVisible) }
        }
        let current = HomeBridgeModuleImpl { isVisible in
            MainActor.assumeIsolated { currentSpy.values.append(isVisible) }
        }
        await MainActor.run { previous.ready() }
        await MainActor.run { current.ready() }
        await MainActor.run {}
        await HomeBridge.searchVisibilityChanged(true)
        await MainActor.run { previous.invalidate() }
        await MainActor.run {}
        await HomeBridge.searchVisibilityChanged(false)

        await MainActor.run {
            XCTAssertEqual(previousSpy.values, [false])
            XCTAssertEqual(currentSpy.values, [false, true, false])
        }
    }

    func testNavigationAfterInvalidationIsIgnored() async {
        let unexpected = expectation(description: "무효화 이후 화면 이동 없음")
        unexpected.isInverted = true
        let module = HomeBridgeModuleImpl { _ in }
        await MainActor.run { [navigator] in
            navigator.onOpenClip = { _, _ in unexpected.fulfill() }
            navigator.onOpenSearch = { unexpected.fulfill() }
            HomeBridge.register(navigator)
            module.invalidate()
        }
        await MainActor.run {}

        module.openClip(UUID().uuidString, kind: "text")
        module.openSearch()

        await fulfillment(of: [unexpected], timeout: 0.1)
    }

    private func resetBridge() async {
        await HomeBridge.unregister(navigator)
        await HomeBridge.unregister(other)
        let module = HomeBridgeModuleImpl { _ in }
        await MainActor.run { module.ready() }
        await MainActor.run { module.invalidate() }
        await MainActor.run {}
        await HomeBridge.searchVisibilityChanged(false)
    }
}

private final class HomeBridgeNavigatorSpy: HomeBridgeNavigator {
    @MainActor var onOpenClip: ((UUID, HomeBridgeClipKind) -> Void)?
    @MainActor var onOpenSearch: (() -> Void)?

    nonisolated init() {}

    @MainActor func openClip(
        id: UUID,
        kind: HomeBridgeClipKind
    ) {
        onOpenClip?(id, kind)
    }

    @MainActor func openSearch() {
        onOpenSearch?()
    }
}

private final class HomeBridgeVisibilitySpy: Sendable {
    @MainActor var values = [Bool]()

    nonisolated init() {}
}
