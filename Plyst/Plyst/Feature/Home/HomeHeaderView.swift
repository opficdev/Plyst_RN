//
//  HomeHeaderView.swift
//  Plyst
//
//  Created by opfic on 9/30/26.
//

import UIKit

final class HomeSectionHeaderView: UICollectionReusableView, HomeSectionHeaderViewLike, SectionTitleLike {
    let title = UILabel()
    let rule = UIView()

    override init(frame: CGRect) {
        super.init(frame: frame)
        configureAppearance()
        makeHierarchy()
        makeLayout()
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) is unavailable")
    }

    func configure(title: String) {
        self.title.attributedText = NSAttributedString(
            string: title,
            attributes: [
                .font: UIFont.monospacedSystemFont(ofSize: 11, weight: .semibold),
                .foregroundColor: UIColor(resource: .homeSecondaryText),
                .kern: 0.88
            ]
        )
    }

    private func configureAppearance() {
        rule.backgroundColor = UIColor(resource: .homeOutline)
    }

    private func makeHierarchy() {
        addSubview(title)
        addSubview(rule)
    }

    private func makeLayout() {
        title.translatesAutoresizingMaskIntoConstraints = false
        rule.translatesAutoresizingMaskIntoConstraints = false

        NSLayoutConstraint.activate([
            title.topAnchor.constraint(equalTo: topAnchor, constant: 20),
            title.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 20),
            rule.centerYAnchor.constraint(equalTo: title.centerYAnchor),
            rule.leadingAnchor.constraint(equalTo: title.trailingAnchor, constant: 10),
            rule.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -20),
            rule.heightAnchor.constraint(equalToConstant: 1)
        ])
    }
}
