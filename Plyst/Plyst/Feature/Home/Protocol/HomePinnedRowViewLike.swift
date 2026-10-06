//
//  HomePinnedRowViewLike.swift
//  Plyst
//
//  Created by opfic on 10/1/26.
//

import UIKit

@MainActor
protocol HomePinnedRowViewLike: UICollectionReusableView, ReuseIdentifiable {
    static var height: CGFloat { get }
    static var thumbnailDimension: CGFloat { get }

    func configure(
        clips: [Clip],
        now: Date,
        key: (Clip) -> HomeThumbnailKey?,
        thumbnail: (HomeThumbnailKey) -> HomeThumbnailPhase,
        send: @escaping @MainActor (HomePinnedRowViewAction) -> Void
    )

    func visibleClips() -> [Clip]
}
