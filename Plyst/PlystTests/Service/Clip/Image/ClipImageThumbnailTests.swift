//
//  ClipImageThumbnailTests.swift
//  PlystTests
//
//  Created by opfic on 10/10/26.
//

import Foundation
import ImageIO
import XCTest
@testable import Plyst

final class ClipImageThumbnailTests: XCTestCase {
    private let directory = FileManager.default.temporaryDirectory.appendingPathComponent("Plyst-thumbnail-\(UUID())")
    private var root: URL { directory.appendingPathComponent("images") }

    override func tearDownWithError() throws {
        if FileManager.default.fileExists(atPath: directory.path) {
            try FileManager.default.removeItem(at: directory)
        }
        try super.tearDownWithError()
    }

    func testFileStoreWritesSeparateSizesAndAtomicallyRewritesWithoutChangingOriginal() throws {
        let files = try ClipImageFileStore(rootURL: root)
        let data = try ClipImageTestFixture.data()
        let image = try files.save(data)
        let small = try files.writeThumbnail(image: image, maximumPixelDimension: 1)
        let large = try files.writeThumbnail(image: image, maximumPixelDimension: 2)
        XCTAssertNotEqual(small, large)
        XCTAssertEqual(small.lastPathComponent, "thumbnail-1")
        XCTAssertEqual(large.lastPathComponent, "thumbnail-2")
        XCTAssertEqual(small.deletingLastPathComponent(), root.appendingPathComponent(image.fileID.uuidString))
        try assertDimension(small, equals: 1)
        try assertDimension(large, equals: 2)
        let expected = try Data(contentsOf: small)
        let preserved = directory.appendingPathComponent("previous-thumbnail")
        try FileManager.default.linkItem(at: small, to: preserved)
        let damaged = Data("손상된 썸네일".utf8)
        try damaged.write(to: small)

        let rewritten = try files.writeThumbnail(image: image, maximumPixelDimension: 1)

        XCTAssertEqual(rewritten, small)
        XCTAssertEqual(try Data(contentsOf: rewritten), expected)
        XCTAssertEqual(try Data(contentsOf: preserved), damaged)
        try FileManager.default.removeItem(at: preserved)
        try FileManager.default.linkItem(at: small, to: preserved)
        let replaced = try files.writeThumbnail(image: image, maximumPixelDimension: 1)
        XCTAssertEqual(replaced, small)
        let previous = try FileManager.default.attributesOfItem(atPath: preserved.path)
        let current = try FileManager.default.attributesOfItem(atPath: replaced.path)
        XCTAssertNotEqual(previous[.systemFileNumber] as? NSNumber, current[.systemFileNumber] as? NSNumber)
        XCTAssertEqual(try files.load(image: image), data)
        try assertDimension(large, equals: 2)
        try files.delete(fileID: image.fileID)
        XCTAssertFalse(FileManager.default.fileExists(atPath: small.path))
        XCTAssertFalse(FileManager.default.fileExists(atPath: large.path))
        XCTAssertFalse(FileManager.default.fileExists(atPath: small.deletingLastPathComponent().path))
        XCTAssertThrowsError(try files.writeThumbnail(image: image, maximumPixelDimension: 1)) {
            XCTAssertEqual($0 as? ClipImageFileError, .notFound(image.fileID))
        }
    }

    func testFileStoreRejectsNonPositiveSizes() throws {
        let files = try ClipImageFileStore(rootURL: root)
        let image = try files.save(ClipImageTestFixture.data())
        for dimension in [0, -1] {
            XCTAssertThrowsError(try files.writeThumbnail(image: image, maximumPixelDimension: dimension)) {
                XCTAssertEqual($0 as? ClipImageFileError, .readFailed)
            }
            let url = root.appendingPathComponent(image.fileID.uuidString).appendingPathComponent("thumbnail-\(dimension)")
            XCTAssertFalse(FileManager.default.fileExists(atPath: url.path))
        }
    }

    func testServiceWritesSeparateSizesRecreatesAndDeletesFiles() async throws {
        let files = try ClipImageFileStore(rootURL: root)
        let storage = try SQLiteClipStorageService(databaseURL: directory.appendingPathComponent("clips.sqlite"))
        let service = ClipImageService(storage: storage, files: files)
        let data = try ClipImageTestFixture.data()
        let clip = try await service.saveImage(data).value
        guard case .image(let image) = clip.content else { return XCTFail("이미지가 아닙니다.") }
        let small = try await service.makeThumbnailFileURL(image, maximumPixelDimension: 1)
        let large = try await service.makeThumbnailFileURL(image, maximumPixelDimension: 2)
        XCTAssertNotEqual(small, large)
        XCTAssertEqual(small.lastPathComponent, "thumbnail-1")
        XCTAssertEqual(large.lastPathComponent, "thumbnail-2")
        try assertDimension(small, equals: 1)
        try assertDimension(large, equals: 2)
        let expected = try Data(contentsOf: small)
        let preserved = directory.appendingPathComponent("previous-service-thumbnail")
        try FileManager.default.linkItem(at: small, to: preserved)
        let damaged = Data("손상된 썸네일".utf8)
        try damaged.write(to: small)

        let rewritten = try await service.makeThumbnailFileURL(image, maximumPixelDimension: 1)

        XCTAssertEqual(rewritten, small)
        XCTAssertEqual(try Data(contentsOf: rewritten), expected)
        XCTAssertEqual(try Data(contentsOf: preserved), damaged)
        try FileManager.default.removeItem(at: preserved)
        try FileManager.default.linkItem(at: small, to: preserved)
        let replaced = try await service.makeThumbnailFileURL(image, maximumPixelDimension: 1)
        XCTAssertEqual(replaced, small)
        let previous = try FileManager.default.attributesOfItem(atPath: preserved.path)
        let current = try FileManager.default.attributesOfItem(atPath: replaced.path)
        XCTAssertNotEqual(previous[.systemFileNumber] as? NSNumber, current[.systemFileNumber] as? NSNumber)
        XCTAssertEqual(try files.load(image: image), data)
        for dimension in [0, -1] {
            do {
                _ = try await service.makeThumbnailFileURL(image, maximumPixelDimension: dimension)
                XCTFail("잘못된 크기의 썸네일이 생성됐습니다.")
            } catch {
                XCTAssertEqual(error as? ClipImageFileError, .readFailed)
            }
        }
        _ = try await service.delete(id: clip.id)
        let deleted = try await storage.fetch(id: clip.id)
        XCTAssertNil(deleted)
        XCTAssertFalse(FileManager.default.fileExists(atPath: small.path))
        XCTAssertFalse(FileManager.default.fileExists(atPath: large.path))
        do {
            _ = try await service.makeThumbnailFileURL(image, maximumPixelDimension: 1)
            XCTFail("삭제한 원본의 썸네일이 생성됐습니다.")
        } catch {
            XCTAssertEqual(error as? ClipImageFileError, .notFound(image.fileID))
        }
    }

    func testCancelledFileStoreWriteDoesNotCreateFile() async throws {
        let files = try ClipImageFileStore(rootURL: root)
        let image = try files.save(ClipImageTestFixture.data())
        let task = Task {
            withUnsafeCurrentTask { $0?.cancel() }
            return try files.writeThumbnail(image: image, maximumPixelDimension: 2)
        }
        do {
            _ = try await task.value
            XCTFail("취소된 썸네일이 생성됐습니다.")
        } catch {
            XCTAssertTrue(error is CancellationError)
        }
        let url = root.appendingPathComponent(image.fileID.uuidString).appendingPathComponent("thumbnail-2")
        XCTAssertFalse(FileManager.default.fileExists(atPath: url.path))
    }

    func testCancelledServiceWriteDoesNotCreateFileOrBlockNextWrite() async throws {
        let files = try ClipImageFileStore(rootURL: root)
        let storage = try SQLiteClipStorageService(databaseURL: directory.appendingPathComponent("clips.sqlite"))
        let service = ClipImageService(storage: storage, files: files)
        let image = try files.save(ClipImageTestFixture.data())
        let task = Task {
            withUnsafeCurrentTask { $0?.cancel() }
            return try await service.makeThumbnailFileURL(image, maximumPixelDimension: 2)
        }
        do {
            _ = try await task.value
            XCTFail("취소된 썸네일이 생성됐습니다.")
        } catch {
            XCTAssertTrue(error is CancellationError)
        }
        let url = root.appendingPathComponent(image.fileID.uuidString).appendingPathComponent("thumbnail-2")
        XCTAssertFalse(FileManager.default.fileExists(atPath: url.path))
        let written = try await service.makeThumbnailFileURL(image, maximumPixelDimension: 2)
        XCTAssertEqual(written, url)
        try assertDimension(written, equals: 2)
    }

    private func assertDimension(
        _ url: URL,
        equals dimension: Int
    ) throws {
        let source = try XCTUnwrap(CGImageSourceCreateWithURL(url as CFURL, nil))
        let image = try XCTUnwrap(CGImageSourceCreateImageAtIndex(source, 0, nil))
        XCTAssertEqual(max(image.width, image.height), dimension)
    }
}
