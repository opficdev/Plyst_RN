//
//  SQLiteClipStorageServiceTests.swift
//  PlystTests
//
//  Created by opfic on 9/29/26.
//

import Foundation
import XCTest
@testable import Plyst

final class SQLiteClipStorageServiceTests: ClipTemporaryDirectoryTestCase {
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
        let listed = try await restored.fetchAll(order: .createdAt)
        XCTAssertEqual(listed, [image, text])
    }

    func testEventsFollowCommitOrderAndUnchangedUpdatePublishesNothing() async throws {
        let storage = try SQLiteClipStorageService(databaseURL: url)
        let stream = await storage.changes()
        let clip = Clip(content: .text("원문"), name: "이름")
        try await storage.insert(clip)
        let change = ClipUpdate.details(name: "새 이름", memo: nil, isPinned: false, requestedAt: Date(timeIntervalSince1970: 300))
        let updated = try await storage.update(id: clip.id, change: change)
        let unchanged = try await storage.update(id: clip.id, change: change)
        try await storage.delete(id: clip.id)
        XCTAssertEqual(unchanged, updated)
        await assertEvents(stream, expected: [.inserted(clip), .updated(updated), .deleted(clip.id)])
    }

    func testStoreErrorsKeepTheirMeaning() async throws {
        let storage = try SQLiteClipStorageService(databaseURL: url)
        let clip = Clip(content: .text("원문"))
        await assertError(.notFound(clip.id)) { try await storage.delete(id: clip.id) }
        try await storage.insert(clip)
        await assertError(.duplicateID(clip.id)) { try await storage.insert(clip) }
        await assertError(.invalidContent) { try await storage.insert(Clip(content: .text("   "))) }
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

    private func assertError(_ expected: ClipStorageError, operation: () async throws -> Void) async {
        do {
            try await operation()
            XCTFail("저장소 작업이 예상한 오류 없이 성공함")
        } catch {
            XCTAssertEqual(error as? ClipStorageError, expected)
        }
    }
}
