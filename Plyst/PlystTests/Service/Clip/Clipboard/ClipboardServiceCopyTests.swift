//
//  ClipboardServiceCopyTests.swift
//  PlystTests
//
//  Created by opfic on 9/29/26.
//

import Foundation
import SQLiteData
import XCTest
@testable import Plyst

@MainActor
final class ClipboardServiceCopyTests: XCTestCase {
    private let directory = FileManager.default.temporaryDirectory.appendingPathComponent("Plyst-copy-\(UUID())", isDirectory: true)
    private var url: URL { directory.appendingPathComponent("clips.sqlite") }

    override func tearDownWithError() throws {
        if FileManager.default.fileExists(atPath: directory.path) { try FileManager.default.removeItem(at: directory) }
        try super.tearDownWithError()
    }

    func testTextCopyPreservesOriginalAndDetailsAndCommitsUsageAndEvent() async throws {
        let storage = try SQLiteClipStorageService(databaseURL: url)
        let text = " \n한글 'text'\0🙂\nhttps://example.com/path?query=value\t "
        let clip = Clip(
            content: .text(text),
            name: "이름",
            isPinned: true,
            memo: "메모",
            createdAt: Date(timeIntervalSinceReferenceDate: 100),
            lastUsedAt: Date(timeIntervalSinceReferenceDate: 50)
        )
        try await storage.insert(clip)
        let stream = await storage.changes()
        let writer = ClipboardWriterSpy()
        let reader = ClipboardReaderSpy(result: .empty)
        let images = ClipImageService(
            storage: storage,
            files: try ClipImageFileStore(rootURL: directory.appendingPathComponent("images"))
        )
        let service = ClipboardService(
            storage: storage,
            images: images,
            reader: reader,
            writer: writer
        )
        XCTAssertEqual(writer.contents, [])
        let startedAt = Date()

        let result = try await service.copy(id: clip.id)

        guard case .copied(let updated) = result else { return XCTFail("복사 성공 결과 누락") }
        let usedAt = try XCTUnwrap(updated.lastUsedAt)
        XCTAssertEqual(updated, ClipUpdate.lastUsedAt(usedAt).applying(to: clip))
        XCTAssertLessThanOrEqual(startedAt, usedAt)
        XCTAssertLessThanOrEqual(usedAt, Date())
        XCTAssertEqual(writer.contents, [.text(text)])
        XCTAssertEqual(reader.readCount, 0)
        let reopened = try SQLiteClipStorageService(databaseURL: url)
        let restored = try await reopened.fetch(id: clip.id)
        XCTAssertEqual(restored, updated)
        await assertEvents(stream, expected: [.updated(updated)])
    }

    func testUnobservedWriteDoesNotUpdateUsageOrPublish() async throws {
        let storage = try SQLiteClipStorageService(databaseURL: url)
        let clip = Clip(content: .text("원문"), lastUsedAt: Date(timeIntervalSinceReferenceDate: 50))
        try await storage.insert(clip)
        let stream = await storage.changes()
        let spy = ClipboardStorageServiceSpy(storage: storage)
        let writer = ClipboardWriterSpy(result: .notObserved)
        let service = try makeService(storage: spy, writer: writer)

        let result = try await service.copy(id: clip.id)

        XCTAssertEqual(result, .writeNotObserved(clip.id))
        XCTAssertEqual(writer.contents, [.text("원문")])
        let updateCount = await spy.updateCount
        XCTAssertEqual(updateCount, 0)
        let preserved = try await storage.fetch(id: clip.id)
        XCTAssertEqual(preserved, clip)
        let sentinel = Clip(content: .text("검증"))
        try await storage.insert(sentinel)
        await assertEvents(stream, expected: [.inserted(sentinel)])
    }

    func testMissingClipDoesNotWriteOrUpdate() async throws {
        let storage = try SQLiteClipStorageService(databaseURL: url)
        let spy = ClipboardStorageServiceSpy(storage: storage)
        let writer = ClipboardWriterSpy()
        let service = try makeService(storage: spy, writer: writer)
        let id = UUID()

        do {
            _ = try await service.copy(id: id)
            XCTFail("없는 클립 복사 성공")
        } catch { XCTAssertEqual(error as? ClipStorageError, .notFound(id)) }

        XCTAssertEqual(writer.contents, [])
        let updateCount = await spy.updateCount
        XCTAssertEqual(updateCount, 0)
    }

    func testFailedUsageCommitReturnsCopiedResultWithoutRetryOrEvent() async throws {
        let storage = try SQLiteClipStorageService(databaseURL: url)
        let clip = Clip(content: .text("복사할 원문"), lastUsedAt: Date(timeIntervalSinceReferenceDate: 50))
        try await storage.insert(clip)
        let stream = await storage.changes()
        let writer = ClipboardWriterSpy()
        let service = try makeService(storage: storage, writer: writer)
        let connection = try DatabaseQueue(path: url.path)
        try await connection.write { database in
            try database.execute(sql: """
                CREATE TRIGGER rejectUsage AFTER UPDATE ON clips
                BEGIN SELECT RAISE(ABORT, 'Rejected update'); END
                """)
        }
        let startedAt = Date()

        let result = try await service.copy(id: clip.id)

        guard case let .copiedWithoutLastUsedAt(copied, copiedAt, failure) = result else { return XCTFail("부분 성공 결과 누락") }
        XCTAssertEqual(copied, clip)
        XCTAssertEqual(failure, .storage(.writeFailed))
        XCTAssertLessThanOrEqual(startedAt, copiedAt)
        XCTAssertLessThanOrEqual(copiedAt, Date())
        XCTAssertEqual(writer.contents, [.text("복사할 원문")])
        let preserved = try await storage.fetch(id: clip.id)
        XCTAssertEqual(preserved, clip)
        let sentinel = Clip(content: .text("검증"))
        try await storage.insert(sentinel)
        await assertEvents(stream, expected: [.inserted(sentinel)])
    }

    func testDeletionAfterWriteDoesNotRestoreClipOrRepeatCopy() async throws {
        let storage = try SQLiteClipStorageService(databaseURL: url)
        let clip = Clip(content: .text("복사한 뒤 삭제"))
        try await storage.insert(clip)
        let spy = ClipboardStorageServiceSpy(storage: storage, beforeUpdate: {
            try await storage.delete(id: clip.id)
        })
        let writer = ClipboardWriterSpy()
        let service = try makeService(storage: spy, writer: writer)

        let result = try await service.copy(id: clip.id)

        guard case let .copiedWithoutLastUsedAt(copied, _, failure) = result else { return XCTFail("삭제 경합의 부분 성공 결과 누락") }
        XCTAssertEqual(copied, clip)
        XCTAssertEqual(failure, .storage(.notFound(clip.id)))
        XCTAssertEqual(writer.contents, [.text("복사한 뒤 삭제")])
        let deleted = try await storage.fetch(id: clip.id)
        XCTAssertNil(deleted)
    }

    func testUnexpectedStorageErrorAfterCopyIsReportedWithoutExposingIt() async throws {
        let storage = try SQLiteClipStorageService(databaseURL: url)
        let clip = Clip(content: .text("원문"))
        try await storage.insert(clip)
        let spy = ClipboardStorageServiceSpy(storage: storage, beforeUpdate: { throw ClipboardCopyTestError.unexpected })
        let writer = ClipboardWriterSpy()
        let service = try makeService(storage: spy, writer: writer)

        let result = try await service.copy(id: clip.id)

        guard case let .copiedWithoutLastUsedAt(copied, _, failure) = result else { return XCTFail("알 수 없는 저장 오류의 부분 성공 결과 누락") }
        XCTAssertEqual(copied, clip)
        XCTAssertEqual(failure, .unknown)
        XCTAssertEqual(writer.contents, [.text("원문")])
        let preserved = try await storage.fetch(id: clip.id)
        XCTAssertEqual(preserved, clip)
    }

    func testReinsertedClipWithNewCreationTimeDoesNotReceiveOldCopyUsageOrEvent() async throws {
        let storage = try SQLiteClipStorageService(databaseURL: url)
        let clip = Clip(content: .text("같은 원문"), createdAt: Date(timeIntervalSinceReferenceDate: 100))
        let replacement = Clip(
            id: clip.id,
            content: clip.content,
            createdAt: Date(timeIntervalSinceReferenceDate: 200)
        )
        try await storage.insert(clip)
        let stream = await storage.changes()
        let spy = ClipboardStorageServiceSpy(storage: storage, beforeUpdate: {
            try await storage.delete(id: clip.id)
            try await storage.insert(replacement)
        })
        let writer = ClipboardWriterSpy()
        let service = try makeService(storage: spy, writer: writer)

        let result = try await service.copy(id: clip.id)

        guard case let .copiedWithoutLastUsedAt(copied, _, failure) = result else { return XCTFail("교체된 클립의 부분 성공 결과 누락") }
        XCTAssertEqual(copied, clip)
        XCTAssertEqual(failure, .replaced)
        XCTAssertEqual(writer.contents, [.text("같은 원문")])
        let preserved = try await storage.fetch(id: clip.id)
        XCTAssertEqual(preserved, replacement)
        let sentinel = Clip(content: .text("검증"))
        try await storage.insert(sentinel)
        await assertEvents(stream, expected: [.deleted(clip.id), .inserted(replacement), .inserted(sentinel)])
    }

    func testCopyUpdatesUsageWithoutOverwritingDetailsEditedAfterWrite() async throws {
        let storage = try SQLiteClipStorageService(databaseURL: url)
        let clip = Clip(content: .text("편집 중인 원문"))
        try await storage.insert(clip)
        let details = ClipUpdate.details(name: "새 이름", memo: "새 메모", isPinned: true)
        let spy = ClipboardStorageServiceSpy(storage: storage, beforeUpdate: {
            _ = try await storage.update(id: clip.id, change: details)
        })
        let writer = ClipboardWriterSpy()
        let service = try makeService(storage: spy, writer: writer)

        let result = try await service.copy(id: clip.id)

        guard case .copied(let copied) = result else { return XCTFail("상세 편집과 병행한 복사 성공 결과 누락") }
        let usedAt = try XCTUnwrap(copied.lastUsedAt)
        let expected = ClipUpdate.lastUsedAt(usedAt).applying(to: details.applying(to: clip))
        XCTAssertEqual(copied, expected)
        XCTAssertEqual(writer.contents, [.text("편집 중인 원문")])
        let stored = try await storage.fetch(id: clip.id)
        XCTAssertEqual(stored, expected)
    }

    private func makeService(
        storage: any ClipStorageService,
        writer: any ClipboardWriter
    ) throws -> ClipboardService {
        let files = try ClipImageFileStore(rootURL: directory.appendingPathComponent("images"))
        let images = ClipImageService(storage: storage, files: files)
        return ClipboardService(
            storage: storage,
            images: images,
            writer: writer
        )
    }

    private func assertEvents(
        _ stream: AsyncStream<ClipStorageEvent>,
        expected: [ClipStorageEvent]
    ) async {
        let received = expectation(description: "확정된 저장 변경만 전달")
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

private enum ClipboardCopyTestError: Error {
    case unexpected
}
