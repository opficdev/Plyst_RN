//
//  ClipImageFileStoreTests.swift
//  PlystTests
//
//  Created by opfic on 9/29/26.
//

import CoreGraphics
import Foundation
import ImageIO
import UniformTypeIdentifiers
import XCTest
@testable import Plyst

final class ClipImageFileStoreTests: XCTestCase {
    private let root = FileManager.default.temporaryDirectory.appendingPathComponent("Plyst-images-\(UUID())", isDirectory: true)

    override func tearDownWithError() throws {
        try ClipImageFileSystemTestFixture.restorePermissions(at: root)
        if FileManager.default.fileExists(atPath: root.path) { try FileManager.default.removeItem(at: root) }
        try super.tearDownWithError()
    }

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

    func testThumbnailUsesFirstFrameAndPreservesOriginalBytes() throws {
        let data = try ClipImageTestFixture.data(type: UTType.gif.identifier, count: 2)
        let files = try ClipImageFileStore(rootURL: root)
        let image = try files.save(data)

        let thumbnail = try files.loadThumbnail(image: image, maximumPixelDimension: 1)
        let source = try XCTUnwrap(CGImageSourceCreateWithData(thumbnail as CFData, nil))
        let preview = try XCTUnwrap(CGImageSourceCreateImageAtIndex(source, 0, nil))

        XCTAssertEqual(CGImageSourceGetType(source) as String?, UTType.png.identifier)
        XCTAssertLessThanOrEqual(preview.width, 1)
        XCTAssertLessThanOrEqual(preview.height, 1)
        XCTAssertEqual(try files.load(fileID: image.fileID), data)
    }

    func testThumbnailRejectsMismatchedMetadata() throws {
        let files = try ClipImageFileStore(rootURL: root)
        let image = try files.save(ClipImageTestFixture.data())
        let mismatch = ClipImageMetadata(
            fileID: image.fileID,
            contentType: image.contentType,
            pixelWidth: image.pixelWidth + 1,
            pixelHeight: image.pixelHeight,
            byteCount: image.byteCount
        )

        XCTAssertThrowsError(try files.loadThumbnail(image: mismatch, maximumPixelDimension: 2)) {
            XCTAssertEqual($0 as? ClipImageFileError, .corruptedImage(image.fileID))
        }
    }

    func testFileURLReturnsValidatedOriginalWithoutChangingIt() throws {
        let data = try ClipImageTestFixture.data()
        let files = try ClipImageFileStore(rootURL: root)
        let image = try files.save(data)

        let url = try files.fileURL(image: image)

        XCTAssertTrue(url.isFileURL)
        XCTAssertEqual(url.lastPathComponent, "original")
        XCTAssertEqual(try Data(contentsOf: url), data)
    }

    func testFileURLRejectsMissingAndMismatchedOriginals() throws {
        let files = try ClipImageFileStore(rootURL: root)
        let image = try files.save(ClipImageTestFixture.data())
        let mismatch = ClipImageMetadata(
            fileID: image.fileID,
            contentType: image.contentType,
            pixelWidth: image.pixelWidth,
            pixelHeight: image.pixelHeight,
            byteCount: image.byteCount + 1
        )

        XCTAssertThrowsError(try files.fileURL(image: mismatch)) {
            XCTAssertEqual($0 as? ClipImageFileError, .corruptedImage(image.fileID))
        }
        try FileManager.default.removeItem(at: try files.fileURL(image: image))
        XCTAssertThrowsError(try files.fileURL(image: image)) {
            XCTAssertEqual($0 as? ClipImageFileError, .notFound(image.fileID))
        }
    }

    func testIdentifiersAreUniqueAndInjectedRootsAreIsolated() throws {
        let data = try ClipImageTestFixture.data()
        let files = try ClipImageFileStore(rootURL: root)
        let first = try files.save(data)
        let second = try files.save(data)
        XCTAssertNotEqual(first.fileID, second.fileID)
        let other = try ClipImageFileStore(rootURL: root.appendingPathComponent("other"))
        XCTAssertThrowsError(try other.load(fileID: first.fileID)) {
            XCTAssertEqual($0 as? ClipImageFileError, .notFound(first.fileID))
        }
        XCTAssertEqual(try files.load(fileID: first.fileID), data)
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

    func testNonFileRootIsRejected() throws {
        let url = try XCTUnwrap(URL(string: "https://example.com/images"))
        XCTAssertThrowsError(try ClipImageFileStore(rootURL: url)) {
            XCTAssertEqual($0 as? ClipImageFileError, .invalidRoot)
        }
    }

    func testSymlinksCannotRedirectReadsOrDirectoryDeletion() throws {
        let data = try ClipImageTestFixture.data()
        let files = try ClipImageFileStore(rootURL: root)
        let image = try files.save(data)
        let directory = root.appendingPathComponent(image.fileID.uuidString)
        let original = directory.appendingPathComponent("original")
        let outside = root.appendingPathComponent("outside", isDirectory: true)
        try FileManager.default.createDirectory(at: outside, withIntermediateDirectories: false)
        let target = outside.appendingPathComponent("original")
        try data.write(to: target)
        try FileManager.default.removeItem(at: original)
        try FileManager.default.createSymbolicLink(at: original, withDestinationURL: target)
        XCTAssertThrowsError(try files.load(fileID: image.fileID)) {
            XCTAssertEqual($0 as? ClipImageFileError, .unsafePath)
        }
        try FileManager.default.removeItem(at: directory)
        try FileManager.default.createSymbolicLink(at: directory, withDestinationURL: outside)
        XCTAssertThrowsError(try files.load(fileID: image.fileID)) { XCTAssertEqual($0 as? ClipImageFileError, .unsafePath) }
        XCTAssertThrowsError(try files.delete(fileID: image.fileID)) { XCTAssertEqual($0 as? ClipImageFileError, .unsafePath) }
        XCTAssertEqual(try Data(contentsOf: target), data)
    }

    func testUnwritableRootDoesNotLeaveAnOriginal() throws {
        let files = try ClipImageFileStore(rootURL: root)
        try ClipImageFileSystemTestFixture.makeReadOnly(root)
        XCTAssertThrowsError(try files.save(ClipImageTestFixture.data())) {
            XCTAssertEqual($0 as? ClipImageFileError, .writeFailed)
        }
        XCTAssertEqual(try FileManager.default.contentsOfDirectory(atPath: root.path), [])
    }

    func testFailedCleanupKeepsPersistentCandidate() throws {
        let files = try ClipImageFileStore(rootURL: root)
        let image = try files.save(ClipImageTestFixture.data())
        try ClipImageFileSystemTestFixture.makeReadOnly(root.appendingPathComponent(image.fileID.uuidString))
        XCTAssertThrowsError(try files.delete(fileID: image.fileID)) {
            XCTAssertEqual($0 as? ClipImageFileError, .deleteFailed)
        }
        let reopened = try ClipImageFileStore(rootURL: root)
        let candidates = try reopened.pendingFileIDs()
        XCTAssertEqual(candidates, [image.fileID])
        try ClipImageFileSystemTestFixture.restorePermissions(at: root)
        try reopened.delete(fileID: XCTUnwrap(candidates.first))
        XCTAssertEqual(try FileManager.default.contentsOfDirectory(atPath: root.path), [])
    }

    func testInterruptedMarkerCreationRemainsRecoverable() throws {
        let files = try ClipImageFileStore(rootURL: root)
        let fileID = UUID()
        let directory = root.appendingPathComponent(fileID.uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: false)
        try Data("partial".utf8).write(to: directory.appendingPathComponent("temporary"))
        XCTAssertEqual(try files.pendingFileIDs(), [fileID])
        try files.delete(fileID: fileID)
        XCTAssertEqual(try FileManager.default.contentsOfDirectory(atPath: root.path), [])
    }

    func testPartialDeletionPreservesMarkerUntilTemporaryFilesAreRemoved() throws {
        let files = try ClipImageFileStore(rootURL: root)
        let image = try files.save(ClipImageTestFixture.data())
        let directory = root.appendingPathComponent(image.fileID.uuidString)
        let temporary = directory.appendingPathComponent("temporary", isDirectory: true)
        try FileManager.default.createDirectory(at: temporary, withIntermediateDirectories: false)
        try Data("partial".utf8).write(to: temporary.appendingPathComponent("part"))
        try ClipImageFileSystemTestFixture.makeReadOnly(temporary)
        XCTAssertThrowsError(try files.delete(fileID: image.fileID)) {
            XCTAssertEqual($0 as? ClipImageFileError, .deleteFailed)
        }
        XCTAssertFalse(FileManager.default.fileExists(atPath: directory.appendingPathComponent("original").path))
        XCTAssertTrue(FileManager.default.fileExists(atPath: directory.appendingPathComponent("pending").path))
        let reopened = try ClipImageFileStore(rootURL: root)
        XCTAssertEqual(try reopened.pendingFileIDs(), [image.fileID])
        try ClipImageFileSystemTestFixture.restorePermissions(at: root)
        try reopened.delete(fileID: image.fileID)
        XCTAssertEqual(try FileManager.default.contentsOfDirectory(atPath: root.path), [])
    }

    func testDeletionIsIdempotentAndRemovesOriginalAndMarker() throws {
        let files = try ClipImageFileStore(rootURL: root)
        let image = try files.save(ClipImageTestFixture.data())
        try files.delete(fileID: image.fileID)
        try files.delete(fileID: image.fileID)
        XCTAssertEqual(try files.pendingFileIDs(), [])
        XCTAssertThrowsError(try files.load(fileID: image.fileID)) {
            XCTAssertEqual($0 as? ClipImageFileError, .notFound(image.fileID))
        }
    }

    func testValidatedLoadPreservesAnimatedOriginalAndMetadata() throws {
        let files = try ClipImageFileStore(rootURL: root)
        let data = try ClipImageTestFixture.data(type: UTType.gif.identifier, count: 2)
        let image = try files.save(data)

        XCTAssertEqual(try files.load(image: image), data)
        XCTAssertEqual(try files.load(fileID: image.fileID), data)
        XCTAssertEqual(try files.pendingFileIDs(), [image.fileID])
    }

    func testValidatedLoadRejectsMismatchedMetadataWithoutChangingOriginal() throws {
        let files = try ClipImageFileStore(rootURL: root)
        let data = try ClipImageTestFixture.data()
        let image = try files.save(data)
        let mismatches = [
            ClipImageMetadata(
                fileID: image.fileID,
                contentType: UTType.jpeg.identifier,
                pixelWidth: image.pixelWidth,
                pixelHeight: image.pixelHeight,
                byteCount: image.byteCount
            ),
            ClipImageMetadata(
                fileID: image.fileID,
                contentType: image.contentType,
                pixelWidth: image.pixelWidth + 1,
                pixelHeight: image.pixelHeight,
                byteCount: image.byteCount
            ),
            ClipImageMetadata(
                fileID: image.fileID,
                contentType: image.contentType,
                pixelWidth: image.pixelWidth,
                pixelHeight: image.pixelHeight + 1,
                byteCount: image.byteCount
            ),
            ClipImageMetadata(
                fileID: image.fileID,
                contentType: image.contentType,
                pixelWidth: image.pixelWidth,
                pixelHeight: image.pixelHeight,
                byteCount: image.byteCount + 1
            )
        ]

        for metadata in mismatches {
            XCTAssertThrowsError(try files.load(image: metadata)) {
                XCTAssertEqual($0 as? ClipImageFileError, .corruptedImage(image.fileID))
            }
        }
        XCTAssertEqual(try files.load(fileID: image.fileID), data)
    }

    func testValidatedLoadDistinguishesMissingAndCorruptedOriginals() throws {
        let files = try ClipImageFileStore(rootURL: root)
        let data = try ClipImageTestFixture.data()
        let image = try files.save(data)
        let original = root.appendingPathComponent(image.fileID.uuidString).appendingPathComponent("original")
        let corrupted = Data(repeating: 0, count: image.byteCount)
        try corrupted.write(to: original)

        XCTAssertThrowsError(try files.load(image: image)) {
            XCTAssertEqual($0 as? ClipImageFileError, .corruptedImage(image.fileID))
        }
        XCTAssertEqual(try files.load(fileID: image.fileID), corrupted)
        try FileManager.default.removeItem(at: original)
        XCTAssertThrowsError(try files.load(image: image)) {
            XCTAssertEqual($0 as? ClipImageFileError, .notFound(image.fileID))
        }
    }
}

enum ClipImageTestFixture {
    static func data(
        type: String = UTType.png.identifier,
        count: Int = 1,
        orientation: Int = 1
    ) throws -> Data {
        let pixels = Data(repeating: 255, count: 24)
        let provider = try XCTUnwrap(CGDataProvider(data: pixels as CFData))
        let image = try XCTUnwrap(CGImage(
            width: 2,
            height: 3,
            bitsPerComponent: 8,
            bitsPerPixel: 32,
            bytesPerRow: 8,
            space: CGColorSpaceCreateDeviceRGB(),
            bitmapInfo: CGBitmapInfo(rawValue: CGImageAlphaInfo.premultipliedLast.rawValue),
            provider: provider,
            decode: nil,
            shouldInterpolate: false,
            intent: .defaultIntent
        ))
        let data = NSMutableData()
        let destination = try XCTUnwrap(CGImageDestinationCreateWithData(data as CFMutableData, type as CFString, count, nil))
        for _ in 0..<count {
            CGImageDestinationAddImage(destination, image, [kCGImagePropertyOrientation: orientation] as CFDictionary)
        }
        XCTAssertTrue(CGImageDestinationFinalize(destination))
        return data as Data
    }
}

enum ClipImageFileSystemTestFixture {
    static func makeReadOnly(_ directory: URL) throws {
        try FileManager.default.setAttributes([.posixPermissions: 0o500], ofItemAtPath: directory.path)
        if FileManager.default.isWritableFile(atPath: directory.path) {
            throw XCTSkip("디렉터리 쓰기 권한 제한을 적용할 수 없는 실행 환경")
        }
    }

    static func restorePermissions(at root: URL) throws {
        guard FileManager.default.fileExists(atPath: root.path) else { return }
        try FileManager.default.setAttributes([.posixPermissions: 0o700], ofItemAtPath: root.path)
        let entries = FileManager.default.enumerator(at: root, includingPropertiesForKeys: [.isDirectoryKey, .isSymbolicLinkKey])
        while let entry = entries?.nextObject() as? URL {
            let properties = try entry.resourceValues(forKeys: [.isDirectoryKey, .isSymbolicLinkKey])
            if properties.isDirectory == true, properties.isSymbolicLink != true {
                try FileManager.default.setAttributes([.posixPermissions: 0o700], ofItemAtPath: entry.path)
            }
        }
    }
}
