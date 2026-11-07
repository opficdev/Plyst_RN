//
//  SystemClipboardWriterTests.swift
//  PlystTests
//
//  Created by opfic on 9/30/26.
//

import Foundation
import PlystCore
import UIKit
import UniformTypeIdentifiers
import XCTest
@testable import Plyst

/// 기존 클립보드 복구 절차를 공유하고 시스템 클립보드를 쓰는 검증을 같은 XCTestCase에 배치
extension SystemClipboardReaderTests {
    func testWriterCopiesOriginalImageDataAndTypeWithoutReencoding() throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent("Plyst-\(UUID())", isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let writer = SystemClipboardWriter(localOnly: true, expirationDate: nil)
        for type in [UTType.png.identifier, UTType.jpeg.identifier, UTType.gif.identifier] {
            let data = try ClipImageTestFixture.data(
                type: type,
                count: type == UTType.gif.identifier ? 2 : 1,
                orientation: 6
            )

            let original = directory.appendingPathComponent(UUID().uuidString)
            try data.write(to: original)

            let result = try writer.write(content: .image(path: original.path, contentType: type))

            XCTAssertEqual(result, .observed)
            XCTAssertEqual(UIPasteboard.general.numberOfItems, 1)
            XCTAssertEqual(UIPasteboard.general.data(forPasteboardType: type), data)
            XCTAssertNotNil(UIPasteboard.general.image)
        }
    }
}
