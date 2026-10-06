//
//  HomeView.swift
//  Plyst
//
//  Created by opfic on 9/30/26.
//

import UIKit

@MainActor
final class HomeView: UIView, HomeViewLike, ClipGridLike {
    private static let saveIcon = UIGraphicsImageRenderer(size: CGSize(width: 18, height: 18)).image { _ in
        UIColor.black.setStroke()
        let board = UIBezierPath(roundedRect: CGRect(x: 3.5, y: 3, width: 11, height: 13), cornerRadius: 2.5)
        board.lineWidth = 1.7
        board.stroke()
        let clip = UIBezierPath(roundedRect: CGRect(x: 6.5, y: 1.5, width: 5, height: 3), cornerRadius: 1.2)
        clip.fill(with: .clear, alpha: 1)
        clip.lineWidth = 1.5
        clip.stroke()
        let plus = UIBezierPath()
        plus.move(to: CGPoint(x: 9, y: 8))
        plus.addLine(to: CGPoint(x: 9, y: 13))
        plus.move(to: CGPoint(x: 6.5, y: 10.5))
        plus.addLine(to: CGPoint(x: 11.5, y: 10.5))
        plus.lineWidth = 1.7
        plus.lineCapStyle = .round
        plus.stroke()
    }.withRenderingMode(.alwaysTemplate)

    let layout = HomeGridLayout()
    private(set) lazy var collectionView = UICollectionView(frame: .zero, collectionViewLayout: layout)
    private let titleHeader = HomeTitleHeaderView(frame: .zero)
    private let filterBar: HomeFilterBarView
    private let headerContainer = UIView()
    private let topFade = EdgeFadeView(edge: .top, color: UIColor(resource: .homeCanvas))
    private let contentArea = UILayoutGuide()
    private let emptyState = HomeEmptyStateView()
    private let saveBar = UIView()
    private let saveButton = UIButton(type: .system)
    private let lock = UIImageView(image: UIImage(systemName: "lock.fill"))
    private let privacy = UILabel()
    private lazy var privacyRow = UIStackView(arrangedSubviews: [lock, privacy])
    private var headerHeight = CGFloat.zero
    private var hiddenHeaderHeight = CGFloat.zero
    private var scrollViewportSize = CGSize.zero
    private var previousScrollY: CGFloat?
    private var isUpdatingScrollGeometry = false
    private let send: @MainActor (HomeViewAction) -> Void

    init(
        frame: CGRect,
        send: @escaping @MainActor (HomeViewAction) -> Void
    ) {
        self.send = send
        filterBar = HomeFilterBarView { action in
            switch action {
            case .select(let filter): send(.selectFilter(filter))
            }
        }
        super.init(frame: frame)
        configureAppearance()
        registerCells()
        makeHierarchy()
        makeLayout()
        bindActions()
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) is unavailable")
    }

    override func layoutSubviews() {
        super.layoutSubviews()
        updateScrollGeometry()
    }

    var textCellType: any (HomeTextCellLike & ClipCardLike).Type { HomeTextCell.self }
    var imageCellType: any (HomeImageCellLike & ClipCardLike).Type { HomeImageCell.self }
    var sectionHeaderType: any (HomeSectionHeaderViewLike & SectionTitleLike).Type { HomeSectionHeaderView.self }
    var pinnedRowType: any (HomePinnedRowViewLike & SectionTitleLike).Type { HomePinnedRowView.self }

    func reloadContent() {
        let wasUpdating = isUpdatingScrollGeometry
        isUpdatingScrollGeometry = true
        defer { isUpdatingScrollGeometry = wasUpdating }

        layout.invalidateLayout()
        collectionView.reloadData()
        collectionView.layoutIfNeeded()
        collectionView.isScrollEnabled = 0 < collectionView.numberOfSections
        if !collectionView.isScrollEnabled {
            // 항목이 없으면 스크롤할 내용이 없으므로 상단에 고정해 이후 항목이 생겼을 때 헤더와 목록이 어긋나지 않게 한다.
            collectionView.contentOffset.y = -collectionView.contentInset.top
        }
        let scrollY = boundedScrollY(collectionView.contentOffset.y)
        previousScrollY = scrollY
        hiddenHeaderHeight = clampedHiddenHeaderHeight(hiddenHeaderHeight, scrollY: scrollY)
        updateHeaderPresentation()
    }

    func updateScrollPosition(_ offset: CGFloat) {
        guard !isUpdatingScrollGeometry else { return }
        let scrollY = boundedScrollY(offset)
        let previous = previousScrollY ?? scrollY
        previousScrollY = scrollY

        var hidden = hiddenHeaderHeight
        if collectionView.isDragging || collectionView.isDecelerating {
            hidden += scrollY - previous
        }
        hiddenHeaderHeight = clampedHiddenHeaderHeight(hidden, scrollY: scrollY)
        updateHeaderPresentation()
    }

    func setSaving(_ isSaving: Bool) {
        saveButton.isEnabled = !isSaving
        saveButton.alpha = isSaving ? 0.55 : 1
    }

    func setSelectedFilter(_ filter: HomeFilter) {
        filterBar.setSelectedFilter(filter)
    }

    /// 검색 화면이 같은 자리에 자신의 버튼을 그리는 동안 헤더의 버튼을 숨긴다.
    func setSearchButtonHidden(_ isHidden: Bool) {
        titleHeader.searchButton.isHidden = isHidden
    }

    func scrollToTop() {
        let wasUpdating = isUpdatingScrollGeometry
        isUpdatingScrollGeometry = true
        defer { isUpdatingScrollGeometry = wasUpdating }

        hiddenHeaderHeight = 0
        previousScrollY = -collectionView.contentInset.top
        updateHeaderPresentation()
        collectionView.setContentOffset(CGPoint(x: 0, y: -collectionView.contentInset.top), animated: true)
    }

    /// 드래그나 감속이 끝났을 때 헤더뷰의 가장 밑이 safe area 경계선을 넘었는지로 완전히 가리거나 완전히 보이게 스냅한다.
    func snapHeader() {
        guard 0 < headerHeight else { return }
        let top = -collectionView.contentInset.top
        let scrollY = boundedScrollY(collectionView.contentOffset.y)
        let hides = headerHeight - safeAreaInsets.top < hiddenHeaderHeight
        // 목록이 헤더 높이만큼 스크롤되지 않았으면 헤더와 함께 목록도 헤더만큼 이동하거나 맨 위로 돌아간다.
        let targetY = scrollY - top < headerHeight
            ? boundedScrollY(hides ? top + headerHeight : top)
            : scrollY
        let target = clampedHiddenHeaderHeight(
            hides ? headerHeight : 0,
            scrollY: targetY
        )
        guard target != hiddenHeaderHeight || targetY != scrollY else { return }

        let wasUpdating = isUpdatingScrollGeometry
        isUpdatingScrollGeometry = true
        defer { isUpdatingScrollGeometry = wasUpdating }

        hiddenHeaderHeight = target
        previousScrollY = targetY
        UIView.animate(
            withDuration: 0.22,
            delay: 0,
            options: [.beginFromCurrentState, .curveEaseOut, .allowUserInteraction],
            animations: { [weak self] in
                guard let self else { return }
                collectionView.contentOffset = CGPoint(x: collectionView.contentOffset.x, y: targetY)
                updateHeaderPresentation()
            }
        )
    }

    func showEmptyState(
        title: String,
        message: String
    ) {
        emptyState.configure(title: title, message: message)
        emptyState.isHidden = false
    }

    func hideEmptyState() {
        emptyState.isHidden = true
    }

    private func updateScrollGeometry() {
        guard 0 < bounds.width, 0 < bounds.height else { return }
        let height = headerContainer.bounds.height
        let size = collectionView.bounds.size
        guard height != headerHeight || size != scrollViewportSize else { return }

        let offset = collectionView.contentOffset
        let wasAtTop = offset.y <= -collectionView.contentInset.top + 1
        let progress = headerHeight == 0 ? 0 : hiddenHeaderHeight / headerHeight
        let wasUpdating = isUpdatingScrollGeometry
        isUpdatingScrollGeometry = true
        defer { isUpdatingScrollGeometry = wasUpdating }

        headerHeight = height
        scrollViewportSize = size
        collectionView.contentInset.top = height
        collectionView.layoutIfNeeded()
        let scrollY = wasAtTop ? -height : boundedScrollY(offset.y)
        let position = CGPoint(x: offset.x, y: scrollY)
        if collectionView.contentOffset != position {
            collectionView.setContentOffset(position, animated: false)
        }
        let currentScrollY = boundedScrollY(collectionView.contentOffset.y)
        previousScrollY = currentScrollY
        hiddenHeaderHeight = clampedHiddenHeaderHeight(progress * height, scrollY: currentScrollY)
        updateHeaderPresentation()
    }

    private func boundedScrollY(_ offset: CGFloat) -> CGFloat {
        let top = -collectionView.contentInset.top
        let bottom = max(
            top,
            collectionView.contentSize.height - collectionView.bounds.height + collectionView.contentInset.bottom
        )
        return min(bottom, max(top, offset))
    }

    private func clampedHiddenHeaderHeight(
        _ hidden: CGFloat,
        scrollY: CGFloat
    ) -> CGFloat {
        guard 0 < collectionView.numberOfSections else { return 0 }
        // 헤더는 목록이 상단 inset을 지나 스크롤된 거리보다 더 숨겨지지 않는다.
        return max(0, min(headerHeight, hidden, scrollY + collectionView.contentInset.top))
    }

    private func updateHeaderPresentation() {
        headerContainer.transform = CGAffineTransform(translationX: 0, y: -hiddenHeaderHeight)
        collectionView.verticalScrollIndicatorInsets.top = max(0, headerHeight - hiddenHeaderHeight)
    }

    private func configureAppearance() {
        backgroundColor = UIColor(resource: .homeCanvas)
        headerContainer.backgroundColor = backgroundColor
        headerContainer.isUserInteractionEnabled = true

        collectionView.backgroundColor = .clear
        collectionView.contentInsetAdjustmentBehavior = .never
        collectionView.alwaysBounceVertical = true
        collectionView.showsVerticalScrollIndicator = true

        saveButton.layer.shadowColor = UIColor(resource: .homeShadow).cgColor
        saveButton.layer.shadowOpacity = 0.18
        saveButton.layer.shadowRadius = 15
        saveButton.layer.shadowOffset = CGSize(width: 0, height: 8)

        var configuration = UIButton.Configuration.plain()
        var title = AttributedString("현재 클립보드 저장")
        title.font = .systemFont(ofSize: 17, weight: .semibold)
        configuration.attributedTitle = title
        configuration.image = Self.saveIcon
        configuration.imagePadding = 9
        configuration.baseForegroundColor = UIColor(resource: .homeBottomText)
        configuration.background.backgroundColor = UIColor(resource: .homeBottomBar)
        configuration.background.cornerRadius = 22
        configuration.cornerStyle = .fixed
        saveButton.configuration = configuration

        lock.tintColor = UIColor(resource: .homePrivacyText)
        lock.contentMode = .scaleAspectFit
        privacy.text = "이 기기에만 저장됩니다"
        privacy.font = .systemFont(ofSize: 12)
        privacy.textColor = UIColor(resource: .homePrivacyText)
        privacyRow.axis = .horizontal
        privacyRow.alignment = .center
        privacyRow.spacing = 6
    }

    private func registerCells() {
        collectionView.register(textCellType, forCellWithReuseIdentifier: textCellType.reuseIdentifier)
        collectionView.register(imageCellType, forCellWithReuseIdentifier: imageCellType.reuseIdentifier)
        collectionView.register(
            sectionHeaderType,
            forSupplementaryViewOfKind: HomeGridLayout.headerKind,
            withReuseIdentifier: sectionHeaderType.reuseIdentifier
        )
        collectionView.register(
            pinnedRowType,
            forSupplementaryViewOfKind: HomeGridLayout.pinnedRowKind,
            withReuseIdentifier: pinnedRowType.reuseIdentifier
        )
    }

    private func makeHierarchy() {
        addSubview(collectionView)
        addLayoutGuide(contentArea)
        addSubview(emptyState)
        addSubview(headerContainer)
        headerContainer.addSubview(titleHeader)
        headerContainer.addSubview(filterBar)
        // 헤더가 위로 숨겨질 때도 함께 가려지도록 헤더보다 앞에 둡니다.
        addSubview(topFade)
        addSubview(saveBar)
        saveBar.addSubview(saveButton)
        saveBar.addSubview(privacyRow)
    }

    private func makeLayout() {
        headerContainer.translatesAutoresizingMaskIntoConstraints = false
        topFade.translatesAutoresizingMaskIntoConstraints = false
        titleHeader.translatesAutoresizingMaskIntoConstraints = false
        filterBar.translatesAutoresizingMaskIntoConstraints = false
        collectionView.translatesAutoresizingMaskIntoConstraints = false
        emptyState.translatesAutoresizingMaskIntoConstraints = false
        saveBar.translatesAutoresizingMaskIntoConstraints = false
        saveButton.translatesAutoresizingMaskIntoConstraints = false
        lock.translatesAutoresizingMaskIntoConstraints = false
        privacyRow.translatesAutoresizingMaskIntoConstraints = false

        NSLayoutConstraint.activate([
            collectionView.topAnchor.constraint(equalTo: topAnchor),
            collectionView.leadingAnchor.constraint(equalTo: leadingAnchor),
            collectionView.trailingAnchor.constraint(equalTo: trailingAnchor),
            collectionView.bottomAnchor.constraint(equalTo: saveBar.topAnchor, constant: -12),
            headerContainer.topAnchor.constraint(equalTo: topAnchor),
            headerContainer.leadingAnchor.constraint(equalTo: leadingAnchor),
            headerContainer.trailingAnchor.constraint(equalTo: trailingAnchor),
            titleHeader.topAnchor.constraint(equalTo: safeAreaLayoutGuide.topAnchor),
            titleHeader.leadingAnchor.constraint(equalTo: headerContainer.leadingAnchor),
            titleHeader.trailingAnchor.constraint(equalTo: headerContainer.trailingAnchor),
            titleHeader.bottomAnchor.constraint(equalTo: filterBar.topAnchor, constant: 4),
            filterBar.leadingAnchor.constraint(equalTo: headerContainer.leadingAnchor),
            filterBar.trailingAnchor.constraint(equalTo: headerContainer.trailingAnchor),
            filterBar.heightAnchor.constraint(equalToConstant: 40),
            filterBar.bottomAnchor.constraint(equalTo: headerContainer.bottomAnchor, constant: -4),
            contentArea.topAnchor.constraint(equalTo: headerContainer.bottomAnchor),
            contentArea.leadingAnchor.constraint(equalTo: collectionView.leadingAnchor),
            contentArea.trailingAnchor.constraint(equalTo: collectionView.trailingAnchor),
            contentArea.bottomAnchor.constraint(equalTo: saveBar.topAnchor, constant: -12),
            saveBar.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 12),
            saveBar.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -12),
            saveBar.bottomAnchor.constraint(equalTo: safeAreaLayoutGuide.bottomAnchor, constant: -12),
            saveButton.topAnchor.constraint(equalTo: saveBar.topAnchor),
            saveButton.leadingAnchor.constraint(equalTo: saveBar.leadingAnchor),
            saveButton.trailingAnchor.constraint(equalTo: saveBar.trailingAnchor),
            saveButton.heightAnchor.constraint(equalToConstant: 54),
            privacyRow.topAnchor.constraint(equalTo: saveButton.bottomAnchor, constant: 4),
            privacyRow.centerXAnchor.constraint(equalTo: saveBar.centerXAnchor),
            privacyRow.heightAnchor.constraint(equalToConstant: 30),
            privacyRow.bottomAnchor.constraint(equalTo: saveBar.bottomAnchor),
            lock.widthAnchor.constraint(equalToConstant: 10),
            lock.heightAnchor.constraint(equalToConstant: 12),
            emptyState.centerXAnchor.constraint(equalTo: collectionView.centerXAnchor),
            emptyState.centerYAnchor.constraint(equalTo: contentArea.centerYAnchor, constant: 24),
            emptyState.leadingAnchor.constraint(greaterThanOrEqualTo: collectionView.leadingAnchor, constant: 40),
            emptyState.trailingAnchor.constraint(lessThanOrEqualTo: collectionView.trailingAnchor, constant: -40),
            topFade.topAnchor.constraint(equalTo: topAnchor),
            topFade.leadingAnchor.constraint(equalTo: leadingAnchor),
            topFade.trailingAnchor.constraint(equalTo: trailingAnchor),
            topFade.bottomAnchor.constraint(equalTo: safeAreaLayoutGuide.topAnchor)
        ])
    }

    private func bindActions() {
        saveButton.addAction(UIAction { [weak self] _ in
            self?.send(.save)
        }, for: .touchUpInside)
        titleHeader.searchButton.addAction(UIAction { [weak self] _ in
            self?.send(.search)
        }, for: .touchUpInside)
        let longPress = UILongPressGestureRecognizer(target: self, action: #selector(didLongPress(_:)))
        longPress.minimumPressDuration = 0.48
        collectionView.addGestureRecognizer(longPress)
    }

    /// 고정 행은 supplementary view라서 indexPath가 nil이므로 격자 카드에서만 메뉴를 요청합니다.
    @objc private func didLongPress(_ recognizer: UILongPressGestureRecognizer) {
        guard recognizer.state == .began,
              let indexPath = collectionView.indexPathForItem(at: recognizer.location(in: collectionView)) else { return }
        send(.showMenu(indexPath))
    }
}
