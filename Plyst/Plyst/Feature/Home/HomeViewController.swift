//
//  HomeViewController.swift
//  Plyst
//
//  Created by opfic on 9/30/26.
//

import ReactorKit
import RxSwift
import UIKit

@MainActor
final class HomeViewController: ReactorViewController<HomeReactor> {
    private lazy var homeView = makeHomeView(makeSend())
    private var collectionView: UICollectionView { homeView.collectionView }
    private let thumbnails = ThumbnailImageCache(countLimit: 48)
    private lazy var timeline = HomeTimelineScheduler { [weak self] now in
        self?.reactor.action.onNext(.timeChanged(now))
    }

    private var sections = [HomeSection]()
    private var pinnedClips = [Clip]()
    private var renderedNow: Date?
    private var renderedFilter: HomeFilter?
    private let showToast: @MainActor (String, Bool) -> Void
    private lazy var feedbackPresenter = FeedbackPresenter(
        show: showToast,
        dismiss: { [reactor] in reactor.action.onNext(.dismissFeedback($0)) }
    )
    private let makeHomeView: @MainActor (@escaping @MainActor (HomeViewAction) -> Void) -> any HomeViewLike & ClipGridLike
    private let makeSearchViewController: @MainActor (@escaping @MainActor () -> Void) -> UIViewController
    let makeDetailViewController: @MainActor (Clip) -> UIViewController
    private var searchViewController: UIViewController?

    /// 상단 고정 항목이 있으면 section 0을 그 전용으로 두어 시간순 구간이 없어도 표시되게 한다.
    private var pinnedRowSectionCount: Int { pinnedClips.isEmpty ? 0 : 1 }

    init(
        reactor: HomeReactor,
        showToast: @escaping @MainActor (String, Bool) -> Void,
        makeHomeView: @escaping @MainActor (@escaping @MainActor (HomeViewAction) -> Void) -> any HomeViewLike & ClipGridLike,
        makeSearchViewController: @escaping @MainActor (@escaping @MainActor () -> Void) -> UIViewController,
        makeDetailViewController: @escaping @MainActor (Clip) -> UIViewController
    ) {
        self.showToast = showToast
        self.makeHomeView = makeHomeView
        self.makeSearchViewController = makeSearchViewController
        self.makeDetailViewController = makeDetailViewController
        super.init(reactor: reactor)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) is unavailable")
    }

    override func loadView() {
        homeView.collectionView.dataSource = self
        homeView.collectionView.delegate = self
        homeView.layout.delegate = self
        view = homeView
    }

    override func viewDidLoad() {
        super.viewDidLoad()
        reactor.action.onNext(.viewDidLoad)
    }

    override func viewDidAppear(_ animated: Bool) {
        super.viewDidAppear(animated)
        timeline.appear()
    }

    override func viewWillDisappear(_ animated: Bool) {
        super.viewWillDisappear(animated)
        timeline.disappear()
    }

    override func render(state: HomeReactor.State) {
        let content = state.content
        let contentChanged = sections != content.sections || pinnedClips != content.pinnedClips
        if contentChanged || renderedNow != state.now {
            sections = content.sections
            pinnedClips = content.pinnedClips
            renderedNow = state.now
            homeView.reloadContent()
        }
        if contentChanged { timeline.update(clips: state.clips) }

        if renderedFilter != state.filter {
            let isFilterSwitch = renderedFilter != nil
            renderedFilter = state.filter
            homeView.setSelectedFilter(state.filter)
            if isFilterSwitch { homeView.scrollToTop() }
        }

        switch state.loadPhase {
        case .initial:
            homeView.hideEmptyState()
        case .loaded:
            if state.clips.isEmpty {
                homeView.showEmptyState(title: HomeFilter.all.emptyTitle, message: HomeFilter.all.emptyMessage)
            } else if content.isEmpty {
                homeView.showEmptyState(title: state.filter.emptyTitle, message: state.filter.emptyMessage)
            } else {
                homeView.hideEmptyState()
            }
        case .failed:
            if state.clips.isEmpty {
                homeView.showEmptyState(
                    title: "기록을 불러오지 못했습니다",
                    message: "앱을 다시 열어 기록을 확인해 주세요"
                )
            } else {
                homeView.hideEmptyState()
            }
        }

        homeView.setSaving(state.isSaving)
        updateVisibleThumbnails(state: state)
        feedbackPresenter.update(state.feedback)
    }

    private func updateVisibleThumbnails(state: HomeReactor.State) {
        for cell in collectionView.visibleCells {
            guard let cell = cell as? any HomeImageCellLike,
                  let key = cell.representedKey else { continue }
            let phase = thumbnails.phase(for: key, data: state.thumbnails, failed: state.failedThumbnails)
            if !phase.isPending { cell.setThumbnail(phase) }
        }
        for view in collectionView.visibleSupplementaryViews(ofKind: HomeGridLayout.pinnedRowKind) {
            guard let row = view as? any HomePinnedRowViewLike else { continue }
            configurePinnedRow(row, state: state)
        }
    }

    private func configurePinnedRow(
        _ row: any HomePinnedRowViewLike,
        state: HomeReactor.State
    ) {
        row.configure(
            clips: pinnedClips,
            now: state.now,
            key: { [weak self] clip in self?.pinnedRowThumbnailKey(for: clip) },
            thumbnail: { [weak self] key in self?.thumbnails.phase(for: key, data: state.thumbnails, failed: state.failedThumbnails) ?? .pending },
            send: { [weak self] action in self?.handle(action) }
        )
        requestPinnedRowThumbnails(row, state: state)
    }

    private func makeSend() -> @MainActor (HomeViewAction) -> Void {
        { [weak self] action in
            guard let self else { return }
            switch action {
            case .save:
                reactor.action.onNext(.saveCurrentClipboard)
            case .search:
                showSearch()
            case .selectFilter(let filter):
                reactor.action.onNext(.selectFilter(filter))
            case .showMenu(let indexPath):
                showMenu(for: clip(at: indexPath))
            }
        }
    }

    private func handle(_ action: HomePinnedRowViewAction) {
        switch action {
        case .didScroll(let row):
            requestPinnedRowThumbnails(row, state: reactor.currentState)
        case .select(let clip):
            showDetail(for: clip)
        case .showMenu(let clip):
            showMenu(for: clip)
        case .copy(let id):
            reactor.action.onNext(.copy(id))
        }
    }

    /// 검색 화면을 스택에 쌓지 않고 자식 화면으로 표시하므로 스크롤 위치와 필터와 썸네일이 유지됩니다.
    private func showSearch() {
        guard searchViewController == nil else { return }
        let search = makeSearchViewController { [weak self] in self?.hideSearch() }
        embed(search)
        searchViewController = search
        homeView.setSearchButtonHidden(true)
        timeline.disappear()
        // 스크롤 뷰가 둘 다 켜져 있으면 상태 바 탭이 어느 쪽에도 동작하지 않는다.
        collectionView.scrollsToTop = false
    }

    private func hideSearch() {
        guard let search = searchViewController else { return }
        removeEmbedded(search)
        searchViewController = nil
        homeView.setSearchButtonHidden(false)
        timeline.appear()
        collectionView.scrollsToTop = true
    }

    /// 썸네일 보관 개수보다 고정 이미지가 많아도 요청과 제거가 반복되지 않도록 보이는 카드만 요청한다.
    private func requestPinnedRowThumbnails(
        _ row: any HomePinnedRowViewLike,
        state: HomeReactor.State
    ) {
        for clip in row.visibleClips() {
            guard let key = pinnedRowThumbnailKey(for: clip), state.thumbnails[key] == nil else { continue }
            reactor.action.onNext(.thumbnailRequested(key))
        }
    }

    private func pinnedRowThumbnailKey(for clip: Clip) -> HomeThumbnailKey? {
        guard case .image(let image) = clip.content else { return nil }
        let pixels = max(1, Int(ceil(homeView.pinnedRowType.thumbnailDimension * traitCollection.displayScale)))
        return HomeThumbnailKey(
            clipID: clip.id,
            fileID: image.fileID,
            maximumPixelDimension: pixels
        )
    }

    private func clip(at indexPath: IndexPath) -> Clip {
        sections[indexPath.section - pinnedRowSectionCount].clips[indexPath.item]
    }

    private func thumbnailKey(
        for clip: Clip,
        width: CGFloat
    ) -> HomeThumbnailKey? {
        guard case .image(let image) = clip.content else { return nil }
        let pixels = max(1, Int(ceil((width - 12) * traitCollection.displayScale)))
        return HomeThumbnailKey(clipID: clip.id, fileID: image.fileID, maximumPixelDimension: pixels)
    }
}

extension HomeViewController: UICollectionViewDataSource, UICollectionViewDelegate, HomeGridLayoutDelegate {
    func scrollViewDidScroll(_ scrollView: UIScrollView) {
        homeView.updateScrollPosition(scrollView.contentOffset.y)
    }

    func scrollViewDidEndDragging(
        _ scrollView: UIScrollView,
        willDecelerate decelerate: Bool
    ) {
        guard !decelerate else { return }
        homeView.snapHeader()
    }

    func scrollViewDidEndDecelerating(_ scrollView: UIScrollView) {
        homeView.snapHeader()
    }

    func numberOfSections(in collectionView: UICollectionView) -> Int {
        pinnedRowSectionCount + sections.count
    }

    func collectionView(
        _ collectionView: UICollectionView,
        numberOfItemsInSection section: Int
    ) -> Int {
        guard pinnedRowSectionCount <= section else { return 0 }
        return sections[section - pinnedRowSectionCount].clips.count
    }

    func collectionView(
        _ collectionView: UICollectionView,
        cellForItemAt indexPath: IndexPath
    ) -> UICollectionViewCell {
        let clip = clip(at: indexPath)
        switch clip.content {
        case .text:
            guard let cell = collectionView.dequeueReusableCell(
                withReuseIdentifier: homeView.textCellType.reuseIdentifier,
                for: indexPath
            ) as? any HomeTextCellLike else { preconditionFailure("\(homeView.textCellType) registration mismatch") }
            cell.configure(
                with: clip,
                now: reactor.currentState.now,
                name: nil,
                body: nil,
                onCopy: { [weak self] in self?.reactor.action.onNext(.copy(clip.id)) }
            )
            return cell
        case .image:
            guard let cell = collectionView.dequeueReusableCell(
                withReuseIdentifier: homeView.imageCellType.reuseIdentifier,
                for: indexPath
            ) as? any HomeImageCellLike else { preconditionFailure("\(homeView.imageCellType) registration mismatch") }
            let width = max(1, (collectionView.bounds.width - 42) / 2)
            if let key = thumbnailKey(for: clip, width: width) {
                cell.configure(
                    with: clip,
                    now: reactor.currentState.now,
                    key: key,
                    thumbnail: thumbnails.phase(for: key, data: reactor.currentState.thumbnails, failed: reactor.currentState.failedThumbnails),
                    name: nil,
                    onCopy: { [weak self] in self?.reactor.action.onNext(.copy(clip.id)) }
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
        switch kind {
        case HomeGridLayout.pinnedRowKind:
            guard let row = collectionView.dequeueReusableSupplementaryView(
                ofKind: kind,
                withReuseIdentifier: homeView.pinnedRowType.reuseIdentifier,
                for: indexPath
            ) as? any HomePinnedRowViewLike else { preconditionFailure("\(homeView.pinnedRowType) registration mismatch") }
            configurePinnedRow(row, state: reactor.currentState)
            return row

        default:
            guard let header = collectionView.dequeueReusableSupplementaryView(
                ofKind: kind,
                withReuseIdentifier: homeView.sectionHeaderType.reuseIdentifier,
                for: indexPath
            ) as? any HomeSectionHeaderViewLike else { preconditionFailure("\(homeView.sectionHeaderType) registration mismatch") }
            header.configure(title: sections[indexPath.section - pinnedRowSectionCount].kind.title)
            return header
        }
    }

    func collectionView(
        _ collectionView: UICollectionView,
        didSelectItemAt indexPath: IndexPath
    ) {
        showDetail(for: clip(at: indexPath))
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
        willDisplaySupplementaryView view: UICollectionReusableView,
        forElementKind elementKind: String,
        at indexPath: IndexPath
    ) {
        guard let row = view as? any HomePinnedRowViewLike else { return }
        requestPinnedRowThumbnails(row, state: reactor.currentState)
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
        let clip = clip(at: indexPath)
        switch clip.content {
        case .text:
            return homeView.textCellType.height(
                for: clip,
                width: width,
                name: nil,
                body: nil,
                showsCopy: true
            )
        case .image:
            return homeView.imageCellType.height(
                for: clip,
                width: width,
                name: nil,
                showsCopy: true
            )
        }
    }

    func homeLayoutHeightForPinnedRow(_ layout: HomeGridLayout) -> CGFloat {
        pinnedClips.isEmpty ? 0 : homeView.pinnedRowType.height
    }
}
