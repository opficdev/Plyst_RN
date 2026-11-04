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

final class ClipBridgeAdapterTests: ClipTemporaryDirectoryTestCase {
    func testTextClipPreservesFieldsAndUsesUnixMilliseconds() async throws {
        let storage = try makeStorage()
        let adapter = try makeAdapter(storage: storage)
        let clip = Clip(
            content: .text(" https://example.com 원문 "),
            name: "이름",
            pinnedAt: Date(timeIntervalSince1970: 100),
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
        XCTAssertEqual(record.pinnedAt, 100000)
        XCTAssertEqual(record.createdAt, 1234500)
        XCTAssertEqual(record.lastUsedAt, 2345500)
    }

    func testMissingImageFileStillReturnsAndUpdatesTheClip() async throws {
        let storage = try makeStorage()
        let adapter = try makeAdapter(storage: storage)
        let result = try await adapter.images.saveImage(ClipImageTestFixture.data())
        guard case .image(let metadata) = result.value.content else {
            return XCTFail("이미지 클립이 아닙니다.")
        }
        let url = directory.appendingPathComponent("images").appendingPathComponent(metadata.fileID.uuidString).appendingPathComponent("original")
        try FileManager.default.removeItem(at: url)

        let record = try await adapter.clip(id: result.value.id)
        XCTAssertEqual(record?.image?.byteCount, metadata.byteCount)
        let updated = try await adapter.updateClip(
            id: result.value.id,
            name: "새 이름",
            memo: "메모",
            isPinned: true
        )
        XCTAssertEqual(updated?.name, "새 이름")
        XCTAssertEqual(updated?.memo, "메모")
        XCTAssertNotNil(updated?.pinnedAt)
        let preserved = try await storage.fetch(id: result.value.id)
        XCTAssertEqual(preserved?.name, "새 이름")
    }

    func testUpdateReturnsStoredFieldsWithoutNormalization() async throws {
        let storage = try makeStorage()
        let adapter = try makeAdapter(storage: storage)
        let clip = Clip(
            content: .text("원문"),
            name: "기존 이름",
            memo: "기존 메모",
            lastUsedAt: Date(timeIntervalSince1970: 1234)
        )
        try await storage.insert(clip)

        let result = try await adapter.updateClip(
            id: clip.id,
            name: " 이름 ",
            memo: "\n 메모 ",
            isPinned: true
        )
        let record = try XCTUnwrap(result)
        let fetched = try await storage.fetch(id: clip.id)
        let stored = try XCTUnwrap(fetched)

        XCTAssertEqual(stored.name, " 이름 ")
        XCTAssertEqual(stored.memo, "\n 메모 ")
        XCTAssertNotNil(stored.pinnedAt)
        XCTAssertEqual(record.id, stored.id.uuidString)
        XCTAssertEqual(record.name, stored.name)
        XCTAssertEqual(record.memo, stored.memo)
        XCTAssertEqual(record.pinnedAt, stored.pinnedAt.map { $0.timeIntervalSince1970 * 1000 })
        XCTAssertEqual(record.text, "원문")
        XCTAssertEqual(record.createdAt, stored.createdAt.timeIntervalSince1970 * 1000)
        XCTAssertEqual(record.lastUsedAt, 1234000)

        let cleared = try await adapter.updateClip(
            id: clip.id,
            name: nil,
            memo: nil,
            isPinned: false
        )
        XCTAssertNotNil(cleared)
        XCTAssertNil(cleared?.name)
        XCTAssertNil(cleared?.memo)
        XCTAssertNil(cleared?.pinnedAt)
    }

    func testUpdateMissingClipReturnsNil() async throws {
        let adapter = try makeAdapter(storage: makeStorage())
        let record = try await adapter.updateClip(
            id: UUID(),
            name: nil,
            memo: nil,
            isPinned: false
        )
        XCTAssertNil(record)
    }

    func testDeleteRemovesImageFile() async throws {
        let storage = try makeStorage()
        let adapter = try makeAdapter(storage: storage)
        let result = try await adapter.images.saveImage(ClipImageTestFixture.data())
        guard case .image(let metadata) = result.value.content else {
            return XCTFail("이미지 클립이 아닙니다.")
        }
        let url = directory.appendingPathComponent("images").appendingPathComponent(metadata.fileID.uuidString).appendingPathComponent("original")

        try await adapter.deleteClip(id: result.value.id)

        let fetched = try await storage.fetch(id: result.value.id)
        XCTAssertNil(fetched)
        XCTAssertFalse(FileManager.default.fileExists(atPath: url.path))
    }
}
