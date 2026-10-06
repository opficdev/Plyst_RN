//
//  HomeFilterBarView.swift
//  Plyst
//
//  Created by opfic on 9/30/26.
//

import UIKit

final class HomeFilterBarView: UIView {
    private let scrollView = UIScrollView()
    private let stack = UIStackView()
    private var buttons = [HomeFilter: UIButton]()
    private let send: @MainActor (HomeFilterBarViewAction) -> Void

    init(send: @escaping @MainActor (HomeFilterBarViewAction) -> Void) {
        self.send = send
        super.init(frame: .zero)
        configureAppearance()
        makeButtons()
        makeHierarchy()
        makeLayout()
        setSelectedFilter(.all)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) is unavailable")
    }

    func setSelectedFilter(_ filter: HomeFilter) {
        for (candidate, button) in buttons {
            var configuration = UIButton.Configuration.plain()
            var title = AttributedString(candidate.title)
            title.font = .systemFont(ofSize: 13, weight: .semibold)
            configuration.attributedTitle = title
            configuration.contentInsets = NSDirectionalEdgeInsets(
                top: 8,
                leading: 14,
                bottom: 8,
                trailing: 14
            )
            configuration.cornerStyle = .capsule
            if candidate == filter {
                configuration.baseForegroundColor = UIColor(resource: .homeBottomText)
                configuration.background.backgroundColor = UIColor(resource: .homeBottomBar)
            } else {
                configuration.baseForegroundColor = UIColor(resource: .homePrimaryText)
                configuration.background.backgroundColor = UIColor(resource: .homeCard)
                configuration.background.strokeColor = UIColor(resource: .homeOutline)
                configuration.background.strokeWidth = 1
            }
            button.configuration = configuration
        }
    }

    private func configureAppearance() {
        scrollView.showsHorizontalScrollIndicator = false
        scrollView.alwaysBounceHorizontal = true
        stack.axis = .horizontal
        stack.spacing = 8
    }

    private func makeButtons() {
        for filter in HomeFilter.allCases {
            let button = UIButton(type: .system)
            button.addAction(UIAction { [weak self] _ in
                self?.send(.select(filter))
            }, for: .touchUpInside)
            buttons[filter] = button
            stack.addArrangedSubview(button)
        }
    }

    private func makeHierarchy() {
        addSubview(scrollView)
        scrollView.addSubview(stack)
    }

    private func makeLayout() {
        scrollView.translatesAutoresizingMaskIntoConstraints = false
        stack.translatesAutoresizingMaskIntoConstraints = false

        NSLayoutConstraint.activate([
            scrollView.topAnchor.constraint(equalTo: topAnchor),
            scrollView.leadingAnchor.constraint(equalTo: leadingAnchor),
            scrollView.trailingAnchor.constraint(equalTo: trailingAnchor),
            scrollView.bottomAnchor.constraint(equalTo: bottomAnchor),
            stack.topAnchor.constraint(equalTo: scrollView.topAnchor),
            stack.bottomAnchor.constraint(equalTo: scrollView.bottomAnchor),
            stack.leadingAnchor.constraint(equalTo: scrollView.leadingAnchor, constant: 20),
            stack.trailingAnchor.constraint(equalTo: scrollView.trailingAnchor, constant: -20),
            stack.heightAnchor.constraint(equalTo: scrollView.heightAnchor)
        ])
    }
}
