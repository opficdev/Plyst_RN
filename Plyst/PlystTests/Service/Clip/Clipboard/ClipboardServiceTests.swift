//
//  ClipboardServiceTests.swift
//  PlystTests
//
//  Created by opfic on 9/29/26.
//

import Foundation
import SQLiteData
import XCTest
@testable import Plyst

@MainActor
final class ClipboardServiceTests: XCTestCase {
    private let directory = FileManager.default.temporaryDirectory.appendingPathComponent("Plyst-clipboard-\(UUID())", isDirectory: true)
    private var url: URL { directory.appendingPathComponent("clips.sqlite") }

    override func tearDownWithError() throws {
        if FileManager.default.fileExists(atPath: directory.path) {
            try FileManager.default.removeItem(at: directory)
        }
        try super.tearDownWithError()
    }

    func testSavedTextPreservesOriginalDefaultsAndBecomesLatestRecord() async throws {
        let storage = try SQLiteClipStorageService(databaseURL: url)
        let previous = Clip(content: .text("이전 기록"), createdAt: Date(timeIntervalSinceReferenceDate: 100))
        try await storage.insert(previous)
        let stream = await storage.changes()
        let text = " \n한글 'text'\0🙂\nhttps://example.com/path?query=value\t "
        let spy = ClipboardReaderSpy(result: .text(text))
        let service = try makeService(storage: storage, reader: spy)

        let clip = try savedClip(await service.saveCurrentClipboard())

        XCTAssertEqual(clip.content, .text(text))
        XCTAssertNil(clip.name)
        XCTAssertNil(clip.memo)
        XCTAssertNil(clip.pinnedAt)
        XCTAssertNil(clip.lastUsedAt)
        XCTAssertNotEqual(clip.id, previous.id)
        XCTAssertEqual(spy.readCount, 1)
        let stored = try await storage.fetchAll(order: .createdAt)
        XCTAssertEqual(stored, [clip, previous])
        let reopened = try SQLiteClipStorageService(databaseURL: url)
        let restored = try await reopened.fetch(id: clip.id)
        XCTAssertEqual(restored, clip)
        await assertEvents(stream, expected: [.inserted(clip)])
    }

    func testURLTextIsStoredWithoutChangingItsRepresentation() async throws {
        let storage = try SQLiteClipStorageService(databaseURL: url)
        let text = "https://example.com/a%20b?query=value#section"
        let spy = ClipboardReaderSpy(result: .text(text))
        let service = try makeService(storage: storage, reader: spy)

        let clip = try savedClip(await service.saveCurrentClipboard())

        XCTAssertEqual(clip.content, .text(text))
        let stored = try await storage.fetch(id: clip.id)
        XCTAssertEqual(stored, clip)
    }

    private func makeService(
        storage: any ClipStorageService,
        reader: any ClipboardReader
    ) throws -> ClipboardService {
        let files = try ClipImageFileStore(rootURL: directory.appendingPathComponent("images", isDirectory: true))
        let images = ClipImageService(storage: storage, files: files)
        return ClipboardService(
            storage: storage,
            images: images,
            reader: reader
        )
    }

    private func savedClip(_ result: ClipboardSaveResult) throws -> Clip {
        guard case .saved(let clip) = result else {
            XCTFail("저장 성공 결과 누락")
            throw ClipboardTestError.unexpectedResult
        }
        return clip
    }

    private func assertEvents(
        _ stream: AsyncStream<ClipStorageEvent>,
        expected: [ClipStorageEvent]
    ) async {
        let received = expectation(description: "저장 확정 이후의 이벤트만 전달")
        let task = Task {
            var iterator = stream.makeAsyncIterator()
            for expectedEvent in expected {
                let event = await iterator.next()
                XCTAssertEqual(event, expectedEvent)
            }
            received.fulfill()
        }
        await fulfillment(of: [received], timeout: 2)
        task.cancel()
        await task.value
    }

    private func execute(_ sql: String) throws {
        let connection = try DatabaseQueue(path: url.path)
        try connection.write { try $0.execute(sql: sql) }
    }
}

@MainActor
final class ClipboardReaderSpy: ClipboardReader {
    var result: ClipboardReadResult
    private(set) var readCount = 0
    private let onRead: () throws -> Void

    init(
        result: ClipboardReadResult,
        onRead: @escaping () throws -> Void = {}
    ) {
        self.result = result
        self.onRead = onRead
    }

    @MainActor
    func read() async throws -> ClipboardReadResult {
        readCount += 1
        try onRead()
        return result
    }
}

actor ClipboardStorageServiceSpy: ClipStorageService {
    private let storage: SQLiteClipStorageService
    private let beforeInsert: @Sendable () throws -> Void
    private let afterInsert: @Sendable () -> Void
    private let afterFetch: @Sendable () async throws -> Void
    private let beforeUpdate: @Sendable () async throws -> Void
    private let afterUpdate: @Sendable () -> Void
    private(set) var insertCount = 0
    private(set) var updateCount = 0

    init(
        storage: SQLiteClipStorageService,
        beforeInsert: @escaping @Sendable () throws -> Void = {},
        afterInsert: @escaping @Sendable () -> Void = {},
        afterFetch: @escaping @Sendable () async throws -> Void = {},
        beforeUpdate: @escaping @Sendable () async throws -> Void = {},
        afterUpdate: @escaping @Sendable () -> Void = {}
    ) {
        self.storage = storage
        self.beforeInsert = beforeInsert
        self.afterInsert = afterInsert
        self.afterFetch = afterFetch
        self.beforeUpdate = beforeUpdate
        self.afterUpdate = afterUpdate
    }

    func fetchAll(order: ClipSortOrder) async throws -> [Clip] {
        try await storage.fetchAll(order: order)
    }

    func fetch(id: Clip.ID) async throws -> Clip? {
        let clip = try await storage.fetch(id: id)
        try await afterFetch()
        return clip
    }

    func insert(_ clip: Clip) async throws {
        insertCount += 1
        try beforeInsert()
        try await storage.insert(clip)
        afterInsert()
    }

    func update(
        id: Clip.ID,
        change: ClipUpdate
    ) async throws -> Clip {
        updateCount += 1
        try await beforeUpdate()
        let clip = try await storage.update(id: id, change: change)
        afterUpdate()
        return clip
    }

    func delete(id: Clip.ID) async throws {
        try await storage.delete(id: id)
    }

    func changes() async -> AsyncStream<ClipStorageEvent> {
        await storage.changes()
    }
}

private enum ClipboardTestError: Error {
    case unexpectedResult
}
