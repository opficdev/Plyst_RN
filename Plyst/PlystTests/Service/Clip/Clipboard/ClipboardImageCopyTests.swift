//
//  ClipboardImageCopyTests.swift
//  PlystTests
//
//  Created by opfic on 9/30/26.
//

import Foundation
import UniformTypeIdentifiers
import XCTest
@testable import Plyst

@MainActor
final class ClipboardImageCopyTests: ClipTemporaryDirectoryTestCase {
    func testImageCopyPreservesOriginalBytesTypeAndMetadata() async throws {
        let storage = try SQLiteClipStorageService(databaseURL: url)
        let files = try ClipImageFileStore(rootURL: root)
        let images = ClipImageService(storage: storage, files: files)
        let writer = ClipboardWriterSpy()
        let service = ClipboardService(
            storage: storage,
            images: images,
            writer: writer
        )
        for type in [UTType.png.identifier, UTType.jpeg.identifier, UTType.gif.identifier] {
            let data = try ClipImageTestFixture.data(
                type: type,
                count: type == UTType.gif.identifier ? 2 : 1,
                orientation: 6
            )
            let saved = try await images.saveImage(data)
            let clip = saved.value
            let image = try imageMetadata(in: clip)

            let result = try await service.copy(id: clip.id)

            guard case .copied(let copied) = result else { return XCTFail("이미지 복사 성공 결과 누락") }
            XCTAssertEqual(copied.content, clip.content)
            XCTAssertEqual(copied.createdAt, clip.createdAt)
            XCTAssertNotNil(copied.lastUsedAt)
            XCTAssertEqual(writer.contents.last, .image(data: data, contentType: type))
            XCTAssertEqual(try files.load(fileID: image.fileID), data)
            XCTAssertEqual(try files.load(image: image), data)
            XCTAssertEqual(try files.pendingFileIDs(), [])
            let stored = try await storage.fetch(id: clip.id)
            XCTAssertEqual(stored, copied)
        }
        XCTAssertEqual(writer.contents.count, 3)
    }
}
