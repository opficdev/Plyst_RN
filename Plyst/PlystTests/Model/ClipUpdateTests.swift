//
//  ClipUpdateTests.swift
//  PlystTests
//
//  Created by opfic on 9/28/26.
//

import Foundation
import XCTest
@testable import Plyst

final class ClipUpdateTests: XCTestCase {

    func testSavingDetailsAfterCopyPreservesTheLatestUsageTimestamp() {
        let original = Clip(
            content: .text("Original text"),
            name: "Original name",
            memo: "Original memo",
            createdAt: Date(timeIntervalSince1970: 100)
        )
        let date = Date(timeIntervalSince1970: 200)
        let used = ClipUpdate.lastUsedAt(date).applying(to: original)
        let updated = ClipUpdate.details(name: "Edited name", memo: "Edited memo", isPinned: true).applying(to: used)

        XCTAssertEqual(updated.id, original.id)
        XCTAssertEqual(updated.content, original.content)
        XCTAssertEqual(updated.createdAt, original.createdAt)
        XCTAssertEqual(updated.lastUsedAt, date)
        XCTAssertEqual(updated.name, "Edited name")
        XCTAssertEqual(updated.memo, "Edited memo")
        XCTAssertTrue(updated.isPinned)
    }

    func testDetailsCanClearOptionalFieldsAndUnpinAnImage() {
        let image = ClipImageMetadata(fileID: UUID(), contentType: "public.png", pixelWidth: 640, pixelHeight: 480, byteCount: 4096)
        let original = Clip(content: .image(image), name: "Image", isPinned: true, memo: "Memo", lastUsedAt: Date(timeIntervalSince1970: 200))
        let updated = ClipUpdate.details(name: nil, memo: nil, isPinned: false).applying(to: original)

        XCTAssertNil(updated.name)
        XCTAssertNil(updated.memo)
        XCTAssertFalse(updated.isPinned)
        XCTAssertEqual(updated.id, original.id)
        XCTAssertEqual(updated.content, original.content)
        XCTAssertEqual(updated.createdAt, original.createdAt)
        XCTAssertEqual(updated.lastUsedAt, original.lastUsedAt)
    }

    func testRecordingUsagePreservesAllOtherFields() {
        let original = Clip(content: .text("Original text"), name: "Name", isPinned: true, memo: "Memo", createdAt: Date(timeIntervalSince1970: 100))
        let date = Date(timeIntervalSince1970: 200)
        let updated = ClipUpdate.lastUsedAt(date).applying(to: original)

        XCTAssertEqual(updated.id, original.id)
        XCTAssertEqual(updated.content, original.content)
        XCTAssertEqual(updated.name, original.name)
        XCTAssertEqual(updated.isPinned, original.isPinned)
        XCTAssertEqual(updated.memo, original.memo)
        XCTAssertEqual(updated.createdAt, original.createdAt)
        XCTAssertEqual(updated.lastUsedAt, date)
    }

    func testUnchangedDetailsProduceAnEqualSnapshot() {
        let original = Clip(content: .text("Original text"), name: "Name", isPinned: true, memo: "Memo")
        let updated = ClipUpdate.details(name: original.name, memo: original.memo, isPinned: original.isPinned).applying(to: original)

        XCTAssertEqual(updated, original)
    }
}
