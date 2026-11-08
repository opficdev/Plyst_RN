//
//  SystemClipboardReaderTests.swift
//  PlystTests
//
//  Created by opfic on 9/29/26.
//

import Foundation
import UIKit
import UniformTypeIdentifiers
import XCTest
@testable import Plyst

@MainActor
final class SystemClipboardReaderTests: XCTestCase {
    private var items = [[String: Any]]()

    override func setUp() async throws {
        try await super.setUp()
        items = UIPasteboard.general.items
    }

    override func tearDown() async throws {
        UIPasteboard.general.items = items
        try await super.tearDown()
    }

    func testImageWinsOverTextAndURLInTheSameItemWithoutChangingBytes() async throws {
        let data = try ClipImageTestFixture.data(type: UTType.jpeg.identifier, orientation: 6)
        let url = try XCTUnwrap(URL(string: "https://example.com/image"))
        UIPasteboard.general.items = [[
            UTType.jpeg.identifier: data,
            UTType.utf8PlainText.identifier: "이미지 설명",
            UTType.url.identifier: url
        ]]

        let result = try SystemClipboardReader().read()

        XCTAssertEqual(result, .image(data))
    }

    func testAnimatedImageBytesAreReadWithoutReencoding() async throws {
        let data = try ClipImageTestFixture.data(type: UTType.gif.identifier, count: 2)
        UIPasteboard.general.items = [[UTType.gif.identifier: data]]

        let result = try SystemClipboardReader().read()

        XCTAssertEqual(result, .image(data))
    }
}
