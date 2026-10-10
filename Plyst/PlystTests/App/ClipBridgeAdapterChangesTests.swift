//
//  ClipBridgeAdapterChangesTests.swift
//  PlystTests
//
//  Created by opfic on 10/9/26.
//

import Foundation
import PlystBridge
import XCTest
@testable import Plyst

final class ClipBridgeAdapterChangesTests: XCTestCase {
    private let directory = FileManager.default.temporaryDirectory.appendingPathComponent("Plyst-bridge-changes-\(UUID())", isDirectory: true)

    override func tearDown() async throws {
        await ClipBridge.unregister()
        if FileManager.default.fileExists(atPath: directory.path) {
            try FileManager.default.removeItem(at: directory)
        }
        try await super.tearDown()
    }

    func testInsertedIsDiscardedAndUpdatesAndDeletesAreMapped() async throws {
        let storage = try makeStorage()
        let adapter = try makeAdapter(storage: storage)
        let stream = await adapter.changes()
        let inserted = expectation(description: "삽입 매핑")
        inserted.assertForOverFulfill = true
        let updated = expectation(description: "갱신 매핑")
        let deleted = expectation(description: "삭제 매핑")
        updated.assertForOverFulfill = true
        deleted.assertForOverFulfill = true
        let clip = Clip(content: .text("원문"))
        let task = Task {
            for await change in stream {
                XCTAssertEqual(change.id, clip.id)
                switch change.kind {
                case .inserted: inserted.fulfill()
                case .updated: updated.fulfill()
                case .deleted: deleted.fulfill()
                @unknown default:
                    XCTFail("알 수 없는 변경 종류입니다.")
                }
            }
        }
        defer { task.cancel() }

        try await storage.insert(clip)
        _ = try await storage.update(id: clip.id, change: .details(
            name: "변경",
            memo: nil,
            isPinned: false
        ))
        try await storage.delete(id: clip.id)

        await fulfillment(of: [inserted, updated, deleted], timeout: 2, enforceOrder: true)
        task.cancel()
        await task.value
    }

    func testConsumerCancellationRemovesStorageSubscription() async throws {
        let subscribed = expectation(description: "저장소 구독 등록")
        let removed = expectation(description: "저장소 구독 제거")
        let spy = ClipBridgeChangesStorageServiceSpy(subscribed: subscribed, removed: removed)
        let adapter = try makeAdapter(storage: spy)
        let stream = await adapter.changes()
        let task = Task {
            for await _ in stream {}
        }
        defer { task.cancel() }
        await fulfillment(of: [subscribed], timeout: 2)
        let before = await spy.subscriptionCount
        XCTAssertEqual(before, 1)

        task.cancel()
        await task.value

        await fulfillment(of: [removed], timeout: 2)
        let after = await spy.subscriptionCount
        XCTAssertEqual(after, 0)
    }

    func testBridgeUnregisterRemovesStorageSubscription() async throws {
        let subscribed = expectation(description: "저장소 구독 등록")
        let removed = expectation(description: "저장소 구독 제거")
        let spy = ClipBridgeChangesStorageServiceSpy(subscribed: subscribed, removed: removed)
        let adapter = try makeAdapter(storage: spy)
        await ClipBridge.register(adapter)
        await fulfillment(of: [subscribed], timeout: 2)

        await ClipBridge.unregister()

        await fulfillment(of: [removed], timeout: 2)
        let count = await spy.subscriptionCount
        XCTAssertEqual(count, 0)
    }

    private func makeStorage() throws -> SQLiteClipStorageService {
        try SQLiteClipStorageService(databaseURL: directory.appendingPathComponent("clips.sqlite"))
    }

    private func makeAdapter(storage: any ClipStorageService) throws -> ClipBridgeAdapter {
        let files = try ClipImageFileStore(rootURL: directory.appendingPathComponent("images", isDirectory: true))
        let images = ClipImageService(storage: storage, files: files)
        return ClipBridgeAdapter(
            storage: storage,
            images: images,
            clipboard: ClipboardService(storage: storage, images: images),
            photos: ClipPhotoLibraryService(storage: storage, images: images)
        )
    }
}

private actor ClipBridgeChangesStorageServiceSpy: ClipStorageService {
    private let subscribed: XCTestExpectation
    private let removed: XCTestExpectation
    private var subscriptions = [UUID: AsyncStream<ClipStorageEvent>.Continuation]()
    var subscriptionCount: Int { subscriptions.count }

    init(
        subscribed: XCTestExpectation,
        removed: XCTestExpectation
    ) {
        self.subscribed = subscribed
        self.removed = removed
    }

    func changes() async -> AsyncStream<ClipStorageEvent> {
        let id = UUID()
        let (stream, continuation) = AsyncStream<ClipStorageEvent>.makeStream()
        subscriptions[id] = continuation
        continuation.onTermination = { [weak self] reason in
            guard case .cancelled = reason else {
                return XCTFail("저장소 구독이 취소되지 않았습니다.")
            }
            Task { await self?.removeSubscription(id) }
        }
        subscribed.fulfill()
        return stream
    }

    private func removeSubscription(_ id: UUID) {
        subscriptions.removeValue(forKey: id)
        removed.fulfill()
    }

    func fetchAll(order: ClipSortOrder) async throws -> [Clip] { [] }
    func fetch(id: Clip.ID) async throws -> Clip? { nil }
    func insert(_ clip: Clip) async throws {}
    func update(
        id: Clip.ID,
        change: ClipUpdate
    ) async throws -> Clip { throw ClipStorageError.notFound(id) }
    func delete(id: Clip.ID) async throws {}
}
