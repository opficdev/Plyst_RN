//
//  SystemClipboardWriterTests.swift
//  PlystTests
//
//  Created by opfic on 9/30/26.
//

import Foundation
import UIKit
import UniformTypeIdentifiers
import XCTest
@testable import Plyst

/// 기존 클립보드 복구 절차를 공유하고 시스템 클립보드를 쓰는 검증을 같은 XCTestCase에 배치합니다.
extension SystemClipboardReaderTests {
    func testWriterCopiesOriginalTextAndReplacesPreviousItems() async throws {
        UIPasteboard.general.items = [
            [UTType.utf8PlainText.identifier: "기존 항목"],
            [UTType.utf8PlainText.identifier: "추가 항목"]
        ]
        let text = " \n한글🙂\0https://example.com/a%20b\t "
        let writer = SystemClipboardWriter(localOnly: true, expirationDate: nil)

        let result = try await writer.write(.text(text))

        XCTAssertEqual(result, .observed)
        XCTAssertEqual(UIPasteboard.general.numberOfItems, 1)
        XCTAssertEqual(UIPasteboard.general.string, text)
        XCTAssertEqual(UIPasteboard.general.value(forPasteboardType: UTType.utf8PlainText.identifier) as? String, text)
    }

    func testWriterCopiesOriginalImageDataAndTypeWithoutReencoding() async throws {
        let writer = SystemClipboardWriter(localOnly: true, expirationDate: nil)
        for type in [UTType.png.identifier, UTType.jpeg.identifier, UTType.gif.identifier] {
            let data = try ClipImageTestFixture.data(
                type: type,
                count: type == UTType.gif.identifier ? 2 : 1,
                orientation: 6
            )

            let result = try await writer.write(.image(data: data, contentType: type))

            XCTAssertEqual(result, .observed)
            XCTAssertEqual(UIPasteboard.general.numberOfItems, 1)
            XCTAssertEqual(UIPasteboard.general.data(forPasteboardType: type), data)
            XCTAssertNotNil(UIPasteboard.general.image)
        }
    }

    func testWriterSupportsExplicitHandoffAndExpirationOptions() async throws {
        let writer = SystemClipboardWriter(localOnly: false, expirationDate: Date(timeIntervalSinceNow: 60))

        let result = try await writer.write(.text("만료 정책이 있는 원문"))

        // 공개 API는 적용된 옵션을 조회하지 못하므로 해당 옵션을 전달한 쓰기와 기기 내부 표현만 확인합니다.
        XCTAssertEqual(result, .observed)
        XCTAssertEqual(UIPasteboard.general.string, "만료 정책이 있는 원문")
    }

    func testCancelledWriterPreservesPreviousClipboardContents() async throws {
        let text = "기존 클립보드"
        UIPasteboard.general.items = [[UTType.utf8PlainText.identifier: text]]
        let writer = SystemClipboardWriter(localOnly: true, expirationDate: nil)
        let task = Task {
            withUnsafeCurrentTask { $0?.cancel() }
            return try await writer.write(.text("취소된 원문"))
        }

        do {
            _ = try await task.value
            XCTFail("취소된 클립보드 쓰기 성공")
        } catch { XCTAssertTrue(error is CancellationError) }

        XCTAssertEqual(UIPasteboard.general.string, text)
    }
}
