//
//  SearchView.swift
//  Plyst
//
//  Created by opfic on 9/30/26.
//

import UIKit

@MainActor
final class SearchView: UIView, SearchViewLike, ClipGridLike {
    let layout = HomeGridLayout()
    private(set) lazy var collectionView = UICollectionView(frame: .zero, collectionViewLayout: layout)
    private let backdrop = UIView()
    private let fieldContainer = UIView()
    private let searchIcon = UIImageView(image: UIImage(systemName: "magnifyingglass"))
    private let searchField = UITextField()
    private let cancelButton = UIButton(type: .system)
    private let filterBar: HomeFilterBarView
    private let recentView: SearchRecentView
    private let emptyState = HomeEmptyStateView()
    private let send: @MainActor (SearchViewAction) -> Void
    private lazy var fieldExpandedLeading = fieldContainer.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 20)
    private lazy var fieldCollapsedWidth = fieldContainer.widthAnchor.constraint(equalToConstant: 0)
    private lazy var body: [UIView] = [filterBar, collectionView, recentView, emptyState]
    private var isExpanded = false

    init(
        frame: CGRect,
        send: @escaping @MainActor (SearchViewAction) -> Void
    ) {
        self.send = send
        filterBar = HomeFilterBarView { action in
            switch action {
            case .select(let filter): send(.selectFilter(filter))
            }
        }
        recentView = SearchRecentView { action in
            switch action {
            case .select(let term): send(.selectRecentTerm(term))
            case .remove(let term): send(.removeRecentTerm(term))
            case .clear: send(.clearRecentTerms)
            }
        }
        super.init(frame: frame)
        configureAppearance()
        registerCells()
        makeHierarchy()
        makeLayout()
        bindActions()
        bindTraitChanges()
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) is unavailable")
    }

    override func didMoveToWindow() {
        super.didMoveToWindow()
        updateBorder()
    }

    var textCellType: any (HomeTextCellLike & ClipCardLike).Type { HomeTextCell.self }
    var imageCellType: any (HomeImageCellLike & ClipCardLike).Type { HomeImageCell.self }
    var sectionHeaderType: any (HomeSectionHeaderViewLike & SectionTitleLike).Type { HomeSectionHeaderView.self }

    func focusSearchField() {
        searchField.becomeFirstResponder()
    }

    /// 헤더의 검색 버튼 자리에서 버튼이 xmark로 바뀌고 서치바가 leading 방향으로 늘어난다.
    func expand() {
        guard !isExpanded else { return }
        setExpanded(true, completion: nil)
    }

    /// 확장과 반대 순서로 서치바를 줄인 뒤 completion을 호출한다. 이미 접는 중이면 무시한다.
    func collapse(completion: @escaping @MainActor () -> Void) {
        guard isExpanded else { return }
        endEditing(true)
        setExpanded(false, completion: completion)
    }

    /// 상태의 검색어와 다를 때만 필드를 갱신해 입력 중인 커서와 조합 중인 글자를 보존합니다.
    func setQuery(_ query: String) {
        guard searchField.text != query else { return }
        searchField.text = query
    }

    func setSelectedFilter(_ filter: HomeFilter) {
        filterBar.setSelectedFilter(filter)
    }

    func reloadContent() {
        layout.invalidateLayout()
        collectionView.reloadData()
    }

    func scrollToTop() {
        collectionView.setContentOffset(CGPoint(x: 0, y: -collectionView.contentInset.top), animated: true)
    }

    /// 칩을 다시 만들기 때문에 최근 검색어 내용이 바뀔 때만 호출합니다.
    func setRecent(
        terms: [String],
        message: String?,
        showsClear: Bool
    ) {
        recentView.configure(terms: terms, message: message, showsClear: showsClear)
    }

    /// 검색어가 없을 때는 최근 검색어를, 있을 때는 결과 목록을 보여줍니다.
    func showRecent() {
        recentView.isHidden = false
        collectionView.isHidden = true
        emptyState.isHidden = true
    }

    func showResults() {
        recentView.isHidden = true
        collectionView.isHidden = false
        emptyState.isHidden = true
    }

    func showEmptyState(
        title: String,
        message: String
    ) {
        emptyState.configure(title: title, message: message)
        recentView.isHidden = true
        collectionView.isHidden = true
        emptyState.isHidden = false
    }

    private static func makeButtonConfiguration(symbol: String) -> UIButton.Configuration {
        var configuration = UIButton.Configuration.plain()
        configuration.image = UIImage(
            systemName: symbol,
            withConfiguration: UIImage.SymbolConfiguration(pointSize: 17, weight: .semibold)
        )
        configuration.baseForegroundColor = UIColor(resource: .homePrimaryText)
        configuration.background.backgroundColor = UIColor(resource: .homeCard)
        configuration.background.strokeColor = UIColor(resource: .homeOutline)
        configuration.background.strokeWidth = 1
        configuration.cornerStyle = .capsule
        return configuration
    }

    private func setExpanded(
        _ isExpanded: Bool,
        completion: (@MainActor () -> Void)?
    ) {
        self.isExpanded = isExpanded
        layoutIfNeeded()
        if isExpanded {
            fieldCollapsedWidth.isActive = false
            fieldExpandedLeading.isActive = true
        } else {
            fieldExpandedLeading.isActive = false
            fieldCollapsedWidth.isActive = true
        }
        UIView.transition(
            with: cancelButton,
            duration: 0.3,
            options: [.transitionCrossDissolve, .allowUserInteraction],
            animations: { [weak self] in
                self?.cancelButton.configuration = Self.makeButtonConfiguration(
                    symbol: isExpanded ? "xmark" : "magnifyingglass"
                )
            }
        )
        UIView.animate(
            withDuration: 0.3,
            delay: 0,
            options: [.beginFromCurrentState, .curveEaseInOut],
            animations: { [weak self] in
                guard let self else { return }
                let alpha = isExpanded ? 1.0 : 0.0
                backdrop.alpha = alpha
                fieldContainer.alpha = alpha
                for view in body { view.alpha = alpha }
                layoutIfNeeded()
            },
            completion: { _ in completion?() }
        )
    }

    private func configureAppearance() {
        // 접힌 상태는 기록 화면의 헤더와 시각적으로 같아야 하므로 배경과 서치바와 본문을 투명하게 시작한다.
        backgroundColor = .clear
        backdrop.backgroundColor = UIColor(resource: .homeCanvas)
        backdrop.alpha = 0
        for view in body { view.alpha = 0 }

        fieldContainer.backgroundColor = UIColor(resource: .homeCard)
        fieldContainer.layer.cornerRadius = 22
        fieldContainer.layer.borderWidth = 1
        fieldContainer.clipsToBounds = true
        fieldContainer.alpha = 0

        searchIcon.tintColor = UIColor(resource: .homeSecondaryText)
        searchIcon.contentMode = .scaleAspectFit

        searchField.font = .systemFont(ofSize: 16)
        searchField.textColor = UIColor(resource: .homePrimaryText)
        searchField.placeholder = "복사한 내용 검색"
        searchField.returnKeyType = .search
        searchField.clearButtonMode = .whileEditing
        searchField.autocorrectionType = .no
        searchField.spellCheckingType = .no
        searchField.autocapitalizationType = .none

        cancelButton.configuration = Self.makeButtonConfiguration(symbol: "magnifyingglass")

        collectionView.backgroundColor = .clear
        collectionView.contentInsetAdjustmentBehavior = .never
        collectionView.alwaysBounceVertical = true
        collectionView.keyboardDismissMode = .onDrag
        collectionView.contentInset.bottom = 16
        collectionView.isHidden = true

        recentView.isHidden = false
    }

    private func registerCells() {
        collectionView.register(textCellType, forCellWithReuseIdentifier: textCellType.reuseIdentifier)
        collectionView.register(imageCellType, forCellWithReuseIdentifier: imageCellType.reuseIdentifier)
        collectionView.register(
            sectionHeaderType,
            forSupplementaryViewOfKind: HomeGridLayout.headerKind,
            withReuseIdentifier: sectionHeaderType.reuseIdentifier
        )
    }

    private func makeHierarchy() {
        addSubview(backdrop)
        addSubview(fieldContainer)
        fieldContainer.addSubview(searchIcon)
        fieldContainer.addSubview(searchField)
        addSubview(cancelButton)
        addSubview(filterBar)
        addSubview(collectionView)
        addSubview(recentView)
        addSubview(emptyState)
    }

    private func makeLayout() {
        backdrop.translatesAutoresizingMaskIntoConstraints = false
        fieldContainer.translatesAutoresizingMaskIntoConstraints = false
        searchIcon.translatesAutoresizingMaskIntoConstraints = false
        searchField.translatesAutoresizingMaskIntoConstraints = false
        cancelButton.translatesAutoresizingMaskIntoConstraints = false
        filterBar.translatesAutoresizingMaskIntoConstraints = false
        collectionView.translatesAutoresizingMaskIntoConstraints = false
        recentView.translatesAutoresizingMaskIntoConstraints = false
        emptyState.translatesAutoresizingMaskIntoConstraints = false

        // 서치바 입력 필드는 접힌 너비에서 제약이 깨져도 되도록 trailing 우선순위를 낮춘다.
        let fieldTrailing = searchField.trailingAnchor.constraint(equalTo: fieldContainer.trailingAnchor, constant: -12)
        fieldTrailing.priority = .defaultHigh

        NSLayoutConstraint.activate([
            backdrop.topAnchor.constraint(equalTo: topAnchor),
            backdrop.leadingAnchor.constraint(equalTo: leadingAnchor),
            backdrop.trailingAnchor.constraint(equalTo: trailingAnchor),
            backdrop.bottomAnchor.constraint(equalTo: bottomAnchor),
            // 기록 화면 헤더의 검색 버튼과 같은 자리에 놓이도록 마크 중심(safe area 상단 + 17) 기준으로 배치한다.
            cancelButton.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -20),
            cancelButton.centerYAnchor.constraint(equalTo: safeAreaLayoutGuide.topAnchor, constant: 17),
            cancelButton.widthAnchor.constraint(equalToConstant: 44),
            cancelButton.heightAnchor.constraint(equalToConstant: 44),
            fieldContainer.trailingAnchor.constraint(equalTo: cancelButton.leadingAnchor, constant: -12),
            fieldContainer.centerYAnchor.constraint(equalTo: cancelButton.centerYAnchor),
            fieldContainer.heightAnchor.constraint(equalToConstant: 44),
            fieldCollapsedWidth,
            searchIcon.leadingAnchor.constraint(equalTo: fieldContainer.leadingAnchor, constant: 14),
            searchIcon.centerYAnchor.constraint(equalTo: fieldContainer.centerYAnchor),
            searchIcon.widthAnchor.constraint(equalToConstant: 18),
            searchIcon.heightAnchor.constraint(equalToConstant: 18),
            searchField.leadingAnchor.constraint(equalTo: searchIcon.trailingAnchor, constant: 10),
            fieldTrailing,
            searchField.topAnchor.constraint(equalTo: fieldContainer.topAnchor),
            searchField.bottomAnchor.constraint(equalTo: fieldContainer.bottomAnchor),
            // 기록 화면의 필터 바와 같은 높이에 놓이도록 헤더 하단 간격(13)에서 필터 바 겹침(4)을 뺀 값이다.
            filterBar.topAnchor.constraint(equalTo: fieldContainer.bottomAnchor, constant: 9),
            filterBar.leadingAnchor.constraint(equalTo: leadingAnchor),
            filterBar.trailingAnchor.constraint(equalTo: trailingAnchor),
            filterBar.heightAnchor.constraint(equalToConstant: 40),
            // 기록 화면의 목록이 시작하는 헤더 하단과 같은 위치이며 최근 검색어도 같은 선에서 시작한다.
            collectionView.topAnchor.constraint(equalTo: filterBar.bottomAnchor, constant: 4),
            collectionView.leadingAnchor.constraint(equalTo: leadingAnchor),
            collectionView.trailingAnchor.constraint(equalTo: trailingAnchor),
            collectionView.bottomAnchor.constraint(equalTo: keyboardLayoutGuide.topAnchor),
            recentView.topAnchor.constraint(equalTo: collectionView.topAnchor),
            recentView.leadingAnchor.constraint(equalTo: collectionView.leadingAnchor),
            recentView.trailingAnchor.constraint(equalTo: collectionView.trailingAnchor),
            recentView.bottomAnchor.constraint(equalTo: collectionView.bottomAnchor),
            emptyState.centerXAnchor.constraint(equalTo: collectionView.centerXAnchor),
            emptyState.centerYAnchor.constraint(equalTo: collectionView.centerYAnchor),
            emptyState.leadingAnchor.constraint(greaterThanOrEqualTo: collectionView.leadingAnchor, constant: 40),
            emptyState.trailingAnchor.constraint(lessThanOrEqualTo: collectionView.trailingAnchor, constant: -40)
        ])
    }

    private func bindActions() {
        searchField.addAction(UIAction { [weak self] _ in
            guard let self else { return }
            send(.changeQuery(searchField.text ?? ""))
        }, for: .editingChanged)
        searchField.addAction(UIAction { [weak self] _ in
            guard let self else { return }
            send(.submit)
            searchField.resignFirstResponder()
        }, for: .editingDidEndOnExit)
        cancelButton.addAction(UIAction { [weak self] _ in
            self?.send(.cancel)
        }, for: .touchUpInside)
    }

    private func bindTraitChanges() {
        updateBorder()
        registerForTraitChanges([UITraitUserInterfaceStyle.self]) { (view: SearchView, _) in
            view.updateBorder()
        }
    }

    private func updateBorder() {
        fieldContainer.layer.borderColor = UIColor(resource: .homeOutline).resolvedColor(with: traitCollection).cgColor
    }
}
