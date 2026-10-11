//
//  ClipBridgeHistoryRemovalModuleImplTests.swift
//  PlystTests
//
//  Created by opfic on 10/11/26.
//

import Foundation
import PlystBridge
import XCTest

final class ClipBridgeHistoryRemovalModuleImplTests: XCTestCase {
    override func tearDown() async throws {
        await ClipBridge.unregister()
        try await super.tearDown()
    }

    func testRemoveSearchTermDeliversSuccess() async {
        let stub = ClipBridgeHistoryProviderStub(remove: { term in
            XCTAssertEqual(term, "  Raw \n")
            return ["Swift", "QR"]
        })
        await ClipBridge.register(stub)
        let module = ClipBridgeModuleImpl(emit: { _, _ in })
        let completion = expectation(description: "요청 완료")

        module.removeSearchTerm("  Raw \n") { terms, code in
            XCTAssertEqual(terms as? [String], ["Swift", "QR"])
            XCTAssertNil(code)
            completion.fulfill()
        }

        await fulfillment(of: [completion], timeout: 2)
    }

    func testRemoveSearchTermMapsUnknownFailure() async {
        let stub = ClipBridgeHistoryProviderStub(remove: { _ in throw ClipBridgeHistoryTestError.failed })
        await ClipBridge.register(stub)
        let module = ClipBridgeModuleImpl(emit: { _, _ in })
        let completion = expectation(description: "오류 전달")

        module.removeSearchTerm("  Raw \n") { terms, code in
            XCTAssertNil(terms)
            XCTAssertEqual(code, "E_WRITE_FAILED")
            completion.fulfill()
        }

        await fulfillment(of: [completion], timeout: 2)
    }

    func testRemoveSearchTermDeliversUnavailable() async {
        await ClipBridge.unregister()
        let module = ClipBridgeModuleImpl(emit: { _, _ in })
        let completion = expectation(description: "오류 전달")

        module.removeSearchTerm("  Raw \n") { terms, code in
            XCTAssertNil(terms)
            XCTAssertEqual(code, "E_UNAVAILABLE")
            completion.fulfill()
        }

        await fulfillment(of: [completion], timeout: 2)
    }

    func testRemoveSearchTermDeliversCorruptedData() async {
        let stub = ClipBridgeHistoryProviderStub(remove: { _ in throw ClipBridgeError.corruptedData })
        await ClipBridge.register(stub)
        let module = ClipBridgeModuleImpl(emit: { _, _ in })
        let completion = expectation(description: "오류 전달")

        module.removeSearchTerm("  Raw \n") { terms, code in
            XCTAssertNil(terms)
            XCTAssertEqual(code, "E_CORRUPTED_DATA")
            completion.fulfill()
        }

        await fulfillment(of: [completion], timeout: 2)
    }

    func testRemoveSearchTermCancelsAndSuppressesResultAfterInvalidation() async {
        let started = expectation(description: "요청 시작")
        let cancelled = expectation(description: "요청 취소")
        let returned = expectation(description: "요청 반환")
        let completion = expectation(description: "무효화 후 결과 미전달")
        completion.isInverted = true
        let gate = ClipBridgeHistoryRequestGate()
        let stub = ClipBridgeHistoryProviderStub(remove: { _ in
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

        module.removeSearchTerm("  Raw \n") { _, _ in completion.fulfill() }
        await fulfillment(of: [started], timeout: 2)
        module.invalidate()
        await fulfillment(of: [cancelled], timeout: 2)
        await gate.resume()
        await fulfillment(of: [returned], timeout: 2)
        await fulfillment(of: [completion], timeout: 0.1)
    }

    func testRemoveAllSearchTermsDeliversSuccess() async {
        let stub = ClipBridgeHistoryProviderStub(clear: {})
        await ClipBridge.register(stub)
        let module = ClipBridgeModuleImpl(emit: { _, _ in })
        let completion = expectation(description: "요청 완료")

        module.removeAllSearchTerms { code in
            XCTAssertNil(code)
            completion.fulfill()
        }

        await fulfillment(of: [completion], timeout: 2)
    }

    func testRemoveAllSearchTermsMapsUnknownFailure() async {
        let stub = ClipBridgeHistoryProviderStub(clear: { throw ClipBridgeHistoryTestError.failed })
        await ClipBridge.register(stub)
        let module = ClipBridgeModuleImpl(emit: { _, _ in })
        let completion = expectation(description: "오류 전달")

        module.removeAllSearchTerms { code in
            XCTAssertEqual(code, "E_WRITE_FAILED")
            completion.fulfill()
        }

        await fulfillment(of: [completion], timeout: 2)
    }

    func testRemoveAllSearchTermsDeliversUnavailable() async {
        await ClipBridge.unregister()
        let module = ClipBridgeModuleImpl(emit: { _, _ in })
        let completion = expectation(description: "오류 전달")

        module.removeAllSearchTerms { code in
            XCTAssertEqual(code, "E_UNAVAILABLE")
            completion.fulfill()
        }

        await fulfillment(of: [completion], timeout: 2)
    }

    func testRemoveAllSearchTermsCancelsAndSuppressesResultAfterInvalidation() async {
        let started = expectation(description: "요청 시작")
        let cancelled = expectation(description: "요청 취소")
        let returned = expectation(description: "요청 반환")
        let completion = expectation(description: "무효화 후 결과 미전달")
        completion.isInverted = true
        let gate = ClipBridgeHistoryRequestGate()
        let stub = ClipBridgeHistoryProviderStub(clear: {
            await withTaskCancellationHandler {
                await gate.wait(started: started)
            } onCancel: {
                cancelled.fulfill()
            }
            returned.fulfill()
        })
        await ClipBridge.register(stub)
        let module = ClipBridgeModuleImpl(emit: { _, _ in })

        module.removeAllSearchTerms { _ in completion.fulfill() }
        await fulfillment(of: [started], timeout: 2)
        module.invalidate()
        await fulfillment(of: [cancelled], timeout: 2)
        await gate.resume()
        await fulfillment(of: [returned], timeout: 2)
        await fulfillment(of: [completion], timeout: 0.1)
    }

    func testHistoryRequestsAfterInvalidationDoNotCallProviderOrComplete() async {
        let unexpected = expectation(description: "무효화 이후 요청 미전달")
        unexpected.isInverted = true
        let stub = ClipBridgeHistoryProviderStub(
            fetch: {
                unexpected.fulfill()
                return []
            },
            record: { _ in
                unexpected.fulfill()
                return nil
            },
            remove: { _ in
                unexpected.fulfill()
                return []
            },
            clear: { unexpected.fulfill() }
        )
        await ClipBridge.register(stub)
        let module = ClipBridgeModuleImpl(emit: { _, _ in })
        await MainActor.run { module.invalidate() }
        await MainActor.run {}

        module.getSearchHistory { _, _ in unexpected.fulfill() }
        module.recordSearchTerm("term") { _, _ in unexpected.fulfill() }
        module.removeSearchTerm("term") { _, _ in unexpected.fulfill() }
        module.removeAllSearchTerms { _ in unexpected.fulfill() }

        await fulfillment(of: [unexpected], timeout: 0.1)
    }
}
