//
//  ClipBridgeAdapterImageTests.swift
//  PlystTests
//
//  Created by opfic on 10/9/26.
//

import Foundation
import PlystBridge
import XCTest
@testable import Plyst

@MainActor
final class ClipBridgeAdapterImageTests: XCTestCase {
    private let directory = FileManager.default.temporaryDirectory.appendingPathComponent("Plyst-bridge-image-\(UUID())")

    override func tearDownWithError() throws {
        if FileManager.default.fileExists(atPath: directory.path) {
            try FileManager.default.removeItem(at: directory)
        }
        try super.tearDownWithError()
    }

    func testPreviewReturnsDerivedFileAndMissingOrTextReturnsNil() async throws {
        let adapter = try makeAdapter(writer: PhotoLibraryWriterSpy())
        let data = try ClipImageTestFixture.data()
        let clip = try await adapter.images.saveImage(data).value
        let uri = try await adapter.getClipImagePreview(id: clip.id)
        let url = try XCTUnwrap(uri.flatMap(URL.init(string:)))
        XCTAssertTrue(url.isFileURL)
        XCTAssertEqual(url.lastPathComponent, "preview")
        XCTAssertFalse(try Data(contentsOf: url).isEmpty)
        let original = try await adapter.images.loadImage(id: clip.id)
        XCTAssertEqual(original, data)
        let missing = try await adapter.getClipImagePreview(id: UUID())
        XCTAssertNil(missing)
        let text = Clip(content: .text("원문"))
        try await adapter.storage.insert(text)
        let nonImage = try await adapter.getClipImagePreview(id: text.id)
        XCTAssertNil(nonImage)
    }

    func testMissingOriginalRejectsOnlyPreview() async throws {
        let adapter = try makeAdapter(writer: PhotoLibraryWriterSpy())
        let clip = try await adapter.images.saveImage(ClipImageTestFixture.data()).value
        guard case .image(let image) = clip.content else { return XCTFail("이미지가 아닙니다.") }
        let original = directory.appendingPathComponent("images").appendingPathComponent(image.fileID.uuidString).appendingPathComponent("original")
        try FileManager.default.removeItem(at: original)
        do {
            _ = try await adapter.getClipImagePreview(id: clip.id)
            XCTFail("없는 파일의 미리보기가 반환됐습니다.")
        } catch {
            guard case ClipBridgeError.imageUnavailable = error else { return XCTFail("예상한 오류가 아닙니다.") }
        }
        let record = try await adapter.clip(id: clip.id)
        XCTAssertNotNil(record)
    }

    func testPhotoSaveMapsPermissionResultsAndPreservesOriginalBytes() async throws {
        let spy = PhotoLibraryWriterSpy()
        let adapter = try makeAdapter(writer: spy)
        let data = try ClipImageTestFixture.data(orientation: 6)
        let clip = try await adapter.images.saveImage(data).value
        spy.authorization = .denied
        let denied = try await adapter.saveClipImageToPhotos(id: clip.id)
        XCTAssertEqual(denied, .denied)
        spy.authorization = .restricted
        let restricted = try await adapter.saveClipImageToPhotos(id: clip.id)
        XCTAssertEqual(restricted, .restricted)
        XCTAssertTrue(spy.writes.isEmpty)
        spy.authorization = .authorized
        let saved = try await adapter.saveClipImageToPhotos(id: clip.id)
        XCTAssertEqual(saved, .saved)
        XCTAssertEqual(spy.writes.first?.data, data)
    }

    func testPhotoSaveMissingClipReturnsNilAndFailureRejects() async throws {
        let spy = PhotoLibraryWriterSpy()
        let adapter = try makeAdapter(writer: spy)
        let missing = try await adapter.saveClipImageToPhotos(id: UUID())
        XCTAssertNil(missing)
        let clip = try await adapter.images.saveImage(ClipImageTestFixture.data()).value
        spy.failsWrite = true
        do {
            _ = try await adapter.saveClipImageToPhotos(id: clip.id)
            XCTFail("사진 쓰기 실패가 전달되지 않았습니다.")
        } catch {
            guard case ClipBridgeError.photoSaveFailed = error else { return XCTFail("예상한 오류가 아닙니다.") }
        }
        XCTAssertTrue(spy.writes.isEmpty)
    }

    private func makeAdapter(writer: PhotoLibraryWriterSpy) throws -> ClipBridgeAdapter {
        let storage = try SQLiteClipStorageService(databaseURL: directory.appendingPathComponent("clips.sqlite"))
        let files = try ClipImageFileStore(rootURL: directory.appendingPathComponent("images"))
        let images = ClipImageService(storage: storage, files: files)
        return ClipBridgeAdapter(
            storage: storage,
            images: images,
            clipboard: ClipboardService(storage: storage, images: images),
            photos: ClipPhotoLibraryService(
                storage: storage,
                images: images,
                writer: writer
            )
        )
    }
}
