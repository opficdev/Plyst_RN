//
//  ClipShareServiceTests.swift
//  PlystTests
//
//  Created by opfic on 10/1/26.
//

import Foundation
import UIKit
import UniformTypeIdentifiers
import XCTest
@testable import Plyst

@MainActor
final class ClipShareServiceTests: XCTestCase {
    private let directory = FileManager.default.temporaryDirectory.appendingPathComponent("Plyst-share-\(UUID())", isDirectory: true)
    private var url: URL { directory.appendingPathComponent("ShareInbox.sqlite") }

    override func tearDownWithError() throws {
        if FileManager.default.fileExists(atPath: directory.path) {
            try FileManager.default.removeItem(at: directory)
        }
        try super.tearDownWithError()
    }

    func testTextProviderIsSavedAsTextClipWithTrimmedTitle() async throws {
        let storage = try makeStorage()
        let text = " \n한글 'text'\t🙂 "
        let item = makeItem(providers: [NSItemProvider(object: text as NSString)], title: "  공유 제목 \n")

        let result = try await makeService(storage: storage).save(item)

        let clip = try savedClip(result)
        XCTAssertEqual(clip.content, .text(text))
        XCTAssertEqual(clip.name, "공유 제목")
        XCTAssertNil(clip.memo)
        XCTAssertFalse(clip.isPinned)
        let stored = try await storage.fetchAll(order: .createdAt)
        XCTAssertEqual(stored, [clip])
    }

    func testURLProviderIsSavedAsTextClipWithOriginalString() async throws {
        let storage = try makeStorage()
        let original = "https://example.com/a%20b?query=value#section"
        let item = makeItem(providers: [NSItemProvider(object: try XCTUnwrap(URL(string: original)) as NSURL)])

        let result = try await makeService(storage: storage).save(item)

        let clip = try savedClip(result)
        XCTAssertEqual(clip.content, .text(original))
        XCTAssertNil(clip.name)
        XCTAssertTrue(clip.content.isWebLink)
    }

    func testTextItemRegisteredAsObjectIsSavedLikeSafariSelection() async throws {
        let storage = try makeStorage()
        let text = "Safari에서 선택한 텍스트"
        let provider = NSItemProvider(item: text as NSString, typeIdentifier: UTType.plainText.identifier)
        let item = makeItem(providers: [provider])

        let result = try await makeService(storage: storage).save(item)

        XCTAssertEqual(try savedClip(result).content, .text(text))
    }

    func testURLItemRegisteredAsObjectIsSavedAsOriginalString() async throws {
        let storage = try makeStorage()
        let original = "https://example.com/path?query=한글#section"
        let url = try XCTUnwrap(URL(string: original))
        let provider = NSItemProvider(item: url as NSURL, typeIdentifier: UTType.url.identifier)
        let item = makeItem(providers: [provider])

        let result = try await makeService(storage: storage).save(item)

        XCTAssertEqual(try savedClip(result).content, .text(url.absoluteString))
    }

    func testTextIsPreferredWhenProviderOffersTextAndURL() async throws {
        let storage = try makeStorage()
        let provider = NSItemProvider(object: "페이지 제목" as NSString)
        provider.registerObject(try XCTUnwrap(URL(string: "https://example.com")) as NSURL, visibility: .all)
        let item = makeItem(providers: [provider])

        let result = try await makeService(storage: storage).save(item)

        XCTAssertEqual(try savedClip(result).content, .text("페이지 제목"))
    }

    func testOnlyFirstSupportedProviderIsSaved() async throws {
        let storage = try makeStorage()
        let item = makeItem(providers: [
            makeUnsupportedProvider(),
            NSItemProvider(object: "첫 텍스트" as NSString),
            NSItemProvider(object: "둘째 텍스트" as NSString)
        ])

        let result = try await makeService(storage: storage).save(item)

        XCTAssertEqual(try savedClip(result).content, .text("첫 텍스트"))
        let stored = try await storage.fetchAll(order: .createdAt)
        XCTAssertEqual(stored.count, 1)
    }

    func testMissingOrUnsupportedAttachmentsReturnEmptyWithoutRecord() async throws {
        let storage = try makeStorage()
        let service = try makeService(storage: storage)

        let missing = try await service.save(ClipShareItem(item: nil))
        let unsupported = try await service.save(makeItem(providers: [makeUnsupportedProvider()]))

        XCTAssertEqual(missing, .empty)
        XCTAssertEqual(unsupported, .empty)
        let stored = try await storage.fetchAll(order: .createdAt)
        XCTAssertTrue(stored.isEmpty)
    }

    func testWhitespaceOnlyTextReturnsEmptyWithoutRecord() async throws {
        let storage = try makeStorage()
        let item = makeItem(providers: [NSItemProvider(object: " \n\t " as NSString)])

        let result = try await makeService(storage: storage).save(item)

        XCTAssertEqual(result, .empty)
        let stored = try await storage.fetchAll(order: .createdAt)
        XCTAssertTrue(stored.isEmpty)
    }

    func testBlankTitleBecomesNilName() async throws {
        let storage = try makeStorage()
        let item = makeItem(providers: [NSItemProvider(object: "본문" as NSString)], title: " \n ")

        let result = try await makeService(storage: storage).save(item)

        XCTAssertNil(try savedClip(result).name)
    }

    func testLoadFailureReturnsLoadFailedWithoutRecordAndCanBeRetried() async throws {
        let storage = try makeStorage()
        let provider = NSItemProvider()
        provider.registerObject(ofClass: NSString.self, visibility: .all) { completion in
            completion(nil, CocoaError(.fileReadUnknown))
            return nil
        }
        let item = makeItem(providers: [provider])
        let service = try makeService(storage: storage)

        let first = try await service.save(item)
        let second = try await service.save(item)

        XCTAssertEqual(first, .loadFailed)
        XCTAssertEqual(second, .loadFailed)
        let stored = try await storage.fetchAll(order: .createdAt)
        XCTAssertTrue(stored.isEmpty)
    }

    func testStorageFailurePropagatesWithoutRecord() async throws {
        let storage = try makeStorage()
        let spy = ClipboardStorageServiceSpy(
            storage: storage,
            beforeInsert: { throw ClipStorageError.writeFailed }
        )
        let item = makeItem(providers: [NSItemProvider(object: "저장 실패" as NSString)])

        do {
            _ = try await makeService(storage: spy).save(item)
            XCTFail("저장소 오류 전파 누락")
        } catch {
            XCTAssertEqual(error as? ClipStorageError, .writeFailed)
        }

        let stored = try await storage.fetchAll(order: .createdAt)
        XCTAssertTrue(stored.isEmpty)
    }

    func testCancelledTaskThrowsCancellationWithoutRecord() async throws {
        let storage = try makeStorage()
        let item = makeItem(providers: [NSItemProvider(object: "취소 전 텍스트" as NSString)])
        let service = try makeService(storage: storage)

        let task = Task {
            try await service.save(item)
        }
        task.cancel()

        do {
            _ = try await task.value
            XCTFail("취소 전파 누락")
        } catch {
            XCTAssertTrue(error is CancellationError)
        }
        let stored = try await storage.fetchAll(order: .createdAt)
        XCTAssertTrue(stored.isEmpty)
    }

    func testImageProviderIsSavedAsOriginalUntitledImageClip() async throws {
        let storage = try makeStorage()
        let data = try makePNGData()
        let item = makeItem(providers: [makeImageProvider(data: data)], title: "무시되는 제목")

        let result = try await makeService(storage: storage).save(item)

        let clip = try savedClip(result)
        guard case .image(let image) = clip.content else { return XCTFail("이미지 클립 누락") }
        XCTAssertNil(clip.name)
        XCTAssertNil(clip.memo)
        XCTAssertEqual(image.contentType, UTType.png.identifier)
        XCTAssertEqual(image.pixelWidth, 2)
        XCTAssertEqual(image.pixelHeight, 3)
        XCTAssertEqual(image.byteCount, data.count)
        let reopened = try makeStorage()
        let stored = try await reopened.fetchAll(order: .createdAt)
        XCTAssertEqual(stored, [clip])
        let images = ClipImageService(storage: reopened, files: try ClipImageFileStore(rootURL: imagesDirectory))
        let loaded = try await images.loadImage(image)
        XCTAssertEqual(loaded, data)
        XCTAssertEqual(try imageEntryCount(), 1)
    }

    func testImageIsPreferredWhenProviderAlsoOffersURL() async throws {
        let storage = try makeStorage()
        let provider = makeImageProvider(data: try makePNGData())
        provider.registerObject(try XCTUnwrap(URL(string: "https://example.com/image.png")) as NSURL, visibility: .all)
        let item = makeItem(providers: [provider])

        let result = try await makeService(storage: storage).save(item)

        guard case .image = try savedClip(result).content else { return XCTFail("이미지 클립 누락") }
    }

    func testTextProviderBeforeImageProviderIsSavedAsText() async throws {
        let storage = try makeStorage()
        let item = makeItem(providers: [
            NSItemProvider(object: "먼저 온 텍스트" as NSString),
            makeImageProvider(data: try makePNGData())
        ])

        let result = try await makeService(storage: storage).save(item)

        XCTAssertEqual(try savedClip(result).content, .text("먼저 온 텍스트"))
    }

    func testImageLoadFailureReturnsLoadFailedWithoutRecordAndCanBeRetried() async throws {
        let storage = try makeStorage()
        let provider = NSItemProvider()
        provider.registerDataRepresentation(forTypeIdentifier: UTType.png.identifier, visibility: .all) { completion in
            completion(nil, CocoaError(.fileReadUnknown))
            return nil
        }
        let item = makeItem(providers: [provider])
        let service = try makeService(storage: storage)

        let first = try await service.save(item)
        let second = try await service.save(item)

        XCTAssertEqual(first, .loadFailed)
        XCTAssertEqual(second, .loadFailed)
        let stored = try await storage.fetchAll(order: .createdAt)
        XCTAssertTrue(stored.isEmpty)
        XCTAssertEqual(try imageEntryCount(), 0)
    }

    func testUndecodableImageDataThrowsWithoutRecordOrFile() async throws {
        let storage = try makeStorage()
        let item = makeItem(providers: [makeImageProvider(data: Data([0x01, 0x02, 0x03]))])

        do {
            _ = try await makeService(storage: storage).save(item)
            XCTFail("이미지 검증 오류 전파 누락")
        } catch {
            XCTAssertTrue(error is ClipImageFileError)
        }

        let stored = try await storage.fetchAll(order: .createdAt)
        XCTAssertTrue(stored.isEmpty)
        XCTAssertEqual(try imageEntryCount(), 0)
    }

    func testImageStorageFailurePropagatesAndRemovesFile() async throws {
        let storage = try makeStorage()
        let spy = ClipboardStorageServiceSpy(
            storage: storage,
            beforeInsert: { throw ClipStorageError.writeFailed }
        )
        let item = makeItem(providers: [makeImageProvider(data: try makePNGData())])

        do {
            _ = try await makeService(storage: spy).save(item)
            XCTFail("저장소 오류 전파 누락")
        } catch {
            XCTAssertEqual(error as? ClipStorageError, .writeFailed)
        }

        let stored = try await storage.fetchAll(order: .createdAt)
        XCTAssertTrue(stored.isEmpty)
        XCTAssertEqual(try imageEntryCount(), 0)
    }

    func testCancelledImageSaveThrowsCancellationWithoutRecordOrFile() async throws {
        let storage = try makeStorage()
        let item = makeItem(providers: [makeImageProvider(data: try makePNGData())])
        let service = try makeService(storage: storage)

        let task = Task {
            try await service.save(item)
        }
        task.cancel()

        do {
            _ = try await task.value
            XCTFail("취소 전파 누락")
        } catch {
            XCTAssertTrue(error is CancellationError)
        }
        let stored = try await storage.fetchAll(order: .createdAt)
        XCTAssertTrue(stored.isEmpty)
        XCTAssertEqual(try imageEntryCount(), 0)
    }

    private var imagesDirectory: URL { directory.appendingPathComponent("images", isDirectory: true) }

    private func makeStorage() throws -> SQLiteClipStorageService {
        try SQLiteClipStorageService(databaseURL: url)
    }

    private func makeService(storage: any ClipStorageService) throws -> ClipShareService {
        let files = try ClipImageFileStore(rootURL: imagesDirectory)
        let session = ClipImageDownloadURLProtocolStub.makeSession()
        addTeardownBlock { session.invalidateAndCancel() }
        return ClipShareService(
            storage: storage,
            images: ClipImageService(storage: storage, files: files),
            downloads: ClipImageDownloadService(session: session)
        )
    }

    /// 이미지 루트 아래의 항목 수입니다. 저장된 이미지 하나당 디렉터리 하나가 있습니다.
    private func imageEntryCount() throws -> Int {
        try FileManager.default.contentsOfDirectory(atPath: imagesDirectory.path).count
    }

    private func makeUnsupportedProvider() -> NSItemProvider {
        NSItemProvider(item: NSNumber(value: 1), typeIdentifier: UTType.data.identifier)
    }

    private func makeImageProvider(data: Data) -> NSItemProvider {
        let provider = NSItemProvider()
        provider.registerDataRepresentation(forTypeIdentifier: UTType.png.identifier, visibility: .all) { completion in
            completion(data, nil)
            return nil
        }
        return provider
    }

    private func makePNGData() throws -> Data {
        let format = UIGraphicsImageRendererFormat()
        format.scale = 1
        let renderer = UIGraphicsImageRenderer(size: CGSize(width: 2, height: 3), format: format)
        return try XCTUnwrap(renderer.pngData { context in
            UIColor.red.setFill()
            context.fill(CGRect(
                x: 0,
                y: 0,
                width: 2,
                height: 3
            ))
        })
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
