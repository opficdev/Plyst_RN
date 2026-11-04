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

    func testTextAndImageMetadataAreRestoredByAnotherStorage() async throws {
        let text = Clip(
            content: .text("  한글 'text'\0🙂\nhttps://example.com  "),
            name: "",
            pinnedAt: Date(timeIntervalSinceReferenceDate: 793109290.0612345),
            memo: "메모\0끝",
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
        let clip = Clip(
            content: .text("원문"),
            name: "이름",
            pinnedAt: Date(timeIntervalSince1970: 100),
            memo: "메모"
        )
        let storage = try SQLiteClipStorageService(databaseURL: url)
        let other = try SQLiteClipStorageService(databaseURL: url)
        try await storage.insert(clip)
        let date = Date(timeIntervalSinceReferenceDate: 800)
        _ = try await other.update(id: clip.id, change: .lastUsedAt(date))
        let updated = try await storage.update(id: clip.id, change: .details(name: nil, memo: nil, isPinned: false, requestedAt: Date(timeIntervalSince1970: 300)))
        XCTAssertEqual(updated.id, clip.id)
        XCTAssertEqual(updated.content, clip.content)
        XCTAssertEqual(updated.createdAt, clip.createdAt)
        XCTAssertEqual(updated.lastUsedAt, date)
        XCTAssertNil(updated.name)
        XCTAssertNil(updated.memo)
        XCTAssertNil(updated.pinnedAt)
        try await storage.delete(id: clip.id)
        let deleted = try await other.fetch(id: clip.id)
        XCTAssertNil(deleted)
        await assertError(.notFound(clip.id)) { _ = try await storage.update(id: clip.id, change: .lastUsedAt(date)) }
        await assertError(.notFound(clip.id)) { try await storage.delete(id: clip.id) }
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
            _ = try await storage.update(id: clip.id, change: .details(name: "실패한 이름", memo: nil, isPinned: false, requestedAt: Date(timeIntervalSince1970: 300)))
        }
        let preserved = try await storage.fetch(id: clip.id)
        XCTAssertEqual(preserved, clip)
        try execute("DROP TRIGGER rejectUpdate")
        let updated = try await storage.update(id: clip.id, change: .details(name: "저장된 이름", memo: nil, isPinned: false, requestedAt: Date(timeIntervalSince1970: 300)))
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
            "UPDATE clips SET pinnedAt = 'invalid'",
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

    func testNonFiniteStoredPinTimeIsReportedAsCorruptedData() async throws {
        let storage = try SQLiteClipStorageService(databaseURL: url)
        let clip = Clip(content: .text("원문"))
        try await storage.insert(clip)
        try execute("UPDATE clips SET pinnedAt = 1e999")
        await assertError(.corruptedData) { _ = try await storage.fetch(id: clip.id) }
        await assertError(.corruptedData) { _ = try await storage.fetchAll(order: .createdAt) }
    }

    func testNonFinitePinTimeIsRejectedBeforeWriting() async throws {
        let storage = try SQLiteClipStorageService(databaseURL: url)
        let clip = Clip(content: .text("원문"), pinnedAt: Date(timeIntervalSinceReferenceDate: .infinity))
        await assertError(.invalidContent) { try await storage.insert(clip) }
    }

    func testRecordedTermsAreRestoredInOrderByAnotherStorage() async throws {
        let storage = try SQLiteClipStorageService(databaseURL: url)
        _ = try await storage.recordSearchTerm(try query("first"))
        _ = try await storage.recordSearchTerm(try query("second"))

        let restored = try SQLiteClipStorageService(databaseURL: url)
        let history = try await restored.fetchSearchHistory()

        XCTAssertEqual(history.terms, ["second", "first"])
    }

    func testVersionOneDatabaseGainsSearchTermsAndKeepsClips() async throws {
        let clip = Clip(content: .text("원문"))
        let original = try SQLiteClipStorageService(databaseURL: url)
        try await original.insert(clip)
        try execute("DROP TABLE clipSearchTerms")
        try execute("DELETE FROM grdb_migrations WHERE identifier = 'CreateClipSearchTerms'")

        let upgraded = try SQLiteClipStorageService(databaseURL: url)
        let stored = try await upgraded.fetch(id: clip.id)
        let empty = try await upgraded.fetchSearchHistory()
        let recorded = try await upgraded.recordSearchTerm(try query("alpha"))
        let reopened = try SQLiteClipStorageService(databaseURL: url)
        let restored = try await reopened.fetchSearchHistory()

        XCTAssertEqual(stored, clip)
        XCTAssertEqual(empty, ClipSearchHistory())
        XCTAssertEqual(restored, recorded)
    }

    func testUnknownMigrationIsRejectedAsDowngrade() throws {
        _ = try SQLiteClipStorageService(databaseURL: url)
        try execute("INSERT INTO grdb_migrations (identifier) VALUES ('FutureMigration')")

        XCTAssertThrowsError(try SQLiteClipStorageService(databaseURL: url)) {
            XCTAssertEqual($0 as? ClipStorageError, .corruptedData)
        }
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

    private func query(_ raw: String) throws -> ClipSearchQuery {
        try XCTUnwrap(ClipSearchQuery(raw))
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
