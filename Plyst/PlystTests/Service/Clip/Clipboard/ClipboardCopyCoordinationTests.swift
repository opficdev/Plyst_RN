//
//  ClipboardCopyCoordinationTests.swift
//  PlystTests
//
//  Created by opfic on 9/30/26.
//

import Foundation
import XCTest
@testable import Plyst

@MainActor
final class ClipboardCopyCoordinationTests: XCTestCase {
    private let directory = FileManager.default.temporaryDirectory.appendingPathComponent("Plyst-copy-coordination-\(UUID())", isDirectory: true)
    private var url: URL { directory.appendingPathComponent("clips.sqlite") }

    override func tearDownWithError() throws {
        if FileManager.default.fileExists(atPath: directory.path) { try FileManager.default.removeItem(at: directory) }
        try super.tearDownWithError()
    }

    func testCancellationBeforeCopyDoesNotWriteAndDoesNotBlockTheNextCopy() async throws {
        let storage = try SQLiteClipStorageService(databaseURL: url)
        let clip = Clip(content: .text("원문"))
        try await storage.insert(clip)
        let spy = ClipboardStorageServiceSpy(storage: storage)
        let writer = ClipboardWriterSpy()
        let service = try makeService(storage: spy, writer: writer)
        let task = Task {
            withUnsafeCurrentTask { $0?.cancel() }
            return try await service.copy(id: clip.id)
        }

        do {
            _ = try await task.value
            XCTFail("취소된 복사 성공")
        } catch { XCTAssertTrue(error is CancellationError) }

        XCTAssertEqual(writer.contents, [])
        let count = await spy.updateCount
        XCTAssertEqual(count, 0)
        let preserved = try await storage.fetch(id: clip.id)
        XCTAssertEqual(preserved, clip)
        let result = try await service.copy(id: clip.id)
        guard case .copied = result else { return XCTFail("취소 후 다음 복사 결과 누락") }
        XCTAssertEqual(writer.contents, [.text("원문")])
    }

    func testCancellationAfterFetchPreventsClipboardWrite() async throws {
        let storage = try SQLiteClipStorageService(databaseURL: url)
        let clip = Clip(content: .text("원문"))
        try await storage.insert(clip)
        let spy = ClipboardStorageServiceSpy(storage: storage, afterFetch: {
            withUnsafeCurrentTask { $0?.cancel() }
        })
        let writer = ClipboardWriterSpy()
        let service = try makeService(storage: spy, writer: writer)
        let task = Task { try await service.copy(id: clip.id) }

        do {
            _ = try await task.value
            XCTFail("조회 중 취소된 복사 성공")
        } catch { XCTAssertTrue(error is CancellationError) }

        XCTAssertEqual(writer.contents, [])
        let count = await spy.updateCount
        XCTAssertEqual(count, 0)
        let preserved = try await storage.fetch(id: clip.id)
        XCTAssertEqual(preserved, clip)
    }

    func testCancellationAfterObservedWriteReturnsPartialSuccessWithoutRetry() async throws {
        let storage = try SQLiteClipStorageService(databaseURL: url)
        let clip = Clip(content: .text("원문"))
        try await storage.insert(clip)
        let writer = ClipboardWriterSpy(onWrite: { withUnsafeCurrentTask { $0?.cancel() } })
        let service = try makeService(storage: storage, writer: writer)
        let task = Task { try await service.copy(id: clip.id) }

        let result = try await task.value

        guard case let .copiedWithoutLastUsedAt(copied, _, failure) = result else { return XCTFail("쓰기 이후 취소의 부분 성공 결과 누락") }
        XCTAssertTrue(task.isCancelled)
        XCTAssertEqual(copied, clip)
        XCTAssertEqual(failure, .cancelled)
        XCTAssertEqual(writer.contents, [.text("원문")])
        let preserved = try await storage.fetch(id: clip.id)
        XCTAssertEqual(preserved, clip)
    }

    func testCancellationAfterUsageCommitDoesNotHideCommittedSuccess() async throws {
        let storage = try SQLiteClipStorageService(databaseURL: url)
        let clip = Clip(content: .text("원문"))
        try await storage.insert(clip)
        let spy = ClipboardStorageServiceSpy(storage: storage, afterUpdate: {
            withUnsafeCurrentTask { $0?.cancel() }
        })
        let writer = ClipboardWriterSpy()
        let service = try makeService(storage: spy, writer: writer)
        let task = Task { try await service.copy(id: clip.id) }

        let result = try await task.value

        guard case .copied(let copied) = result else { return XCTFail("갱신 확정 후 취소가 복사 성공을 숨김") }
        XCTAssertTrue(task.isCancelled)
        XCTAssertNotNil(copied.lastUsedAt)
        XCTAssertEqual(writer.contents, [.text("원문")])
        let restored = try await storage.fetch(id: clip.id)
        XCTAssertEqual(restored, copied)
    }

    func testConcurrentCopiesWaitUntilPreviousUsageUpdateCompletes() async throws {
        let storage = try SQLiteClipStorageService(databaseURL: url)
        let first = Clip(content: .text("첫 번째"))
        let second = Clip(content: .text("두 번째"))
        try await storage.insert(first)
        try await storage.insert(second)
        let started = expectation(description: "첫 복사의 사용 시각 갱신 대기")
        let gate = ClipboardCopyUpdateGate(entered: started)
        let spy = ClipboardStorageServiceSpy(storage: storage, beforeUpdate: { await gate.wait() })
        let premature = expectation(description: "사용 시각 갱신 전 다음 복사 금지")
        premature.isInverted = true
        var writeCount = 0
        var isWaiting = true
        let writer = ClipboardWriterSpy(onWrite: {
            writeCount += 1
            if isWaiting, writeCount == 2 { premature.fulfill() }
        })
        let service = try makeService(storage: spy, writer: writer)
        let firstTask = Task { try await service.copy(id: first.id) }
        await fulfillment(of: [started], timeout: 2)
        let secondTask = Task { try await service.copy(id: second.id) }
        await fulfillment(of: [premature], timeout: 0.1)
        XCTAssertEqual(writer.contents, [.text("첫 번째")])
        isWaiting = false
        await gate.open()

        let firstResult = try await firstTask.value
        let secondResult = try await secondTask.value

        guard case .copied(let firstCopy) = firstResult, case .copied(let secondCopy) = secondResult else { return XCTFail("순차 복사 성공 결과 누락") }
        XCTAssertEqual(firstCopy.id, first.id)
        XCTAssertEqual(secondCopy.id, second.id)
        XCTAssertNotNil(firstCopy.lastUsedAt)
        XCTAssertNotNil(secondCopy.lastUsedAt)
        XCTAssertEqual(writer.contents, [.text("첫 번째"), .text("두 번째")])
        let updateCount = await spy.updateCount
        XCTAssertEqual(updateCount, 2)
    }

    func testSaveWaitsUntilCopyAndItsUsageUpdateFinish() async throws {
        let storage = try SQLiteClipStorageService(databaseURL: url)
        let clip = Clip(content: .text("복사할 내용"))
        try await storage.insert(clip)
        let started = expectation(description: "복사의 사용 시각 갱신 대기")
        let gate = ClipboardCopyUpdateGate(entered: started)
        let spy = ClipboardStorageServiceSpy(storage: storage, beforeUpdate: { await gate.wait() })
        let premature = expectation(description: "복사가 끝나기 전 저장을 위한 읽기 금지")
        premature.isInverted = true
        var isWaiting = true
        let reader = ClipboardReaderSpy(result: .text("새 기록"), onRead: {
            if isWaiting { premature.fulfill() }
        })
        let writer = ClipboardWriterSpy()
        let images = ClipImageService(
            storage: spy,
            files: try ClipImageFileStore(rootURL: directory.appendingPathComponent("images"))
        )
        let service = ClipboardService(
            storage: spy,
            images: images,
            reader: reader,
            writer: writer
        )
        let copyTask = Task { try await service.copy(id: clip.id) }
        await fulfillment(of: [started], timeout: 2)
        let saveTask = Task { try await service.saveCurrentClipboard() }
        await fulfillment(of: [premature], timeout: 0.1)
        XCTAssertEqual(reader.readCount, 0)
        isWaiting = false
        await gate.open()

        let copyResult = try await copyTask.value
        let saveResult = try await saveTask.value

        guard case .copied(let copied) = copyResult, case .saved(let saved) = saveResult else { return XCTFail("직렬화된 복사와 저장 결과 누락") }
        XCTAssertEqual(copied.id, clip.id)
        XCTAssertNotNil(copied.lastUsedAt)
        XCTAssertEqual(saved.content, .text("새 기록"))
        XCTAssertNil(saved.lastUsedAt)
        XCTAssertNotEqual(saved.id, clip.id)
        XCTAssertEqual(reader.readCount, 1)
        XCTAssertEqual(writer.contents, [.text("복사할 내용")])
    }

    private func makeService(
        storage: any ClipStorageService,
        writer: any ClipboardWriter
    ) throws -> ClipboardService {
        let images = ClipImageService(
            storage: storage,
            files: try ClipImageFileStore(rootURL: directory.appendingPathComponent("images"))
        )
        return ClipboardService(
            storage: storage,
            images: images,
            writer: writer
        )
    }
}

private actor ClipboardCopyUpdateGate {
    private let entered: XCTestExpectation
    private var continuation: CheckedContinuation<Void, Never>?
    private var hasWaited = false

    init(entered: XCTestExpectation) {
        self.entered = entered
    }

    func wait() async {
        guard !hasWaited else { return }
        hasWaited = true
        await withCheckedContinuation {
            continuation = $0
            entered.fulfill()
        }
    }

    func open() {
        continuation?.resume()
        continuation = nil
    }
}
