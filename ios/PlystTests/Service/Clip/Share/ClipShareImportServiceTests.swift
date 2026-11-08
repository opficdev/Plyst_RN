//
//  ClipShareImportServiceTests.swift
//  PlystTests
//
//  Created by opfic on 10/2/26.
//

import Foundation
import XCTest
@testable import Plyst

@MainActor
final class ClipShareImportServiceTests: ClipTemporaryDirectoryTestCase {
    private var inboxDatabaseURL: URL { directory.appendingPathComponent("ShareInbox.sqlite") }
    private var inboxImagesURL: URL { directory.appendingPathComponent("ShareInboxImages", isDirectory: true) }
    func testTextClipIsImportedWithOriginalFieldsAndRemovedFromInbox() async throws {
        let inbox = try makeInbox()
        let clip = Clip(
            content: .text("공유한 텍스트"),
            name: "공유 제목",
            createdAt: Date(timeIntervalSince1970: 100)
        )
        try await inbox.insert(clip)
        let core = try makeCore()
        let events = core.changes()
        var iterator = events.makeAsyncIterator()

        let result = try await makeService(core: core).importPendingClips()

        XCTAssertEqual(
            result,
            ClipShareImportResult(
                importedCount: 1,
                remainingCount: 0,
                hasPendingCleanup: false
            )
        )
        let stored = try await core.fetchAll(order: .createdAt)
        XCTAssertEqual(stored, [clip])
        let event = await iterator.next()
        XCTAssertEqual(event, .inserted(clip))
        let remaining = try await inbox.fetchAll(order: .createdAt)
        XCTAssertTrue(remaining.isEmpty)
    }

    func testImageClipIsImportedWithSameBytesAndRemovedFromInbox() async throws {
        let inbox = try makeInbox()
        let data = try ClipImageTestFixture.data()
        let saved = try await inbox.saveImage(
            data,
            name: "공유 이미지",
            createdAt: Date(timeIntervalSince1970: 100)
        ).value
        let core = try makeCore()

        let result = try await makeService(core: core).importPendingClips()

        XCTAssertEqual(result.importedCount, 1)
        XCTAssertEqual(result.remainingCount, 0)
        let fetched = try await core.fetch(id: saved.id)
        let imported = try XCTUnwrap(fetched)
        XCTAssertEqual(imported.name, "공유 이미지")
        XCTAssertEqual(imported.createdAt, saved.createdAt)
        guard case .image(let metadata) = imported.content else { return XCTFail("이미지 클립이 아님") }
        let loaded = try await core.loadImage(metadata)
        XCTAssertEqual(loaded, data)
        let remaining = try await inbox.fetchAll(order: .createdAt)
        XCTAssertTrue(remaining.isEmpty)
        XCTAssertEqual(try entryCount(at: inboxImagesURL), 0)
        XCTAssertEqual(try entryCount(at: root), 1)
    }

    func testClipAlreadyInStorageIsNotDuplicatedAndIsRemovedFromInbox() async throws {
        let inbox = try makeInbox()
        let clip = Clip(content: .text("이미 반입된 텍스트"))
        try await inbox.insert(clip)
        let core = try makeCore()
        try await core.insert(clip)

        let result = try await makeService(core: core).importPendingClips()

        XCTAssertEqual(result, .empty)
        let stored = try await core.fetchAll(order: .createdAt)
        XCTAssertEqual(stored, [clip])
        let remaining = try await inbox.fetchAll(order: .createdAt)
        XCTAssertTrue(remaining.isEmpty)
    }

    func testSaveFailureKeepsClipInInboxAndNextImportSucceeds() async throws {
        let inbox = try makeInbox()
        let clip = try await inbox.saveImage(ClipImageTestFixture.data()).value
        let core = try makeCore()
        let service = makeService(core: core)
        // 어댑터가 이미지 루트를 만든 뒤에 쓰기를 막음
        try ClipImageFileSystemTestFixture.makeReadOnly(root)

        let first = try await service.importPendingClips()

        XCTAssertEqual(
            first,
            ClipShareImportResult(
                importedCount: 0,
                remainingCount: 1,
                hasPendingCleanup: false
            )
        )
        let kept = try await inbox.fetchAll(order: .createdAt)
        XCTAssertEqual(kept, [clip])
        let empty = try await core.fetchAll(order: .createdAt)
        XCTAssertTrue(empty.isEmpty)

        try ClipImageFileSystemTestFixture.restorePermissions(at: root)
        let second = try await service.importPendingClips()

        XCTAssertEqual(second.importedCount, 1)
        XCTAssertEqual(second.remainingCount, 0)
        let stored = try await core.fetchAll(order: .createdAt)
        XCTAssertEqual(stored.map(\.id), [clip.id])
        let remaining = try await inbox.fetchAll(order: .createdAt)
        XCTAssertTrue(remaining.isEmpty)
    }

    func testCorruptedInboxImageStaysWhileOtherClipsAreImported() async throws {
        let inbox = try makeInbox()
        let image = try await inbox.saveImage(
            try ClipImageTestFixture.data(),
            createdAt: Date(timeIntervalSince1970: 100)
        ).value
        let text = Clip(
            content: .text("함께 공유한 텍스트"),
            createdAt: Date(timeIntervalSince1970: 200)
        )
        try await inbox.insert(text)
        guard case .image(let metadata) = image.content else { return XCTFail("이미지 클립이 아님") }
        let original = inboxImagesURL
            .appendingPathComponent(metadata.fileID.uuidString, isDirectory: true)
            .appendingPathComponent("original")
        try Data([0x01, 0x02, 0x03]).write(to: original)
        let core = try makeCore()

        let result = try await makeService(core: core).importPendingClips()

        XCTAssertEqual(
            result,
            ClipShareImportResult(
                importedCount: 1,
                remainingCount: 1,
                hasPendingCleanup: false
            )
        )
        let stored = try await core.fetchAll(order: .createdAt)
        XCTAssertEqual(stored, [text])
        let remaining = try await inbox.fetchAll(order: .createdAt)
        XCTAssertEqual(remaining, [image])
    }

    func testCancelledImportThrowsCancellationAndKeepsInbox() async throws {
        let inbox = try makeInbox()
        let clip = Clip(content: .text("취소 전 텍스트"))
        try await inbox.insert(clip)
        let core = try makeCore()
        let service = makeService(core: core)

        let task = Task {
            try await service.importPendingClips()
        }
        task.cancel()

        do {
            _ = try await task.value
            XCTFail("취소 전파 누락")
        } catch {
            XCTAssertTrue(error is CancellationError)
        }
        let stored = try await core.fetchAll(order: .createdAt)
        XCTAssertTrue(stored.isEmpty)
        let remaining = try await inbox.fetchAll(order: .createdAt)
        XCTAssertEqual(remaining, [clip])
    }

    private func makeInbox() throws -> ClipCoreAdapter {
        try ClipCoreAdapter(
            databaseURL: inboxDatabaseURL,
            imagesURL: inboxImagesURL
        )
    }

    private func makeService(core: ClipCoreAdapter) -> ClipShareImportService {
        ClipShareImportService(
            inboxDatabaseURL: inboxDatabaseURL,
            inboxImagesURL: inboxImagesURL,
            core: core
        )
    }
}
