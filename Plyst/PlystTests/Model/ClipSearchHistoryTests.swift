//
//  ClipSearchHistoryTests.swift
//  PlystTests
//
//  Created by opfic on 9/30/26.
//

import Foundation
import XCTest
@testable import Plyst

final class ClipSearchHistoryTests: XCTestCase {
    func testRecordPlacesNewestFirst() throws {
        var history = ClipSearchHistory()

        history.record(try query("first"))
        history.record(try query("second"))

        XCTAssertEqual(history.terms, ["second", "first"])
    }

    func testRecordMovesCaseInsensitiveDuplicateToFrontAndKeepsNewSpelling() throws {
        var history = ClipSearchHistory()
        history.record(try query("qr"))
        history.record(try query("swift"))

        history.record(try query("QR"))

        XCTAssertEqual(history.terms, ["QR", "swift"])
    }

    func testRecordTreatsCanonicallyEquivalentKoreanAsSameTerm() throws {
        var history = ClipSearchHistory()
        history.record(try query("한글"))

        history.record(try query("한글".decomposedStringWithCanonicalMapping))

        XCTAssertEqual(history.terms.count, 1)
    }

    func testRecordKeepsAtMostFiveTermsAndDropsTheOldest() throws {
        var history = ClipSearchHistory()

        for term in ["1", "2", "3", "4", "5", "6"] {
            history.record(try query(term))
        }

        XCTAssertEqual(history.terms, ["6", "5", "4", "3", "2"])
    }

    func testRemoveDeletesCaseInsensitiveMatchOnly() throws {
        var history = ClipSearchHistory()
        history.record(try query("alpha"))
        history.record(try query("Beta"))

        history.remove("BETA")

        XCTAssertEqual(history.terms, ["alpha"])
    }

    func testRemoveIgnoresMissingAndBlankTerms() throws {
        var history = ClipSearchHistory()
        history.record(try query("alpha"))
        let original = history

        history.remove("missing")
        history.remove("   ")

        XCTAssertEqual(history, original)
    }

    func testRestoringAcceptsValidTerms() {
        XCTAssertEqual(ClipSearchHistory(terms: ["b", "a"])?.terms, ["b", "a"])
        XCTAssertEqual(ClipSearchHistory(terms: []), ClipSearchHistory())
    }

    func testRestoringRejectsRuleViolations() {
        XCTAssertNil(ClipSearchHistory(terms: ["a", "A"]))
        XCTAssertNil(ClipSearchHistory(terms: ["1", "2", "3", "4", "5", "6"]))
        XCTAssertNil(ClipSearchHistory(terms: [" padded "]))
        XCTAssertNil(ClipSearchHistory(terms: [""]))
    }

    private func query(_ raw: String) throws -> ClipSearchQuery {
        try XCTUnwrap(ClipSearchQuery(raw))
    }
}
