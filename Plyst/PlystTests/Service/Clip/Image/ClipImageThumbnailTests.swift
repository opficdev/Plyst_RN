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
    func testFileStoreWritesSeparateSizesWithoutChangingOriginal() throws {
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
        XCTAssertEqual(try files.load(image: image), data)
        try files.delete(fileID: image.fileID)
        XCTAssertFalse(FileManager.default.fileExists(atPath: small.path))
        XCTAssertFalse(FileManager.default.fileExists(atPath: large.path))
        XCTAssertFalse(FileManager.default.fileExists(atPath: small.deletingLastPathComponent().path))
        XCTAssertThrowsError(try files.writeThumbnail(image: image, maximumPixelDimension: 1)) {
            XCTAssertEqual($0 as? ClipImageFileError, .notFound(image.fileID))
        }
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
