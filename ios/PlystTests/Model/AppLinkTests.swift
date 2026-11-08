//
//  AppLinkTests.swift
//  PlystTests
//
//  Created by opfic on 10/3/26.
//

import Foundation
import XCTest
@testable import Plyst

final class AppLinkTests: XCTestCase {
    func testSaveClipboardURLRoundTrips() throws {
        let url = try XCTUnwrap(AppLink.saveClipboard.url)

        XCTAssertEqual(url.absoluteString, "plystrn://clipboard/save")
        XCTAssertEqual(AppLink(url: url), .saveClipboard)
    }

    func testUnknownURLsAreRejected() throws {
        let urls = ["https://clipboard/save", "plystrn://clipboard/other", "plystrn://other/save", "plystrn://clipboard"]

        for string in urls {
            let url = try XCTUnwrap(URL(string: string))
            XCTAssertNil(AppLink(url: url), string)
        }
    }
}
