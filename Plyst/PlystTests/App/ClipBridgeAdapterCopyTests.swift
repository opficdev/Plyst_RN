//
//  ClipBridgeAdapterCopyTests.swift
//  PlystTests
//
//  Created by opfic on 10/9/26.
//

import Foundation
import PlystBridge
import XCTest
@testable import Plyst

@MainActor
final class ClipBridgeAdapterCopyTests: XCTestCase {
    private let directory = FileManager.default.temporaryDirectory.appendingPathComponent("Plyst-bridge-copy-\(UUID())", isDirectory: true)

    override func tearDownWithError() throws {
        if FileManager.default.fileExists(atPath: directory.path) {
            try FileManager.default.removeItem(at: directory)
        }
        try super.tearDownWithError()
    }

    func testCopiedResult() async throws {
        let storage = try makeStorage()
        let clip = Clip(content: .text(" 원문 "))
        try await storage.insert(clip)
        let writer = ClipboardWriterSpy()
        let adapter = try makeAdapter(storage: storage, writer: writer)

        let result = try await adapter.copyClip(id: clip.id)

        XCTAssertEqual(result, .copied)
        XCTAssertEqual(writer.contents, [.text(" 원문 ")])
        let stored = try await storage.fetch(id: clip.id)
        XCTAssertNotNil(stored?.lastUsedAt)
    }

    func testCopiedWithoutLastUsedAtResult() async throws {
        let storage = try makeStorage()
        let clip = Clip(content: .text("원문"))
        try await storage.insert(clip)
        let spy = ClipboardStorageServiceSpy(storage: storage, beforeUpdate: {
            throw ClipStorageError.writeFailed
        })
        let writer = ClipboardWriterSpy()
        let adapter = try makeAdapter(storage: spy, writer: writer)

        let result = try await adapter.copyClip(id: clip.id)

        XCTAssertEqual(result, .copiedWithoutLastUsedAt)
        XCTAssertEqual(writer.contents, [.text("원문")])
        let stored = try await storage.fetch(id: clip.id)
        XCTAssertEqual(stored, clip)
    }

    func testWriteNotObservedResult() async throws {
        let storage = try makeStorage()
        let clip = Clip(content: .text("원문"))
        try await storage.insert(clip)
        let writer = ClipboardWriterSpy(result: .notObserved)
        let adapter = try makeAdapter(storage: storage, writer: writer)

        let result = try await adapter.copyClip(id: clip.id)

        XCTAssertEqual(result, .writeNotObserved)
        XCTAssertEqual(writer.contents, [.text("원문")])
        let stored = try await storage.fetch(id: clip.id)
        XCTAssertEqual(stored, clip)
    }

    func testMissingClipReturnsNil() async throws {
        let writer = ClipboardWriterSpy()
        let adapter = try makeAdapter(storage: makeStorage(), writer: writer)

        let result = try await adapter.copyClip(id: UUID())

        XCTAssertNil(result)
        XCTAssertTrue(writer.contents.isEmpty)
    }

    func testFailureMapsToCopyFailed() async throws {
        let storage = try makeStorage()
        let spy = ClipboardStorageServiceSpy(storage: storage, afterFetch: {
            throw ClipStorageError.corruptedData
        })
        let writer = ClipboardWriterSpy()
        let adapter = try makeAdapter(storage: spy, writer: writer)

        do {
            _ = try await adapter.copyClip(id: UUID())
            XCTFail("실패해야 하는 복사가 성공했습니다.")
        } catch {
            guard case ClipBridgeError.copyFailed = error else {
                return XCTFail("복사 오류가 변환되지 않았습니다: \(error)")
            }
        }
        XCTAssertTrue(writer.contents.isEmpty)
    }

    func testCancellationPropagates() async throws {
        let storage = try makeStorage()
        let spy = ClipboardStorageServiceSpy(storage: storage, afterFetch: {
            throw CancellationError()
        })
        let writer = ClipboardWriterSpy()
        let adapter = try makeAdapter(storage: spy, writer: writer)

        do {
            _ = try await adapter.copyClip(id: UUID())
            XCTFail("취소해야 하는 복사가 성공했습니다.")
        } catch {
            XCTAssertTrue(error is CancellationError)
        }
        XCTAssertTrue(writer.contents.isEmpty)
    }

    private func makeStorage() throws -> SQLiteClipStorageService {
        try SQLiteClipStorageService(databaseURL: directory.appendingPathComponent("clips.sqlite"))
    }

    private func makeAdapter(
        storage: any ClipStorageService,
        writer: any ClipboardWriter
    ) throws -> ClipBridgeAdapter {
        let files = try ClipImageFileStore(rootURL: directory.appendingPathComponent("images", isDirectory: true))
        let images = ClipImageService(storage: storage, files: files)
        let clipboard = ClipboardService(
            storage: storage,
            images: images,
            writer: writer
        )
        return ClipBridgeAdapter(
            storage: storage,
            images: images,
            clipboard: clipboard,
            photos: ClipPhotoLibraryService(storage: storage, images: images)
        )
    }
}

@MainActor
final class ClipBridgeAdapterSaveTests: XCTestCase {
    private let directory = FileManager.default.temporaryDirectory.appendingPathComponent("Plyst-bridge-save-\(UUID())", isDirectory: true)

    override func tearDownWithError() throws {
        if FileManager.default.fileExists(atPath: directory.path) {
            try ClipImageFileSystemTestFixture.restorePermissions(at: directory)
            try FileManager.default.removeItem(at: directory)
        }
        try super.tearDownWithError()
    }

    func testSaveTextAndImage() async throws {
        let storage = try makeStorage()
        let data = try ClipImageTestFixture.data()
        for content in [ClipboardReadResult.text(" 원문 "), .image(data)] {
            let reader = ClipboardReaderSpy(result: content)
            let adapter = try makeAdapter(storage: storage, reader: reader)

            let result = try await adapter.saveCurrentClipboard()

            XCTAssertEqual(result, .saved)
            XCTAssertEqual(reader.readCount, 1)
        }
        let clips = try await storage.fetchAll(order: .createdAt)
        XCTAssertEqual(clips.count, 2)
        XCTAssertTrue(clips.contains { $0.content == .text(" 원문 ") })
        let adapter = try makeAdapter(storage: storage, reader: ClipboardReaderSpy(result: .empty))
        let imageClip = try XCTUnwrap(clips.first {
            if case .image = $0.content { return true }
            return false
        })
        guard case .image(let image) = imageClip.content else { return XCTFail("이미지 클립이 없습니다.") }
        let stored = try await adapter.images.loadImage(image)
        XCTAssertEqual(stored, data)
    }

    func testSaveNonSavingResults() async throws {
        let storage = try makeStorage()
        let cases = [
            (ClipboardReadResult.empty, ClipBridgeClipboardSaveResult.empty),
            (.text("  "), .empty),
            (.unsupported, .unsupported),
            (.accessFailed, .accessFailed),
            (.image(Data()), .invalidImage)
        ]
        for (content, expected) in cases {
            let reader = ClipboardReaderSpy(result: content)
            let adapter = try makeAdapter(storage: storage, reader: reader)
            let result = try await adapter.saveCurrentClipboard()
            XCTAssertEqual(result, expected)
            XCTAssertEqual(reader.readCount, 1)
        }
        let clips = try await storage.fetchAll(order: .createdAt)
        XCTAssertTrue(clips.isEmpty)
    }

    func testSaveFailureMapsToSaveFailed() async throws {
        let storage = try makeStorage()
        let spy = ClipboardStorageServiceSpy(storage: storage, beforeInsert: {
            throw ClipStorageError.writeFailed
        })
        let reader = ClipboardReaderSpy(result: .text("실패한 기록"))
        let adapter = try makeAdapter(storage: spy, reader: reader)

        do {
            _ = try await adapter.saveCurrentClipboard()
            XCTFail("실패해야 하는 저장이 성공했습니다.")
        } catch {
            guard case ClipBridgeError.saveFailed = error else {
                return XCTFail("저장 오류가 변환되지 않았습니다: \(error)")
            }
        }
        let clips = try await storage.fetchAll(order: .createdAt)
        XCTAssertTrue(clips.isEmpty)
    }

    func testSaveCancellationPropagates() async throws {
        let reader = ClipboardReaderSpy(result: .text("취소할 기록"), onRead: {
            throw CancellationError()
        })
        let storage = try makeStorage()
        let adapter = try makeAdapter(storage: storage, reader: reader)

        do {
            _ = try await adapter.saveCurrentClipboard()
            XCTFail("취소해야 하는 저장이 성공했습니다.")
        } catch {
            XCTAssertTrue(error is CancellationError)
        }
        let clips = try await storage.fetchAll(order: .createdAt)
        XCTAssertTrue(clips.isEmpty)
    }

    func testPendingCleanupStillReturnsSaved() async throws {
        let storage = try makeStorage()
        let root = directory.appendingPathComponent("images", isDirectory: true)
        let spy = ClipboardStorageServiceSpy(storage: storage, beforeInsert: {
            let entries = try FileManager.default.contentsOfDirectory(at: root, includingPropertiesForKeys: nil)
            try ClipImageFileSystemTestFixture.makeReadOnly(XCTUnwrap(entries.first))
        })
        let data = try ClipImageTestFixture.data()
        let reader = ClipboardReaderSpy(result: .image(data))
        let adapter = try makeAdapter(storage: spy, reader: reader)

        let result = try await adapter.saveCurrentClipboard()

        XCTAssertEqual(result, .saved)
        let clips = try await storage.fetchAll(order: .createdAt)
        XCTAssertEqual(clips.count, 1)
        guard case .image(let image) = try XCTUnwrap(clips.first).content else {
            return XCTFail("저장된 이미지가 없습니다.")
        }
        let stored = try await adapter.images.loadImage(image)
        XCTAssertEqual(stored, data)
        // 정리 재시도 후에도 저장된 원본이 남아 있는지 확인합니다.
        _ = try await adapter.images.recoverPendingCleanup()
        try ClipImageFileSystemTestFixture.restorePermissions(at: root)
        _ = try await adapter.images.recoverPendingCleanup()
        let retained = try await adapter.images.loadImage(image)
        XCTAssertEqual(retained, data)
    }

    private func makeStorage() throws -> SQLiteClipStorageService {
        try SQLiteClipStorageService(databaseURL: directory.appendingPathComponent("clips.sqlite"))
    }

    private func makeAdapter(
        storage: any ClipStorageService,
        reader: any ClipboardReader
    ) throws -> ClipBridgeAdapter {
        let files = try ClipImageFileStore(rootURL: directory.appendingPathComponent("images", isDirectory: true))
        let images = ClipImageService(storage: storage, files: files)
        return ClipBridgeAdapter(
            storage: storage,
            images: images,
            clipboard: ClipboardService(
                storage: storage,
                images: images,
                reader: reader
            ),
            photos: ClipPhotoLibraryService(storage: storage, images: images)
        )
    }
}
