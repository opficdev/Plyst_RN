//
//  ClipBridgeWriteModuleImplTests.swift
//  PlystTests
//
//  Created by opfic on 10/9/26.
//

import Foundation
import PlystBridge
import XCTest
@testable import Plyst

final class ClipBridgeWriteModuleImplTests: XCTestCase {
    override func tearDown() async throws {
        await ClipBridge.unregister()
        try await super.tearDown()
    }

    func testUpdateSuccessDelivery() async {
        let id = UUID()
        let module = ClipBridgeModuleImpl(emit: { _, _ in })
        let stub = ClipBridgeProviderStub(
            update: { receivedID, name, memo, isPinned in
                XCTAssertEqual(receivedID, id)
                XCTAssertEqual(name, " 이름 ")
                XCTAssertNil(memo)
                XCTAssertTrue(isPinned)
                return ClipBridgeRecord(
                    id: receivedID.uuidString,
                    text: "원문",
                    image: nil,
                    name: name,
                    memo: memo,
                    isPinned: isPinned,
                    createdAt: 1000,
                    lastUsedAt: nil
                )
            },
            delete: { receivedID in
                XCTAssertEqual(receivedID, id)
            }
        )
        await ClipBridge.register(stub)
        let completion = expectation(description: "요청 완료")

        module.updateClip(
            id.uuidString,
            name: " 이름 ",
            memo: nil,
            isPinned: true
        ) { record, code in
            XCTAssertEqual(record?["id"] as? String, id.uuidString)
            XCTAssertEqual(record?["name"] as? String, " 이름 ")
            XCTAssertTrue(record?["memo"] is NSNull)
            XCTAssertEqual(record?["isPinned"] as? Bool, true)
            XCTAssertNil(code)
            completion.fulfill()
        }

        await fulfillment(of: [completion], timeout: 2)
    }

    func testUpdateMissingDelivery() async {
        let id = UUID()
        let module = ClipBridgeModuleImpl(emit: { _, _ in })
        let stub = ClipBridgeProviderStub(
            update: { _, _, _, _ in
                return nil
            },
            delete: { receivedID in
                XCTAssertEqual(receivedID, id)
            }
        )
        await ClipBridge.register(stub)
        let completion = expectation(description: "요청 완료")

        module.updateClip(
            id.uuidString,
            name: " 이름 ",
            memo: nil,
            isPinned: true
        ) { record, code in
            XCTAssertNil(record)
            XCTAssertNil(code)
            completion.fulfill()
        }

        await fulfillment(of: [completion], timeout: 2)
    }

    func testUpdateWriteFailureDelivery() async {
        let id = UUID()
        let module = ClipBridgeModuleImpl(emit: { _, _ in })
        let stub = ClipBridgeProviderStub(
            update: { _, _, _, _ in
                throw ClipBridgeProviderTestError.failed
            },
            delete: { _ in
                throw ClipBridgeProviderTestError.failed
            }
        )
        await ClipBridge.register(stub)
        let completion = expectation(description: "요청 완료")

        module.updateClip(
            id.uuidString,
            name: " 이름 ",
            memo: nil,
            isPinned: true
        ) { record, code in
            XCTAssertNil(record)
            XCTAssertEqual(code, "E_WRITE_FAILED")
            completion.fulfill()
        }

        await fulfillment(of: [completion], timeout: 2)
    }

    func testUpdateInvalidIdentifierDelivery() async {
        let id = UUID()
        let module = ClipBridgeModuleImpl(emit: { _, _ in })
        let stub = ClipBridgeProviderStub(
            update: { _, _, _, _ in
                return nil
            },
            delete: { receivedID in
                XCTAssertEqual(receivedID, id)
            }
        )
        await ClipBridge.register(stub)
        let completion = expectation(description: "요청 완료")

        module.updateClip(
            "invalid",
            name: " 이름 ",
            memo: nil,
            isPinned: true
        ) { record, code in
            XCTAssertNil(record)
            XCTAssertEqual(code, "E_INVALID_ID")
            completion.fulfill()
        }

        await fulfillment(of: [completion], timeout: 2)
    }

    func testUpdateUnavailableDelivery() async {
        let id = UUID()
        let module = ClipBridgeModuleImpl(emit: { _, _ in })
        await ClipBridge.unregister()
        let completion = expectation(description: "요청 완료")

        module.updateClip(
            id.uuidString,
            name: " 이름 ",
            memo: nil,
            isPinned: true
        ) { record, code in
            XCTAssertNil(record)
            XCTAssertEqual(code, "E_UNAVAILABLE")
            completion.fulfill()
        }

        await fulfillment(of: [completion], timeout: 2)
    }

    func testUpdateDoesNotDeliverAfterInvalidation() async {
        let started = expectation(description: "요청 시작")
        let cancelled = expectation(description: "요청 취소")
        let returned = expectation(description: "요청 반환")
        let completion = expectation(description: "무효화 뒤 결과 미전달")
        completion.isInverted = true
        let gate = ClipBridgeRequestGate()
        let stub = ClipBridgeProviderStub(
            update: { _, _, _, _ in
                await withTaskCancellationHandler {
                    await gate.wait(started: started)
                } onCancel: {
                    cancelled.fulfill()
                }
                returned.fulfill()
                return nil
            },
            delete: { _ in
                await withTaskCancellationHandler {
                    await gate.wait(started: started)
                } onCancel: {
                    cancelled.fulfill()
                }
                returned.fulfill()
            }
        )
        await ClipBridge.register(stub)
        let module = ClipBridgeModuleImpl(emit: { _, _ in })

        module.updateClip(
            UUID().uuidString,
            name: " 이름 ",
            memo: nil,
            isPinned: true
        ) { _, _ in
            completion.fulfill()
        }
        await fulfillment(of: [started], timeout: 2)
        module.invalidate()
        await fulfillment(of: [cancelled], timeout: 2)
        await gate.resume()
        await fulfillment(of: [returned], timeout: 2)
        await fulfillment(of: [completion], timeout: 0.1)
    }

    func testDeleteSuccessDelivery() async {
        let id = UUID()
        let module = ClipBridgeModuleImpl(emit: { _, _ in })
        let stub = ClipBridgeProviderStub(
            update: { _, _, _, _ in
                return nil
            },
            delete: { receivedID in
                XCTAssertEqual(receivedID, id)
            }
        )
        await ClipBridge.register(stub)
        let completion = expectation(description: "요청 완료")

        module.deleteClip(id.uuidString) { code in
            XCTAssertNil(code)
            completion.fulfill()
        }

        await fulfillment(of: [completion], timeout: 2)
    }

    func testDeleteWriteFailureDelivery() async {
        let id = UUID()
        let module = ClipBridgeModuleImpl(emit: { _, _ in })
        let stub = ClipBridgeProviderStub(
            update: { _, _, _, _ in
                throw ClipBridgeProviderTestError.failed
            },
            delete: { _ in
                throw ClipBridgeProviderTestError.failed
            }
        )
        await ClipBridge.register(stub)
        let completion = expectation(description: "요청 완료")

        module.deleteClip(id.uuidString) { code in
            XCTAssertEqual(code, "E_WRITE_FAILED")
            completion.fulfill()
        }

        await fulfillment(of: [completion], timeout: 2)
    }

    func testDeleteInvalidIdentifierDelivery() async {
        let id = UUID()
        let module = ClipBridgeModuleImpl(emit: { _, _ in })
        let stub = ClipBridgeProviderStub(
            update: { _, _, _, _ in
                return nil
            },
            delete: { receivedID in
                XCTAssertEqual(receivedID, id)
            }
        )
        await ClipBridge.register(stub)
        let completion = expectation(description: "요청 완료")

        module.deleteClip("invalid") { code in
            XCTAssertEqual(code, "E_INVALID_ID")
            completion.fulfill()
        }

        await fulfillment(of: [completion], timeout: 2)
    }

    func testDeleteUnavailableDelivery() async {
        let id = UUID()
        let module = ClipBridgeModuleImpl(emit: { _, _ in })
        await ClipBridge.unregister()
        let completion = expectation(description: "요청 완료")

        module.deleteClip(id.uuidString) { code in
            XCTAssertEqual(code, "E_UNAVAILABLE")
            completion.fulfill()
        }

        await fulfillment(of: [completion], timeout: 2)
    }

    func testDeleteDoesNotDeliverAfterInvalidation() async {
        let started = expectation(description: "요청 시작")
        let cancelled = expectation(description: "요청 취소")
        let returned = expectation(description: "요청 반환")
        let completion = expectation(description: "무효화 뒤 결과 미전달")
        completion.isInverted = true
        let gate = ClipBridgeRequestGate()
        let stub = ClipBridgeProviderStub(
            update: { _, _, _, _ in
                await withTaskCancellationHandler {
                    await gate.wait(started: started)
                } onCancel: {
                    cancelled.fulfill()
                }
                returned.fulfill()
                return nil
            },
            delete: { _ in
                await withTaskCancellationHandler {
                    await gate.wait(started: started)
                } onCancel: {
                    cancelled.fulfill()
                }
                returned.fulfill()
            }
        )
        await ClipBridge.register(stub)
        let module = ClipBridgeModuleImpl(emit: { _, _ in })

        module.deleteClip(UUID().uuidString) { _ in
            completion.fulfill()
        }
        await fulfillment(of: [started], timeout: 2)
        module.invalidate()
        await fulfillment(of: [cancelled], timeout: 2)
        await gate.resume()
        await fulfillment(of: [returned], timeout: 2)
        await fulfillment(of: [completion], timeout: 0.1)
    }
}

private enum ClipBridgeProviderTestError: Error {
    case failed
}

private struct ClipBridgeProviderStub: ClipBridgeProvider {
    let update: @Sendable (UUID, String?, String?, Bool) async throws -> ClipBridgeRecord?
    let delete: @Sendable (UUID) async throws -> Void

    func changes() async -> AsyncStream<ClipBridgeChange> {
        AsyncStream { $0.finish() }
    }

    func getClipImagePreview(id: UUID) async throws -> String? { nil }

    func saveClipImageToPhotos(id: UUID) async throws -> ClipBridgePhotoSaveResult? { nil }

    func clip(id: UUID) async throws -> ClipBridgeRecord? { nil }

    func copyClip(id: UUID) async throws -> ClipBridgeCopyResult? { nil }

    func updateClip(
        id: UUID,
        name: String?,
        memo: String?,
        isPinned: Bool
    ) async throws -> ClipBridgeRecord? {
        try await update(id, name, memo, isPinned)
    }

    func deleteClip(id: UUID) async throws {
        try await delete(id)
    }
}

private actor ClipBridgeRequestGate {
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
