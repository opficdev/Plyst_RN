//
//  FeedbackPresenter.swift
//  Plyst
//
//  Created by opfic on 10/1/26.
//

import UIKit

/// Scene의 토스트 창에 피드백을 한 번만 표시한 뒤 일정 시간이 지나면 닫도록 알립니다.
/// 같은 식별자의 피드백이 다시 전달돼도 토스트를 다시 띄우지 않습니다.
@MainActor
final class FeedbackPresenter {
    private let window: ToastWindow
    private let successColor: UIColor
    private let failureColor: UIColor
    private let duration: Duration
    private let dismiss: @MainActor (UUID) -> Void
    private var presentedID: UUID?
    private var task: Task<Void, Never>?

    init(
        window: ToastWindow,
        duration: Duration = .seconds(2),
        successColor: UIColor = UIColor(resource: .homeFeedbackSuccess),
        failureColor: UIColor = UIColor(resource: .homeFeedbackFailure),
        dismiss: @escaping @MainActor (UUID) -> Void
    ) {
        self.window = window
        self.successColor = successColor
        self.failureColor = failureColor
        self.duration = duration
        self.dismiss = dismiss
    }

    /// feedback이 nil이면 자신이 표시한 토스트만 숨깁니다. 마지막 식별자는 남겨 중복 표시를 막습니다.
    func update(_ feedback: (any FeedbackPresentable)?) {
        guard let feedback else {
            if let presentedID { window.hide(id: presentedID) }
            return
        }
        guard presentedID != feedback.id else { return }
        presentedID = feedback.id
        let id = feedback.id
        window.show(
            id: id,
            message: feedback.message,
            backgroundColor: feedback.isSuccess ? successColor : failureColor
        )
        task?.cancel()
        // 화면이 해제돼도 타이머는 끝까지 진행합니다. 창은 약하게 참조하고 원래 Reactor에 닫기를 알립니다.
        task = Task { @MainActor [weak window, duration, dismiss] in
            try? await Task.sleep(for: duration)
            guard !Task.isCancelled else { return }
            window?.hide(id: id)
            dismiss(id)
        }
    }
}
