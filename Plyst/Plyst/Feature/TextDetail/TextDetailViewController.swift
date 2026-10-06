//
//  TextDetailViewController.swift
//  Plyst
//
//  Created by opfic on 10/1/26.
//

import ReactorKit
import RxSwift
import UIKit

/// 텍스트 클립의 상세 정보를 시트로 표시하고 편집합니다.
/// 닫는 동작은 스스로 dismiss하므로 내비게이션 스택에 의존하지 않습니다.
@MainActor
final class TextDetailViewController: ReactorViewController<TextDetailReactor> {
    private lazy var detailView = makeTextDetailView(makeSend())
    private let makeTextDetailView: @MainActor (@escaping @MainActor (TextDetailViewAction) -> Void) -> any TextDetailViewLike & ClipDetailLike
    /// 처음 나타날 때 이름 입력에 초점을 줄지 여부입니다.
    private let focusesName: Bool
    private let toastWindow: ToastWindow
    private lazy var feedbackPresenter = FeedbackPresenter(
        window: toastWindow,
        dismiss: { [reactor] in reactor.action.onNext(.dismissFeedback($0)) }
    )
    private var didFocusName = false
    private var didClose = false

    init(
        reactor: TextDetailReactor,
        toastWindow: ToastWindow,
        makeTextDetailView: @escaping @MainActor (@escaping @MainActor (TextDetailViewAction) -> Void) -> any TextDetailViewLike & ClipDetailLike,
        focusesName: Bool = false
    ) {
        self.toastWindow = toastWindow
        self.makeTextDetailView = makeTextDetailView
        self.focusesName = focusesName
        super.init(reactor: reactor)
        modalPresentationStyle = .pageSheet
        sheetPresentationController?.detents = [.large()]
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) is unavailable")
    }

    private func makeSend() -> @MainActor (TextDetailViewAction) -> Void {
        { [weak self] action in
            guard let self else { return }
            switch action {
            case .close:
                close()
            case .save:
                reactor.action.onNext(.save)
            case .copy:
                reactor.action.onNext(.copy)
            case .delete:
                confirmDelete()
            case .changeName(let name):
                reactor.action.onNext(.changeName(name))
            case .changeMemo(let memo):
                reactor.action.onNext(.changeMemo(memo))
            case .changePinned(let isPinned):
                reactor.action.onNext(.changePinned(isPinned))
            }
        }
    }

    override func loadView() {
        view = detailView
    }

    override func viewDidLoad() {
        super.viewDidLoad()
        reactor.action.onNext(.viewDidLoad)
    }

    override func viewDidAppear(_ animated: Bool) {
        super.viewDidAppear(animated)
        if focusesName, !didFocusName {
            didFocusName = true
            detailView.focusName()
        }
    }

    override func render(state: TextDetailReactor.State) {
        let clip = state.clip
        detailView.setContent(
            meta: "\(clip.isPinned ? "고정됨 · " : "")\(state.characterCount)자",
            text: state.text
        )
        detailView.setDraft(
            name: state.draft.name,
            memo: state.draft.memo,
            isPinned: state.draft.isPinned
        )
        detailView.setDates(
            saved: Self.dateText(clip.createdAt),
            lastUsed: clip.lastUsedAt.map(Self.dateText) ?? ""
        )
        detailView.setSaveEnabled(state.canSave)
        detailView.setBusy(state.isDeleting)
        feedbackPresenter.update(state.feedback)
        if state.isRemoved || state.isSaved { close() }
    }

    /// 날짜는 한국어 년월일 형식으로 표시하고 시각은 다음 줄에 표시합니다.
    private static func dateText(_ date: Date) -> String {
        let locale = Locale(identifier: "ko_KR")
        let day = date.formatted(.dateTime.year().month(.wide).day().locale(locale))
        let time = date.formatted(.dateTime.hour().minute().locale(locale))
        return "\(day)\n\(time)"
    }

    /// 저장하지 않은 초안은 Reactor와 함께 사라지므로 닫기만 하면 폐기됩니다.
    private func close() {
        guard !didClose else { return }
        didClose = true
        dismiss(animated: true)
    }

    private func confirmDelete() {
        let alert = ActionSheetViewController(
            title: "이 텍스트를 삭제할까요?",
            message: "삭제하면 되돌릴 수 없습니다.",
            items: [
                ActionSheetItem(
                    title: "삭제",
                    role: .destructive,
                    handler: { [weak self] in self?.reactor.action.onNext(.delete) }
                ),
                ActionSheetItem(title: "취소", role: .cancel)
            ]
        )
        present(alert, animated: true)
    }
}
