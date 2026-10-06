//
//  HomeCopyButton.swift
//  Plyst
//
//  Created by opfic on 9/30/26.
//

import UIKit

/// 카드의 메타데이터 행 오른쪽에 표시하는 복사 버튼입니다.
final class HomeCopyButton: UIButton {
    static let side = CGFloat(32)

    override init(frame: CGRect) {
        super.init(frame: frame)
        configureAppearance()
        makeLayout()
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) is unavailable")
    }

    private func configureAppearance() {
        var configuration = UIButton.Configuration.plain()
        configuration.image = UIImage(
            systemName: "doc.on.doc",
            withConfiguration: UIImage.SymbolConfiguration(pointSize: 13, weight: .semibold)
        )
        configuration.baseForegroundColor = UIColor(resource: .homePrimaryText)
        configuration.background.backgroundColor = UIColor(resource: .homeImageBackground)
        configuration.background.cornerRadius = 10
        configuration.cornerStyle = .fixed
        self.configuration = configuration
    }

    private func makeLayout() {
        translatesAutoresizingMaskIntoConstraints = false
        NSLayoutConstraint.activate([
            widthAnchor.constraint(equalToConstant: Self.side),
            heightAnchor.constraint(equalToConstant: Self.side)
        ])
    }
}
