//
//  SearchReactor.swift
//  Plyst
//
//  Created by opfic on 9/30/26.
//

import Foundation
import ReactorKit
import RxSwift

final class SearchReactor: Reactorable {
    enum Action: Sendable {
        case viewDidLoad
        case timeChanged(Date)
        case changeQuery(String)
        case submitQuery
        case selectRecentTerm(String)
        case removeRecentTerm(String)
        case clearRecentTerms
        case selectFilter(HomeFilter)
        case copy(Clip.ID)
        case dismissFeedback(UUID)
        case thumbnailRequested(HomeThumbnailKey)
        case thumbnailCancelled(HomeThumbnailKey)
    }

    enum Mutation: Sendable {
        case clipsLoaded([Clip], Date)
        case loadFailed
        case timeChanged(Date)
        case queryChanged(String)
        case filterSelected(HomeFilter)
        case searchHistoryLoaded(ClipSearchHistory)
        case searchHistoryLoadFailed
        case searchHistoryWriteFailed(UUID)
        case copyResult(ClipboardCopyResult, UUID)
        case copyFailed(UUID)
        case feedbackDismissed(UUID)
        case thumbnailStarted(HomeThumbnailKey)
        case thumbnailLoaded(HomeThumbnailKey, Data)
        case thumbnailFailed(HomeThumbnailKey)
        case thumbnailCancelled(HomeThumbnailKey)
    }

    enum LoadPhase: Sendable {
        case initial
        case loaded
        case failed
    }

    enum SearchHistoryPhase: Sendable {
        case initial
        case loaded
        case failed
    }

    struct Feedback: FeedbackPresentable, Equatable {
        let id: UUID
        let message: String
        let isSuccess: Bool
    }

    struct State: Sendable {
        var clips = [Clip]()
        /// 초기값만 여기서 정하고, 이후에는 Mutation이 전달한 값만 씁니다.
        var now = Date()
        var loadPhase = LoadPhase.initial
        var query = ""
        var filter = HomeFilter.all
        /// clips, query, filter, now가 바뀔 때마다 refreshContent로 다시 계산하는 파생 값입니다.
        var content = SearchContent.empty
        var searchHistory = ClipSearchHistory()
        var searchHistoryPhase = SearchHistoryPhase.initial
        var feedback: Feedback?
        var thumbnails = [HomeThumbnailKey: Data]()
        var thumbnailOrder = [HomeThumbnailKey]()
        var loadingThumbnails = Set<HomeThumbnailKey>()
        var failedThumbnails = Set<HomeThumbnailKey>()
    }

    let initialState = State()

    private let storage: any ClipStorageService
    private let history: any ClipSearchHistoryStorageService
    private let clipboard: ClipboardService
    private let images: ClipImageService
    /// 최근 검색어 쓰기를 넣은 순서대로 하나씩 실행하는 큐입니다. 응답이 요청과 다른 순서로 도착해 오래된 목록이 최신 목록을 덮어쓰지 않게 합니다.
    /// 원소는 mutate에서 만든 cold effect이며, 큐에는 메인 스레드에서만 넣습니다.
    private let historyOperations = PublishSubject<Observable<Mutation>>()

    init(
        storage: any ClipStorageService,
        history: any ClipSearchHistoryStorageService,
        clipboard: ClipboardService,
        images: ClipImageService
    ) {
        self.storage = storage
        self.history = history
        self.clipboard = clipboard
        self.images = images
    }

    func transform(mutation: Observable<Mutation>) -> Observable<Mutation> {
        // Reactorable의 기본 구현을 대체하므로 메인 스케줄러 전달을 여기서 다시 보장합니다.
        Observable.merge(mutation, historyOperations.concat())
            .observe(on: MainScheduler.instance)
    }

    func mutate(action: Action) -> Observable<Mutation> {
        switch action {
        case .viewDidLoad:
            let storage = storage
            let history = history
            // 최초 조회도 큐의 첫 작업으로 넣어 이후의 쓰기 결과를 덮어쓰지 않게 합니다.
            historyOperations.onNext(
                ReactorEffect.task { try await history.fetchSearchHistory() }
                    .map { Mutation.searchHistoryLoaded($0) }
                    .catch { _ in .just(.searchHistoryLoadFailed) }
            )
            return ReactorEffect.stream { continuation in
                let changes = await storage.changes()
                await Self.load(storage: storage, into: continuation)
                for await _ in changes {
                    await Self.load(storage: storage, into: continuation)
                }
            }

        case .timeChanged(let now):
            return .just(.timeChanged(now))

        case .changeQuery(let query):
            return .just(.queryChanged(query))

        case .selectRecentTerm(let term):
            return .just(.queryChanged(term))

        case .submitQuery:
            guard let query = ClipSearchQuery(currentState.query) else { return .empty() }
            let history = history
            enqueueUserOperation(
                ReactorEffect.task { try await history.recordSearchTerm(query) }
            )
            return .empty()

        case .removeRecentTerm(let term):
            let history = history
            enqueueUserOperation(
                ReactorEffect.task { try await history.removeSearchTerm(term) }
            )
            return .empty()

        case .clearRecentTerms:
            let history = history
            enqueueUserOperation(
                ReactorEffect.task {
                    try await history.removeAllSearchTerms()
                    return ClipSearchHistory()
                }
            )
            return .empty()

        case .selectFilter(let filter):
            guard currentState.filter != filter else { return .empty() }
            return .just(.filterSelected(filter))

        case .copy(let id):
            // 복사 시점의 검색어를 캡처합니다. 복사 성공 뒤 기록에 쓰입니다.
            let query = ClipSearchQuery(currentState.query)
            let clipboard = clipboard
            let history = history
            return ReactorEffect.task { try await clipboard.copy(id: id) }
                .map { Mutation.copyResult($0, UUID()) }
                .catch { _ in .just(.copyFailed(UUID())) }
                // Task 스레드가 아니라 메인 스레드에서 큐에 넣습니다.
                .observe(on: MainScheduler.instance)
                .do(onNext: { [weak self] mutation in
                    guard let self, let query, case .copyResult(let result, _) = mutation else { return }
                    switch result {
                    case .copied, .copiedWithoutLastUsedAt:
                        // 복사 결과는 이미 전달됐으므로 기록 실패는 알리지 않습니다.
                        historyOperations.onNext(
                            ReactorEffect.task { try await history.recordSearchTerm(query) }
                                .map { Mutation.searchHistoryLoaded($0) }
                                .catch { _ in .empty() }
                        )
                    case .writeNotObserved:
                        break
                    }
                })

        case .dismissFeedback(let id):
            return .just(.feedbackDismissed(id))

        case .thumbnailRequested(let key):
            guard 0 < key.maximumPixelDimension,
                  currentState.thumbnails[key] == nil,
                  !currentState.loadingThumbnails.contains(key),
                  !currentState.failedThumbnails.contains(key),
                  let clip = currentState.clips.first(where: { $0.id == key.clipID }),
                  case .image(let image) = clip.content,
                  image.fileID == key.fileID else { return .empty() }

            let images = images
            let cancelled = self.action.filter { action in
                guard case .thumbnailCancelled(let other) = action else { return false }
                return other == key
            }
            let effect = ReactorEffect.task {
                try await images.loadThumbnail(image, maximumPixelDimension: key.maximumPixelDimension)
            }
            .map { Mutation.thumbnailLoaded(key, $0) }
            .catch { _ in .just(.thumbnailFailed(key)) }
            .take(until: cancelled)
            return .concat([
                .just(.thumbnailStarted(key)),
                effect
            ])

        case .thumbnailCancelled(let key):
            return .just(.thumbnailCancelled(key))
        }
    }

    func reduce(
        state: State,
        mutation: Mutation
    ) -> State {
        var state = state
        switch mutation {
        case .clipsLoaded(let clips, let now):
            state.clips = clips
            state.now = now
            state.loadPhase = .loaded
            let valid = Set(clips.compactMap { clip -> UUID? in
                guard case .image(let image) = clip.content else { return nil }
                return image.fileID
            })
            state.thumbnails = state.thumbnails.filter { valid.contains($0.key.fileID) }
            state.thumbnailOrder.removeAll { !valid.contains($0.fileID) }
            state.loadingThumbnails = state.loadingThumbnails.filter { valid.contains($0.fileID) }
            state.failedThumbnails = state.failedThumbnails.filter { valid.contains($0.fileID) }
            Self.refreshContent(&state)

        case .loadFailed:
            state.loadPhase = .failed

        case .timeChanged(let now):
            state.now = now
            Self.refreshContent(&state)

        case .queryChanged(let query):
            state.query = query
            Self.refreshContent(&state)

        case .filterSelected(let filter):
            state.filter = filter
            Self.refreshContent(&state)

        case .searchHistoryLoaded(let history):
            state.searchHistory = history
            state.searchHistoryPhase = .loaded

        case .searchHistoryLoadFailed:
            state.searchHistoryPhase = .failed

        case .searchHistoryWriteFailed(let id):
            state.feedback = Feedback(
                id: id,
                message: "최근 검색어를 변경하지 못했습니다",
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

        case .feedbackDismissed(let id):
            if state.feedback?.id == id { state.feedback = nil }

        case .thumbnailStarted(let key):
            state.loadingThumbnails.insert(key)

        case .thumbnailLoaded(let key, let data):
            guard state.loadingThumbnails.remove(key) != nil,
                  state.clips.contains(where: { clip in
                      guard clip.id == key.clipID, case .image(let image) = clip.content else { return false }
                      return image.fileID == key.fileID
                  }) else { return state }
            state.thumbnails[key] = data
            state.thumbnailOrder.removeAll { $0 == key }
            state.thumbnailOrder.append(key)
            while 48 < state.thumbnailOrder.count {
                let oldest = state.thumbnailOrder.removeFirst()
                state.thumbnails.removeValue(forKey: oldest)
            }

        case .thumbnailFailed(let key):
            state.loadingThumbnails.remove(key)
            state.failedThumbnails.insert(key)

        case .thumbnailCancelled(let key):
            state.loadingThumbnails.remove(key)
        }
        return state
    }

    /// 사용자가 직접 요청한 최근 검색어 쓰기를 큐에 넣습니다. 실패하면 토스트로 알립니다.
    private func enqueueUserOperation(_ effect: Observable<ClipSearchHistory>) {
        historyOperations.onNext(
            effect
                .map { Mutation.searchHistoryLoaded($0) }
                .catch { _ in .just(.searchHistoryWriteFailed(UUID())) }
        )
    }

    private static func refreshContent(_ state: inout State) {
        state.content = SearchContent.make(
            from: state.clips,
            query: ClipSearchQuery(state.query),
            filter: state.filter,
            now: state.now
        )
    }

    private static func load(
        storage: any ClipStorageService,
        into continuation: AsyncThrowingStream<Mutation, Error>.Continuation
    ) async {
        do {
            let clips = try await storage.fetchAll(order: .createdAt)
            continuation.yield(.clipsLoaded(clips, Date()))
        } catch is CancellationError {
            return
        } catch {
            continuation.yield(.loadFailed)
        }
    }
}
