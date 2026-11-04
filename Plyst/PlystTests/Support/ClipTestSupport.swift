//
//  ClipTestSupport.swift
//  PlystTests
//
//  Created by opfic on 11/4/26.
//

import Foundation
import XCTest
@testable import Plyst

/// 임시 폴더를 쓰는 테스트의 공용 기반
class ClipTemporaryDirectoryTestCase: XCTestCase {
    let directory = FileManager.default.temporaryDirectory.appendingPathComponent("Plyst-\(UUID())", isDirectory: true)
    var url: URL { directory.appendingPathComponent("clips.sqlite") }
    var root: URL { directory.appendingPathComponent("images", isDirectory: true) }

    override func tearDownWithError() throws {
        try ClipImageFileSystemTestFixture.restorePermissions(at: directory)
        if FileManager.default.fileExists(atPath: directory.path) { try FileManager.default.removeItem(at: directory) }
        try super.tearDownWithError()
    }

    func makeStorage() throws -> SQLiteClipStorageService {
        try SQLiteClipStorageService(databaseURL: url)
    }

    func makeAdapter(storage: any ClipStorageService) throws -> ClipBridgeAdapter {
        let images = ClipImageService(storage: storage, files: try ClipImageFileStore(rootURL: root))
        return ClipBridgeAdapter(
            storage: storage,
            history: try makeStorage(),
            images: images,
            clipboard: ClipboardService(storage: storage, images: images),
            photos: ClipPhotoLibraryService(storage: storage, images: images)
        )
    }
}

extension XCTestCase {
    /// 스트림의 이벤트가 기대한 순서로 도착하는지 검사
    func assertEvents(
        _ stream: AsyncStream<ClipStorageEvent>,
        expected: [ClipStorageEvent]
    ) async {
        let received = expectation(description: "확정된 저장 변경만 이벤트로 전달")
        let task = Task {
            var iterator = stream.makeAsyncIterator()
            for event in expected {
                let actual = await iterator.next()
                XCTAssertEqual(actual, event)
            }
            received.fulfill()
        }
        await fulfillment(of: [received], timeout: 2)
        task.cancel()
        await task.value
    }
}

/// 실제 저장소 호출 앞에 거부와 동작을 끼워 넣는 대역
actor ClipStorageServiceSpy: ClipStorageService {
    enum Operation: Hashable { case insert, delete, list }
    private let storage: SQLiteClipStorageService
    private var rejected = Set<Operation>()
    private var yieldsBeforeInsert = false
    private let beforeInsert: @Sendable (Clip) throws -> Void
    private let beforeUpdate: @Sendable () async throws -> Void
    private let beforeDelete: @Sendable (Clip.ID) throws -> Void

    init(
        storage: SQLiteClipStorageService,
        beforeInsert: @escaping @Sendable (Clip) throws -> Void = { _ in },
        beforeUpdate: @escaping @Sendable () async throws -> Void = {},
        beforeDelete: @escaping @Sendable (Clip.ID) throws -> Void = { _ in }
    ) {
        self.storage = storage
        self.beforeInsert = beforeInsert
        self.beforeUpdate = beforeUpdate
        self.beforeDelete = beforeDelete
    }

    func reject(_ operation: Operation) { rejected.insert(operation) }
    func allow(_ operation: Operation) { rejected.remove(operation) }
    func yieldBeforeInsert() { yieldsBeforeInsert = true }

    func fetchAll(order: ClipSortOrder) async throws -> [Clip] {
        if rejected.contains(.list) { throw ClipStorageError.readFailed }
        return try await storage.fetchAll(order: order)
    }

    func fetch(id: Clip.ID) async throws -> Clip? { try await storage.fetch(id: id) }

    func insert(_ clip: Clip) async throws {
        try beforeInsert(clip)
        if rejected.contains(.insert) { throw ClipStorageError.writeFailed }
        if yieldsBeforeInsert { await Task.yield() }
        try await storage.insert(clip)
    }

    func update(
        id: Clip.ID,
        change: ClipUpdate
    ) async throws -> Clip {
        try await beforeUpdate()
        return try await storage.update(id: id, change: change)
    }

    func delete(id: Clip.ID) async throws {
        try beforeDelete(id)
        if rejected.contains(.delete) { throw ClipStorageError.writeFailed }
        try await storage.delete(id: id)
    }

    func changes() async -> AsyncStream<ClipStorageEvent> { await storage.changes() }
}
