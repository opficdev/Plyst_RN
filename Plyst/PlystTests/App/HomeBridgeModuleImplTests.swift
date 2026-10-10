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
        let module = HomeBridgeModuleImpl(emit: { _ in }, requestSave: {})

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
        let module = HomeBridgeModuleImpl(emit: { _ in }, requestSave: {})

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

        HomeBridgeModuleImpl(emit: { _ in }, requestSave: {}).openSearch()

        await fulfillment(of: [completion], timeout: 2)
    }

    func testRequestsWithoutNavigatorDoNothing() async {
        let unexpected = expectation(description: "대상 해제 이후 화면 이동 없음")
        unexpected.isInverted = true
        await MainActor.run {
            var navigator = Optional(HomeBridgeNavigatorSpy())
            weak let reference = navigator
            navigator?.onOpenClip = { _, _ in unexpected.fulfill() }
            navigator?.onOpenSearch = { unexpected.fulfill() }
            HomeBridge.register(navigator!)
            navigator = nil
            XCTAssertNil(reference)
        }
        let module = HomeBridgeModuleImpl(emit: { _ in }, requestSave: {})

        module.openClip(UUID().uuidString, kind: "text")
        module.openSearch()

        await fulfillment(of: [unexpected], timeout: 0.1)
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
        let module = HomeBridgeModuleImpl(emit: { isVisible in
            XCTAssertFalse(isVisible)
            completion.fulfill()
        }, requestSave: {})

        module.ready()

        await fulfillment(of: [completion], timeout: 2)
    }

    func testVisibilityBeforeReadyStoresLatestValueAndEmitsOnce() async {
        let spy = HomeBridgeVisibilitySpy()
        let module = HomeBridgeModuleImpl(emit: { isVisible in
            MainActor.assumeIsolated { spy.values.append(isVisible) }
        }, requestSave: {})

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
        let module = HomeBridgeModuleImpl(emit: { isVisible in
            MainActor.assumeIsolated { spy.values.append(isVisible) }
        }, requestSave: {})
        await MainActor.run { module.ready() }
        await MainActor.run {}

        await HomeBridge.searchVisibilityChanged(true)
        await HomeBridge.searchVisibilityChanged(false)
        await HomeBridge.searchVisibilityChanged(true)

        await MainActor.run { XCTAssertEqual(spy.values, [false, true, false, true]) }
    }

    func testInvalidatedModuleDoesNotEmitOrRegisterAgain() async {
        let spy = HomeBridgeVisibilitySpy()
        let module = HomeBridgeModuleImpl(emit: { isVisible in
            MainActor.assumeIsolated { spy.values.append(isVisible) }
        }, requestSave: {})
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
        let previous = HomeBridgeModuleImpl(emit: { isVisible in
            MainActor.assumeIsolated { previousSpy.values.append(isVisible) }
        }, requestSave: {})
        let current = HomeBridgeModuleImpl(emit: { isVisible in
            MainActor.assumeIsolated { currentSpy.values.append(isVisible) }
        }, requestSave: {})
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
        let module = HomeBridgeModuleImpl(emit: { _ in }, requestSave: {})
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

    func testClipboardSaveBeforeReadyIsDeliveredOnceWhenReady() async {
        let spy = HomeBridgeClipboardSaveSpy()
        let module = HomeBridgeModuleImpl(emit: { _ in }, requestSave: {
            MainActor.assumeIsolated { spy.count += 1 }
        })

        await HomeBridge.requestClipboardSave()
        await MainActor.run {
            XCTAssertEqual(spy.count, 0)
            module.ready()
        }
        await MainActor.run {}
        await MainActor.run { XCTAssertEqual(spy.count, 1) }

        await MainActor.run { module.ready() }
        await MainActor.run {}
        await MainActor.run { XCTAssertEqual(spy.count, 1) }
    }

    func testClipboardSaveAfterReadyIsDeliveredImmediately() async {
        let spy = HomeBridgeClipboardSaveSpy()
        let module = HomeBridgeModuleImpl(emit: { _ in }, requestSave: {
            MainActor.assumeIsolated { spy.count += 1 }
        })
        await MainActor.run { module.ready() }
        await MainActor.run {}

        await MainActor.run {
            XCTAssertEqual(spy.count, 0)
            HomeBridge.requestClipboardSave()
            XCTAssertEqual(spy.count, 1)
            HomeBridge.requestClipboardSave()
            XCTAssertEqual(spy.count, 2)
        }
    }

    func testMultipleClipboardSaveRequestsBeforeReadyAreDeliveredOnce() async {
        let spy = HomeBridgeClipboardSaveSpy()
        let module = HomeBridgeModuleImpl(emit: { _ in }, requestSave: {
            MainActor.assumeIsolated { spy.count += 1 }
        })

        await MainActor.run {
            HomeBridge.requestClipboardSave()
            HomeBridge.requestClipboardSave()
            HomeBridge.requestClipboardSave()
            XCTAssertEqual(spy.count, 0)
            module.ready()
        }
        await MainActor.run {}
        await MainActor.run { XCTAssertEqual(spy.count, 1) }

        await MainActor.run { module.ready() }
        await MainActor.run {}
        await MainActor.run { XCTAssertEqual(spy.count, 1) }
    }

    func testClipboardSaveAfterInvalidationIsKeptUntilNextModuleIsReady() async {
        let previousSpy = HomeBridgeClipboardSaveSpy()
        let currentSpy = HomeBridgeClipboardSaveSpy()
        let previous = HomeBridgeModuleImpl(emit: { _ in }, requestSave: {
            MainActor.assumeIsolated { previousSpy.count += 1 }
        })
        let current = HomeBridgeModuleImpl(emit: { _ in }, requestSave: {
            MainActor.assumeIsolated { currentSpy.count += 1 }
        })
        await MainActor.run { previous.ready() }
        await MainActor.run { previous.invalidate() }
        await MainActor.run {}

        await HomeBridge.requestClipboardSave()
        await MainActor.run { previous.ready() }
        await MainActor.run {}
        await MainActor.run {
            XCTAssertEqual(previousSpy.count, 0)
            XCTAssertEqual(currentSpy.count, 0)
            current.ready()
        }
        await MainActor.run {}
        await MainActor.run {
            XCTAssertEqual(previousSpy.count, 0)
            XCTAssertEqual(currentSpy.count, 1)
        }

        await MainActor.run { current.ready() }
        await MainActor.run {}
        await MainActor.run { XCTAssertEqual(currentSpy.count, 1) }
    }

    private func resetBridge() async {
        await MainActor.run { [navigator] in
            navigator.onOpenClip = nil
            navigator.onOpenSearch = nil
            HomeBridge.register(navigator)
        }
        let module = HomeBridgeModuleImpl(emit: { _ in }, requestSave: {})
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

private final class HomeBridgeClipboardSaveSpy: Sendable {
    @MainActor var count = 0

    nonisolated init() {}
}
