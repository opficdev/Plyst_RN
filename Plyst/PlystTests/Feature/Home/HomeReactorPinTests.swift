//
//  HomeReactorPinTests.swift
//  PlystTests
//
//  Created by opfic on 9/30/26.
//

import Foundation
import ReactorKit
import RxSwift
import XCTest
@testable import Plyst

@MainActor
final class HomeReactorPinTests: XCTestCase {
    private let directory = FileManager.default.temporaryDirectory.appendingPathComponent("Plyst-home-pin-\(UUID())", isDirectory: true)

    override func tearDownWithError() throws {
        if FileManager.default.fileExists(atPath: directory.path) {
            try FileManager.default.removeItem(at: directory)
        }
        try super.tearDownWithError()
    }

    func testPinChangeMovesClipToPinnedRowAndPinnedFilterWhileKeepingSelectedFilter() async throws {
        let storage = try SQLiteClipStorageService(databaseURL: directory.appendingPathComponent("clips.sqlite"))
        let clip = Clip(content: .text("자주 쓰는 문장"))
        try await storage.insert(clip)
        let reactor = try makeReactor(storage: storage)

        reactor.action.onNext(.viewDidLoad)
        await waitForState(of: reactor) { $0.content.sections.flatMap(\.clips).map(\.id) == [clip.id] }

        reactor.action.onNext(.setPinned(clip.id, true))
        await waitForState(of: reactor) { $0.content.pinnedClips.map(\.id) == [clip.id] }
        XCTAssertTrue(reactor.currentState.content.sections.isEmpty)
        XCTAssertEqual(reactor.currentState.filter, .all)

        reactor.action.onNext(.selectFilter(.pinned))
        await waitForState(of: reactor) { $0.filter == .pinned }
        XCTAssertEqual(reactor.currentState.content.sections.flatMap(\.clips).map(\.id), [clip.id])

        reactor.action.onNext(.setPinned(clip.id, false))
        await waitForState(of: reactor) { $0.content.isEmpty }
        XCTAssertEqual(reactor.currentState.filter, .pinned)
        let stored = try await storage.fetch(id: clip.id)
        XCTAssertEqual(stored?.isPinned, false)
    }

    func testSelectingCurrentFilterKeepsSingleSelection() async throws {
        let storage = try SQLiteClipStorageService(databaseURL: directory.appendingPathComponent("clips.sqlite"))
        let reactor = try makeReactor(storage: storage)

        reactor.action.onNext(.selectFilter(.image))
        reactor.action.onNext(.selectFilter(.text))
        reactor.action.onNext(.selectFilter(.text))
        await waitForState(of: reactor) { $0.filter == .text }

        XCTAssertEqual(reactor.currentState.filter, .text)
    }

    private func makeReactor(storage: SQLiteClipStorageService) throws -> HomeReactor {
        let files = try ClipImageFileStore(rootURL: directory.appendingPathComponent("images", isDirectory: true))
        let images = ClipImageService(storage: storage, files: files)
        let clipboard = ClipboardService(
            storage: storage,
            images: images,
            reader: ClipboardReaderSpy(result: .empty)
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
