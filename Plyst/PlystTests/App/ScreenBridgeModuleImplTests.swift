//
//  ScreenBridgeModuleImplTests.swift
//  PlystTests
//
//  Created by opfic on 10/8/26.
//

import Foundation
import PlystBridge
import XCTest

final class ScreenBridgeModuleImplTests: XCTestCase {
    private let closer = ScreenBridgeCloserSpy()
    private let other = ScreenBridgeCloserSpy()

    override func tearDown() async throws {
        await ScreenBridge.unregister(closer)
        await ScreenBridge.unregister(other)
        let module = ScreenBridgeModuleImpl(emit: {})
        await MainActor.run { module.ready() }
        await MainActor.run { module.invalidate() }
        await MainActor.run {}
        try await super.tearDown()
    }

    func testCloseCallsRegisteredCloser() async {
        let completion = expectation(description: "화면 닫기")
        await MainActor.run { [closer] in
            closer.onClose = { completion.fulfill() }
            ScreenBridge.register(closer)
        }

        ScreenBridgeModuleImpl(emit: {}).close()

        await fulfillment(of: [completion], timeout: 2)
    }

    func testCloseDoesNothingAfterInvalidation() async {
        let completion = expectation(description: "화면 닫기 없음")
        completion.isInverted = true
        let module = ScreenBridgeModuleImpl(emit: {})
        await MainActor.run { [closer] in
            closer.onClose = { completion.fulfill() }
            ScreenBridge.register(closer)
            module.invalidate()
        }
        await MainActor.run {}

        module.close()

        await fulfillment(of: [completion], timeout: 0.1)
    }

    func testUnregisteringDifferentCloserPreservesRegistration() async {
        let completion = expectation(description: "등록된 화면 닫기")
        await MainActor.run { [closer, other] in
            closer.onClose = { completion.fulfill() }
            ScreenBridge.register(closer)
            ScreenBridge.unregister(other)
        }

        ScreenBridgeModuleImpl(emit: {}).close()

        await fulfillment(of: [completion], timeout: 2)
    }

    func testSaveEmitsAfterReady() async {
        let completion = expectation(description: "저장 탭 전송")
        let module = ScreenBridgeModuleImpl { completion.fulfill() }
        await MainActor.run { module.ready() }
        await MainActor.run {}

        await ScreenBridge.save()

        await fulfillment(of: [completion], timeout: 2)
    }

    func testSaveBeforeReadyIsDiscarded() async {
        let completion = expectation(description: "준비 이후 저장 탭만 전송")
        completion.assertForOverFulfill = true
        let module = ScreenBridgeModuleImpl { completion.fulfill() }

        await ScreenBridge.save()
        await MainActor.run { module.ready() }
        await MainActor.run {}
        await ScreenBridge.save()

        await fulfillment(of: [completion], timeout: 2)
    }

    func testSetSaveEnabledCallsRegisteredCloser() async {
        let enabled = expectation(description: "저장 버튼 활성화")
        let disabled = expectation(description: "저장 버튼 비활성화")
        await MainActor.run { [closer] in
            closer.onSetSaveEnabled = { isEnabled in
                if isEnabled { enabled.fulfill() } else { disabled.fulfill() }
            }
            ScreenBridge.register(closer)
        }
        let module = ScreenBridgeModuleImpl(emit: {})

        module.setSaveEnabled(true)
        await fulfillment(of: [enabled], timeout: 2)
        module.setSaveEnabled(false)

        await fulfillment(of: [disabled], timeout: 2)
    }

    func testSetSaveEnabledDoesNothingAfterInvalidation() async {
        let unexpected = expectation(description: "무효화 이후 저장 버튼 상태 미전달")
        unexpected.isInverted = true
        let module = ScreenBridgeModuleImpl(emit: {})
        await MainActor.run { [closer] in
            closer.onSetSaveEnabled = { _ in unexpected.fulfill() }
            ScreenBridge.register(closer)
            module.invalidate()
        }
        await MainActor.run {}

        module.setSaveEnabled(true)
        module.setSaveEnabled(false)

        await fulfillment(of: [unexpected], timeout: 0.1)
    }

    func testInvalidatingPreviousInstancePreservesCurrentRegistration() async {
        let unexpected = expectation(description: "이전 모듈의 저장 탭 미전달")
        unexpected.isInverted = true
        let completion = expectation(description: "현재 모듈의 저장 탭 전송")
        let previous = ScreenBridgeModuleImpl { unexpected.fulfill() }
        let current = ScreenBridgeModuleImpl { completion.fulfill() }
        await MainActor.run { previous.ready() }
        await MainActor.run { current.ready() }
        await MainActor.run { previous.invalidate() }
        await MainActor.run {}

        await ScreenBridge.save()

        await fulfillment(of: [completion], timeout: 2)
        await fulfillment(of: [unexpected], timeout: 0.1)
    }

    func testInvalidatedModuleDoesNotEmitOrRegisterAgain() async {
        let unexpected = expectation(description: "무효화 이후 저장 탭 미전달")
        unexpected.isInverted = true
        let module = ScreenBridgeModuleImpl { unexpected.fulfill() }
        await MainActor.run { module.ready() }
        await MainActor.run { module.invalidate() }
        await MainActor.run { module.ready() }
        await MainActor.run {}

        await ScreenBridge.save()

        await fulfillment(of: [unexpected], timeout: 0.1)
    }
}

private final class ScreenBridgeCloserSpy: ScreenBridgeCloser {
    @MainActor var onClose: (() -> Void)?
    @MainActor var onSetSaveEnabled: ((Bool) -> Void)?

    nonisolated init() {}

    @MainActor func close() {
        onClose?()
    }

    @MainActor func setSaveEnabled(_ isEnabled: Bool) {
        onSetSaveEnabled?(isEnabled)
    }
}
