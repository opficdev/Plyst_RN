//
//  ToastBridgeModuleImplTests.swift
//  PlystTests
//
//  Created by opfic on 10/8/26.
//

import PlystBridge
import XCTest

final class ToastBridgeModuleImplTests: XCTestCase {
    override func tearDown() async throws {
        let module = ToastBridgeModuleImpl { _, _ in }
        await MainActor.run { module.ready() }
        await MainActor.run { module.invalidate() }
        await MainActor.run {}
        try await super.tearDown()
    }

    func testShowEmitsAfterReady() async {
        let completion = expectation(description: "토스트 요청 전송")
        let module = ToastBridgeModuleImpl { message, isSuccess in
            XCTAssertEqual(message, "복사 완료")
            XCTAssertTrue(isSuccess)
            completion.fulfill()
        }
        await MainActor.run { module.ready() }
        await MainActor.run {}

        await ToastBridge.show(message: "복사 완료", isSuccess: true)

        await fulfillment(of: [completion], timeout: 2)
    }

    func testReadyEmitsOnlyLastPendingRequest() async {
        let completion = expectation(description: "마지막 토스트 요청 전송")
        completion.assertForOverFulfill = true
        let module = ToastBridgeModuleImpl { message, isSuccess in
            XCTAssertEqual(message, "저장 실패")
            XCTAssertFalse(isSuccess)
            completion.fulfill()
        }

        await ToastBridge.show(message: "복사 완료", isSuccess: true)
        await ToastBridge.show(message: "저장 실패", isSuccess: false)
        module.ready()

        await fulfillment(of: [completion], timeout: 2)

        await MainActor.run { module.ready() }
        await MainActor.run {}
    }

    func testInvalidationStoresRequestUntilNextInstanceIsReady() async {
        let unexpected = expectation(description: "무효화된 모듈의 전송 없음")
        unexpected.isInverted = true
        let module = ToastBridgeModuleImpl { _, _ in unexpected.fulfill() }
        await MainActor.run { module.ready() }
        await MainActor.run { module.invalidate() }
        await MainActor.run {}

        await ToastBridge.show(message: "보관된 요청", isSuccess: false)
        module.ready()

        await fulfillment(of: [unexpected], timeout: 0.1)

        let completion = expectation(description: "다음 모듈에 보관된 요청 전송")
        let next = ToastBridgeModuleImpl { message, isSuccess in
            XCTAssertEqual(message, "보관된 요청")
            XCTAssertFalse(isSuccess)
            completion.fulfill()
        }
        next.ready()

        await fulfillment(of: [completion], timeout: 2)
    }

    func testInvalidatingPreviousInstancePreservesCurrentRegistration() async {
        let unexpected = expectation(description: "이전 모듈의 전송 없음")
        unexpected.isInverted = true
        let previous = ToastBridgeModuleImpl { _, _ in unexpected.fulfill() }
        let completion = expectation(description: "현재 모듈에 토스트 요청 전송")
        let current = ToastBridgeModuleImpl { message, isSuccess in
            XCTAssertEqual(message, "현재 요청")
            XCTAssertTrue(isSuccess)
            completion.fulfill()
        }
        await MainActor.run { previous.ready() }
        await MainActor.run { current.ready() }
        await MainActor.run { previous.invalidate() }
        await MainActor.run {}

        await ToastBridge.show(message: "현재 요청", isSuccess: true)

        await fulfillment(of: [completion, unexpected], timeout: 0.1)
    }
}
