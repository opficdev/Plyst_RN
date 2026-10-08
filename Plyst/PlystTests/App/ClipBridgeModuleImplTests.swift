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

        ClipBridgeModuleImpl().getClip(clip.id.uuidString) { record, code in
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

        ClipBridgeModuleImpl().getClip(UUID().uuidString) { record, code in
            XCTAssertNil(record)
            XCTAssertNil(code)
            completion.fulfill()
        }

        await fulfillment(of: [completion], timeout: 2)
    }

    func testInvalidIdentifierReturnsCode() async {
        let completion = expectation(description: "조회 완료")

        ClipBridgeModuleImpl().getClip("invalid") { record, code in
            XCTAssertNil(record)
            XCTAssertEqual(code, "E_INVALID_ID")
            completion.fulfill()
        }

        await fulfillment(of: [completion], timeout: 2)
    }

    func testUnregisteredProviderReturnsUnavailable() async {
        await ClipBridge.unregister()
        let completion = expectation(description: "조회 완료")

        ClipBridgeModuleImpl().getClip(UUID().uuidString) { record, code in
            XCTAssertNil(record)
            XCTAssertEqual(code, "E_UNAVAILABLE")
            completion.fulfill()
        }

        await fulfillment(of: [completion], timeout: 2)
    }

    private func makeStorage() throws -> SQLiteClipStorageService {
        try SQLiteClipStorageService(databaseURL: directory.appendingPathComponent("clips.sqlite"))
    }

    private func makeAdapter(storage: SQLiteClipStorageService) throws -> ClipBridgeAdapter {
        let files = try ClipImageFileStore(rootURL: directory.appendingPathComponent("images", isDirectory: true))
        return ClipBridgeAdapter(storage: storage, images: ClipImageService(storage: storage, files: files))
    }
}
