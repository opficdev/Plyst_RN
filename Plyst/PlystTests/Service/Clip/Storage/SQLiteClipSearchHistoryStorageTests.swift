//
//  SQLiteClipSearchHistoryStorageTests.swift
//  PlystTests
//
//  Created by opfic on 9/30/26.
//

import Foundation
import SQLiteData
import XCTest
@testable import Plyst

final class SQLiteClipSearchHistoryStorageTests: XCTestCase {
    private let directory = FileManager.default.temporaryDirectory.appendingPathComponent("Plyst-\(UUID())", isDirectory: true)
    private var url: URL { directory.appendingPathComponent("clips.sqlite") }

    override func tearDownWithError() throws {
        if FileManager.default.fileExists(atPath: directory.path) {
            try FileManager.default.removeItem(at: directory)
        }
        try super.tearDownWithError()
    }

    func testEmptyStoreReturnsEmptyHistory() async throws {
        let storage = try SQLiteClipStorageService(databaseURL: url)

        let history = try await storage.fetchSearchHistory()

        XCTAssertEqual(history, ClipSearchHistory())
    }

    func testRecordedTermsAreRestoredInOrderByAnotherStorage() async throws {
        let storage = try SQLiteClipStorageService(databaseURL: url)
        _ = try await storage.recordSearchTerm(try query("first"))
        _ = try await storage.recordSearchTerm(try query("second"))

        let restored = try SQLiteClipStorageService(databaseURL: url)
        let history = try await restored.fetchSearchHistory()

        XCTAssertEqual(history.terms, ["second", "first"])
    }

    func testStorageKeepsAtMostFiveTermsWithContiguousPositions() async throws {
        let storage = try SQLiteClipStorageService(databaseURL: url)

        for term in ["1", "2", "3", "4", "5", "6", "7"] {
            _ = try await storage.recordSearchTerm(try query(term))
        }

        let history = try await storage.fetchSearchHistory()
        XCTAssertEqual(history.terms, ["7", "6", "5", "4", "3"])
        XCTAssertEqual(try positions(), [0, 1, 2, 3, 4])
    }

    func testRecordingDuplicateMovesItToFrontWithoutDuplicates() async throws {
        let storage = try SQLiteClipStorageService(databaseURL: url)
        _ = try await storage.recordSearchTerm(try query("qr"))
        _ = try await storage.recordSearchTerm(try query("swift"))

        let history = try await storage.recordSearchTerm(try query("QR"))

        XCTAssertEqual(history.terms, ["QR", "swift"])
        let stored = try await storage.fetchSearchHistory()
        XCTAssertEqual(stored, history)
    }

    func testRemoveSearchTermDeletesOnlyThatTermAndIgnoresMissingTerm() async throws {
        let storage = try SQLiteClipStorageService(databaseURL: url)
        _ = try await storage.recordSearchTerm(try query("alpha"))
        _ = try await storage.recordSearchTerm(try query("beta"))

        let removed = try await storage.removeSearchTerm("ALPHA")
        let unchanged = try await storage.removeSearchTerm("missing")

        XCTAssertEqual(removed.terms, ["beta"])
        XCTAssertEqual(unchanged, removed)
        let stored = try await storage.fetchSearchHistory()
        XCTAssertEqual(stored, removed)
    }

    func testRemoveAllClearsHistoryAndPersists() async throws {
        let storage = try SQLiteClipStorageService(databaseURL: url)
        _ = try await storage.recordSearchTerm(try query("alpha"))

        try await storage.removeAllSearchTerms()

        let restored = try SQLiteClipStorageService(databaseURL: url)
        let history = try await restored.fetchSearchHistory()
        XCTAssertEqual(history, ClipSearchHistory())
    }

    func testUnchangedResultDoesNotWriteAndFailedWriteRollsBack() async throws {
        let storage = try SQLiteClipStorageService(databaseURL: url)
        let recorded = try await storage.recordSearchTerm(try query("alpha"))
        try execute("""
            CREATE TRIGGER rejectInsert BEFORE INSERT ON clipSearchTerms
            BEGIN SELECT RAISE(ABORT, 'Rejected insert'); END
            """)

        let unchanged = try await storage.recordSearchTerm(try query("alpha"))
        await assertError(.writeFailed) {
            _ = try await storage.recordSearchTerm(try query("beta"))
        }

        XCTAssertEqual(unchanged, recorded)
        try execute("DROP TRIGGER rejectInsert")
        let preserved = try await storage.fetchSearchHistory()
        XCTAssertEqual(preserved, recorded)
    }

    func testCorruptedRowsAreReportedAndRemovedByRemoveAll() async throws {
        let storage = try SQLiteClipStorageService(databaseURL: url)
        try execute("INSERT INTO clipSearchTerms (position, term) VALUES (0, 'a'), (1, 'A')")

        await assertError(.corruptedData) { _ = try await storage.fetchSearchHistory() }
        await assertError(.corruptedData) { _ = try await storage.recordSearchTerm(try query("b")) }
        try await storage.removeAllSearchTerms()

        let history = try await storage.fetchSearchHistory()
        XCTAssertEqual(history, ClipSearchHistory())
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

    func testSearchTermChangesDoNotPublishClipEvents() async throws {
        let storage = try SQLiteClipStorageService(databaseURL: url)
        let stream = await storage.changes()
        let clip = Clip(content: .text("원문"))

        _ = try await storage.recordSearchTerm(try query("alpha"))
        _ = try await storage.removeSearchTerm("alpha")
        try await storage.removeAllSearchTerms()
        try await storage.insert(clip)

        await assertFirstEvent(stream, equalTo: .inserted(clip))
    }

    func testCancelledRecordPreservesHistory() async throws {
        let storage = try SQLiteClipStorageService(databaseURL: url)
        let term = try query("alpha")
        let task = Task {
            withUnsafeCurrentTask { $0?.cancel() }
            return try await storage.recordSearchTerm(term)
        }

        do {
            _ = try await task.value
            XCTFail("취소된 작업이 성공함")
        } catch {
            XCTAssertTrue(error is CancellationError)
        }

        let history = try await storage.fetchSearchHistory()
        XCTAssertEqual(history, ClipSearchHistory())
    }

    private func assertFirstEvent(
        _ stream: AsyncStream<ClipStorageEvent>,
        equalTo expected: ClipStorageEvent
    ) async {
        let received = expectation(description: "검색어 변경은 이벤트를 발행하지 않음")
        let task = Task {
            var iterator = stream.makeAsyncIterator()
            guard let event = await iterator.next() else { return }
            XCTAssertEqual(event, expected)
            received.fulfill()
        }
        await fulfillment(of: [received], timeout: 2)
        task.cancel()
        await task.value
    }

    private func assertError(
        _ expected: ClipStorageError,
        operation: () async throws -> Void
    ) async {
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

    private func positions() throws -> [Int] {
        let connection = try DatabaseQueue(path: url.path)
        return try connection.read { try Int.fetchAll($0, sql: "SELECT position FROM clipSearchTerms ORDER BY position") }
    }

    private func execute(_ sql: String) throws {
        let connection = try DatabaseQueue(path: url.path)
        try connection.write { try $0.execute(sql: sql) }
    }
}
