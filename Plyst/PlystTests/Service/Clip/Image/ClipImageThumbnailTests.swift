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

    private func assertDimension(
        _ url: URL,
        equals dimension: Int
    ) throws {
        let source = try XCTUnwrap(CGImageSourceCreateWithURL(url as CFURL, nil))
        let image = try XCTUnwrap(CGImageSourceCreateImageAtIndex(source, 0, nil))
        XCTAssertEqual(max(image.width, image.height), dimension)
    }
}
