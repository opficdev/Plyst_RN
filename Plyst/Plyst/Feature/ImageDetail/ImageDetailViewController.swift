//
//  ImageDetailViewController.swift
//  Plyst
//
//  Created by opfic on 10/1/26.
//

import ReactorKit
import RxSwift
import UIKit

@MainActor
final class ImageDetailViewController: ReactorViewController<ImageDetailReactor> {
    private lazy var detailView = makeImageDetailView(makeSend())
    private let makeImageDetailView: @MainActor (@escaping @MainActor (ImageDetailViewAction) -> Void) -> any ImageDetailViewLike & ClipDetailLike
    private let showToast: @MainActor (String, Bool) -> Void
    private lazy var feedbackPresenter = FeedbackPresenter(
        show: showToast,
        dismiss: { [reactor] in reactor.action.onNext(.dismissFeedback($0)) }
    )
    private var requestedImage: ClipImageMetadata?
    private var renderedData: Data?
    private var preview: UIImage?
    private var didClose = false

    init(
        reactor: ImageDetailReactor,
        showToast: @escaping @MainActor (String, Bool) -> Void,
        makeImageDetailView: @escaping @MainActor (@escaping @MainActor (ImageDetailViewAction) -> Void) -> any ImageDetailViewLike & ClipDetailLike
    ) {
        self.showToast = showToast
        self.makeImageDetailView = makeImageDetailView
        super.init(reactor: reactor)
        modalPresentationStyle = .pageSheet
        sheetPresentationController?.detents = [.large()]
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) is unavailable")
    }

    override func loadView() {
        view = detailView
    }

    override func viewDidLoad() {
        super.viewDidLoad()
        reactor.action.onNext(.viewDidLoad)
    }

    override func render(state: ImageDetailReactor.State) {
        if state.isRemoved || state.isSaved {
            close()
            return
        }
        if requestedImage != state.image {
            requestedImage = state.image
            reactor.action.onNext(.previewRequested(1600))
        }
        if renderedData != state.previewData {
            renderedData = state.previewData
            preview = state.previewData.flatMap { UIImage(data: $0) }
        }
        if let image = state.image {
            let size = ByteCountFormatter.string(fromByteCount: Int64(image.byteCount), countStyle: .file)
            detailView.setContent(meta: "\(image.pixelWidth) × \(image.pixelHeight) px, \(size)")
        }
        detailView.setPreview(
            preview,
            isLoading: state.isPreviewLoading,
            didFail: state.didFailPreview || (state.previewData != nil && preview == nil)
        )
        detailView.setDraft(name: state.draft.name, isPinned: state.draft.isPinned)
        detailView.setDates(
            saved: Self.dateText(state.clip.createdAt),
            lastUsed: state.clip.lastUsedAt.map(Self.dateText) ?? ""
        )
        detailView.setSaveEnabled(state.canSave)
        detailView.setBusy(state.isDeleting)
        detailView.setSavingToPhotos(state.isSavingToPhotos)
        feedbackPresenter.update(state.feedback)
    }

    private func makeSend() -> @MainActor (ImageDetailViewAction) -> Void {
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
            case .saveToPhotos:
                reactor.action.onNext(.saveToPhotos)
            case .changeName(let name):
                reactor.action.onNext(.changeName(name))
            case .changePinned(let isPinned):
                reactor.action.onNext(.changePinned(isPinned))
            }
        }
    }

    private static func dateText(_ date: Date) -> String {
        let locale = Locale(identifier: "ko_KR")
        let day = date.formatted(.dateTime.year().month(.wide).day().locale(locale))
        let time = date.formatted(.dateTime.hour().minute().locale(locale))
        return "\(day)\n\(time)"
    }

    private func close() {
        guard !didClose else { return }
        didClose = true
        // 저장하지 않은 초안은 Reactor와 함께 폐기됩니다.
        dismiss(animated: true)
    }

    private func confirmDelete() {
        let alert = ActionSheetViewController(
            title: "이 이미지를 삭제할까요?",
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
