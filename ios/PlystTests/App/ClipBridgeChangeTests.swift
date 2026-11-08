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
        let inserted = expectation(description: "삽입 전송")
        let updated = expectation(description: "갱신 전송")
        let deleted = expectation(description: "삭제 전송")
        let module = ClipBridgeModuleImpl { kind, identifier in
            XCTAssertEqual(identifier, id.uuidString)
            switch kind {
            case "inserted": inserted.fulfill()
            case "updated": updated.fulfill()
            case "deleted": deleted.fulfill()
            default: XCTFail("예상하지 못한 변경입니다.")
            }
        }
        let stub = ClipBridgeChangeProviderStub()
        await ClipBridge.register(stub)
        await MainActor.run { module.ready() }
        await MainActor.run {}

        stub.continuation.yield(ClipBridgeChange(kind: .inserted, id: id))
        stub.continuation.yield(ClipBridgeChange(kind: .updated, id: id))
        stub.continuation.yield(ClipBridgeChange(kind: .deleted, id: id))

        await fulfillment(of: [inserted, updated, deleted], timeout: 2, enforceOrder: true)
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
}

private struct ClipBridgeChangeProviderStub: ClipBridgeProvider {
    private let pair = AsyncStream<ClipBridgeChange>.makeStream()
    var continuation: AsyncStream<ClipBridgeChange>.Continuation { pair.continuation }

    func changes() async -> AsyncStream<ClipBridgeChange> { pair.stream }
    func getClipThumbnail(
        id: UUID,
        maximumPixelDimension: Int
    ) async throws -> String? { nil }

    func getClipImagePreview(id: UUID) async throws -> String? { nil }

    func saveClipImageToPhotos(id: UUID) async throws -> ClipBridgePhotoSaveResult? { nil }

    func clip(id: UUID) async throws -> ClipBridgeRecord? { nil }
    func saveCurrentClipboard() async throws -> ClipBridgeClipboardSaveResult { .empty }

    func searchHistory() async throws -> [String] { [] }
    func recordSearchTerm(_ term: String) async throws -> [String]? { nil }
    func removeSearchTerm(_ term: String) async throws -> [String] { [] }
    func removeAllSearchTerms() async throws {}

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
