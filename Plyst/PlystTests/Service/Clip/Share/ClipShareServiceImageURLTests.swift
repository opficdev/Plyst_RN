//
//  ClipShareServiceImageURLTests.swift
//  PlystTests
//
//  Created by opfic on 10/3/26.
//

import Foundation
import UIKit
import UniformTypeIdentifiers
import XCTest
@testable import Plyst

@MainActor
final class ClipShareServiceImageURLTests: XCTestCase {
    private let directory = FileManager.default.temporaryDirectory.appendingPathComponent("Plyst-share-url-\(UUID())", isDirectory: true)
    private var url: URL { directory.appendingPathComponent("ShareInbox.sqlite") }
    private var imagesDirectory: URL { directory.appendingPathComponent("images", isDirectory: true) }

    override func setUp() {
        super.setUp()
        // 이미지 URL이 아닌 공유에서는 요청이 없어야 하므로 요청이 생기면 실패하도록 둡니다.
        ClipImageDownloadURLProtocolStub.reset(.failure(.notConnectedToInternet))
    }

    override func tearDownWithError() throws {
        if FileManager.default.fileExists(atPath: directory.path) {
            try FileManager.default.removeItem(at: directory)
        }
        try super.tearDownWithError()
    }

    func testImageURLIsDownloadedAndSavedAsImageClipWithOriginalURLMemo() async throws {
        let storage = try makeStorage()
        let original = "https://example.com/photo.png"
        let data = try makePNGData()
        stubImageResponse(body: data)

        let result = try await makeService(storage: storage).save(try makeURLItem(original))

        let clip = try savedClip(result)
        guard case .image(let image) = clip.content else { return XCTFail("이미지 클립 누락") }
        XCTAssertNil(clip.name)
        XCTAssertEqual(clip.memo, original)
        XCTAssertEqual(image.pixelWidth, 2)
        XCTAssertEqual(image.pixelHeight, 3)
        XCTAssertEqual(ClipImageDownloadURLProtocolStub.requests, [try XCTUnwrap(URL(string: original))])
        let reopened = try makeStorage()
        let stored = try await reopened.fetchAll(order: .createdAt)
        XCTAssertEqual(stored, [clip])
        let images = ClipImageService(storage: reopened, files: try ClipImageFileStore(rootURL: imagesDirectory))
        let loaded = try await images.loadImage(id: clip.id)
        XCTAssertEqual(loaded, data)
    }

    func testImageExtensionInQueryValueIsDownloadedAndSavedAsImageClip() async throws {
        let storage = try makeStorage()
        let original = "https://search.pstatic.net/common/?src=http%3A%2F%2Fimgnews.naver.net%2Fimage%2Fa.jpg&type=a340"
        stubImageResponse(body: try makePNGData())

        let result = try await makeService(storage: storage).save(try makeURLItem(original))

        let clip = try savedClip(result)
        guard case .image = clip.content else { return XCTFail("이미지 클립 누락") }
        XCTAssertEqual(clip.memo, original)
        XCTAssertEqual(ClipImageDownloadURLProtocolStub.requests, [try XCTUnwrap(URL(string: original))])
    }

    func testQueryValueWithoutImageExtensionMakesNoRequestAndSavesText() async throws {
        let storage = try makeStorage()
        let original = "https://example.com/view?page=2&src=https%3A%2F%2Fexample.com%2Farticle"

        let result = try await makeService(storage: storage).save(try makeURLItem(original))

        try await assertSavedAsText(result, original, storage: storage)
        XCTAssertTrue(ClipImageDownloadURLProtocolStub.requests.isEmpty)
    }

    func testDownloadFailureSavesURLAsTextClip() async throws {
        let storage = try makeStorage()
        let original = "https://example.com/photo.png"
        ClipImageDownloadURLProtocolStub.reset(.failure(.timedOut))

        let result = try await makeService(storage: storage).save(try makeURLItem(original))

        try await assertSavedAsText(result, original, storage: storage)
    }

    func testNonImageResponseSavesURLAsTextClip() async throws {
        let storage = try makeStorage()
        let original = "https://example.com/photo.png"
        stubImageResponse(mimeType: "text/html", body: try makePNGData())

        let result = try await makeService(storage: storage).save(try makeURLItem(original))

        try await assertSavedAsText(result, original, storage: storage)
    }

    func testOversizedResponseSavesURLAsTextClip() async throws {
        let storage = try makeStorage()
        let original = "https://example.com/photo.png"
        stubImageResponse(
            headers: ["Content-Length": "\(21 * 1024 * 1024)"],
            body: try makePNGData()
        )

        let result = try await makeService(storage: storage).save(try makeURLItem(original))

        try await assertSavedAsText(result, original, storage: storage)
    }

    func testUndecodableDownloadedImageSavesURLAsTextClip() async throws {
        let storage = try makeStorage()
        let original = "https://example.com/photo.png"
        stubImageResponse(body: Data([0x01, 0x02, 0x03]))

        let result = try await makeService(storage: storage).save(try makeURLItem(original))

        try await assertSavedAsText(result, original, storage: storage)
    }

    func testPageLinkMakesNoRequestAndSavesText() async throws {
        let storage = try makeStorage()
        let original = "https://example.com/article"

        let result = try await makeService(storage: storage).save(try makeURLItem(original))

        try await assertSavedAsText(result, original, storage: storage)
        XCTAssertTrue(ClipImageDownloadURLProtocolStub.requests.isEmpty)
    }

    func testImageURLWithTextTypeMakesNoRequestAndSavesText() async throws {
        let storage = try makeStorage()
        let original = "https://example.com/photo.png"
        let provider = NSItemProvider(item: original as NSString, typeIdentifier: UTType.plainText.identifier)
        provider.registerObject(try XCTUnwrap(URL(string: original)) as NSURL, visibility: .all)

        let result = try await makeService(storage: storage).save(makeItem(providers: [provider]))

        try await assertSavedAsText(result, original, storage: storage)
        XCTAssertTrue(ClipImageDownloadURLProtocolStub.requests.isEmpty)
    }

    func testCancelledDownloadThrowsCancellationWithoutRecordOrFile() async throws {
        let storage = try makeStorage()
        ClipImageDownloadURLProtocolStub.reset(.stall)
        let item = try makeURLItem("https://example.com/photo.png")
        let service = try makeService(storage: storage)
        let task = Task {
            try await service.save(item)
        }
        for _ in 0..<500 where ClipImageDownloadURLProtocolStub.requests.isEmpty {
            try await Task.sleep(for: .milliseconds(10))
        }
        XCTAssertFalse(ClipImageDownloadURLProtocolStub.requests.isEmpty)

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

    func testDownloadedImageStorageFailurePropagatesAndRemovesFile() async throws {
        let storage = try makeStorage()
        let spy = ClipboardStorageServiceSpy(
            storage: storage,
            beforeInsert: { throw ClipStorageError.writeFailed }
        )
        stubImageResponse(body: try makePNGData())

        do {
            _ = try await makeService(storage: spy).save(try makeURLItem("https://example.com/photo.png"))
            XCTFail("저장소 오류 전파 누락")
        } catch {
            XCTAssertEqual(error as? ClipStorageError, .writeFailed)
        }

        let stored = try await storage.fetchAll(order: .createdAt)
        XCTAssertTrue(stored.isEmpty)
        XCTAssertEqual(try imageEntryCount(), 0)
    }

    private func makeURLItem(_ string: String) throws -> ClipShareItem {
        let url = try XCTUnwrap(URL(string: string))
        return makeItem(providers: [NSItemProvider(item: url as NSURL, typeIdentifier: UTType.url.identifier)])
    }

    private func stubImageResponse(
        mimeType: String = "image/png",
        headers: [String: String] = [:],
        body: Data
    ) {
        ClipImageDownloadURLProtocolStub.reset(.response(
            statusCode: 200,
            headers: headers.merging(["Content-Type": mimeType]) { $1 },
            body: body
        ))
    }

    private func assertSavedAsText(
        _ result: ClipShareSaveResult,
        _ original: String,
        storage: SQLiteClipStorageService
    ) async throws {
        XCTAssertEqual(try savedClip(result).content, .text(original))
        let stored = try await storage.fetchAll(order: .createdAt)
        XCTAssertEqual(stored.count, 1)
        XCTAssertEqual(try imageEntryCount(), 0)
    }

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

    private func makeItem(providers: [NSItemProvider]) -> ClipShareItem {
        let extensionItem = NSExtensionItem()
        extensionItem.attachments = providers
        return ClipShareItem(item: extensionItem)
    }

    private func savedClip(_ result: ClipShareSaveResult) throws -> Clip {
        guard case .saved(let clip) = result else {
            XCTFail("저장 성공 결과 누락")
            throw ClipShareImageURLTestError.unexpectedResult
        }
        return clip
    }
}

private enum ClipShareImageURLTestError: Error {
    case unexpectedResult
}
