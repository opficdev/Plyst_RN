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

    func testThumbnailForwardsIdentifierSizeAndURI() async {
        let id = UUID()
        let stub = ClipBridgeImageProviderStub(
            preview: { _ in nil },
            save: { _ in nil },
            thumbnail: { identifier, dimension in
                XCTAssertEqual(identifier, id)
                XCTAssertEqual(dimension, 240)
                return "file:///images/thumbnail-240"
            }
        )
        await ClipBridge.register(stub)
        let completion = expectation(description: "썸네일 완료")
        let module = ClipBridgeModuleImpl(emit: { _, _ in })
        module.getClipThumbnail(id.uuidString, maximumPixelDimension: 240) { result, code in
            XCTAssertEqual(result, "file:///images/thumbnail-240")
            XCTAssertNil(code)
            completion.fulfill()
        }
        await fulfillment(of: [completion], timeout: 2)
    }

    func testThumbnailRejectsInvalidSizesWithoutCallingProvider() async {
        await ClipBridge.register(ClipBridgeImageProviderStub(
            preview: { _ in nil },
            save: { _ in nil },
            thumbnail: { _, _ in
                XCTFail("잘못된 크기가 제공자에게 전달됐습니다.")
                return nil
            }
        ))
        let module = ClipBridgeModuleImpl(emit: { _, _ in })
        for dimension in [0.0, -1, .nan, .infinity, -.infinity, 1.5, Double.greatestFiniteMagnitude] {
            let completion = expectation(description: "잘못된 썸네일 크기")
            module.getClipThumbnail(UUID().uuidString, maximumPixelDimension: dimension) { result, code in
                XCTAssertNil(result)
                XCTAssertEqual(code, "E_IMAGE_UNAVAILABLE")
                completion.fulfill()
            }
            await fulfillment(of: [completion], timeout: 2)
        }
    }

    func testThumbnailRejectsInvalidIdentifierWithoutCallingProvider() async {
        await ClipBridge.register(ClipBridgeImageProviderStub(
            preview: { _ in nil },
            save: { _ in nil },
            thumbnail: { _, _ in
                XCTFail("잘못된 식별자가 제공자에게 전달됐습니다.")
                return nil
            }
        ))
        let completion = expectation(description: "잘못된 썸네일 식별자")
        let module = ClipBridgeModuleImpl(emit: { _, _ in })
        module.getClipThumbnail("invalid", maximumPixelDimension: 240) { result, code in
            XCTAssertNil(result)
            XCTAssertEqual(code, "E_INVALID_ID")
            completion.fulfill()
        }
        await fulfillment(of: [completion], timeout: 2)
    }

    func testThumbnailMissingImageReturnsNil() async {
        await ClipBridge.register(ClipBridgeImageProviderStub(
            preview: { _ in nil },
            save: { _ in nil }
        ))
        let completion = expectation(description: "썸네일 없음")
        let module = ClipBridgeModuleImpl(emit: { _, _ in })
        module.getClipThumbnail(UUID().uuidString, maximumPixelDimension: 240) { result, code in
            XCTAssertNil(result)
            XCTAssertNil(code)
            completion.fulfill()
        }
        await fulfillment(of: [completion], timeout: 2)
    }

    func testThumbnailProviderFailuresUseImageErrorCode() async {
        for known in [false, true] {
            await ClipBridge.register(ClipBridgeImageProviderStub(
                preview: { _ in nil },
                save: { _ in nil },
                thumbnail: { _, _ in
                    if known { throw ClipBridgeError.imageUnavailable }
                    throw ClipBridgeImageProviderTestError.failed
                }
            ))
            let completion = expectation(description: "썸네일 오류")
            let module = ClipBridgeModuleImpl(emit: { _, _ in })
            module.getClipThumbnail(UUID().uuidString, maximumPixelDimension: 240) { result, code in
                XCTAssertNil(result)
                XCTAssertEqual(code, "E_IMAGE_UNAVAILABLE")
                completion.fulfill()
            }
            await fulfillment(of: [completion], timeout: 2)
        }
    }

    func testThumbnailUnregisteredProviderReturnsUnavailable() async {
        await ClipBridge.unregister()
        let completion = expectation(description: "썸네일 제공자 없음")
        let module = ClipBridgeModuleImpl(emit: { _, _ in })
        module.getClipThumbnail(UUID().uuidString, maximumPixelDimension: 240) { result, code in
            XCTAssertNil(result)
            XCTAssertEqual(code, "E_UNAVAILABLE")
            completion.fulfill()
        }
        await fulfillment(of: [completion], timeout: 2)
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
    var thumbnail: @Sendable (UUID, Int) async throws -> String? = { _, _ in nil }

    func changes() async -> AsyncStream<ClipBridgeChange> {
        AsyncStream { $0.finish() }
    }

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

    func getClipThumbnail(
        id: UUID,
        maximumPixelDimension: Int
    ) async throws -> String? {
        try await thumbnail(id, maximumPixelDimension)
    }

    func getClipImagePreview(id: UUID) async throws -> String? {
        try await preview(id)
    }

    func saveClipImageToPhotos(id: UUID) async throws -> ClipBridgePhotoSaveResult? {
        try await save(id)
    }
}
