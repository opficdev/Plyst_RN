//
//  ClipPhotoLibraryServiceTests.swift
//  PlystTests
//
//  Created by opfic on 10/1/26.
//

import Foundation
import UniformTypeIdentifiers
import XCTest
@testable import Plyst

@MainActor
final class ClipPhotoLibraryServiceTests: XCTestCase {
    private let directory = FileManager.default.temporaryDirectory.appendingPathComponent("Plyst-photos-\(UUID())", isDirectory: true)

    override func tearDownWithError() throws {
        if FileManager.default.fileExists(atPath: directory.path) {
            try FileManager.default.removeItem(at: directory)
        }
        try super.tearDownWithError()
    }

    func testPermissionFailureDoesNotReadMissingOriginalOrWritePhotos() async throws {
        let storage = try makeStorage()
        let files = try ClipImageFileStore(rootURL: directory.appendingPathComponent("images", isDirectory: true))
        let images = ClipImageService(storage: storage, files: files)
        let clip = try await images.saveImage(ClipImageTestFixture.data()).value
        guard case .image(let image) = clip.content else { return XCTFail("이미지 클립 필요") }
        try files.delete(fileID: image.fileID)
        let spy = PhotoLibraryWriterSpy()
        let service = ClipPhotoLibraryService(
            storage: storage,
            images: images,
            writer: spy
        )

        spy.authorization = .denied
        let denied = try await service.save(id: clip.id)
        XCTAssertEqual(denied, .denied)
        spy.authorization = .restricted
        let restricted = try await service.save(id: clip.id)
        XCTAssertEqual(restricted, .restricted)
        XCTAssertEqual(spy.authorizationCount, 2)
        XCTAssertTrue(spy.writes.isEmpty)
    }

    func testSavePassesUnmodifiedAnimatedOriginalAndTypeAndKeepsClip() async throws {
        let storage = try makeStorage()
        let images = try makeImages(storage: storage)
        let data = try ClipImageTestFixture.data(type: UTType.gif.identifier, count: 2)
        let clip = try await images.saveImage(data, name: "움직이는 이미지", memo: "메모", isPinned: true).value
        let spy = PhotoLibraryWriterSpy()
        let service = ClipPhotoLibraryService(
            storage: storage,
            images: images,
            writer: spy
        )

        let result = try await service.save(id: clip.id)

        XCTAssertEqual(result, .saved)
        XCTAssertEqual(spy.writes, [PhotoLibraryWriterSpy.PhotoLibraryWrite(data: data, contentType: UTType.gif.identifier)])
        let stored = try await storage.fetch(id: clip.id)
        guard case .image(let image) = try XCTUnwrap(stored).content else { return XCTFail("이미지 클립 필요") }
        let original = try await images.loadImage(image)
        XCTAssertEqual(stored, clip)
        XCTAssertEqual(original, data)
    }

    func testMissingClipAndNonImageNeverReachWriter() async throws {
        let storage = try makeStorage()
        let images = try makeImages(storage: storage)
        let spy = PhotoLibraryWriterSpy()
        let service = ClipPhotoLibraryService(
            storage: storage,
            images: images,
            writer: spy
        )
        let id = UUID()
        do {
            _ = try await service.save(id: id)
            XCTFail("없는 클립 저장 성공")
        } catch { XCTAssertEqual(error as? ClipStorageError, .notFound(id)) }
        let clip = Clip(content: .text("텍스트"))
        try await storage.insert(clip)
        do {
            _ = try await service.save(id: clip.id)
            XCTFail("텍스트 클립 사진 저장 성공")
        } catch { XCTAssertEqual(error as? ClipImageFileError, .notImage(clip.id)) }
        XCTAssertTrue(spy.writes.isEmpty)
    }

    func testWriteFailurePreservesClipAndOriginal() async throws {
        let storage = try makeStorage()
        let images = try makeImages(storage: storage)
        let data = try ClipImageTestFixture.data()
        let clip = try await images.saveImage(data).value
        let spy = PhotoLibraryWriterSpy()
        spy.failsWrite = true
        let service = ClipPhotoLibraryService(
            storage: storage,
            images: images,
            writer: spy
        )

        do {
            _ = try await service.save(id: clip.id)
            XCTFail("사진 쓰기 실패 누락")
        } catch { XCTAssertTrue(error is PhotoLibraryWriterSpy.Failure) }
        let stored = try await storage.fetch(id: clip.id)
        guard case .image(let image) = try XCTUnwrap(stored).content else { return XCTFail("이미지 클립 필요") }
        let original = try await images.loadImage(image)
        XCTAssertEqual(stored, clip)
        XCTAssertEqual(original, data)
    }

    func testCancellationAfterAuthorizationStopsBeforeReadingOriginal() async throws {
        let storage = try makeStorage()
        let images = try makeImages(storage: storage)
        let spy = PhotoLibraryWriterSpy()
        spy.cancelsAfterAuthorization = true
        let service = ClipPhotoLibraryService(
            storage: storage,
            images: images,
            writer: spy
        )
        let task = Task { try await service.save(id: UUID()) }
        do {
            _ = try await task.value
            XCTFail("권한 승인 뒤 취소 누락")
        } catch { XCTAssertTrue(error is CancellationError) }
        XCTAssertTrue(spy.writes.isEmpty)
    }

    func testConfirmedWriteIsNotReplacedByCancellation() async throws {
        let storage = try makeStorage()
        let images = try makeImages(storage: storage)
        let clip = try await images.saveImage(ClipImageTestFixture.data()).value
        let spy = PhotoLibraryWriterSpy()
        spy.cancelsAfterWrite = true
        let service = ClipPhotoLibraryService(
            storage: storage,
            images: images,
            writer: spy
        )
        let task = Task { try await service.save(id: clip.id) }

        let result = try await task.value

        XCTAssertEqual(result, .saved)
        XCTAssertEqual(spy.writes.count, 1)
    }

    private func makeStorage() throws -> SQLiteClipStorageService {
        try SQLiteClipStorageService(databaseURL: directory.appendingPathComponent("clips.sqlite"))
    }

    private func makeImages(storage: SQLiteClipStorageService) throws -> ClipImageService {
        ClipImageService(
            storage: storage,
            files: try ClipImageFileStore(rootURL: directory.appendingPathComponent("images", isDirectory: true))
        )
    }
}
