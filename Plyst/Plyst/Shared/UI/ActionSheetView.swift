//
//  ActionSheetView.swift
//  Plyst
//
//  Created by opfic on 10/2/26.
//

import UIKit

/// 어두운 배경 위 화면 가운데에 제목과 요약 문구와 항목 버튼을 카드로 표시하는 공용 액션 시트 화면입니다.
/// 카드가 화면보다 커지면 항목 영역만 스크롤됩니다.
final class ActionSheetView: UIView, ActionSheetLike {
    let scrimView = UIView()
    let cardView = UIView()
    private let headerStack = UIStackView()
    let titleLabel = UILabel()
    let messageLabel = UILabel()
    private let scrollView = UIScrollView()
    private let buttonStack = UIStackView()
    private let items: [ActionSheetItem]
    private let select: @MainActor (ActionSheetItem) -> Void
    private let cancel: @MainActor () -> Void

    init(
        title: String,
        message: String,
        items: [ActionSheetItem],
        select: @escaping @MainActor (ActionSheetItem) -> Void,
        cancel: @escaping @MainActor () -> Void
    ) {
        self.items = items
        self.select = select
        self.cancel = cancel
        super.init(frame: .zero)
        configureAppearance(
            title: title,
            message: message
        )
        makeHierarchy()
        makeLayout()
        bindActions()
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) is unavailable")
    }

    private func configureAppearance(
        title: String,
        message: String
    ) {
        scrimView.backgroundColor = UIColor(resource: .homeShadow)

        cardView.backgroundColor = UIColor(resource: .homeCard)
        cardView.layer.cornerRadius = 32
        cardView.layer.cornerCurve = .continuous

        headerStack.axis = .vertical
        headerStack.spacing = 6

        titleLabel.text = title
        titleLabel.font = .systemFont(ofSize: 20, weight: .bold)
        titleLabel.textColor = UIColor(resource: .homePrimaryText)
        titleLabel.textAlignment = .left
        titleLabel.numberOfLines = 0

        messageLabel.text = message
        messageLabel.font = .systemFont(ofSize: 15, weight: .regular)
        messageLabel.textColor = UIColor(resource: .homeSecondaryText)
        messageLabel.textAlignment = .left
        messageLabel.numberOfLines = 4

        scrollView.alwaysBounceVertical = false
        scrollView.showsVerticalScrollIndicator = false

        buttonStack.axis = .vertical
        buttonStack.spacing = 10
    }

    private func makeHierarchy() {
        addSubview(scrimView)
        addSubview(cardView)
        cardView.addSubview(headerStack)
        cardView.addSubview(scrollView)
        headerStack.addArrangedSubview(titleLabel)
        headerStack.addArrangedSubview(messageLabel)
        scrollView.addSubview(buttonStack)
        for item in items {
            let button = ActionSheetButton(
                title: item.title,
                role: item.role
            )
            buttonStack.addArrangedSubview(button)
        }
    }

    private func makeLayout() {
        scrimView.translatesAutoresizingMaskIntoConstraints = false
        cardView.translatesAutoresizingMaskIntoConstraints = false
        headerStack.translatesAutoresizingMaskIntoConstraints = false
        scrollView.translatesAutoresizingMaskIntoConstraints = false
        buttonStack.translatesAutoresizingMaskIntoConstraints = false

        // 항목이 많거나 글자가 커서 카드가 넘치면 이 높이 제약이 먼저 깨지고 스크롤됩니다.
        // 헤더의 압축 저항(750)보다 낮아야 헤더가 잘리지 않습니다.
        let scrollHeight = scrollView.heightAnchor.constraint(equalTo: scrollView.contentLayoutGuide.heightAnchor)
        scrollHeight.priority = UILayoutPriority(749)

        NSLayoutConstraint.activate([
            scrimView.topAnchor.constraint(equalTo: topAnchor),
            scrimView.bottomAnchor.constraint(equalTo: bottomAnchor),
            scrimView.leadingAnchor.constraint(equalTo: leadingAnchor),
            scrimView.trailingAnchor.constraint(equalTo: trailingAnchor),
            cardView.leadingAnchor.constraint(equalTo: safeAreaLayoutGuide.leadingAnchor, constant: 32),
            cardView.trailingAnchor.constraint(equalTo: safeAreaLayoutGuide.trailingAnchor, constant: -32),
            cardView.centerYAnchor.constraint(equalTo: safeAreaLayoutGuide.centerYAnchor),
            cardView.topAnchor.constraint(greaterThanOrEqualTo: safeAreaLayoutGuide.topAnchor, constant: 12),
            cardView.bottomAnchor.constraint(lessThanOrEqualTo: safeAreaLayoutGuide.bottomAnchor, constant: -12),
            headerStack.topAnchor.constraint(equalTo: cardView.topAnchor, constant: 28),
            headerStack.leadingAnchor.constraint(equalTo: cardView.leadingAnchor, constant: 24),
            headerStack.trailingAnchor.constraint(equalTo: cardView.trailingAnchor, constant: -24),
            scrollView.topAnchor.constraint(equalTo: headerStack.bottomAnchor),
            scrollView.leadingAnchor.constraint(equalTo: cardView.leadingAnchor),
            scrollView.trailingAnchor.constraint(equalTo: cardView.trailingAnchor),
            scrollView.bottomAnchor.constraint(equalTo: cardView.bottomAnchor),
            scrollHeight,
            buttonStack.topAnchor.constraint(equalTo: scrollView.contentLayoutGuide.topAnchor, constant: 20),
            buttonStack.bottomAnchor.constraint(equalTo: scrollView.contentLayoutGuide.bottomAnchor, constant: -16),
            buttonStack.leadingAnchor.constraint(equalTo: scrollView.frameLayoutGuide.leadingAnchor, constant: 16),
            buttonStack.trailingAnchor.constraint(equalTo: scrollView.frameLayoutGuide.trailingAnchor, constant: -16)
        ])
    }

    private func bindActions() {
        for (button, item) in zip(buttonStack.arrangedSubviews.compactMap { $0 as? UIButton }, items) {
            button.addAction(UIAction { [select] _ in select(item) }, for: .touchUpInside)
        }
        scrimView.addGestureRecognizer(
            UITapGestureRecognizer(
                target: self,
                action: #selector(scrimTapped)
            )
        )
    }

    @objc private func scrimTapped() {
        cancel()
    }
}
