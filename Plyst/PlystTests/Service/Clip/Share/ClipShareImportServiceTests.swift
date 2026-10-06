//
//  ClipShareImportServiceTests.swift
//  PlystTests
//
//  Created by opfic on 10/2/26.
//

import Foundation
import os
import UIKit
import XCTest
@testable import Plyst

@MainActor
final class ClipShareImportServiceTests: XCTestCase {
    private let directory = FileManager.default.temporaryDirectory.appendingPathComponent("Plyst-import-\(UUID())", isDirectory: true)
    private var inboxDatabaseURL: URL { directory.appendingPathComponent("ShareInbox.sqlite") }
    private var inboxImagesURL: URL { directory.appendingPathComponent("ShareInboxImages", isDirectory: true) }
    private var databaseURL: URL { directory.appendingPathComponent("clips.sqlite") }
    private var imagesURL: URL { directory.appendingPathComponent("images", isDirectory: true) }

    override func tearDownWithError() throws {
        if FileManager.default.fileExists(atPath: directory.path) {
            try FileManager.default.removeItem(at: directory)
        }
        try super.tearDownWithError()
    }

    func testTextClipIsImportedWithOriginalFieldsAndRemovedFromInbox() async throws {
        let inbox = try makeInboxStorage()
        let clip = Clip(
            content: .text("공유한 텍스트"),
            name: "공유 제목",
            createdAt: Date(timeIntervalSince1970: 100)
        )
        try await inbox.insert(clip)
        let storage = try makeStorage()
        let events = await storage.changes()
        var iterator = events.makeAsyncIterator()

        let result = try await makeService(storage: storage).importPendingClips()

        XCTAssertEqual(
            result,
            ClipShareImportResult(
                importedCount: 1,
                remainingCount: 0,
                hasPendingCleanup: false
            )
        )
        let stored = try await storage.fetchAll(order: .createdAt)
        XCTAssertEqual(stored, [clip])
        let event = await iterator.next()
        XCTAssertEqual(event, .inserted(clip))
        let remaining = try await inbox.fetchAll(order: .createdAt)
        XCTAssertTrue(remaining.isEmpty)
    }

    func testImageClipIsImportedWithSameBytesAndRemovedFromInbox() async throws {
        let inbox = try makeInboxStorage()
        let inboxImages = try makeInboxImages(storage: inbox)
        let data = try makePNGData()
        let saved = try await inboxImages.saveImage(
            data,
            name: "공유 이미지",
            createdAt: Date(timeIntervalSince1970: 100)
        ).value
        let storage = try makeStorage()
        let images = try makeImages(storage: storage)

        let result = try await makeService(
            storage: storage,
            images: images
        ).importPendingClips()

        XCTAssertEqual(result.importedCount, 1)
        XCTAssertEqual(result.remainingCount, 0)
        let fetched = try await storage.fetch(id: saved.id)
        let imported = try XCTUnwrap(fetched)
        XCTAssertEqual(imported.name, "공유 이미지")
        XCTAssertEqual(imported.createdAt, saved.createdAt)
        guard case .image(let metadata) = imported.content else { return XCTFail("이미지 클립이 아님") }
        let loaded = try await images.loadImage(metadata)
        XCTAssertEqual(loaded, data)
        let remaining = try await inbox.fetchAll(order: .createdAt)
        XCTAssertTrue(remaining.isEmpty)
        XCTAssertEqual(try entryCount(at: inboxImagesURL), 0)
        XCTAssertEqual(try entryCount(at: imagesURL), 1)
    }

    func testMissingInboxDoesNotTouchStorageOrCreateInbox() async throws {
        let storage = try makeStorage()

        let result = try await makeService(storage: storage).importPendingClips()

        XCTAssertEqual(result, .empty)
        let stored = try await storage.fetchAll(order: .createdAt)
        XCTAssertTrue(stored.isEmpty)
        XCTAssertFalse(FileManager.default.fileExists(atPath: inboxDatabaseURL.path))
    }

    func testEmptyInboxImportsNothing() async throws {
        _ = try makeInboxStorage()
        let storage = try makeStorage()

        let result = try await makeService(storage: storage).importPendingClips()

        XCTAssertEqual(result, .empty)
        let stored = try await storage.fetchAll(order: .createdAt)
        XCTAssertTrue(stored.isEmpty)
    }

    func testClipAlreadyInStorageIsNotDuplicatedAndIsRemovedFromInbox() async throws {
        let inbox = try makeInboxStorage()
        let clip = Clip(content: .text("이미 반입된 텍스트"))
        try await inbox.insert(clip)
        let storage = try makeStorage()
        try await storage.insert(clip)

        let result = try await makeService(storage: storage).importPendingClips()

        XCTAssertEqual(result, .empty)
        let stored = try await storage.fetchAll(order: .createdAt)
        XCTAssertEqual(stored, [clip])
        let remaining = try await inbox.fetchAll(order: .createdAt)
        XCTAssertTrue(remaining.isEmpty)
    }

    func testStorageFailureKeepsClipInInboxAndNextImportSucceeds() async throws {
        let inbox = try makeInboxStorage()
        let clip = Clip(content: .text("저장 실패 후 재시도"))
        try await inbox.insert(clip)
        let storage = try makeStorage()
        let shouldFail = OSAllocatedUnfairLock(initialState: true)
        let spy = ClipboardStorageServiceSpy(
            storage: storage,
            beforeInsert: {
                if shouldFail.withLock({ $0 }) { throw ClipStorageError.writeFailed }
            }
        )
        let service = try makeService(storage: spy)

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
        let empty = try await storage.fetchAll(order: .createdAt)
        XCTAssertTrue(empty.isEmpty)

        shouldFail.withLock { $0 = false }
        let second = try await service.importPendingClips()

        XCTAssertEqual(second.importedCount, 1)
        XCTAssertEqual(second.remainingCount, 0)
        let stored = try await storage.fetchAll(order: .createdAt)
        XCTAssertEqual(stored, [clip])
        let remaining = try await inbox.fetchAll(order: .createdAt)
        XCTAssertTrue(remaining.isEmpty)
    }

    func testCorruptedInboxImageStaysWhileOtherClipsAreImported() async throws {
        let inbox = try makeInboxStorage()
        let inboxImages = try makeInboxImages(storage: inbox)
        let image = try await inboxImages.saveImage(
            try makePNGData(),
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
        let storage = try makeStorage()

        let result = try await makeService(storage: storage).importPendingClips()

        XCTAssertEqual(
            result,
            ClipShareImportResult(
                importedCount: 1,
                remainingCount: 1,
                hasPendingCleanup: false
            )
        )
        let stored = try await storage.fetchAll(order: .createdAt)
        XCTAssertEqual(stored, [text])
        let remaining = try await inbox.fetchAll(order: .createdAt)
        XCTAssertEqual(remaining, [image])
    }

    func testClipSavedByExtensionAfterFirstImportIsImportedNextTime() async throws {
        let inbox = try makeInboxStorage()
        let storage = try makeStorage()
        let service = try makeService(storage: storage)
        let first = try await service.importPendingClips()
        XCTAssertEqual(first, .empty)
        let clip = Clip(content: .text("나중에 공유한 텍스트"))
        try await inbox.insert(clip)

        let second = try await service.importPendingClips()

        XCTAssertEqual(second.importedCount, 1)
        let stored = try await storage.fetchAll(order: .createdAt)
        XCTAssertEqual(stored, [clip])
    }

    func testCancelledImportThrowsCancellationAndKeepsInbox() async throws {
        let inbox = try makeInboxStorage()
        let clip = Clip(content: .text("취소 전 텍스트"))
        try await inbox.insert(clip)
        let storage = try makeStorage()
        let service = try makeService(storage: storage)

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
        let stored = try await storage.fetchAll(order: .createdAt)
        XCTAssertTrue(stored.isEmpty)
        let remaining = try await inbox.fetchAll(order: .createdAt)
        XCTAssertEqual(remaining, [clip])
    }

    private func makeInboxStorage() throws -> SQLiteClipStorageService {
        try SQLiteClipStorageService(databaseURL: inboxDatabaseURL)
    }

    private func makeInboxImages(storage: any ClipStorageService) throws -> ClipImageService {
        ClipImageService(storage: storage, files: try ClipImageFileStore(rootURL: inboxImagesURL))
    }

    private func makeStorage() throws -> SQLiteClipStorageService {
        try SQLiteClipStorageService(databaseURL: databaseURL)
    }

    private func makeImages(storage: any ClipStorageService) throws -> ClipImageService {
        ClipImageService(storage: storage, files: try ClipImageFileStore(rootURL: imagesURL))
    }

    private func makeService(storage: any ClipStorageService) throws -> ClipShareImportService {
        try makeService(storage: storage, images: makeImages(storage: storage))
    }

    private func makeService(
        storage: any ClipStorageService,
        images: ClipImageService
    ) -> ClipShareImportService {
        ClipShareImportService(
            inboxDatabaseURL: inboxDatabaseURL,
            inboxImagesURL: inboxImagesURL,
            storage: storage,
            images: images
        )
    }

    /// 이미지 루트 아래의 항목 수입니다. 저장된 이미지 하나당 디렉터리 하나가 있습니다.
    private func entryCount(at url: URL) throws -> Int {
        try FileManager.default.contentsOfDirectory(atPath: url.path).count
    }

    private func makePNGData() throws -> Data {
        let format = UIGraphicsImageRendererFormat()
        format.scale = 1
        let renderer = UIGraphicsImageRenderer(size: CGSize(width: 2, height: 3), format: format)
        return try XCTUnwrap(renderer.pngData { context in
            UIColor.red.setFill()
            context.fill(CGRect(
                x: 0,
                y: 0,
                width: 2,
                height: 3
            ))
        })
    }
}
