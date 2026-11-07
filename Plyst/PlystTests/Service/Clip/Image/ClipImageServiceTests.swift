//
//  ClipImageServiceTests.swift
//  PlystTests
//
//  Created by opfic on 9/29/26.
//

import Foundation
import UniformTypeIdentifiers
import XCTest
@testable import Plyst

final class ClipImageServiceTests: ClipTemporaryDirectoryTestCase {
    func testSavedClipAndOriginalAreRestoredByNewInstances() async throws {
        let data = try ClipImageTestFixture.data()
        let storage = try makeStorage()
        let service = try ClipImageService(storage: storage, rootURL: root)
        let result = try await service.saveImage(data, name: "이름", memo: "메모", pinnedAt: Date(timeIntervalSince1970: 100))
        XCTAssertEqual(result.cleanup, .completed)
        let reopenedStorage = try makeStorage()
        let reopened = try ClipImageService(storage: reopenedStorage, rootURL: root)
        let clip = try await reopenedStorage.fetch(id: result.value.id)
        let restored = try await reopened.loadImage(imageMetadata(in: XCTUnwrap(clip)))
        XCTAssertEqual(restored, data)
        XCTAssertEqual(clip, result.value)
        XCTAssertEqual(clip?.name, "이름")
        XCTAssertNotNil(clip?.pinnedAt)
    }

    func testOriginalBytesAndMetadataSurviveReopeningWithoutApplyingOrientation() async throws {
        for type in [UTType.png.identifier, UTType.jpeg.identifier] {
            let data = try ClipImageTestFixture.data(type: type, orientation: 6)
            let service = try ClipImageService(storage: makeStorage(), rootURL: root)
            let image = try imageMetadata(in: await service.saveImage(data).value)
            XCTAssertEqual(image.contentType, type)
            XCTAssertEqual(image.pixelWidth, 2)
            XCTAssertEqual(image.pixelHeight, 3)
            XCTAssertEqual(image.byteCount, data.count)
            let reopened = try ClipImageService(storage: makeStorage(), rootURL: root)
            let loaded = try await reopened.loadImage(image)
            XCTAssertEqual(loaded, data)
            XCTAssertEqual(try originalData(of: image), data)
        }
    }

    func testInvalidAndTruncatedImagesDoNotCreateFiles() async throws {
        let png = try ClipImageTestFixture.data()
        let gif = try ClipImageTestFixture.data(type: UTType.gif.identifier, count: 2)
        let service = try ClipImageService(storage: makeStorage(), rootURL: root)
        for data in [Data(), Data("<svg></svg>".utf8), Data(png.prefix(png.count / 2)), Data(gif.dropLast(8))] {
            do {
                _ = try await service.saveImage(data)
                XCTFail("잘못된 이미지 저장 성공")
            } catch { XCTAssertNotNil(error as? ClipImageFileError) }
            XCTAssertEqual(try entryCount(at: root), 0)
        }
        let image = try imageMetadata(in: await service.saveImage(gif).value)
        XCTAssertEqual(try originalData(of: image), gif)
    }

    func testValidatedLoadPreservesAnimatedOriginalAndMetadata() async throws {
        let service = try ClipImageService(storage: makeStorage(), rootURL: root)
        let data = try ClipImageTestFixture.data(type: UTType.gif.identifier, count: 2)
        let image = try imageMetadata(in: await service.saveImage(data).value)

        let loaded = try await service.loadImage(image)

        XCTAssertEqual(loaded, data)
    }

    func testCancelledTaskReachesCoreAndKeepsClip() async throws {
        let storage = try makeStorage()
        let service = try ClipImageService(storage: storage, rootURL: root)
        let saved = try await service.saveImage(ClipImageTestFixture.data()).value
        let task = Task {
            withUnsafeCurrentTask { $0?.cancel() }
            return try await service.delete(id: saved.id)
        }

        do {
            _ = try await task.value
            XCTFail("취소된 삭제 성공")
        } catch { XCTAssertTrue(error is CancellationError) }

        let preserved = try await storage.fetch(id: saved.id)
        XCTAssertEqual(preserved, saved)
    }

    private func originalData(of image: ClipImageMetadata) throws -> Data {
        try Data(contentsOf: root.appendingPathComponent(image.fileID.uuidString).appendingPathComponent("original"))
    }
}
