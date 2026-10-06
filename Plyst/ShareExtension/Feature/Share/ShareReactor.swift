//
//  ShareReactor.swift
//  ShareExtension
//
//  Created by opfic on 10/1/26.
//

import ReactorKit
import RxSwift

/// 공유 항목을 클립으로 저장하는 흐름을 관리합니다.
final class ShareReactor: Reactorable {
    enum Action: Sendable {
        /// 처음 저장과 다시 시도에 함께 사용합니다.
        case save
        case cancel
    }

    enum Mutation: Sendable {
        case saveStarted
        case saveFinished(ClipShareSaveResult)
        case saveFailed
    }

    struct State: Sendable {
        var status = ShareStatus.saving
        var isSaving = false
    }

    let initialState = State()

    private let item: ClipShareItem
    private let service: ClipShareService

    init(
        item: ClipShareItem,
        service: ClipShareService
    ) {
        self.item = item
        self.service = service
    }

    func mutate(action: Action) -> Observable<Mutation> {
        switch action {
        case .save:
            guard !currentState.isSaving, currentState.status != .completed else { return .empty() }
            let item = item
            let service = service
            let cancelled = self.action.filter { action in
                guard case .cancel = action else { return false }
                return true
            }
            let effect = ReactorEffect.task {
                try await service.save(item)
            }
            .map { Mutation.saveFinished($0) }
            .catch { _ in .just(.saveFailed) }
            .take(until: cancelled)
            return .concat([
                .just(.saveStarted),
                effect
            ])

        case .cancel:
            // 진행 중인 저장은 save의 take(until:)이 중단합니다.
            return .empty()
        }
    }

    func reduce(
        state: State,
        mutation: Mutation
    ) -> State {
        var state = state
        switch mutation {
        case .saveStarted:
            state.isSaving = true
            state.status = .saving
        case .saveFinished(let result):
            state.isSaving = false
            if case .saved = result {
                state.status = .completed
            } else {
                state.status = .failed
            }
        case .saveFailed:
            state.isSaving = false
            state.status = .failed
        }
        return state
    }
}
