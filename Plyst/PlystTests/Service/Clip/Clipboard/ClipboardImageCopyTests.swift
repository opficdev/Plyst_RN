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
final class ClipboardImageCopyTests: XCTestCase {
    private let directory = FileManager.default.temporaryDirectory.appendingPathComponent("Plyst-image-copy-\(UUID())", isDirectory: true)
    private var root: URL { directory.appendingPathComponent("images") }
    private var url: URL { directory.appendingPathComponent("clips.sqlite") }

    override func tearDownWithError() throws {
        if FileManager.default.fileExists(atPath: directory.path) { try FileManager.default.removeItem(at: directory) }
        try super.tearDownWithError()
    }

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
            let image = try metadata(in: clip)

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

    func testMissingOriginalDoesNotWriteOrChangeClip() async throws {
        let storage = try SQLiteClipStorageService(databaseURL: url)
        let files = try ClipImageFileStore(rootURL: root)
        let images = ClipImageService(storage: storage, files: files)
        let saved = try await images.saveImage(ClipImageTestFixture.data())
        let clip = saved.value
        let image = try metadata(in: clip)
        let writer = ClipboardWriterSpy()
        let service = ClipboardService(
            storage: storage,
            images: images,
            writer: writer
        )
        try FileManager.default.removeItem(at: root.appendingPathComponent(image.fileID.uuidString).appendingPathComponent("original"))

        do {
            _ = try await service.copy(id: clip.id)
            XCTFail("원본이 없는 이미지 복사 성공")
        } catch { XCTAssertEqual(error as? ClipImageFileError, .notFound(image.fileID)) }

        XCTAssertEqual(writer.contents, [])
        let preserved = try await storage.fetch(id: clip.id)
        XCTAssertEqual(preserved, clip)
    }

    func testCorruptedOriginalDoesNotWriteOrRepairTheFile() async throws {
        let storage = try SQLiteClipStorageService(databaseURL: url)
        let files = try ClipImageFileStore(rootURL: root)
        let images = ClipImageService(storage: storage, files: files)
        let saved = try await images.saveImage(ClipImageTestFixture.data())
        let clip = saved.value
        let image = try metadata(in: clip)
        let corrupted = Data(repeating: 0, count: image.byteCount)
        let original = root.appendingPathComponent(image.fileID.uuidString).appendingPathComponent("original")
        try corrupted.write(to: original)
        let writer = ClipboardWriterSpy()
        let service = ClipboardService(
            storage: storage,
            images: images,
            writer: writer
        )

        do {
            _ = try await service.copy(id: clip.id)
            XCTFail("손상된 원본 복사 성공")
        } catch { XCTAssertEqual(error as? ClipImageFileError, .corruptedImage(image.fileID)) }

        XCTAssertEqual(writer.contents, [])
        XCTAssertEqual(try Data(contentsOf: original), corrupted)
        let preserved = try await storage.fetch(id: clip.id)
        XCTAssertEqual(preserved, clip)
    }

    func testReplacingClipAfterFetchDoesNotMixOldTypeWithNewBytes() async throws {
        let storage = try SQLiteClipStorageService(databaseURL: url)
        let files = try ClipImageFileStore(rootURL: root)
        let images = ClipImageService(storage: storage, files: files)
        let saved = try await images.saveImage(ClipImageTestFixture.data(type: UTType.png.identifier))
        let clip = saved.value
        let image = try metadata(in: clip)
        let replacement = try ClipImageTestFixture.data(type: UTType.jpeg.identifier)
        let spy = ClipboardStorageServiceSpy(storage: storage, afterFetch: {
            _ = try await images.delete(id: clip.id)
            _ = try await images.saveImage(replacement, id: clip.id)
        })
        let writer = ClipboardWriterSpy()
        let service = ClipboardService(
            storage: spy,
            images: images,
            writer: writer
        )

        do {
            _ = try await service.copy(id: clip.id)
            XCTFail("교체된 클립의 메타데이터와 원본을 혼합하여 복사")
        } catch { XCTAssertEqual(error as? ClipImageFileError, .notFound(image.fileID)) }

        XCTAssertEqual(writer.contents, [])
        let stored = try await storage.fetch(id: clip.id)
        let current = try XCTUnwrap(stored)
        let currentImage = try metadata(in: current)
        XCTAssertEqual(currentImage.contentType, UTType.jpeg.identifier)
        XCTAssertNotEqual(currentImage.fileID, image.fileID)
        XCTAssertNil(current.lastUsedAt)
        XCTAssertEqual(try files.load(image: currentImage), replacement)
    }

    private func metadata(in clip: Clip) throws -> ClipImageMetadata {
        guard case .image(let image) = clip.content else { throw ClipImageFileError.notImage(clip.id) }
        return image
    }
}
