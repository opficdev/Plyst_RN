//
//  FeedbackPresenter.swift
//  Plyst
//
//  Created by opfic on 10/1/26.
//

import Foundation

/// 피드백 표시를 한 번만 요청한 뒤 일정 시간이 지나면 상태를 비우도록 알립니다.
/// 같은 식별자의 피드백이 다시 전달돼도 토스트를 다시 띄우지 않습니다.
@MainActor
final class FeedbackPresenter {
    private let show: @MainActor (String, Bool) -> Void
    private let duration: Duration
    private let dismiss: @MainActor (UUID) -> Void
    private var presentedID: UUID?
    private var task: Task<Void, Never>?

    init(
        show: @escaping @MainActor (String, Bool) -> Void,
        duration: Duration = .seconds(2),
        dismiss: @escaping @MainActor (UUID) -> Void
    ) {
        self.show = show
        self.duration = duration
        self.dismiss = dismiss
    }

    /// feedback이 nil이면 아무 작업도 하지 않습니다. 마지막 식별자는 남겨 중복 표시를 막습니다.
    func update(_ feedback: (any FeedbackPresentable)?) {
        guard let feedback else { return }
        guard presentedID != feedback.id else { return }
        presentedID = feedback.id
        let id = feedback.id
        show(feedback.message, feedback.isSuccess)
        task?.cancel()
        // 화면이 해제돼도 타이머는 끝까지 진행합니다. 원래 Reactor에 피드백 상태를 비우도록 알립니다.
        task = Task { @MainActor [duration, dismiss] in
            try? await Task.sleep(for: duration)
            guard !Task.isCancelled else { return }
            dismiss(id)
        }
    }
}
