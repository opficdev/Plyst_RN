//
//  DetailBarButton.swift
//  Plyst
//
//  Created by opfic on 10/1/26.
//

import UIKit

/// 상세 화면 상단 바의 원형 아이콘 버튼과 캡슐형 텍스트 버튼입니다.
/// iOS 26 이상에서는 Liquid Glass를 씁니다. 그보다 낮은 버전에서는 테두리가 있는 평면 버튼으로 표시합니다.
final class DetailBarButton: UIButton {
    enum Style {
        case icon(String)
        case title(String)
    }

    private static var usesGlass: Bool {
        if #available(iOS 26.0, *) { return true }
        return false
    }

    private let style: Style

    init(style: Style) {
        self.style = style
        super.init(frame: .zero)
        configureAppearance()
        makeLayout()
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) is unavailable")
    }

    private static func baseConfiguration() -> UIButton.Configuration {
        if #available(iOS 26.0, *) { return .glass() }
        return .plain()
    }

    private func configureAppearance() {
        var configuration = Self.baseConfiguration()
        configuration.cornerStyle = .capsule
        switch style {
        case .icon(let name):
            configuration.image = UIImage(
                systemName: name,
                withConfiguration: UIImage.SymbolConfiguration(pointSize: 15, weight: .semibold)
            )
        case .title(let title):
            var text = AttributedString(title)
            text.font = .systemFont(ofSize: 15, weight: .semibold)
            configuration.attributedTitle = text
            configuration.contentInsets = NSDirectionalEdgeInsets(
                top: 0,
                leading: 16,
                bottom: 0,
                trailing: 16
            )
        }
        self.configuration = configuration

        configurationUpdateHandler = { button in
            guard var configuration = button.configuration else { return }
            let color = UIColor(resource: button.isEnabled ? .homePrimaryText : .homePlaceholder)
            configuration.baseForegroundColor = color
            if !Self.usesGlass {
                configuration.background.strokeWidth = 1
                configuration.background.backgroundColor = UIColor(resource: .homeCard)
                configuration.background.strokeColor = UIColor(resource: .homeOutline)
            }
            button.configuration = configuration
        }
    }

    private func makeLayout() {
        translatesAutoresizingMaskIntoConstraints = false
        let side = CGFloat(Self.usesGlass ? 44 : 40)
        if case .icon = style {
            widthAnchor.constraint(equalToConstant: side).isActive = true
        }
        heightAnchor.constraint(equalToConstant: side).isActive = true
    }
}
