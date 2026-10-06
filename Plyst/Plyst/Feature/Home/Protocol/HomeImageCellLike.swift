//
//  HomeImageCellLike.swift
//  Plyst
//
//  Created by opfic on 10/1/26.
//

import UIKit

@MainActor
protocol HomeImageCellLike: UICollectionViewCell, ReuseIdentifiable {
    var representedKey: HomeThumbnailKey? { get }

    // 프로토콜 요구사항에는 기본 인자를 둘 수 없어 구현체(기본 인자 2개 제외 4개)와 달리 6개로 집계됩니다.
    // swiftlint:disable:next function_parameter_count
    func configure(
        with clip: Clip,
        now: Date,
        key: HomeThumbnailKey,
        thumbnail: HomeThumbnailPhase,
        name: NSAttributedString?,
        onCopy: (() -> Void)?
    )

    func setThumbnail(_ thumbnail: HomeThumbnailPhase)

    static func height(
        for clip: Clip,
        width: CGFloat,
        name: NSAttributedString?,
        showsCopy: Bool
    ) -> CGFloat
}
