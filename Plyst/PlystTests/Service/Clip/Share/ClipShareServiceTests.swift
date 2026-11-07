//
//  ClipShareServiceTests.swift
//  PlystTests
//
//  Created by opfic on 10/1/26.
//

import Foundation
import UniformTypeIdentifiers
import XCTest
@testable import Plyst

@MainActor
final class ClipShareServiceTests: ClipTemporaryDirectoryTestCase {
    func testTextProviderIsSavedAsTextClipWithTrimmedTitle() async throws {
        let core = try makeCore()
        let text = " \n한글 'text'\t🙂 "
        let item = makeItem(providers: [NSItemProvider(object: text as NSString)], title: "  공유 제목 \n")

        let result = try await makeService(core: core).save(item)

        let clip = try savedClip(result)
        XCTAssertEqual(clip.content, .text(text))
        XCTAssertEqual(clip.name, "공유 제목")
        XCTAssertNil(clip.memo)
        XCTAssertNil(clip.pinnedAt)
        let stored = try await core.fetchAll(order: .createdAt)
        XCTAssertEqual(stored, [clip])
    }

    func testURLProviderIsSavedAsTextClipWithOriginalString() async throws {
        let core = try makeCore()
        let original = "https://example.com/a%20b?query=value#section"
        let item = makeItem(providers: [NSItemProvider(object: try XCTUnwrap(URL(string: original)) as NSURL)])

        let result = try await makeService(core: core).save(item)

        let clip = try savedClip(result)
        XCTAssertEqual(clip.content, .text(original))
        XCTAssertNil(clip.name)
        XCTAssertTrue(clip.content.isWebLink)
    }

    func testTextItemRegisteredAsObjectIsSavedLikeSafariSelection() async throws {
        let core = try makeCore()
        let text = "Safari에서 선택한 텍스트"
        let provider = NSItemProvider(item: text as NSString, typeIdentifier: UTType.plainText.identifier)
        let item = makeItem(providers: [provider])

        let result = try await makeService(core: core).save(item)

        XCTAssertEqual(try savedClip(result).content, .text(text))
    }

    func testURLItemRegisteredAsObjectIsSavedAsOriginalString() async throws {
        let core = try makeCore()
        let original = "https://example.com/path?query=한글#section"
        let url = try XCTUnwrap(URL(string: original))
        let provider = NSItemProvider(item: url as NSURL, typeIdentifier: UTType.url.identifier)
        let item = makeItem(providers: [provider])

        let result = try await makeService(core: core).save(item)

        XCTAssertEqual(try savedClip(result).content, .text(url.absoluteString))
    }

    func testImageProviderIsSavedAsOriginalUntitledImageClip() async throws {
        let core = try makeCore()
        let data = try ClipImageTestFixture.data()
        let item = makeItem(providers: [makeImageProvider(data: data)], title: "무시되는 제목")

        let result = try await makeService(core: core).save(item)

        let clip = try savedClip(result)
        guard case .image(let image) = clip.content else { return XCTFail("이미지 클립 누락") }
        XCTAssertNil(clip.name)
        XCTAssertNil(clip.memo)
        XCTAssertEqual(image.contentType, UTType.png.identifier)
        XCTAssertEqual(image.pixelWidth, 2)
        XCTAssertEqual(image.pixelHeight, 3)
        XCTAssertEqual(image.byteCount, data.count)
        let reopened = try makeCore()
        let stored = try await reopened.fetchAll(order: .createdAt)
        XCTAssertEqual(stored, [clip])
        let loaded = try await reopened.loadImage(image)
        XCTAssertEqual(loaded, data)
        XCTAssertEqual(try entryCount(at: root), 1)
    }

    private func makeService(core: ClipCoreAdapter) -> ClipShareService {
        let session = URLSession(configuration: ClipImageDownloadService.configuration)
        addTeardownBlock { session.invalidateAndCancel() }
        return ClipShareService(
            core: core,
            downloads: ClipImageDownloadService(session: session)
        )
    }

    private func makeImageProvider(data: Data) -> NSItemProvider {
        let provider = NSItemProvider()
        provider.registerDataRepresentation(forTypeIdentifier: UTType.png.identifier, visibility: .all) { completion in
            completion(data, nil)
            return nil
        }
        return provider
    }

    private func makeItem(
        providers: [NSItemProvider],
        title: String? = nil
    ) -> ClipShareItem {
        let extensionItem = NSExtensionItem()
        extensionItem.attachments = providers
        if let title {
            extensionItem.attributedTitle = NSAttributedString(string: title)
        }
        return ClipShareItem(item: extensionItem)
    }

    private func savedClip(_ result: ClipShareSaveResult) throws -> Clip {
        guard case .saved(let clip) = result else {
            XCTFail("저장 성공 결과 누락")
            throw ClipShareTestError.unexpectedResult
        }
        return clip
    }
}

private enum ClipShareTestError: Error {
    case unexpectedResult
}
