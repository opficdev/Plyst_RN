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
}
