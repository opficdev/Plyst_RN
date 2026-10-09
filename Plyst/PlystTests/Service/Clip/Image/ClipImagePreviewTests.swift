//
//  ClipImagePreviewTests.swift
//  PlystTests
//
//  Created by opfic on 10/9/26.
//

import CoreGraphics
import Foundation
import ImageIO
import UniformTypeIdentifiers
import XCTest
@testable import Plyst

final class ClipImagePreviewTests: XCTestCase {
    private let directory = FileManager.default.temporaryDirectory.appendingPathComponent("Plyst-preview-\(UUID())")
    private var root: URL { directory.appendingPathComponent("images") }

    override func tearDownWithError() throws {
        try ClipImageFileSystemTestFixture.restorePermissions(at: directory)
        if FileManager.default.fileExists(atPath: directory.path) {
            try FileManager.default.removeItem(at: directory)
        }
        try super.tearDownWithError()
    }

    func testFileStoreRecreatesOrientedPNGWithoutChangingOriginal() throws {
        let files = try ClipImageFileStore(rootURL: root)
        let data = try ClipImageTestFixture.data(orientation: 6)
        let image = try files.save(data)
        let url = try files.writePreview(image: image, maximumPixelDimension: 1600)
        let source = try XCTUnwrap(CGImageSourceCreateWithURL(url as CFURL, nil))
        let preview = try XCTUnwrap(CGImageSourceCreateImageAtIndex(source, 0, nil))
        XCTAssertEqual(CGImageSourceGetType(source) as String?, UTType.png.identifier)
        XCTAssertEqual(preview.width, 3)
        XCTAssertEqual(preview.height, 2)
        XCTAssertEqual(url, root.appendingPathComponent(image.fileID.uuidString).appendingPathComponent("preview"))
        let expected = try Data(contentsOf: url)
        try Data("손상된 미리보기".utf8).write(to: url)

        let recreated = try files.writePreview(image: image, maximumPixelDimension: 1600)

        XCTAssertEqual(recreated, url)
        XCTAssertEqual(try Data(contentsOf: recreated), expected)
        XCTAssertEqual(try files.load(image: image), data)
        try files.delete(fileID: image.fileID)
        XCTAssertFalse(FileManager.default.fileExists(atPath: url.path))
    }

    func testPreviewRejectsSymlinkAndPreservesTarget() throws {
        let files = try ClipImageFileStore(rootURL: root)
        let image = try files.save(ClipImageTestFixture.data())
        let preview = root.appendingPathComponent(image.fileID.uuidString).appendingPathComponent("preview")
        let target = directory.appendingPathComponent("outside")
        let data = Data("보존할 파일".utf8)
        try data.write(to: target)
        try FileManager.default.createSymbolicLink(at: preview, withDestinationURL: target)

        XCTAssertThrowsError(try files.writePreview(image: image, maximumPixelDimension: 1600)) {
            XCTAssertEqual($0 as? ClipImageFileError, .unsafePath)
        }
        XCTAssertEqual(try Data(contentsOf: target), data)
    }

    func testPreviewRejectsDirectoryDestination() throws {
        let files = try ClipImageFileStore(rootURL: root)
        let image = try files.save(ClipImageTestFixture.data())
        let preview = root.appendingPathComponent(image.fileID.uuidString).appendingPathComponent("preview")
        try FileManager.default.createDirectory(at: preview, withIntermediateDirectories: false)
        XCTAssertThrowsError(try files.writePreview(image: image, maximumPixelDimension: 1600)) {
            XCTAssertEqual($0 as? ClipImageFileError, .unsafePath)
        }
    }

    func testPreviewRejectsMissingOriginalEvenWhenPreviewExists() throws {
        let files = try ClipImageFileStore(rootURL: root)
        let image = try files.save(ClipImageTestFixture.data())
        let preview = try files.writePreview(image: image, maximumPixelDimension: 1600)
        try FileManager.default.removeItem(at: preview.deletingLastPathComponent().appendingPathComponent("original"))
        XCTAssertThrowsError(try files.writePreview(image: image, maximumPixelDimension: 1600)) {
            XCTAssertEqual($0 as? ClipImageFileError, .notFound(image.fileID))
        }
    }

    func testServiceLimitsPreviewTo1600PixelsAndDeletesDerivedFile() async throws {
        let storage = try SQLiteClipStorageService(databaseURL: directory.appendingPathComponent("clips.sqlite"))
        let files = try ClipImageFileStore(rootURL: root)
        let service = ClipImageService(storage: storage, files: files)
        let data = try largeImage()
        let clip = try await service.saveImage(data).value
        guard case .image(let image) = clip.content else { return XCTFail("이미지가 아닙니다.") }

        let url = try await service.makePreviewFileURL(image)
        let source = try XCTUnwrap(CGImageSourceCreateWithURL(url as CFURL, nil))
        let preview = try XCTUnwrap(CGImageSourceCreateImageAtIndex(source, 0, nil))
        XCTAssertEqual(preview.width, 1600)
        XCTAssertEqual(preview.height, 800)
        XCTAssertEqual(try files.load(image: image), data)
        try Data().write(to: url)
        let recreated = try await service.makePreviewFileURL(image)
        XCTAssertFalse(try Data(contentsOf: recreated).isEmpty)

        _ = try await service.delete(id: clip.id)

        XCTAssertFalse(FileManager.default.fileExists(atPath: url.path))
        do {
            _ = try await service.makePreviewFileURL(image)
            XCTFail("삭제한 원본의 미리보기가 생성됐습니다.")
        } catch {
            XCTAssertEqual(error as? ClipImageFileError, .notFound(image.fileID))
        }
    }

    func testCancelledPreviewDoesNotCreateFile() async throws {
        let files = try ClipImageFileStore(rootURL: root)
        let image = try files.save(ClipImageTestFixture.data())
        let task = Task {
            withUnsafeCurrentTask { $0?.cancel() }
            return try files.writePreview(image: image, maximumPixelDimension: 1600)
        }
        do {
            _ = try await task.value
            XCTFail("취소된 미리보기가 생성됐습니다.")
        } catch {
            XCTAssertTrue(error is CancellationError)
        }
        let preview = root.appendingPathComponent(image.fileID.uuidString).appendingPathComponent("preview")
        XCTAssertFalse(FileManager.default.fileExists(atPath: preview.path))
    }

    func testPreviewWaitsForDeletionBeforeReadingOriginal() async throws {
        let storage = try SQLiteClipStorageService(databaseURL: directory.appendingPathComponent("clips.sqlite"))
        let started = expectation(description: "삭제 조회 시작")
        let gate = ClipImagePreviewGate()
        let stub = ClipImagePreviewStorageServiceStub(
            storage: storage,
            beforeFetch: { await gate.wait(started: started) }
        )
        let files = try ClipImageFileStore(rootURL: root)
        let service = ClipImageService(storage: stub, files: files)
        let clip = try await service.saveImage(ClipImageTestFixture.data()).value
        guard case .image(let image) = clip.content else { return XCTFail("이미지가 아닙니다.") }
        let deletion = Task { try await service.delete(id: clip.id) }
        await fulfillment(of: [started], timeout: 2)
        let written = expectation(description: "삭제 대기 중 미리보기 쓰기 금지")
        written.isInverted = true
        let preview = Task {
            do {
                let url = try await service.makePreviewFileURL(image)
                written.fulfill()
                return Result<URL, Error>.success(url)
            } catch {
                return Result<URL, Error>.failure(error)
            }
        }
        await fulfillment(of: [written], timeout: 0.1)
        await gate.resume()
        _ = try await deletion.value
        let result = await preview.value
        XCTAssertThrowsError(try result.get()) {
            XCTAssertEqual($0 as? ClipImageFileError, .notFound(image.fileID))
        }
    }

    func testUnwritablePreviewPreservesOriginal() throws {
        let files = try ClipImageFileStore(rootURL: root)
        let data = try ClipImageTestFixture.data()
        let image = try files.save(data)
        try ClipImageFileSystemTestFixture.makeReadOnly(root.appendingPathComponent(image.fileID.uuidString))
        XCTAssertThrowsError(try files.writePreview(image: image, maximumPixelDimension: 1600)) {
            XCTAssertEqual($0 as? ClipImageFileError, .writeFailed)
        }
        XCTAssertEqual(try files.load(image: image), data)
    }

    private func largeImage() throws -> Data {
        let context = try XCTUnwrap(CGContext(
            data: nil,
            width: 3200,
            height: 1600,
            bitsPerComponent: 8,
            bytesPerRow: 0,
            space: CGColorSpaceCreateDeviceRGB(),
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        ))
        let image = try XCTUnwrap(context.makeImage())
        let data = NSMutableData()
        let destination = try XCTUnwrap(CGImageDestinationCreateWithData(data as CFMutableData, UTType.png.identifier as CFString, 1, nil))
        CGImageDestinationAddImage(destination, image, nil)
        XCTAssertTrue(CGImageDestinationFinalize(destination))
        return data as Data
    }
}

private struct ClipImagePreviewStorageServiceStub: ClipStorageService {
    let storage: SQLiteClipStorageService
    let beforeFetch: @Sendable () async -> Void

    func fetchAll(order: ClipSortOrder) async throws -> [Clip] {
        try await storage.fetchAll(order: order)
    }

    func fetch(id: Clip.ID) async throws -> Clip? {
        await beforeFetch()
        return try await storage.fetch(id: id)
    }

    func insert(_ clip: Clip) async throws {
        try await storage.insert(clip)
    }

    func update(
        id: Clip.ID,
        change: ClipUpdate
    ) async throws -> Clip {
        try await storage.update(id: id, change: change)
    }

    func delete(id: Clip.ID) async throws {
        try await storage.delete(id: id)
    }

    func changes() async -> AsyncStream<ClipStorageEvent> {
        await storage.changes()
    }
}

private actor ClipImagePreviewGate {
    private var continuation: CheckedContinuation<Void, Never>?

    func wait(started: XCTestExpectation) async {
        await withCheckedContinuation {
            continuation = $0
            started.fulfill()
        }
    }

    func resume() {
        continuation?.resume()
        continuation = nil
    }
}
