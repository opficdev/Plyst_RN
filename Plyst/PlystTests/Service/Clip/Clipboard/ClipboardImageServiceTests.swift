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
        let original = root.appendingPathComponent(image.fileID.uuidString).appendingPathComponent("original")
        XCTAssertEqual(try Data(contentsOf: original), data)
        await assertEvents(stream, expected: [.inserted(clip)])
    }

    private func makeService(
        storage: SQLiteClipStorageService,
        reader: any ClipboardReader
    ) throws -> ClipboardService {
        ClipboardService(images: try ClipImageService(storage: storage, rootURL: root), reader: reader)
    }

    private func savedClip(_ result: ClipboardSaveResult) throws -> Clip {
        guard case .saved(let clip) = result else {
            XCTFail("이미지 저장 성공 결과 누락")
            throw ClipStorageError.invalidContent
        }
        return clip
    }
}
