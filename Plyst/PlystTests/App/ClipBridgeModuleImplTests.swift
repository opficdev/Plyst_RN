//
//  ClipBridgeModuleImplTests.swift
//  PlystTests
//
//  Created by opfic on 10/8/26.
//

import Foundation
import PlystBridge
import XCTest
@testable import Plyst

final class ClipBridgeModuleImplTests: XCTestCase {
    private let directory = FileManager.default.temporaryDirectory.appendingPathComponent("Plyst-module-\(UUID())", isDirectory: true)

    override func tearDown() async throws {
        await ClipBridge.unregister()
        if FileManager.default.fileExists(atPath: directory.path) {
            try FileManager.default.removeItem(at: directory)
        }
        try await super.tearDown()
    }

    func testFoundRecordReturnsName() async throws {
        let storage = try makeStorage()
        let adapter = try makeAdapter(storage: storage)
        let clip = Clip(content: .text("가족 👨‍👩‍👧‍👦"), name: "이름")
        try await storage.insert(clip)
        await ClipBridge.register(adapter)
        let completion = expectation(description: "조회 완료")

        ClipBridgeModuleImpl(emit: { _, _ in }).getClip(clip.id.uuidString) { record, code in
            XCTAssertEqual(record?["name"] as? String, "이름")
            XCTAssertEqual(record?["characterCount"] as? Int, 4)
            XCTAssertNil(code)
            completion.fulfill()
        }

        await fulfillment(of: [completion], timeout: 2)
    }

    func testMissingRecordReturnsNilWithoutCode() async throws {
        let adapter = try makeAdapter(storage: makeStorage())
        await ClipBridge.register(adapter)
        let completion = expectation(description: "조회 완료")

        ClipBridgeModuleImpl(emit: { _, _ in }).getClip(UUID().uuidString) { record, code in
            XCTAssertNil(record)
            XCTAssertNil(code)
            completion.fulfill()
        }

        await fulfillment(of: [completion], timeout: 2)
    }

    func testInvalidIdentifierReturnsCode() async {
        let completion = expectation(description: "조회 완료")

        ClipBridgeModuleImpl(emit: { _, _ in }).getClip("invalid") { record, code in
            XCTAssertNil(record)
            XCTAssertEqual(code, "E_INVALID_ID")
            completion.fulfill()
        }

        await fulfillment(of: [completion], timeout: 2)
    }

    func testUnregisteredProviderReturnsUnavailable() async {
        await ClipBridge.unregister()
        let completion = expectation(description: "조회 완료")

        ClipBridgeModuleImpl(emit: { _, _ in }).getClip(UUID().uuidString) { record, code in
            XCTAssertNil(record)
            XCTAssertEqual(code, "E_UNAVAILABLE")
            completion.fulfill()
        }

        await fulfillment(of: [completion], timeout: 2)
    }

    func testImageRecordContainsFormattedSizeWithoutURI() async throws {
        let adapter = try makeAdapter(storage: makeStorage())
        let data = try ClipImageTestFixture.data()
        let clip = try await adapter.images.saveImage(data).value
        await ClipBridge.register(adapter)
        let completion = expectation(description: "이미지 조회 완료")
        let expected = ByteCountFormatter.string(fromByteCount: Int64(data.count), countStyle: .file)

        ClipBridgeModuleImpl(emit: { _, _ in }).getClip(clip.id.uuidString) { record, code in
            let image = record?["image"] as? NSDictionary
            XCTAssertEqual(image?["byteCountText"] as? String, expected)
            XCTAssertNil(image?["uri"])
            XCTAssertNil(code)
            completion.fulfill()
        }

        await fulfillment(of: [completion], timeout: 2)
    }

    func testGetClipsReturnsDictionariesWithWebLink() async throws {
        let storage = try makeStorage()
        let adapter = try makeAdapter(storage: storage)
        let link = Clip(content: .text("https://example.com"), createdAt: Date(timeIntervalSince1970: 2))
        let plain = Clip(content: .text("원문"), createdAt: Date(timeIntervalSince1970: 1))
        try await storage.insert(plain)
        try await storage.insert(link)
        await ClipBridge.register(adapter)
        let completion = expectation(description: "목록 조회 완료")

        ClipBridgeModuleImpl(emit: { _, _ in }).getClips { records, code in
            let records = records as? [NSDictionary]
            XCTAssertEqual(records?.count, 2)
            XCTAssertEqual(records?.first?["id"] as? String, link.id.uuidString)
            XCTAssertEqual(records?.first?["text"] as? String, "https://example.com")
            XCTAssertEqual(records?.first?["characterCount"] as? Int, 19)
            XCTAssertEqual(records?.first?["isPinned"] as? Bool, false)
            XCTAssertEqual(records?.first?["isWebLink"] as? Bool, true)
            XCTAssertEqual(records?.last?["isWebLink"] as? Bool, false)
            XCTAssertEqual(records?.first?["createdAt"] as? Double, 2000)
            XCTAssertNil(code)
            completion.fulfill()
        }

        await fulfillment(of: [completion], timeout: 2)
    }

    func testGetClipsReturnsEmptyArray() async throws {
        let adapter = try makeAdapter(storage: makeStorage())
        await ClipBridge.register(adapter)
        let completion = expectation(description: "빈 목록 조회 완료")

        ClipBridgeModuleImpl(emit: { _, _ in }).getClips { records, code in
            XCTAssertEqual(records?.count, 0)
            XCTAssertNil(code)
            completion.fulfill()
        }

        await fulfillment(of: [completion], timeout: 2)
    }

    func testGetClipsUnregisteredProviderReturnsUnavailable() async {
        await ClipBridge.unregister()
        let completion = expectation(description: "목록 조회 실패")

        ClipBridgeModuleImpl(emit: { _, _ in }).getClips { records, code in
            XCTAssertNil(records)
            XCTAssertEqual(code, "E_UNAVAILABLE")
            completion.fulfill()
        }

        await fulfillment(of: [completion], timeout: 2)
    }

    func testGetClipsCorruptedDataReturnsCode() async throws {
        let spy = ClipBridgeStorageServiceSpy(storage: try makeStorage(), failure: ClipStorageError.corruptedData)
        let adapter = try makeAdapter(storage: spy)
        await ClipBridge.register(adapter)
        let completion = expectation(description: "목록 조회 실패")

        ClipBridgeModuleImpl(emit: { _, _ in }).getClips { records, code in
            XCTAssertNil(records)
            XCTAssertEqual(code, "E_CORRUPTED_DATA")
            completion.fulfill()
        }

        await fulfillment(of: [completion], timeout: 2)
    }

    func testGetClipsReadFailureReturnsCode() async throws {
        let spy = ClipBridgeStorageServiceSpy(storage: try makeStorage(), failure: ClipStorageError.readFailed)
        let adapter = try makeAdapter(storage: spy)
        await ClipBridge.register(adapter)
        let completion = expectation(description: "목록 조회 실패")

        ClipBridgeModuleImpl(emit: { _, _ in }).getClips { records, code in
            XCTAssertNil(records)
            XCTAssertEqual(code, "E_READ_FAILED")
            completion.fulfill()
        }

        await fulfillment(of: [completion], timeout: 2)
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
