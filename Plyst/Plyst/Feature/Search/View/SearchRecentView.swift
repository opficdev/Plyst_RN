//
//  SearchRecentView.swift
//  Plyst
//
//  Created by opfic on 9/30/26.
//

import UIKit

/// 검색어가 없을 때 보이는 최근 검색어 영역입니다.
final class SearchRecentView: UIView, SectionTitleLike {
    let title = UILabel()
    private let clearButton = UIButton(type: .system)
    let rule = UIView()
    private let scrollView = UIScrollView()
    private let chips = UIStackView()
    private let message = UILabel()
    private let hint = UILabel()
    private let send: @MainActor (SearchRecentViewAction) -> Void
    private lazy var ruleTrailingToClear = rule.trailingAnchor.constraint(equalTo: clearButton.leadingAnchor, constant: -10)
    private lazy var ruleTrailingToEdge = rule.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -20)

    init(send: @escaping @MainActor (SearchRecentViewAction) -> Void) {
        self.send = send
        super.init(frame: .zero)
        configureAppearance()
        makeHierarchy()
        makeLayout()
        bindActions()
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) is unavailable")
    }

    /// terms가 있으면 칩을 표시하고, 없으면 message를 표시합니다. showsClear는 전체 삭제 버튼 표시 여부입니다.
    func configure(
        terms: [String],
        message text: String?,
        showsClear: Bool
    ) {
        chips.arrangedSubviews.forEach { $0.removeFromSuperview() }
        for term in terms {
            let chip = SearchTermChipView(term: term)
            chip.onSelect = { [weak self] in
                self?.send(.select(term))
            }
            chip.onRemove = { [weak self] in
                self?.send(.remove(term))
            }
            chips.addArrangedSubview(chip)
        }
        scrollView.isHidden = terms.isEmpty
        message.text = text
        message.isHidden = text == nil
        clearButton.isHidden = !showsClear
        // 지우기 버튼이 없으면 구분선이 다른 뷰들과 같은 오른쪽 여백까지 이어진다.
        ruleTrailingToClear.isActive = showsClear
        ruleTrailingToEdge.isActive = !showsClear
    }

    private func configureAppearance() {
        title.text = "최근 검색어"
        title.font = .monospacedSystemFont(ofSize: 11, weight: .semibold)
        title.textColor = UIColor(resource: .homeSecondaryText)

        clearButton.setTitle("지우기", for: .normal)
        clearButton.titleLabel?.font = .systemFont(ofSize: 13, weight: .semibold)
        clearButton.setTitleColor(UIColor(resource: .homeSecondaryText), for: .normal)

        rule.backgroundColor = UIColor(resource: .homeOutline)

        scrollView.showsHorizontalScrollIndicator = false
        scrollView.alwaysBounceHorizontal = true
        chips.axis = .horizontal
        chips.spacing = 8
        chips.alignment = .center

        message.font = .systemFont(ofSize: 14)
        message.textColor = UIColor(resource: .homeSecondaryText)
        message.numberOfLines = 0

        hint.text = "텍스트는 내용과 이름으로, 이미지는 이름과 저장 시각으로 찾을 수 있어요."
        hint.font = .systemFont(ofSize: 13)
        hint.textColor = UIColor(resource: .homeSecondaryText)
        hint.numberOfLines = 0
    }

    private func makeHierarchy() {
        addSubview(title)
        addSubview(clearButton)
        addSubview(rule)
        addSubview(scrollView)
        scrollView.addSubview(chips)
        addSubview(message)
        addSubview(hint)
    }

    private func makeLayout() {
        title.translatesAutoresizingMaskIntoConstraints = false
        clearButton.translatesAutoresizingMaskIntoConstraints = false
        rule.translatesAutoresizingMaskIntoConstraints = false
        scrollView.translatesAutoresizingMaskIntoConstraints = false
        chips.translatesAutoresizingMaskIntoConstraints = false
        message.translatesAutoresizingMaskIntoConstraints = false
        hint.translatesAutoresizingMaskIntoConstraints = false

        NSLayoutConstraint.activate([
            title.topAnchor.constraint(equalTo: topAnchor, constant: 20),
            title.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 20),
            clearButton.centerYAnchor.constraint(equalTo: title.centerYAnchor),
            clearButton.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -20),
            rule.centerYAnchor.constraint(equalTo: title.centerYAnchor),
            rule.leadingAnchor.constraint(equalTo: title.trailingAnchor, constant: 10),
            ruleTrailingToEdge,
            rule.heightAnchor.constraint(equalToConstant: 1),
            scrollView.topAnchor.constraint(equalTo: title.bottomAnchor, constant: 14),
            scrollView.leadingAnchor.constraint(equalTo: leadingAnchor),
            scrollView.trailingAnchor.constraint(equalTo: trailingAnchor),
            scrollView.heightAnchor.constraint(equalToConstant: 36),
            chips.topAnchor.constraint(equalTo: scrollView.topAnchor),
            chips.bottomAnchor.constraint(equalTo: scrollView.bottomAnchor),
            chips.leadingAnchor.constraint(equalTo: scrollView.leadingAnchor, constant: 20),
            chips.trailingAnchor.constraint(equalTo: scrollView.trailingAnchor, constant: -20),
            chips.heightAnchor.constraint(equalTo: scrollView.heightAnchor),
            message.topAnchor.constraint(equalTo: title.bottomAnchor, constant: 14),
            message.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 20),
            message.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -20),
            hint.topAnchor.constraint(equalTo: scrollView.bottomAnchor, constant: 42),
            hint.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 20),
            hint.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -20)
        ])
    }

    private func bindActions() {
        clearButton.addAction(UIAction { [weak self] _ in
            self?.send(.clear)
        }, for: .touchUpInside)
    }
}

/// 검색어를 다시 선택하거나 하나만 삭제할 수 있는 칩입니다.
private final class SearchTermChipView: UIView, SearchTermChipLike {
    var onSelect: (() -> Void)?
    var onRemove: (() -> Void)?

    let termButton = UIButton(type: .system)
    let removeButton = UIButton(type: .system)
    private lazy var row = UIStackView(arrangedSubviews: [termButton, removeButton])

    init(term: String) {
        super.init(frame: .zero)
        configureAppearance(term: term)
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

    private func configureAppearance(term: String) {
        backgroundColor = UIColor(resource: .homeCard)
        layer.cornerRadius = 18
        layer.borderWidth = 1

        var termConfiguration = UIButton.Configuration.plain()
        var title = AttributedString(term)
        title.font = .systemFont(ofSize: 13, weight: .semibold)
        termConfiguration.attributedTitle = title
        termConfiguration.baseForegroundColor = UIColor(resource: .homePrimaryText)
        termConfiguration.titleLineBreakMode = .byTruncatingTail
        termConfiguration.contentInsets = NSDirectionalEdgeInsets(
            top: 8,
            leading: 14,
            bottom: 8,
            trailing: 4
        )
        termButton.configuration = termConfiguration

        var removeConfiguration = UIButton.Configuration.plain()
        removeConfiguration.image = UIImage(
            systemName: "xmark",
            withConfiguration: UIImage.SymbolConfiguration(pointSize: 10, weight: .bold)
        )
        removeConfiguration.baseForegroundColor = UIColor(resource: .homeSecondaryText)
        removeConfiguration.contentInsets = NSDirectionalEdgeInsets(
            top: 8,
            leading: 6,
            bottom: 8,
            trailing: 12
        )
        removeButton.configuration = removeConfiguration

        row.axis = .horizontal
        row.alignment = .center
    }

    private func makeHierarchy() {
        addSubview(row)
    }

    private func makeLayout() {
        row.translatesAutoresizingMaskIntoConstraints = false
        termButton.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
        removeButton.setContentCompressionResistancePriority(.required, for: .horizontal)

        NSLayoutConstraint.activate([
            row.topAnchor.constraint(equalTo: topAnchor),
            row.leadingAnchor.constraint(equalTo: leadingAnchor),
            row.trailingAnchor.constraint(equalTo: trailingAnchor),
            row.bottomAnchor.constraint(equalTo: bottomAnchor),
            widthAnchor.constraint(lessThanOrEqualToConstant: 220)
        ])
    }

    private func bindActions() {
        termButton.addAction(UIAction { [weak self] _ in
            self?.onSelect?()
        }, for: .touchUpInside)
        removeButton.addAction(UIAction { [weak self] _ in
            self?.onRemove?()
        }, for: .touchUpInside)
    }

    private func bindTraitChanges() {
        updateBorder()
        registerForTraitChanges([UITraitUserInterfaceStyle.self]) { (view: SearchTermChipView, _) in
            view.updateBorder()
        }
    }

    private func updateBorder() {
        layer.borderColor = UIColor(resource: .homeOutline).resolvedColor(with: traitCollection).cgColor
    }
}
