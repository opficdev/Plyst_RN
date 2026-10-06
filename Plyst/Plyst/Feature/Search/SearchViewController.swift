//
//  SearchViewController.swift
//  Plyst
//
//  Created by opfic on 9/30/26.
//

import ReactorKit
import RxSwift
import UIKit

@MainActor
final class SearchViewController: ReactorViewController<SearchReactor> {
    private struct CardDisplay {
        let result: SearchResult
        let name: NSAttributedString?
        let body: NSAttributedString?
    }

    private struct RecentDisplay: Equatable {
        let terms: [String]
        let message: String?
        let showsClear: Bool
    }

    private lazy var searchView = makeSearchView(makeSend())
    private var collectionView: UICollectionView { searchView.collectionView }
    private let thumbnails = ThumbnailImageCache(countLimit: 48)
    private lazy var timeline = HomeTimelineScheduler { [weak self] now in
        self?.reactor.action.onNext(.timeChanged(now))
    }

    private let makeSearchView: @MainActor (@escaping @MainActor (SearchViewAction) -> Void) -> any SearchViewLike & ClipGridLike
    private let makeDetailViewController: @MainActor (Clip) -> UIViewController
    private let cancel: @MainActor () -> Void

    private var displays = [CardDisplay]()
    private var renderedContent: SearchContent?
    private var renderedNow: Date?
    private var renderedClips = [Clip]()
    private var renderedFilter: HomeFilter?
    private var renderedRecent: RecentDisplay?
    private let toastWindow: ToastWindow
    private lazy var feedbackPresenter = FeedbackPresenter(
        window: toastWindow,
        dismiss: { [reactor] in reactor.action.onNext(.dismissFeedback($0)) }
    )
    private var didEnter = false

    /// 취소 동작은 내비게이션 스택에 의존하지 않고 표시한 쪽이 넘긴 cancel로 전달한다.
    init(
        reactor: SearchReactor,
        toastWindow: ToastWindow,
        makeSearchView: @escaping @MainActor (@escaping @MainActor (SearchViewAction) -> Void) -> any SearchViewLike & ClipGridLike,
        makeDetailViewController: @escaping @MainActor (Clip) -> UIViewController,
        cancel: @escaping @MainActor () -> Void
    ) {
        self.toastWindow = toastWindow
        self.makeSearchView = makeSearchView
        self.makeDetailViewController = makeDetailViewController
        self.cancel = cancel
        super.init(reactor: reactor)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) is unavailable")
    }

    private func makeSend() -> @MainActor (SearchViewAction) -> Void {
        { [weak self] action in
            guard let self else { return }
            switch action {
            case .changeQuery(let query):
                reactor.action.onNext(.changeQuery(query))
            case .submit:
                reactor.action.onNext(.submitQuery)
            case .cancel:
                // 서치바를 접는 모션이 끝난 뒤에 표시한 쪽이 이 화면을 제거한다.
                searchView.collapse(completion: cancel)
            case .selectFilter(let filter):
                reactor.action.onNext(.selectFilter(filter))
            case .selectRecentTerm(let term):
                reactor.action.onNext(.selectRecentTerm(term))
            case .removeRecentTerm(let term):
                reactor.action.onNext(.removeRecentTerm(term))
            case .clearRecentTerms:
                reactor.action.onNext(.clearRecentTerms)
            }
        }
    }

    override func loadView() {
        searchView.collectionView.dataSource = self
        searchView.collectionView.delegate = self
        searchView.layout.delegate = self
        view = searchView
    }

    override func viewDidLoad() {
        super.viewDidLoad()
        reactor.action.onNext(.viewDidLoad)
    }

    override func viewDidAppear(_ animated: Bool) {
        super.viewDidAppear(animated)
        timeline.appear()
        if !didEnter {
            didEnter = true
            searchView.focusSearchField()
            searchView.expand()
        }
    }

    override func viewWillDisappear(_ animated: Bool) {
        super.viewWillDisappear(animated)
        timeline.disappear()
    }

    override func render(state: SearchReactor.State) {
        let content = state.content
        if renderedContent != content || renderedNow != state.now {
            renderedContent = content
            renderedNow = state.now
            displays = content.results.map {
                CardDisplay(
                    result: $0,
                    name: SearchCardText.name(for: $0),
                    body: SearchCardText.body(for: $0)
                )
            }
            searchView.reloadContent()
        }
        if renderedClips != state.clips {
            renderedClips = state.clips
            timeline.update(clips: state.clips)
        }

        searchView.setQuery(state.query)
        if renderedFilter != state.filter {
            let isFilterSwitch = renderedFilter != nil
            renderedFilter = state.filter
            searchView.setSelectedFilter(state.filter)
            if isFilterSwitch { searchView.scrollToTop() }
        }

        renderRecent(state: state)
        renderMode(state: state, content: content)
        updateVisibleThumbnails(state: state)
        feedbackPresenter.update(state.feedback)
    }

    private func renderRecent(state: SearchReactor.State) {
        let display: RecentDisplay
        switch state.searchHistoryPhase {
        case .initial:
            display = RecentDisplay(
                terms: [],
                message: nil,
                showsClear: false
            )
        case .loaded:
            let terms = state.searchHistory.terms
            display = RecentDisplay(
                terms: terms,
                message: terms.isEmpty ? "최근 검색어가 없어요." : nil,
                showsClear: !terms.isEmpty
            )
        case .failed:
            // 저장값이 손상돼도 전체 삭제로 복구할 수 있게 지우기를 남깁니다.
            display = RecentDisplay(
                terms: [],
                message: "최근 검색어를 불러오지 못했어요.",
                showsClear: true
            )
        }
        guard renderedRecent != display else { return }
        renderedRecent = display
        searchView.setRecent(terms: display.terms, message: display.message, showsClear: display.showsClear)
    }

    private func renderMode(
        state: SearchReactor.State,
        content: SearchContent
    ) {
        guard let query = content.query else {
            searchView.showRecent()
            return
        }
        switch state.loadPhase {
        case .initial:
            searchView.showResults()
        case .loaded:
            if content.results.isEmpty {
                searchView.showEmptyState(
                    title: "‘\(query.text)’ 결과 없음",
                    message: Self.emptyMessage(for: state.filter)
                )
            } else {
                searchView.showResults()
            }
        case .failed:
            if state.clips.isEmpty {
                searchView.showEmptyState(
                    title: "기록을 불러오지 못했습니다",
                    message: "앱을 다시 열어 기록을 확인해 주세요"
                )
            } else if content.results.isEmpty {
                searchView.showEmptyState(
                    title: "‘\(query.text)’ 결과 없음",
                    message: Self.emptyMessage(for: state.filter)
                )
            } else {
                searchView.showResults()
            }
        }
    }

    private static func emptyMessage(for filter: HomeFilter) -> String {
        switch filter {
        case .all: "이미지는 이름과 저장 시각으로만 찾을 수 있어요."
        case .text, .image, .pinned: "필터를 ‘전체’로 바꾸거나 다른 단어로 검색해 보세요."
        }
    }

    private func updateVisibleThumbnails(state: SearchReactor.State) {
        for cell in collectionView.visibleCells {
            guard let cell = cell as? any HomeImageCellLike,
                  let key = cell.representedKey else { continue }
            let phase = thumbnails.phase(for: key, data: state.thumbnails, failed: state.failedThumbnails)
            if !phase.isPending { cell.setThumbnail(phase) }
        }
    }

    private func thumbnailKey(
        for clip: Clip,
        width: CGFloat
    ) -> HomeThumbnailKey? {
        guard case .image(let image) = clip.content else { return nil }
        let pixels = max(1, Int(ceil((width - 12) * traitCollection.displayScale)))
        return HomeThumbnailKey(
            clipID: clip.id,
            fileID: image.fileID,
            maximumPixelDimension: pixels
        )
    }

    private func headerTitle() -> String {
        guard let content = renderedContent else { return "" }
        let title = "결과 \(content.results.count)개"
        guard 0 < content.textCount, 0 < content.imageCount else { return title }
        return "\(title) · 텍스트 \(content.textCount) · 이미지 \(content.imageCount)"
    }
}

extension SearchViewController: UICollectionViewDataSource, UICollectionViewDelegate, HomeGridLayoutDelegate {
    func numberOfSections(in collectionView: UICollectionView) -> Int {
        displays.isEmpty ? 0 : 1
    }

    func collectionView(
        _ collectionView: UICollectionView,
        numberOfItemsInSection section: Int
    ) -> Int {
        displays.count
    }

    func collectionView(
        _ collectionView: UICollectionView,
        cellForItemAt indexPath: IndexPath
    ) -> UICollectionViewCell {
        let display = displays[indexPath.item]
        let clip = display.result.clip
        let copy = { [weak self] in
            guard let self else { return }
            reactor.action.onNext(.copy(clip.id))
        }
        switch clip.content {
        case .text:
            guard let cell = collectionView.dequeueReusableCell(
                withReuseIdentifier: searchView.textCellType.reuseIdentifier,
                for: indexPath
            ) as? any HomeTextCellLike else { preconditionFailure("\(searchView.textCellType) registration mismatch") }
            cell.configure(
                with: clip,
                now: reactor.currentState.now,
                name: display.name,
                body: display.body,
                onCopy: copy
            )
            return cell
        case .image:
            guard let cell = collectionView.dequeueReusableCell(
                withReuseIdentifier: searchView.imageCellType.reuseIdentifier,
                for: indexPath
            ) as? any HomeImageCellLike else { preconditionFailure("\(searchView.imageCellType) registration mismatch") }
            let width = max(1, (collectionView.bounds.width - 42) / 2)
            if let key = thumbnailKey(for: clip, width: width) {
                cell.configure(
                    with: clip,
                    now: reactor.currentState.now,
                    key: key,
                    thumbnail: thumbnails.phase(for: key, data: reactor.currentState.thumbnails, failed: reactor.currentState.failedThumbnails),
                    name: display.name,
                    onCopy: copy
                )
            }
            return cell
        }
    }

    func collectionView(
        _ collectionView: UICollectionView,
        viewForSupplementaryElementOfKind kind: String,
        at indexPath: IndexPath
    ) -> UICollectionReusableView {
        guard let header = collectionView.dequeueReusableSupplementaryView(
            ofKind: kind,
            withReuseIdentifier: searchView.sectionHeaderType.reuseIdentifier,
            for: indexPath
        ) as? any HomeSectionHeaderViewLike else { preconditionFailure("\(searchView.sectionHeaderType) registration mismatch") }
        header.configure(title: headerTitle())
        return header
    }

    func collectionView(
        _ collectionView: UICollectionView,
        didSelectItemAt indexPath: IndexPath
    ) {
        let clip = displays[indexPath.item].result.clip
        // 이미 상세 화면이 떠 있으면 다시 열지 않습니다.
        guard presentedViewController == nil else { return }
        // 검색 입력의 키보드가 시트 위에 남지 않게 내립니다.
        searchView.endEditing(true)
        present(makeDetailViewController(clip), animated: true)
    }

    func collectionView(
        _ collectionView: UICollectionView,
        willDisplay cell: UICollectionViewCell,
        forItemAt indexPath: IndexPath
    ) {
        guard let cell = cell as? any HomeImageCellLike,
              let key = cell.representedKey,
              reactor.currentState.thumbnails[key] == nil else { return }
        reactor.action.onNext(.thumbnailRequested(key))
    }

    func collectionView(
        _ collectionView: UICollectionView,
        didEndDisplaying cell: UICollectionViewCell,
        forItemAt indexPath: IndexPath
    ) {
        guard let cell = cell as? any HomeImageCellLike,
              let key = cell.representedKey else { return }
        Task { @MainActor [weak self] in
            guard let self,
                  !self.collectionView.visibleCells.contains(where: { ($0 as? any HomeImageCellLike)?.representedKey == key }) else { return }
            self.reactor.action.onNext(.thumbnailCancelled(key))
        }
    }

    func homeLayout(
        _ layout: HomeGridLayout,
        heightForItemAt indexPath: IndexPath,
        width: CGFloat
    ) -> CGFloat {
        let display = displays[indexPath.item]
        switch display.result.clip.content {
        case .text:
            return searchView.textCellType.height(
                for: display.result.clip,
                width: width,
                name: display.name,
                body: display.body,
                showsCopy: true
            )
        case .image:
            return searchView.imageCellType.height(
                for: display.result.clip,
                width: width,
                name: display.name,
                showsCopy: true
            )
        }
    }
}
