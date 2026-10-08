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
        XCTAssertTrue(stored.isPinned)
        XCTAssertEqual(record.id, stored.id.uuidString)
        XCTAssertEqual(record.name, stored.name)
        XCTAssertEqual(record.memo, stored.memo)
        XCTAssertEqual(record.isPinned, stored.isPinned)
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
        XCTAssertEqual(cleared?.isPinned, false)
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

    func testDeleteRemovesTextClip() async throws {
        let storage = try makeStorage()
        let adapter = try makeAdapter(storage: storage)
        let clip = Clip(content: .text("원문"))
        try await storage.insert(clip)

        try await adapter.deleteClip(id: clip.id)

        let fetched = try await storage.fetch(id: clip.id)
        XCTAssertNil(fetched)
    }

    func testDeleteRemovesImageFile() async throws {
        let storage = try makeStorage()
        let adapter = try makeAdapter(storage: storage)
        let result = try await adapter.images.saveImage(ClipImageTestFixture.data())
        guard case .image(let metadata) = result.value.content else {
            return XCTFail("이미지 클립이 아닙니다.")
        }
        let url = try await adapter.images.loadImageFileURL(metadata)

        try await adapter.deleteClip(id: result.value.id)

        let fetched = try await storage.fetch(id: result.value.id)
        XCTAssertNil(fetched)
        XCTAssertFalse(FileManager.default.fileExists(atPath: url.path))
    }

    func testDeleteMissingClipSucceeds() async throws {
        let adapter = try makeAdapter(storage: makeStorage())
        try await adapter.deleteClip(id: UUID())
    }

    func testUpdateWriteFailure() async throws {
        let storage = try makeStorage()
        let clip = Clip(content: .text("원문"))
        try await storage.insert(clip)
        let spy = ClipBridgeStorageServiceSpy(storage: storage, failure: ClipStorageError.writeFailed)
        let adapter = try makeAdapter(storage: spy)

        do {
            _ = try await adapter.updateClip(
                id: clip.id,
                name: nil,
                memo: nil,
                isPinned: false
            )
            XCTFail("실패해야 하는 요청이 성공했습니다.")
        } catch {
            guard case ClipBridgeError.writeFailed = error else {
                return XCTFail("예상한 오류가 아닙니다: \(error)")
            }
        }
        let preserved = try await storage.fetch(id: clip.id)
        XCTAssertEqual(preserved, clip)
    }

    func testUpdateCorruptedData() async throws {
        let storage = try makeStorage()
        let clip = Clip(content: .text("원문"))
        try await storage.insert(clip)
        let spy = ClipBridgeStorageServiceSpy(storage: storage, failure: ClipStorageError.corruptedData)
        let adapter = try makeAdapter(storage: spy)

        do {
            _ = try await adapter.updateClip(
                id: clip.id,
                name: nil,
                memo: nil,
                isPinned: false
            )
            XCTFail("실패해야 하는 요청이 성공했습니다.")
        } catch {
            guard case ClipBridgeError.corruptedData = error else {
                return XCTFail("예상한 오류가 아닙니다: \(error)")
            }
        }
        let preserved = try await storage.fetch(id: clip.id)
        XCTAssertEqual(preserved, clip)
    }

    func testUpdateCancellation() async throws {
        let storage = try makeStorage()
        let clip = Clip(content: .text("원문"))
        try await storage.insert(clip)
        let spy = ClipBridgeStorageServiceSpy(storage: storage, failure: CancellationError())
        let adapter = try makeAdapter(storage: spy)

        do {
            _ = try await adapter.updateClip(
                id: clip.id,
                name: nil,
                memo: nil,
                isPinned: false
            )
            XCTFail("실패해야 하는 요청이 성공했습니다.")
        } catch {
            guard error is CancellationError else {
                return XCTFail("예상한 오류가 아닙니다: \(error)")
            }
        }
        let preserved = try await storage.fetch(id: clip.id)
        XCTAssertEqual(preserved, clip)
    }

    func testDeleteWriteFailure() async throws {
        let storage = try makeStorage()
        let clip = Clip(content: .text("원문"))
        try await storage.insert(clip)
        let spy = ClipBridgeStorageServiceSpy(storage: storage, failure: ClipStorageError.writeFailed)
        let adapter = try makeAdapter(storage: spy)

        do {
            try await adapter.deleteClip(id: clip.id)
            XCTFail("실패해야 하는 요청이 성공했습니다.")
        } catch {
            guard case ClipBridgeError.writeFailed = error else {
                return XCTFail("예상한 오류가 아닙니다: \(error)")
            }
        }
        let preserved = try await storage.fetch(id: clip.id)
        XCTAssertEqual(preserved, clip)
    }

    func testDeleteCorruptedData() async throws {
        let storage = try makeStorage()
        let clip = Clip(content: .text("원문"))
        try await storage.insert(clip)
        let spy = ClipBridgeStorageServiceSpy(storage: storage, failure: ClipStorageError.corruptedData)
        let adapter = try makeAdapter(storage: spy)

        do {
            try await adapter.deleteClip(id: clip.id)
            XCTFail("실패해야 하는 요청이 성공했습니다.")
        } catch {
            guard case ClipBridgeError.corruptedData = error else {
                return XCTFail("예상한 오류가 아닙니다: \(error)")
            }
        }
        let preserved = try await storage.fetch(id: clip.id)
        XCTAssertEqual(preserved, clip)
    }

    func testDeleteCancellation() async throws {
        let storage = try makeStorage()
        let clip = Clip(content: .text("원문"))
        try await storage.insert(clip)
        let spy = ClipBridgeStorageServiceSpy(storage: storage, failure: CancellationError())
        let adapter = try makeAdapter(storage: spy)

        do {
            try await adapter.deleteClip(id: clip.id)
            XCTFail("실패해야 하는 요청이 성공했습니다.")
        } catch {
            guard error is CancellationError else {
                return XCTFail("예상한 오류가 아닙니다: \(error)")
            }
        }
        let preserved = try await storage.fetch(id: clip.id)
        XCTAssertEqual(preserved, clip)
    }

    private func makeStorage() throws -> SQLiteClipStorageService {
        try SQLiteClipStorageService(databaseURL: directory.appendingPathComponent("clips.sqlite"))
    }

    private func makeAdapter(storage: any ClipStorageService) throws -> ClipBridgeAdapter {
        let files = try ClipImageFileStore(rootURL: directory.appendingPathComponent("images", isDirectory: true))
        return ClipBridgeAdapter(storage: storage, images: ClipImageService(storage: storage, files: files))
    }
}

private actor ClipBridgeStorageServiceSpy: ClipStorageService {
    private let storage: SQLiteClipStorageService
    private let failure: any Error

    init(
        storage: SQLiteClipStorageService,
        failure: any Error
    ) {
        self.storage = storage
        self.failure = failure
    }

    func fetchAll(order: ClipSortOrder) async throws -> [Clip] {
        try await storage.fetchAll(order: order)
    }

    func fetch(id: Clip.ID) async throws -> Clip? {
        try await storage.fetch(id: id)
    }

    func insert(_ clip: Clip) async throws {
        try await storage.insert(clip)
    }

    func update(
        id: Clip.ID,
        change: ClipUpdate
    ) async throws -> Clip {
        throw failure
    }

    func delete(id: Clip.ID) async throws {
        throw failure
    }

    func changes() async -> AsyncStream<ClipStorageEvent> {
        await storage.changes()
    }
}
