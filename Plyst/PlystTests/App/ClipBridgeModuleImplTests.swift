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

final class ClipBridgeModuleImplTests: ClipTemporaryDirectoryTestCase {
    override func tearDown() async throws {
        await ClipBridge.unregister()
        try await super.tearDown()
    }

    func testImageRecordContainsRawSizeWithoutURI() async throws {
        let adapter = try makeAdapter(core: makeCore())
        let data = try ClipImageTestFixture.data()
        let clip = try await adapter.core.saveImage(data).value
        await ClipBridge.register(adapter)
        let completion = expectation(description: "이미지 조회 완료")
        ClipBridgeModuleImpl(emit: { _, _ in }).getClip(clip.id.uuidString) { record, code in
            let image = record?["image"] as? NSDictionary
            XCTAssertEqual(image?["byteCount"] as? Int, data.count)
            XCTAssertNil(image?["uri"])
            XCTAssertTrue(record?["text"] is NSNull)
            XCTAssertNil(code)
            completion.fulfill()
        }

        await fulfillment(of: [completion], timeout: 2)
    }

    func testGetClipsReturnsDictionaries() async throws {
        let core = try makeCore()
        let adapter = makeAdapter(core: core)
        let link = Clip(content: .text("https://example.com"), createdAt: Date(timeIntervalSince1970: 2))
        let plain = Clip(content: .text("원문"), createdAt: Date(timeIntervalSince1970: 1))
        try await core.insert(plain)
        try await core.insert(link)
        await ClipBridge.register(adapter)
        let completion = expectation(description: "목록 조회 완료")

        ClipBridgeModuleImpl(emit: { _, _ in }).getClips { records, code in
            let records = records as? [NSDictionary]
            XCTAssertEqual(records?.count, 2)
            XCTAssertEqual(records?.first?["id"] as? String, link.id.uuidString)
            XCTAssertEqual(records?.first?["text"] as? String, "https://example.com")
            XCTAssertTrue(records?.first?["pinnedAt"] is NSNull)
            XCTAssertNil(records?.first?["isPinned"])
            XCTAssertEqual(records?.first?["isWebLink"] as? Bool, true)
            XCTAssertEqual(records?.last?["isWebLink"] as? Bool, false)
            XCTAssertEqual(records?.first?["createdAt"] as? Double, 2000)
            XCTAssertNil(code)
            completion.fulfill()
        }

        await fulfillment(of: [completion], timeout: 2)
    }

    func testUpdateArgumentsReachStoredClipThroughAdapter() async throws {
        let core = try makeCore()
        let adapter = makeAdapter(core: core)
        let clip = Clip(content: .text("원문"))
        try await core.insert(clip)
        await ClipBridge.register(adapter)
        let completion = expectation(description: "수정 완료")

        ClipBridgeModuleImpl(emit: { _, _ in }).updateClip(
            clip.id.uuidString,
            name: "이름",
            memo: "메모",
            isPinned: true
        ) { record, code in
            XCTAssertEqual(record?["name"] as? String, "이름")
            XCTAssertEqual(record?["memo"] as? String, "메모")
            XCTAssertNil(code)
            completion.fulfill()
        }

        await fulfillment(of: [completion], timeout: 2)
        let fetched = try await core.fetch(id: clip.id)
        let stored = try XCTUnwrap(fetched)
        XCTAssertEqual(stored.name, "이름")
        XCTAssertEqual(stored.memo, "메모")
        XCTAssertNotNil(stored.pinnedAt)
    }
}
