//
//  ClipBridgeHistoryModuleImplTests.swift
//  PlystTests
//
//  Created by opfic on 10/11/26.
//

import Foundation
import PlystBridge
import XCTest

final class ClipBridgeHistoryModuleImplTests: XCTestCase {
    override func tearDown() async throws {
        await ClipBridge.unregister()
        try await super.tearDown()
    }

    func testGetSearchHistoryDeliversSuccess() async {
        let stub = ClipBridgeHistoryProviderStub(fetch: { ["Swift", "QR"] })
        await ClipBridge.register(stub)
        let module = ClipBridgeModuleImpl(emit: { _, _ in })
        let completion = expectation(description: "요청 완료")

        module.getSearchHistory { terms, code in
            XCTAssertEqual(terms as? [String], ["Swift", "QR"])
            XCTAssertNil(code)
            completion.fulfill()
        }

        await fulfillment(of: [completion], timeout: 2)
    }

    func testGetSearchHistoryMapsUnknownFailure() async {
        let stub = ClipBridgeHistoryProviderStub(fetch: { throw ClipBridgeHistoryTestError.failed })
        await ClipBridge.register(stub)
        let module = ClipBridgeModuleImpl(emit: { _, _ in })
        let completion = expectation(description: "오류 전달")

        module.getSearchHistory { terms, code in
            XCTAssertNil(terms)
            XCTAssertEqual(code, "E_READ_FAILED")
            completion.fulfill()
        }

        await fulfillment(of: [completion], timeout: 2)
    }

    func testGetSearchHistoryDeliversUnavailable() async {
        await ClipBridge.unregister()
        let module = ClipBridgeModuleImpl(emit: { _, _ in })
        let completion = expectation(description: "오류 전달")

        module.getSearchHistory { terms, code in
            XCTAssertNil(terms)
            XCTAssertEqual(code, "E_UNAVAILABLE")
            completion.fulfill()
        }

        await fulfillment(of: [completion], timeout: 2)
    }

    func testGetSearchHistoryDeliversCorruptedData() async {
        let stub = ClipBridgeHistoryProviderStub(fetch: { throw ClipBridgeError.corruptedData })
        await ClipBridge.register(stub)
        let module = ClipBridgeModuleImpl(emit: { _, _ in })
        let completion = expectation(description: "오류 전달")

        module.getSearchHistory { terms, code in
            XCTAssertNil(terms)
            XCTAssertEqual(code, "E_CORRUPTED_DATA")
            completion.fulfill()
        }

        await fulfillment(of: [completion], timeout: 2)
    }

    func testGetSearchHistoryCancelsAndSuppressesResultAfterInvalidation() async {
        let started = expectation(description: "요청 시작")
        let cancelled = expectation(description: "요청 취소")
        let returned = expectation(description: "요청 반환")
        let completion = expectation(description: "무효화 후 결과 미전달")
        completion.isInverted = true
        let gate = ClipBridgeHistoryRequestGate()
        let stub = ClipBridgeHistoryProviderStub(fetch: {
            await withTaskCancellationHandler {
                await gate.wait(started: started)
            } onCancel: {
                cancelled.fulfill()
            }
            returned.fulfill()
            return []
        })
        await ClipBridge.register(stub)
        let module = ClipBridgeModuleImpl(emit: { _, _ in })

        module.getSearchHistory { _, _ in completion.fulfill() }
        await fulfillment(of: [started], timeout: 2)
        module.invalidate()
        await fulfillment(of: [cancelled], timeout: 2)
        await gate.resume()
        await fulfillment(of: [returned], timeout: 2)
        await fulfillment(of: [completion], timeout: 0.1)
    }

    func testRecordSearchTermDeliversSuccess() async {
        let stub = ClipBridgeHistoryProviderStub(record: { term in
            XCTAssertEqual(term, "  Raw \n")
            return ["Swift", "QR"]
        })
        await ClipBridge.register(stub)
        let module = ClipBridgeModuleImpl(emit: { _, _ in })
        let completion = expectation(description: "요청 완료")

        module.recordSearchTerm("  Raw \n") { terms, code in
            XCTAssertEqual(terms as? [String], ["Swift", "QR"])
            XCTAssertNil(code)
            completion.fulfill()
        }

        await fulfillment(of: [completion], timeout: 2)
    }

    func testRecordSearchTermMapsUnknownFailure() async {
        let stub = ClipBridgeHistoryProviderStub(record: { _ in throw ClipBridgeHistoryTestError.failed })
        await ClipBridge.register(stub)
        let module = ClipBridgeModuleImpl(emit: { _, _ in })
        let completion = expectation(description: "오류 전달")

        module.recordSearchTerm("  Raw \n") { terms, code in
            XCTAssertNil(terms)
            XCTAssertEqual(code, "E_WRITE_FAILED")
            completion.fulfill()
        }

        await fulfillment(of: [completion], timeout: 2)
    }

    func testRecordSearchTermDeliversUnavailable() async {
        await ClipBridge.unregister()
        let module = ClipBridgeModuleImpl(emit: { _, _ in })
        let completion = expectation(description: "오류 전달")

        module.recordSearchTerm("  Raw \n") { terms, code in
            XCTAssertNil(terms)
            XCTAssertEqual(code, "E_UNAVAILABLE")
            completion.fulfill()
        }

        await fulfillment(of: [completion], timeout: 2)
    }

    func testRecordSearchTermDeliversCorruptedData() async {
        let stub = ClipBridgeHistoryProviderStub(record: { _ in throw ClipBridgeError.corruptedData })
        await ClipBridge.register(stub)
        let module = ClipBridgeModuleImpl(emit: { _, _ in })
        let completion = expectation(description: "오류 전달")

        module.recordSearchTerm("  Raw \n") { terms, code in
            XCTAssertNil(terms)
            XCTAssertEqual(code, "E_CORRUPTED_DATA")
            completion.fulfill()
        }

        await fulfillment(of: [completion], timeout: 2)
    }

    func testRecordSearchTermCancelsAndSuppressesResultAfterInvalidation() async {
        let started = expectation(description: "요청 시작")
        let cancelled = expectation(description: "요청 취소")
        let returned = expectation(description: "요청 반환")
        let completion = expectation(description: "무효화 후 결과 미전달")
        completion.isInverted = true
        let gate = ClipBridgeHistoryRequestGate()
        let stub = ClipBridgeHistoryProviderStub(record: { _ in
            await withTaskCancellationHandler {
                await gate.wait(started: started)
            } onCancel: {
                cancelled.fulfill()
            }
            returned.fulfill()
            return []
        })
        await ClipBridge.register(stub)
        let module = ClipBridgeModuleImpl(emit: { _, _ in })

        module.recordSearchTerm("  Raw \n") { _, _ in completion.fulfill() }
        await fulfillment(of: [started], timeout: 2)
        module.invalidate()
        await fulfillment(of: [cancelled], timeout: 2)
        await gate.resume()
        await fulfillment(of: [returned], timeout: 2)
        await fulfillment(of: [completion], timeout: 0.1)
    }

    func testRecordSearchTermDeliversNilWithoutInterpretingInput() async {
        let stub = ClipBridgeHistoryProviderStub(record: { term in
            XCTAssertEqual(term, " \n\t ")
            return nil
        })
        await ClipBridge.register(stub)
        let module = ClipBridgeModuleImpl(emit: { _, _ in })
        let completion = expectation(description: "공백 기록 결과 전달")

        module.recordSearchTerm(" \n\t ") { terms, code in
            XCTAssertNil(terms)
            XCTAssertNil(code)
            completion.fulfill()
        }

        await fulfillment(of: [completion], timeout: 2)
    }
}

enum ClipBridgeHistoryTestError: Error {
    case failed
}

struct ClipBridgeHistoryProviderStub: ClipBridgeProvider {
    var fetch: @Sendable () async throws -> [String] = { [] }
    var record: @Sendable (String) async throws -> [String]? = { _ in nil }
    var remove: @Sendable (String) async throws -> [String] = { _ in [] }
    var clear: @Sendable () async throws -> Void = {}

    func searchHistory() async throws -> [String] { try await fetch() }
    func recordSearchTerm(_ term: String) async throws -> [String]? { try await record(term) }
    func removeSearchTerm(_ term: String) async throws -> [String] { try await remove(term) }
    func removeAllSearchTerms() async throws { try await clear() }

    func changes() async -> AsyncStream<ClipBridgeChange> { AsyncStream { $0.finish() } }
    func getClipImagePreview(id: UUID) async throws -> String? { nil }
    func getClipThumbnail(
        id: UUID,
        maximumPixelDimension: Int
    ) async throws -> String? { nil }
    func saveClipImageToPhotos(id: UUID) async throws -> ClipBridgePhotoSaveResult? { nil }
    func clip(id: UUID) async throws -> ClipBridgeRecord? { nil }
    func saveCurrentClipboard() async throws -> ClipBridgeClipboardSaveResult { .empty }
    func clips() async throws -> [ClipBridgeRecord] { [] }
    func updateClip(
        id: UUID,
        name: String?,
        memo: String?,
        isPinned: Bool
    ) async throws -> ClipBridgeRecord? { nil }
    func deleteClip(id: UUID) async throws {}
    func copyClip(id: UUID) async throws -> ClipBridgeCopyResult? { nil }
}

actor ClipBridgeHistoryRequestGate {
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
