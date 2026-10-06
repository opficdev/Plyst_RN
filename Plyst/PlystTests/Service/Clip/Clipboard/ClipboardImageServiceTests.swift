//
//  ClipboardImageServiceTests.swift
//  PlystTests
//
//  Created by opfic on 9/29/26.
//

import Foundation
import UniformTypeIdentifiers
import XCTest
@testable import Plyst

@MainActor
final class ClipboardImageServiceTests: XCTestCase {
    private let directory = FileManager.default.temporaryDirectory.appendingPathComponent("Plyst-clipboard-image-\(UUID())", isDirectory: true)
    private var url: URL { directory.appendingPathComponent("clips.sqlite") }
    private var root: URL { directory.appendingPathComponent("images", isDirectory: true) }

    override func tearDownWithError() throws {
        try ClipImageFileSystemTestFixture.restorePermissions(at: directory)
        if FileManager.default.fileExists(atPath: directory.path) { try FileManager.default.removeItem(at: directory) }
        try super.tearDownWithError()
    }

    func testSavedImagePreservesBytesMetadataAndDefaultsAsLatestRecord() async throws {
        let storage = try SQLiteClipStorageService(databaseURL: url)
        let previous = Clip(content: .text("이전 기록"), createdAt: Date(timeIntervalSinceReferenceDate: 100))
        try await storage.insert(previous)
        let stream = await storage.changes()
        let data = try ClipImageTestFixture.data(type: UTType.jpeg.identifier, orientation: 6)
        let reader = ClipboardReaderSpy(result: .image(data))
        let service = try makeService(storage: storage, reader: reader)

        let clip = try savedClip(await service.saveCurrentClipboard())

        let image = try metadata(in: clip)
        XCTAssertEqual(image.contentType, UTType.jpeg.identifier)
        XCTAssertEqual(image.pixelWidth, 2)
        XCTAssertEqual(image.pixelHeight, 3)
        XCTAssertEqual(image.byteCount, data.count)
        XCTAssertNil(clip.name)
        XCTAssertNil(clip.memo)
        XCTAssertFalse(clip.isPinned)
        XCTAssertNil(clip.lastUsedAt)
        XCTAssertEqual(reader.readCount, 1)
        let stored = try await storage.fetchAll(order: .createdAt)
        XCTAssertEqual(stored, [clip, previous])
        let reopened = try SQLiteClipStorageService(databaseURL: url)
        let restored = try await reopened.fetch(id: clip.id)
        XCTAssertEqual(restored, clip)
        let files = try ClipImageFileStore(rootURL: root)
        XCTAssertEqual(try files.load(fileID: image.fileID), data)
        XCTAssertEqual(try files.pendingFileIDs(), [])
        await assertEvents(stream, expected: [.inserted(clip)])
    }

    func testExplicitImageRequestsCreateSeparateClipsAndOriginals() async throws {
        let storage = try SQLiteClipStorageService(databaseURL: url)
        let stream = await storage.changes()
        let data = try ClipImageTestFixture.data(type: UTType.gif.identifier, count: 2)
        let reader = ClipboardReaderSpy(result: .image(data))
        let service = try makeService(storage: storage, reader: reader)
        XCTAssertEqual(reader.readCount, 0)

        let first = try savedClip(await service.saveCurrentClipboard())
        let second = try savedClip(await service.saveCurrentClipboard())

        let firstImage = try metadata(in: first)
        let secondImage = try metadata(in: second)
        XCTAssertNotEqual(first.id, second.id)
        XCTAssertNotEqual(firstImage.fileID, secondImage.fileID)
        XCTAssertEqual(reader.readCount, 2)
        let files = try ClipImageFileStore(rootURL: root)
        XCTAssertEqual(try files.load(fileID: firstImage.fileID), data)
        XCTAssertEqual(try files.load(fileID: secondImage.fileID), data)
        let stored = try await storage.fetchAll(order: .createdAt)
        XCTAssertEqual(Set(stored.map(\.id)), Set([first.id, second.id]))
        await assertEvents(stream, expected: [.inserted(first), .inserted(second)])
    }

    func testInvalidImagesDoNotInsertWriteOrPublish() async throws {
        let storage = try SQLiteClipStorageService(databaseURL: url)
        let previous = Clip(content: .text("기존 기록"))
        try await storage.insert(previous)
        let stream = await storage.changes()
        let spy = ClipboardStorageServiceSpy(storage: storage)
        let reader = ClipboardReaderSpy(result: .image(Data()))
        let service = try makeService(storage: spy, reader: reader)
        let png = try ClipImageTestFixture.data()
        let gif = try ClipImageTestFixture.data(type: UTType.gif.identifier, count: 2)
        let inputs = [Data(), Data("손상된 이미지".utf8), Data("<svg></svg>".utf8), Data(png.prefix(png.count / 2)), Data(gif.dropLast(8))]

        for data in inputs {
            reader.result = .image(data)
            let result = try await service.saveCurrentClipboard()
            XCTAssertEqual(result, .invalidImage)
        }

        let insertCount = await spy.insertCount
        XCTAssertEqual(insertCount, 0)
        XCTAssertEqual(reader.readCount, inputs.count)
        let stored = try await storage.fetchAll(order: .createdAt)
        XCTAssertEqual(stored, [previous])
        XCTAssertEqual(try FileManager.default.contentsOfDirectory(atPath: root.path), [])
        try await assertNoImageEvents(stream, storage: storage)
    }

    func testFileWriteFailureDoesNotInsertOrPublish() async throws {
        let storage = try SQLiteClipStorageService(databaseURL: url)
        let stream = await storage.changes()
        let spy = ClipboardStorageServiceSpy(storage: storage)
        let reader = ClipboardReaderSpy(result: .image(try ClipImageTestFixture.data()))
        let service = try makeService(storage: spy, reader: reader)
        try ClipImageFileSystemTestFixture.makeReadOnly(root)

        do {
            _ = try await service.saveCurrentClipboard()
            XCTFail("쓰기 권한이 없는 경로에서 이미지 저장 성공")
        } catch { XCTAssertEqual(error as? ClipImageFileError, .writeFailed) }

        let insertCount = await spy.insertCount
        XCTAssertEqual(insertCount, 0)
        let stored = try await storage.fetchAll(order: .createdAt)
        XCTAssertEqual(stored, [])
        XCTAssertEqual(try FileManager.default.contentsOfDirectory(atPath: root.path), [])
        try ClipImageFileSystemTestFixture.restorePermissions(at: root)
        try await assertNoImageEvents(stream, storage: storage)
    }

    func testFailedMetadataInsertCleansOriginalAndPreservesRecordsAndEvents() async throws {
        let storage = try SQLiteClipStorageService(databaseURL: url)
        let previous = Clip(content: .text("기존 기록"))
        try await storage.insert(previous)
        let stream = await storage.changes()
        let spy = ClipboardStorageServiceSpy(storage: storage, beforeInsert: { throw ClipStorageError.writeFailed })
        let reader = ClipboardReaderSpy(result: .image(try ClipImageTestFixture.data()))
        let service = try makeService(storage: spy, reader: reader)

        do {
            _ = try await service.saveCurrentClipboard()
            XCTFail("실패하도록 설정한 메타데이터 저장 성공")
        } catch { XCTAssertEqual(error as? ClipStorageError, .writeFailed) }

        let insertCount = await spy.insertCount
        XCTAssertEqual(insertCount, 1)
        let stored = try await storage.fetchAll(order: .createdAt)
        XCTAssertEqual(stored, [previous])
        XCTAssertEqual(try FileManager.default.contentsOfDirectory(atPath: root.path), [])
        try await assertNoImageEvents(stream, storage: storage)
    }

    func testFailedCompensationPreservesStorageErrorAndRecoverableOriginal() async throws {
        let storage = try SQLiteClipStorageService(databaseURL: url)
        let stream = await storage.changes()
        let root = self.root
        let spy = ClipboardStorageServiceSpy(storage: storage, beforeInsert: {
            let entries = try FileManager.default.contentsOfDirectory(at: root, includingPropertiesForKeys: nil)
            try ClipImageFileSystemTestFixture.makeReadOnly(XCTUnwrap(entries.first))
            throw ClipStorageError.writeFailed
        })
        let files = try ClipImageFileStore(rootURL: root)
        let images = ClipImageService(storage: spy, files: files)
        let data = try ClipImageTestFixture.data()
        let reader = ClipboardReaderSpy(result: .image(data))
        let service = ClipboardService(
            storage: spy,
            images: images,
            reader: reader
        )

        do {
            _ = try await service.saveCurrentClipboard()
            XCTFail("실패하도록 설정한 이미지 저장 성공")
        } catch {
            if error is XCTSkip { throw error }
            XCTAssertEqual(error as? ClipStorageError, .writeFailed)
        }

        let candidates = try files.pendingFileIDs()
        XCTAssertEqual(candidates.count, 1)
        XCTAssertEqual(try files.load(fileID: XCTUnwrap(candidates.first)), data)
        let stored = try await storage.fetchAll(order: .createdAt)
        XCTAssertEqual(stored, [])
        try ClipImageFileSystemTestFixture.restorePermissions(at: root)
        let pending = try await images.recoverPendingCleanup()
        XCTAssertEqual(pending, [])
        XCTAssertEqual(try FileManager.default.contentsOfDirectory(atPath: root.path), [])
        try await assertNoImageEvents(stream, storage: storage)
    }

    func testCommittedSaveReportsPendingCleanupAndRecoveryPreservesOriginal() async throws {
        let storage = try SQLiteClipStorageService(databaseURL: url)
        let stream = await storage.changes()
        let root = self.root
        let spy = ClipboardStorageServiceSpy(storage: storage, beforeInsert: {
            let entries = try FileManager.default.contentsOfDirectory(at: root, includingPropertiesForKeys: nil)
            try ClipImageFileSystemTestFixture.makeReadOnly(XCTUnwrap(entries.first))
        })
        let files = try ClipImageFileStore(rootURL: root)
        let images = ClipImageService(storage: spy, files: files)
        let data = try ClipImageTestFixture.data()
        let reader = ClipboardReaderSpy(result: .image(data))
        let service = ClipboardService(
            storage: spy,
            images: images,
            reader: reader
        )

        let result = try await service.saveCurrentClipboard()

        guard case .savedWithPendingCleanup(let clip, let fileID) = result else {
            XCTFail("확정된 저장의 정리 대기 결과 누락")
            return
        }
        XCTAssertEqual(try metadata(in: clip).fileID, fileID)
        let stored = try await storage.fetchAll(order: .createdAt)
        XCTAssertEqual(stored, [clip])
        XCTAssertEqual(try files.load(fileID: fileID), data)
        XCTAssertEqual(try files.pendingFileIDs(), [fileID])
        try ClipImageFileSystemTestFixture.restorePermissions(at: root)
        let pending = try await images.recoverPendingCleanup()
        XCTAssertEqual(pending, [])
        XCTAssertEqual(try files.pendingFileIDs(), [])
        XCTAssertEqual(try files.load(fileID: fileID), data)
        let recovered = try await storage.fetchAll(order: .createdAt)
        XCTAssertEqual(recovered, [clip])
        await assertEvents(stream, expected: [.inserted(clip)])
    }

    func testCancellationBeforeReadingDoesNotCreateAnImage() async throws {
        let storage = try SQLiteClipStorageService(databaseURL: url)
        let stream = await storage.changes()
        let reader = ClipboardReaderSpy(result: .image(try ClipImageTestFixture.data()))
        let service = try makeService(storage: storage, reader: reader)
        let task = Task {
            withUnsafeCurrentTask { $0?.cancel() }
            return try await service.saveCurrentClipboard()
        }

        do {
            _ = try await task.value
            XCTFail("취소된 이미지 저장 성공")
        } catch { XCTAssertTrue(error is CancellationError) }

        XCTAssertEqual(reader.readCount, 0)
        let stored = try await storage.fetchAll(order: .createdAt)
        XCTAssertEqual(stored, [])
        XCTAssertEqual(try FileManager.default.contentsOfDirectory(atPath: root.path), [])
        try await assertNoImageEvents(stream, storage: storage)
    }

    func testCancellationDuringReadingDoesNotCreateAnImage() async throws {
        let storage = try SQLiteClipStorageService(databaseURL: url)
        let stream = await storage.changes()
        let reader = ClipboardReaderSpy(result: .image(try ClipImageTestFixture.data()), onRead: {
            withUnsafeCurrentTask { $0?.cancel() }
        })
        let service = try makeService(storage: storage, reader: reader)
        let task = Task { try await service.saveCurrentClipboard() }

        do {
            _ = try await task.value
            XCTFail("읽는 동안 취소된 이미지 저장 성공")
        } catch { XCTAssertTrue(error is CancellationError) }

        XCTAssertEqual(reader.readCount, 1)
        let stored = try await storage.fetchAll(order: .createdAt)
        XCTAssertEqual(stored, [])
        XCTAssertEqual(try FileManager.default.contentsOfDirectory(atPath: root.path), [])
        try await assertNoImageEvents(stream, storage: storage)
    }

    func testMetadataCancellationCleansOriginalWithoutPublishing() async throws {
        let storage = try SQLiteClipStorageService(databaseURL: url)
        let stream = await storage.changes()
        let spy = ClipboardStorageServiceSpy(storage: storage, beforeInsert: { throw CancellationError() })
        let reader = ClipboardReaderSpy(result: .image(try ClipImageTestFixture.data()))
        let service = try makeService(storage: spy, reader: reader)

        do {
            _ = try await service.saveCurrentClipboard()
            XCTFail("메타데이터 저장 중 취소된 이미지 저장 성공")
        } catch { XCTAssertTrue(error is CancellationError) }

        let insertCount = await spy.insertCount
        XCTAssertEqual(insertCount, 1)
        let stored = try await storage.fetchAll(order: .createdAt)
        XCTAssertEqual(stored, [])
        XCTAssertEqual(try FileManager.default.contentsOfDirectory(atPath: root.path), [])
        try await assertNoImageEvents(stream, storage: storage)
    }

    func testCancellationAfterCommitReturnsSavedImage() async throws {
        let storage = try SQLiteClipStorageService(databaseURL: url)
        let stream = await storage.changes()
        let spy = ClipboardStorageServiceSpy(storage: storage, afterInsert: {
            withUnsafeCurrentTask { $0?.cancel() }
        })
        let data = try ClipImageTestFixture.data()
        let reader = ClipboardReaderSpy(result: .image(data))
        let service = try makeService(storage: spy, reader: reader)
        let task = Task { try await service.saveCurrentClipboard() }

        let clip = try savedClip(await task.value)

        XCTAssertTrue(task.isCancelled)
        let restored = try await storage.fetch(id: clip.id)
        XCTAssertEqual(restored, clip)
        let files = try ClipImageFileStore(rootURL: root)
        XCTAssertEqual(try files.load(fileID: metadata(in: clip).fileID), data)
        XCTAssertEqual(try files.pendingFileIDs(), [])
        await assertEvents(stream, expected: [.inserted(clip)])
    }

    private func makeService(
        storage: any ClipStorageService,
        reader: any ClipboardReader
    ) throws -> ClipboardService {
        let files = try ClipImageFileStore(rootURL: root)
        let images = ClipImageService(storage: storage, files: files)
        return ClipboardService(
            storage: storage,
            images: images,
            reader: reader
        )
    }

    private func savedClip(_ result: ClipboardSaveResult) throws -> Clip {
        guard case .saved(let clip) = result else {
            XCTFail("이미지 저장 성공 결과 누락")
            throw ClipStorageError.invalidContent
        }
        return clip
    }

    private func metadata(in clip: Clip) throws -> ClipImageMetadata {
        guard case .image(let image) = clip.content else { throw ClipImageFileError.notImage(clip.id) }
        return image
    }

    private func assertNoImageEvents(
        _ stream: AsyncStream<ClipStorageEvent>,
        storage: any ClipStorageService
    ) async throws {
        let sentinel = Clip(content: .text("검증"))
        try await storage.insert(sentinel)
        await assertEvents(stream, expected: [.inserted(sentinel)])
    }

    private func assertEvents(
        _ stream: AsyncStream<ClipStorageEvent>,
        expected: [ClipStorageEvent]
    ) async {
        let received = expectation(description: "이미지 저장 확정 이후의 이벤트만 전달")
        let task = Task {
            var iterator = stream.makeAsyncIterator()
            for event in expected {
                let actual = await iterator.next()
                XCTAssertEqual(actual, event)
            }
            received.fulfill()
        }
        await fulfillment(of: [received], timeout: 2)
        task.cancel()
        await task.value
    }
}
