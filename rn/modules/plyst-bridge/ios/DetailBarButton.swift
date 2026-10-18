//
//  DetailBarButton.swift
//  PlystBridge
//
//  Created by opfic on 10/1/26.
//

import UIKit

/// 상세 화면 상단 바의 원형 아이콘 버튼과 캡슐형 텍스트 버튼입니다.
/// iOS 26 이상에서는 Liquid Glass를 씁니다. 그보다 낮은 버전에서는 테두리가 있는 평면 버튼으로 표시합니다.
/// 색은 앱 에셋 카탈로그의 이름을 문자열로 참조하므로 앱 타깃에 같은 이름의 색이 있어야 합니다.
@objc(DetailBarButton)
public final class DetailBarButton: UIButton {
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

    /// Objective-C++ 컴포넌트 뷰가 SF Symbol 이름으로 원형 아이콘 버튼을 만듭니다.
    @objc
    public convenience init(icon: String) {
        self.init(style: .icon(icon))
    }

    /// Objective-C++ 컴포넌트 뷰가 제목으로 캡슐형 텍스트 버튼을 만듭니다.
    @objc
    public convenience init(title: String) {
        self.init(style: .title(title))
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) is unavailable")
    }

    private static func baseConfiguration() -> UIButton.Configuration {
        if #available(iOS 26.0, *) { return .glass() }
        return .plain()
    }

    private static func color(_ name: String) -> UIColor {
        return UIColor(named: name) ?? .label
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
            let color = Self.color(button.isEnabled ? "HomePrimaryText" : "HomePlaceholder")
            configuration.baseForegroundColor = color
            if !Self.usesGlass {
                configuration.background.strokeWidth = 1
                configuration.background.backgroundColor = Self.color("HomeCard")
                configuration.background.strokeColor = Self.color("HomeOutline")
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
