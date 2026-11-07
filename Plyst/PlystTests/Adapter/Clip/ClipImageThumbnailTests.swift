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

final class ClipImageThumbnailTests: ClipTemporaryDirectoryTestCase {
    func testAdapterWritesSeparateSizesWithoutChangingOriginal() async throws {
        let core = try makeCore()
        let data = try ClipImageTestFixture.data()
        let clip = try await core.saveImage(data).value
        let image = try imageMetadata(in: clip)
        let small = try await core.makeThumbnailFileURL(image, maximumPixelDimension: 1)
        let large = try await core.makeThumbnailFileURL(image, maximumPixelDimension: 2)
        XCTAssertNotEqual(small, large)
        XCTAssertEqual(small.lastPathComponent, "thumbnail-1")
        XCTAssertEqual(large.lastPathComponent, "thumbnail-2")
        XCTAssertEqual(small.deletingLastPathComponent().lastPathComponent, image.fileID.uuidString)
        try assertDimension(small, equals: 1)
        try assertDimension(large, equals: 2)
        let loaded = try await core.loadImage(image)
        XCTAssertEqual(loaded, data)
        _ = try await core.delete(id: clip.id)
        XCTAssertFalse(FileManager.default.fileExists(atPath: small.path))
        XCTAssertFalse(FileManager.default.fileExists(atPath: large.path))
        XCTAssertFalse(FileManager.default.fileExists(atPath: small.deletingLastPathComponent().path))
        do {
            _ = try await core.makeThumbnailFileURL(image, maximumPixelDimension: 1)
            XCTFail("삭제한 이미지의 썸네일 생성 성공")
        } catch { XCTAssertEqual(error as? ClipImageFileError, .notFound(image.fileID)) }
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
