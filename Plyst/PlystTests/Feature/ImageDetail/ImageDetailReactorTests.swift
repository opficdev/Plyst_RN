//
//  ImageDetailReactorTests.swift
//  PlystTests
//
//  Created by opfic on 10/1/26.
//

import Foundation
import ImageIO
import ReactorKit
import RxSwift
import XCTest
@testable import Plyst

@MainActor
final class ImageDetailReactorTests: XCTestCase {
    private let directory = FileManager.default.temporaryDirectory.appendingPathComponent("Plyst-image-detail-\(UUID())", isDirectory: true)

    override func tearDownWithError() throws {
        if FileManager.default.fileExists(atPath: directory.path) {
            try FileManager.default.removeItem(at: directory)
        }
        try super.tearDownWithError()
    }

    func testSavingWithoutChangesDoesNotEmitMutations() async throws {
        let storage = try makeStorage()
        let images = try makeImages(storage: storage)
        let clip = try await images.saveImage(ClipImageTestFixture.data(), name: "이름").value
        let reactor = makeReactor(clip: clip, storage: storage, images: images)
        reactor.action.onNext(.changeName(" 이름 "))
        await waitForState(of: reactor) { $0.draft.name == " 이름 " }

        XCTAssertFalse(reactor.currentState.canSave)
        var didMutate = false
        let disposable = reactor.mutate(action: .save).subscribe(onNext: { _ in didMutate = true })
        disposable.dispose()

        XCTAssertFalse(didMutate)
        let stored = try await storage.fetch(id: clip.id)
        XCTAssertEqual(stored, clip)
    }

    func testSaveStoresNameAndPinTogetherPreservingMemoOriginalAndDates() async throws {
        let storage = try makeStorage()
        let images = try makeImages(storage: storage)
        let data = try ClipImageTestFixture.data()
        let clip = try await images.saveImage(data, name: "처음", memo: "보존할 메모").value
        let used = Date(timeIntervalSinceReferenceDate: 500)
        let original = try await storage.update(id: clip.id, change: .lastUsedAt(used))
        let reactor = makeReactor(clip: original, storage: storage, images: images)
        reactor.action.onNext(.changeName(" 새 이름 "))
        reactor.action.onNext(.changePinned(true))
        await waitForState(of: reactor) { $0.draft.isPinned && $0.canSave }
        reactor.action.onNext(.save)
        await waitForState(of: reactor) { $0.feedback?.isSuccess == true && !$0.canSave }

        let stored = try await storage.fetch(id: clip.id)
        let bytes = try await images.loadImage(id: clip.id)
        XCTAssertEqual(stored?.name, "새 이름")
        XCTAssertEqual(stored?.isPinned, true)
        XCTAssertEqual(stored?.memo, original.memo)
        XCTAssertEqual(stored?.content, original.content)
        XCTAssertEqual(stored?.createdAt, original.createdAt)
        XCTAssertEqual(stored?.lastUsedAt, used)
        XCTAssertEqual(bytes, data)
        XCTAssertEqual(reactor.currentState.draft.name, "새 이름")
    }

    func testUnsavedDraftDoesNotReachStorage() async throws {
        let storage = try makeStorage()
        let images = try makeImages(storage: storage)
        let clip = try await images.saveImage(ClipImageTestFixture.data(), name: "원본").value
        var reactor: ImageDetailReactor? = makeReactor(clip: clip, storage: storage, images: images)
        reactor?.action.onNext(.changeName("편집 중"))
        reactor?.action.onNext(.changePinned(true))
        if let reactor { await waitForState(of: reactor) { $0.hasChanges } }
        reactor = nil

        let stored = try await storage.fetch(id: clip.id)
        XCTAssertEqual(stored, clip)
    }

    func testCopyWritesOriginalUpdatesUsageAndKeepsDraft() async throws {
        let storage = try makeStorage()
        let images = try makeImages(storage: storage)
        let data = try ClipImageTestFixture.data()
        let clip = try await images.saveImage(data).value
        let spy = ClipboardWriterSpy()
        let reactor = makeReactor(
            clip: clip,
            storage: storage,
            images: images,
            clipboardWriter: spy
        )
        reactor.action.onNext(.viewDidLoad)
        reactor.action.onNext(.changeName("편집 중"))
        await waitForState(of: reactor) { $0.draft.name == "편집 중" }
        reactor.action.onNext(.copy)
        await waitForState(of: reactor) { $0.feedback?.isSuccess == true && $0.clip.lastUsedAt != nil }

        XCTAssertEqual(spy.contents, [.image(data: data, contentType: "public.png")])
        XCTAssertEqual(reactor.currentState.draft.name, "편집 중")
        let used = reactor.currentState.clip.lastUsedAt
        reactor.action.onNext(.save)
        await waitForState(of: reactor) { $0.clip.name == "편집 중" && !$0.isSaving }
        let stored = try await storage.fetch(id: clip.id)
        XCTAssertEqual(stored?.lastUsedAt, used)
    }

    func testPreviewUsesOrientedThumbnailAndLeavesOriginalUntouched() async throws {
        let storage = try makeStorage()
        let images = try makeImages(storage: storage)
        let data = try ClipImageTestFixture.data(orientation: 6)
        let clip = try await images.saveImage(data).value
        let reactor = makeReactor(clip: clip, storage: storage, images: images)

        reactor.action.onNext(.previewRequested(20))
        await waitForState(of: reactor) { $0.previewData != nil && !$0.isPreviewLoading }

        let thumbnail = try XCTUnwrap(reactor.currentState.previewData)
        let source = try XCTUnwrap(CGImageSourceCreateWithData(thumbnail as CFData, nil))
        let image = try XCTUnwrap(CGImageSourceCreateImageAtIndex(source, 0, nil))
        XCTAssertEqual(image.width, 3)
        XCTAssertEqual(image.height, 2)
        let original = try await images.loadImage(id: clip.id)
        XCTAssertEqual(original, data)
        XCTAssertFalse(reactor.currentState.didFailPreview)
    }

    func testMissingOriginalReportsPreviewFailure() async throws {
        let storage = try makeStorage()
        let images = try makeImages(storage: storage)
        let clip = try await images.saveImage(ClipImageTestFixture.data()).value
        guard case .image(let image) = clip.content else { return XCTFail("이미지 클립 필요") }
        let files = try ClipImageFileStore(rootURL: directory.appendingPathComponent("images", isDirectory: true))
        try files.delete(fileID: image.fileID)
        let reactor = makeReactor(clip: clip, storage: storage, images: images)

        reactor.action.onNext(.previewRequested(20))
        await waitForState(of: reactor) { $0.didFailPreview }

        XCTAssertNil(reactor.currentState.previewData)
        XCTAssertFalse(reactor.currentState.isPreviewLoading)
        XCTAssertFalse(reactor.currentState.isRemoved)
    }

    func testDeleteRemovesMetadataAndOriginalFile() async throws {
        let storage = try makeStorage()
        let images = try makeImages(storage: storage)
        let clip = try await images.saveImage(ClipImageTestFixture.data()).value
        guard case .image(let image) = clip.content else { return XCTFail("이미지 클립 필요") }
        let reactor = makeReactor(clip: clip, storage: storage, images: images)

        reactor.action.onNext(.delete)
        await waitForState(of: reactor) { $0.isRemoved }

        let stored = try await storage.fetch(id: clip.id)
        XCTAssertNil(stored)
        let files = try ClipImageFileStore(rootURL: directory.appendingPathComponent("images", isDirectory: true))
        XCTAssertThrowsError(try files.load(fileID: image.fileID)) {
            XCTAssertEqual($0 as? ClipImageFileError, .notFound(image.fileID))
        }
    }

    func testPhotoPermissionResultsAndWriteFailureHaveDifferentFeedback() async throws {
        let storage = try makeStorage()
        let images = try makeImages(storage: storage)
        let clip = try await images.saveImage(ClipImageTestFixture.data()).value
        let spy = PhotoLibraryWriterSpy()
        let reactor = makeReactor(
            clip: clip,
            storage: storage,
            images: images,
            photoWriter: spy
        )

        spy.authorization = .denied
        reactor.action.onNext(.saveToPhotos)
        await waitForState(of: reactor) { $0.feedback?.message.contains("권한") == true }
        XCTAssertEqual(reactor.currentState.feedback?.isSuccess, false)
        XCTAssertTrue(spy.writes.isEmpty)
        spy.authorization = .restricted
        reactor.action.onNext(.saveToPhotos)
        await waitForState(of: reactor) { $0.feedback?.message.contains("제한") == true }
        XCTAssertTrue(spy.writes.isEmpty)
        spy.authorization = .authorized
        spy.failsWrite = true
        reactor.action.onNext(.saveToPhotos)
        await waitForState(of: reactor) { $0.feedback?.message == "사진 앱에 저장하지 못했습니다" }
        spy.failsWrite = false
        reactor.action.onNext(.saveToPhotos)
        await waitForState(of: reactor) { $0.feedback?.isSuccess == true }
        XCTAssertEqual(spy.writes.count, 1)
        XCTAssertFalse(reactor.currentState.isSavingToPhotos)
    }

    func testPhotoSaveForDeletedClipClosesScreenWithoutWriting() async throws {
        let storage = try makeStorage()
        let images = try makeImages(storage: storage)
        let clip = try await images.saveImage(ClipImageTestFixture.data()).value
        let spy = PhotoLibraryWriterSpy()
        let reactor = makeReactor(
            clip: clip,
            storage: storage,
            images: images,
            photoWriter: spy
        )
        _ = try await images.delete(id: clip.id)

        reactor.action.onNext(.saveToPhotos)
        await waitForState(of: reactor) { $0.isRemoved }

        XCTAssertTrue(spy.writes.isEmpty)
        XCTAssertFalse(reactor.currentState.isSavingToPhotos)
        XCTAssertNil(reactor.currentState.feedback)
    }

    func testActionsAreIgnoredWhileDeletingAndAfterRemoval() async throws {
        let storage = try makeStorage()
        let images = try makeImages(storage: storage)
        let clip = try await images.saveImage(ClipImageTestFixture.data(), name: "원본").value
        let clipboardSpy = ClipboardWriterSpy()
        let photoSpy = PhotoLibraryWriterSpy()
        let reactor = makeReactor(
            clip: clip,
            storage: storage,
            images: images,
            clipboardWriter: clipboardSpy,
            photoWriter: photoSpy
        )
        reactor.action.onNext(.changeName("편집 중"))
        await waitForState(of: reactor) { $0.canSave }

        // 삭제를 시작한 직후의 상태에서 동작을 보내 삭제 중 guard를 확인합니다.
        let actions = [ImageDetailReactor.Action.save, .copy, .delete, .saveToPhotos]
        var ignoredWhileDeleting = [Bool]()
        let disposable = reactor.state.subscribe(onNext: { [self] state in
            guard state.isDeleting, ignoredWhileDeleting.isEmpty else { return }
            ignoredWhileDeleting = actions.map { ignores($0, on: reactor) }
        })
        reactor.action.onNext(.delete)
        await waitForState(of: reactor) { $0.isRemoved }
        disposable.dispose()

        XCTAssertEqual(ignoredWhileDeleting, [true, true, true, true])
        let afterRemoval = actions + [.previewRequested(20)]
        XCTAssertEqual(afterRemoval.map { ignores($0, on: reactor) }, [true, true, true, true, true])
        XCTAssertTrue(clipboardSpy.contents.isEmpty)
        XCTAssertTrue(photoSpy.writes.isEmpty)
        XCTAssertEqual(photoSpy.authorizationCount, 0)
        let stored = try await storage.fetch(id: clip.id)
        XCTAssertNil(stored)
    }

    func testExternalChangesKeepEditedDraftAndExternalDeletionClosesScreen() async throws {
        let storage = try makeStorage()
        let images = try makeImages(storage: storage)
        let clip = try await images.saveImage(ClipImageTestFixture.data(), name: "처음").value
        let reactor = makeReactor(clip: clip, storage: storage, images: images)
        reactor.action.onNext(.viewDidLoad)
        _ = try await storage.update(id: clip.id, change: .details(name: "바뀜", memo: "메모", isPinned: false))
        await waitForState(of: reactor) { $0.clip.name == "바뀜" }
        XCTAssertEqual(reactor.currentState.draft.name, "바뀜")
        reactor.action.onNext(.changeName("내가 입력"))
        await waitForState(of: reactor) { $0.draft.name == "내가 입력" }
        _ = try await storage.update(id: clip.id, change: .details(name: "또 바뀜", memo: "새 메모", isPinned: false))
        await waitForState(of: reactor) { $0.clip.memo == "새 메모" }
        XCTAssertEqual(reactor.currentState.draft.name, "내가 입력")
        reactor.action.onNext(.save)
        await waitForState(of: reactor) { $0.clip.name == "내가 입력" && !$0.isSaving }
        let stored = try await storage.fetch(id: clip.id)
        XCTAssertEqual(stored?.memo, "새 메모")

        _ = try await images.delete(id: clip.id)
        await waitForState(of: reactor) { $0.isRemoved }
    }

    private func makeStorage() throws -> SQLiteClipStorageService {
        try SQLiteClipStorageService(databaseURL: directory.appendingPathComponent("clips.sqlite"))
    }

    private func makeImages(storage: SQLiteClipStorageService) throws -> ClipImageService {
        ClipImageService(
            storage: storage,
            files: try ClipImageFileStore(rootURL: directory.appendingPathComponent("images", isDirectory: true))
        )
    }

    private func makeReactor(
        clip: Clip,
        storage: SQLiteClipStorageService,
        images: ClipImageService,
        clipboardWriter: ClipboardWriterSpy = ClipboardWriterSpy(),
        photoWriter: PhotoLibraryWriterSpy = PhotoLibraryWriterSpy()
    ) -> ImageDetailReactor {
        ImageDetailReactor(
            clip: clip,
            storage: storage,
            clipboard: ClipboardService(
                storage: storage,
                images: images,
                reader: ClipboardReaderSpy(result: .empty),
                writer: clipboardWriter
            ),
            images: images,
            photos: ClipPhotoLibraryService(
                storage: storage,
                images: images,
                writer: photoWriter
            )
        )
    }

    /// guard에 막힌 동작은 아무 Mutation도 내보내지 않고 즉시 완료됩니다.
    private func ignores(
        _ action: ImageDetailReactor.Action,
        on reactor: ImageDetailReactor
    ) -> Bool {
        var didEmit = false
        var didComplete = false
        let disposable = reactor.mutate(action: action).subscribe(
            onNext: { _ in didEmit = true },
            onCompleted: { didComplete = true }
        )
        disposable.dispose()
        return didComplete && !didEmit
    }

    private func waitForState(
        of reactor: ImageDetailReactor,
        where predicate: @escaping (ImageDetailReactor.State) -> Bool
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
