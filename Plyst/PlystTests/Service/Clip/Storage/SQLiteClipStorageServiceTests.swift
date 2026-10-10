//
//  SQLiteClipStorageServiceTests.swift
//  PlystTests
//
//  Created by opfic on 9/29/26.
//

import Foundation
import SQLiteData
import XCTest
@testable import Plyst

final class SQLiteClipStorageServiceTests: XCTestCase {

    private let directory = FileManager.default.temporaryDirectory.appendingPathComponent("Plyst-\(UUID())", isDirectory: true)
    private var url: URL { directory.appendingPathComponent("clips.sqlite") }

    override func tearDownWithError() throws {
        if FileManager.default.fileExists(atPath: directory.path) {
            try FileManager.default.removeItem(at: directory)
        }
        try super.tearDownWithError()
    }

    func testEmptyStoreReturnsEmptyResultsAndMissingIdentifier() async throws {
        let storage = try SQLiteClipStorageService(databaseURL: url)
        let clips = try await storage.fetchAll(order: .createdAt)
        let missing = try await storage.fetch(id: UUID())
        XCTAssertEqual(clips, [])
        XCTAssertNil(missing)
    }

    func testTextAndImageMetadataAreRestoredByAnotherStorage() async throws {
        let text = Clip(
            content: .text("  한글 'text'\0🙂\nhttps://example.com  "), name: "", isPinned: true, memo: "메모\0끝",
            createdAt: Date(timeIntervalSinceReferenceDate: 793109282.0612345),
            lastUsedAt: Date(timeIntervalSinceReferenceDate: 793109300.1234567)
        )
        let image = Clip(content: .image(ClipImageMetadata(
            fileID: UUID(), contentType: "public.png", pixelWidth: 640, pixelHeight: 480, byteCount: 4096
        )))
        let storage = try SQLiteClipStorageService(databaseURL: url)
        try await storage.insert(text)
        try await storage.insert(image)
        let restored = try SQLiteClipStorageService(databaseURL: url)
        let restoredText = try await restored.fetch(id: text.id)
        let restoredImage = try await restored.fetch(id: image.id)
        XCTAssertEqual(restoredText, text)
        XCTAssertEqual(restoredImage, image)
    }

    func testDetailsPreserveLatestUsageAndDeletionPersists() async throws {
        let clip = Clip(content: .text("원문"), name: "이름", isPinned: true, memo: "메모")
        let storage = try SQLiteClipStorageService(databaseURL: url)
        let other = try SQLiteClipStorageService(databaseURL: url)
        try await storage.insert(clip)
        let date = Date(timeIntervalSinceReferenceDate: 800)
        _ = try await other.update(id: clip.id, change: .lastUsedAt(date))
        let updated = try await storage.update(id: clip.id, change: .details(name: nil, memo: nil, isPinned: false))
        XCTAssertEqual(updated.id, clip.id)
        XCTAssertEqual(updated.content, clip.content)
        XCTAssertEqual(updated.createdAt, clip.createdAt)
        XCTAssertEqual(updated.lastUsedAt, date)
        XCTAssertNil(updated.name)
        XCTAssertNil(updated.memo)
        XCTAssertFalse(updated.isPinned)
        try await storage.delete(id: clip.id)
        let deleted = try await other.fetch(id: clip.id)
        XCTAssertNil(deleted)
        await assertError(.notFound(clip.id)) { _ = try await storage.update(id: clip.id, change: .lastUsedAt(date)) }
        await assertError(.notFound(clip.id)) { try await storage.delete(id: clip.id) }
    }

    func testStoredDatesPreserveDeterministicCreationOrder() async throws {
        let first = makeClip(id: 1, createdAt: 300, lastUsedAt: 400)
        let second = makeClip(id: 2, createdAt: 300, lastUsedAt: 400)
        let recent = makeClip(id: 3, createdAt: 100, lastUsedAt: 500)
        let unused = makeClip(id: 4, createdAt: 600)
        let storage = try SQLiteClipStorageService(databaseURL: url)
        for clip in [unused, second, recent, first] { try await storage.insert(clip) }
        let created = try await storage.fetchAll(order: .createdAt)
        XCTAssertEqual(created, [unused, first, second, recent])
    }

    func testAllSubscribersReceiveChangesInCommitOrderWithoutReplay() async throws {
        let storage = try SQLiteClipStorageService(databaseURL: url)
        let first = await storage.changes()
        let second = await storage.changes()
        let clip = Clip(content: .text("원문"))
        try await storage.insert(clip)
        let late = await storage.changes()
        let updated = try await storage.update(id: clip.id, change: .details(name: "새 이름", memo: nil, isPinned: true))
        try await storage.delete(id: clip.id)
        let expected = [ClipStorageEvent.inserted(clip), .updated(updated), .deleted(clip.id)]
        await assertEvents(first, equalTo: expected)
        await assertEvents(second, equalTo: expected)
        await assertEvents(late, equalTo: [.updated(updated), .deleted(clip.id)])
    }

    func testDuplicateInvalidAndUnchangedWritesDoNotPublishEvents() async throws {
        let storage = try SQLiteClipStorageService(databaseURL: url)
        let clip = Clip(content: .text("원문"))
        try await storage.insert(clip)
        let stream = await storage.changes()
        await assertError(.duplicateID(clip.id)) { try await storage.insert(clip) }
        await assertError(.invalidContent) { try await storage.insert(Clip(content: .text(" \n\t"))) }
        let unchanged = try await storage.update(id: clip.id, change: .details(name: nil, memo: nil, isPinned: false))
        XCTAssertEqual(unchanged, clip)
        try await storage.delete(id: clip.id)
        await assertEvents(stream, equalTo: [.deleted(clip.id)])
    }

    func testFailedUpdateRollsBackAndDoesNotPublishAnEvent() async throws {
        let storage = try SQLiteClipStorageService(databaseURL: url)
        let clip = Clip(content: .text("원문"), name: "기존 이름")
        try await storage.insert(clip)
        let stream = await storage.changes()
        try execute("""
            CREATE TRIGGER rejectUpdate AFTER UPDATE ON clips
            BEGIN SELECT RAISE(ABORT, 'Rejected update'); END
            """)
        await assertError(.writeFailed) {
            _ = try await storage.update(id: clip.id, change: .details(name: "실패한 이름", memo: nil, isPinned: false))
        }
        let preserved = try await storage.fetch(id: clip.id)
        XCTAssertEqual(preserved, clip)
        try execute("DROP TRIGGER rejectUpdate")
        let updated = try await storage.update(id: clip.id, change: .details(name: "저장된 이름", memo: nil, isPinned: false))
        await assertEvents(stream, equalTo: [.updated(updated)])
    }

    func testCorruptedFileIsReportedWithoutReplacingItsContents() throws {
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let contents = Data("Invalid SQLite data".utf8)
        try contents.write(to: url)
        XCTAssertThrowsError(try SQLiteClipStorageService(databaseURL: url)) {
            XCTAssertEqual($0 as? ClipStorageError, .corruptedData)
        }
        XCTAssertEqual(try Data(contentsOf: url), contents)
    }

    func testInvalidStoredContentIsReportedAsCorruptedData() async throws {
        let storage = try SQLiteClipStorageService(databaseURL: url)
        let clip = Clip(content: .text("원문"))
        try await storage.insert(clip)
        try execute("UPDATE clips SET text = '   '")
        await assertError(.corruptedData) { _ = try await storage.fetch(id: clip.id) }
        await assertError(.corruptedData) { _ = try await storage.fetchAll(order: .createdAt) }
    }

    func testSchemaRejectsInvalidContentShapesAndStorageTypes() async throws {
        let storage = try SQLiteClipStorageService(databaseURL: url)
        let text = Clip(content: .text("원문"))
        let image = Clip(content: .image(ClipImageMetadata(
            fileID: UUID(), contentType: "public.png", pixelWidth: 640, pixelHeight: 480, byteCount: 4096
        )))
        try await storage.insert(text)
        try await storage.insert(image)
        let invalid = [
            "UPDATE clips SET kind = 'unknown' WHERE kind = 'text'",
            "UPDATE clips SET text = NULL WHERE kind = 'text'",
            "UPDATE clips SET imageFileID = 'file' WHERE kind = 'text'",
            "UPDATE clips SET createdAt = 'invalid'",
            "UPDATE clips SET isPinned = 2",
            "UPDATE clips SET text = 'text' WHERE kind = 'image'",
            "UPDATE clips SET imageFileID = NULL WHERE kind = 'image'",
            "UPDATE clips SET imageContentType = NULL WHERE kind = 'image'",
            "UPDATE clips SET pixelWidth = 0 WHERE kind = 'image'",
            "UPDATE clips SET pixelHeight = -1 WHERE kind = 'image'",
            "UPDATE clips SET byteCount = 0 WHERE kind = 'image'"
        ]
        for sql in invalid {
            XCTAssertThrowsError(try execute(sql)) {
                XCTAssertEqual(($0 as? DatabaseError)?.resultCode, .SQLITE_CONSTRAINT)
            }
        }
        let storedText = try await storage.fetch(id: text.id)
        let storedImage = try await storage.fetch(id: image.id)
        XCTAssertEqual(storedText, text)
        XCTAssertEqual(storedImage, image)
    }

    func testUnknownStoredKindIsReportedAsCorruptedData() async throws {
        let storage = try SQLiteClipStorageService(databaseURL: url)
        let clip = Clip(content: .text("원문"))
        try await storage.insert(clip)
        try execute("""
            PRAGMA ignore_check_constraints = ON;
            UPDATE clips SET kind = 'unknown';
            """)
        await assertError(.corruptedData) { _ = try await storage.fetch(id: clip.id) }
        await assertError(.corruptedData) { _ = try await storage.fetchAll(order: .createdAt) }
    }

    func testUnreadableLocationReturnsReadFailure() throws {
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        XCTAssertThrowsError(try SQLiteClipStorageService(databaseURL: url)) {
            XCTAssertEqual($0 as? ClipStorageError, .readFailed)
        }
    }

    func testCancelledInsertPreservesStorage() async throws {
        let storage = try SQLiteClipStorageService(databaseURL: url)
        let clip = Clip(content: .text("원문"))
        let task = Task {
            withUnsafeCurrentTask { $0?.cancel() }
            try await storage.insert(clip)
        }
        do {
            try await task.value
            XCTFail("취소된 작업이 성공함")
        } catch {
            XCTAssertTrue(error is CancellationError)
        }
        let stored = try await storage.fetch(id: clip.id)
        XCTAssertNil(stored)
    }

    func testStreamFinishesWhenStorageIsReleased() async throws {
        var storage: SQLiteClipStorageService? = try SQLiteClipStorageService(databaseURL: url)
        weak let reference = storage
        let pending = await storage?.changes()
        let stream = try XCTUnwrap(pending)
        let finished = expectation(description: "저장소 해제 후 스트림 종료")
        let task = Task {
            for await _ in stream { XCTFail("변경이 없는 저장소에서 이벤트 발생") }
            finished.fulfill()
        }
        defer { task.cancel() }
        storage = nil
        XCTAssertNil(reference)
        await fulfillment(of: [finished], timeout: 2)
    }

    private func assertEvents(_ stream: AsyncStream<ClipStorageEvent>, equalTo expected: [ClipStorageEvent]) async {
        let received = expectation(description: "저장 확정 순서로 이벤트 전달")
        let task = Task {
            var iterator = stream.makeAsyncIterator()
            for expectedEvent in expected {
                guard let event = await iterator.next() else { return }
                XCTAssertEqual(event, expectedEvent)
            }
            received.fulfill()
        }
        await fulfillment(of: [received], timeout: 2)
        task.cancel()
        await task.value
    }

    private func assertError(_ expected: ClipStorageError, operation: () async throws -> Void) async {
        do {
            try await operation()
            XCTFail("저장소 작업이 예상한 오류 없이 성공함")
        } catch {
            XCTAssertEqual(error as? ClipStorageError, expected)
        }
    }

    private func execute(_ sql: String) throws {
        let connection = try DatabaseQueue(path: url.path)
        try connection.write { try $0.execute(sql: sql) }
    }

    private func makeClip(id: UInt8, createdAt: TimeInterval, lastUsedAt: TimeInterval? = nil) -> Clip {
        Clip(
            id: UUID(uuid: (0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, id)), content: .text("원문"),
            createdAt: Date(timeIntervalSinceReferenceDate: createdAt),
            lastUsedAt: lastUsedAt.map { Date(timeIntervalSinceReferenceDate: $0) }
        )
    }
}
