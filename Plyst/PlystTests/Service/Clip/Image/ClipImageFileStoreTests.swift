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
