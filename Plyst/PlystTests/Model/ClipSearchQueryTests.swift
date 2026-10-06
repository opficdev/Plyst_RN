//
//  ClipSearchQueryTests.swift
//  PlystTests
//
//  Created by opfic on 9/30/26.
//

import Foundation
import XCTest
@testable import Plyst

final class ClipSearchQueryTests: XCTestCase {
    func testInitializerTrimsWhitespaceAndRejectsBlankInput() {
        XCTAssertEqual(ClipSearchQuery("  Swift \n")?.text, "Swift")
        XCTAssertNil(ClipSearchQuery(""))
        XCTAssertNil(ClipSearchQuery(" \n\t "))
    }

    func testMatchingIgnoresCaseOnly() throws {
        let query = try XCTUnwrap(ClipSearchQuery("qr"))

        XCTAssertTrue(query.matches("Scan the QR code"))
        XCTAssertTrue(query.matches("qr"))
        XCTAssertFalse(query.matches("q r"))
        XCTAssertFalse(try XCTUnwrap(ClipSearchQuery("cafe")).matches("Café"))
    }

    func testRangesReturnEveryNonOverlappingMatch() throws {
        let query = try XCTUnwrap(ClipSearchQuery("aa"))
        let target = "aaaa AA a"

        let matches = query.ranges(in: target).map { String(target[$0]) }

        XCTAssertEqual(matches, ["aa", "aa", "AA"])
    }

    func testRangesAreEmptyWhenNothingMatches() throws {
        let query = try XCTUnwrap(ClipSearchQuery("xyz"))

        XCTAssertTrue(query.ranges(in: "abc").isEmpty)
        XCTAssertTrue(query.ranges(in: "").isEmpty)
    }

    func testRangesMatchCanonicallyEquivalentKorean() throws {
        let composed = "한글"
        let decomposed = "한글".decomposedStringWithCanonicalMapping
        let target = "앞 \(decomposed) 뒤"

        let query = try XCTUnwrap(ClipSearchQuery(composed))
        let matches = query.ranges(in: target).map { String(target[$0]) }

        XCTAssertEqual(matches, [decomposed])
    }

    func testRangesKeepGraphemeBoundariesAroundEmojiAndCombiningMarks() throws {
        let query = try XCTUnwrap(ClipSearchQuery("e"))
        let target = "👨‍👩‍👧 e\u{0301}x e"

        let ranges = query.ranges(in: target)

        for range in ranges {
            XCTAssertEqual(target.rangeOfComposedCharacterSequences(for: range), range)
        }
        XCTAssertFalse(ranges.isEmpty)
    }
}
