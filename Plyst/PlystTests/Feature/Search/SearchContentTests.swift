//
//  SearchContentTests.swift
//  PlystTests
//
//  Created by opfic on 9/30/26.
//

import Foundation
import XCTest
@testable import Plyst

final class SearchContentTests: XCTestCase {
    private let now = Date(timeIntervalSinceReferenceDate: 800_000_000)

    func testBlankQueryProducesNoResults() {
        let clips = [makeText("Swift", id: 1)]

        let content = SearchContent.make(from: clips, query: nil, filter: .all, now: now)

        XCTAssertNil(content.query)
        XCTAssertTrue(content.results.isEmpty)
    }

    func testTextIsFoundByBodyAndNameIgnoringCase() throws {
        let body = makeText("Scan the QR code", id: 1)
        let named = makeText("무관한 본문", id: 2, name: "qr 메모")
        let other = makeText("Swift", id: 3)

        let content = SearchContent.make(from: [body, named, other], query: try query("qr"), filter: .all, now: now)

        XCTAssertEqual(content.results.map(\.clip.id), [body.id, named.id])
        XCTAssertEqual(content.results[0].bodyRanges.count, 1)
        XCTAssertTrue(content.results[0].nameRanges.isEmpty)
        XCTAssertEqual(content.results[1].nameRanges.count, 1)
        XCTAssertTrue(content.results[1].bodyRanges.isEmpty)
    }

    func testMatchRangesPointIntoTheOriginalStrings() throws {
        let clip = makeText("Alpha alpha", id: 1, name: "ALPHA name")

        let content = SearchContent.make(from: [clip], query: try query("alpha"), filter: .all, now: now)
        let result = try XCTUnwrap(content.results.first)

        XCTAssertEqual(result.bodyRanges.map { String("Alpha alpha"[$0]) }, ["Alpha", "alpha"])
        XCTAssertEqual(result.nameRanges.map { String("ALPHA name"[$0]) }, ["ALPHA"])
    }

    func testImageIsFoundByNameButPlaceholderNameIsNotSearchable() throws {
        let named = makeImage(id: 1, name: "Receipt")
        let unnamed = makeImage(id: 2)

        let byName = SearchContent.make(from: [named, unnamed], query: try query("receipt"), filter: .all, now: now)
        let byPlaceholder = SearchContent.make(from: [unnamed], query: try query("이름 없는"), filter: .all, now: now)

        XCTAssertEqual(byName.results.map(\.clip.id), [named.id])
        XCTAssertTrue(byPlaceholder.results.isEmpty)
    }

    func testImageIsFoundBySavedTimeButTextIsNot() throws {
        let calendar = Calendar.current
        let yesterdayNoon = try XCTUnwrap(calendar.date(byAdding: .hour, value: -12, to: calendar.startOfDay(for: now)))
        let image = makeImage(id: 1, createdAt: yesterdayNoon)
        let text = makeText("무관한 본문", id: 2, createdAt: yesterdayNoon)
        let dateText = DateFormatter.localizedString(from: yesterdayNoon, dateStyle: .medium, timeStyle: .none)

        let bySection = SearchContent.make(from: [image, text], query: try query("어제"), filter: .all, now: now)
        let byDate = SearchContent.make(from: [image, text], query: try query(dateText), filter: .all, now: now)

        XCTAssertEqual(bySection.results.map(\.clip.id), [image.id])
        XCTAssertEqual(byDate.results.map(\.clip.id), [image.id])
        XCTAssertTrue(bySection.results[0].nameRanges.isEmpty)
    }

    func testFilterAndQueryApplyTogetherAndCountsFollowFilteredResults() throws {
        let text = makeText("report text", id: 1)
        let pinnedText = makeText("report pinned", id: 2, isPinned: true)
        let image = makeImage(id: 3, name: "report image")
        let clips = [text, pinnedText, image]
        let query = try query("report")

        let all = SearchContent.make(from: clips, query: query, filter: .all, now: now)
        let textOnly = SearchContent.make(from: clips, query: query, filter: .text, now: now)
        let imageOnly = SearchContent.make(from: clips, query: query, filter: .image, now: now)
        let pinned = SearchContent.make(from: clips, query: query, filter: .pinned, now: now)

        XCTAssertEqual(all.results.count, 3)
        XCTAssertEqual(all.textCount, 2)
        XCTAssertEqual(all.imageCount, 1)
        XCTAssertEqual(textOnly.results.map(\.clip.id), [text.id, pinnedText.id])
        XCTAssertEqual(textOnly.imageCount, 0)
        XCTAssertEqual(imageOnly.results.map(\.clip.id), [image.id])
        XCTAssertEqual(imageOnly.textCount, 0)
        XCTAssertEqual(pinned.results.map(\.clip.id), [pinnedText.id])
    }

    func testResultsKeepInputOrder() throws {
        let clips = [makeText("a match", id: 3), makeText("a match", id: 1), makeText("a match", id: 2)]

        let content = SearchContent.make(from: clips, query: try query("match"), filter: .all, now: now)

        XCTAssertEqual(content.results.map(\.clip.id), clips.map(\.id))
    }

    func testBodyExcerptStartsFourteenCharactersBeforeALateMatch() throws {
        let prefix = String(repeating: "가", count: 50)
        let late = makeText(prefix + "target", id: 1)
        let early = makeText("target" + prefix, id: 2)
        let boundary = makeText(String(repeating: "가", count: 40) + "target", id: 3)

        let content = SearchContent.make(from: [late, early, boundary], query: try query("target"), filter: .all, now: now)

        let lateStart = try XCTUnwrap(content.results[0].bodyExcerptStart)
        XCTAssertEqual(String((prefix + "target")[lateStart...]), String(repeating: "가", count: 14) + "target")
        XCTAssertNil(content.results[1].bodyExcerptStart)
        XCTAssertNil(content.results[2].bodyExcerptStart)
    }

    private func query(_ raw: String) throws -> ClipSearchQuery {
        try XCTUnwrap(ClipSearchQuery(raw))
    }

    private func makeText(
        _ text: String,
        id: UInt8,
        name: String? = nil,
        isPinned: Bool = false,
        createdAt: Date? = nil
    ) -> Clip {
        Clip(
            id: UUID(uuid: (0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, id)),
            content: .text(text),
            name: name,
            isPinned: isPinned,
            createdAt: createdAt ?? now.addingTimeInterval(-TimeInterval(id) * 3_600 * 24 * 30)
        )
    }

    private func makeImage(
        id: UInt8,
        name: String? = nil,
        createdAt: Date? = nil
    ) -> Clip {
        Clip(
            id: UUID(uuid: (0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 1, id)),
            content: .image(ClipImageMetadata(
                fileID: UUID(),
                contentType: "public.png",
                pixelWidth: 10,
                pixelHeight: 10,
                byteCount: 100
            )),
            name: name,
            createdAt: createdAt ?? now.addingTimeInterval(-TimeInterval(id) * 3_600 * 24 * 30)
        )
    }
}
