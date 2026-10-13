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
        let updated = ClipUpdate.details(name: "Edited name", memo: "Edited memo", isPinned: true, requestedAt: Date(timeIntervalSince1970: 300)).applying(to: used)

        XCTAssertEqual(updated.id, original.id)
        XCTAssertEqual(updated.content, original.content)
        XCTAssertEqual(updated.createdAt, original.createdAt)
        XCTAssertEqual(updated.lastUsedAt, date)
        XCTAssertEqual(updated.name, "Edited name")
        XCTAssertEqual(updated.memo, "Edited memo")
        XCTAssertNotNil(updated.pinnedAt)
    }

    func testDetailsCanClearOptionalFieldsAndUnpinAnImage() {
        let image = ClipImageMetadata(fileID: UUID(), contentType: "public.png", pixelWidth: 640, pixelHeight: 480, byteCount: 4096)
        let original = Clip(
            content: .image(image),
            name: "Image",
            pinnedAt: Date(timeIntervalSince1970: 100),
            memo: "Memo",
            lastUsedAt: Date(timeIntervalSince1970: 200)
        )
        let updated = ClipUpdate.details(name: nil, memo: nil, isPinned: false, requestedAt: Date(timeIntervalSince1970: 300)).applying(to: original)

        XCTAssertNil(updated.name)
        XCTAssertNil(updated.memo)
        XCTAssertNil(updated.pinnedAt)
        XCTAssertEqual(updated.id, original.id)
        XCTAssertEqual(updated.content, original.content)
        XCTAssertEqual(updated.createdAt, original.createdAt)
        XCTAssertEqual(updated.lastUsedAt, original.lastUsedAt)
    }

    func testRecordingUsagePreservesAllOtherFields() {
        let original = Clip(
            content: .text("Original text"),
            name: "Name",
            pinnedAt: Date(timeIntervalSince1970: 100),
            memo: "Memo",
            createdAt: Date(timeIntervalSince1970: 100)
        )
        let date = Date(timeIntervalSince1970: 200)
        let updated = ClipUpdate.lastUsedAt(date).applying(to: original)

        XCTAssertEqual(updated.id, original.id)
        XCTAssertEqual(updated.content, original.content)
        XCTAssertEqual(updated.name, original.name)
        XCTAssertEqual(updated.pinnedAt, original.pinnedAt)
        XCTAssertEqual(updated.memo, original.memo)
        XCTAssertEqual(updated.createdAt, original.createdAt)
        XCTAssertEqual(updated.lastUsedAt, date)
    }

    func testUnchangedDetailsProduceAnEqualSnapshot() {
        let original = Clip(
            content: .text("Original text"),
            name: "Name",
            pinnedAt: Date(timeIntervalSince1970: 100),
            memo: "Memo"
        )
        let updated = ClipUpdate.details(name: original.name, memo: original.memo, isPinned: original.pinnedAt != nil, requestedAt: Date(timeIntervalSince1970: 300)).applying(to: original)

        XCTAssertEqual(updated, original)
    }

    func testPinTransitionsPreserveAndReplaceRequestedTimes() {
        let original = Clip(content: .text("원문"))
        let first = Date(timeIntervalSince1970: 100)
        let later = Date(timeIntervalSince1970: 200)
        let unchanged = ClipUpdate.details(name: nil, memo: nil, isPinned: false, requestedAt: first).applying(to: original)
        XCTAssertNil(unchanged.pinnedAt)

        let pinned = ClipUpdate.details(name: nil, memo: nil, isPinned: true, requestedAt: first).applying(to: original)
        XCTAssertEqual(pinned.pinnedAt, first)
        let kept = ClipUpdate.details(name: nil, memo: nil, isPinned: true, requestedAt: later).applying(to: pinned)
        XCTAssertEqual(kept.pinnedAt, first)
        let edited = ClipUpdate.details(name: "새 이름", memo: "새 메모", isPinned: true, requestedAt: later).applying(to: kept)
        XCTAssertEqual(edited.pinnedAt, first)
        XCTAssertEqual(edited.name, "새 이름")
        XCTAssertEqual(edited.memo, "새 메모")

        let unpinned = ClipUpdate.details(name: nil, memo: nil, isPinned: false, requestedAt: later).applying(to: edited)
        XCTAssertNil(unpinned.pinnedAt)
        let repinned = ClipUpdate.details(name: nil, memo: nil, isPinned: true, requestedAt: later).applying(to: unpinned)
        XCTAssertEqual(repinned.pinnedAt, later)
    }
}
