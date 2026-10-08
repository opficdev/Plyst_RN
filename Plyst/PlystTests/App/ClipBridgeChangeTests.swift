//
//  ClipBridgeChangeTests.swift
//  PlystTests
//
//  Created by opfic on 10/9/26.
//

import Foundation
import PlystBridge
import XCTest

final class ClipBridgeChangeTests: XCTestCase {
    override func tearDown() async throws {
        await ClipBridge.unregister()
        let module = ClipBridgeModuleImpl { _, _ in }
        await MainActor.run { module.ready() }
        await MainActor.run { module.invalidate() }
        await MainActor.run {}
        try await super.tearDown()
    }

    func testProviderChangesEmitAfterReady() async {
        let id = UUID()
        let updated = expectation(description: "갱신 전송")
        let deleted = expectation(description: "삭제 전송")
        let module = ClipBridgeModuleImpl { kind, identifier in
            XCTAssertEqual(identifier, id.uuidString)
            switch kind {
            case "updated": updated.fulfill()
            case "deleted": deleted.fulfill()
            default: XCTFail("예상하지 못한 변경입니다.")
            }
        }
        let stub = ClipBridgeChangeProviderStub()
        await ClipBridge.register(stub)
        await MainActor.run { module.ready() }
        await MainActor.run {}

        stub.continuation.yield(ClipBridgeChange(kind: .updated, id: id))
        stub.continuation.yield(ClipBridgeChange(kind: .deleted, id: id))

        await fulfillment(of: [updated, deleted], timeout: 2, enforceOrder: true)
    }

    func testChangesBeforeReadyAreDiscarded() async {
        let unexpected = expectation(description: "준비 이전 변경 미전달")
        unexpected.isInverted = true
        let completion = expectation(description: "준비 이후 변경 전송")
        let before = UUID()
        let after = UUID()
        let module = ClipBridgeModuleImpl { _, identifier in
            if identifier == before.uuidString { unexpected.fulfill() }
            if identifier == after.uuidString { completion.fulfill() }
        }
        let stub = ClipBridgeChangeProviderStub()
        await ClipBridge.register(stub)
        stub.continuation.yield(ClipBridgeChange(kind: .updated, id: before))
        await fulfillment(of: [unexpected], timeout: 0.1)
        await MainActor.run { module.ready() }
        await MainActor.run {}

        stub.continuation.yield(ClipBridgeChange(kind: .updated, id: after))

        await fulfillment(of: [completion], timeout: 2)
    }

    func testUnregisterCancelsSubscription() async {
        let cancelled = expectation(description: "구독 취소")
        let stub = ClipBridgeChangeProviderStub()
        stub.continuation.onTermination = { reason in
            guard case .cancelled = reason else {
                return XCTFail("구독이 취소되지 않았습니다.")
            }
            cancelled.fulfill()
        }
        await ClipBridge.register(stub)

        await ClipBridge.unregister()

        await fulfillment(of: [cancelled], timeout: 2)
    }

    func testRegisterReplacesSubscriptionAndPreservesEmitter() async {
        let cancelled = expectation(description: "이전 구독 취소")
        let completion = expectation(description: "새 저장소 변경 전송")
        let previous = ClipBridgeChangeProviderStub()
        previous.continuation.onTermination = { _ in cancelled.fulfill() }
        let current = ClipBridgeChangeProviderStub()
        let id = UUID()
        let module = ClipBridgeModuleImpl { _, identifier in
            XCTAssertEqual(identifier, id.uuidString)
            completion.fulfill()
        }
        await ClipBridge.register(previous)
        await MainActor.run { module.ready() }
        await MainActor.run {}

        await ClipBridge.register(current)
        await fulfillment(of: [cancelled], timeout: 2)
        previous.continuation.yield(ClipBridgeChange(kind: .updated, id: UUID()))
        current.continuation.yield(ClipBridgeChange(kind: .deleted, id: id))

        await fulfillment(of: [completion], timeout: 2)
    }

    func testInvalidatingPreviousInstancePreservesCurrentRegistration() async {
        let unexpected = expectation(description: "이전 모듈의 전송 없음")
        unexpected.isInverted = true
        let completion = expectation(description: "현재 모듈의 전송")
        let previous = ClipBridgeModuleImpl { _, _ in unexpected.fulfill() }
        let current = ClipBridgeModuleImpl { _, _ in completion.fulfill() }
        let stub = ClipBridgeChangeProviderStub()
        await ClipBridge.register(stub)
        await MainActor.run { previous.ready() }
        await MainActor.run { current.ready() }
        await MainActor.run { previous.invalidate() }
        await MainActor.run {}

        stub.continuation.yield(ClipBridgeChange(kind: .updated, id: UUID()))

        await fulfillment(of: [completion], timeout: 2)
        await fulfillment(of: [unexpected], timeout: 0.1)
    }

    func testInvalidatedModuleDoesNotEmitOrRegisterAgain() async {
        let unexpected = expectation(description: "무효화 이후 전송 없음")
        unexpected.isInverted = true
        let module = ClipBridgeModuleImpl { _, _ in unexpected.fulfill() }
        let stub = ClipBridgeChangeProviderStub()
        await ClipBridge.register(stub)
        await MainActor.run { module.ready() }
        await MainActor.run { module.invalidate() }
        await MainActor.run { module.ready() }
        await MainActor.run {}

        stub.continuation.yield(ClipBridgeChange(kind: .deleted, id: UUID()))

        await fulfillment(of: [unexpected], timeout: 0.1)
    }
}

private struct ClipBridgeChangeProviderStub: ClipBridgeProvider {
    private let pair = AsyncStream<ClipBridgeChange>.makeStream()
    var continuation: AsyncStream<ClipBridgeChange>.Continuation { pair.continuation }

    func changes() async -> AsyncStream<ClipBridgeChange> { pair.stream }
    func clip(id: UUID) async throws -> ClipBridgeRecord? { nil }
    func updateClip(
        id: UUID,
        name: String?,
        memo: String?,
        isPinned: Bool
    ) async throws -> ClipBridgeRecord? { nil }
    func deleteClip(id: UUID) async throws {}
    func copyClip(id: UUID) async throws -> ClipBridgeCopyResult? { nil }
}
