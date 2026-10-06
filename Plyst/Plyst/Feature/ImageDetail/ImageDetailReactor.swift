//
//  ImageDetailReactor.swift
//  Plyst
//
//  Created by opfic on 10/1/26.
//

import Foundation
import ReactorKit
import RxSwift

final class ImageDetailReactor: Reactorable {
    enum Action: Sendable {
        case viewDidLoad
        case changeName(String)
        case changePinned(Bool)
        case save
        case copy
        case delete
        case saveToPhotos
        case previewRequested(Int)
        case dismissFeedback(UUID)
    }

    enum Mutation: Sendable {
        case clipLoaded(Clip)
        case removed
        case nameChanged(String)
        case pinnedChanged(Bool)
        case saveStarted
        case saved(Clip, UUID)
        case saveFailed(UUID)
        case copyResult(ClipboardCopyResult, UUID)
        case copyFailed(UUID)
        case deleteStarted
        case deleteFailed(UUID)
        case feedbackDismissed(UUID)
        case photoSaveStarted
        case photoSaveResult(ClipPhotoLibrarySaveResult, UUID)
        case photoSaveFailed(UUID)
        case previewStarted(ClipImageMetadata)
        case previewLoaded(ClipImageMetadata, Data)
        case previewFailed(ClipImageMetadata)
    }

    /// 저장하기 전의 편집 값입니다. 원본 Clip에는 반영되지 않으며 Reactor가 해제되면 함께 사라집니다.
    struct Draft: Equatable, Sendable {
        var name: String
        var isPinned: Bool

        init(clip: Clip) {
            name = clip.name ?? ""
            isPinned = clip.isPinned
        }

        /// 앞뒤 공백을 제거합니다. 공백뿐이면 이름이 없는 것으로 저장합니다.
        var normalizedName: String? {
            let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
            return trimmed.isEmpty ? nil : trimmed
        }

        /// 저장했을 때 원본의 이름과 고정 여부가 바뀌는지 여부입니다.
        func differs(from clip: Clip) -> Bool {
            normalizedName != clip.name || isPinned != clip.isPinned
        }
    }

    struct Feedback: FeedbackPresentable, Equatable {
        let id: UUID
        let message: String
        let isSuccess: Bool
    }

    struct State: Sendable {
        /// 저장소에서 확정된 최신 원본입니다.
        var clip: Clip
        var draft: Draft
        var isSaving = false
        var isDeleting = false
        var isSavingToPhotos = false
        var previewData: Data?
        var isPreviewLoading = false
        var didFailPreview = false
        /// 삭제됐거나 다른 곳에서 삭제돼 화면을 닫아야 하는지 여부입니다.
        var isRemoved = false
        var isSaved = false
        var feedback: Feedback?

        init(clip: Clip) {
            self.clip = clip
            draft = Draft(clip: clip)
        }

        var image: ClipImageMetadata? {
            guard case .image(let image) = clip.content else { return nil }
            return image
        }

        var hasChanges: Bool {
            draft.differs(from: clip)
        }

        var canSave: Bool {
            hasChanges && !isSaving && !isDeleting && !isRemoved
        }
    }

    let initialState: State

    private let clipID: Clip.ID
    private let storage: any ClipStorageService
    private let clipboard: ClipboardService
    private let images: ClipImageService
    private let photos: ClipPhotoLibraryService

    init(
        clip: Clip,
        storage: any ClipStorageService,
        clipboard: ClipboardService,
        images: ClipImageService,
        photos: ClipPhotoLibraryService
    ) {
        initialState = State(clip: clip)
        clipID = clip.id
        self.storage = storage
        self.clipboard = clipboard
        self.images = images
        self.photos = photos
    }

    func mutate(action: Action) -> Observable<Mutation> {
        switch action {
        case .viewDidLoad:
            let storage = storage
            let id = clipID
            return ReactorEffect.stream { continuation in
                let changes = await storage.changes()
                // 구독을 등록한 뒤 다시 조회해 진입 이후에 확정된 변경을 놓치지 않습니다.
                await Self.load(storage: storage, id: id, into: continuation)
                for await event in changes {
                    switch event {
                    case .updated(let clip) where clip.id == id:
                        await Self.load(storage: storage, id: id, into: continuation)
                    case .deleted(let deleted) where deleted == id:
                        continuation.yield(.removed)
                    case .inserted, .updated, .deleted:
                        continue
                    }
                }
            }

        case .changeName(let name):
            return .just(.nameChanged(name))

        case .changePinned(let isPinned):
            return .just(.pinnedChanged(isPinned))

        case .save:
            // 변경이 없으면 저장소를 호출하지 않습니다.
            guard currentState.canSave else { return .empty() }
            let storage = storage
            let id = clipID
            let draft = currentState.draft
            let change = ClipUpdate.details(
                name: draft.normalizedName,
                memo: currentState.clip.memo,
                isPinned: draft.isPinned
            )
            let save = ReactorEffect.task { try await storage.update(id: id, change: change) }
                .map { Mutation.saved($0, UUID()) }
                .catch { error in
                    Self.isNotFound(error) ? .just(.removed) : .just(.saveFailed(UUID()))
                }
            return .concat([.just(.saveStarted), save])

        case .copy:
            guard !currentState.isDeleting, !currentState.isRemoved else { return .empty() }
            let clipboard = clipboard
            let id = clipID
            return ReactorEffect.task { try await clipboard.copy(id: id) }
                .map { Mutation.copyResult($0, UUID()) }
                .catch { _ in .just(.copyFailed(UUID())) }

        case .delete:
            guard !currentState.isDeleting, !currentState.isRemoved else { return .empty() }
            let images = images
            let id = clipID
            // 파일 정리가 보류돼도 DB 삭제는 확정된 결과로 처리합니다.
            let delete = ReactorEffect.task { _ = try await images.delete(id: id) }
                .map { Mutation.removed }
                .catch { error in
                    Self.isNotFound(error) ? .just(.removed) : .just(.deleteFailed(UUID()))
                }
            return .concat([.just(.deleteStarted), delete])

        case .saveToPhotos:
            guard !currentState.isSavingToPhotos, !currentState.isDeleting, !currentState.isRemoved else { return .empty() }
            let photos = photos
            let id = clipID
            let save = ReactorEffect.task { try await photos.save(id: id) }
                .map { Mutation.photoSaveResult($0, UUID()) }
                .catch { error in
                    Self.isNotFound(error) ? .just(.removed) : .just(.photoSaveFailed(UUID()))
                }
            return .concat([.just(.photoSaveStarted), save])

        case .previewRequested(let maximumPixelDimension):
            guard let image = currentState.image, !currentState.isRemoved else { return .empty() }
            let images = images
            let load = ReactorEffect.task {
                try await images.loadThumbnail(image, maximumPixelDimension: maximumPixelDimension)
            }
            .map { Mutation.previewLoaded(image, $0) }
            .catch { _ in .just(.previewFailed(image)) }
            return .concat([.just(.previewStarted(image)), load])

        case .dismissFeedback(let id):
            return .just(.feedbackDismissed(id))
        }
    }

    func reduce(
        state: State,
        mutation: Mutation
    ) -> State {
        var state = state
        switch mutation {
        case .clipLoaded(let clip):
            // 아직 편집하지 않은 초안만 새 원본에 맞춥니다. 편집 중인 값은 덮어쓰지 않습니다.
            let isUntouched = state.draft == Draft(clip: state.clip)
            if state.clip.content != clip.content {
                state.previewData = nil
                state.isPreviewLoading = false
                state.didFailPreview = false
            }
            state.clip = clip
            if isUntouched { state.draft = Draft(clip: clip) }

        case .removed:
            state.isSaving = false
            state.isDeleting = false
            state.isRemoved = true
            state.isSavingToPhotos = false

        case .nameChanged(let name):
            state.draft.name = name

        case .pinnedChanged(let isPinned):
            state.draft.isPinned = isPinned

        case .saveStarted:
            state.isSaving = true

        case .saved(let clip, let id):
            state.isSaving = false
            state.isSaved = true
            state.clip = clip
            // 저장 중에 더 편집하지 않았다면 입력 필드를 저장된 값으로 정리합니다.
            if !state.draft.differs(from: clip) { state.draft = Draft(clip: clip) }
            state.feedback = Feedback(
                id: id,
                message: "저장했습니다",
                isSuccess: true
            )

        case .saveFailed(let id):
            state.isSaving = false
            state.feedback = Feedback(
                id: id,
                message: "저장하지 못했습니다",
                isSuccess: false
            )

        case .copyResult(let result, let id):
            switch result {
            case .copied, .copiedWithoutLastUsedAt:
                state.feedback = Feedback(
                    id: id,
                    message: "클립보드에 복사했습니다",
                    isSuccess: true
                )
            case .writeNotObserved:
                state.feedback = Feedback(
                    id: id,
                    message: "클립보드에 복사하지 못했습니다",
                    isSuccess: false
                )
            }

        case .copyFailed(let id):
            state.feedback = Feedback(
                id: id,
                message: "클립보드에 복사하지 못했습니다",
                isSuccess: false
            )

        case .deleteStarted:
            state.isDeleting = true

        case .deleteFailed(let id):
            state.isDeleting = false
            state.feedback = Feedback(
                id: id,
                message: "삭제하지 못했습니다",
                isSuccess: false
            )

        case .photoSaveStarted:
            state.isSavingToPhotos = true

        case .photoSaveResult(let result, let id):
            state.isSavingToPhotos = false
            let message: String
            switch result {
            case .saved:
                message = "사진 앱에 저장했습니다"
            case .denied:
                message = "사진 추가 권한이 없습니다. 설정에서 허용해 주세요"
            case .restricted:
                message = "이 기기에서는 사진 추가가 제한되어 있습니다"
            }
            state.feedback = Feedback(
                id: id,
                message: message,
                isSuccess: result == .saved
            )

        case .photoSaveFailed(let id):
            state.isSavingToPhotos = false
            state.feedback = Feedback(
                id: id,
                message: "사진 앱에 저장하지 못했습니다",
                isSuccess: false
            )

        case .previewStarted(let image):
            guard state.image == image else { break }
            state.isPreviewLoading = true
            state.didFailPreview = false

        case .previewLoaded(let image, let data):
            guard state.image == image, !state.isRemoved else { break }
            state.previewData = data
            state.isPreviewLoading = false
            state.didFailPreview = false

        case .previewFailed(let image):
            guard state.image == image, !state.isRemoved else { break }
            state.isPreviewLoading = false
            state.didFailPreview = true

        case .feedbackDismissed(let id):
            if state.feedback?.id == id { state.feedback = nil }
        }
        return state
    }

    private static func isNotFound(_ error: any Error) -> Bool {
        guard let error = error as? ClipStorageError, case .notFound = error else { return false }
        return true
    }

    /// 저장소에서 최신 원본을 다시 읽습니다. 조회에 실패하면 현재 표시를 유지합니다. 항목이 없으면 삭제된 것으로 봅니다.
    private static func load(
        storage: any ClipStorageService,
        id: Clip.ID,
        into continuation: AsyncThrowingStream<Mutation, Error>.Continuation
    ) async {
        do {
            if let clip = try await storage.fetch(id: id) {
                continuation.yield(.clipLoaded(clip))
            } else {
                continuation.yield(.removed)
            }
        } catch {
            return
        }
    }
}
