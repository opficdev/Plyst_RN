//
//  ClipboardImageServiceTests.swift
//  PlystTests
//
//  Created by opfic on 9/29/26.
//

import Foundation
import UniformTypeIdentifiers
import XCTest
@testable import Plyst

@MainActor
final class ClipboardImageServiceTests: ClipTemporaryDirectoryTestCase {
    func testSavedImagePreservesBytesMetadataAndDefaultsAsLatestRecord() async throws {
        let storage = try SQLiteClipStorageService(databaseURL: url)
        let previous = Clip(content: .text("이전 기록"), createdAt: Date(timeIntervalSinceReferenceDate: 100))
        try await storage.insert(previous)
        let stream = await storage.changes()
        let data = try ClipImageTestFixture.data(type: UTType.jpeg.identifier, orientation: 6)
        let reader = ClipboardReaderSpy(result: .image(data))
        let service = try makeService(storage: storage, reader: reader)

        let clip = try savedClip(await service.saveCurrentClipboard())

        let image = try imageMetadata(in: clip)
        XCTAssertEqual(image.contentType, UTType.jpeg.identifier)
        XCTAssertEqual(image.pixelWidth, 2)
        XCTAssertEqual(image.pixelHeight, 3)
        XCTAssertEqual(image.byteCount, data.count)
        XCTAssertNil(clip.name)
        XCTAssertNil(clip.memo)
        XCTAssertNil(clip.pinnedAt)
        XCTAssertNil(clip.lastUsedAt)
        XCTAssertEqual(reader.readCount, 1)
        let stored = try await storage.fetchAll(order: .createdAt)
        XCTAssertEqual(stored, [clip, previous])
        let reopened = try SQLiteClipStorageService(databaseURL: url)
        let restored = try await reopened.fetch(id: clip.id)
        XCTAssertEqual(restored, clip)
        let files = try ClipImageFileStore(rootURL: root)
        XCTAssertEqual(try files.load(fileID: image.fileID), data)
        XCTAssertEqual(try files.pendingFileIDs(), [])
        await assertEvents(stream, expected: [.inserted(clip)])
    }

    func testCommittedSaveReportsPendingCleanupAndRecoveryPreservesOriginal() async throws {
        let storage = try SQLiteClipStorageService(databaseURL: url)
        let stream = await storage.changes()
        let root = self.root
        let spy = ClipStorageServiceSpy(storage: storage, beforeInsert: { _ in
            let entries = try FileManager.default.contentsOfDirectory(at: root, includingPropertiesForKeys: nil)
            try ClipImageFileSystemTestFixture.makeReadOnly(XCTUnwrap(entries.first))
        })
        let files = try ClipImageFileStore(rootURL: root)
        let images = ClipImageService(storage: spy, files: files)
        let data = try ClipImageTestFixture.data()
        let reader = ClipboardReaderSpy(result: .image(data))
        let service = ClipboardService(
            storage: spy,
            images: images,
            reader: reader
        )

        let result = try await service.saveCurrentClipboard()

        guard case .savedWithPendingCleanup(let clip, let fileID) = result else {
            XCTFail("확정된 저장의 정리 대기 결과 누락")
            return
        }
        XCTAssertEqual(try imageMetadata(in: clip).fileID, fileID)
        let stored = try await storage.fetchAll(order: .createdAt)
        XCTAssertEqual(stored, [clip])
        XCTAssertEqual(try files.load(fileID: fileID), data)
        XCTAssertEqual(try files.pendingFileIDs(), [fileID])
        try ClipImageFileSystemTestFixture.restorePermissions(at: root)
        let pending = try await images.recoverPendingCleanup()
        XCTAssertEqual(pending, [])
        XCTAssertEqual(try files.pendingFileIDs(), [])
        XCTAssertEqual(try files.load(fileID: fileID), data)
        let recovered = try await storage.fetchAll(order: .createdAt)
        XCTAssertEqual(recovered, [clip])
        await assertEvents(stream, expected: [.inserted(clip)])
    }

    private func makeService(
        storage: any ClipStorageService,
        reader: any ClipboardReader
    ) throws -> ClipboardService {
        let files = try ClipImageFileStore(rootURL: root)
        let images = ClipImageService(storage: storage, files: files)
        return ClipboardService(
            storage: storage,
            images: images,
            reader: reader
        )
    }

    private func savedClip(_ result: ClipboardSaveResult) throws -> Clip {
        guard case .saved(let clip) = result else {
            XCTFail("이미지 저장 성공 결과 누락")
            throw ClipStorageError.invalidContent
        }
        return clip
    }
}
