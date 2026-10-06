//
//  HomeTextCellLike.swift
//  Plyst
//
//  Created by opfic on 10/1/26.
//

import UIKit

@MainActor
protocol HomeTextCellLike: UICollectionViewCell, ReuseIdentifiable {
    func configure(
        with clip: Clip,
        now: Date,
        name: NSAttributedString?,
        body: NSAttributedString?,
        onCopy: (() -> Void)?
    )

    static func height(
        for clip: Clip,
        width: CGFloat,
        name: NSAttributedString?,
        body: NSAttributedString?,
        showsCopy: Bool
    ) -> CGFloat
}
