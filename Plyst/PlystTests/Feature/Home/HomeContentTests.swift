//
//  HomeContentTests.swift
//  PlystTests
//
//  Created by opfic on 9/30/26.
//

import Foundation
import XCTest
@testable import Plyst

final class HomeContentTests: XCTestCase {
    func testAllFilterSeparatesPinnedClipsIntoPinnedRowWithoutDuplicatingTimeline() throws {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = try XCTUnwrap(TimeZone(secondsFromGMT: 0))
        let now = try XCTUnwrap(calendar.date(from: DateComponents(year: 2026, month: 9, day: 30, hour: 10)))
        let pinned = Clip(
            content: .text("고정된 텍스트"),
            isPinned: true,
            createdAt: now.addingTimeInterval(-30)
        )
        let unpinned = Clip(content: .text("일반 텍스트"), createdAt: now.addingTimeInterval(-60))

        let content = HomeContent.make(
            from: [pinned, unpinned],
            filter: .all,
            now: now,
            calendar: calendar
        )

        XCTAssertEqual(content.pinnedClips, [pinned])
        XCTAssertEqual(content.sections.flatMap(\.clips), [unpinned])
    }

    func testTextAndImageFiltersExcludeOtherTypes() throws {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = try XCTUnwrap(TimeZone(secondsFromGMT: 0))
        let now = try XCTUnwrap(calendar.date(from: DateComponents(year: 2026, month: 9, day: 30, hour: 10)))
        let text = Clip(content: .text("텍스트"), createdAt: now.addingTimeInterval(-30))
        let metadata = ClipImageMetadata(
            fileID: UUID(),
            contentType: "public.png",
            pixelWidth: 10,
            pixelHeight: 10,
            byteCount: 1
        )
        let image = Clip(content: .image(metadata), createdAt: now.addingTimeInterval(-60))

        let textContent = HomeContent.make(
            from: [text, image],
            filter: .text,
            now: now,
            calendar: calendar
        )
        let imageContent = HomeContent.make(
            from: [text, image],
            filter: .image,
            now: now,
            calendar: calendar
        )

        XCTAssertEqual(textContent.sections.flatMap(\.clips), [text])
        XCTAssertTrue(textContent.pinnedClips.isEmpty)
        XCTAssertEqual(imageContent.sections.flatMap(\.clips), [image])
        XCTAssertTrue(imageContent.pinnedClips.isEmpty)
    }

    func testPinnedFilterShowsOnlyPinnedClipsAsTimelineWithoutPinnedRow() throws {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = try XCTUnwrap(TimeZone(secondsFromGMT: 0))
        let now = try XCTUnwrap(calendar.date(from: DateComponents(year: 2026, month: 9, day: 30, hour: 10)))
        let pinned = Clip(
            content: .text("고정"),
            isPinned: true,
            createdAt: now.addingTimeInterval(-30)
        )
        let unpinned = Clip(content: .text("일반"), createdAt: now.addingTimeInterval(-60))

        let content = HomeContent.make(
            from: [pinned, unpinned],
            filter: .pinned,
            now: now,
            calendar: calendar
        )

        XCTAssertTrue(content.pinnedClips.isEmpty)
        XCTAssertEqual(content.sections.flatMap(\.clips), [pinned])
    }

    func testIsEmptyRequiresBothPinnedRowAndSectionsEmpty() throws {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = try XCTUnwrap(TimeZone(secondsFromGMT: 0))
        let now = try XCTUnwrap(calendar.date(from: DateComponents(year: 2026, month: 9, day: 30, hour: 10)))
        let pinned = Clip(
            content: .text("고정"),
            isPinned: true,
            createdAt: now.addingTimeInterval(-30)
        )

        let onlyPinned = HomeContent.make(
            from: [pinned],
            filter: .all,
            now: now,
            calendar: calendar
        )
        let noImages = HomeContent.make(
            from: [pinned],
            filter: .image,
            now: now,
            calendar: calendar
        )

        XCTAssertFalse(onlyPinned.isEmpty)
        XCTAssertTrue(noImages.isEmpty)
    }
}
