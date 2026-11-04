//
//  HomeBridgeModuleImplTests.swift
//  PlystTests
//
//  Created by opfic on 10/10/26.
//

import Foundation
import PlystBridge
import XCTest

final class HomeBridgeModuleImplTests: XCTestCase {
    override func setUp() async throws {
        try await super.setUp()
        await resetBridge()
    }

    override func tearDown() async throws {
        await resetBridge()
        try await super.tearDown()
    }

    func testClipboardSaveBeforeReadyIsDeliveredOnceWhenReady() async {
        let spy = HomeBridgeClipboardSaveSpy()
        let module = HomeBridgeModuleImpl(requestSave: {
            MainActor.assumeIsolated { spy.count += 1 }
        })

        await HomeBridge.requestClipboardSave()
        await MainActor.run {
            XCTAssertEqual(spy.count, 0)
            module.ready()
        }
        await MainActor.run {}
        await MainActor.run { XCTAssertEqual(spy.count, 1) }

        await MainActor.run { module.ready() }
        await MainActor.run {}
        await MainActor.run { XCTAssertEqual(spy.count, 1) }
    }

    func testMultipleClipboardSaveRequestsBeforeReadyAreDeliveredOnce() async {
        let spy = HomeBridgeClipboardSaveSpy()
        let module = HomeBridgeModuleImpl(requestSave: {
            MainActor.assumeIsolated { spy.count += 1 }
        })

        await MainActor.run {
            HomeBridge.requestClipboardSave()
            HomeBridge.requestClipboardSave()
            HomeBridge.requestClipboardSave()
            XCTAssertEqual(spy.count, 0)
            module.ready()
        }
        await MainActor.run {}
        await MainActor.run { XCTAssertEqual(spy.count, 1) }

        await MainActor.run { module.ready() }
        await MainActor.run {}
        await MainActor.run { XCTAssertEqual(spy.count, 1) }
    }

    private func resetBridge() async {
        let module = HomeBridgeModuleImpl(requestSave: {})
        await MainActor.run { module.ready() }
        await MainActor.run { module.invalidate() }
        await MainActor.run {}
    }
}

private final class HomeBridgeClipboardSaveSpy: Sendable {
    @MainActor var count = 0

    nonisolated init() {}
}
