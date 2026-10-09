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
            clipboard: clipboard
        )
    }
}
