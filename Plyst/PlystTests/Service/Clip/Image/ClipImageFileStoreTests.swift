//
//  ClipImageFileStoreTests.swift
//  PlystTests
//
//  Created by opfic on 9/29/26.
//

import Foundation
import UniformTypeIdentifiers
import XCTest
@testable import Plyst

final class ClipImageFileStoreTests: ClipTemporaryDirectoryTestCase {
    override var root: URL { directory }

    func testOriginalBytesAndMetadataSurviveReopeningWithoutApplyingOrientation() throws {
        for type in [UTType.png.identifier, UTType.jpeg.identifier] {
            let data = try ClipImageTestFixture.data(type: type, orientation: 6)
            let files = try ClipImageFileStore(rootURL: root)
            let image = try files.save(data)
            XCTAssertEqual(image.contentType, type)
            XCTAssertEqual(image.pixelWidth, 2)
            XCTAssertEqual(image.pixelHeight, 3)
            XCTAssertEqual(image.byteCount, data.count)
            let reopened = try ClipImageFileStore(rootURL: root)
            XCTAssertEqual(try reopened.load(fileID: image.fileID), data)
            try reopened.finishPending(fileID: image.fileID)
            XCTAssertEqual(try reopened.pendingFileIDs(), [])
        }
    }

    func testInvalidAndTruncatedImagesDoNotCreateFiles() throws {
        let png = try ClipImageTestFixture.data()
        let gif = try ClipImageTestFixture.data(type: UTType.gif.identifier, count: 2)
        let files = try ClipImageFileStore(rootURL: root)
        for data in [Data(), Data("<svg></svg>".utf8), Data(png.prefix(png.count / 2)), Data(gif.dropLast(8))] {
            XCTAssertThrowsError(try files.save(data))
            XCTAssertEqual(try FileManager.default.contentsOfDirectory(atPath: root.path), [])
        }
        let image = try files.save(gif)
        XCTAssertEqual(try files.load(fileID: image.fileID), gif)
    }

    func testValidatedLoadPreservesAnimatedOriginalAndMetadata() throws {
        let files = try ClipImageFileStore(rootURL: root)
        let data = try ClipImageTestFixture.data(type: UTType.gif.identifier, count: 2)
        let image = try files.save(data)

        XCTAssertEqual(try files.load(image: image), data)
        XCTAssertEqual(try files.load(fileID: image.fileID), data)
        XCTAssertEqual(try files.pendingFileIDs(), [image.fileID])
    }
}
