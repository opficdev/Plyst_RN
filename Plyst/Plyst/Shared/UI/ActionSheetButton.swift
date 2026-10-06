//
//  ActionSheetButton.swift
//  Plyst
//
//  Created by opfic on 10/2/26.
//

import UIKit

/// 공용 액션 시트의 알약 모양 항목 버튼입니다. 역할에 따라 글자색을 구분합니다.
final class ActionSheetButton: UIButton {
    private let itemRole: ActionSheetItem.Role

    init(
        title: String,
        role: ActionSheetItem.Role
    ) {
        itemRole = role
        super.init(frame: .zero)
        configureAppearance(title: title)
        makeLayout()
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) is unavailable")
    }

    private func configureAppearance(title: String) {
        var configuration = UIButton.Configuration.plain()
        var text = AttributedString(title)
        text.font = .systemFont(ofSize: 17, weight: .semibold)
        configuration.attributedTitle = text
        configuration.cornerStyle = .capsule
        configuration.contentInsets = NSDirectionalEdgeInsets(
            top: 14,
            leading: 20,
            bottom: 14,
            trailing: 20
        )
        configuration.background.backgroundColor = UIColor(resource: .homeOutline)
        switch itemRole {
        case .default, .cancel:
            configuration.baseForegroundColor = UIColor(resource: .homePrimaryText)
        case .destructive:
            configuration.baseForegroundColor = UIColor(resource: .homeFeedbackFailure)
        }
        self.configuration = configuration

        configurationUpdateHandler = { button in
            button.alpha = button.isHighlighted ? 0.6 : 1
        }
    }

    private func makeLayout() {
        translatesAutoresizingMaskIntoConstraints = false
        heightAnchor.constraint(greaterThanOrEqualToConstant: 52).isActive = true
    }
}
