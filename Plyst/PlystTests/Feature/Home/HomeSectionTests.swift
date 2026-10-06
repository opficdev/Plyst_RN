//
//  HomeSectionTests.swift
//  PlystTests
//
//  Created by opfic on 9/30/26.
//

import Foundation
import XCTest
@testable import Plyst

final class HomeSectionTests: XCTestCase {
    func testCreationTimeGroupsKeepStorageOrderAndExcludeEmptySections() throws {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = try XCTUnwrap(TimeZone(secondsFromGMT: 0))
        let now = try XCTUnwrap(calendar.date(from: DateComponents(year: 2026, month: 9, day: 30, hour: 10)))
        let newest = Clip(content: .text("최신"), createdAt: now.addingTimeInterval(-30))
        let recent = Clip(content: .text("방금"), createdAt: now.addingTimeInterval(-120))
        let today = Clip(content: .text("오늘"), createdAt: now.addingTimeInterval(-60 * 60))
        let yesterday = Clip(content: .text("어제"), createdAt: now.addingTimeInterval(-20 * 60 * 60))
        let earlier = Clip(content: .text("이전"), createdAt: now.addingTimeInterval(-3 * 24 * 60 * 60))

        let sections = HomeSection.make(
            from: [newest, recent, today, yesterday, earlier],
            now: now,
            calendar: calendar
        )

        XCTAssertEqual(sections.map(\.kind), [.recent, .today, .yesterday, .earlier])
        XCTAssertEqual(sections[0].clips, [newest, recent])
        XCTAssertEqual(sections[1].clips, [today])
        XCTAssertEqual(sections[2].clips, [yesterday])
        XCTAssertEqual(sections[3].clips, [earlier])
    }

    func testRecentCrossesMidnightAndFiveMinuteBoundaryIsExcluded() throws {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = try XCTUnwrap(TimeZone(secondsFromGMT: 0))
        let now = try XCTUnwrap(calendar.date(from: DateComponents(year: 2026, month: 9, day: 30, hour: 0, minute: 2)))
        let recent = Clip(content: .text("자정 직전"), createdAt: now.addingTimeInterval(-3 * 60))
        let boundary = Clip(content: .text("경계"), createdAt: now.addingTimeInterval(-5 * 60))
        let yesterday = Clip(content: .text("어제"), createdAt: now.addingTimeInterval(-12 * 60))

        let sections = HomeSection.make(
            from: [recent, boundary, yesterday],
            now: now,
            calendar: calendar
        )

        XCTAssertEqual(sections.map(\.kind), [.recent, .yesterday])
        XCTAssertEqual(sections[0].clips, [recent])
        XCTAssertEqual(sections[1].clips, [boundary, yesterday])
    }
}
