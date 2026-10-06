//
//  HomeEmptyStateView.swift
//  Plyst
//
//  Created by opfic on 9/30/26.
//

import UIKit

@MainActor
final class HomeEmptyStateView: UIStackView, HomeEmptyStateLike {
    let emptyTitle = UILabel()
    let emptyBody = UILabel()

    override init(frame: CGRect) {
        super.init(frame: frame)
        configureAppearance()
        makeHierarchy()
    }

    @available(*, unavailable)
    required init(coder: NSCoder) {
        fatalError("init(coder:) is unavailable")
    }

    func configure(
        title: String,
        message: String
    ) {
        let titleParagraph = NSMutableParagraphStyle()
        titleParagraph.alignment = .center
        titleParagraph.lineBreakStrategy = [.hangulWordPriority, .pushOut]
        emptyTitle.attributedText = NSAttributedString(
            string: title,
            attributes: [
                .font: UIFont.systemFont(ofSize: 21, weight: .bold),
                .foregroundColor: UIColor(resource: .homePrimaryText),
                .kern: -0.315,
                .paragraphStyle: titleParagraph
            ]
        )
        let bodyParagraph = NSMutableParagraphStyle()
        bodyParagraph.alignment = .center
        bodyParagraph.minimumLineHeight = 24
        bodyParagraph.maximumLineHeight = 24
        // 한글은 어절 단위로 줄바꿈하고, 마지막 줄에 한 어절만 남지 않도록 앞줄에서 밀어낸다.
        bodyParagraph.lineBreakStrategy = [.hangulWordPriority, .pushOut]
        emptyBody.attributedText = NSAttributedString(
            string: message,
            attributes: [
                .font: UIFont.systemFont(ofSize: 15),
                .foregroundColor: UIColor(resource: .homeSecondaryText),
                .paragraphStyle: bodyParagraph
            ]
        )
    }

    private func configureAppearance() {
        axis = .vertical
        alignment = .center
        spacing = 10
        isHidden = true

        emptyTitle.numberOfLines = 0
        emptyBody.numberOfLines = 0
    }

    private func makeHierarchy() {
        addArrangedSubview(emptyTitle)
        addArrangedSubview(emptyBody)
    }
}
