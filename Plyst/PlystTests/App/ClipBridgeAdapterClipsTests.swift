//
//  ClipBridgeAdapterClipsTests.swift
//  PlystTests
//
//  Created by opfic on 10/10/26.
//

import Foundation
import PlystBridge
import XCTest
@testable import Plyst

final class ClipBridgeAdapterClipsTests: XCTestCase {
    private let directory = FileManager.default.temporaryDirectory.appendingPathComponent("Plyst-bridge-clips-\(UUID())", isDirectory: true)

    override func tearDownWithError() throws {
        if FileManager.default.fileExists(atPath: directory.path) {
            try FileManager.default.removeItem(at: directory)
        }
        try super.tearDownWithError()
    }

    func testClipsReturnsAllRecordsInCreatedAtOrder() async throws {
        let storage = try makeStorage()
        let adapter = try makeAdapter(storage: storage)
        let older = Clip(content: .text("이전"), createdAt: Date(timeIntervalSince1970: 1))
        let first = Clip(
            id: try XCTUnwrap(UUID(uuidString: "00000000-0000-0000-0000-000000000001")),
            content: .text("첫째"),
            createdAt: Date(timeIntervalSince1970: 2)
        )
        let second = Clip(
            id: try XCTUnwrap(UUID(uuidString: "00000000-0000-0000-0000-000000000002")),
            content: .text("둘째"),
            createdAt: first.createdAt
        )
        for clip in [second, older, first] {
            try await storage.insert(clip)
        }

        let records = try await adapter.clips()

        XCTAssertEqual(records.map(\.id), [first.id, second.id, older.id].map(\.uuidString))
        XCTAssertEqual(records.map(\.text), ["첫째", "둘째", "이전"])
    }

    func testClipsUsesContentWebLinkValidation() async throws {
        let storage = try makeStorage()
        let adapter = try makeAdapter(storage: storage)
        let link = Clip(content: .text(" https://example.com "))
        let plain = Clip(content: .text("일반 텍스트"))
        try await storage.insert(link)
        try await storage.insert(plain)
        let image = try await adapter.images.saveImage(ClipImageTestFixture.data()).value

        let records = try await adapter.clips()

        XCTAssertEqual(records.count, 3)
        XCTAssertEqual(records.first { $0.id == link.id.uuidString }?.isWebLink, true)
        XCTAssertEqual(records.first { $0.id == plain.id.uuidString }?.isWebLink, false)
        XCTAssertEqual(records.first { $0.id == image.id.uuidString }?.isWebLink, false)
    }

    func testClipsReturnsEmptyList() async throws {
        let adapter = try makeAdapter(storage: makeStorage())

        let records = try await adapter.clips()

        XCTAssertTrue(records.isEmpty)
    }

    func testClipsCorruptedData() async throws {
        let spy = ClipBridgeStorageServiceSpy(storage: try makeStorage(), failure: ClipStorageError.corruptedData)
        let adapter = try makeAdapter(storage: spy)

        do {
            _ = try await adapter.clips()
            XCTFail("실패해야 하는 요청이 성공했습니다.")
        } catch {
            guard case ClipBridgeError.corruptedData = error else {
                return XCTFail("예상한 오류가 아닙니다: \(error)")
            }
        }
    }

    func testClipsReadFailure() async throws {
        let spy = ClipBridgeStorageServiceSpy(storage: try makeStorage(), failure: ClipStorageError.readFailed)
        let adapter = try makeAdapter(storage: spy)

        do {
            _ = try await adapter.clips()
            XCTFail("실패해야 하는 요청이 성공했습니다.")
        } catch {
            guard case ClipBridgeError.readFailed = error else {
                return XCTFail("예상한 오류가 아닙니다: \(error)")
            }
        }
    }

    func testClipsCancellation() async throws {
        let spy = ClipBridgeStorageServiceSpy(storage: try makeStorage(), failure: CancellationError())
        let adapter = try makeAdapter(storage: spy)

        do {
            _ = try await adapter.clips()
            XCTFail("실패해야 하는 요청이 성공했습니다.")
        } catch {
            guard error is CancellationError else {
                return XCTFail("예상한 오류가 아닙니다: \(error)")
            }
        }
    }

    private func makeStorage() throws -> SQLiteClipStorageService {
        try SQLiteClipStorageService(databaseURL: directory.appendingPathComponent("clips.sqlite"))
    }

    private func makeAdapter(storage: any ClipStorageService) throws -> ClipBridgeAdapter {
        let files = try ClipImageFileStore(rootURL: directory.appendingPathComponent("images", isDirectory: true))
        let images = ClipImageService(storage: storage, files: files)
        return ClipBridgeAdapter(
            storage: storage,
            images: images,
            clipboard: ClipboardService(storage: storage, images: images),
            photos: ClipPhotoLibraryService(storage: storage, images: images)
        )
    }
}
