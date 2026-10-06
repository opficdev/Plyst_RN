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
        XCTAssertFalse(clip.isPinned)
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

    func testNonSavableResultsDoNotInsertOrPublishAndPreserveExistingRecord() async throws {
        let storage = try SQLiteClipStorageService(databaseURL: url)
        let previous = Clip(content: .text("기존 기록"))
        try await storage.insert(previous)
        let stream = await storage.changes()
        let spy = ClipboardStorageServiceSpy(storage: storage)
        let reader = ClipboardReaderSpy(result: .empty)
        let service = try makeService(storage: spy, reader: reader)
        let cases = [
            (ClipboardReadResult.empty, ClipboardSaveResult.empty),
            (.text(""), .empty),
            (.text("   "), .empty),
            (.text("\n\r\t "), .empty),
            (.unsupported, .unsupported),
            (.accessFailed, .accessFailed)
        ]

        for (input, expected) in cases {
            reader.result = input
            let result = try await service.saveCurrentClipboard()
            XCTAssertEqual(result, expected)
        }

        let insertCount = await spy.insertCount
        let stored = try await storage.fetchAll(order: .createdAt)
        XCTAssertEqual(insertCount, 0)
        XCTAssertEqual(reader.readCount, cases.count)
        XCTAssertEqual(stored, [previous])
        // 후속 확정 이벤트까지 비교하여 저장하지 않은 요청이 이벤트를 발행하지 않았는지 확인합니다.
        let sentinel = Clip(content: .text("검증"))
        try await storage.insert(sentinel)
        await assertEvents(stream, expected: [.inserted(sentinel)])
    }

    func testInitializationDoesNotReadAndEachExplicitRequestCreatesANewRecord() async throws {
        let storage = try SQLiteClipStorageService(databaseURL: url)
        let stream = await storage.changes()
        let spy = ClipboardReaderSpy(result: .text("같은 원문"))
        let service = try makeService(storage: storage, reader: spy)
        XCTAssertEqual(spy.readCount, 0)

        let first = try savedClip(await service.saveCurrentClipboard())
        let second = try savedClip(await service.saveCurrentClipboard())

        XCTAssertNotEqual(first.id, second.id)
        XCTAssertEqual(first.content, second.content)
        XCTAssertEqual(spy.readCount, 2)
        let stored = try await storage.fetchAll(order: .createdAt)
        XCTAssertEqual(Set(stored.map(\.id)), Set([first.id, second.id]))
        await assertEvents(stream, expected: [.inserted(first), .inserted(second)])
    }

    func testFailedInsertPreservesStorageErrorRecordsAndEvents() async throws {
        let storage = try SQLiteClipStorageService(databaseURL: url)
        let previous = Clip(content: .text("기존 기록"))
        try await storage.insert(previous)
        let stream = await storage.changes()
        let spy = ClipboardStorageServiceSpy(storage: storage)
        let reader = ClipboardReaderSpy(result: .text("실패한 기록"))
        let service = try makeService(storage: spy, reader: reader)
        try execute("""
            CREATE TRIGGER rejectInsert AFTER INSERT ON clips
            BEGIN SELECT RAISE(ABORT, 'Rejected insert'); END
            """)

        do {
            _ = try await service.saveCurrentClipboard()
            XCTFail("실패하도록 설정한 저장 성공")
        } catch { XCTAssertEqual(error as? ClipStorageError, .writeFailed) }

        let insertCount = await spy.insertCount
        let stored = try await storage.fetchAll(order: .createdAt)
        XCTAssertEqual(insertCount, 1)
        XCTAssertEqual(stored, [previous])
        try execute("DROP TRIGGER rejectInsert")
        let sentinel = Clip(content: .text("검증"))
        try await storage.insert(sentinel)
        await assertEvents(stream, expected: [.inserted(sentinel)])
    }

    func testCancellationBeforeReadingDoesNotReadInsertOrPublish() async throws {
        let storage = try SQLiteClipStorageService(databaseURL: url)
        let stream = await storage.changes()
        let spy = ClipboardStorageServiceSpy(storage: storage)
        let reader = ClipboardReaderSpy(result: .text("취소된 기록"))
        let service = try makeService(storage: spy, reader: reader)
        let task = Task {
            withUnsafeCurrentTask { $0?.cancel() }
            return try await service.saveCurrentClipboard()
        }

        do {
            _ = try await task.value
            XCTFail("취소된 저장 성공")
        } catch { XCTAssertTrue(error is CancellationError) }

        let insertCount = await spy.insertCount
        let stored = try await storage.fetchAll(order: .createdAt)
        XCTAssertEqual(reader.readCount, 0)
        XCTAssertEqual(insertCount, 0)
        XCTAssertEqual(stored, [])
        let sentinel = Clip(content: .text("검증"))
        try await storage.insert(sentinel)
        await assertEvents(stream, expected: [.inserted(sentinel)])
    }

    func testCancellationDuringReadingPreventsInsertAndEvents() async throws {
        let storage = try SQLiteClipStorageService(databaseURL: url)
        let stream = await storage.changes()
        let spy = ClipboardStorageServiceSpy(storage: storage)
        let reader = ClipboardReaderSpy(result: .text("취소된 기록"), onRead: {
            withUnsafeCurrentTask { $0?.cancel() }
        })
        let service = try makeService(storage: spy, reader: reader)
        let task = Task { try await service.saveCurrentClipboard() }

        do {
            _ = try await task.value
            XCTFail("읽는 동안 취소된 저장 성공")
        } catch { XCTAssertTrue(error is CancellationError) }

        let insertCount = await spy.insertCount
        let stored = try await storage.fetchAll(order: .createdAt)
        XCTAssertEqual(reader.readCount, 1)
        XCTAssertEqual(insertCount, 0)
        XCTAssertEqual(stored, [])
        let sentinel = Clip(content: .text("검증"))
        try await storage.insert(sentinel)
        await assertEvents(stream, expected: [.inserted(sentinel)])
    }

    func testStorageCancellationIsPropagatedWithoutRecordOrEvent() async throws {
        let storage = try SQLiteClipStorageService(databaseURL: url)
        let stream = await storage.changes()
        let spy = ClipboardStorageServiceSpy(storage: storage, beforeInsert: { throw CancellationError() })
        let reader = ClipboardReaderSpy(result: .text("취소된 기록"))
        let service = try makeService(storage: spy, reader: reader)

        do {
            _ = try await service.saveCurrentClipboard()
            XCTFail("저장소에서 취소된 저장 성공")
        } catch { XCTAssertTrue(error is CancellationError) }

        let stored = try await storage.fetchAll(order: .createdAt)
        XCTAssertEqual(stored, [])
        let sentinel = Clip(content: .text("검증"))
        try await storage.insert(sentinel)
        await assertEvents(stream, expected: [.inserted(sentinel)])
    }

    func testCancellationAfterCommitReturnsSavedRecord() async throws {
        let storage = try SQLiteClipStorageService(databaseURL: url)
        let stream = await storage.changes()
        let spy = ClipboardStorageServiceSpy(storage: storage, afterInsert: {
            withUnsafeCurrentTask { $0?.cancel() }
        })
        let reader = ClipboardReaderSpy(result: .text("확정된 기록"))
        let service = try makeService(storage: spy, reader: reader)
        let task = Task { try await service.saveCurrentClipboard() }

        let clip = try savedClip(await task.value)

        XCTAssertTrue(task.isCancelled)
        let stored = try await storage.fetch(id: clip.id)
        XCTAssertEqual(stored, clip)
        await assertEvents(stream, expected: [.inserted(clip)])
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
