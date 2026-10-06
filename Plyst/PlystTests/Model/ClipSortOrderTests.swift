//
//  ClipSortOrderTests.swift
//  PlystTests
//
//  Created by opfic on 9/28/26.
//

import Foundation
import XCTest
@testable import Plyst

final class ClipSortOrderTests: XCTestCase {

    func testCreationOrderUsesIdentifierForTiesAndIgnoresUsageTime() {
        let first = makeClip(id: 1, createdAt: 300, lastUsedAt: 400)
        let second = makeClip(id: 2, createdAt: 300, lastUsedAt: 500)
        let older = makeClip(id: 3, createdAt: 100, lastUsedAt: 600)

        XCTAssertEqual(ClipSortOrder.createdAt.sorted([older, second, first]), [first, second, older])
        XCTAssertEqual(ClipSortOrder.createdAt.sorted([first, older, second]), [first, second, older])
    }

    func testUsageOrderPlacesUnusedClipsLastAndBreaksTiesDeterministically() {
        let recent = makeClip(id: 1, createdAt: 100, lastUsedAt: 500)
        let firstTie = makeClip(id: 2, createdAt: 300, lastUsedAt: 400)
        let secondTie = makeClip(id: 3, createdAt: 300, lastUsedAt: 400)
        let olderTie = makeClip(id: 4, createdAt: 200, lastUsedAt: 400)
        let unused = makeClip(id: 5, createdAt: 600)
        let olderUnused = makeClip(id: 6, createdAt: 550)
        let clips = [olderUnused, olderTie, secondTie, unused, firstTie, recent]
        let expected = [recent, firstTie, secondTie, olderTie, unused, olderUnused]

        XCTAssertEqual(ClipSortOrder.lastUsedAt.sorted(clips), expected)
        XCTAssertEqual(ClipSortOrder.lastUsedAt.sorted(Array(clips.reversed())), expected)
    }

    private func makeClip(id: UInt8, createdAt: TimeInterval, lastUsedAt: TimeInterval? = nil) -> Clip {
        Clip(
            id: UUID(uuid: (0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, id)),
            content: .text("Text"),
            createdAt: Date(timeIntervalSince1970: createdAt),
            lastUsedAt: lastUsedAt.map { Date(timeIntervalSince1970: $0) }
        )
    }
}
