//
//  ClipboardImageCopyTests.swift
//  PlystTests
//
//  Created by opfic on 9/30/26.
//

import Foundation
import PlystCore
import UniformTypeIdentifiers
import XCTest
@testable import Plyst

@MainActor
final class ClipboardImageCopyTests: ClipTemporaryDirectoryTestCase {
    func testImageCopyPreservesOriginalBytesTypeAndMetadata() async throws {
        let core = try makeCore()
        let writer = ClipboardWriterSpy()
        let service = ClipboardService(core: core, writer: writer)
        for type in [UTType.png.identifier, UTType.jpeg.identifier, UTType.gif.identifier] {
            let data = try ClipImageTestFixture.data(
                type: type,
                count: type == UTType.gif.identifier ? 2 : 1,
                orientation: 6
            )
            let saved = try await core.saveImage(data)
            let clip = saved.value
            let image = try imageMetadata(in: clip)

            let result = try await service.copy(id: clip.id)

            guard case .copied(let copied) = result else { return XCTFail("이미지 복사 성공 결과 누락") }
            XCTAssertEqual(copied.content, clip.content)
            XCTAssertEqual(copied.createdAt, clip.createdAt)
            XCTAssertNotNil(copied.lastUsedAt)
            guard case let .image(path, contentType) = writer.contents.last else { return XCTFail("이미지 쓰기 누락") }
            XCTAssertEqual(contentType, type)
            XCTAssertEqual(try Data(contentsOf: URL(fileURLWithPath: path)), data)
            let loaded = try await core.loadImage(image)
            XCTAssertEqual(loaded, data)
            let stored = try await core.fetch(id: clip.id)
            XCTAssertEqual(stored, copied)
        }
        XCTAssertEqual(writer.contents.count, 3)
    }
}
