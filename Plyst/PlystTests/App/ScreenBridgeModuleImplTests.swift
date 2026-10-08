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
        try await super.tearDown()
    }

    func testCloseCallsRegisteredCloser() async {
        let completion = expectation(description: "화면 닫기")
        await MainActor.run { [closer] in
            closer.onClose = { completion.fulfill() }
            ScreenBridge.register(closer)
        }

        ScreenBridgeModuleImpl().close()

        await fulfillment(of: [completion], timeout: 2)
    }

    func testCloseDoesNothingAfterInvalidation() async {
        let completion = expectation(description: "화면 닫기 없음")
        completion.isInverted = true
        let module = ScreenBridgeModuleImpl()
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

        ScreenBridgeModuleImpl().close()

        await fulfillment(of: [completion], timeout: 2)
    }
}

private final class ScreenBridgeCloserSpy: ScreenBridgeCloser {
    @MainActor var onClose: (() -> Void)?

    nonisolated init() {}

    @MainActor func close() {
        onClose?()
    }
}
