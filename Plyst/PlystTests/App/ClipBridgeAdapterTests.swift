//
//  ClipBridgeAdapterTests.swift
//  PlystTests
//
//  Created by opfic on 10/7/26.
//

import Foundation
import PlystBridge
import XCTest
@testable import Plyst

final class ClipBridgeAdapterTests: XCTestCase {
    private let directory = FileManager.default.temporaryDirectory.appendingPathComponent("Plyst-bridge-\(UUID())", isDirectory: true)

    override func tearDownWithError() throws {
        if FileManager.default.fileExists(atPath: directory.path) {
            try FileManager.default.removeItem(at: directory)
        }
        try super.tearDownWithError()
    }

    func testTextClipPreservesFieldsAndUsesUnixMilliseconds() async throws {
        let storage = try makeStorage()
        let adapter = try makeAdapter(storage: storage)
        let clip = Clip(
            content: .text(" https://example.com 원문 "),
            name: "이름",
            isPinned: true,
            memo: "메모",
            createdAt: Date(timeIntervalSince1970: 1234.5),
            lastUsedAt: Date(timeIntervalSince1970: 2345.5)
        )
        try await storage.insert(clip)

        let result = try await adapter.clip(id: clip.id)
        let record = try XCTUnwrap(result)

        XCTAssertEqual(record.id, clip.id.uuidString)
        XCTAssertEqual(record.text, " https://example.com 원문 ")
        XCTAssertNil(record.image)
        XCTAssertEqual(record.name, clip.name)
        XCTAssertEqual(record.memo, clip.memo)
        XCTAssertTrue(record.isPinned)
        XCTAssertEqual(record.createdAt, 1234500)
        XCTAssertEqual(record.lastUsedAt, 2345500)
    }

    func testImageClipReturnsOriginalFileURIAndMetadata() async throws {
        let storage = try makeStorage()
        let adapter = try makeAdapter(storage: storage)
        let result = try await adapter.images.saveImage(ClipImageTestFixture.data())
        guard case .image(let metadata) = result.value.content else {
            return XCTFail("이미지 클립이 아닙니다.")
        }

        let fetched = try await adapter.clip(id: result.value.id)
        let record = try XCTUnwrap(fetched)
        let image = try XCTUnwrap(record.image)
        let url = try await adapter.images.loadImageFileURL(metadata)

        XCTAssertEqual(record.id, result.value.id.uuidString)
        XCTAssertNil(record.text)
        XCTAssertNil(record.name)
        XCTAssertNil(record.memo)
        XCTAssertNil(record.lastUsedAt)
        XCTAssertFalse(record.isPinned)
        XCTAssertEqual(record.createdAt, result.value.createdAt.timeIntervalSince1970 * 1000)
        XCTAssertEqual(image.uri, url.absoluteString)
        XCTAssertTrue(image.uri.hasPrefix("file://"))
        XCTAssertEqual(image.contentType, metadata.contentType)
        XCTAssertEqual(image.pixelWidth, metadata.pixelWidth)
        XCTAssertEqual(image.pixelHeight, metadata.pixelHeight)
    }

    func testMissingClipReturnsNil() async throws {
        let adapter = try makeAdapter(storage: makeStorage())

        let record = try await adapter.clip(id: UUID())

        XCTAssertNil(record)
    }

    func testMissingImageFileRejectsTheClip() async throws {
        let storage = try makeStorage()
        let adapter = try makeAdapter(storage: storage)
        let result = try await adapter.images.saveImage(ClipImageTestFixture.data())
        guard case .image(let metadata) = result.value.content else {
            return XCTFail("이미지 클립이 아닙니다.")
        }
        let url = try await adapter.images.loadImageFileURL(metadata)
        try FileManager.default.removeItem(at: url)

        do {
            _ = try await adapter.clip(id: result.value.id)
            XCTFail("없는 이미지 파일의 조회가 성공했습니다.")
        } catch {
            guard case ClipBridgeError.imageUnavailable = error else {
                return XCTFail("이미지 파일 오류가 변환되지 않았습니다: \(error)")
            }
        }
        let preserved = try await storage.fetch(id: result.value.id)
        XCTAssertEqual(preserved, result.value)
    }

    private func makeStorage() throws -> SQLiteClipStorageService {
        try SQLiteClipStorageService(databaseURL: directory.appendingPathComponent("clips.sqlite"))
    }

    private func makeAdapter(storage: SQLiteClipStorageService) throws -> ClipBridgeAdapter {
        let files = try ClipImageFileStore(rootURL: directory.appendingPathComponent("images", isDirectory: true))
        return ClipBridgeAdapter(storage: storage, images: ClipImageService(storage: storage, files: files))
    }
}
