//
//  ClipCoreAdapterImageTests.swift
//  PlystTests
//
//  Created by opfic on 9/29/26.
//

import Foundation
import UniformTypeIdentifiers
import XCTest
@testable import Plyst

final class ClipCoreAdapterImageTests: ClipTemporaryDirectoryTestCase {
    func testSavedClipAndOriginalAreRestoredByNewInstances() async throws {
        let data = try ClipImageTestFixture.data()
        let core = try makeCore()
        let result = try await core.saveImage(data, name: "이름", memo: "메모", pinnedAt: Date(timeIntervalSince1970: 100))
        XCTAssertEqual(result.cleanup, .completed)
        let reopened = try makeCore()
        let clip = try await reopened.fetch(id: result.value.id)
        let restored = try await reopened.loadImage(imageMetadata(in: XCTUnwrap(clip)))
        XCTAssertEqual(restored, data)
        XCTAssertEqual(clip, result.value)
        XCTAssertEqual(clip?.name, "이름")
        XCTAssertNotNil(clip?.pinnedAt)
    }

    func testOriginalBytesAndMetadataSurviveReopeningWithoutApplyingOrientation() async throws {
        for type in [UTType.png.identifier, UTType.jpeg.identifier] {
            let data = try ClipImageTestFixture.data(type: type, orientation: 6)
            let core = try makeCore()
            let image = try imageMetadata(in: await core.saveImage(data).value)
            XCTAssertEqual(image.contentType, type)
            XCTAssertEqual(image.pixelWidth, 2)
            XCTAssertEqual(image.pixelHeight, 3)
            XCTAssertEqual(image.byteCount, data.count)
            let reopened = try makeCore()
            let loaded = try await reopened.loadImage(image)
            XCTAssertEqual(loaded, data)
            XCTAssertEqual(try originalData(of: image), data)
        }
    }

    func testInvalidAndTruncatedImagesDoNotCreateFiles() async throws {
        let png = try ClipImageTestFixture.data()
        let gif = try ClipImageTestFixture.data(type: UTType.gif.identifier, count: 2)
        let core = try makeCore()
        for data in [Data(), Data("<svg></svg>".utf8), Data(png.prefix(png.count / 2)), Data(gif.dropLast(8))] {
            do {
                _ = try await core.saveImage(data)
                XCTFail("잘못된 이미지 저장 성공")
            } catch { XCTAssertNotNil(error as? ClipImageFileError) }
            XCTAssertEqual(try entryCount(at: root), 0)
        }
        let image = try imageMetadata(in: await core.saveImage(gif).value)
        XCTAssertEqual(try originalData(of: image), gif)
    }

    func testValidatedLoadPreservesAnimatedOriginalAndMetadata() async throws {
        let core = try makeCore()
        let data = try ClipImageTestFixture.data(type: UTType.gif.identifier, count: 2)
        let image = try imageMetadata(in: await core.saveImage(data).value)

        let loaded = try await core.loadImage(image)

        XCTAssertEqual(loaded, data)
    }

    func testCancelledTaskReachesCoreAndKeepsClip() async throws {
        let core = try makeCore()
        let saved = try await core.saveImage(ClipImageTestFixture.data()).value
        let task = Task {
            withUnsafeCurrentTask { $0?.cancel() }
            return try await core.delete(id: saved.id)
        }

        do {
            _ = try await task.value
            XCTFail("취소된 삭제 성공")
        } catch { XCTAssertTrue(error is CancellationError) }

        let preserved = try await core.fetch(id: saved.id)
        XCTAssertEqual(preserved, saved)
    }

    private func originalData(of image: ClipImageMetadata) throws -> Data {
        try Data(contentsOf: root.appendingPathComponent(image.fileID.uuidString).appendingPathComponent("original"))
    }
}
