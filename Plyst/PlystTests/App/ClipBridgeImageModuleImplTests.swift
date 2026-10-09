//
//  ClipBridgeImageModuleImplTests.swift
//  PlystTests
//
//  Created by opfic on 10/9/26.
//

import Foundation
import PlystBridge
import XCTest

final class ClipBridgeImageModuleImplTests: XCTestCase {
    override func tearDown() async throws {
        await ClipBridge.unregister()
        try await super.tearDown()
    }

    func testImageMethodsForwardIdentifierAndResults() async {
        let id = UUID()
        let stub = ClipBridgeImageProviderStub(
            preview: {
                XCTAssertEqual($0, id)
                return "file:///images/preview"
            },
            save: {
                XCTAssertEqual($0, id)
                return .saved
            }
        )
        await ClipBridge.register(stub)
        let preview = expectation(description: "미리보기 완료")
        let save = expectation(description: "사진 저장 완료")
        let module = ClipBridgeModuleImpl(emit: { _, _ in })
        module.getClipImagePreview(id.uuidString) { result, code in
            XCTAssertEqual(result, "file:///images/preview")
            XCTAssertNil(code)
            preview.fulfill()
        }
        module.saveClipImageToPhotos(id.uuidString) { result, code in
            XCTAssertEqual(result, "saved")
            XCTAssertNil(code)
            save.fulfill()
        }
        await fulfillment(of: [preview, save], timeout: 2)
    }

    func testMissingImagesReturnNilWithoutError() async {
        await ClipBridge.register(ClipBridgeImageProviderStub(
            preview: { _ in nil },
            save: { _ in nil }
        ))
        let preview = expectation(description: "미리보기 완료")
        let save = expectation(description: "사진 저장 완료")
        let module = ClipBridgeModuleImpl(emit: { _, _ in })
        module.getClipImagePreview(UUID().uuidString) { result, code in
            XCTAssertNil(result)
            XCTAssertNil(code)
            preview.fulfill()
        }
        module.saveClipImageToPhotos(UUID().uuidString) { result, code in
            XCTAssertNil(result)
            XCTAssertNil(code)
            save.fulfill()
        }
        await fulfillment(of: [preview, save], timeout: 2)
    }

    func testUnknownFailuresUseOperationErrorCodes() async {
        await ClipBridge.register(ClipBridgeImageProviderStub(
            preview: { _ in throw ClipBridgeImageProviderTestError.failed },
            save: { _ in throw ClipBridgeImageProviderTestError.failed }
        ))
        let preview = expectation(description: "미리보기 오류")
        let save = expectation(description: "사진 저장 오류")
        let module = ClipBridgeModuleImpl(emit: { _, _ in })
        module.getClipImagePreview(UUID().uuidString) { result, code in
            XCTAssertNil(result)
            XCTAssertEqual(code, "E_IMAGE_UNAVAILABLE")
            preview.fulfill()
        }
        module.saveClipImageToPhotos(UUID().uuidString) { result, code in
            XCTAssertNil(result)
            XCTAssertEqual(code, "E_PHOTO_SAVE_FAILED")
            save.fulfill()
        }
        await fulfillment(of: [preview, save], timeout: 2)
    }

    func testInvalidIdentifiersReturnCommonErrorCode() async {
        let preview = expectation(description: "잘못된 미리보기 식별자")
        let save = expectation(description: "잘못된 사진 저장 식별자")
        let module = ClipBridgeModuleImpl(emit: { _, _ in })
        module.getClipImagePreview("invalid") { result, code in
            XCTAssertNil(result)
            XCTAssertEqual(code, "E_INVALID_ID")
            preview.fulfill()
        }
        module.saveClipImageToPhotos("invalid") { result, code in
            XCTAssertNil(result)
            XCTAssertEqual(code, "E_INVALID_ID")
            save.fulfill()
        }
        await fulfillment(of: [preview, save], timeout: 2)
    }

    func testUnregisteredProviderReturnsUnavailable() async {
        await ClipBridge.unregister()
        let preview = expectation(description: "미리보기 제공자 없음")
        let save = expectation(description: "사진 저장 제공자 없음")
        let module = ClipBridgeModuleImpl(emit: { _, _ in })
        module.getClipImagePreview(UUID().uuidString) { result, code in
            XCTAssertNil(result)
            XCTAssertEqual(code, "E_UNAVAILABLE")
            preview.fulfill()
        }
        module.saveClipImageToPhotos(UUID().uuidString) { result, code in
            XCTAssertNil(result)
            XCTAssertEqual(code, "E_UNAVAILABLE")
            save.fulfill()
        }
        await fulfillment(of: [preview, save], timeout: 2)
    }

    func testPhotoPermissionResultsAreRawStrings() async {
        for result in [ClipBridgePhotoSaveResult.denied, .restricted] {
            await ClipBridge.register(ClipBridgeImageProviderStub(
                preview: { _ in nil },
                save: { _ in result }
            ))
            let completion = expectation(description: "사진 권한 결과")
            ClipBridgeModuleImpl(emit: { _, _ in }).saveClipImageToPhotos(UUID().uuidString) { value, code in
                XCTAssertEqual(value, result.rawValue)
                XCTAssertNil(code)
                completion.fulfill()
            }
            await fulfillment(of: [completion], timeout: 2)
        }
    }
}

private enum ClipBridgeImageProviderTestError: Error {
    case failed
}

private struct ClipBridgeImageProviderStub: ClipBridgeProvider {
    let preview: @Sendable (UUID) async throws -> String?
    let save: @Sendable (UUID) async throws -> ClipBridgePhotoSaveResult?

    func changes() async -> AsyncStream<ClipBridgeChange> {
        AsyncStream { $0.finish() }
    }

    func clip(id: UUID) async throws -> ClipBridgeRecord? { nil }

    func updateClip(
        id: UUID,
        name: String?,
        memo: String?,
        isPinned: Bool
    ) async throws -> ClipBridgeRecord? { nil }

    func deleteClip(id: UUID) async throws {}

    func copyClip(id: UUID) async throws -> ClipBridgeCopyResult? { nil }

    func getClipImagePreview(id: UUID) async throws -> String? {
        try await preview(id)
    }

    func saveClipImageToPhotos(id: UUID) async throws -> ClipBridgePhotoSaveResult? {
        try await save(id)
    }
}
