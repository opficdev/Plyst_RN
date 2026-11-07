//
//  ClipboardServiceTests.swift
//  PlystTests
//
//  Created by opfic on 9/29/26.
//

import Foundation
import XCTest
@testable import Plyst

@MainActor
final class ClipboardServiceTests: ClipTemporaryDirectoryTestCase {
    func testSavedTextPreservesOriginalDefaultsAndBecomesLatestRecord() async throws {
        let core = try makeCore()
        let previous = Clip(content: .text("이전 기록"), createdAt: Date(timeIntervalSinceReferenceDate: 100))
        try await core.insert(previous)
        let stream = core.changes()
        let text = " \n한글 'text'\0🙂\nhttps://example.com/path?query=value\t "
        let spy = ClipboardReaderSpy(result: .text(text))
        let service = ClipboardService(core: core, reader: spy)

        let clip = try savedClip(await service.saveCurrentClipboard())

        XCTAssertEqual(clip.content, .text(text))
        XCTAssertNil(clip.name)
        XCTAssertNil(clip.memo)
        XCTAssertNil(clip.pinnedAt)
        XCTAssertNil(clip.lastUsedAt)
        XCTAssertNotEqual(clip.id, previous.id)
        XCTAssertEqual(spy.readCount, 1)
        let stored = try await core.fetchAll(order: .createdAt)
        XCTAssertEqual(stored, [clip, previous])
        let reopened = try makeCore()
        let restored = try await reopened.fetch(id: clip.id)
        XCTAssertEqual(restored, clip)
        await assertEvents(stream, expected: [.inserted(clip)])
    }

    func testURLTextIsStoredWithoutChangingItsRepresentation() async throws {
        let core = try makeCore()
        let text = "https://example.com/a%20b?query=value#section"
        let spy = ClipboardReaderSpy(result: .text(text))
        let service = ClipboardService(core: core, reader: spy)

        let clip = try savedClip(await service.saveCurrentClipboard())

        XCTAssertEqual(clip.content, .text(text))
        let stored = try await core.fetch(id: clip.id)
        XCTAssertEqual(stored, clip)
    }

    private func savedClip(_ result: ClipboardSaveResult) throws -> Clip {
        guard case .saved(let clip) = result else {
            XCTFail("저장 성공 결과 누락")
            throw ClipboardTestError.unexpectedResult
        }
        return clip
    }
}

private enum ClipboardTestError: Error {
    case unexpectedResult
}
