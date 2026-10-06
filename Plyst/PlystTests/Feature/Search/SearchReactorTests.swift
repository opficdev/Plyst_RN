//
//  SearchReactorTests.swift
//  PlystTests
//
//  Created by opfic on 9/30/26.
//

import Foundation
import ReactorKit
import RxSwift
import SQLiteData
import XCTest
@testable import Plyst

@MainActor
final class SearchReactorTests: XCTestCase {
    private let directory = FileManager.default.temporaryDirectory.appendingPathComponent("Plyst-search-\(UUID())", isDirectory: true)
    private var url: URL { directory.appendingPathComponent("clips.sqlite") }

    override func tearDownWithError() throws {
        if FileManager.default.fileExists(atPath: directory.path) {
            try FileManager.default.removeItem(at: directory)
        }
        try super.tearDownWithError()
    }

    func testQueryChangesFilterResultsAndFollowStorageChanges() async throws {
        let storage = try SQLiteClipStorageService(databaseURL: url)
        let swift = Clip(content: .text("Swift concurrency"), createdAt: Date(timeIntervalSinceReferenceDate: 100))
        let other = Clip(content: .text("Kotlin"), createdAt: Date(timeIntervalSinceReferenceDate: 90))
        try await storage.insert(swift)
        try await storage.insert(other)
        let reactor = try makeReactor(storage: storage, writer: ClipboardWriterSpy())

        reactor.action.onNext(.viewDidLoad)
        await waitForState(of: reactor) { $0.loadPhase == .loaded }
        XCTAssertTrue(reactor.currentState.content.results.isEmpty)

        reactor.action.onNext(.changeQuery("SWIFT"))
        await waitForState(of: reactor) { $0.content.results.map(\.clip.id) == [swift.id] }

        let added = Clip(content: .text("more swift"), createdAt: Date(timeIntervalSinceReferenceDate: 110))
        try await storage.insert(added)
        await waitForState(of: reactor) { $0.content.results.map(\.clip.id) == [added.id, swift.id] }

        try await storage.delete(id: swift.id)
        await waitForState(of: reactor) { $0.content.results.map(\.clip.id) == [added.id] }

        reactor.action.onNext(.changeQuery("   "))
        await waitForState(of: reactor) { $0.content.results.isEmpty }
    }

    func testFilterAndQueryApplyTogether() async throws {
        let storage = try SQLiteClipStorageService(databaseURL: url)
        let plain = Clip(content: .text("report"), createdAt: Date(timeIntervalSinceReferenceDate: 100))
        let pinned = Clip(
            content: .text("report pinned"),
            isPinned: true,
            createdAt: Date(timeIntervalSinceReferenceDate: 90)
        )
        try await storage.insert(plain)
        try await storage.insert(pinned)
        let reactor = try makeReactor(storage: storage, writer: ClipboardWriterSpy())

        reactor.action.onNext(.viewDidLoad)
        reactor.action.onNext(.changeQuery("report"))
        await waitForState(of: reactor) { $0.content.results.count == 2 }

        reactor.action.onNext(.selectFilter(.pinned))
        await waitForState(of: reactor) { $0.content.results.map(\.clip.id) == [pinned.id] }
        XCTAssertEqual(reactor.currentState.query, "report")
    }

    func testRecentTermsAreLoadedRecordedAndRemoved() async throws {
        let storage = try SQLiteClipStorageService(databaseURL: url)
        _ = try await storage.recordSearchTerm(try query("stored"))
        let reactor = try makeReactor(storage: storage, writer: ClipboardWriterSpy())

        reactor.action.onNext(.viewDidLoad)
        await waitForState(of: reactor) { $0.searchHistory.terms == ["stored"] }
        XCTAssertEqual(reactor.currentState.searchHistoryPhase, .loaded)

        reactor.action.onNext(.changeQuery("  fresh "))
        await waitForState(of: reactor) { $0.query == "  fresh " }
        reactor.action.onNext(.submitQuery)
        await waitForState(of: reactor) { $0.searchHistory.terms == ["fresh", "stored"] }

        reactor.action.onNext(.removeRecentTerm("STORED"))
        await waitForState(of: reactor) { $0.searchHistory.terms == ["fresh"] }

        reactor.action.onNext(.clearRecentTerms)
        await waitForState(of: reactor) { $0.searchHistory.terms.isEmpty }
        let stored = try await storage.fetchSearchHistory()
        XCTAssertEqual(stored, ClipSearchHistory())
    }

    func testBlankQueryIsNotRecorded() async throws {
        let storage = try SQLiteClipStorageService(databaseURL: url)
        let reactor = try makeReactor(storage: storage, writer: ClipboardWriterSpy())

        reactor.action.onNext(.viewDidLoad)
        await waitForState(of: reactor) { $0.searchHistoryPhase == .loaded }
        reactor.action.onNext(.changeQuery("   "))
        await waitForState(of: reactor) { $0.query == "   " }
        reactor.action.onNext(.submitQuery)
        try await Task.sleep(for: .milliseconds(200))

        let stored = try await storage.fetchSearchHistory()
        XCTAssertEqual(stored, ClipSearchHistory())
    }

    func testSelectingRecentTermOnlyFillsTheQuery() async throws {
        let storage = try SQLiteClipStorageService(databaseURL: url)
        _ = try await storage.recordSearchTerm(try query("older"))
        _ = try await storage.recordSearchTerm(try query("newer"))
        let reactor = try makeReactor(storage: storage, writer: ClipboardWriterSpy())

        reactor.action.onNext(.viewDidLoad)
        await waitForState(of: reactor) { $0.searchHistory.terms == ["newer", "older"] }
        reactor.action.onNext(.selectRecentTerm("older"))
        await waitForState(of: reactor) { $0.query == "older" }
        try await Task.sleep(for: .milliseconds(200))

        let stored = try await storage.fetchSearchHistory()
        XCTAssertEqual(stored.terms, ["newer", "older"])
    }

    func testRapidHistoryWritesLeaveTheStateEqualToTheStoredHistory() async throws {
        let storage = try SQLiteClipStorageService(databaseURL: url)
        let reactor = try makeReactor(storage: storage, writer: ClipboardWriterSpy())

        reactor.action.onNext(.viewDidLoad)
        for term in ["a", "b", "c", "d"] {
            reactor.action.onNext(.changeQuery(term))
            // submitQuery는 mutate 시점의 State.query를 읽으므로 변경이 반영된 뒤 제출합니다.
            await waitForState(of: reactor) { $0.query == term }
            reactor.action.onNext(.submitQuery)
        }
        reactor.action.onNext(.removeRecentTerm("b"))
        reactor.action.onNext(.removeRecentTerm("c"))
        await waitForState(of: reactor) { $0.searchHistory.terms == ["d", "a"] }

        let stored = try await storage.fetchSearchHistory()
        XCTAssertEqual(reactor.currentState.searchHistory, stored)
    }

    func testCopyWritesTheClipShowsFeedbackAndRecordsTheQuery() async throws {
        let storage = try SQLiteClipStorageService(databaseURL: url)
        let clip = Clip(content: .text("복사할 문장"), createdAt: Date(timeIntervalSinceReferenceDate: 100))
        try await storage.insert(clip)
        let writer = ClipboardWriterSpy()
        let reactor = try makeReactor(storage: storage, writer: writer)

        reactor.action.onNext(.viewDidLoad)
        reactor.action.onNext(.changeQuery("문장"))
        await waitForState(of: reactor) { $0.content.results.map(\.clip.id) == [clip.id] }

        reactor.action.onNext(.copy(clip.id))
        await waitForState(of: reactor) { $0.feedback?.isSuccess == true && $0.searchHistory.terms == ["문장"] }

        XCTAssertEqual(writer.contents, [.text("복사할 문장")])
        let copied = try await storage.fetch(id: clip.id)
        XCTAssertNotNil(copied?.lastUsedAt)
        await waitForState(of: reactor) { $0.content.results.map(\.clip.id) == [clip.id] }
    }

    func testUnobservedCopyReportsFailureAndRecordsNothing() async throws {
        let storage = try SQLiteClipStorageService(databaseURL: url)
        let clip = Clip(content: .text("복사할 문장"))
        try await storage.insert(clip)
        let reactor = try makeReactor(storage: storage, writer: ClipboardWriterSpy(result: .notObserved))

        reactor.action.onNext(.viewDidLoad)
        reactor.action.onNext(.changeQuery("문장"))
        await waitForState(of: reactor) { $0.content.results.count == 1 }
        reactor.action.onNext(.copy(clip.id))
        await waitForState(of: reactor) { $0.feedback?.isSuccess == false }
        try await Task.sleep(for: .milliseconds(200))

        let stored = try await storage.fetchSearchHistory()
        XCTAssertEqual(stored, ClipSearchHistory())
    }

    func testHistoryWriteFailureAfterCopyDoesNotTurnTheCopyIntoAFailure() async throws {
        let storage = try SQLiteClipStorageService(databaseURL: url)
        let clip = Clip(content: .text("복사할 문장"))
        try await storage.insert(clip)
        let writer = ClipboardWriterSpy()
        let reactor = try makeReactor(storage: storage, writer: writer)
        reactor.action.onNext(.viewDidLoad)
        reactor.action.onNext(.changeQuery("문장"))
        await waitForState(of: reactor) { $0.content.results.count == 1 && $0.searchHistoryPhase == .loaded }
        try execute("""
            CREATE TRIGGER rejectInsert BEFORE INSERT ON clipSearchTerms
            BEGIN SELECT RAISE(ABORT, 'Rejected insert'); END
            """)

        reactor.action.onNext(.copy(clip.id))
        await waitForState(of: reactor) { $0.feedback?.isSuccess == true }
        try await Task.sleep(for: .milliseconds(300))

        XCTAssertEqual(writer.contents, [.text("복사할 문장")])
        XCTAssertEqual(reactor.currentState.feedback?.isSuccess, true)
        XCTAssertTrue(reactor.currentState.searchHistory.terms.isEmpty)
    }

    func testFailedUserHistoryWriteShowsFeedbackAndKeepsTheList() async throws {
        let storage = try SQLiteClipStorageService(databaseURL: url)
        _ = try await storage.recordSearchTerm(try query("stored"))
        let reactor = try makeReactor(storage: storage, writer: ClipboardWriterSpy())
        reactor.action.onNext(.viewDidLoad)
        await waitForState(of: reactor) { $0.searchHistory.terms == ["stored"] }
        try execute("""
            CREATE TRIGGER rejectInsert BEFORE INSERT ON clipSearchTerms
            BEGIN SELECT RAISE(ABORT, 'Rejected insert'); END
            """)

        reactor.action.onNext(.changeQuery("fresh"))
        await waitForState(of: reactor) { $0.query == "fresh" }
        reactor.action.onNext(.submitQuery)
        await waitForState(of: reactor) { $0.feedback?.isSuccess == false }

        XCTAssertEqual(reactor.currentState.searchHistory.terms, ["stored"])
    }

    func testCorruptedHistoryIsReportedAndCanBeClearedToRecover() async throws {
        let storage = try SQLiteClipStorageService(databaseURL: url)
        try execute("INSERT INTO clipSearchTerms (position, term) VALUES (0, 'a'), (1, 'A')")
        let reactor = try makeReactor(storage: storage, writer: ClipboardWriterSpy())

        reactor.action.onNext(.viewDidLoad)
        await waitForState(of: reactor) { $0.searchHistoryPhase == .failed }
        reactor.action.onNext(.clearRecentTerms)
        await waitForState(of: reactor) { $0.searchHistoryPhase == .loaded }

        XCTAssertTrue(reactor.currentState.searchHistory.terms.isEmpty)
    }

    func testStateIsDeliveredOnTheMainThread() async throws {
        let storage = try SQLiteClipStorageService(databaseURL: url)
        let reactor = try makeReactor(storage: storage, writer: ClipboardWriterSpy())
        let delivered = expectation(description: "History state is delivered on the main thread")
        delivered.assertForOverFulfill = false
        let disposable = reactor.state.subscribe(onNext: { state in
            if state.searchHistoryPhase == .loaded {
                XCTAssertTrue(Thread.isMainThread)
                delivered.fulfill()
            }
        })

        reactor.action.onNext(.viewDidLoad)
        await fulfillment(of: [delivered], timeout: 2)
        disposable.dispose()
    }

    private func makeReactor(
        storage: SQLiteClipStorageService,
        writer: ClipboardWriterSpy
    ) throws -> SearchReactor {
        let files = try ClipImageFileStore(rootURL: directory.appendingPathComponent("images", isDirectory: true))
        let images = ClipImageService(storage: storage, files: files)
        let clipboard = ClipboardService(
            storage: storage,
            images: images,
            reader: ClipboardReaderSpy(result: .empty),
            writer: writer
        )
        return SearchReactor(
            storage: storage,
            history: storage,
            clipboard: clipboard,
            images: images
        )
    }

    private func query(_ raw: String) throws -> ClipSearchQuery {
        try XCTUnwrap(ClipSearchQuery(raw))
    }

    private func execute(_ sql: String) throws {
        let connection = try DatabaseQueue(path: url.path)
        try connection.write { try $0.execute(sql: sql) }
    }

    private func waitForState(
        of reactor: SearchReactor,
        where predicate: @escaping (SearchReactor.State) -> Bool
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
