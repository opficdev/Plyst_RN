//
//  HomeReactorQuickActionTests.swift
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
final class HomeReactorQuickActionTests: XCTestCase {
    private let directory = FileManager.default.temporaryDirectory.appendingPathComponent("Plyst-home-quick-\(UUID())", isDirectory: true)

    override func tearDownWithError() throws {
        if FileManager.default.fileExists(atPath: directory.path) {
            try FileManager.default.removeItem(at: directory)
        }
        try super.tearDownWithError()
    }

    func testCopyWritesClipTextAndShowsSuccessFeedbackWithoutReorderingList() async throws {
        let storage = try SQLiteClipStorageService(databaseURL: directory.appendingPathComponent("clips.sqlite"))
        let older = Clip(
            content: .text("먼저 저장"),
            createdAt: Date(timeIntervalSinceReferenceDate: 100)
        )
        let newer = Clip(
            content: .text("나중에 저장"),
            createdAt: Date(timeIntervalSinceReferenceDate: 200)
        )
        try await storage.insert(older)
        try await storage.insert(newer)
        let writer = ClipboardWriterSpy()
        let reactor = try makeReactor(storage: storage, writer: writer)
        reactor.action.onNext(.viewDidLoad)
        await waitForState(of: reactor) { $0.clips.count == 2 }
        let order = reactor.currentState.clips.map(\.id)

        reactor.action.onNext(.copy(older.id))
        await waitForState(of: reactor) { $0.feedback?.isSuccess == true }

        XCTAssertEqual(writer.contents, [.text("먼저 저장")])
        XCTAssertEqual(reactor.currentState.feedback?.message, "클립보드에 복사했습니다")
        await waitForState(of: reactor) { $0.clips.first(where: { $0.id == older.id })?.lastUsedAt != nil }
        XCTAssertEqual(reactor.currentState.clips.map(\.id), order)
    }

    func testCopyShowsFailureFeedbackWhenWriteIsNotObserved() async throws {
        let storage = try SQLiteClipStorageService(databaseURL: directory.appendingPathComponent("clips.sqlite"))
        let clip = Clip(content: .text("원문"))
        try await storage.insert(clip)
        let reactor = try makeReactor(storage: storage, writer: ClipboardWriterSpy(result: .notObserved))
        reactor.action.onNext(.viewDidLoad)
        await waitForState(of: reactor) { $0.clips.count == 1 }

        reactor.action.onNext(.copy(clip.id))
        await waitForState(of: reactor) { $0.feedback?.isSuccess == false }

        XCTAssertEqual(reactor.currentState.feedback?.message, "클립보드에 복사하지 못했습니다")
        let stored = try await storage.fetch(id: clip.id)
        XCTAssertNil(stored?.lastUsedAt)
    }

    func testDeletingTextClipRemovesItFromListAndStorage() async throws {
        let storage = try SQLiteClipStorageService(databaseURL: directory.appendingPathComponent("clips.sqlite"))
        let clip = Clip(content: .text("지울 문장"))
        let kept = Clip(content: .text("남길 문장"))
        try await storage.insert(clip)
        try await storage.insert(kept)
        let reactor = try makeReactor(storage: storage)
        reactor.action.onNext(.viewDidLoad)
        await waitForState(of: reactor) { $0.clips.count == 2 }

        reactor.action.onNext(.delete(clip.id))
        await waitForState(of: reactor) { $0.clips.map(\.id) == [kept.id] }

        let stored = try await storage.fetch(id: clip.id)
        XCTAssertNil(stored)
        XCTAssertNil(reactor.currentState.feedback)
    }

    func testDeletingPinnedImageClipRemovesItFromPinnedRowAndStorage() async throws {
        let storage = try SQLiteClipStorageService(databaseURL: directory.appendingPathComponent("clips.sqlite"))
        let files = try ClipImageFileStore(rootURL: directory.appendingPathComponent("images", isDirectory: true))
        let images = ClipImageService(storage: storage, files: files)
        let clip = try await images.saveImage(ClipImageTestFixture.data(), name: "고정 이미지").value
        _ = try await storage.update(
            id: clip.id,
            change: .details(name: clip.name, memo: clip.memo, isPinned: true)
        )
        let reactor = makeReactor(storage: storage, images: images)
        reactor.action.onNext(.viewDidLoad)
        await waitForState(of: reactor) { $0.content.pinnedClips.map(\.id) == [clip.id] }

        reactor.action.onNext(.delete(clip.id))
        await waitForState(of: reactor) { $0.clips.isEmpty }

        XCTAssertTrue(reactor.currentState.content.pinnedClips.isEmpty)
        let stored = try await storage.fetch(id: clip.id)
        XCTAssertNil(stored)
    }

    func testDeletingUnknownClipDoesNotTouchStorage() async throws {
        let storage = try SQLiteClipStorageService(databaseURL: directory.appendingPathComponent("clips.sqlite"))
        let clip = Clip(content: .text("그대로"))
        try await storage.insert(clip)
        let reactor = try makeReactor(storage: storage)
        reactor.action.onNext(.viewDidLoad)
        await waitForState(of: reactor) { $0.clips.count == 1 }

        var didMutate = false
        let disposable = reactor.mutate(action: .delete(UUID())).subscribe(onNext: { _ in didMutate = true })
        disposable.dispose()

        XCTAssertFalse(didMutate)
        let stored = try await storage.fetch(id: clip.id)
        XCTAssertEqual(stored, clip)
    }

    private func makeReactor(
        storage: SQLiteClipStorageService,
        writer: ClipboardWriterSpy = ClipboardWriterSpy()
    ) throws -> HomeReactor {
        let files = try ClipImageFileStore(rootURL: directory.appendingPathComponent("images", isDirectory: true))
        let images = ClipImageService(storage: storage, files: files)
        return makeReactor(storage: storage, images: images, writer: writer)
    }

    private func makeReactor(
        storage: SQLiteClipStorageService,
        images: ClipImageService,
        writer: ClipboardWriterSpy = ClipboardWriterSpy()
    ) -> HomeReactor {
        let clipboard = ClipboardService(
            storage: storage,
            images: images,
            reader: ClipboardReaderSpy(result: .empty),
            writer: writer
        )
        return HomeReactor(
            storage: storage,
            clipboard: clipboard,
            images: images
        )
    }

    private func waitForState(
        of reactor: HomeReactor,
        where predicate: @escaping (HomeReactor.State) -> Bool
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
