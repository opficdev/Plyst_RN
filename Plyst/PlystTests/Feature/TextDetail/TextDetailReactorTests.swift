//
//  TextDetailReactorTests.swift
//  PlystTests
//
//  Created by opfic on 10/1/26.
//

import Foundation
import ReactorKit
import RxSwift
import XCTest
@testable import Plyst

@MainActor
final class TextDetailReactorTests: XCTestCase {
    private let directory = FileManager.default.temporaryDirectory.appendingPathComponent("Plyst-text-detail-\(UUID())", isDirectory: true)
    private var url: URL { directory.appendingPathComponent("clips.sqlite") }

    override func tearDownWithError() throws {
        if FileManager.default.fileExists(atPath: directory.path) {
            try FileManager.default.removeItem(at: directory)
        }
        try super.tearDownWithError()
    }

    func testSavingWithoutChangesDoesNotWriteOrEmitEvents() async throws {
        let storage = try SQLiteClipStorageService(databaseURL: url)
        let clip = Clip(
            content: .text("원문"),
            name: "이름",
            memo: "메모"
        )
        try await storage.insert(clip)
        let changes = await storage.changes()
        let collector = Task {
            var events = [ClipStorageEvent]()
            for await event in changes { events.append(event) }
            return events
        }
        let reactor = try makeReactor(clip: clip, storage: storage, writer: ClipboardWriterSpy())

        XCTAssertFalse(reactor.currentState.canSave)
        reactor.action.onNext(.save)
        try await Task.sleep(for: .milliseconds(200))

        XCTAssertFalse(reactor.currentState.isSaving)
        XCTAssertNil(reactor.currentState.feedback)
        let stored = try await storage.fetch(id: clip.id)
        XCTAssertEqual(stored, clip)
        collector.cancel()
        let events = await collector.value
        XCTAssertTrue(events.isEmpty)
    }

    func testSavingStoresNameMemoAndPinnedTogetherAndKeepsTheRest() async throws {
        let storage = try SQLiteClipStorageService(databaseURL: url)
        let used = Date(timeIntervalSinceReferenceDate: 500)
        let clip = Clip(
            content: .text("원문"),
            createdAt: Date(timeIntervalSinceReferenceDate: 100),
            lastUsedAt: used
        )
        try await storage.insert(clip)
        let reactor = try makeReactor(clip: clip, storage: storage, writer: ClipboardWriterSpy())

        reactor.action.onNext(.changeName("  새 이름  "))
        reactor.action.onNext(.changeMemo("  메모 본문"))
        reactor.action.onNext(.changePinned(true))
        await waitForState(of: reactor) { $0.canSave }
        reactor.action.onNext(.save)
        await waitForState(of: reactor) { $0.feedback?.isSuccess == true && !$0.canSave }

        let stored = try await storage.fetch(id: clip.id)
        XCTAssertEqual(stored?.name, "새 이름")
        XCTAssertEqual(stored?.memo, "  메모 본문")
        XCTAssertEqual(stored?.isPinned, true)
        XCTAssertEqual(stored?.content, clip.content)
        XCTAssertEqual(stored?.createdAt, clip.createdAt)
        XCTAssertEqual(stored?.lastUsedAt, used)
        XCTAssertEqual(reactor.currentState.draft.name, "새 이름")
    }

    func testBlankNameAndMemoAreStoredAsNil() async throws {
        let storage = try SQLiteClipStorageService(databaseURL: url)
        let clip = Clip(
            content: .text("원문"),
            name: "이름",
            memo: "메모"
        )
        try await storage.insert(clip)
        let reactor = try makeReactor(clip: clip, storage: storage, writer: ClipboardWriterSpy())

        reactor.action.onNext(.changeName("   "))
        reactor.action.onNext(.changeMemo("\n "))
        await waitForState(of: reactor) { $0.canSave }
        reactor.action.onNext(.save)
        await waitForState(of: reactor) { $0.feedback?.isSuccess == true }

        let stored = try await storage.fetch(id: clip.id)
        XCTAssertNil(stored?.name)
        XCTAssertNil(stored?.memo)
    }

    func testDraftThatDiffersOnlyByOuterWhitespaceIsNotAChange() async throws {
        let storage = try SQLiteClipStorageService(databaseURL: url)
        let clip = Clip(content: .text("원문"), name: "이름")
        try await storage.insert(clip)
        let reactor = try makeReactor(clip: clip, storage: storage, writer: ClipboardWriterSpy())

        reactor.action.onNext(.changeName(" 이름 "))
        await waitForState(of: reactor) { $0.draft.name == " 이름 " }

        XCTAssertFalse(reactor.currentState.hasChanges)
        XCTAssertFalse(reactor.currentState.canSave)
    }

    func testUnsavedDraftNeverReachesStorage() async throws {
        let storage = try SQLiteClipStorageService(databaseURL: url)
        let clip = Clip(content: .text("원문"))
        try await storage.insert(clip)
        var reactor: TextDetailReactor? = try makeReactor(clip: clip, storage: storage, writer: ClipboardWriterSpy())

        reactor?.action.onNext(.changeName("저장하지 않은 이름"))
        reactor?.action.onNext(.changePinned(true))
        if let reactor {
            await waitForState(of: reactor) { $0.hasChanges }
        }
        reactor = nil
        try await Task.sleep(for: .milliseconds(200))

        let stored = try await storage.fetch(id: clip.id)
        XCTAssertEqual(stored, clip)
    }

    func testCopyUpdatesLastUsedAtAndKeepsTheDraft() async throws {
        let storage = try SQLiteClipStorageService(databaseURL: url)
        let clip = Clip(content: .text("복사할 원문"))
        try await storage.insert(clip)
        let writer = ClipboardWriterSpy()
        let reactor = try makeReactor(clip: clip, storage: storage, writer: writer)

        reactor.action.onNext(.viewDidLoad)
        reactor.action.onNext(.changeName("편집 중"))
        await waitForState(of: reactor) { $0.draft.name == "편집 중" }
        reactor.action.onNext(.copy)
        await waitForState(of: reactor) { $0.feedback?.isSuccess == true && $0.clip.lastUsedAt != nil }

        XCTAssertEqual(writer.contents, [.text("복사할 원문")])
        let stored = try await storage.fetch(id: clip.id)
        XCTAssertNotNil(stored?.lastUsedAt)
        XCTAssertEqual(reactor.currentState.draft.name, "편집 중")
    }

    func testUnobservedCopyReportsFailure() async throws {
        let storage = try SQLiteClipStorageService(databaseURL: url)
        let clip = Clip(content: .text("원문"))
        try await storage.insert(clip)
        let reactor = try makeReactor(
            clip: clip,
            storage: storage,
            writer: ClipboardWriterSpy(result: .notObserved)
        )

        reactor.action.onNext(.copy)
        await waitForState(of: reactor) { $0.feedback?.isSuccess == false }

        let stored = try await storage.fetch(id: clip.id)
        XCTAssertNil(stored?.lastUsedAt)
    }

    func testDeleteRemovesTheClipFromStorageAndSearchResults() async throws {
        let storage = try SQLiteClipStorageService(databaseURL: url)
        let clip = Clip(content: .text("지울 원문"))
        let other = Clip(content: .text("남을 원문"))
        try await storage.insert(clip)
        try await storage.insert(other)
        let reactor = try makeReactor(clip: clip, storage: storage, writer: ClipboardWriterSpy())

        reactor.action.onNext(.delete)
        await waitForState(of: reactor) { $0.isRemoved }

        let stored = try await storage.fetch(id: clip.id)
        XCTAssertNil(stored)
        let all = try await storage.fetchAll(order: .createdAt)
        XCTAssertEqual(all.map(\.id), [other.id])
        let results = SearchContent.make(
            from: all,
            query: ClipSearchQuery("원문"),
            filter: .all,
            now: Date()
        )
        XCTAssertEqual(results.results.map(\.clip.id), [other.id])
    }

    func testDeletionFromElsewhereClosesTheScreen() async throws {
        let storage = try SQLiteClipStorageService(databaseURL: url)
        let clip = Clip(content: .text("원문"))
        try await storage.insert(clip)
        let reactor = try makeReactor(clip: clip, storage: storage, writer: ClipboardWriterSpy())

        reactor.action.onNext(.viewDidLoad)
        await waitForState(of: reactor) { _ in true }
        try await Task.sleep(for: .milliseconds(100))
        try await storage.delete(id: clip.id)
        await waitForState(of: reactor) { $0.isRemoved }

        XCTAssertTrue(reactor.currentState.isRemoved)
    }

    func testExternalUpdateReplacesAnUntouchedDraftButNotAnEditedOne() async throws {
        let storage = try SQLiteClipStorageService(databaseURL: url)
        let clip = Clip(content: .text("원문"), name: "처음")
        try await storage.insert(clip)
        let reactor = try makeReactor(clip: clip, storage: storage, writer: ClipboardWriterSpy())

        reactor.action.onNext(.viewDidLoad)
        try await Task.sleep(for: .milliseconds(100))
        _ = try await storage.update(id: clip.id, change: .details(name: "바뀜", memo: nil, isPinned: false))
        await waitForState(of: reactor) { $0.clip.name == "바뀜" }
        XCTAssertEqual(reactor.currentState.draft.name, "바뀜")

        reactor.action.onNext(.changeName("내가 입력"))
        await waitForState(of: reactor) { $0.draft.name == "내가 입력" }
        _ = try await storage.update(id: clip.id, change: .details(name: "또 바뀜", memo: nil, isPinned: false))
        await waitForState(of: reactor) { $0.clip.name == "또 바뀜" }
        XCTAssertEqual(reactor.currentState.draft.name, "내가 입력")
    }

    func testTheOriginalTextCannotBeEdited() throws {
        let storage = try SQLiteClipStorageService(databaseURL: url)
        let clip = Clip(content: .text("원문"))
        let reactor = try makeReactor(clip: clip, storage: storage, writer: ClipboardWriterSpy())

        XCTAssertEqual(reactor.currentState.text, "원문")
        XCTAssertEqual(reactor.currentState.characterCount, 2)
        XCTAssertEqual(reactor.currentState.clip.content, clip.content)
    }

    private func makeReactor(
        clip: Clip,
        storage: SQLiteClipStorageService,
        writer: ClipboardWriterSpy
    ) throws -> TextDetailReactor {
        let files = try ClipImageFileStore(rootURL: directory.appendingPathComponent("images", isDirectory: true))
        let images = ClipImageService(storage: storage, files: files)
        let clipboard = ClipboardService(
            storage: storage,
            images: images,
            reader: ClipboardReaderSpy(result: .empty),
            writer: writer
        )
        return TextDetailReactor(
            clip: clip,
            storage: storage,
            clipboard: clipboard
        )
    }

    private func waitForState(
        of reactor: TextDetailReactor,
        where predicate: @escaping (TextDetailReactor.State) -> Bool
    ) async {
        let matched = expectation(description: "State matches the condition")
        matched.assertForOverFulfill = false
        let disposable = reactor.state.subscribe(onNext: { state in
            if predicate(state) { matched.fulfill() }
        })
        await fulfillment(of: [matched], timeout: 2)
        disposable.dispose()
    }
}
