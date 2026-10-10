//
//  ClipBridgeCopyModuleImplTests.swift
//  PlystTests
//
//  Created by opfic on 10/9/26.
//

import Foundation
import PlystBridge
import XCTest

final class ClipBridgeCopyModuleImplTests: XCTestCase {
    override func tearDown() async throws {
        await ClipBridge.unregister()
        try await super.tearDown()
    }

    func testCopySuccessDelivery() async {
        for result in [ClipBridgeCopyResult.copied, .copiedWithoutLastUsedAt, .writeNotObserved] {
            let id = UUID()
            let stub = ClipBridgeCopyProviderStub { receivedID in
                XCTAssertEqual(receivedID, id)
                return result
            }
            await ClipBridge.register(stub)
            let completion = expectation(description: "복사 결과 전달")

            ClipBridgeModuleImpl(emit: { _, _ in }).copyClip(id.uuidString) { value, code in
                XCTAssertEqual(value, result.rawValue)
                XCTAssertNil(code)
                completion.fulfill()
            }

            await fulfillment(of: [completion], timeout: 2)
        }
    }

    func testCopyMissingDelivery() async {
        let id = UUID()
        let stub = ClipBridgeCopyProviderStub { receivedID in
            XCTAssertEqual(receivedID, id)
            return nil
        }
        await ClipBridge.register(stub)
        let completion = expectation(description: "없는 클립 결과 전달")

        ClipBridgeModuleImpl(emit: { _, _ in }).copyClip(id.uuidString) { value, code in
            XCTAssertNil(value)
            XCTAssertNil(code)
            completion.fulfill()
        }

        await fulfillment(of: [completion], timeout: 2)
    }

    func testCopyFailureDelivery() async {
        let stub = ClipBridgeCopyProviderStub { _ in
            throw ClipBridgeCopyProviderTestError.failed
        }
        await ClipBridge.register(stub)
        let completion = expectation(description: "복사 오류 전달")

        ClipBridgeModuleImpl(emit: { _, _ in }).copyClip(UUID().uuidString) { value, code in
            XCTAssertNil(value)
            XCTAssertEqual(code, "E_COPY_FAILED")
            completion.fulfill()
        }

        await fulfillment(of: [completion], timeout: 2)
    }

    func testCopyInvalidIdentifierDelivery() async {
        let stub = ClipBridgeCopyProviderStub { _ in
            XCTFail("잘못된 식별자로 제공자를 호출했습니다.")
            return nil
        }
        await ClipBridge.register(stub)
        let completion = expectation(description: "식별자 오류 전달")

        ClipBridgeModuleImpl(emit: { _, _ in }).copyClip("invalid") { value, code in
            XCTAssertNil(value)
            XCTAssertEqual(code, "E_INVALID_ID")
            completion.fulfill()
        }

        await fulfillment(of: [completion], timeout: 2)
    }

    func testCopyUnavailableDelivery() async {
        await ClipBridge.unregister()
        let completion = expectation(description: "제공자 등록 오류 전달")

        ClipBridgeModuleImpl(emit: { _, _ in }).copyClip(UUID().uuidString) { value, code in
            XCTAssertNil(value)
            XCTAssertEqual(code, "E_UNAVAILABLE")
            completion.fulfill()
        }

        await fulfillment(of: [completion], timeout: 2)
    }

    func testCopyDoesNotDeliverAfterInvalidation() async {
        let started = expectation(description: "요청 시작")
        let cancelled = expectation(description: "요청 취소")
        let returned = expectation(description: "요청 반환")
        let completion = expectation(description: "무효화 뒤 결과 미전달")
        completion.isInverted = true
        let gate = ClipBridgeCopyRequestGate()
        let stub = ClipBridgeCopyProviderStub { _ in
            await withTaskCancellationHandler {
                await gate.wait(started: started)
            } onCancel: {
                cancelled.fulfill()
            }
            returned.fulfill()
            return .copied
        }
        await ClipBridge.register(stub)
        let module = ClipBridgeModuleImpl(emit: { _, _ in })

        module.copyClip(UUID().uuidString) { _, _ in
            completion.fulfill()
        }
        await fulfillment(of: [started], timeout: 2)
        module.invalidate()
        await fulfillment(of: [cancelled], timeout: 2)
        await gate.resume()
        await fulfillment(of: [returned], timeout: 2)
        await fulfillment(of: [completion], timeout: 0.1)
    }
}

private enum ClipBridgeCopyProviderTestError: Error {
    case failed
}

private struct ClipBridgeCopyProviderStub: ClipBridgeProvider {
    let copy: @Sendable (UUID) async throws -> ClipBridgeCopyResult?

    func changes() async -> AsyncStream<ClipBridgeChange> {
        AsyncStream { $0.finish() }
    }

    func getClipThumbnail(
        id: UUID,
        maximumPixelDimension: Int
    ) async throws -> String? { nil }

    func getClipImagePreview(id: UUID) async throws -> String? { nil }

    func saveClipImageToPhotos(id: UUID) async throws -> ClipBridgePhotoSaveResult? { nil }

    func clip(id: UUID) async throws -> ClipBridgeRecord? { nil }
    func saveCurrentClipboard() async throws -> ClipBridgeClipboardSaveResult { .empty }

    func clips() async throws -> [ClipBridgeRecord] { [] }

    func updateClip(
        id: UUID,
        name: String?,
        memo: String?,
        isPinned: Bool
    ) async throws -> ClipBridgeRecord? { nil }

    func deleteClip(id: UUID) async throws {}

    func copyClip(id: UUID) async throws -> ClipBridgeCopyResult? {
        try await copy(id)
    }
}

private actor ClipBridgeCopyRequestGate {
    private var continuation: CheckedContinuation<Void, Never>?

    func wait(started: XCTestExpectation) async {
        await withCheckedContinuation {
            continuation = $0
            started.fulfill()
        }
    }

    func resume() {
        continuation?.resume()
        continuation = nil
    }
}

final class ClipBridgeSaveModuleImplTests: XCTestCase {
    override func tearDown() async throws {
        await ClipBridge.unregister()
        try await super.tearDown()
    }

    func testSaveResultDelivery() async {
        for result in [ClipBridgeClipboardSaveResult.saved, .empty, .unsupported, .accessFailed, .invalidImage] {
            await ClipBridge.register(ClipBridgeSaveProviderStub { result })
            let completion = expectation(description: "저장 결과 전달")

            ClipBridgeModuleImpl(emit: { _, _ in }).saveCurrentClipboard { value, code in
                XCTAssertEqual(value, result.rawValue)
                XCTAssertNil(code)
                completion.fulfill()
            }

            await fulfillment(of: [completion], timeout: 2)
        }
    }

    func testSaveFailureDelivery() async {
        await ClipBridge.register(ClipBridgeSaveProviderStub {
            throw ClipBridgeCopyProviderTestError.failed
        })
        let completion = expectation(description: "저장 실패 전달")

        ClipBridgeModuleImpl(emit: { _, _ in }).saveCurrentClipboard { value, code in
            XCTAssertNil(value)
            XCTAssertEqual(code, "E_SAVE_FAILED")
            completion.fulfill()
        }

        await fulfillment(of: [completion], timeout: 2)
    }

    func testSaveUnavailableDelivery() async {
        await ClipBridge.unregister()
        let completion = expectation(description: "제공자 없음 전달")

        ClipBridgeModuleImpl(emit: { _, _ in }).saveCurrentClipboard { value, code in
            XCTAssertNil(value)
            XCTAssertEqual(code, "E_UNAVAILABLE")
            completion.fulfill()
        }

        await fulfillment(of: [completion], timeout: 2)
    }

    func testSaveDoesNotDeliverAfterInvalidation() async {
        let started = expectation(description: "저장 시작")
        let cancelled = expectation(description: "저장 취소")
        let returned = expectation(description: "저장 반환")
        let completion = expectation(description: "무효화 뒤 결과 미전달")
        completion.isInverted = true
        let gate = ClipBridgeCopyRequestGate()
        await ClipBridge.register(ClipBridgeSaveProviderStub {
            await withTaskCancellationHandler {
                await gate.wait(started: started)
            } onCancel: {
                cancelled.fulfill()
            }
            returned.fulfill()
            return .saved
        })
        let module = ClipBridgeModuleImpl(emit: { _, _ in })

        module.saveCurrentClipboard { _, _ in completion.fulfill() }
        await fulfillment(of: [started], timeout: 2)
        module.invalidate()
        await fulfillment(of: [cancelled], timeout: 2)
        await gate.resume()
        await fulfillment(of: [returned], timeout: 2)
        await fulfillment(of: [completion], timeout: 0.1)
    }
}

private struct ClipBridgeSaveProviderStub: ClipBridgeProvider {
    let save: @Sendable () async throws -> ClipBridgeClipboardSaveResult

    func saveCurrentClipboard() async throws -> ClipBridgeClipboardSaveResult {
        try await save()
    }

    func changes() async -> AsyncStream<ClipBridgeChange> {
        AsyncStream { $0.finish() }
    }

    func getClipThumbnail(
        id: UUID,
        maximumPixelDimension: Int
    ) async throws -> String? { nil }

    func getClipImagePreview(id: UUID) async throws -> String? { nil }
    func saveClipImageToPhotos(id: UUID) async throws -> ClipBridgePhotoSaveResult? { nil }
    func clip(id: UUID) async throws -> ClipBridgeRecord? { nil }
    func clips() async throws -> [ClipBridgeRecord] { [] }

    func updateClip(
        id: UUID,
        name: String?,
        memo: String?,
        isPinned: Bool
    ) async throws -> ClipBridgeRecord? { nil }

    func deleteClip(id: UUID) async throws {}
    func copyClip(id: UUID) async throws -> ClipBridgeCopyResult? { nil }
}
